#if DEBUG
import SceneKit
import SwiftUI

enum MotionLabPunch: String, CaseIterable {
    case jab = "JAB"
    case cross = "CROSS"

    var punch: Punch { self == .jab ? .jab : .cross }

    var spec: AttackSpec {
        guard let spec = CombatData.attacks[punch] else {
            preconditionFailure("Missing motion lab attack specification: \(rawValue)")
        }
        return spec
    }
}

enum MotionLabDistance: String, CaseIterable {
    case close = "Near"
    case middle = "Mid"
    case limit = "Range cap"

    @MainActor
    func units(for punch: MotionLabPunch, fighter: FighterModel) -> Double {
        let limit = punch.spec.range * fighter.reachMultiplier(for: punch.punch)
            + CombatData.punchReachExtension + CombatData.fighterContactRadius / CombatData.sceneScale
        switch self {
        case .close: return limit * 0.60
        case .middle: return limit * 0.80
        case .limit: return limit
        }
    }
}

enum MotionLabDefense: String, CaseIterable {
    case open = "Open dummy"
    case guardUp = "Guard"
    case duckLeft = "Duck left"
    case duckRight = "Duck right"

    var duckDirection: Int {
        switch self {
        case .open, .guardUp: 0
        case .duckLeft: -1
        case .duckRight: 1
        }
    }
}

enum MotionLabSpeed: String, CaseIterable {
    case quarter = "0.25x"
    case half = "0.5x"
    case normal = "1x"

    var multiplier: Double {
        switch self {
        case .quarter: 0.25
        case .half: 0.5
        case .normal: 1
        }
    }
}

@MainActor
final class MotionLabRun {
    let engine: CombatEngine
    let scene: Arena3DScene
    let inspectionCamera = SCNNode()
    let targetMarker = SCNNode(geometry: SCNSphere(radius: CGFloat(PunchContactGeometry.radius(.head))))
    private(set) var events: [CombatEvent] = []

    init(punch: MotionLabPunch, distance: MotionLabDistance, defense: MotionLabDefense) {
        let engine = CombatEngine(persistHabits: false, randomSeed: 0x524956414C)
        let presentation = CombatPresentation()
        engine.startSession()
        let separation = distance.units(for: punch, fighter: engine.player)
        engine.player.x = 295 - separation / 2
        engine.enemy.x = 295 + separation / 2
        engine.player.facingX = 1
        engine.player.facingY = 0
        engine.enemy.facingX = -1
        engine.enemy.facingY = 0
        engine.player.guarding = true
        engine.player.guardAmount = 1
        // A stationary test dummy, not a rival AI policy or a change to live combat.
        engine.enemy.stagger = 1_000
        engine.enemy.guarding = defense == .guardUp
        engine.enemy.guardAmount = defense == .guardUp ? 1 : 0
        engine.enemy.duckDirection = defense.duckDirection
        engine.enemy.duckTime = defense.duckDirection == 0 ? 0 : 10
        self.engine = engine
        scene = Arena3DScene(engine: engine, presentation: presentation)
        engine.onCombatEvent = { [weak self, weak presentation] event in
            self?.events.append(event)
            presentation?.receive(event)
        }
        inspectionCamera.camera = SCNCamera()
        inspectionCamera.camera?.fieldOfView = 42
        inspectionCamera.camera?.zNear = 0.05
        inspectionCamera.simdPosition = SIMD3<Float>(0, 2.7, 6.8)
        inspectionCamera.look(at: SCNVector3(0, 1.4, 0))
        scene.rootNode.addChildNode(inspectionCamera)
        targetMarker.name = "motionLabTarget"
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemYellow
        material.lightingModel = .constant
        material.fillMode = .lines
        targetMarker.geometry?.materials = [material]
        scene.rootNode.addChildNode(targetMarker)
        updateTargetMarker()
    }

    func updateTargetMarker() {
        let center = Float(295 * CombatData.sceneScale)
        targetMarker.simdPosition = PunchContactGeometry.target(engine.enemy, zone: .head)
            - SIMD3<Float>(center, -0.13, center)
    }
}

