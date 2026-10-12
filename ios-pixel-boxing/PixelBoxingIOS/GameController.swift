/*
 GameController.swift

 파일 설명:
 - 게임 엔진(`CombatEngine`), 프레젠테이션(`CombatPresentation`), 사운드(`SoundManager`), 햅틱,
     그리고 UI 사이를 중재하는 중심 컨트롤러입니다. 입력을 수신하고 엔진에 전달하며,
     정기적으로 상태 스냅샷을 게시(publish)합니다.

 사용 영향 및 주의사항:
 - `GameController`의 변경은 입력 처리, 재생 로직, 저장/통계 등에 광범위한 영향을 미칩니다.
 - 이미 많은 함수에 상세 주석이 존재하므로 파일 상단에 전체 설명을 추가합니다.
*/
import Combine
import SwiftUI

/// 플레이어의 온-디바이스 누적 통계 구조체
/// - 서버 동기화 없이 로컬에 저장되며, 보상 잠금(의상, 스트릭 보상 등)과
///   리더보드 제출 시 사용됩니다. 값이 누락된 이전 버전의 세이브와도
///   호환되도록 `decodeIfPresent`를 사용해 기본값을 제공합니다.
struct PlayerStats: Codable, Equatable {
    /// 스타일별 승리 횟수. 키는 `FightStyle.rawValue` 문자열.
    var winsByStyle: [String: Int] = [:]
    /// 연습(Gym)에서 누적한 초 단위 시간. 특정 의상 잠금 해제 조건에 사용.
    var gymSeconds: Double = 0
    /// 라운드 동안 피해를 전혀 입지 않고 이긴 라운드 수(퍼펙트 라운드).
    var perfectRoundWins: Int = 0
    /// 현재 연속 승리 스트릭(라이브 값). 라운드 패배 시 리셋됨.
    var currentWinStreak: Int = 0
    /// 지금까지의 최고 연속 승리 스트릭(절대 감소하지 않음). 스트릭 보상 조건에 사용.
    var bestWinStreak: Int = 0

    /// 총 승리 합계(모든 스타일의 합).
    var totalWins: Int { winsByStyle.values.reduce(0, +) }

    /// 플레이어의 선호 스타일(가장 많이 승리한 스타일). 없으면 `nil`.
    /// 미래 버전에서 추가된 미지 스타일 키는 무시해 현재 버전이 해석 가능한 스타일만 대상으로 계산합니다.
    var preferredStyle: FightStyle? {
        winsByStyle
            .compactMap { key, wins in
                FightStyle(rawValue: key).map { ($0, wins) }
            }
            .max { $0.1 < $1.1 }?
            .0
    }
}

extension PlayerStats {
    private enum CodingKeys: String, CodingKey {
        case winsByStyle, gymSeconds, perfectRoundWins, currentWinStreak, bestWinStreak
    }

    /// Older paid releases did not contain every reward counter. Missing keys are defaults, not a
    /// reason to discard existing wins/outfit progress. Keys and enum raw values stay unchanged.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // 이전 버전의 저장 데이터와 호환되도록 모든 필드는 `decodeIfPresent`로 읽고
        // 값이 없으면 안전한 기본값을 사용합니다.
        winsByStyle = try values.decodeIfPresent([String: Int].self, forKey: .winsByStyle) ?? [:]
        gymSeconds = try values.decodeIfPresent(Double.self, forKey: .gymSeconds) ?? 0
        perfectRoundWins = try values.decodeIfPresent(Int.self, forKey: .perfectRoundWins) ?? 0
        currentWinStreak = try values.decodeIfPresent(Int.self, forKey: .currentWinStreak) ?? 0
        // bestWinStreak는 이전에 저장된 best와 현재 스트릭 중 큰 값을 취해 감소를 방지합니다.
        bestWinStreak = max(currentWinStreak, try values.decodeIfPresent(Int.self, forKey: .bestWinStreak) ?? 0)
    }
}

@MainActor
final class GameController: ObservableObject {
    /// 내부: 현재 입력 상태를 집계하기 위한 간단한 구조체.
    /// - `forward`/`strafe`는 -1/0/1 값을 가지며, 여러 버튼이 동시에 눌린 경우 합산됩니다.
    private struct MovementControl: Hashable {
        let forward: Int
        let strafe: Int
    }

