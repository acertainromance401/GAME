/*
 SoundManager.swift

 파일 설명:
 - 프로시저럴 사운드 합성 및 재생을 담당합니다. 임팩트, 벨, 휘핑 사운드, 라운드 결과 스팅어 등
     모든 효과가 런타임에 버퍼로 생성되어 재생됩니다(번들 오디오 자원 사용 없음).

 구현/주의사항:
 - 내부적으로 `AVAudioEngine`과 `AVAudioPlayerNode`를 사용해 버퍼를 생성·캐시하고, 필요 시 재생합니다.
 - 샘플 생성 과정에는 사인/화이트노이즈/엔벨로프/필터 단계가 포함되어 있으며, 성능 상 초기화 비용이 있습니다.
 - 사운드 파라미터(주파수, 길이, 에너지 등)를 변경하면 청각적 피드백이 즉시 달라지므로 밸런스 테스트가 필요합니다.

 사용 영향:
 - 이 파일의 변경은 게임의 모든 오디오 피드백에 영향을 줍니다. 런타임 사운드 동작을 바꾸려면
     실제 장비에서 확인하세요. 주석 추가만으로는 동작에 영향이 없습니다.
*/
import AVFAudio
import AudioToolbox
/// session can't be started (e.g. a constrained host environment) every call below silently no-ops so the
/// game stays fully playable without sound.
@MainActor
final class SoundManager {
    enum Cutscene {
        case introduction(StoryOpponent, short: Bool)
        case aftermath(StoryOpponent)
        case opening
    }

    private enum CutsceneEffect {
        case step, cloth, gloveTouch, bagHit, air, cheer, award, tension
    }

    private enum CutsceneAmbience: Hashable {
        case crowd, gym
    }

    private enum Venue: Equatable {
        case arena, gym, outboxer, counter, slugger, championship

        init(opponent: StoryOpponent?) {
            switch opponent {
            case .pressure: self = .gym
            case .outboxer: self = .outboxer
            case .counter: self = .counter
            case .slugger: self = .slugger
            case .rival: self = .championship
            case nil: self = .arena
            }
        }
    }

    private struct CutsceneCue {
        let time: Double
        let effect: CutsceneEffect
        let volume: Float
        let pan: Float

        init(_ time: Double, _ effect: CutsceneEffect, volume: Float = 0.4, pan: Float = 0) {
            self.time = time
            self.effect = effect
            self.volume = volume
            self.pan = pan
        }
    }