@MainActor
final class MotionLabModel: ObservableObject {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["RIVAL_MOTION_LAB"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-rival-motion-lab")
    }

    static let framesPerSecond = 60.0
    static let leadInFrames = 15
    @Published private(set) var run: MotionLabRun
    @Published private(set) var frame = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var failure: String?
    @Published private(set) var punch = MotionLabPunch.jab
    @Published private(set) var distance = MotionLabDistance.middle
    @Published private(set) var defense = MotionLabDefense.open
    @Published var speed = MotionLabSpeed.normal
    @Published var loops = true
    @Published var gameCamera = false
    @Published var showsTarget = false
    private var accumulatedTime = 0.0

    var endFrame: Int { Self.leadInFrames + Int(ceil(punch.spec.duration * Self.framesPerSecond)) + 30 }
    var contactFrame: Int { Self.leadInFrames + Int(ceil(punch.spec.activeStart * Self.framesPerSecond)) }
    var time: Double { Double(frame) / Self.framesPerSecond }
    var pointOfView: SCNNode { gameCamera ? run.scene.cameraNode : run.inspectionCamera }
    var separation: Double { run.engine.enemy.x - run.engine.player.x }
    var result: String {
        if let failure { return failure }
        for event in run.events {
            if case let .impact(impact) = event {
                return impact.guarded ? "BLOCK / \(impact.damage) damage" : "HIT / \(impact.damage) damage"
            }
            if case .dodge = event { return "DODGED" }
            if case .whiff = event { return "MISS" }
        }
        return frame <= Self.leadInFrames ? "READY" : "PENDING"
    }

    init() {
        run = MotionLabRun(punch: .jab, distance: .middle, defense: .open)
    }

    func configure(punch: MotionLabPunch, distance: MotionLabDistance, defense: MotionLabDefense) {
        pause()
        self.punch = punch
        self.distance = distance
        self.defense = defense
        rebuild()
    }

    func pause() {
        isPlaying = false
        accumulatedTime = 0
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            if frame == endFrame || failure != nil { rebuild() }
            isPlaying = true
        }
    }

    func seek(to requestedFrame: Int) {
        pause()
        let target = min(endFrame, max(0, requestedFrame))
        // Replaying the same seed also resets the production rig's stateful foot/pose solvers.
        if target < frame || failure != nil { rebuild() }
        while frame < target, failure == nil { step() }
    }

    func advance(realDeltaTime: Double) {
        guard isPlaying else { return }
        guard realDeltaTime.isFinite, realDeltaTime >= 0 else {
            fail("Invalid playback delta")
            return
        }
        accumulatedTime += min(0.1, realDeltaTime) * speed.multiplier
        let stepTime = 1 / Self.framesPerSecond
        while accumulatedTime + 0.0000001 >= stepTime, isPlaying {
            accumulatedTime = max(0, accumulatedTime - stepTime)
            if frame == endFrame {
                if loops { rebuild() } else { pause(); break }
            }
            step()
        }
    }

    private func rebuild() {
        run = MotionLabRun(punch: punch, distance: distance, defense: defense)
        frame = 0
        failure = nil
    }

    private func step() {
        if frame == Self.leadInFrames {
            guard run.engine.startAttack(run.engine.player, punch: punch.punch) else {
                fail("Production engine rejected \(punch.rawValue)")
                return
            }
        }
        if frame > Self.leadInFrames, run.engine.player.attack == nil {
            run.engine.setGuarding(true)
        }
        run.scene.update(at: 1 + Double(frame + 1) / Self.framesPerSecond)
        run.updateTargetMarker()
        frame += 1
    }

    private func fail(_ message: String) {
        failure = message
        print("RIVAL_MOTION_LAB FAILED: \(message)")
        pause()
    }
}