    // UserDefaults 키 상수
    private static let outfitDefaultsKey = "pixelBoxingEquippedOutfit"
    private static let soundMutedDefaultsKey = "pixelBoxingSoundMuted"
    private static let statsDefaultsKey = "pixelBoxingPlayerStats"

    /// 전투 시뮬레이션 엔진(게임 룰 담당)
    let engine: CombatEngine
    /// 프레젠테이션 레이어: 엔진 이벤트를 받아 화면 연출(시그니처, 카메라 등)을 담당
    let presentation = CombatPresentation()
    /// 사운드 매니저(피드백 활성화 시 생성). nil이면 사운드를 무시합니다.
    private let sound: SoundManager?
    /// 온-디바이스 지속성(통계/설정 저장)에 사용되는 `UserDefaults`. 비활성화 가능.
    private let defaults: UserDefaults?
    private let storyStore: StoryProgressStore?
    private var preferredOutfit: OutfitID
    private var purchaseAccessSubscription: AnyCancellable?
    private var lastStorySave = Date.distantPast
    @Published private(set) var storyBout: StoryBoutState?
    @Published private(set) var storyRoundTransition: StoryRoundTransition?
    @Published private(set) var storyIntroduction: StoryIntroduction?
    @Published private(set) var storyRivalScene: StoryRivalScene?
    var isPlayingStoryScene: Bool { storyIntroduction != nil || storyRivalScene != nil }
    var canPlayStoryRivalScene: Bool {
        guard let opponent = engine.storyBout?.opponent else { return false }
        return engine.storyBout?.phase == .finished && engine.storyBout?.verdict == .win
            && !isPlayingStoryScene
            && storyStore?.progress.seenRivalScenes.contains(opponent) != true
            && StoryIntroClip.rivalScene(for: opponent) != nil
    }
    private var introductionDefersBell = false
    private var introductionPreviewOnly = false
    private var rivalScenePreviewOnly = false
    /// 햅틱/사운드 등 피드백을 활성화할지 여부(디버그/테스트 모드에서 꺼둘 수 있음).
    private let feedbackEnabled: Bool
    /// 현재 뷰에 바인딩되어 표시되는 스냅샷(엔진에서 복사한 읽기 전용 상태)
    @Published private(set) var snapshot: CombatSnapshot
    /// 플레이어의 현재 선택한 스타일(FightStyle)
    @Published private(set) var playerStyle: FightStyle
    /// 현재 장착된 의상 ID
    @Published private(set) var equippedOutfit: OutfitID
    @Published private(set) var equippedAppearance: StoryOpponent?
    @Published private(set) var championBeltEquipped: Bool
    var clearedStoryOpponents: Set<StoryOpponent> { storyStore?.progress.clearedOpponents ?? [] }
    var championOutfitEarned: Bool { storyStore?.progress.championOutfitUnlocked == true }
    var championBeltEarned: Bool { storyStore?.progress.championBeltUnlocked == true }
    var championBeltUnlocked: Bool { StoryPurchaseStore.shared.hasStoryAccess && championBeltEarned }
    /// 사운드 음소거 상태(설정 반영)
    @Published private(set) var isSoundMuted: Bool
    /// 플레이어 통계 데이터
    @Published private(set) var playerStats: PlayerStats
    /// 누르고 있는 이동 버튼들의 집합(다중 입력을 합산하기 위해 사용)
    private var heldMovement: Set<MovementControl> = []
    /// 방어(가드) 버튼이 눌려 있는지
    @Published private(set) var modifiers = CombatModifiers()
    private var heldWeaves: Set<Int> = []
    private var guardHeld: Bool { modifiers.guarding }
    /// 더킹(duck) 입력 방향: -1/0/1
    private var duckDirectionHeld: Int { modifiers.duckDirection }

    lazy var scene3D: Arena3DScene = {
        // SceneKit 기반 3D 씬을 지연 생성합니다. `scene3D`는 뷰에서 직접 렌더링됩니다.
        let scene = Arena3DScene(engine: engine, presentation: presentation)
        scene.setPlayerOutfit(equippedOutfit)
        scene.setPlayerAppearance(equippedAppearance)
        scene.setPlayerChampionBelt(championBeltEquipped)
        scene.controller = self
        return scene
    }()