    private let engine = AVAudioEngine()
    private let effectMixer = AVAudioMixerNode()
    private let ambienceMixer = AVAudioMixerNode()
    private let outputMixer = AVAudioMixerNode()
    private let effectEQ = AVAudioUnitEQ(numberOfBands: 3)
    private let ambienceEQ = AVAudioUnitEQ(numberOfBands: 2)
    private let effectReverb = AVAudioUnitReverb()
    private let ambienceReverb = AVAudioUnitReverb()
    private let peakLimiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))
    private let battleVenue: Venue
    private var activeVenue: Venue?
    private var effectPlayers: [AVAudioPlayerNode] = []
    private var nextEffectPlayerIndex = 0
    // Swing cues cannot steal a voice from a landed hit, KO or round-result sound.
    private var swingPlayers: [AVAudioPlayerNode] = []
    private var nextSwingPlayerIndex = 0
    private var lightSwingBuffers: [AVAudioPCMBuffer] = []
    private var heavySwingBuffers: [AVAudioPCMBuffer] = []
    private let ambiencePlayer = AVAudioPlayerNode()
    private var audiencePlayers: [AVAudioPlayerNode] = []
    private var nextAudiencePlayerIndex = 0
    private var battleAmbienceActive = false
    private var audienceExcitement: Float = 0
    private var audienceReactionCooldown = 0.0
    private var ambienceDuckRemaining = 0.0
    private var ambienceDuckGain: Float = 1
    private var cutscenePlayers: [AVAudioPlayerNode] = []
    private var nextCutscenePlayerIndex = 0
    private var cutscene: Cutscene?
    private var cutsceneCues: [CutsceneCue] = []
    private var nextCutsceneCueIndex = 0
    private var cutsceneElapsed = 0.0
    private var cutsceneSuspended = false
    private var cutsceneInterrupted = false
    private var currentAmbience: CutsceneAmbience?
    private var ambienceBuffers: [CutsceneAmbience: AVAudioPCMBuffer] = [:]
    private lazy var stepBuffer = Self.makeCutsceneStepBuffer(sampleRate: sampleRate)
    private lazy var clothBuffer = Self.makeClothBuffer(sampleRate: sampleRate)
    private lazy var cheerBuffer = Self.makeCheerBuffer(sampleRate: sampleRate)
    private lazy var awardBuffer = Self.makeCutsceneChordBuffer(victory: true, sampleRate: sampleRate)
    private lazy var tensionBuffer = Self.makeCutsceneChordBuffer(victory: false, sampleRate: sampleRate)

    /// Mutes all game audio effects without tearing down the engine, so it can be toggled instantly from
    /// a settings switch.
    var isMuted = false {
        didSet { engine.mainMixerNode.outputVolume = isMuted ? 0 : 1 }
    }

    private let sampleRate: Double = 44_100
    private var lightHitBuffer: AVAudioPCMBuffer?
    private var heavyHitBuffer: AVAudioPCMBuffer?
    private var bodyHitBuffer: AVAudioPCMBuffer?
    private var hookHitBuffer: AVAudioPCMBuffer?
    private var uppercutHitBuffer: AVAudioPCMBuffer?
    private var guardBuffer: AVAudioPCMBuffer?
    private var duckBuffer: AVAudioPCMBuffer?
    private var bellBuffer: AVAudioPCMBuffer?
    private var koBuffer: AVAudioPCMBuffer?
    private var whiffBuffer: AVAudioPCMBuffer?
    private var backstepBuffer: AVAudioPCMBuffer?
    private var guardBreakBuffer: AVAudioPCMBuffer?
    private var exhaustedBuffer: AVAudioPCMBuffer?
    private var tickBuffer: AVAudioPCMBuffer?
    private var victoryBuffer: AVAudioPCMBuffer?
    private var defeatBuffer: AVAudioPCMBuffer?
    private var drawBuffer: AVAudioPCMBuffer?

    init(opponent: StoryOpponent? = nil) {
        battleVenue = Venue(opponent: opponent)
        buildBuffers()
        ambienceBuffers[.crowd] = Self.makeAmbienceBuffer(crowd: true, sampleRate: sampleRate)
        ambienceBuffers[.gym] = Self.makeAmbienceBuffer(crowd: false, sampleRate: sampleRate)
        _ = cheerBuffer
        buildGraph()
        applyVenue(battleVenue)
        configureSession()
        startEngine()
    }

    // MARK: Public game events

    /// A quiet air rush on actual extension, whether the punch later hits or misses.
    /// Pick a prebuilt variation; no synthesis or delayed task runs on the attack frame.
    func playPunchSwing(_ punch: Punch, pan: Float = 0) {
        guard !isMuted, engine.isRunning, !swingPlayers.isEmpty else { return }
        let light = punch == .jab
        guard let buffer = (light ? lightSwingBuffers : heavySwingBuffers).randomElement() else { return }
        let player = swingPlayers[nextSwingPlayerIndex]
        nextSwingPlayerIndex = (nextSwingPlayerIndex + 1) % swingPlayers.count
        let volume: Float = (light ? 0.36 : 0.43) * Float.random(in: 0.94...1.0)
        playBuffer(buffer, on: player, volume: volume, pan: pan)
    }

    func playImpact(_ impact: CombatImpact, pan: Float = 0) {
        guard !isMuted, engine.isRunning else { return }
        let feedback = ImpactFeedback.sample(impact)
        let buffer: AVAudioPCMBuffer?
        switch feedback.texture {
        case .jab: buffer = lightHitBuffer
        case .cross: buffer = heavyHitBuffer
        case .body: buffer = bodyHitBuffer
        case .hook: buffer = hookHitBuffer
        case .uppercut: buffer = uppercutHitBuffer
        case .blocked: buffer = guardBuffer
        case .guardBreak: buffer = guardBreakBuffer
        case .knockout: buffer = koBuffer
        }
        playEffect(buffer, volume: feedback.volume, pan: pan)
        duckAmbience(duration: 0.20, gain: 0.64)
        guard cutscene == nil, battleAmbienceActive else { return }
        switch feedback.texture {
        case .knockout:
            audienceExcitement = 1
            playAudienceReaction(volume: 0.46, force: true)
            duckAmbience(duration: 0.45, gain: 0.48)
        case .guardBreak:
            audienceExcitement = max(audienceExcitement, 0.65)
            playAudienceReaction(volume: 0.25)
        case .cross, .hook, .uppercut:
            audienceExcitement = min(1, audienceExcitement + 0.22)
        default: break
        }
    }

    func playDuckEvade(pan: Float = 0) {
        playEffect(duckBuffer, volume: 0.55, pan: pan)
    }

    func playRoundStart() {
        playEffect(bellBuffer, volume: 0.85)
        duckAmbience(duration: 0.40, gain: 0.56)
    }

    /// Rings the round-end bell and layers a distinct rising (win) / falling (loss) / neutral (draw)
    /// stinger on top, so the outcome is audible even without reading the HUD text.
    func playRoundResult(outcome: RoundOutcome, knockout: Bool) {
        playEffect(bellBuffer, volume: 0.55)
        let resultBuffer: AVAudioPCMBuffer?
        switch outcome {
        case .playerWin: resultBuffer = victoryBuffer
        case .playerLoss: resultBuffer = defeatBuffer
        case .draw: resultBuffer = drawBuffer
        }
        playEffect(resultBuffer, volume: knockout ? 1.0 : 0.85)
        duckAmbience(duration: 0.50, gain: 0.52)
        if outcome == .playerWin, !knockout, battleAmbienceActive {
            playAudienceReaction(volume: 0.34)
        }
    }

    /// A punch that missed entirely — a soft airy whoosh instead of the punchier impact textures, so a
    /// miss reads as clearly different from a landed (or blocked) hit.
    func playWhiff(pan: Float = 0) {
        playEffect(whiffBuffer, volume: 0.4, pan: pan)
    }

    func playBackstep(pan: Float = 0) {
        playEffect(backstepBuffer, volume: 0.55, pan: pan)
    }

    func playExhausted(pan: Float = 0) {
        playEffect(exhaustedBuffer, volume: 0.6, pan: pan)
    }

    /// A short tick for the final seconds of a round, to build urgency without relying on the HUD alone.
    func playCountdownTick() {
        playEffect(tickBuffer, volume: 0.55)
    }

    func updateMix(deltaTime: Double, battleActive: Bool, fighting: Bool) {
        guard deltaTime.isFinite, !cutsceneSuspended, !cutsceneInterrupted, engine.isRunning else { return }
        let elapsed = max(0, min(0.05, deltaTime))
        audienceReactionCooldown = max(0, audienceReactionCooldown - elapsed)
        audienceExcitement = max(0, audienceExcitement - Float(elapsed) * 0.13)
        ambienceDuckRemaining = max(0, ambienceDuckRemaining - elapsed)
        let targetGain: Float = ambienceDuckRemaining > 0 ? ambienceDuckGain : 1
        let response = targetGain < ambienceMixer.outputVolume ? 26.0 : 4.5
        let blend = Float(1 - exp(-elapsed * response))
        ambienceMixer.outputVolume += (targetGain - ambienceMixer.outputVolume) * blend
        guard cutscene == nil else { return }
        if battleActive {
            applyVenue(battleVenue)
            let baseline: Float = battleVenue == .championship ? 0.23 : battleVenue == .gym ? 0.12 : 0.17
            let volume = baseline * (fighting ? 1 : 0.82) + audienceExcitement * 0.08
            playAmbience(.crowd, volume: volume)
            battleAmbienceActive = true
        } else if battleAmbienceActive {
            stopBattleAudio()
        }
    }

    func stopBattleAudio() {
        for player in audiencePlayers { player.stop() }
        battleAmbienceActive = false
        audienceExcitement = 0
        audienceReactionCooldown = 0
        guard cutscene == nil else { return }
        ambiencePlayer.stop()
        currentAmbience = nil
        for player in effectPlayers + swingPlayers { player.stop() }
        effectReverb.reset()
        ambienceReverb.reset()
        ambienceDuckRemaining = 0
        ambienceDuckGain = 1
        ambienceMixer.outputVolume = 1
    }

    private func duckAmbience(duration: Double, gain: Float) {
        ambienceDuckGain = ambienceDuckRemaining > 0 ? min(ambienceDuckGain, gain) : gain
        ambienceDuckRemaining = max(ambienceDuckRemaining, duration)
    }

    private func playAudienceReaction(volume: Float, force: Bool = false) {
        guard !isMuted, engine.isRunning, !audiencePlayers.isEmpty,
              force || audienceReactionCooldown <= 0, let cheerBuffer else { return }
        let player = audiencePlayers[nextAudiencePlayerIndex]
        nextAudiencePlayerIndex = (nextAudiencePlayerIndex + 1) % audiencePlayers.count
        playBuffer(cheerBuffer, on: player, volume: volume, pan: Float.random(in: -0.25...0.25))
        audienceReactionCooldown = force ? 4.0 : 3.0
    }

    func beginCutscene(_ scene: Cutscene, clip: StoryIntroClip? = nil) {
        stopCutscene()
        cutscene = scene
        cutsceneCues = cues(for: scene)
        if let clip {
            if case .introduction(_, short: true) = scene {
                cutsceneCues.removeAll()
            } else {
                let footsteps = footstepCues(in: clip)
                if case .aftermath(.rival) = scene {
                    cutsceneCues += footsteps.filter { $0.time < ChampionshipEndingTiming.gymCut }
                } else {
                    cutsceneCues += footsteps
                }
                if case .introduction(.slugger, short: false) = scene,
                   let contact = clip.frames.filter({ $0.time >= 4.5 && $0.time < 6.3 }).min(by: {
                       gloveGapSquared(in: $0) < gloveGapSquared(in: $1)
                   }) {
                    cutsceneCues.append(CutsceneCue(contact.time, .gloveTouch, volume: 0.30))
                }
            }
        }
        cutsceneCues.sort { $0.time < $1.time }
        _ = stepBuffer
        _ = clothBuffer
        _ = cheerBuffer
        _ = awardBuffer
        _ = tensionBuffer
        updateCutscene(elapsed: 0)
    }

    func updateCutscene(elapsed: Double) {
        guard let cutscene, !cutsceneSuspended, !cutsceneInterrupted, elapsed.isFinite else { return }
        cutsceneElapsed = max(0, elapsed)
        let ambience: CutsceneAmbience
        let volume: Float
        switch cutscene {
        case .aftermath(.pressure):
            ambience = cutsceneElapsed < 3.2 ? .crowd : .gym
            volume = cutsceneElapsed < 3.2 ? 0.23 : 0.20
        case .aftermath(.rival):
            ambience = cutsceneElapsed >= ChampionshipEndingTiming.gymCut ? .gym : .crowd
            volume = ambience == .gym ? 0.18
                : cutsceneElapsed >= ChampionshipEndingTiming.ceremonyStart ? 0.36 : 0.22
        case .aftermath:
            ambience = .gym
            volume = 0.20
        case .introduction(.pressure, _):
            ambience = .crowd
            volume = 0.14
        case .introduction(.rival, _):
            ambience = .crowd
            volume = 0.30
        case .introduction, .opening:
            ambience = .crowd
            volume = 0.21
        }
        applyVenue(ambience == .gym ? .gym : battleVenue)
        playAmbience(ambience, volume: volume)
        while nextCutsceneCueIndex < cutsceneCues.count,
              cutsceneCues[nextCutsceneCueIndex].time <= cutsceneElapsed {
            let cue = cutsceneCues[nextCutsceneCueIndex]
            nextCutsceneCueIndex += 1
            if cutsceneElapsed - cue.time <= 0.20 { playCutsceneCue(cue) }
        }
    }

    func setCutsceneSuspended(_ suspended: Bool) {
        cutsceneSuspended = suspended
        if suspended {
            outputMixer.outputVolume = 0
            ambiencePlayer.pause()
            for player in effectPlayers + swingPlayers + cutscenePlayers + audiencePlayers { player.stop() }
            effectReverb.reset()
            ambienceReverb.reset()
        } else if !cutsceneInterrupted {
            outputMixer.outputVolume = 0.88
            if cutscene != nil, engine.isRunning {
                updateCutscene(elapsed: cutsceneElapsed)
                ambiencePlayer.play()
            }
        }
    }

    func stopCutscene() {
        ambiencePlayer.stop()
        for player in cutscenePlayers + audiencePlayers { player.stop() }
        effectReverb.reset()
        ambienceReverb.reset()
        battleAmbienceActive = false
        audienceExcitement = 0
        audienceReactionCooldown = 0
        ambienceDuckRemaining = 0
        ambienceDuckGain = 1
        ambienceMixer.outputVolume = 1
        cutscene = nil
        cutsceneCues.removeAll()
        nextCutsceneCueIndex = 0
        cutsceneElapsed = 0
        currentAmbience = nil
        cutsceneSuspended = false
    }

    private func playAmbience(_ ambience: CutsceneAmbience, volume: Float) {
        guard engine.isRunning else { return }
        ambiencePlayer.volume = volume
        guard currentAmbience != ambience else { return }
        if ambienceBuffers[ambience] == nil {
            ambienceBuffers[ambience] = Self.makeAmbienceBuffer(crowd: ambience == .crowd, sampleRate: sampleRate)
        }
        guard let buffer = ambienceBuffers[ambience] else { return }
        ambiencePlayer.stop()
        ambiencePlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        ambiencePlayer.play()
        currentAmbience = ambience
    }

    private func playCutsceneCue(_ cue: CutsceneCue) {
        guard !isMuted, engine.isRunning, !cutscenePlayers.isEmpty else { return }
        let buffer: AVAudioPCMBuffer?
        switch cue.effect {
        case .step: buffer = stepBuffer
        case .cloth: buffer = clothBuffer
        case .gloveTouch: buffer = guardBuffer
        case .bagHit: buffer = bodyHitBuffer
        case .air: buffer = heavySwingBuffers.first
        case .cheer: buffer = cheerBuffer
        case .award: buffer = awardBuffer
        case .tension: buffer = tensionBuffer
        }
        guard let buffer else { return }
        let player = cutscenePlayers[nextCutscenePlayerIndex]
        nextCutscenePlayerIndex = (nextCutscenePlayerIndex + 1) % cutscenePlayers.count
        playBuffer(buffer, on: player, volume: cue.volume, pan: cue.pan)
        switch cue.effect {
        case .award, .tension:
            duckAmbience(duration: 0.50, gain: 0.52)
        case .bagHit, .gloveTouch:
            duckAmbience(duration: 0.18, gain: 0.70)
        case .cheer:
            duckAmbience(duration: 0.35, gain: 0.76)
        default: break
        }
    }

    private func cues(for scene: Cutscene) -> [CutsceneCue] {
        switch scene {
        case .opening:
            return [CutsceneCue(0.08, .tension, volume: 0.28)]
        case .introduction(_, short: true):
            return []
        case .introduction(.rival, short: false):
            return [CutsceneCue(0.12, .tension, volume: 0.32),
                CutsceneCue(3.10, .cloth, volume: 0.40), CutsceneCue(4.35, .cloth, volume: 0.22)]
        case .introduction:
            return []
        case .aftermath(.pressure):
            return [CutsceneCue(0.10, .cheer, volume: 0.26),
                CutsceneCue(1.1, .gloveTouch, volume: 0.32),
                CutsceneCue(1.7, .gloveTouch, volume: 0.32),
                CutsceneCue(2.3, .gloveTouch, volume: 0.30)]
        case .aftermath(.outboxer):
            return [CutsceneCue(4.45, .cloth, volume: 0.22)]
        case .aftermath(.counter):
            return []
        case .aftermath(.slugger):
            return [CutsceneCue(2.26, .air, volume: 0.22), CutsceneCue(2.40, .bagHit, volume: 0.48),
                CutsceneCue(4.26, .air, volume: 0.24), CutsceneCue(4.40, .bagHit, volume: 0.51),
                CutsceneCue(6.26, .air, volume: 0.26), CutsceneCue(6.40, .bagHit, volume: 0.54),
                CutsceneCue(8.15, .tension, volume: 0.32)]
        case .aftermath(.rival):
            var cues = [CutsceneCue(5.4, .gloveTouch, volume: 0.36),
                CutsceneCue(ChampionshipEndingTiming.beltAward, .award, volume: 0.52),
                CutsceneCue(ChampionshipEndingTiming.ceremonyStart, .cheer, volume: 0.62),
                CutsceneCue(9.2, .cloth, volume: 0.22), CutsceneCue(9.32, .cloth, volume: 0.18),
                CutsceneCue(11.2, .cheer, volume: 0.66), CutsceneCue(13.7, .cloth, volume: 0.18),
                CutsceneCue(ChampionshipEndingTiming.gymCut + 0.2, .cloth, volume: 0.16),
                CutsceneCue(ChampionshipEndingTiming.gymCut + 4.06, .step, volume: 0.25)]
            for index in 0..<5 {
                let period = ChampionshipEndingTiming.applausePeriod(for: index)
                var time = ChampionshipEndingTiming.ceremonyStart + period * 0.5
                    - ChampionshipEndingTiming.applauseOffset(for: index)
                while time < ChampionshipEndingTiming.gymCut {
                    if time >= ChampionshipEndingTiming.ceremonyStart {
                        cues.append(CutsceneCue(time, .gloveTouch, volume: 0.12, pan: Float(index - 2) * 0.16))
                    }
                    time += period
                }
            }
            var coachClap = ChampionshipEndingTiming.ceremonyStart + ChampionshipEndingTiming.coachApplausePeriod * 0.5
            while coachClap < ChampionshipEndingTiming.gymCut {
                cues.append(CutsceneCue(coachClap, .gloveTouch, volume: 0.10, pan: 0.22))
                coachClap += ChampionshipEndingTiming.coachApplausePeriod
            }
            for beat in ChampionshipShadowboxingMotion.punches {
                guard let spec = CombatData.attacks[beat.punch] else { continue }
                let lead = [.jab, .leftBody, .leftHook, .leftUppercut].contains(beat.punch)
                cues.append(CutsceneCue(ChampionshipEndingTiming.gymCut + beat.start + spec.activeStart * 0.70,
                    .air, volume: spec.family == .straight ? 0.22 : 0.30, pan: lead ? -0.08 : 0.08))
            }
            return cues
        }
    }

    private func gloveGapSquared(in frame: StoryIntroFrame) -> Float {
        let deltaX = frame.pose.leftGlove.x - frame.pose.rightGlove.x
        let deltaY = frame.pose.leftGlove.y - frame.pose.rightGlove.y
        let deltaZ = frame.pose.leftGlove.z - frame.pose.rightGlove.z
        return deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ
    }

    private func footstepCues(in clip: StoryIntroClip) -> [CutsceneCue] {
        var cues: [CutsceneCue] = []
        for leftFoot in [true, false] {
            let floor = clip.frames.map { leftFoot ? $0.pose.leftFoot.y : $0.pose.rightFoot.y }.min() ?? 0
            var lifted = false
            for frame in clip.frames {
                let height = leftFoot ? frame.pose.leftFoot.y : frame.pose.rightFoot.y
                if height > floor + 0.012 {
                    lifted = true
                } else if lifted && height <= floor + 0.006 {
                    cues.append(CutsceneCue(frame.time, .step, volume: 0.42, pan: leftFoot ? -0.10 : 0.10))
                    lifted = false
                }
            }
        }
        return cues
    }

    // MARK: Engine plumbing

    private func configureSession() {
        // 오디오 세션 설정
        // - 카테고리: `.ambient`로 설정해 다른 앱 오디오와 믹스 가능하도록 함
        // - 활성화 실패는 예외 처리 없이 무시하여 사운드가 불가능한 환경에서도 게임이 동작하도록 보장
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: session
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        // 오디오 세션 인터럽트(전화, 알림 등) 처리
        // - 인터럽트가 끝나면 세션을 재활성화하고 엔진을 재시작하려 시도합니다.
        // - 실패는 무시하여 게임 플레이가 중단되지 않도록 합니다.
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            cutsceneInterrupted = true
            outputMixer.outputVolume = 0
            ambiencePlayer.pause()
            for player in effectPlayers + swingPlayers + cutscenePlayers + audiencePlayers { player.stop() }
            effectReverb.reset()
            ambienceReverb.reset()
        case .ended:
            cutsceneInterrupted = false
            try? AVAudioSession.sharedInstance().setActive(true)
            startEngine()
            currentAmbience = nil
            if !cutsceneSuspended {
                outputMixer.outputVolume = 0.88
                updateCutscene(elapsed: cutsceneElapsed)
            }
        @unknown default: break
        }
    }

    private func buildGraph() {
        // 플레이어 노드(다중)와 믹서 연결을 구성합니다.
        // - 여러 플레이어 노드를 순환 사용(interrupts)해 중복 효과를 자연스럽게 처리합니다.
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let processingNodes: [AVAudioNode] = [effectMixer, ambienceMixer, outputMixer,
            effectEQ, ambienceEQ, effectReverb, ambienceReverb, peakLimiter]
        for node in processingNodes { engine.attach(node) }
        engine.connect(effectMixer, to: effectEQ, format: stereoFormat)
        engine.connect(effectEQ, to: effectReverb, format: stereoFormat)
        engine.connect(effectReverb, to: outputMixer, format: stereoFormat)
        engine.connect(ambienceMixer, to: ambienceEQ, format: stereoFormat)
        engine.connect(ambienceEQ, to: ambienceReverb, format: stereoFormat)
        engine.connect(ambienceReverb, to: outputMixer, format: stereoFormat)
        engine.connect(outputMixer, to: peakLimiter, format: stereoFormat)
        engine.connect(peakLimiter, to: engine.mainMixerNode, format: stereoFormat)
        outputMixer.outputVolume = 0.88
        effectEQ.bands[0].filterType = .highPass
        effectEQ.bands[0].frequency = 48
        effectEQ.bands[1].filterType = .lowShelf
        effectEQ.bands[1].frequency = 160
        effectEQ.bands[2].filterType = .highShelf
        effectEQ.bands[2].frequency = 5_500
        ambienceEQ.bands[0].filterType = .highPass
        ambienceEQ.bands[0].frequency = 95
        ambienceEQ.bands[1].filterType = .lowPass
        for band in effectEQ.bands + ambienceEQ.bands { band.bypass = false }
        for _ in 0..<4 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: effectMixer, format: format)
            effectPlayers.append(node)
        }
        for _ in 0..<2 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: effectMixer, format: format)
            swingPlayers.append(node)
        }
        engine.attach(ambiencePlayer)
        engine.connect(ambiencePlayer, to: ambienceMixer, format: format)
        for _ in 0..<2 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: ambienceMixer, format: format)
            audiencePlayers.append(node)
        }
        for _ in 0..<4 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: effectMixer, format: format)
            cutscenePlayers.append(node)
        }
    }

    private func applyVenue(_ venue: Venue) {
        guard activeVenue != venue else { return }
        let preset: AVAudioUnitReverbPreset
        let wetMix: Float
        let bassGain: Float
        let presenceGain: Float
        let crowdCutoff: Float
        switch venue {
        case .gym:
            preset = .smallRoom
            wetMix = 6
            bassGain = 0.6
            presenceGain = -0.8
            crowdCutoff = 4_800
        case .outboxer:
            preset = .mediumRoom
            wetMix = 9
            bassGain = 0.3
            presenceGain = -1.0
            crowdCutoff = 5_800
        case .counter:
            preset = .mediumHall
            wetMix = 10
            bassGain = 0.2
            presenceGain = -0.6
            crowdCutoff = 6_200
        case .slugger:
            preset = .mediumChamber
            wetMix = 11
            bassGain = 1.2
            presenceGain = -2.0
            crowdCutoff = 5_000
        case .championship:
            preset = .largeHall
            wetMix = 16
            bassGain = 0.5
            presenceGain = -1.2
            crowdCutoff = 7_000
        case .arena:
            preset = .mediumHall
            wetMix = 12
            bassGain = 0.5
            presenceGain = -1.0
            crowdCutoff = 6_000
        }
        effectReverb.loadFactoryPreset(preset)
        ambienceReverb.loadFactoryPreset(preset)
        effectReverb.wetDryMix = wetMix
        ambienceReverb.wetDryMix = wetMix + 8
        effectEQ.bands[1].gain = bassGain
        effectEQ.bands[2].gain = presenceGain
        ambienceEQ.bands[1].frequency = crowdCutoff
        activeVenue = venue
    }

    private func startEngine() {
        // AVAudioEngine 시작. 이미 실행 중이면 무시.
        // - `engine.start()` 실패 시 예외를 흘려보내지 않고 조용히 반환하여 사운드 없이도 게임이 동작합니다.
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            return
        }
    }

    private func playEffect(_ buffer: AVAudioPCMBuffer?, volume: Float, pan: Float = 0) {
        // 실제 효과 재생 유틸리티
        // - `buffer`가 nil이거나 오디오 엔진이 실행 중이 아니면 조용히 반환합니다.
        // - 여러 플레이어 노드를 순환(round-robin) 사용해 동시 재생을 처리합니다.
        guard !isMuted, let buffer, engine.isRunning, !effectPlayers.isEmpty else { return }
        let player = effectPlayers[nextEffectPlayerIndex]
        nextEffectPlayerIndex = (nextEffectPlayerIndex + 1) % effectPlayers.count
        playBuffer(buffer, on: player, volume: volume, pan: pan)
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer, on player: AVAudioPlayerNode, volume: Float, pan: Float) {
        player.stop()
        player.volume = volume
        player.pan = max(-1, min(1, pan))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    // MARK: Buffer synthesis

    private func buildBuffers() {
        // 모든 효과용 PCM 버퍼를 생성해 캐싱합니다.
        // - 버퍼 생성을 통해 런타임 재생 시 오버헤드를 줄입니다(초기화 비용이 존재).
        lightHitBuffer = Self.makePunchBuffer(duration: 0.10, frequency: 185, body: false, sampleRate: sampleRate)
        heavyHitBuffer = Self.makePunchBuffer(duration: 0.15, frequency: 112, body: false, sampleRate: sampleRate)
        bodyHitBuffer = Self.makePunchBuffer(duration: 0.20, frequency: 78, body: true, sampleRate: sampleRate)
        hookHitBuffer = Self.makePunchBuffer(duration: 0.17, frequency: 98, body: false, sampleRate: sampleRate)
        uppercutHitBuffer = Self.makePunchBuffer(duration: 0.19, frequency: 86, body: false, sampleRate: sampleRate)
        guardBuffer = Self.makePunchBuffer(duration: 0.11, frequency: 160, body: true, sampleRate: sampleRate)
        duckBuffer = Self.makeBuffer(duration: 0.22, sampleRate: sampleRate) { time in
            let progress = time / 0.22
            let envelope = sin(.pi * progress)
            let noise = Double.random(in: -1...1)
            return Float(noise * envelope * 0.5)
        }
        bellBuffer = Self.makeBellBuffer(duration: 0.9, sampleRate: sampleRate)
        koBuffer = Self.makeImpactBuffer(duration: 0.5, sampleRate: sampleRate, baseFrequency: 60)
        whiffBuffer = Self.makeWhiffBuffer(sampleRate: sampleRate)
        backstepBuffer = Self.makeBackstepBuffer(sampleRate: sampleRate)
        guardBreakBuffer = Self.makeGuardBreakBuffer(sampleRate: sampleRate)
        exhaustedBuffer = Self.makeExhaustedBuffer(sampleRate: sampleRate)
        tickBuffer = Self.makeTickBuffer(sampleRate: sampleRate)
        victoryBuffer = Self.makeVictoryBuffer(sampleRate: sampleRate)
        defeatBuffer = Self.makeDefeatBuffer(sampleRate: sampleRate)
        drawBuffer = Self.makeDrawBuffer(sampleRate: sampleRate)
        lightSwingBuffers = [0.94, 1.0, 1.06].compactMap { variation in
            Self.makeSwingBuffer(duration: 0.075, brightness: 0.55 * variation, sampleRate: sampleRate)
        }
        heavySwingBuffers = [0.94, 1.0, 1.06].compactMap { variation in
            Self.makeSwingBuffer(duration: 0.11, brightness: 0.38 * variation, sampleRate: sampleRate)
        }
    }

    /// Filtered air only: no tonal thump or sharp impact transient that could imply a landed hit.
    private static func makeSwingBuffer(duration: Double, brightness: Double, sampleRate: Double) -> AVAudioPCMBuffer? {
        var filteredNoise = 0.0
        var lowNoise = 0.0
        return makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            let progress = min(1, time / duration)
            let envelope = sin(.pi * progress) * exp(-1.8 * progress)
            let noise = Double.random(in: -1...1)
            // A falling low-pass sweep with the bass removed keeps the sound short and breathy.
            filteredNoise += (noise - filteredNoise) * brightness * (1 - 0.55 * progress)
            lowNoise += (filteredNoise - lowNoise) * 0.045
            return Float((filteredNoise - lowNoise) * envelope * 0.8)
        }
    }

    /// A soft airy whoosh for a punch that missed entirely, filtered the same way as the crowd rumble so
    /// it reads as breathy air movement instead of a solid impact texture.
    private static func makeWhiffBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 0.16
        var noiseState = 0.0
        return makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            let progress = time / duration
            let envelope = sin(.pi * min(1, progress))
            let rawNoise = Double.random(in: -1...1)
            noiseState += (rawNoise - noiseState) * 0.5
            return Float(noiseState * envelope * 0.4)
        }
    }

    /// Two quick low thumps approximating a backward footwork shuffle.
    private static func makeBackstepBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 0.20
        let steps = [0.0, 0.09]
        return makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            var sample = 0.0
            for step in steps {
            let dt = time - step
                guard dt >= 0 else { continue }
                let decay = exp(-dt * 22)
                sample += sin(2 * .pi * 70 * dt) * decay
            }
            return Float(sample * 0.55)
        }
    }

    /// A sharper, more dramatic crack than the regular guarded-impact thud, marking the moment a guard
    /// actually collapses under stamina pressure.
    private static func makeGuardBreakBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 0.42
        return makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            let crackDecay = exp(-time * 30)
            let crackNoise = Double.random(in: -1...1) * crackDecay
            let ringDecay = exp(-time * 5)
            let ring = (sin(2 * .pi * 340 * time) * 0.5 + sin(2 * .pi * 512 * time) * 0.3) * ringDecay
            return Float((crackNoise * 0.7 + ring) * 0.85)
        }
    }

    /// A descending, deflating tone for a fighter gassing out.
    private static func makeExhaustedBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 0.55
        return makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            let progress = min(1, time / duration)
            let frequency = 220 * (1 - 0.65 * progress)
            let envelope = sin(.pi * progress)
            let tone = sin(2 * .pi * frequency * time)
            let breath = Double.random(in: -1...1) * 0.2
            return Float((tone * 0.6 + breath) * envelope * 0.6)
        }
    }

    /// A short beep for the final seconds of a round.
    private static func makeTickBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 0.09
        return makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            let decay = exp(-time * 40)
            return Float(sin(2 * .pi * 1046 * time) * decay * 0.7)
        }
    }

    /// A bright rising three-note chime for a round win.
    private static func makeVictoryBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let notes: [(Double, Double)] = [(0.0, 523.25), (0.12, 659.25), (0.24, 783.99)]
        return makeBuffer(duration: 0.6, sampleRate: sampleRate) { time in
            var sample = 0.0
            for (start, frequency) in notes {
            let dt = time - start
                guard dt >= 0 else { continue }
                sample += sin(2 * .pi * frequency * dt) * exp(-dt * 4.5)
            }
            return Float(sample * 0.35)
        }
    }

    /// A falling three-note stinger for a round loss.
    private static func makeDefeatBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let notes: [(Double, Double)] = [(0.0, 392.00), (0.16, 349.23), (0.32, 261.63)]
        return makeBuffer(duration: 0.7, sampleRate: sampleRate) { time in
            var sample = 0.0
            for (start, frequency) in notes {
            let dt = time - start
                guard dt >= 0 else { continue }
                sample += sin(2 * .pi * frequency * dt) * exp(-dt * 3.2)
            }
            return Float(sample * 0.32)
        }
    }

    /// A flat, neutral double-tone for a draw.
    private static func makeDrawBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        makeBuffer(duration: 0.5, sampleRate: sampleRate) { time in
            let decay = exp(-time * 5)
            let tone = sin(2 * .pi * 440 * time) * 0.5 + sin(2 * .pi * 660 * time) * 0.2
            return Float(tone * decay * 0.4)
        }
    }

    private static func makeImpactBuffer(duration: Double, sampleRate: Double, baseFrequency: Double) -> AVAudioPCMBuffer? {
        makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            let decay = exp(-time * 9.0)
            let tone = sin(2 * .pi * baseFrequency * time) * decay
            let noise = Double.random(in: -1...1) * decay * 0.5
            return Float((tone * 0.75 + noise) * 0.9)
        }
    }

    /// A brief glove crack plus a falling low thump. Body/blocked hits use a filtered, duller texture.
    /// Buffers are synthesized once, not on the hit frame; no delayed playback tasks or extra audio nodes.
    private static func makePunchBuffer(duration: Double, frequency: Double, body: Bool, sampleRate: Double) -> AVAudioPCMBuffer? {
        var filteredNoise = 0.0
        return makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            let noise = Double.random(in: -1...1)
            filteredNoise += (noise - filteredNoise) * (body ? 0.12 : 0.55)
            let attack = min(1, time / 0.0015)
            let release = min(1, max(0, (duration - time) / 0.015))
            let phase = 2 * Double.pi * frequency * (0.58 * time + 0.42 * (1 - exp(-28 * time)) / 28)
            let thump = sin(phase) * exp(-time * (body ? 22 : 32)) * 0.64
            let crack = noise * exp(-time * 110) * (body ? 0.10 : 0.38)
            let texture = filteredNoise * exp(-time * 34) * (body ? 0.42 : 0.24)
            return Float((thump + crack + texture) * attack * release * 0.85)
        }
    }

    private static func makeBellBuffer(duration: Double, sampleRate: Double) -> AVAudioPCMBuffer? {
        let strikeTimes = [0.0, 0.42]
        return makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            var sample = 0.0
            for strike in strikeTimes {
                let dt = time - strike
                guard dt >= 0 else { continue }
                let decay = exp(-dt * 3.2)
                let tone = sin(2 * .pi * 880 * dt) * 0.5 + sin(2 * .pi * 1320 * dt) * 0.3 + sin(2 * .pi * 660 * dt) * 0.2
                sample += tone * decay
            }
            return Float(sample * 0.6)
        }
    }

    private static func makeCutsceneStepBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        var filteredNoise = 0.0
        return makeBuffer(duration: 0.17, sampleRate: sampleRate) { time in
            filteredNoise += (Double.random(in: -1...1) - filteredNoise) * 0.18
            let attack = min(1, time / 0.003)
            let release = min(1, max(0, (0.17 - time) / 0.02))
            let sole = sin(2 * .pi * 82 * time) * exp(-time * 35) * 0.52
            let brush = filteredNoise * exp(-time * 27) * 0.38
            return Float((sole + brush) * attack * release)
        }
    }

    private static func makeClothBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        var lowNoise = 0.0
        return makeBuffer(duration: 0.34, sampleRate: sampleRate) { time in
            let noise = Double.random(in: -1...1)
            lowNoise += (noise - lowNoise) * 0.10
            let envelope = pow(sin(.pi * time / 0.34), 1.6)
            let friction = 0.65 + 0.35 * sin(2 * .pi * 31 * time)
            return Float((noise - lowNoise) * envelope * friction * 0.28)
        }
    }

    private static func makeAmbienceBuffer(crowd: Bool, sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 5.0
        var lowNoise = 0.0
        var midNoise = 0.0
        return makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            let noise = Double.random(in: -1...1)
            lowNoise += (noise - lowNoise) * 0.035
            midNoise += (noise - midNoise) * 0.16
            let fade = min(1, time / 0.04, max(0, (duration - time) / 0.04))
            let room = lowNoise * (crowd ? 0.55 : 0.30)
            let movement = (midNoise - lowNoise) * (crowd ? 0.26 : 0.08)
            let swell = 0.74 + 0.18 * sin(2 * .pi * time / duration) + 0.08 * sin(2 * .pi * 3 * time / duration)
            let hum = crowd ? 0 : sin(2 * .pi * 50 * time) * 0.018 + sin(2 * .pi * 100 * time) * 0.006
            return Float(((room + movement) * swell + hum) * fade)
        }
    }

    private static func makeCheerBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 2.8
        var lowNoise = 0.0
        var midNoise = 0.0
        return makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            let noise = Double.random(in: -1...1)
            lowNoise += (noise - lowNoise) * 0.04
            midNoise += (noise - midNoise) * 0.32
            let envelope = min(1, time / 0.35) * min(1, max(0, (duration - time) / 0.65))
            let voiceModulation = sin(2.0 * Double.pi * 1.3 * time)
            let voices = (midNoise - lowNoise) * (0.42 + 0.16 * voiceModulation)
            let clapPulse = max(0.0, sin(2.0 * Double.pi * 7.5 * time))
            let claps = noise * pow(clapPulse, 18.0) * 0.20
            let whistleEnvelope = max(0, 1 - abs(time - 1.15) / 0.40)
            let whistleModulation = sin(2.0 * Double.pi * 4.0 * time)
            let whistlePhase = 2.0 * Double.pi * (1650.0 * time + 18.0 * whistleModulation)
            let whistle = sin(whistlePhase) * whistleEnvelope * 0.035
            return Float((voices + lowNoise * 0.55 + claps + whistle) * envelope)
        }
    }

    private static func makeCutsceneChordBuffer(victory: Bool, sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = victory ? 1.8 : 1.35
        let notes = victory ? [261.63, 329.63, 392.0, 523.25] : [146.83, 174.61, 220.0]
        return makeBuffer(duration: duration, sampleRate: sampleRate) { time in
            var sample = 0.0
            for (index, frequency) in notes.enumerated() {
                let elapsed = time - Double(index) * (victory ? 0.12 : 0.045)
                guard elapsed >= 0 else { continue }
                let attack = min(1, elapsed / (victory ? 0.02 : 0.12))
                let envelope = attack * exp(-elapsed * (victory ? 2.8 : 2.1))
                let tone = sin(2 * .pi * frequency * elapsed) + 0.15 * sin(2 * .pi * frequency * 2 * elapsed)
                sample += tone * envelope * 0.13
            }
            return Float(sample * min(1, max(0, (duration - time) / 0.16)))
        }
    }

    private static func makeBuffer(
        duration: Double, sampleRate: Double, generator: (Double) -> Float
    ) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            channel[frame] = min(0.98, max(-0.98, generator(time)))
        }
        return buffer
    }
}
