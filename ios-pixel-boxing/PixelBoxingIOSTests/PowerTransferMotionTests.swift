import SceneKit
import XCTest
@testable import RIVAL

@MainActor
final class PowerTransferMotionTests: XCTestCase {
    private let punches: [Punch] = [.leftBody, .rightBody, .leftUppercut, .rightUppercut, .leftHook, .rightHook]

    func testBodyLoadsOnceAndHoldsTheExistingContactHeight() throws {
        for punch in [Punch.leftBody, .rightBody] {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            var previous: Float = 0
            for frame in 0...120 {
                let time = spec.activeStart * Double(frame) / 120
                let motion = PunchMotion.sample(punch, progress: Float(time / spec.duration))
                XCTAssertGreaterThanOrEqual(motion.legDrop, previous - 0.000001)
                XCTAssertLessThanOrEqual(motion.legDrop, 0.117001)
                if time >= spec.deliveryStart * 0.55 {
                    XCTAssertEqual(motion.legDrop, 0.117, accuracy: 0.000001)
                }
                previous = motion.legDrop
            }
            for time in [spec.activeStart, spec.activeEnd] {
                let motion = PunchMotion.sample(punch, progress: Float(time / spec.duration))
                XCTAssertEqual(motion.legDrop, 0.117 * motion.torsoDrive, accuracy: 0.000001)
            }
        }
    }

    func testUppercutUnloadsBeforeGloveArrivesWithoutJumping() throws {
        for punch in [Punch.leftUppercut, .rightUppercut] {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            let release = spec.deliveryStart + (spec.activeStart - spec.deliveryStart) * 0.55
            let motion = PunchMotion.sample(punch, progress: Float(release / spec.duration))
            XCTAssertEqual(motion.legDrop, 0, accuracy: 0.000001)
            XCTAssertLessThan(motion.reach, 0.9)
            XCTAssertEqual(motion.footDrive, 1, accuracy: 0.000001)
            for frame in 0...120 {
                let motion = PunchMotion.sample(punch, progress: Float(frame) / 120)
                XCTAssertGreaterThanOrEqual(motion.legDrop, 0)
                XCTAssertLessThanOrEqual(motion.legDrop, 0.160001)
            }
        }
    }

    func testStandingFootAndHipLeadTheChestAndSettleAfterTheHands() throws {
        for punch in punches {
            let spec = try XCTUnwrap(CombatData.attacks[punch])
            func peaks(crouch: Float) -> [Int] {
                let samples = (0...1_000).map {
                    PunchMotion.sample(punch, progress: Float(spec.activeStart / spec.duration) * Float($0) / 1_000,
                        defensiveCrouch: crouch)
                }
                return [samples.firstIndex { $0.footDrive >= 0.99999 } ?? 1_001,
                    samples.firstIndex { $0.hipDrive >= 0.99999 } ?? 1_001,
                    samples.firstIndex { $0.torsoDrive >= 0.99999 } ?? 1_001]
            }
            let standing = peaks(crouch: 0), low = peaks(crouch: 0.4)
            XCTAssertLessThan(standing[0], standing[1])
            XCTAssertLessThan(standing[1], standing[2])
            XCTAssertLessThan(standing[0], low[0])
            XCTAssertLessThan(standing[1], low[1])
            XCTAssertEqual(standing[2], low[2])
            let late = Float((spec.recoveryEnd + spec.duration) * 0.5 / spec.duration)
            let motion = PunchMotion.sample(punch, progress: late)
            XCTAssertEqual(motion.reach, 0)
            XCTAssertEqual(motion.shoulderDrive, 0)
            XCTAssertGreaterThan(motion.hipDrive, 0.001)
            XCTAssertGreaterThan(motion.footDrive, 0.001)
            XCTAssertEqual(PunchMotion.sample(punch, progress: 0), PunchMotion())
            XCTAssertEqual(PunchMotion.sample(punch, progress: 1), PunchMotion())
        }
    }