        init(persistsProgress: Bool = true, feedbackEnabled: Bool = true,
            storyOpponent: StoryOpponent? = nil, storyStore: StoryProgressStore? = nil) {
        // 초기화 시점 설명:
        // - `persistsProgress`: 로컬 퍼시스턴스(.standard) 사용 여부. false면 기본 설정/통계 비활성화.
        // - `feedbackEnabled`: 사운드/햅틱 사용 여부.
        defaults = persistsProgress ? .standard : nil
        self.storyStore = storyStore
        self.feedbackEnabled = feedbackEnabled
        engine = CombatEngine(persistHabits: persistsProgress, storyOpponent: storyOpponent,
            storyLearning: storyStore?.progress.learning ?? StoryLearningState())
        if storyOpponent != nil,
           let rawStyle = defaults?.string(forKey: "pixelBoxingPlayerStyle"),
           let style = FightStyle(rawValue: rawStyle) {
            engine.setPlayerStyle(style)
        }
        storyBout = engine.storyBout
        sound = feedbackEnabled ? SoundManager(opponent: storyOpponent) : nil
        snapshot = engine.snapshot
        playerStyle = engine.player.style
        let savedOutfit = OutfitID(rawValue: defaults?.string(forKey: GameController.outfitDefaultsKey) ?? "") ?? .classic
        preferredOutfit = savedOutfit
        let hasStoryAccess = StoryPurchaseStore.shared.hasStoryAccess
        equippedOutfit = .classic
        let savedAppearance = storyStore?.progress.equippedAppearance
        equippedAppearance = hasStoryAccess && storyStore?.progress.canEquipAppearance(savedAppearance) == true
            ? savedAppearance : nil
        championBeltEquipped = hasStoryAccess && storyStore?.progress.championBeltUnlocked == true
            && storyStore?.progress.championBeltEquipped == true
        isSoundMuted = defaults?.bool(forKey: GameController.soundMutedDefaultsKey) ?? false
        if let data = defaults?.data(forKey: GameController.statsDefaultsKey),
           let saved = try? JSONDecoder().decode(PlayerStats.self, from: data) {
            playerStats = saved
        } else {
            playerStats = PlayerStats()
        }
        equippedOutfit = isOutfitUnlocked(savedOutfit, hasStoryAccess: hasStoryAccess) ? savedOutfit : .classic
        sound?.isMuted = isSoundMuted
        // 엔진 이벤트를 구독하여 프레젠테이션과 피드백(사운드/햅틱)을 트리거합니다.
        engine.onCombatEvent = { [weak self] event in
            self?.handleCombatEvent(event)
        }
        purchaseAccessSubscription = StoryPurchaseStore.shared.$accessState.sink { [weak self] accessState in
            self?.refreshPurchaseEquipment(hasStoryAccess: accessState == .unlocked)
        }
    }

    func updateStoryRoundTransition() {
        let transition = engine.storyRoundTransition
        if storyRoundTransition != transition { storyRoundTransition = transition }
    }