struct MotionLabView: View {
    @StateObject private var model = MotionLabModel()
    @State private var scrubbing = false
    @State private var scrubFrame = 0.0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("MOTION LAB / LIVE").font(.headline)
                Spacer()
                Text(model.result).monospaced().accessibilityIdentifier("motionLabResult")
            }
            HStack(spacing: 16) {
                MotionLabSceneView(model: model, active: scenePhase == .active)
                    .accessibilityIdentifier("motionLabScene")
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Punch", selection: Binding(get: { model.punch }, set: {
                            model.configure(punch: $0, distance: model.distance, defense: model.defense)
                        })) {
                            ForEach(MotionLabPunch.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("motionLabPunch")
                        Picker("Distance", selection: Binding(get: { model.distance }, set: {
                            model.configure(punch: model.punch, distance: $0, defense: model.defense)
                        })) {
                            ForEach(MotionLabDistance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Text(String(format: "Distance %.1f game units", model.separation)).font(.caption)
                        Picker("Defense", selection: Binding(get: { model.defense }, set: {
                            model.configure(punch: model.punch, distance: model.distance, defense: $0)
                        })) {
                            ForEach(MotionLabDefense.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.accessibilityIdentifier("motionLabDefense")
                        Toggle("Game camera", isOn: $model.gameCamera)
                        Toggle("Head contact volume", isOn: $model.showsTarget)
                        Text("Fixed dummy / no AI\nNo saves, rewards, audio or haptics.\nCurrent in-game procedural motion.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(width: 240)
            }
            VStack(spacing: 5) {
                HStack {
                    Text(String(format: "Frame %d / %d | %.3fs", model.frame, model.endFrame, model.time))
                        .accessibilityIdentifier("motionLabFrame")
                    Spacer()
                    Text(String(format: "Contact %.3fs | Active end %.3fs",
                        model.punch.spec.activeStart, model.punch.spec.activeEnd))
                }.font(.caption.monospaced())
                Slider(value: Binding(get: { scrubbing ? scrubFrame : Double(model.frame) }, set: {
                    if scrubbing { scrubFrame = $0 } else { model.seek(to: Int($0)) }
                }), in: 0...Double(model.endFrame), step: 1, onEditingChanged: { editing in
                    if editing {
                        scrubFrame = Double(model.frame)
                        model.pause()
                        scrubbing = true
                    } else {
                        scrubbing = false
                        model.seek(to: Int(scrubFrame))
                    }
                }).accessibilityIdentifier("motionLabTimeline")
                HStack(spacing: 14) {
                    Button("Reset") { model.seek(to: 0) }.accessibilityIdentifier("motionLabReset")
                    Button("-1 frame") { model.seek(to: model.frame - 1) }.accessibilityIdentifier("motionLabBack")
                    Button(model.isPlaying ? "Pause" : "Play") { model.togglePlayback() }
                        .accessibilityIdentifier("motionLabPlay")
                    Button("+1 frame") { model.seek(to: model.frame + 1) }.accessibilityIdentifier("motionLabForward")
                    Button("Contact") { model.seek(to: model.contactFrame) }.accessibilityIdentifier("motionLabContact")
                    Picker("Speed", selection: $model.speed) {
                        ForEach(MotionLabSpeed.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 180)
                    Toggle("Loop", isOn: $model.loops).fixedSize()
                }.font(.subheadline)
            }
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(Color(white: 0.07).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.pause() }
        }
        .onDisappear { model.pause() }
    }
}

private struct MotionLabSceneView: UIViewRepresentable {
    @ObservedObject var model: MotionLabModel
    let active: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== model.run.scene { view.scene = model.run.scene }
        view.pointOfView = model.pointOfView
        model.run.targetMarker.isHidden = !model.showsTarget
        view.rendersContinuously = active && model.isPlaying
        context.coordinator.configure(playing: active && model.isPlaying)
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.configure(playing: false)
        view.rendersContinuously = false
        view.scene = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        private let model: MotionLabModel
        private var displayLink: CADisplayLink?
        private var previousTime: TimeInterval?

        init(model: MotionLabModel) { self.model = model }

        func configure(playing: Bool) {
            if playing {
                guard displayLink == nil else { return }
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                link.add(to: .main, forMode: .common)
                displayLink = link
            } else {
                displayLink?.invalidate()
                displayLink = nil
                previousTime = nil
            }
        }

        @objc private func tick(_ link: CADisplayLink) {
            let delta = previousTime.map { link.timestamp - $0 } ?? 0
            previousTime = link.timestamp
            model.advance(realDeltaTime: delta)
        }
    }
}
#endif
