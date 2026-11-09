import SceneKit
import XCTest
@testable import RIVAL

@MainActor
final class AttackConnectionMotionTests: XCTestCase {
    private let punches: [Punch] = [.jab, .cross, .leftHook, .cross]
    private let moves: [(String, SIMD2<Double>)] = [
        ("standing", .zero), ("advance", SIMD2(1, 0)), ("retreat", SIMD2(-1, 0)),
        ("left", SIMD2(0, -1)), ("right", SIMD2(0, 1)),
    ]

    func testHandsRecoverBeforeSupportFinishesWithoutExtendingAttack() throws {
        for punch in Punch.allCases {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let time = (spec.recoveryEnd + spec.duration) * 0.5
            let motion = PunchMotion.sample(punch, progress: Float(time / spec.duration))
            XCTAssertEqual(motion.reach, 0)
            XCTAssertEqual(motion.shoulderDrive, 0)
            XCTAssertGreaterThan(motion.hipDrive, 0.001)
            XCTAssertGreaterThan(motion.footDrive, 0.001)
            XCTAssertEqual(PunchMotion.sample(punch, progress: 0), PunchMotion())
            XCTAssertEqual(PunchMotion.sample(punch, progress: 1), PunchMotion())
        }
        for punch in [Punch.leftBody, .rightBody, .leftUppercut, .rightUppercut] {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let motion = PunchMotion.sample(punch,
                progress: Float((spec.recoveryEnd + spec.duration) * 0.5 / spec.duration), defensiveCrouch: 0.40)
            XCTAssertEqual(motion.hipDrive, 0)
            XCTAssertEqual(motion.footDrive, 0)
        }
    }