    func publishSnapshot() {
        updateStoryRoundTransition()
        // 엔진에서 최신 상태를 읽어와 `snapshot`을 갱신합니다.
        // 또한 중요한 타이밍 기반 오디오(라운드 종료 벨, 카운트다운 틱)를 여기서 트리거합니다.
        let nextSnapshot = engine.snapshot
        if nextSnapshot.showsRoundResult, !snapshot.showsRoundResult {
            // KO의 낙하음 등은 이미 재생되었을 수 있으므로 결과 리빌(announce)용 벨/스팅어만 추가합니다.
            sound?.playRoundResult(outcome: nextSnapshot.lastRoundOutcome, knockout: nextSnapshot.lastRoundWasKnockout)
        }
        if nextSnapshot.phase == .fight {
            // 라운드 타이머의 마지막 3초(3,2,1)에 틱음을 재생하여 긴장감을 조성합니다.
            let previousCeil = Int(ceil(snapshot.time))
            let nextCeil = Int(ceil(nextSnapshot.time))
            if nextCeil != previousCeil, (1...3).contains(nextCeil) {
                sound?.playCountdownTick()
            }
        }
        snapshot = nextSnapshot
        let previousStory = storyBout
        storyBout = engine.storyBout
        if let storyBout {
            if previousStory?.phase != storyBout.phase, storyBout.phase != .fighting {
                releaseHeldControls()
                if storyBout.phase == .corner { sound?.playRoundResult(outcome: .draw, knockout: false) }
            }
            if storyBout.phase == .counting, previousStory?.displayedCount != storyBout.displayedCount {
                sound?.playCountdownTick()
            }
            if storyBout.phase != .finished,
               previousStory?.phase != storyBout.phase || previousStory?.round != storyBout.round
                || Date().timeIntervalSince(lastStorySave) >= 2 {
                saveStoryProgress()
            }
        }
    }

    func saveStoryProgress() {
        guard !introductionPreviewOnly && !rivalScenePreviewOnly else { return }
        guard let checkpoint = engine.storyCheckpoint() else { return }
        storyStore?.save(checkpoint)
        lastStorySave = Date()
    }

    func retryStoryBout() {
        guard engine.storyBout != nil else { return }
        releaseHeldControls()
        introductionDefersBell = true
        engine.startSession()
        beginStoryIntroduction(short: true)
        publishSnapshot()
        saveStoryProgress()
    }

    /// 엔진에서 발생한 `CombatEvent`를 수신하여
    /// - `presentation`에 전달(화면 연출 업데이트)
    /// - 통계 업데이트(라운드 종료 시 기록)
    /// - 피드백(사운드/햅틱) 트리거
    /// 로직을 수행합니다. 이 메서드는 비파괴적이며 게임 룰 자체를 변경하지 않습니다.
    private func handleCombatEvent(_ event: CombatEvent) {
        presentation.receive(event)
        if case let .roundEnded(outcome, _) = event {
            if engine.storyBout != nil {
                saveStoryProgress()
            } else {
                // 라운드 종료 시점에만 통계를 영구 저장합니다.
                if outcome == .playerWin {
                    recordWin(perfectRound: engine.player.hp == 100)
                } else if outcome == .playerLoss {
                    recordLoss()
                }
            }
        }
        guard feedbackEnabled else { return }
        switch event {
        case .roundStarted:
            // 라운드 시작 사운드
            if !introductionDefersBell { sound?.playRoundStart() }
        case let .dodge(fighter, grade):
            // 더킹/회피 감지: 사운드와 플레이어 전용 햅틱을 재생
            sound?.playDuckEvade(pan: pan(forPlayer: fighter == .player))
            guard fighter == .player else { return }
            switch grade {
            case .perfect:
                HapticsManager.shared.impact(style: .medium, intensity: 0.8)
            case .accurate:
                HapticsManager.shared.impact(style: .light, intensity: 0.55)
            case .good:
                HapticsManager.shared.impact(style: .soft, intensity: 0.4)
            case .normal, .none:
                HapticsManager.shared.impact(style: .soft, intensity: 0.25)
            }
        case let .impact(impact):
            let pan = pan(forPlayer: impact.attacker == .rival)
            sound?.playImpact(impact, pan: pan)
            HapticsManager.shared.playImpact(impact)
        case let .whiff(fighter):
            sound?.playWhiff(pan: pan(forPlayer: fighter == .player))
        case let .exhausted(fighter):
            sound?.playExhausted(pan: pan(forPlayer: fighter == .player))
        case .attackStarted:
            HapticsManager.shared.prepareContact()
        case let .punchSwing(fighter, punch):
            sound?.playPunchSwing(punch, pan: pan(forPlayer: fighter == .player))
        case .roundEnded:
            break
        }
    }

    /// Maps a fighter's arena x-position to a rough left/right stereo pan (-1...1) so effect sounds hint
    /// at where the action happened in the ring instead of always playing dead-center.
    private func pan(forPlayer isPlayer: Bool) -> Float {
        let x = isPlayer ? engine.player.x : engine.enemy.x
        return Float(max(-1, min(1, (x - 295) / 125)))
    }