    func testLowEntriesRetainTheirOriginalLoweringAndUpperBodyChannels() throws {
        for punch in punches {
            let family = try XCTUnwrap(CombatData.attacks[punch]).family
            for crouch in [Float(0.04), 0.10, 0.40] {
                for frame in 0...120 {
                    let progress = Float(frame) / 120
                    let motion = PunchMotion.sample(punch, progress: progress, defensiveCrouch: crouch)
                    let standing = PunchMotion.sample(punch, progress: progress)
                    let expected: Float
                    switch family {
                    case .body: expected = max(0, 0.18 - crouch) * max(motion.hipLoad, motion.torsoDrive * 0.65)
                    case .uppercut: expected = max(0, 0.16 - crouch) * motion.hipLoad
                    case .hook: expected = max(0, 0.045 - crouch) * motion.hipLoad
                    case .straight: expected = 0
                    }
                    XCTAssertEqual(motion.legDrop, expected, accuracy: 0.000001)
                    XCTAssertEqual(motion.reach, standing.reach)
                    XCTAssertEqual(motion.torsoDrive, standing.torsoDrive)
                    XCTAssertEqual(motion.shoulderDrive, standing.shoulderDrive)
                    XCTAssertEqual(motion.defensiveRise, standing.defensiveRise)
                }
            }
        }
    }

    func testPowerLoadKeepsFeetAndAnatomyContinuousAcrossFrameRates() {
        let rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        for style in FightStyle.allCases {
            for punch in punches {
                for fps in [20, 30, 60, 120] {
                    var previous: Float = 0
                    for frame in 0...fps {
                        let progress = Float(frame) / Float(fps)
                        var pose = FightPose.neutral(stride: 0, style: style)
                        let base = pose
                        pose.applyAttack(punch, progress: progress)
                        XCTAssertEqual(pose.leftFoot, base.leftFoot)
                        XCTAssertEqual(pose.rightFoot, base.rightFoot)
                        XCTAssertEqual(pose.rootY, 0)
                        XCTAssertEqual(pose.rootZ, 0)
                        let drop = pose.bodyDrop
                        XCTAssertTrue(drop.isFinite)
                        XCTAssertLessThan(abs(drop - previous), 0.17)
                        previous = drop
                        pose.resolveContactSupport(rootPosition: .zero, rootRotation: rotation)
                        for (root, joint, end) in [(pose.leftShoulder, pose.leftElbow, pose.leftGlove),
                                                  (pose.rightShoulder, pose.rightElbow, pose.rightGlove)] {
                            XCTAssertEqual(simd_distance(root, joint), 0.4, accuracy: 0.0001)
                            XCTAssertEqual(simd_distance(joint, end), 0.58, accuracy: 0.0001)
                        }
                    }
                }
            }
        }
    }

    private struct Frame: Encodable {
        let time: Double
        let points: [String: [Float]]
        let metrics: [String: Float]
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

