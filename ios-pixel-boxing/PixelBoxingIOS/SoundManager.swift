import AVFoundation

/// Procedurally synthesized sound effects for RIVAL.
///
/// No bundled audio assets are used (matching how the app icon is code-generated instead of imported):
/// every buffer below is filled with plain sine/noise math at launch and cached for reuse. If the audio
/// session can't be started (e.g. a constrained host environment) every call below silently no-ops so the
/// game stays fully playable without sound.
@MainActor
final class SoundManager {
    private let engine = AVAudioEngine()
    private var effectPlayers: [AVAudioPlayerNode] = []
    private var nextEffectPlayerIndex = 0

    /// Mutes all game audio effects without tearing down the engine, so it can be toggled instantly from
    /// a settings switch.
    var isMuted = false {
        didSet { engine.mainMixerNode.outputVolume = isMuted ? 0 : 1 }
    }

    private let sampleRate: Double = 44_100
    private var lightHitBuffer: AVAudioPCMBuffer?
    private var heavyHitBuffer: AVAudioPCMBuffer?
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

    init() {
        buildBuffers()
        buildGraph()
        configureSession()
        startEngine()
    }

    // MARK: Public game events

    /// A landed punch. `damage` drives which impact texture plays, so bigger hits are audibly
    /// distinguishable from light taps. `guarded` swaps in a duller block thud. `pan` places the sound
    /// left/right (-1...1) to roughly match where the action happened in the ring.
    func playImpact(damage: Int, guarded: Bool, pan: Float = 0) {
        let intensity = min(1, 0.30 + Double(damage) / 16)
        let buffer = guarded ? guardBuffer : (damage >= 10 ? heavyHitBuffer : lightHitBuffer)
        playEffect(buffer, volume: Float(0.5 + intensity * 0.5), pan: pan)
    }

    func playDuckEvade(pan: Float = 0) {
        playEffect(duckBuffer, volume: 0.55, pan: pan)
    }

    func playRoundStart() {
        playEffect(bellBuffer, volume: 0.85)
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
    }

    func playKnockout() {
        playEffect(koBuffer, volume: 1.0)
    }

    /// A punch that missed entirely — a soft airy whoosh instead of the punchier impact textures, so a
    /// miss reads as clearly different from a landed (or blocked) hit.
    func playWhiff(pan: Float = 0) {
        playEffect(whiffBuffer, volume: 0.4, pan: pan)
    }

    func playBackstep(pan: Float = 0) {
        playEffect(backstepBuffer, volume: 0.55, pan: pan)
    }

    /// A defender's guard collapsing under stamina pressure — a sharper, more dramatic cue than the
    /// regular guarded-impact thud, since it marks a meaningful turning point in the exchange.
    func playGuardBreak(pan: Float = 0) {
        playEffect(guardBreakBuffer, volume: 0.9, pan: pan)
    }

    func playExhausted(pan: Float = 0) {
        playEffect(exhaustedBuffer, volume: 0.6, pan: pan)
    }

    /// A short tick for the final seconds of a round, to build urgency without relying on the HUD alone.
    func playCountdownTick() {
        playEffect(tickBuffer, volume: 0.55)
    }