    func start(resumingStory: Bool = true, shortStoryIntroduction: Bool = false) {
        releaseHeldControls()
        if resumingStory, let checkpoint = storyStore?.progress.activeBout,
           checkpoint.bout.opponent == engine.storyBout?.opponent {
            engine.restoreStory(checkpoint)
        } else {
            introductionDefersBell = engine.storyBout != nil
            if engine.storyBout != nil {
                engine.startSession()
            } else {
                engine.resumeSession()
            }
            if engine.storyBout != nil {
                beginStoryIntroduction(short: shortStoryIntroduction)
            }
        }
        publishSnapshot()
        if !resumingStory { saveStoryProgress() }
        if feedbackEnabled { HapticsManager.shared.notify(.success) }
    }

    /// 전투 시작(또는 재시작): 입력 상태 초기화, 엔진 재개, 스냅샷 게시
    /// - UI에서 'FIGHT' 버튼 누를 때 호출됩니다.

    func setCinematicMode(_ active: Bool, presentation: ArenaCinematicPresentation = .matchIntro) {
        scene3D.setCinematicMode(active, presentation: presentation)
        if active && (presentation == .appOpening || presentation == .matchIntro) {
            sound?.beginCutscene(.opening)
        } else {
            sound?.stopCutscene()
        }
    }

    func updateCinematicSound(elapsed: Double) {
        sound?.updateCutscene(elapsed: elapsed)
    }

    func updateAudioMix(deltaTime: Double) {
        sound?.updateMix(deltaTime: deltaTime,
            battleActive: engine.phase == .fight || engine.phase == .roundBreak,
            fighting: engine.phase == .fight)
    }

    func stopBattleSound() {
        sound?.stopBattleAudio()
    }

    func pause() {
        releaseHeldControls()
        engine.togglePause()
        publishSnapshot()
        saveStoryProgress()
    }

    /// 게임을 일시정지/재개합니다. 내부 입력을 해제하여 보류 상태를 초기화합니다.

    func suspendForInactivity() {
        releaseHeldControls()
        sound?.setCutsceneSuspended(true)
        if isPlayingStoryScene {
            scene3D.setStoryIntroductionSuspended(true)
            saveStoryProgress()
            return
        }
        if engine.phase == .fight || (engine.storyBout != nil && engine.phase == .roundBreak && engine.storyBout?.phase != .finished) {
            engine.togglePause()
            publishSnapshot()
        }
        saveStoryProgress()
    }

    func resumeStoryIntroduction() {
        sound?.setCutsceneSuspended(false)
        guard isPlayingStoryScene else { return }
        scene3D.setStoryIntroductionSuspended(false)
    }

    func beginStoryRivalScene(replay: Bool = false) {
        guard !isPlayingStoryScene, let opponent = engine.storyBout?.opponent,
              let clip = StoryIntroClip.rivalScene(for: opponent) else { return }
        if replay {
            guard storyStore?.progress.canReplayRivalScene(opponent) == true else { return }
        } else {
            guard canPlayStoryRivalScene else { return }
        }
        rivalScenePreviewOnly = replay
        releaseHeldControls()
        saveStoryProgress()
        let duration = scene3D.beginStoryRivalScene(clip: clip, chapter: opponent)
        storyRivalScene = StoryRivalScene(chapter: opponent, duration: duration)
        sound?.beginCutscene(.aftermath(opponent), clip: clip)
    }

    func updateStoryRivalScene(elapsed: Double) {
        guard var scene = storyRivalScene else { return }
        scene.elapsed = min(scene.duration, elapsed)
        storyRivalScene = scene
    }

    func finishStoryRivalScene() {
        guard let scene = storyRivalScene else { return }
        sound?.stopCutscene()
        scene3D.setCinematicMode(false)
        scene3D.resetFrameClock()
        releaseHeldControls()
        if !rivalScenePreviewOnly { storyStore?.markRivalSceneSeen(scene.chapter) }
        storyRivalScene = nil
    }