    private func attach<T: Encodable>(_ value: T, name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let attachment = XCTAttachment(data: try encoder.encode(value), uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func single(punch: Punch, style: FightStyle, distance: Double, low: Bool,
                        defense: String, capture: Bool = false) throws -> [String: String] {
        let fixture = DefensivePunchFixture(punch: punch, style: style,
            distanceFraction: distance, renders: capture)
        fixture.engine.enemy.guarding = defense == "guard"
        fixture.engine.enemy.duckDirection = defense == "left" ? -1 : (defense == "right" ? 1 : 0)
        if low { fixture.enter(.duck, punch: punch) }
        fixture.advance(0)
        for _ in 0..<18 { fixture.advance(1.0 / 120) }
        XCTAssertTrue(fixture.engine.startAttack(fixture.engine.player, punch: punch))
        let renderer: SCNRenderer?
        if capture {
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
        } else {
            renderer = nil
        }
        var frames: [Frame] = []
        var minimumStamina = fixture.engine.player.stamina
        for frame in 0..<(capture ? 54 : 108) {
            fixture.advance(capture ? 1.0 / 60 : 1.0 / 120)
            minimumStamina = min(minimumStamina, fixture.engine.player.stamina)
            if let renderer {
                var points: [String: [Float]] = [:]
                for prefix in ["player", "rival"] {
                    for part in ["Head", "Torso", "Pelvis", "LeftGlove", "RightGlove", "LeftFoot", "RightFoot"] {
                        let node = try XCTUnwrap(fixture.scene.rootNode.childNode(
                            withName: prefix + part, recursively: true))
                        let p = node.simdWorldPosition
                        points[prefix + part] = [p.x, p.y, p.z]
                        if prefix == "player", part.hasSuffix("Foot") {
                            XCTAssertEqual(bottom(node), 0.1225, accuracy: 0.005, "\(punch)/\(frame)/\(part)")
                        }
                    }
                }
                let player = fixture.engine.player
                let sharedHead = PunchContactGeometry.target(player, zone: .head)
                let renderedHead = try XCTUnwrap(points["playerHead"])
                XCTAssertLessThan(abs(renderedHead[1] - sharedHead.y - 0.13), 0.015, "\(punch)/\(frame)")
                let pose = PunchContactGeometry.samplePose(player)
                frames.append(Frame(time: fixture.elapsed, points: points,
                    metrics: ["bodyDrop": pose.bodyDrop, "hipYaw": pose.hipYaw, "torsoYaw": pose.torsoYaw,
                        "leftFootYaw": pose.leftFootYaw, "rightFootYaw": pose.rightFootYaw,
                        "leftFootPitch": pose.leftFootPitch, "rightFootPitch": pose.rightFootPitch]))
                if frame.isMultiple(of: 2) {
                    let image = renderer.snapshot(atTime: fixture.elapsed, with: CGSize(width: 960, height: 540),
                        antialiasingMode: .multisampling4X)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = String(format: "power-%@-%03d", punch.rawValue, frame)
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
        if capture { try attach(frames, name: "power-\(punch.rawValue)-points") }
        XCTAssertNotEqual(fixture.result, "unresolved")
        return ["punch": punch.rawValue, "style": style.rawValue, "distance": "\(distance)",
            "low": "\(low)", "defense": defense, "result": fixture.result,
            "hp": "\(fixture.engine.enemy.hp)", "stamina": "\(minimumStamina)",
            "x": "\(fixture.engine.player.x)", "y": "\(fixture.engine.player.y)"]
    }

    private func exchange(punch: Punch, incoming: Punch, style: FightStyle,
                          distance: Double, offset: Double) -> [String: String] {
        let fixture = DefensivePunchFixture(punch: punch, style: style, distanceFraction: distance)
        let playerTime = 0.15
        let enemyTime = playerTime + offset
        var playerStarted = false, enemyStarted = false
        var starts: [String] = []
        while fixture.elapsed < 0.95 - 1e-10 {
            if !playerStarted, fixture.elapsed >= playerTime - 1e-10 {
                starts.append("player:\(fixture.engine.startAttack(fixture.engine.player, punch: punch))")
                playerStarted = true
            }
            if !enemyStarted, fixture.elapsed >= enemyTime - 1e-10 {
                fixture.engine.enemy.stagger = 0
                starts.append("enemy:\(fixture.engine.startAttack(fixture.engine.enemy, punch: incoming))")
                fixture.engine.enemy.stagger = 1_000
                enemyStarted = true
            }
            let boundary = min(playerStarted ? 0.95 : playerTime, enemyStarted ? 0.95 : enemyTime)
            fixture.advance(min(1.0 / 120, boundary - fixture.elapsed))
        }
        let events = fixture.events.compactMap { event -> String? in
            switch event {
            case .impact(let hit): return "\(hit.attacker):\(hit.punch.rawValue):\(hit.damage):\(hit.guarded)"
            case .whiff(let fighter): return "\(fighter):miss"
            case .dodge(let fighter, _): return "\(fighter):dodged"
            default: return nil
            }
        }
        return ["punch": punch.rawValue, "incoming": incoming.rawValue, "style": style.rawValue,
            "distance": "\(distance)", "offset": "\(offset)", "starts": starts.joined(separator: ","),
            "events": events.joined(separator: ","), "hp": "\(fixture.engine.player.hp)",
            "enemyHP": "\(fixture.engine.enemy.hp)"]
    }

    func testCapturePowerTransferAndCombatOutcomes() throws {
        var singles: [[String: String]] = []
        var exchanges: [[String: String]] = []
        for style in FightStyle.allCases {
            for punch in punches {
                for distance in [0.65, 0.85, 1.05] {
                    for low in [false, true] {
                        for defense in ["none", "guard", "left", "right"] {
                            singles.append(try single(punch: punch, style: style, distance: distance,
                                low: low, defense: defense))
                        }
                    }
                }
                for incoming in [Punch.jab, .cross, .leftBody] {
                    for distance in [0.65, 0.85] {
                        for offset in [-0.08, -0.04, 0, 0.04, 0.08] {
                            exchanges.append(exchange(punch: punch, incoming: incoming, style: style,
                                distance: distance, offset: offset))
                        }
                    }
                }
            }
        }
        try attach(singles, name: "power-single-outcomes")
        try attach(exchanges, name: "power-exchange-outcomes")
        for punch in punches {
            _ = try single(punch: punch, style: .standard, distance: 0.65,
                low: false, defense: "none", capture: true)
        }
    }
}