    func testMovingFeetFinishBeforeContactAndStayPlantedAtEveryFrameRate() throws {
        let rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        for fps in [20, 30, 60, 120] {
            let dt = 1.0 / Double(fps)
            for direction in [SIMD3<Float>(1, 0, 0), SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 0, -1)] {
                for punch in [Punch.jab, .cross, .leftHook, .rightHook] {
                    let spec = try XCTUnwrap(CombatData.attacks[punch])
                    let pose = FightPose.neutral(stride: 0)
                    var plant = FootPlantMotion()
                    var root = SIMD3<Float>.zero
                    _ = plant.sample(rootPosition: root, rootRotation: rotation,
                        left: pose.leftFoot, right: pose.rightFoot, deltaTime: dt, moving: false)
                    for _ in 0..<max(1, Int(0.20 / dt)) {
                        root += direction * Float(dt * 4)
                        _ = plant.sample(rootPosition: root, rootRotation: rotation,
                            left: pose.leftFoot, right: pose.rightFoot, deltaTime: dt, moving: true)
                    }
                    var previous: FootPlantMotion.Feet?
                    var contacts = 0
                    for frame in 1...Int(ceil(spec.activeEnd / dt)) {
                        let time = Double(frame) * dt
                        let feet = plant.sample(rootPosition: root, rootRotation: rotation,
                            left: pose.leftFoot, right: pose.rightFoot, deltaTime: dt, moving: false,
                            plantBy: spec.activeStart - time)
                        XCTAssertEqual(min(feet.left.y - pose.leftFoot.y, feet.right.y - pose.rightFoot.y),
                            0, accuracy: 0.000001)
                        XCTAssertGreaterThanOrEqual(feet.left.x - feet.right.x, 0.2599)
                        if time >= spec.activeStart - 1e-10 {
                            XCTAssertEqual(feet.left.y, pose.leftFoot.y, accuracy: 0.000001)
                            XCTAssertEqual(feet.right.y, pose.rightFoot.y, accuracy: 0.000001)
                            if let previous {
                                XCTAssertEqual(feet.left, previous.left)
                                XCTAssertEqual(feet.right, previous.right)
                            }
                            previous = feet
                            contacts += 1
                        }
                    }
                    XCTAssertGreaterThan(contacts, 0)
                }
            }
        }
    }

    func testPlantPauseResetAndReducedMotionKeepCurrentContact() {
        let pose = FightPose.neutral(stride: 0)
        for reduced in [false, true] {
            var plant = FootPlantMotion()
            let rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            _ = plant.sample(rootPosition: .zero, rootRotation: rotation, left: pose.leftFoot,
                right: pose.rightFoot, deltaTime: 1.0 / 60, moving: false)
            let root = SIMD3<Float>(0.4, 0, 0)
            let moving = plant.sample(rootPosition: root, rootRotation: rotation, left: pose.leftFoot,
                right: pose.rightFoot, deltaTime: 1.0 / 60, moving: true, reducedMotion: reduced)
            let paused = plant.sample(rootPosition: root, rootRotation: rotation, left: pose.leftFoot,
                right: pose.rightFoot, deltaTime: 0, moving: false, reducedMotion: reduced, plantBy: 0.08)
            XCTAssertEqual(paused.left, moving.left)
            XCTAssertEqual(paused.right, moving.right)
            let prepared = plant.sample(rootPosition: root, rootRotation: rotation, left: pose.leftFoot,
                right: pose.rightFoot, deltaTime: 1.0 / 60, moving: false, reducedMotion: reduced,
                plantBy: 0.08 - 1.0 / 60)
            XCTAssertLessThanOrEqual(max(prepared.left.y - pose.leftFoot.y, prepared.right.y - pose.rightFoot.y),
                reduced ? 0.025001 : 0.065001)
            let reset = plant.sample(rootPosition: root, rootRotation: rotation, left: pose.leftFoot,
                right: pose.rightFoot, deltaTime: 1.0 / 60, moving: false, reset: true, reducedMotion: reduced)
            XCTAssertEqual(reset.left, pose.leftFoot)
            XCTAssertEqual(reset.right, pose.rightFoot)
        }
    }

    func testSequentialPunchesKeepOriginalStartGatesAndCosts() throws {
        for style in FightStyle.allCases {
            let fixture = DefensivePunchFixture(punch: .leftHook, style: style, distanceFraction: 1.05)
            for punch in punches {
                let spec = try XCTUnwrap(CombatData.attacks[punch])
                let before = fixture.engine.player.stamina
                XCTAssertTrue(fixture.engine.startAttack(fixture.engine.player, punch: punch))
                XCTAssertEqual(fixture.engine.player.stamina,
                    before - spec.staminaCost * style.punchStaminaMultiplier, accuracy: 0.000001)
                for _ in 0..<Int(spec.duration * 1_000 - 1) { fixture.advance(0.001) }
                let charged = fixture.engine.player.stamina
                XCTAssertFalse(fixture.engine.startAttack(fixture.engine.player, punch: .jab))
                XCTAssertEqual(fixture.engine.player.stamina, charged)
                fixture.advance(0.002)
                XCTAssertNil(fixture.engine.player.attack)
            }
        }
    }

    func testLowEntriesKeepSupportTimingWithoutASnapNearStanding() throws {
        for punch in [Punch.jab, .cross, .leftHook, .rightHook] {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let progress = Float((spec.recoveryEnd + spec.duration) * 0.5 / spec.duration)
            let low = PunchMotion.sample(punch, progress: progress, defensiveCrouch: 0.40)
            XCTAssertEqual(low.hipDrive, 0)
            XCTAssertEqual(low.footDrive, 0)
            for frame in 0...120 {
                let time = Float(frame) / 120
                let standing = PunchMotion.sample(punch, progress: time)
                let ducked = PunchMotion.sample(punch, progress: time, defensiveCrouch: 0.40)
                XCTAssertEqual(ducked.reach, standing.reach)
                XCTAssertEqual(ducked.torsoDrive, standing.torsoDrive)
                XCTAssertEqual(ducked.shoulderDrive, standing.shoulderDrive)
                XCTAssertEqual(ducked.defensiveRise, standing.defensiveRise)
            }
            var previous = PunchMotion.sample(punch, progress: progress)
            for step in 1...400 {
                let motion = PunchMotion.sample(punch, progress: progress,
                    defensiveCrouch: Float(step) * 0.0001)
                XCTAssertLessThan(abs(motion.hipDrive - previous.hipDrive), 0.01)
                XCTAssertLessThan(abs(motion.footDrive - previous.footDrive), 0.01)
                previous = motion
            }
        }
    }

    func testMovingAttackRendererKeepsHeadAndContactFeetAligned() throws {
        for style in FightStyle.allCases {
            for (name, move) in moves where name != "standing" {
                _ = try run(style: style, move: move, distance: 0.85, defense: "none",
                    renders: true, name: name, captures: false, validatesContact: true, leadTime: 1.0 / 60)
            }
        }
    }

    private func bottom(_ node: SCNNode) -> Float {
        let box = node.boundingBox
        return [box.min.x, box.max.x].flatMap { x in
            [box.min.y, box.max.y].flatMap { y in
                [box.min.z, box.max.z].map { z in
                    node.simdConvertPosition(SIMD3(x, y, z), to: nil).y
                }
            }
        }.min()!
    }

    private func run(style: FightStyle, move: SIMD2<Double>, distance: Double, defense: String,
                     renders: Bool, name: String, captures: Bool = true,
                     validatesContact: Bool = false, leadTime: Double = 0.20) throws -> [String: String] {
        let fixture = DefensivePunchFixture(punch: .leftHook, style: style,
            distanceFraction: distance, renders: renders)
        fixture.engine.setMove(x: move.x, y: move.y)
        fixture.engine.enemy.guarding = defense == "guard"
        fixture.engine.enemy.duckDirection = defense == "left" ? -1 : (defense == "right" ? 1 : 0)
        fixture.advance(0)
        let renderer: SCNRenderer?
        let left: SCNNode?
        let right: SCNNode?
        let head: SCNNode?
        if renders {
            let view = SCNRenderer(device: nil, options: nil)
            view.scene = fixture.scene
            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 42
            camera.simdPosition = SIMD3(0.15, 2.0, 5.7)
            camera.look(at: SCNVector3(0, 1.35, 0))
            fixture.scene.rootNode.addChildNode(camera)
            view.pointOfView = camera
            renderer = view
            left = try XCTUnwrap(fixture.scene.rootNode.childNode(withName: "playerLeftFoot", recursively: true))
            right = try XCTUnwrap(fixture.scene.rootNode.childNode(withName: "playerRightFoot", recursively: true))
            head = try XCTUnwrap(fixture.scene.rootNode.childNode(withName: "playerHead", recursively: true))
        } else {
            renderer = nil
            left = nil
            right = nil
            head = nil
        }
        var index = 0
        var minimumStamina = 100.0
        var starts: [String] = []
        var samples: [[String: String]] = []
        var lastMovement = 0.0
        let dt = renders ? 1.0 / 60 : 1.0 / 120
        for frame in 0..<(renders ? 120 : 240) {
            if fixture.elapsed >= leadTime - 1e-10, fixture.engine.player.attack == nil, index < punches.count {
                if validatesContact, index == 0 { XCTAssertGreaterThan(lastMovement, 0.05) }
                XCTAssertTrue(fixture.engine.startAttack(fixture.engine.player, punch: punches[index]))
                starts.append("\(fixture.elapsed)")
                index += 1
            }
            let position = SIMD2(fixture.engine.player.x, fixture.engine.player.y)
            fixture.advance(dt)
            lastMovement = simd_distance(position, SIMD2(fixture.engine.player.x, fixture.engine.player.y))
            minimumStamina = min(minimumStamina, fixture.engine.player.stamina)
            if let renderer, let left, let right, let head {
                let player = fixture.engine.player
                samples.append(["frame": "\(frame)", "punch": player.attack?.rawValue ?? "none",
                    "time": "\(player.actionTime)", "leftY": "\(bottom(left))", "rightY": "\(bottom(right))",
                    "headY": "\(head.simdWorldPosition.y)",
                    "contactHeadY": "\(PunchContactGeometry.target(player, zone: .head).y + 0.13)"])
                if validatesContact, let punch = player.attack, let spec = CombatData.attacks[punch],
                   player.actionTime >= spec.activeStart, player.actionTime <= spec.activeEnd {
                    let context = "\(style)/\(name)/\(punch)/\(player.actionTime)"
                    XCTAssertLessThan(abs(head.simdWorldPosition.y
                        - PunchContactGeometry.target(player, zone: .head).y - 0.13), 0.015, context)
                    XCTAssertEqual(bottom(left), 0.1225, accuracy: 0.005, context)
                    XCTAssertEqual(bottom(right), 0.1225, accuracy: 0.005, context)
                }
                if captures, frame.isMultiple(of: 2) {
                    let image = renderer.snapshot(atTime: fixture.elapsed, with: CGSize(width: 960, height: 540),
                        antialiasingMode: .multisampling4X)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = String(format: "connection-%@-%03d", name, frame)
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
        XCTAssertEqual(index, punches.count)
        if renders, captures {
            try attach(samples, name: "connection-\(name)-samples")
        }
        let outcomes = fixture.events.compactMap { event -> String? in
            switch event {
            case .impact(let impact): return "\(impact.punch.rawValue):\(impact.damage):\(impact.guarded)"
            case .dodge: return "dodged"
            case .whiff: return "miss"
            default: return nil
            }
        }
        return ["style": style.rawValue, "distance": "\(distance)", "defense": defense,
            "outcomes": outcomes.joined(separator: ","), "starts": starts.joined(separator: ","),
            "hp": "\(fixture.engine.enemy.hp)", "stamina": "\(minimumStamina)",
            "x": "\(fixture.engine.player.x)", "y": "\(fixture.engine.player.y)"]
    }

    private func attach<T: Encodable>(_ value: T, name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(value), uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureConnectionsAndActualCombatOutcomes() throws {
        var outcomes: [[String: String]] = []
        for style in FightStyle.allCases {
            for (name, move) in moves {
                for distance in [0.65, 0.85, 1.05] {
                    for defense in ["none", "guard", "left", "right"] {
                        var result = try run(style: style, move: move, distance: distance,
                            defense: defense, renders: false, name: name)
                        result["move"] = name
                        outcomes.append(result)
                    }
                }
            }
        }
        try attach(outcomes, name: "connection-combat-outcomes")
        for (name, move) in moves where ["standing", "advance", "right"].contains(name) {
            _ = try run(style: .standard, move: move, distance: 0.85,
                defense: "none", renders: true, name: name)
        }
    }
}