    func beginStoryIntroduction(short: Bool = false, previewOnly: Bool = false) {
        guard let opponent = engine.storyBout?.opponent else { return }
        releaseHeldControls()
        introductionPreviewOnly = previewOnly
        let duration = scene3D.beginStoryIntroduction(short: short)
        storyIntroduction = StoryIntroduction(opponent: opponent, short: short, duration: duration)
        sound?.beginCutscene(.introduction(opponent, short: short), clip: StoryIntroClip.clip(for: opponent))
    }

    func updateStoryIntroduction(elapsed: Double) {
        guard var introduction = storyIntroduction else { return }
        introduction.elapsed = min(introduction.duration, elapsed)
        storyIntroduction = introduction
    }

    func finishStoryIntroduction() {
        guard let introduction = storyIntroduction else { return }
        sound?.stopCutscene()
        scene3D.setCinematicMode(false)
        scene3D.resetFrameClock()
        releaseHeldControls()
        storyIntroduction = nil
        if !introductionPreviewOnly {
            storyStore?.markIntroductionSeen(introduction.opponent)
            introductionDefersBell = false
            sound?.playRoundStart()
            publishSnapshot()
            saveStoryProgress()
        }
    }

    func continueToNextRound() {
        guard engine.snapshot.canAdvanceRound else { return }
        releaseHeldControls()
        engine.requestNextRound()
        publishSnapshot()
        if feedbackEnabled { HapticsManager.shared.notify(.success) }
    }

    /// 다음 라운드로 진행 요청. 엔진의 `canAdvanceRound`를 확인하고, 요청을 보낸 뒤 스냅샷을 갱신합니다.

    func releaseHeldControls() {
        heldWeaves.removeAll()
        engine.cancelWeaveInput()
        heldMovement.removeAll()
        modifiers.reset()
        engine.setMove(x: 0, y: 0)
        engine.setGuarding(false)
        engine.setDuck(0, active: false)
    }

    /// 모든 입력 상태를 해제(버튼 릴리즈)하고 엔진에도 반영합니다.

    func resetLearning() {
        releaseHeldControls()
        engine.resetLearning()
        publishSnapshot()
        if feedbackEnabled { HapticsManager.shared.notify(.warning) }
    }

    /// 엔진의 학습(기록/습관 추적)을 초기화합니다. 연습 데이터 초기화 등에 사용됩니다.

    func move(x: Double, y: Double, active: Bool) {
        guard storyIntroduction == nil else { return }
        let control = MovementControl(forward: Int(x), strafe: Int(y))
        if active {
            heldMovement.insert(control)
        } else {
            heldMovement.remove(control)
        }
        let forward = heldMovement.reduce(0) { $0 + $1.forward }
        let strafe = heldMovement.reduce(0) { $0 + $1.strafe }
        engine.setMove(x: Double(forward), y: Double(strafe))
    }

    /// 이동 입력 처리: 여러 방향 입력을 중첩할 수 있어 `heldMovement`에 누적하고
    /// 합산 결과를 엔진에 전송합니다. `active`가 false면 해당 입력을 해제합니다.

    func guardButton(active: Bool) {
        guard storyIntroduction == nil else { return }
        guard !active || (engine.player.stagger <= 0 && engine.player.exhausted <= 0) else { return }
        modifiers.guarding = active
        engine.setGuarding(active)
    }

    /// 가드(방어) 버튼 처리. 누르고 있는 동안 `engine.setGuarding(true)`.

    func duckButton(direction: Int, active: Bool) {
        guard storyIntroduction == nil else { return }
        guard !active || (engine.player.stagger <= 0 && engine.player.exhausted <= 0) else { return }
        modifiers.setDuck(direction, active: active)
        engine.setDuck(duckDirectionHeld, active: duckDirectionHeld != 0)
    }

    /// 더킹(상하 회피) 버튼 처리. `direction`은 -1/0/1.

    func attack(_ punch: Punch) {
        guard storyIntroduction == nil else { return }
        if engine.startAttack(engine.player, punch: punch, recordsHabit: true) {
            if feedbackEnabled { HapticsManager.shared.impact(style: .light, intensity: 0.25) }
        }
    }

    /// 단일 공격(펀치) 명령: 엔진에 공격 시작을 요청하고, 성공적으로 시작되면 햅틱을 발생시킵니다.