    // MARK: Engine plumbing

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: session
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawType) == .ended else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        startEngine()
    }

    private func buildGraph() {
        let format = lightHitBuffer?.format ?? engine.mainMixerNode.outputFormat(forBus: 0)
        for _ in 0..<4 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            effectPlayers.append(node)
        }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            return
        }
    }

    private func playEffect(_ buffer: AVAudioPCMBuffer?, volume: Float, pan: Float = 0) {
        guard let buffer, engine.isRunning, !effectPlayers.isEmpty else { return }
        let player = effectPlayers[nextEffectPlayerIndex]
        nextEffectPlayerIndex = (nextEffectPlayerIndex + 1) % effectPlayers.count
        player.stop()
        player.volume = volume
        player.pan = max(-1, min(1, pan))
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    // MARK: Buffer synthesis

    private func buildBuffers() {
        lightHitBuffer = Self.makeImpactBuffer(duration: 0.18, sampleRate: sampleRate, baseFrequency: 150, heavy: false)
        heavyHitBuffer = Self.makeImpactBuffer(duration: 0.26, sampleRate: sampleRate, baseFrequency: 90, heavy: true)
        guardBuffer = Self.makeImpactBuffer(duration: 0.16, sampleRate: sampleRate, baseFrequency: 240, heavy: false)
        duckBuffer = Self.makeBuffer(duration: 0.22, sampleRate: sampleRate) { _, t in
            let progress = t / 0.22
            let envelope = sin(.pi * progress)
            let noise = Double.random(in: -1...1)
            return Float(noise * envelope * 0.5)
        }
        bellBuffer = Self.makeBellBuffer(duration: 0.9, sampleRate: sampleRate)
        koBuffer = Self.makeImpactBuffer(duration: 0.5, sampleRate: sampleRate, baseFrequency: 60, heavy: true)
        whiffBuffer = Self.makeWhiffBuffer(sampleRate: sampleRate)
        backstepBuffer = Self.makeBackstepBuffer(sampleRate: sampleRate)
        guardBreakBuffer = Self.makeGuardBreakBuffer(sampleRate: sampleRate)
        exhaustedBuffer = Self.makeExhaustedBuffer(sampleRate: sampleRate)
        tickBuffer = Self.makeTickBuffer(sampleRate: sampleRate)
        victoryBuffer = Self.makeVictoryBuffer(sampleRate: sampleRate)
        defeatBuffer = Self.makeDefeatBuffer(sampleRate: sampleRate)
        drawBuffer = Self.makeDrawBuffer(sampleRate: sampleRate)
    }

    /// A soft airy whoosh for a punch that missed entirely, filtered the same way as the crowd rumble so
    /// it reads as breathy air movement instead of a solid impact texture.
    private static func makeWhiffBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 0.16
        var noiseState = 0.0
        return makeBuffer(duration: duration, sampleRate: sampleRate) { _, t in
            let progress = t / duration
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
        return makeBuffer(duration: duration, sampleRate: sampleRate) { _, t in
            var sample = 0.0
            for step in steps {
                let dt = t - step
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
        return makeBuffer(duration: duration, sampleRate: sampleRate) { _, t in
            let crackDecay = exp(-t * 30)
            let crackNoise = Double.random(in: -1...1) * crackDecay
            let ringDecay = exp(-t * 5)
            let ring = (sin(2 * .pi * 340 * t) * 0.5 + sin(2 * .pi * 512 * t) * 0.3) * ringDecay
            return Float((crackNoise * 0.7 + ring) * 0.85)
        }
    }

    /// A descending, deflating tone for a fighter gassing out.
    private static func makeExhaustedBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 0.55
        return makeBuffer(duration: duration, sampleRate: sampleRate) { _, t in
            let progress = min(1, t / duration)
            let frequency = 220 * (1 - 0.65 * progress)
            let envelope = sin(.pi * progress)
            let tone = sin(2 * .pi * frequency * t)
            let breath = Double.random(in: -1...1) * 0.2
            return Float((tone * 0.6 + breath) * envelope * 0.6)
        }
    }

    /// A short beep for the final seconds of a round.
    private static func makeTickBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let duration = 0.09
        return makeBuffer(duration: duration, sampleRate: sampleRate) { _, t in
            let decay = exp(-t * 40)
            return Float(sin(2 * .pi * 1046 * t) * decay * 0.7)
        }
    }

    /// A bright rising three-note chime for a round win.
    private static func makeVictoryBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let notes: [(Double, Double)] = [(0.0, 523.25), (0.12, 659.25), (0.24, 783.99)]
        return makeBuffer(duration: 0.6, sampleRate: sampleRate) { _, t in
            var sample = 0.0
            for (start, frequency) in notes {
                let dt = t - start
                guard dt >= 0 else { continue }
                sample += sin(2 * .pi * frequency * dt) * exp(-dt * 4.5)
            }
            return Float(sample * 0.35)
        }
    }

    /// A falling three-note stinger for a round loss.
    private static func makeDefeatBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        let notes: [(Double, Double)] = [(0.0, 392.00), (0.16, 349.23), (0.32, 261.63)]
        return makeBuffer(duration: 0.7, sampleRate: sampleRate) { _, t in
            var sample = 0.0
            for (start, frequency) in notes {
                let dt = t - start
                guard dt >= 0 else { continue }
                sample += sin(2 * .pi * frequency * dt) * exp(-dt * 3.2)
            }
            return Float(sample * 0.32)
        }
    }

    /// A flat, neutral double-tone for a draw.
    private static func makeDrawBuffer(sampleRate: Double) -> AVAudioPCMBuffer? {
        makeBuffer(duration: 0.5, sampleRate: sampleRate) { _, t in
            let decay = exp(-t * 5)
            let tone = sin(2 * .pi * 440 * t) * 0.5 + sin(2 * .pi * 660 * t) * 0.2
            return Float(tone * decay * 0.4)
        }
    }

    private static func makeImpactBuffer(duration: Double, sampleRate: Double, baseFrequency: Double, heavy: Bool) -> AVAudioPCMBuffer? {
        makeBuffer(duration: duration, sampleRate: sampleRate) { _, t in
            let decay = exp(-t * (heavy ? 9.0 : 14.0))
            let tone = sin(2 * .pi * baseFrequency * t) * decay
            let noise = Double.random(in: -1...1) * decay * (heavy ? 0.5 : 0.35)
            return Float((tone * 0.75 + noise) * 0.9)
        }
    }

    private static func makeBellBuffer(duration: Double, sampleRate: Double) -> AVAudioPCMBuffer? {
        let strikeTimes = [0.0, 0.42]
        return makeBuffer(duration: duration, sampleRate: sampleRate) { _, t in
            var sample = 0.0
            for strike in strikeTimes {
                let dt = t - strike
                guard dt >= 0 else { continue }
                let decay = exp(-dt * 3.2)
                let tone = sin(2 * .pi * 880 * dt) * 0.5 + sin(2 * .pi * 1320 * dt) * 0.3 + sin(2 * .pi * 660 * dt) * 0.2
                sample += tone * decay
            }
            return Float(sample * 0.6)
        }
    }

    private static func makeBuffer(
        duration: Double, sampleRate: Double, generator: (Int, Double) -> Float
    ) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return nil }
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            channel[frame] = generator(frame, t)
        }
        return buffer
    }
}