    func comboAttack(base: Punch) {
        guard storyIntroduction == nil else { return }
        if WeaveState.hook(base: base, direction: engine.player.weave.comboDirection) != nil {
            _ = engine.requestWeaveHook(base: base)
            return
        }
        guard !engine.player.weave.isActive else { return }
        attack(selectedPunch(base: base))
    }

    /// One press starts one weave; holding never repeats it. Releasing does not cancel its step.
    func weaveButton(direction: Int, active: Bool) {
        guard storyIntroduction == nil else { return }
        guard direction == -1 || direction == 1 else { return }
        if !active { heldWeaves.remove(direction); return }
        guard heldWeaves.insert(direction).inserted else { return }
        if engine.weave(direction: direction) {
            if feedbackEnabled { HapticsManager.shared.impact(style: .light, intensity: 0.25) }
            publishSnapshot()
        }
    }

    /// The same resolved input is used by the command and its VoiceOver name, including held combos.
    func selectedPunch(base: Punch) -> Punch {
        if let hook = WeaveState.hook(base: base, direction: engine.player.weave.comboDirection) { return hook }
        if engine.player.weave.isActive { return base }
        return modifiers.punch(base: base)
    }

    /// 콤보 공격 진입: 현재 가드/더킹 상태를 반영한 콤보 펀치를 생성해 `attack(_:)`로 위임합니다.

    func backstep() {
        guard storyIntroduction == nil else { return }
        if engine.backstep() {
            sound?.playBackstep(pan: pan(forPlayer: true))
            if feedbackEnabled { HapticsManager.shared.impact(style: .light, intensity: 0.45) }
            publishSnapshot()
        }
    }

    /// 백스텝(후방 이동) 시도. 성공 시 소리·햅틱·스냅샷 갱신을 수행합니다.

    func synchronizeHeldControls() {
        guard !isPlayingStoryScene else { return }
        guard engine.player.attack == nil, !engine.player.weave.isActive else { return }
        engine.setGuarding(guardHeld)
        engine.setDuck(duckDirectionHeld, active: duckDirectionHeld != 0)
    }

    /// 외부(예: 뷰 라이프사이클)에서 입력 상태를 엔진과 동기화할 때 사용합니다.

    func setPlayerStyle(_ style: FightStyle) {
        engine.setPlayerStyle(style)
        playerStyle = style
    }

    /// 플레이어 스타일 변경: 엔진의 내부 스타일을 바꾸고 퍼블리시합니다.

    func isOutfitUnlocked(_ outfit: OutfitID) -> Bool {
        isOutfitUnlocked(outfit, hasStoryAccess: StoryPurchaseStore.shared.hasStoryAccess)
    }

    private func isOutfitUnlocked(_ outfit: OutfitID, hasStoryAccess: Bool) -> Bool {
        if outfit == .storyStarter { return hasStoryAccess }
        return (hasStoryAccess && (outfit == .champion || outfit == .storyChampion) && championOutfitEarned) || outfit.isUnlocked(
            highestRound: engine.highestRound,
            totalWins: playerStats.totalWins,
            gymSeconds: playerStats.gymSeconds,
            perfectRoundWins: playerStats.perfectRoundWins,
            bestWinStreak: playerStats.bestWinStreak,
            winsByStyle: playerStats.winsByStyle
        )
    }

    func isAppearanceUnlocked(_ opponent: StoryOpponent) -> Bool {
        StoryPurchaseStore.shared.hasStoryAccess && storyStore?.progress.canEquipAppearance(opponent) == true
    }

    func setEquippedOutfit(_ outfit: OutfitID) {
        guard isOutfitUnlocked(outfit) else { return }
        setEquippedAppearance(nil)
        preferredOutfit = outfit
        equippedOutfit = outfit
        scene3D.setPlayerOutfit(outfit)
        defaults?.set(outfit.rawValue, forKey: GameController.outfitDefaultsKey)
    }

    private func refreshPurchaseEquipment(hasStoryAccess: Bool) {
        let outfit = isOutfitUnlocked(preferredOutfit, hasStoryAccess: hasStoryAccess) ? preferredOutfit : .classic
        if equippedOutfit != outfit {
            equippedOutfit = outfit
            scene3D.setPlayerOutfit(outfit)
        }
        let savedAppearance = storyStore?.progress.equippedAppearance
        let appearance = hasStoryAccess && storyStore?.progress.canEquipAppearance(savedAppearance) == true
            ? savedAppearance : nil
        if equippedAppearance != appearance {
            equippedAppearance = appearance
            scene3D.setPlayerAppearance(appearance)
        }
        let belt = hasStoryAccess && championBeltEarned && storyStore?.progress.championBeltEquipped == true
        if championBeltEquipped != belt {
            championBeltEquipped = belt
            scene3D.setPlayerChampionBelt(belt)
        }
    }

    func setEquippedAppearance(_ opponent: StoryOpponent?) {
        if let opponent, !isAppearanceUnlocked(opponent) { return }
        guard equippedAppearance != opponent || storyStore?.progress.equippedAppearance != opponent else { return }
        storyStore?.equipAppearance(opponent)
        equippedAppearance = opponent
        scene3D.setPlayerAppearance(opponent)
    }

    func setChampionBeltEquipped(_ equipped: Bool) {
        guard !equipped || championBeltUnlocked else { return }
        storyStore?.equipChampionBelt(equipped)
        championBeltEquipped = equipped
        scene3D.setPlayerChampionBelt(equipped)
    }

    func refreshStoryEquipment() {
        refreshPurchaseEquipment(hasStoryAccess: StoryPurchaseStore.shared.hasStoryAccess)
    }

    /// 장착 의상 변경: 잠금 조건을 확인한 뒤 씬/설정에 반영합니다.

    func setSoundMuted(_ muted: Bool) {
        isSoundMuted = muted
        sound?.isMuted = muted
        defaults?.set(muted, forKey: GameController.soundMutedDefaultsKey)
    }

    /// 사운드 음소거 토글: `SoundManager`와 `UserDefaults`를 동시에 업데이트합니다.

    /// Bumps the on-device win record for the round's outcome and best-effort submits the updated total
    /// (plus the player's most-used style) to the optional Game Center leaderboard. Never blocks or affects
    /// local gameplay if the submission fails (offline, not signed in, leaderboard not yet configured).
    private func recordWin(perfectRound: Bool) {
        playerStats.winsByStyle[playerStyle.rawValue, default: 0] += 1
        if perfectRound {
            playerStats.perfectRoundWins += 1
        }
        playerStats.currentWinStreak += 1
        playerStats.bestWinStreak = max(playerStats.bestWinStreak, playerStats.currentWinStreak)
        persistStats()
        synchronizeGameCenterScore()
    }

    func synchronizeGameCenterScore() {
        guard defaults != nil, playerStats.totalWins > 0 else { return }
        GameCenterManager.shared.submit(
            totalWins: playerStats.totalWins,
            preferredStyle: playerStats.preferredStyle,
            highestRound: engine.highestRound
        )
    }

    /// 라운드 승리 기록: 로컬 스탯을 업데이트하고(퍼시스트) Game Center에 비동기 제출 시도.
    /// - 실패/네트워크 문제는 게임 흐름에 영향 주지 않음.

    /// Breaks the player's live win streak on a round loss. Only `currentWinStreak` resets here --
    /// `bestWinStreak` (used for the streak outfit's unlock check) is never decreased.
    private func recordLoss() {
        guard playerStats.currentWinStreak != 0 else { return }
        playerStats.currentWinStreak = 0
        persistStats()
    }

    /// 패배 처리: 현재 연속 승리 스트릭을 리셋합니다.

    /// Adds active practice-room time toward the Gym's cumulative-hours outfit unlock when the app becomes
    /// inactive or the player leaves the practice room.
    func addGymSeconds(_ seconds: Double) {
        guard seconds > 0 else { return }
        playerStats.gymSeconds += seconds
        persistStats()
    }

    /// 연습실 체류 시간 추가: PracticeView의 appear/disappear 시 호출됩니다.

    private func persistStats() {
        if let data = try? JSONEncoder().encode(playerStats) {
            defaults?.set(data, forKey: GameController.statsDefaultsKey)
        }
    }
}
