import QuartzCore
@preconcurrency import SceneKit
import SwiftUI
import UIKit

enum ArenaCinematicPresentation {
    case matchIntro
    case appOpening
}

private struct CinematicFighterState {
    let x: Double
    let y: Double
    let facingX: Double
    let facingY: Double
    let attack: Punch?
    let actionTime: Double
    let guarding: Bool
    let duckDirection: Int
    let hitReaction: Double

    init(_ fighter: FighterModel) {
        x = fighter.x
        y = fighter.y
        facingX = fighter.facingX
        facingY = fighter.facingY
        attack = fighter.attack
        actionTime = fighter.actionTime
        guarding = fighter.guarding
        duckDirection = fighter.duckDirection
        hitReaction = fighter.hitReaction
    }

    func restore(to fighter: FighterModel) {
        fighter.x = x
        fighter.y = y
        fighter.facingX = facingX
        fighter.facingY = facingY
        fighter.attack = attack
        fighter.actionTime = actionTime
        fighter.guarding = guarding
        fighter.duckDirection = duckDirection
        fighter.hitReaction = hitReaction
    }
}

@MainActor
final class Arena3DScene: SCNScene {
    weak var controller: GameController?
    let cameraNode = SCNNode()

    /// TEMP (icon/splash capture only): when set, pulls the two fighters closer together and locks the
    /// camera to a tight face-off framing instead of the normal dynamic tracking shot, so a single
    /// screenshot can be cropped into app icon / loading screen art. Remove once art is captured.
    static let isIconCaptureMode = ProcessInfo.processInfo.environment["RIVAL_ICON_CAPTURE"] != nil

    private let engine: CombatEngine
    private let playerRig: BoxerRig
    private let enemyRig: BoxerRig
    private var lastUpdateTime = 0.0
    private var publishTimer = 0.0
    private var cameraTarget = SIMD3<Float>(0, 1.35, 0)
    private var cameraForward = SIMD3<Float>(1, 0, 0)
    private var previousPlayerHP = 100
    private var previousEnemyHP = 100
    private var impactTimer = 0.0
    private var impactStrength: Float = 0
    private var impactPhase: Float = 0
    private var cinematicMode = false
    private var cinematicElapsed = 0.0
    private var cinematicPresentation = ArenaCinematicPresentation.matchIntro
    private var openingPlayerState: CinematicFighterState?
    private var openingEnemyState: CinematicFighterState?
    private var openingImpactPulse: Float = 0

    private var usesOpeningCaptureBeat: Bool {
        ProcessInfo.processInfo.environment["RIVAL_OPENING_CAPTURE_BEAT"] == "1"
    }

    init(engine: CombatEngine) {
        self.engine = engine
        playerRig = BoxerRig(team: .player)
        enemyRig = BoxerRig(team: .rival)
        super.init()
        background.contents = UIColor(red: 0.018, green: 0.028, blue: 0.055, alpha: 1)
        fogColor = UIColor(red: 0.025, green: 0.035, blue: 0.065, alpha: 1)
        fogStartDistance = 19
        fogEndDistance = 34
        buildArena()
        buildLighting()
        buildCamera()
        rootNode.addChildNode(playerRig.root)
        rootNode.addChildNode(enemyRig.root)
        if Arena3DScene.isIconCaptureMode {
            engine.player.x = 235
            engine.player.y = 295
            engine.enemy.x = 355
            engine.enemy.y = 295
            // The over-the-shoulder capture camera sits extremely close behind ME's own shoulder. ME's
            // own floating nameplate (normally a small plate hovering above the head, harmless at normal
            // camera distances) has no depth test and a high rendering order, so at this close range it
            // balloons across the screen and reads as an ugly solid black slab over the back/shoulder.
            // It's redundant anyway (nobody needs to see their own nameplate hovering behind their own
            // head), so just hide it for this capture framing.
            playerRig.root.childNode(withName: "playerIdentityLabel", recursively: false)?.isHidden = true
        }
        if let savedOutfit = UserDefaults.standard.string(forKey: "pixelBoxingEquippedOutfit"),
           let outfit = OutfitID(rawValue: savedOutfit) {
            playerRig.applyOutfit(outfit)
        }
        synchronizeVisuals(deltaTime: 1.0 / 60.0, elapsedTime: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Recolors the player's rig to reflect a newly equipped outfit choice.
    func setPlayerOutfit(_ outfit: OutfitID) {
        playerRig.applyOutfit(outfit)
    }

    func setCinematicMode(_ active: Bool, presentation: ArenaCinematicPresentation = .matchIntro) {
        let wasAppOpening = cinematicMode && cinematicPresentation == .appOpening
        if active && presentation == .appOpening && openingPlayerState == nil {
            openingPlayerState = CinematicFighterState(engine.player)
            openingEnemyState = CinematicFighterState(engine.enemy)
        }
        if !active && wasAppOpening {
            openingPlayerState?.restore(to: engine.player)
            openingEnemyState?.restore(to: engine.enemy)
            openingPlayerState = nil
            openingEnemyState = nil
            openingImpactPulse = 0
        }
        cinematicMode = active
        cinematicElapsed = 0
        cinematicPresentation = presentation
        let hidesIdentityLabels = active && presentation == .appOpening
        playerRig.root.childNode(withName: "playerIdentityLabel", recursively: false)?.isHidden = hidesIdentityLabels || Arena3DScene.isIconCaptureMode
        enemyRig.root.childNode(withName: "rivalIdentityLabel", recursively: false)?.isHidden = hidesIdentityLabels
    }

    func update(at time: TimeInterval) {
        let deltaTime = lastUpdateTime == 0 ? 1.0 / 60.0 : min(0.05, time - lastUpdateTime)
        lastUpdateTime = time
        if cinematicMode {
            cinematicElapsed += deltaTime
        } else {
            controller?.synchronizeHeldControls()
            engine.update(deltaTime: deltaTime)
            updateImpact(deltaTime: deltaTime)
        }
        synchronizeVisuals(deltaTime: deltaTime, elapsedTime: time)

        if !cinematicMode {
            publishTimer += deltaTime
            if publishTimer >= 0.08 {
                publishTimer = 0
                controller?.publishSnapshot()
            }
        }
    }

    private func updateImpact(deltaTime: Double) {
        let playerDamage = max(0, previousPlayerHP - engine.player.hp)
        let enemyDamage = max(0, previousEnemyHP - engine.enemy.hp)
        let damage = max(playerDamage, enemyDamage)
        previousPlayerHP = engine.player.hp
        previousEnemyHP = engine.enemy.hp

        if damage > 0 {
            impactTimer = 0.17
            impactStrength = min(1.35, 0.38 + Float(damage) / 17)
            impactPhase = 0
        } else {
            impactTimer = max(0, impactTimer - deltaTime)
            impactPhase += Float(deltaTime) * 84
        }
    }

    private func synchronizeVisuals(deltaTime: Double, elapsedTime: TimeInterval) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        if cinematicMode && cinematicPresentation == .appOpening {
            updateAppOpeningChoreography()
        }
        playerRig.update(from: engine.player, deltaTime: deltaTime, elapsedTime: elapsedTime)
        enemyRig.update(from: engine.enemy, deltaTime: deltaTime, elapsedTime: elapsedTime)
        if cinematicMode {
            updateCinematicCamera()
        } else {
            updateCamera(deltaTime: deltaTime)
        }
        SCNTransaction.commit()
    }

    private func buildCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 50
        camera.zNear = 0.08
        camera.zFar = 70
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = true
        camera.exposureOffset = -0.25
        camera.bloomIntensity = 0.22
        camera.bloomThreshold = 1.15
        camera.bloomBlurRadius = 5
        cameraNode.name = "shoulderCamera"
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3<Float>(-8.2, 5.25, 1.05)
        cameraNode.look(at: SCNVector3(cameraTarget), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        rootNode.addChildNode(cameraNode)
    }

    private func updateCamera(deltaTime: Double) {
        if Arena3DScene.isIconCaptureMode {
            // Over-the-shoulder face-off framing (user-approved): sit just behind/above ME's shoulder and
            // look across at RIVAL, so the two rigs clearly read as confronting each other in the ring
            // (ME close in the foreground, RIVAL smaller in the distance with guard raised toward ME) —
            // like real fight-poster staredown photography.
            let playerPos = worldPosition(engine.player)
            let enemyPos = worldPosition(engine.enemy)
            let behindSign: Float = playerPos.x <= enemyPos.x ? -1 : 1
            let camPos = SIMD3<Float>(
                playerPos.x + behindSign * 0.95,
                1.95,
                playerPos.z - 1.55
            )
            let lookTarget = SIMD3<Float>(enemyPos.x, 1.68, enemyPos.z)
            cameraNode.simdPosition = camPos
            cameraNode.look(at: SCNVector3(lookTarget), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            return
        }
        let player = worldPosition(engine.player)
        let enemy = worldPosition(engine.enemy)
        let separation = simd_distance(player, enemy)
        var desiredForward = enemy - player
        desiredForward.y = 0
        if simd_length(desiredForward) > 0.001 {
            desiredForward = simd_normalize(desiredForward)
        } else {
            desiredForward = cameraForward
        }
        cameraForward = stabilizedCameraForward(
            current: cameraForward,
            desired: desiredForward,
            separation: separation,
            deltaTime: deltaTime
        )
        let forward = cameraForward
        let right = SIMD3<Float>(forward.z, 0, -forward.x)

        let spread = min(1, max(0, (separation - 2.0) / 5.0))
        let focusPull = 0.34 + 0.24 * spread
        let midpoint = (player + enemy) * 0.5
        var target = player * Float(1 - focusPull) + midpoint * Float(focusPull)
        target += right * 0.16
        target.y = 1.42

        var distance = 6.75 + 1.55 * Float(spread)
        if separation < 2.25 { distance -= 0.22 }
        if engine.player.attack != nil { target += forward * 0.18 }
        let shoulderOffset: Float = separation < 2.6 ? 1.32 : 1.05
        var desiredPosition = player - forward * distance + right * shoulderOffset + SIMD3<Float>(0, 5.05, 0)
        if impactTimer > 0 {
            let decay = Float(impactTimer / 0.17)
            let impulse = impactStrength * decay * decay
            desiredPosition += right * sin(impactPhase) * 0.10 * impulse
            desiredPosition.y += cos(impactPhase * 1.37) * 0.055 * impulse
            target += forward * 0.045 * impulse
        }

        let positionBlend = Float(1 - exp(-deltaTime * 5.5))
        let targetBlend = Float(1 - exp(-deltaTime * 7.0))
        cameraNode.simdPosition += (desiredPosition - cameraNode.simdPosition) * positionBlend
        cameraTarget += (target - cameraTarget) * targetBlend
        cameraNode.look(at: SCNVector3(cameraTarget), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }

    private func updateCinematicCamera() {
        let player = worldPosition(engine.player)
        let enemy = worldPosition(engine.enemy)
        var forward = enemy - player
        forward.y = 0
        if simd_length(forward) > 0.001 {
            forward = simd_normalize(forward)
        } else {
            forward = cameraForward
        }
        let right = SIMD3<Float>(forward.z, 0, -forward.x)
        let cinematicDuration = cinematicPresentation == .appOpening ? 1.55 : 1.9
        let progress = Float(min(1, max(0, cinematicElapsed / cinematicDuration)))
        let eased = progress * progress * (3 - 2 * progress)
        let midpoint = (player + enemy) * 0.5
        cameraForward = forward
        switch cinematicPresentation {
        case .matchIntro:
            let widePosition = midpoint - forward * 10.2 + right * 1.65 + SIMD3<Float>(0, 6.3, 0)
            let closePosition = player - forward * 6.45 + right * 1.1 + SIMD3<Float>(0, 5.0, 0)
            var wideTarget = midpoint
            wideTarget.y = 1.12
            var closeTarget = player * 0.45 + enemy * 0.55
            closeTarget.y = 1.44
            cameraNode.simdPosition = widePosition + (closePosition - widePosition) * eased
            cameraTarget = wideTarget + (closeTarget - wideTarget) * eased
        case .appOpening:
            let widePosition = midpoint - forward * 7.4 + right * 5.8 + SIMD3<Float>(0, 4.8, 0)
            let closePosition = midpoint - forward * 1.85 + right * 3.30 + SIMD3<Float>(0, 2.35, 0)
            var wideTarget = midpoint
            wideTarget.y = 1.3
            var closeTarget = midpoint
            closeTarget.y = 1.55
            let impact = openingImpactPulse
            let cameraPosition = widePosition + (closePosition - widePosition) * eased
            let horizontalShake = Float(sin(cinematicElapsed * 92)) * 0.09 * impact
            let verticalShake = Float(cos(cinematicElapsed * 117)) * 0.045 * impact
            cameraNode.simdPosition = cameraPosition + right * horizontalShake
            cameraNode.simdPosition.y += verticalShake
            cameraTarget = wideTarget + (closeTarget - wideTarget) * eased + forward * 0.065 * impact
        }
        cameraNode.look(at: SCNVector3(cameraTarget), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }

    private func updateAppOpeningChoreography() {
        let player = engine.player
        let enemy = engine.enemy
        let beat: Float
        if usesOpeningCaptureBeat {
            beat = 0.92
        } else {
            beat = Float(cinematicElapsed.truncatingRemainder(dividingBy: 1.55))
        }

        player.x = 255
        player.y = 295
        player.facingX = 1
        player.facingY = 0
        enemy.x = 335
        enemy.y = 295
        enemy.facingX = -1
        enemy.facingY = 0
        player.attack = nil
        enemy.attack = nil
        player.actionTime = 0
        enemy.actionTime = 0
        player.guarding = false
        enemy.guarding = false
        player.duckDirection = 0
        enemy.duckDirection = 0
        player.hitReaction = 0
        enemy.hitReaction = 0

        if beat < 0.20 {
            player.guarding = true
            enemy.guarding = true
        } else if beat < 0.53 {
            applyCinematicAttack(player, punch: .jab, progress: (beat - 0.20) / 0.33)
            enemy.duckDirection = 1
        } else if beat < 0.70 {
            player.guarding = true
            enemy.duckDirection = 1
        } else if beat < 1.06 {
            applyCinematicAttack(enemy, punch: .cross, progress: (beat - 0.70) / 0.36)
            player.duckDirection = -1
        } else if beat < 1.42 {
            applyCinematicAttack(player, punch: .leftHook, progress: (beat - 1.06) / 0.36)
            enemy.guarding = true
        } else {
            player.guarding = true
            enemy.guarding = true
        }

        let jabImpact = openingPulse(beat, at: 0.47)
        let crossImpact = openingPulse(beat, at: 1.00)
        let hookImpact = openingPulse(beat, at: 1.36)
        openingImpactPulse = max(jabImpact, max(crossImpact, hookImpact))
        if openingImpactPulse > 0.12 {
            if beat < 0.60 || beat > 1.08 {
                enemy.hitReaction = Double(openingImpactPulse) * 0.16
            } else {
                player.hitReaction = Double(openingImpactPulse) * 0.16
            }
        }
    }

    private func applyCinematicAttack(_ fighter: FighterModel, punch: Punch, progress: Float) {
        guard let spec = CombatData.attacks[punch] else { return }
        fighter.attack = punch
        fighter.actionTime = Double(min(1, max(0, progress))) * spec.duration
    }

    private func openingPulse(_ beat: Float, at impactTime: Float) -> Float {
        max(0, 1 - abs(beat - impactTime) / 0.075)
    }

    private func buildArena() {
        let ground = SCNFloor()
        ground.reflectivity = 0.08
        ground.reflectionFalloffEnd = 9
        ground.firstMaterial = material(color: UIColor(red: 0.018, green: 0.025, blue: 0.044, alpha: 1), roughness: 0.88)
        let groundNode = SCNNode(geometry: ground)
        groundNode.position.y = -0.68
        groundNode.name = "arenaFloor"
        rootNode.addChildNode(groundNode)

        let apron = box(width: 13.5, height: 0.72, length: 13.5, radius: 0.08, color: UIColor(red: 0.055, green: 0.075, blue: 0.12, alpha: 1), roughness: 0.6)
        apron.name = "ringApron"
        apron.position.y = -0.36
        rootNode.addChildNode(apron)

        let canvas = box(width: 12.35, height: 0.14, length: 12.35, radius: 0.03, color: UIColor(red: 0.78, green: 0.84, blue: 0.86, alpha: 1), roughness: 0.78)
        canvas.name = "ringCanvas"
        canvas.position.y = 0.04
        rootNode.addChildNode(canvas)

        let centerMark = SCNCylinder(radius: 1.28, height: 0.012)
        centerMark.firstMaterial = material(color: UIColor(red: 0.055, green: 0.12, blue: 0.19, alpha: 1), roughness: 0.7)
        let centerNode = SCNNode(geometry: centerMark)
        centerNode.position.y = 0.12
        rootNode.addChildNode(centerNode)
        let centerInset = SCNTorus(ringRadius: 0.86, pipeRadius: 0.035)
        centerInset.firstMaterial = material(color: UIColor(red: 0.92, green: 0.66, blue: 0.16, alpha: 1), roughness: 0.4, metalness: 0.2)
        let centerInsetNode = SCNNode(geometry: centerInset)
        centerInsetNode.position.y = 0.135
        rootNode.addChildNode(centerInsetNode)

        buildPostsAndRopes()
        buildArenaWalls()
        buildAudience()
    }

    private func buildPostsAndRopes() {
        let extent: Float = 6.15
        let postColor = UIColor(red: 0.82, green: 0.87, blue: 0.90, alpha: 1)
        let red = UIColor(red: 0.84, green: 0.11, blue: 0.20, alpha: 1)
        let blue = UIColor(red: 0.04, green: 0.58, blue: 0.78, alpha: 1)
        let corners = [
            SIMD3<Float>(-extent, 0, -extent), SIMD3<Float>(extent, 0, -extent),
            SIMD3<Float>(extent, 0, extent), SIMD3<Float>(-extent, 0, extent),
        ]

        for (index, corner) in corners.enumerated() {
            let post = SCNCylinder(radius: 0.16, height: 2.25)
            post.radialSegmentCount = 12
            post.firstMaterial = material(color: postColor, roughness: 0.25, metalness: 0.65)
            let postNode = SCNNode(geometry: post)
            postNode.name = "cornerPost\(index)"
            postNode.simdPosition = corner + SIMD3<Float>(0, 1.1, 0)
            postNode.castsShadow = true
            rootNode.addChildNode(postNode)

            let pad = box(width: 0.48, height: 0.7, length: 0.48, radius: 0.1, color: index % 2 == 0 ? red : blue, roughness: 0.55)
            pad.simdPosition = corner + SIMD3<Float>(0, 1.35, 0)
            rootNode.addChildNode(pad)
        }

        let ropeHeights: [Float] = [0.68, 1.10, 1.52]
        for (level, height) in ropeHeights.enumerated() {
            let color = level == 1 ? UIColor(white: 0.9, alpha: 1) : (level == 0 ? blue : red)
            for index in corners.indices {
                let start = corners[index] + SIMD3<Float>(0, height, 0)
                let end = corners[(index + 1) % corners.count] + SIMD3<Float>(0, height, 0)
                rootNode.addChildNode(cylinderBetween(start, end, radius: 0.055, color: color, roughness: 0.42))
            }
        }
    }

    private func buildArenaWalls() {
        let lowerStand = box(width: 20, height: 1.2, length: 20, radius: 0, color: UIColor(red: 0.035, green: 0.045, blue: 0.075, alpha: 1), roughness: 0.9)
        lowerStand.position.y = -1.2
        rootNode.addChildNode(lowerStand)

        for depth in 0..<3 {
            let size = 16.5 + CGFloat(depth) * 2.2
            let thickness: CGFloat = 1.05
            let color = UIColor(red: 0.045 + CGFloat(depth) * 0.012, green: 0.055, blue: 0.082, alpha: 1)
            let height = 0.65 + CGFloat(depth) * 0.18
            let y = -0.5 + Float(depth) * 0.52
            let sections = [
                box(width: size, height: height, length: thickness, radius: 0.04, color: color, roughness: 0.92),
                box(width: size, height: height, length: thickness, radius: 0.04, color: color, roughness: 0.92),
                box(width: thickness, height: height, length: size - thickness * 2, radius: 0.04, color: color, roughness: 0.92),
                box(width: thickness, height: height, length: size - thickness * 2, radius: 0.04, color: color, roughness: 0.92),
            ]
            sections[0].position = SCNVector3(0, y, Float(size / 2))
            sections[1].position = SCNVector3(0, y, -Float(size / 2))
            sections[2].position = SCNVector3(Float(size / 2), y, 0)
            sections[3].position = SCNVector3(-Float(size / 2), y, 0)
            sections.forEach(rootNode.addChildNode)
        }

        let trussMaterial = UIColor(red: 0.25, green: 0.29, blue: 0.34, alpha: 1)
        let trussY: Float = 7.2
        rootNode.addChildNode(cylinderBetween(SIMD3<Float>(-9, trussY, -7), SIMD3<Float>(9, trussY, -7), radius: 0.09, color: trussMaterial, roughness: 0.35, metalness: 0.7))
        rootNode.addChildNode(cylinderBetween(SIMD3<Float>(-9, trussY, 7), SIMD3<Float>(9, trussY, 7), radius: 0.09, color: trussMaterial, roughness: 0.35, metalness: 0.7))
    }

    private func buildAudience() {
        let shirtColors = [
            UIColor(red: 0.13, green: 0.48, blue: 0.63, alpha: 1),
            UIColor(red: 0.68, green: 0.16, blue: 0.25, alpha: 1),
            UIColor(red: 0.78, green: 0.57, blue: 0.16, alpha: 1),
            UIColor(red: 0.17, green: 0.43, blue: 0.30, alpha: 1),
            UIColor(red: 0.39, green: 0.28, blue: 0.52, alpha: 1),
        ]
        let skinColors = [
            UIColor(red: 0.92, green: 0.68, blue: 0.49, alpha: 1),
            UIColor(red: 0.55, green: 0.33, blue: 0.22, alpha: 1),
            UIColor(red: 0.78, green: 0.51, blue: 0.35, alpha: 1),
        ]

        for side in 0..<4 {
            for index in 0..<13 {
                let spectator = SCNNode()
                let row = index % 3
                let along = Float(index / 3) * 1.25 - 2.1
                let distance = 7.6 + Float(row) * 0.72
                switch side {
                case 0: spectator.position = SCNVector3(along, 0.82 + Float(row) * 0.48, -distance)
                case 1: spectator.position = SCNVector3(distance, 0.82 + Float(row) * 0.48, along)
                case 2: spectator.position = SCNVector3(-along, 0.82 + Float(row) * 0.48, distance)
                default: spectator.position = SCNVector3(-distance, 0.82 + Float(row) * 0.48, -along)
                }
                let body = SCNNode(geometry: SCNCapsule(capRadius: 0.18, height: 0.64))
                body.geometry?.firstMaterial = material(color: shirtColors[(index + side) % shirtColors.count], roughness: 0.85)
                body.position.y = 0.32
                spectator.addChildNode(body)
                let headGeometry = SCNSphere(radius: 0.16)
                headGeometry.segmentCount = 8
                let head = SCNNode(geometry: headGeometry)
                head.geometry?.firstMaterial = material(color: skinColors[(index + side * 2) % skinColors.count], roughness: 0.8)
                head.position.y = 0.82
                spectator.addChildNode(head)
                rootNode.addChildNode(spectator)
            }
        }
    }

    private func buildLighting() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 260
        ambient.color = UIColor(red: 0.30, green: 0.39, blue: 0.57, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)

        let lightPositions: [(SIMD3<Float>, UIColor)] = [
            (SIMD3<Float>(-5.5, 8.2, -4.8), UIColor(red: 0.70, green: 0.87, blue: 1, alpha: 1)),
            (SIMD3<Float>(5.5, 8.2, -4.8), UIColor(red: 1, green: 0.78, blue: 0.68, alpha: 1)),
            (SIMD3<Float>(-5.5, 8.2, 4.8), UIColor(red: 0.65, green: 0.91, blue: 1, alpha: 1)),
            (SIMD3<Float>(5.5, 8.2, 4.8), UIColor(red: 1, green: 0.86, blue: 0.66, alpha: 1)),
        ]
        for (index, entry) in lightPositions.enumerated() {
            let light = SCNLight()
            light.type = .spot
            light.intensity = index == 0 ? 1_650 : 1_050
            light.spotInnerAngle = 24
            light.spotOuterAngle = 70
            light.attenuationStartDistance = 5
            light.attenuationEndDistance = 18
            light.color = entry.1
            light.castsShadow = index == 0
            light.shadowRadius = 5
            light.shadowColor = UIColor.black.withAlphaComponent(0.65)
            light.shadowMapSize = CGSize(width: 1024, height: 1024)
            let node = SCNNode()
            node.light = light
            node.simdPosition = entry.0
            node.look(at: SCNVector3(0, 0, 0))
            rootNode.addChildNode(node)
        }
    }

    private func worldPosition(_ fighter: FighterModel) -> SIMD3<Float> {
        let scale: Float = 0.025
        return SIMD3<Float>(Float(fighter.x - 295) * scale, 0.13, Float(fighter.y - 295) * scale)
    }
}

@MainActor
private final class BoxerRig {
    enum Team {
        case player
        case rival
    }

    let root = SCNNode()
    private let team: Team
    private let poseRoot = SCNNode()
    private let torso: SCNNode
    private let trunks: SCNNode
    private let waistband: SCNNode
    private let champBadge: SCNNode
    private let neck: SCNNode
    private let head: SCNNode
    private let identityLabel: SCNNode
    private let leftEye: SCNNode
    private let rightEye: SCNNode
    private let leftGlove: SCNNode
    private let rightGlove: SCNNode
    private let leftFoot: SCNNode
    private let rightFoot: SCNNode
    private let leftShoulderJoint: SCNNode
    private let rightShoulderJoint: SCNNode
    private let leftUpperArm: BoneNode
    private let leftForearm: BoneNode
    private let rightUpperArm: BoneNode
    private let rightForearm: BoneNode
    private let leftThigh: BoneNode
    private let leftShin: BoneNode
    private let rightThigh: BoneNode
    private let rightShin: BoneNode
    private let leftTrail: BoneNode
    private let rightTrail: BoneNode
    private let skinMaterial: SCNMaterial
    private let teamMaterial: SCNMaterial
    private let gloveMaterial: SCNMaterial
    private let gloveAccentMaterial: SCNMaterial
    private let shirtMaterial: SCNMaterial
    private let shirtTorso: SCNNode
    private let leftSleeveCap: SCNNode
    private let rightSleeveCap: SCNNode
    private let leftSleeveUpper: BoneNode
    private let leftSleeveLower: BoneNode
    private let rightSleeveUpper: BoneNode
    private let rightSleeveLower: BoneNode
    private var previousPosition = SIMD2<Double>(0, 0)
    private var travelPhase = 0.0
    private var duckVisual: Float = 0

    init(team: Team) {
        self.team = team
        let teamColor = team == .player
            ? UIColor(red: 0.025, green: 0.20, blue: 0.52, alpha: 1)
            : UIColor(red: 0.52, green: 0.025, blue: 0.07, alpha: 1)
        let gloveColor = team == .player
            ? UIColor(red: 0.035, green: 0.29, blue: 0.70, alpha: 1)
            : UIColor(red: 0.68, green: 0.035, blue: 0.11, alpha: 1)
        let labelColor = team == .player
            ? UIColor(red: 0.28, green: 0.80, blue: 1, alpha: 1)
            : UIColor(red: 1, green: 0.30, blue: 0.43, alpha: 1)
        // A noticeably darker shade of the glove color, used for the wrist strap/seam/logo-patch details
        // that break up the glove's single flat color into distinct, more detailed-looking sections.
        let gloveAccentColor = team == .player
            ? UIColor(red: 0.02, green: 0.16, blue: 0.39, alpha: 1)
            : UIColor(red: 0.37, green: 0.02, blue: 0.06, alpha: 1)
        skinMaterial = material(color: UIColor(red: 0.74, green: 0.42, blue: 0.26, alpha: 1), roughness: 0.62)
        teamMaterial = material(color: teamColor, roughness: 0.34, metalness: 0.08)
        gloveMaterial = material(color: gloveColor, roughness: 0.24, metalness: 0.10)
        gloveAccentMaterial = material(color: gloveAccentColor, roughness: 0.42, metalness: 0.04)
        let trailMaterial = material(color: gloveColor.withAlphaComponent(0.7), roughness: 0.15)
        trailMaterial.lightingModel = .constant
        trailMaterial.emission.contents = gloveColor
        trailMaterial.emission.intensity = 0.75
        trailMaterial.blendMode = .add
        trailMaterial.writesToDepthBuffer = false
        let darkMaterial = material(color: UIColor(red: 0.025, green: 0.035, blue: 0.055, alpha: 1), roughness: 0.75)

        torso = SCNNode(geometry: SCNCapsule(capRadius: 0.40, height: 0.94))
        torso.geometry?.materials = [skinMaterial]
        torso.scale = SCNVector3(1.08, 1, 0.72)
        trunks = SCNNode(geometry: SCNBox(width: 0.84, height: 0.45, length: 0.56, chamferRadius: 0.09))
        trunks.geometry?.materials = [teamMaterial]
        waistband = SCNNode(geometry: SCNBox(width: 0.88, height: 0.13, length: 0.59, chamferRadius: 0.025))
        waistband.geometry?.materials = [teamMaterial]
        // A small gold-embossed "CHAMP" text plate mounted flush on the waistband's front face -- only shown
        // when the "Champ" outfit (1000 cumulative wins) is equipped, toggled in `applyOutfit`.
        champBadge = BoxerRig.champBadge()
        waistband.addChildNode(champBadge)
        neck = SCNNode(geometry: SCNCylinder(radius: 0.15, height: 0.24))
        neck.geometry?.materials = [skinMaterial]
        head = SCNNode(geometry: SCNSphere(radius: 0.30))
        head.geometry?.materials = [skinMaterial]
        head.scale = SCNVector3(0.86, 1.08, 0.88)
        identityLabel = BoxerRig.identityLabel(text: team == .player ? "ME" : "RIVAL", color: labelColor)
        leftEye = SCNNode(geometry: SCNSphere(radius: 0.026))
        rightEye = SCNNode(geometry: SCNSphere(radius: 0.026))
        leftEye.geometry?.materials = [darkMaterial]
        rightEye.geometry?.materials = [darkMaterial]

        leftGlove = BoxerRig.glove(material: gloveMaterial, accentMaterial: gloveAccentMaterial, handedness: 1)
        rightGlove = BoxerRig.glove(material: gloveMaterial, accentMaterial: gloveAccentMaterial, handedness: -1)
        leftFoot = BoxerRig.shoe(material: teamMaterial, sole: darkMaterial)
        rightFoot = BoxerRig.shoe(material: teamMaterial, sole: darkMaterial)
        // A rounded joint sphere sits exactly at the shoulder anchor so the upper arm bone (which starts
        // at that same point) always reads as visually attached to the body, even though the torso capsule
        // is a separate piece of geometry that only approximately lines up with the pose's shoulder point.
        leftShoulderJoint = SCNNode(geometry: SCNSphere(radius: 0.175))
        leftShoulderJoint.geometry?.materials = [skinMaterial]
        rightShoulderJoint = SCNNode(geometry: SCNSphere(radius: 0.175))
        rightShoulderJoint.geometry?.materials = [skinMaterial]
        leftUpperArm = BoneNode(radius: 0.14, material: skinMaterial)
        leftForearm = BoneNode(radius: 0.12, material: skinMaterial)
        rightUpperArm = BoneNode(radius: 0.14, material: skinMaterial)
        rightForearm = BoneNode(radius: 0.12, material: skinMaterial)
        leftThigh = BoneNode(radius: 0.17, material: skinMaterial)
        leftShin = BoneNode(radius: 0.14, material: skinMaterial)
        rightThigh = BoneNode(radius: 0.17, material: skinMaterial)
        rightShin = BoneNode(radius: 0.14, material: skinMaterial)
        leftTrail = BoneNode(radius: 0.055, material: trailMaterial)
        rightTrail = BoneNode(radius: 0.055, material: trailMaterial)

        shirtMaterial = material(color: UIColor(red: 0.46, green: 0.47, blue: 0.49, alpha: 1), roughness: 0.6)
        let shirtGeometry = SCNCapsule(capRadius: 0.415, height: 0.98)
        shirtGeometry.materials = [shirtMaterial]
        shirtTorso = SCNNode(geometry: shirtGeometry)
        shirtTorso.name = "practiceShirtTorso"
        shirtTorso.isHidden = true
        // Radius/scale chosen so this sphere fully ENCLOSES the skin-colored shoulder joint sphere
        // (radius 0.175) in every direction -- a previous version squished the cap's y-extent down to
        // 0.185*0.85 = 0.157, i.e. SMALLER than the joint's own 0.175 radius, so the joint poked out top
        // and bottom and read as bare, exposed ("off-shoulder") skin right at the shoulder line.
        leftSleeveCap = SCNNode(geometry: SCNSphere(radius: 0.20))
        leftSleeveCap.geometry?.materials = [shirtMaterial]
        leftSleeveCap.name = "practiceLeftSleeve"
        leftSleeveCap.scale = SCNVector3(1, 0.94, 1)
        leftSleeveCap.isHidden = true
        rightSleeveCap = SCNNode(geometry: SCNSphere(radius: 0.20))
        rightSleeveCap.geometry?.materials = [shirtMaterial]
        rightSleeveCap.name = "practiceRightSleeve"
        rightSleeveCap.scale = SCNVector3(1, 0.94, 1)
        rightSleeveCap.isHidden = true

        // Long t-shirt sleeves running the full arm (instead of just a shoulder cap), following the exact
        // same shoulder/elbow/glove points the skin-colored arm bones use each frame (see `updateSleeve`).
        leftSleeveUpper = BoneNode(radius: 0.165, material: shirtMaterial)
        leftSleeveLower = BoneNode(radius: 0.145, material: shirtMaterial)
        rightSleeveUpper = BoneNode(radius: 0.165, material: shirtMaterial)
        rightSleeveLower = BoneNode(radius: 0.145, material: shirtMaterial)
        leftSleeveUpper.node.name = "practiceLeftSleeveUpper"
        leftSleeveLower.node.name = "practiceLeftSleeveLower"
        rightSleeveUpper.node.name = "practiceRightSleeveUpper"
        rightSleeveLower.node.name = "practiceRightSleeveLower"
        leftSleeveUpper.node.isHidden = true
        leftSleeveLower.node.isHidden = true
        rightSleeveUpper.node.isHidden = true
        rightSleeveLower.node.isHidden = true

        root.name = team == .player ? "playerBoxer" : "rivalBoxer"
        identityLabel.name = team == .player ? "playerIdentityLabel" : "rivalIdentityLabel"
        leftGlove.name = team == .player ? "playerLeftGlove" : "rivalLeftGlove"
        rightGlove.name = team == .player ? "playerRightGlove" : "rivalRightGlove"
        leftTrail.node.name = team == .player ? "playerLeftPunchTrail" : "rivalLeftPunchTrail"
        rightTrail.node.name = team == .player ? "playerRightPunchTrail" : "rivalRightPunchTrail"
        leftTrail.node.isHidden = true
        rightTrail.node.isHidden = true
        root.addChildNode(poseRoot)
        root.addChildNode(identityLabel)
        for node in [
            torso, trunks, waistband, neck, head, leftEye, rightEye,
            leftGlove, rightGlove, leftFoot, rightFoot,
            leftShoulderJoint, rightShoulderJoint,
            leftUpperArm.node, leftForearm.node, rightUpperArm.node, rightForearm.node,
            leftThigh.node, leftShin.node, rightThigh.node, rightShin.node,
            leftTrail.node, rightTrail.node,
            leftSleeveUpper.node, leftSleeveLower.node, rightSleeveUpper.node, rightSleeveLower.node,
        ] {
            node.castsShadow = true
            poseRoot.addChildNode(node)
        }
        // Practice-room-only gray gym outfit overlay (a simple long-sleeve t-shirt, no hood): parented
        // directly to the torso/shoulder joints so it automatically follows the same pose transforms every
        // frame with no extra per-update code needed.
        torso.addChildNode(shirtTorso)
        leftShoulderJoint.addChildNode(leftSleeveCap)
        rightShoulderJoint.addChildNode(rightSleeveCap)
    }

    func update(from fighter: FighterModel, deltaTime: Double, elapsedTime: TimeInterval) {
        let worldScale: Float = 0.025
        root.simdPosition = SIMD3<Float>(Float(fighter.x - 295) * worldScale, 0.13, Float(fighter.y - 295) * worldScale)
        root.eulerAngles.y = Float(atan2(fighter.facingX, fighter.facingY))

        let movementX = fighter.x - previousPosition.x
        let movementY = fighter.y - previousPosition.y
        let movement = hypot(movementX, movementY)
        if movement < 20 { travelPhase += movement * 0.12 }
        previousPosition = SIMD2<Double>(fighter.x, fighter.y)
        let moving = movement > 0.05 && movement < 20
        let strideCycle = moving ? Float(sin(travelPhase)) : 0
        let stride = strideCycle * 0.13
        let movementScale = moving ? 1 / max(0.001, movement) : 0
        let normalizedX = movementX * movementScale
        let normalizedY = movementY * movementScale
        let forwardMotion = Float(normalizedX * fighter.facingX + normalizedY * fighter.facingY)
        let strafeMotion = Float(-normalizedX * fighter.facingY + normalizedY * fighter.facingX)
        let idle = Float(sin(elapsedTime * 3.1)) * 0.018
        let weave = Float(sin(elapsedTime * 1.7)) * fighter.style.idleWeaveAmount
        let duckBlend = Float(1 - exp(-deltaTime * 15))
        duckVisual += (Float(fighter.duckDirection) - duckVisual) * duckBlend

        var pose = FightPose.neutral(
            stride: stride,
            style: fighter.style,
            stanceWidth: fighter.style.stanceWidth,
            leanBias: fighter.style.leanBias,
            pitchBias: fighter.style.pitchBias
        )
        pose.torsoY += idle
        pose.torsoLean += weave
        pose.torsoYaw += weave * 0.4
        if moving, fighter.attack == nil, !fighter.guarding {
            pose.applyMovement(forward: forwardMotion, strafe: strafeMotion, strideCycle: strideCycle)
        }
        if fighter.guarding { pose.applyGuard(style: fighter.style) }
        if abs(duckVisual) > 0.01 { pose.applyDuck(direction: duckVisual, style: fighter.style) }
        var attackProgress: Float?
        if let punch = fighter.attack, let spec = CombatData.attacks[punch] {
            let progress = Float(min(1, fighter.actionTime / spec.duration))
            attackProgress = progress
            pose.applyAttack(punch, progress: progress)
        }

        let reaction = Float(min(1, fighter.hitReaction / 0.24))
        poseRoot.position = SCNVector3(-duckVisual * 0.26, pose.rootY, pose.rootZ - reaction * 0.26)
        let reactionDirection: Float = team == .player ? -1 : 1
        poseRoot.eulerAngles = SCNVector3(0, pose.torsoYaw - reaction * 0.22, reaction * reactionDirection * 0.16)
        if fighter.knockedOut {
            let fall = smoothStep(Float(fighter.knockdown))
            poseRoot.eulerAngles.x = -fall * (.pi / 2)
            poseRoot.position.y = 0.02
            poseRoot.position.z = -0.25 * fall
        }

        torso.simdPosition = SIMD3<Float>(0, pose.torsoY, 0)
        torso.eulerAngles = SCNVector3(pose.torsoPitch, 0, pose.torsoLean)
        torso.simdScale = SIMD3<Float>(
            1.08 * fighter.style.torsoWidthScale,
            fighter.style.torsoHeightScale,
            0.72 * fighter.style.torsoDepthScale
        )
        trunks.simdPosition = SIMD3<Float>(0, 0.86 - pose.bodyDrop * 0.72, 0)
        trunks.simdScale = SIMD3<Float>(fighter.style.torsoWidthScale, 1, fighter.style.torsoDepthScale)
        waistband.simdPosition = SIMD3<Float>(0, 1.08 - pose.bodyDrop * 0.82, 0)
        waistband.simdScale = SIMD3<Float>(fighter.style.torsoWidthScale, 1, fighter.style.torsoDepthScale)
        neck.simdPosition = SIMD3<Float>(0, 2.02 + idle - pose.bodyDrop, 0.015)
        head.simdPosition = SIMD3<Float>(0, 2.28 + idle - pose.bodyDrop, 0.04)
        head.eulerAngles.z = -pose.torsoLean * 0.45
        identityLabel.simdPosition = SIMD3<Float>(0, fighter.knockedOut ? 0.62 : 2.80 + idle - pose.bodyDrop, 0)
        leftEye.simdPosition = SIMD3<Float>(-0.11, 2.34 + idle - pose.bodyDrop, 0.265)
        rightEye.simdPosition = SIMD3<Float>(0.11, 2.34 + idle - pose.bodyDrop, 0.265)

        // The torso capsule rotates around its own pivot for pitch/lean, but shoulder/elbow/glove points are
        // authored assuming an upright torso, so rotate them the same amount here — otherwise the upper arm
        // visibly floats away from the torso surface whenever a punch or lean tilts the torso.
        let torsoPivotY = pose.torsoY
        let leftShoulderPosition = attachToTorso(pose.leftShoulder, pivotY: torsoPivotY, pitch: pose.torsoPitch, lean: pose.torsoLean)
        let leftElbowPosition = attachToTorso(pose.leftElbow, pivotY: torsoPivotY, pitch: pose.torsoPitch, lean: pose.torsoLean)
        let leftGlovePosition = attachToTorso(pose.leftGlove, pivotY: torsoPivotY, pitch: pose.torsoPitch, lean: pose.torsoLean)
        let rightShoulderPosition = attachToTorso(pose.rightShoulder, pivotY: torsoPivotY, pitch: pose.torsoPitch, lean: pose.torsoLean)
        let rightElbowPosition = attachToTorso(pose.rightElbow, pivotY: torsoPivotY, pitch: pose.torsoPitch, lean: pose.torsoLean)
        let rightGlovePosition = attachToTorso(pose.rightGlove, pivotY: torsoPivotY, pitch: pose.torsoPitch, lean: pose.torsoLean)

        // Give each style a visibly different limb thickness to match its torso build scale above. The
        // shoulder joint ball uses its own (separate) scale so it can be tuned independently of arm/leg
        // bone thickness.
        let limbScale = fighter.style.limbRadiusScale
        let shoulderScale = fighter.style.shoulderJointScale
        leftShoulderJoint.simdPosition = leftShoulderPosition
        rightShoulderJoint.simdPosition = rightShoulderPosition
        leftShoulderJoint.simdScale = SIMD3<Float>(repeating: shoulderScale)
        rightShoulderJoint.simdScale = SIMD3<Float>(repeating: shoulderScale)
        leftUpperArm.setRadiusScale(limbScale)
        leftForearm.setRadiusScale(limbScale)
        rightUpperArm.setRadiusScale(limbScale)
        rightForearm.setRadiusScale(limbScale)
        leftThigh.setRadiusScale(limbScale)
        leftShin.setRadiusScale(limbScale)
        rightThigh.setRadiusScale(limbScale)
        rightShin.setRadiusScale(limbScale)

        updateArm(shoulder: leftShoulderPosition, elbow: leftElbowPosition, glove: leftGlovePosition, upper: leftUpperArm, lower: leftForearm, gloveNode: leftGlove)
        updateArm(shoulder: rightShoulderPosition, elbow: rightElbowPosition, glove: rightGlovePosition, upper: rightUpperArm, lower: rightForearm, gloveNode: rightGlove)
        updateSleeve(shoulder: leftShoulderPosition, elbow: leftElbowPosition, glove: leftGlovePosition, upper: leftSleeveUpper, lower: leftSleeveLower)
        updateSleeve(shoulder: rightShoulderPosition, elbow: rightElbowPosition, glove: rightGlovePosition, upper: rightSleeveUpper, lower: rightSleeveLower)
        updateLeg(hip: pose.leftHip, knee: pose.leftKnee, foot: pose.leftFoot, thigh: leftThigh, shin: leftShin, footNode: leftFoot)
        updateLeg(hip: pose.rightHip, knee: pose.rightKnee, foot: pose.rightFoot, thigh: rightThigh, shin: rightShin, footNode: rightFoot)

        leftTrail.node.isHidden = true
        rightTrail.node.isHidden = true
        leftGlove.scale = SCNVector3(1, 1, 1)
        rightGlove.scale = SCNVector3(1, 1, 1)
        if let punch = fighter.attack, let attackProgress {
            let extensionAmount = attackEnvelope(attackProgress)
            if extensionAmount > 0.06 {
                let neutral = FightPose.neutral(stride: 0)
                let leadLeft = [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch)
                let trail = leadLeft ? leftTrail : rightTrail
                let start = leadLeft ? neutral.leftGlove : neutral.rightGlove
                let end = leadLeft ? leftGlovePosition : rightGlovePosition
                trail.update(from: start, to: end)
                trail.node.opacity = CGFloat(0.18 + 0.34 * extensionAmount)
                trail.node.isHidden = false
                let gloveNode = leadLeft ? leftGlove : rightGlove
                let emphasis = 1 + 0.12 * extensionAmount
                gloveNode.scale = SCNVector3(emphasis, emphasis, emphasis)
            }
        }

        skinMaterial.emission.contents = fighter.hitReaction > 0.16 ? UIColor.white : UIColor.black
        skinMaterial.emission.intensity = fighter.hitReaction > 0.16 ? 0.65 : 0
        teamMaterial.emission.contents = fighter.exposed > 0 ? UIColor(red: 0.95, green: 0.56, blue: 0.08, alpha: 1) : UIColor.black
        teamMaterial.emission.intensity = fighter.exposed > 0 ? 0.28 : 0
    }

    /// Recolors the cosmetic surfaces (trunks/waistband/shoes/gloves) to reflect an unlocked outfit choice.
    /// Only meaningful for the player rig — the rival always keeps its default look.
    func applyOutfit(_ outfit: OutfitID) {
        guard team == .player else { return }
        // The "Gym Gray" outfit reuses the exact same long-sleeve shirt overlay the practice room always
        // forces on -- enabling it here (main match rig) also sets the gray team/glove colors as a side
        // effect; every other outfit case below then overrides those colors with its own.
        setPracticeAppearance(outfit == .gymGray)
        switch outfit {
        case .classic:
            teamMaterial.diffuse.contents = UIColor(red: 0.025, green: 0.20, blue: 0.52, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.035, green: 0.29, blue: 0.70, alpha: 1)
        case .champion:
            teamMaterial.diffuse.contents = UIColor(red: 0.62, green: 0.47, blue: 0.06, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.83, green: 0.65, blue: 0.10, alpha: 1)
        case .blackout:
            // 100 cumulative wins: a plain, matte near-black -- no text, no shine, just a stealthy "seen it
            // all" look that reads as noticeably darker than every other outfit at a glance.
            teamMaterial.diffuse.contents = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        case .gymGray:
            break // colors + shirt visibility already handled by setPracticeAppearance(true) above.
        case .unscathed:
            // 10 rounds won without taking a hit: a pristine off-white/platinum base with a bright sky-blue
            // glove accent -- reads as "spotless", i.e. never touched, in contrast to every other outfit's
            // darker palette.
            teamMaterial.diffuse.contents = UIColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.25, green: 0.55, blue: 0.85, alpha: 1)
        case .champ:
            // 1000 cumulative wins: a deep black-and-gold combo (darker/richer than Champion Gold) plus the
            // embossed "CHAMP" waistband badge toggled below -- the game's top cosmetic tier.
            teamMaterial.diffuse.contents = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.55, green: 0.42, blue: 0.08, alpha: 1)
        case .streak:
            // 20-win streak ("Blaze"): a hot orange-red base with a bright yellow-orange glove accent, read
            // as "on fire" -- distinct from the golden Champion/Champ palettes by leaning fully into red.
            teamMaterial.diffuse.contents = UIColor(red: 0.62, green: 0.14, blue: 0.03, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.95, green: 0.42, blue: 0.05, alpha: 1)
        case .masteryInFighter:
            // 50 wins as In-Fighter ("Steel Guard"): a cool steel blue-gray, evoking a sturdy, balanced
            // defensive stance.
            teamMaterial.diffuse.contents = UIColor(red: 0.24, green: 0.29, blue: 0.36, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.42, green: 0.49, blue: 0.58, alpha: 1)
        case .masteryOutboxer:
            // 50 wins as Outboxing ("Ghost Step"): a sleek cyan/teal, evoking speed and evasive footwork.
            teamMaterial.diffuse.contents = UIColor(red: 0.04, green: 0.32, blue: 0.34, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.10, green: 0.62, blue: 0.64, alpha: 1)
        case .masterySlugger:
            // 50 wins as Slugger ("Heavyweight"): a deep maroon, evoking raw, unconditional power.
            teamMaterial.diffuse.contents = UIColor(red: 0.32, green: 0.03, blue: 0.07, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.55, green: 0.06, blue: 0.12, alpha: 1)
        }
        champBadge.isHidden = outfit != .champ
    }

    /// Practice-room only: dresses the player in a full gray gym outfit (shirt covering the torso/shoulders
    /// + shorts + gloves, all unified to gray tones) instead of the bare-chested main-match look, regardless
    /// of whatever outfit is otherwise equipped. Only meaningful for the player rig.
    /// Practice-room-only outfit: a simple long-sleeve gray gym t-shirt (torso capsule + shoulder caps +
    /// full-arm sleeves), no hood. Several rounds of hood geometry (dome/brim/collar/mantle/peak/drawstrings)
    /// never read correctly in-app (hid the face, made the shoulders look like a thick block, and had a
    /// distracting extra circle on top no matter how the numbers were tuned), so the hood was removed
    /// entirely rather than continuing to patch it.
    func setPracticeAppearance(_ enabled: Bool) {
        guard team == .player else { return }
        shirtTorso.isHidden = !enabled
        leftSleeveCap.isHidden = !enabled
        rightSleeveCap.isHidden = !enabled
        leftSleeveUpper.node.isHidden = !enabled
        leftSleeveLower.node.isHidden = !enabled
        rightSleeveUpper.node.isHidden = !enabled
        rightSleeveLower.node.isHidden = !enabled
        if enabled {
            teamMaterial.diffuse.contents = UIColor(red: 0.42, green: 0.43, blue: 0.45, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.58, green: 0.59, blue: 0.61, alpha: 1)
        }
    }

    /// Rotates an arm anchor point by the torso's own pitch/lean around the torso's pivot, so the shoulder
    /// (and the rest of the arm) stays visually attached to the torso's rotated surface instead of the arm
    /// appearing to float away whenever the torso tilts (e.g. during a punch or a lean bias).
    private func attachToTorso(_ point: SIMD3<Float>, pivotY: Float, pitch: Float, lean: Float) -> SIMD3<Float> {
        var p = point
        p.y -= pivotY
        let cosPitch = cos(pitch)
        let sinPitch = sin(pitch)
        let y1 = p.y * cosPitch - p.z * sinPitch
        let z1 = p.y * sinPitch + p.z * cosPitch
        p.y = y1
        p.z = z1
        let cosLean = cos(lean)
        let sinLean = sin(lean)
        let x2 = p.x * cosLean - p.y * sinLean
        let y2 = p.x * sinLean + p.y * cosLean
        p.x = x2
        p.y = y2
        p.y += pivotY
        return p
    }

    private func updateArm(shoulder: SIMD3<Float>, elbow: SIMD3<Float>, glove: SIMD3<Float>, upper: BoneNode, lower: BoneNode, gloveNode: SCNNode) {
        let wristVector = elbow - glove
        let wristDirection = simd_length(wristVector) > 0.001
            ? simd_normalize(wristVector)
            : SIMD3<Float>(0, -1, 0)
        let cuffOpening = glove + wristDirection * 0.29
        upper.update(from: shoulder, to: elbow)
        lower.update(from: elbow, to: cuffOpening)
        gloveNode.simdPosition = glove
        gloveNode.simdOrientation = simd_quatf(from: SIMD3<Float>(0, -1, 0), to: wristDirection)
    }

    private func updateLeg(hip: SIMD3<Float>, knee: SIMD3<Float>, foot: SIMD3<Float>, thigh: BoneNode, shin: BoneNode, footNode: SCNNode) {
        thigh.update(from: hip, to: knee)
        shin.update(from: knee, to: foot + SIMD3<Float>(0, 0.16, 0))
        footNode.simdPosition = foot
    }

    /// Runs a long-sleeve shirt sleeve (upper arm + forearm) along the exact same shoulder/elbow/glove points
    /// the skin arm bones use, extending slightly past the wrist toward the glove for a long-sleeve look. Kept
    /// as a separate pair of `BoneNode`s (rather than just thickening the skin arm) so the sleeves can be
    /// shown only in the practice room while the real-match bare-arm look is untouched.
    private func updateSleeve(shoulder: SIMD3<Float>, elbow: SIMD3<Float>, glove: SIMD3<Float>, upper: BoneNode, lower: BoneNode) {
        let wristVector = elbow - glove
        let wristDirection = simd_length(wristVector) > 0.001
            ? simd_normalize(wristVector)
            : SIMD3<Float>(0, -1, 0)
        // Kept CLOSER to the glove than the skin arm's own cuff point (`updateArm`'s `cuffOpening` at 0.29)
        // so the gray sleeve fully overlaps the bare forearm all the way down to the wrist, with no exposed
        // skin gap at the cuff -- a previous, larger offset (0.36) stopped short of the skin arm's own
        // visible extent and left a sliver of bare forearm showing right above the glove.
        let cuffEdge = glove + wristDirection * 0.20
        upper.update(from: shoulder, to: elbow)
        lower.update(from: elbow, to: cuffEdge)
    }

    /// Builds the small gold-embossed "CHAMP" text plate mounted flush on the waistband's front face, shown
    /// only when the "Champ" outfit (1000 cumulative wins) is equipped. A static child of the waistband
    /// (not a billboard like the floating name tag) so it rotates naturally with the body, like a real
    /// belt/waistband inscription.
    private static func champBadge() -> SCNNode {
        let textGeometry = SCNText(string: "CHAMP", extrusionDepth: 0.012)
        textGeometry.font = UIFont.systemFont(ofSize: 9, weight: .black)
        textGeometry.flatness = 0.1
        let textMaterial = SCNMaterial()
        textMaterial.diffuse.contents = UIColor(red: 0.95, green: 0.80, blue: 0.30, alpha: 1)
        textMaterial.metalness.contents = 0.7
        textMaterial.roughness.contents = 0.25
        textGeometry.materials = [textMaterial]
        let node = SCNNode(geometry: textGeometry)
        let bounds = node.boundingBox
        node.pivot = SCNMatrix4MakeTranslation(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5,
            (bounds.min.z + bounds.max.z) * 0.5
        )
        node.scale = SCNVector3(0.017, 0.017, 0.017)
        node.position = SCNVector3(0, 0, 0.30)
        node.name = "champBadge"
        node.isHidden = true
        return node
    }

    /// Builds one boxing glove: a rounded palm/fist body, a thumb, a cuff at the wrist, and a single
    /// contrasting wrist-strap band (using `accentMaterial`, a darker shade of the glove's own color) for a
    /// clean, simple silhouette with no stray floating pieces.
    private static func glove(material: SCNMaterial, accentMaterial: SCNMaterial, handedness: Float) -> SCNNode {
        let node = SCNNode()
        let palm = SCNNode(geometry: SCNSphere(radius: 0.18))
        palm.name = "glovePalm"
        palm.geometry?.materials = [material]
        palm.scale = SCNVector3(1.02, 1.02, 1.20)
        palm.position.z = 0.025

        let thumb = SCNNode(geometry: SCNCapsule(capRadius: 0.065, height: 0.20))
        thumb.name = "gloveThumb"
        thumb.geometry?.materials = [material]
        thumb.position = SCNVector3(-0.13 * handedness, -0.015, 0.085)
        thumb.eulerAngles.z = 0.55 * handedness

        let cuff = SCNNode(geometry: SCNCylinder(radius: 0.135, height: 0.22))
        cuff.name = "gloveCuff"
        cuff.geometry?.materials = [material]
        cuff.position.y = -0.18

        // Wrist strap band -- a slightly wider, contrasting-color cylinder wrapped around the cuff, like the
        // Velcro closure strap on a real training glove.
        let strap = SCNNode(geometry: SCNCylinder(radius: 0.142, height: 0.055))
        strap.name = "gloveStrap"
        strap.geometry?.materials = [accentMaterial]
        strap.position.y = -0.155

        node.addChildNode(palm)
        node.addChildNode(thumb)
        node.addChildNode(cuff)
        node.addChildNode(strap)
        return node
    }

    private static func identityLabel(text: String, color: UIColor) -> SCNNode {
        let root = SCNNode()
        let width: CGFloat = text == "ME" ? 0.48 : 0.78
        let background = SCNPlane(width: width, height: 0.26)
        background.cornerRadius = 0.05
        let backgroundMaterial = SCNMaterial()
        backgroundMaterial.lightingModel = .constant
        backgroundMaterial.diffuse.contents = UIColor.black.withAlphaComponent(0.72)
        backgroundMaterial.isDoubleSided = true
        backgroundMaterial.readsFromDepthBuffer = false
        backgroundMaterial.writesToDepthBuffer = false
        background.materials = [backgroundMaterial]
        let backgroundNode = SCNNode(geometry: background)
        backgroundNode.name = "identityBackground"
        backgroundNode.renderingOrder = 100

        let textGeometry = SCNText(string: text, extrusionDepth: 0.006)
        textGeometry.font = UIFont.systemFont(ofSize: 9, weight: .black)
        textGeometry.flatness = 0.12
        let textMaterial = SCNMaterial()
        textMaterial.lightingModel = .constant
        textMaterial.diffuse.contents = color
        textMaterial.emission.contents = color
        textMaterial.emission.intensity = 0.35
        textMaterial.isDoubleSided = true
        textMaterial.readsFromDepthBuffer = false
        textMaterial.writesToDepthBuffer = false
        textGeometry.materials = [textMaterial]
        let textNode = SCNNode(geometry: textGeometry)
        textNode.name = "identityText"
        let bounds = textNode.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation(
            (bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5,
            0
        )
        textNode.scale = SCNVector3(0.022, 0.022, 0.022)
        textNode.position.z = 0.008
        textNode.renderingOrder = 101

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        root.constraints = [billboard]
        root.addChildNode(backgroundNode)
        root.addChildNode(textNode)
        return root
    }

    private static func shoe(material: SCNMaterial, sole: SCNMaterial) -> SCNNode {
        let node = SCNNode()
        let boot = SCNNode(geometry: SCNBox(width: 0.31, height: 0.22, length: 0.48, chamferRadius: 0.08))
        boot.geometry?.materials = [material]
        boot.position.z = 0.08
        let soleNode = SCNNode(geometry: SCNBox(width: 0.33, height: 0.055, length: 0.51, chamferRadius: 0.02))
        soleNode.geometry?.materials = [sole]
        soleNode.position = SCNVector3(0, -0.12, 0.08)
        node.addChildNode(boot)
        node.addChildNode(soleNode)
        return node
    }
}

struct FightPose {
    var rootY: Float = 0
    var rootZ: Float = 0
    var bodyDrop: Float = 0
    var torsoY: Float = 1.55
    var torsoLean: Float = 0
    var torsoPitch: Float = 0
    var torsoYaw: Float = 0
    var leftShoulder = SIMD3<Float>(0.39, 1.82, 0)
    var rightShoulder = SIMD3<Float>(-0.39, 1.82, 0)
    var leftElbow = SIMD3<Float>(0.50, 1.52, 0.25)
    var rightElbow = SIMD3<Float>(-0.50, 1.52, 0.25)
    var leftGlove = SIMD3<Float>(0.25, 1.82, 0.48)
    var rightGlove = SIMD3<Float>(-0.25, 1.78, 0.44)
    var leftHip = SIMD3<Float>(0.22, 0.86, 0)
    var rightHip = SIMD3<Float>(-0.22, 0.86, 0)
    var leftKnee = SIMD3<Float>(0.29, 0.46, 0.14)
    var rightKnee = SIMD3<Float>(-0.30, 0.46, -0.12)
    var leftFoot = SIMD3<Float>(0.31, 0.14, 0.29)
    var rightFoot = SIMD3<Float>(-0.32, 0.14, -0.22)

    static func neutral(
        stride: Float, style: FightStyle = .standard, stanceWidth: Float = 0,
        leanBias: Float = 0, pitchBias: Float = 0
    ) -> FightPose {
        var pose = FightPose()
        pose.leftKnee.z += stride
        pose.rightKnee.z -= stride
        pose.leftFoot.z += stride
        pose.rightFoot.z -= stride
        pose.leftKnee.x += stanceWidth
        pose.rightKnee.x -= stanceWidth
        pose.leftFoot.x += stanceWidth
        pose.rightFoot.x -= stanceWidth
        pose.applyStance(style)
        pose.torsoLean += leanBias
        pose.torsoPitch += pitchBias
        return pose
    }

    /// Sets the resting arm/hand configuration for each style's signature guard shape. Standard keeps the
    /// rig's default "hands up" boxing pose untouched.
    mutating func applyStance(_ style: FightStyle) {
        switch style {
        case .standard:
            break
        case .outboxing:
            // Philly shell / shoulder-roll: the rear (right) hand stays up guarding the chin while the
            // lead (left) arm folds down at roughly 90° across the body to shield the ribs/solar plexus.
            // The lead elbow/glove sit well forward of the torso capsule (z > ~0.3) so the arm reads as a
            // raised shield in front of the body instead of clipping into it.
            rightElbow = SIMD3<Float>(-0.36, 1.70, 0.18)
            rightGlove = SIMD3<Float>(-0.22, 2.04, 0.34)
            leftElbow = SIMD3<Float>(0.36, 1.42, 0.34)
            leftGlove = SIMD3<Float>(0.10, 1.56, 0.46)
        case .infighting:
            // Slugger: a loose, dropped guard with the arms flared wide apart. Widening just the elbow/glove
            // while leaving the shoulder attachment at the rig's default (0.39) still buried that attachment
            // point inside Slugger's own bulkier torso (torsoWidthScale > 1), so the upper arm read as fused
            // to the body instead of standing away from the ribs. Pushing the shoulder itself outward here
            // opens a visible gap between the arm and the torso's side, and the elbow/glove are re-tapered
            // outward from that new shoulder position (never narrower than it) to avoid a bent "chicken wing"
            // kink -- together this reads as an aggressive brawler with arms held clear of the body. Eased
            // slightly back in from the first pass (0.47→0.43) per user follow-up feedback. The previous
            // "opened up" pass overcorrected -- pushing the glove straight out and down from the elbow made
            // the whole arm read as almost fully straight (a stiff T-pose look), not a natural bent-elbow
            // stance. Re-derived numerically so the upper-arm vector (shoulder→elbow) and forearm vector
            // (elbow→glove) are actually perpendicular (~90° interior elbow angle), and raised the elbow
            // itself higher (y 1.44→1.52) so the upper arm doesn't droop as low.
            leftShoulder.x = 0.43
            rightShoulder.x = -0.43
            leftElbow = SIMD3<Float>(0.48, 1.52, 0.06)
            rightElbow = SIMD3<Float>(-0.48, 1.52, 0.06)
            leftGlove = SIMD3<Float>(0.46, 1.58, 0.36)
            rightGlove = SIMD3<Float>(-0.46, 1.58, 0.36)
        }
    }

    mutating func applyMovement(forward: Float, strafe: Float, strideCycle: Float) {
        let stepWeight = abs(strideCycle)
        rootY += 0.035 * stepWeight
        rootZ += 0.055 * forward
        torsoY += 0.025 * stepWeight
        torsoPitch -= 0.065 * forward
        torsoLean -= 0.10 * strafe
        torsoYaw += 0.045 * strafe
        leftGlove.z -= 0.085 * strideCycle
        rightGlove.z += 0.085 * strideCycle
        leftGlove.y += 0.025 * stepWeight
        rightGlove.y += 0.025 * stepWeight
        leftShoulder.y += 0.018 * stepWeight
        rightShoulder.y += 0.018 * stepWeight
        leftHip.x += 0.045 * strafe
        rightHip.x += 0.045 * strafe
    }

    mutating func applyGuard(style: FightStyle = .standard) {
        switch style {
        case .standard:
            leftElbow = SIMD3<Float>(0.34, 1.66, 0.14)
            rightElbow = SIMD3<Float>(-0.34, 1.66, 0.14)
            leftGlove = SIMD3<Float>(0.20, 2.16, 0.30)
            rightGlove = SIMD3<Float>(-0.20, 2.16, 0.30)
        case .outboxing:
            // Tightened Philly shell: rear hand clamps to the chin, lead arm stays folded low but clear of
            // the torso, across the body.
            rightElbow = SIMD3<Float>(-0.34, 1.72, 0.18)
            rightGlove = SIMD3<Float>(-0.20, 2.20, 0.34)
            leftElbow = SIMD3<Float>(0.34, 1.38, 0.32)
            leftGlove = SIMD3<Float>(0.08, 1.52, 0.42)
        case .infighting:
            // The previous pass pulled the glove ABOVE shoulder height (y=1.92 > shoulder's 1.82) and only
            // barely forward of the torso surface (z=0.28), which -- since the torso's own scaled surface
            // extends out to roughly x=0.47/z=0.32 for Slugger's build -- put the glove almost directly
            // above-and-behind the shoulder joint from most turntable camera angles. That foreshortened the
            // whole forearm segment down to a sliver and visually buried it behind the shoulder ball/torso,
            // which is why the forearm looked like it had vanished entirely (just a glove floating at the
            // chest with no visible arm connecting it). Re-derived so the elbow flares out clearly beyond
            // the torso's own ellipse (x=0.52 vs. the torso's ~0.47 boundary) and the glove sits at roughly
            // shoulder height but reaches forward by a wide, unambiguous margin (z=0.24, well outside the
            // torso's ~0.32/0.17 boundary at that x/z ratio) -- this keeps the forearm's length/direction
            // close to the upper arm's own (comparable segment lengths, no more radical foreshortening) so
            // it stays clearly visible as a distinct capsule from every rotation angle.
            leftElbow = SIMD3<Float>(0.52, 1.58, 0.08)
            rightElbow = SIMD3<Float>(-0.52, 1.58, 0.08)
            leftGlove = SIMD3<Float>(0.40, 1.80, 0.24)
            rightGlove = SIMD3<Float>(-0.40, 1.80, 0.24)
        }
        torsoLean -= 0.05
    }

    /// Ducking should always show the guard's raised, hands-protecting-the-head arm shape -- rather than
    /// hand-tuning a separate small elbow/glove offset for the duck pose on top of whatever base arm pose
    /// (idle/moving) happened to already be active, this now reuses `applyGuard`'s already-correct per-style
    /// absolute arm positions directly, then only layers on the crouch/lean/shift that's unique to ducking
    /// (torso drop, hip/knee bend, sideways lean into the dodge). This also fixes the guard-collapsing-
    /// during-a-duck issue at the root instead of patching around it with small deltas.
    mutating func applyDuck(direction: Float, style: FightStyle = .standard) {
        let amount = min(1, abs(direction))
        applyGuard(style: style)
        bodyDrop = 0.42 * amount
        rootZ = -0.08 * amount
        torsoY -= 0.40 * amount
        // `attachToTorso` rotates every arm joint around the torso's own centerline using this lean angle --
        // a point's x-offset gets converted into a y-shift proportional to sin(lean), so a wide arm spread
        // (e.g. Slugger's elbow/glove sitting well out from center) combined with this large a roll made one
        // arm swing dramatically UP and the other swing dramatically DOWN. Eased from 0.28 to 0.14 so the
        // body still visibly leans into the duck without the arms swinging apart.
        torsoLean = -direction * 0.14
        torsoPitch = 0.16 * amount
        // The shoulder is the torso's attachment point for the whole arm, so it must only drift sideways as
        // far as the torso's own lean rotation carries it, or the upper arm visibly separates from the
        // torso surface. The hand/glove can still swing further out for the dodge's guard motion.
        let shoulderShift = -direction * 0.08
        let handShift = -direction * 0.24
        leftShoulder.x += shoulderShift
        rightShoulder.x += shoulderShift
        leftGlove.x += handShift
        rightGlove.x += handShift
        // Only the shoulder (the torso's own attachment point) drops with the body; the guard's own
        // elbow/glove positions (from `applyGuard` above) are left as-is so the guard visibly stays up
        // protecting the head/chin as the body lowers underneath it.
        leftShoulder.y -= 0.40 * amount
        rightShoulder.y -= 0.40 * amount
        leftHip.y -= 0.30 * amount
        rightHip.y -= 0.30 * amount
        leftKnee.y -= 0.08 * amount
        rightKnee.y -= 0.08 * amount
        leftKnee.z += 0.18 * amount
        rightKnee.z += 0.18 * amount
    }

    mutating func applyAttack(_ punch: Punch, progress: Float) {
        let extensionAmount = attackEnvelope(progress)
        let leadLeft = [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch)
        let side: Float = leadLeft ? 1 : -1
        torsoYaw = side * -0.24 * extensionAmount
        let shoulder = leadLeft ? leftShoulder : rightShoulder
        var glove = leadLeft ? leftGlove : rightGlove
        var elbow = leadLeft ? leftElbow : rightElbow

        switch punch {
        case .jab:
            rootZ = 0.16 * extensionAmount
            torsoPitch = -0.06 * extensionAmount
            glove = SIMD3<Float>(0.10, 1.91, 0.42 + 1.48 * extensionAmount)
            elbow = mix(shoulder, glove, amount: 0.50) + SIMD3<Float>(0.08, -0.06, 0)
        case .cross:
            rootZ = 0.24 * extensionAmount
            torsoPitch = -0.09 * extensionAmount
            glove = SIMD3<Float>(-0.08, 1.91, 0.38 + 1.30 * extensionAmount)
            elbow = mix(shoulder, glove, amount: 0.50) + SIMD3<Float>(-0.08, -0.07, 0)
            torsoYaw = side * 0.38 * extensionAmount
        case .leftBody, .rightBody:
            rootY -= 0.16 * extensionAmount
            rootZ = 0.18 * extensionAmount
            torsoPitch = 0.14 * extensionAmount
            glove = SIMD3<Float>(side * 0.10, 1.30, 0.38 + 1.12 * extensionAmount)
            elbow = mix(shoulder, glove, amount: 0.48) + SIMD3<Float>(side * 0.16, -0.12, 0)
            torsoLean = side * 0.08 * extensionAmount
        case .leftHook, .rightHook:
            let sweep = min(1, max(0, (progress - 0.18) / 0.48))
            let arc = sin(min(1, progress / 0.72) * .pi)
            rootZ = 0.13 * arc
            glove = SIMD3<Float>(side * (0.78 - 0.68 * sweep), 1.94, 0.34 + 1.04 * arc)
            elbow = SIMD3<Float>(side * 0.72, 1.83, 0.36 + 0.52 * arc)
            torsoYaw = side * -0.52 * arc
        case .leftUppercut, .rightUppercut:
            let rise = min(1, max(0, (progress - 0.20) / 0.48))
            rootY -= 0.20 * (1 - rise) * extensionAmount
            rootZ = 0.12 * extensionAmount
            torsoPitch = 0.12 * (1 - rise) - 0.08 * rise
            glove = SIMD3<Float>(side * 0.14, 1.30 + 0.90 * rise, 0.42 + 0.68 * extensionAmount)
            elbow = SIMD3<Float>(side * 0.34, 1.38, 0.40 + 0.28 * extensionAmount)
            torsoLean = side * 0.10 * extensionAmount
        }

        if leadLeft {
            leftGlove = glove
            leftElbow = elbow
        } else {
            rightGlove = glove
            rightElbow = elbow
        }
    }
}

@MainActor
private final class BoneNode {
    let node: SCNNode
    private let geometry: SCNCapsule
    private let baseRadius: CGFloat

    init(radius: CGFloat, material: SCNMaterial) {
        baseRadius = radius
        geometry = SCNCapsule(capRadius: radius, height: radius * 2.2)
        geometry.radialSegmentCount = 10
        geometry.capSegmentCount = 5
        geometry.materials = [material]
        node = SCNNode(geometry: geometry)
    }

    func update(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        let direction = end - start
        let length = max(0.01, simd_length(direction))
        geometry.height = CGFloat(length)
        node.simdPosition = (start + end) * 0.5
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction / length)
    }

    /// Scales the bone's thickness relative to its original radius, used to give each fighting style a
    /// visibly different limb thickness (leaner for outboxing, stockier for infighting).
    func setRadiusScale(_ scale: Float) {
        geometry.capRadius = baseRadius * CGFloat(scale)
    }
}

struct Arena3DView: UIViewRepresentable {
    @ObservedObject var controller: GameController

    func makeCoordinator() -> Coordinator {
        Coordinator(scene: controller.scene3D)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = controller.scene3D
        view.pointOfView = controller.scene3D.cameraNode
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        context.coordinator.start()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        view.pointOfView = controller.scene3D.cameraNode
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stop()
        view.isPlaying = false
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var scene: Arena3DScene?
        private var displayLink: CADisplayLink?

        init(scene: Arena3DScene) {
            self.scene = scene
        }

        func start() {
            guard displayLink == nil else { return }
            let displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func tick(_ displayLink: CADisplayLink) {
            scene?.update(at: displayLink.timestamp)
        }
    }
}

/// A small standalone scene showing just the player rig in its guard stance, used to preview each fighting
/// style (and equipped outfit) in the waiting room without needing the full arena or an opponent.
@MainActor
final class StylePreviewScene: SCNScene {
    let cameraNode = SCNNode()
    private let rig = BoxerRig(team: .player)
    // BoxerRig.update() positions the root at (fighter.x - 295, _, fighter.y - 295) since 295 is the arena's
    // center coordinate — use that same center here so the standalone preview rig lands at world origin,
    // right where the camera below is aimed.
    private let fighter = FighterModel(name: "PREVIEW", colorName: "blue", x: 295, y: 295)
    private var startTime: TimeInterval?
    // Tracks when the current style's turntable spin began; reset to nil whenever the style changes so the
    // character snaps back to facing the camera and restarts its 360° turn from the beginning.
    private var turntableStartTime: TimeInterval?
    private var isConfigured = false
    // Full 360° turn every 16 seconds, applied purely as a Y-axis rotation on the rig itself — never on the
    // camera — so it always reads as a clean turntable spin instead of an orbiting-camera illusion.
    private let turntableSpeed: Float = (2 * .pi) / 16

    /// Builds lighting/camera/rig and performs the first pose update. Safe to call multiple times; only
    /// runs once. Not done in `init()` because overriding `SCNScene`'s parameterless `init()` with
    /// `@MainActor` isolation conflicts with its nonisolated `NSObject` declaration.
    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        background.contents = UIColor(red: 0.045, green: 0.07, blue: 0.11, alpha: 1)
        fighter.guarding = true
        buildLighting()
        buildCamera()
        rootNode.addChildNode(rig.root)
        rig.update(from: fighter, deltaTime: 1.0 / 60.0, elapsedTime: 0)
    }

    func setStyle(_ style: FightStyle) {
        guard fighter.style != style else { return }
        fighter.style = style
        turntableStartTime = nil
    }

    func setOutfit(_ outfit: OutfitID) {
        rig.applyOutfit(outfit)
    }

    func update(at time: TimeInterval) {
        if startTime == nil { startTime = time }
        if turntableStartTime == nil { turntableStartTime = time }
        let elapsed = time - (startTime ?? time)
        rig.update(from: fighter, deltaTime: 1.0 / 60.0, elapsedTime: elapsed)
        // rig.update() just set root.eulerAngles.y from the fighter's fixed facing direction (this is the
        // "facing the camera" angle) — add the turntable spin on top of that so angle 0 always starts front-on.
        let turntableElapsed = Float(time - (turntableStartTime ?? time))
        rig.root.eulerAngles.y += turntableElapsed * turntableSpeed
    }

    private func buildCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 40
        camera.zNear = 0.05
        camera.zFar = 20
        cameraNode.camera = camera
        // Fixed framing — the rig spins in place (see update(at:)), so the camera never needs to move.
        // Pulled back and centered on the character's vertical middle so the whole body (feet to head,
        // roughly y in [0.14, 2.9]) fits in frame at every turntable angle.
        cameraNode.simdPosition = SIMD3<Float>(4.0, 2.05, -2.45)
        cameraNode.look(at: SCNVector3(0, 1.5, -0.05))
        rootNode.addChildNode(cameraNode)
    }

    private func buildLighting() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 420
        ambient.color = UIColor(white: 0.92, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 950
        key.color = UIColor(red: 1, green: 0.96, blue: 0.90, alpha: 1)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = SIMD3<Float>(-2.5, 4, 2.5)
        keyNode.look(at: SCNVector3(0, 1.4, 0))
        rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 320
        fill.color = UIColor(red: 0.55, green: 0.68, blue: 0.85, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.simdPosition = SIMD3<Float>(3, 2, -3)
        fillNode.look(at: SCNVector3(0, 1.4, 0))
        rootNode.addChildNode(fillNode)
    }
}

/// SwiftUI wrapper around `StylePreviewScene`, embedded in the waiting room so players can see each style's
/// stance update live as they tap between them.
struct StylePreviewView: UIViewRepresentable {
    let style: FightStyle
    let outfit: OutfitID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.scene.cameraNode
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.allowsCameraControl = false
        context.coordinator.scene.setStyle(style)
        context.coordinator.scene.setOutfit(outfit)
        context.coordinator.start()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.scene.setStyle(style)
        context.coordinator.scene.setOutfit(outfit)
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stop()
        view.isPlaying = false
    }

    @MainActor
    final class Coordinator: NSObject {
        let scene = StylePreviewScene()
        private var displayLink: CADisplayLink?

        func start() {
            scene.configure()
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func tick(_ link: CADisplayLink) {
            scene.update(at: link.timestamp)
        }
    }
}

private func material(color: UIColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNMaterial {
    let result = SCNMaterial()
    result.lightingModel = .physicallyBased
    result.diffuse.contents = color
    result.roughness.contents = roughness
    result.metalness.contents = metalness
    return result
}

private func box(width: CGFloat, height: CGFloat, length: CGFloat, radius: CGFloat, color: UIColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNNode {
    let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: radius)
    geometry.firstMaterial = material(color: color, roughness: roughness, metalness: metalness)
    return SCNNode(geometry: geometry)
}

private func cylinderBetween(_ start: SIMD3<Float>, _ end: SIMD3<Float>, radius: CGFloat, color: UIColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNNode {
    let direction = end - start
    let length = max(0.01, simd_length(direction))
    let geometry = SCNCylinder(radius: radius, height: CGFloat(length))
    geometry.radialSegmentCount = 10
    geometry.firstMaterial = material(color: color, roughness: roughness, metalness: metalness)
    let node = SCNNode(geometry: geometry)
    node.simdPosition = (start + end) * 0.5
    node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction / length)
    return node
}

private func attackEnvelope(_ progress: Float) -> Float {
    if progress <= 0.54 { return min(1, max(0, (progress - 0.16) / 0.38)) }
    return min(1, max(0, 1 - (progress - 0.54) / 0.28))
}

private func smoothStep(_ value: Float) -> Float {
    let clamped = min(1, max(0, value))
    return clamped * clamped * (3 - 2 * clamped)
}

private func mix(_ start: SIMD3<Float>, _ end: SIMD3<Float>, amount: Float) -> SIMD3<Float> {
    start + (end - start) * amount
}

func stabilizedCameraForward(
    current: SIMD3<Float>,
    desired: SIMD3<Float>,
    separation: Float,
    deltaTime: Double
) -> SIMD3<Float> {
    let currentAngle = atan2(current.z, current.x)
    let desiredAngle = atan2(desired.z, desired.x)
    var angleDelta = atan2(sin(desiredAngle - currentAngle), cos(desiredAngle - currentAngle))
    if separation < 0.72, abs(angleDelta) > .pi / 2 {
        angleDelta = 0
    }
    let response = Float(1 - exp(-deltaTime * 3.2))
    let maxStep = Float(deltaTime) * 1.25
    let step = min(maxStep, max(-maxStep, angleDelta * response))
    let angle = currentAngle + step
    return SIMD3<Float>(cos(angle), 0, sin(angle))
}

private extension SCNVector3 {
    init(_ value: SIMD3<Float>) {
        self.init(value.x, value.y, value.z)
    }
}

/// The practice room: a small boxing-gym floor built around one fixed heavy bag, hung dead center, which
/// the player's rig can freely circle to drill combos. Reuses the exact same dynamic shoulder-tracking
/// camera algorithm as the real match (`Arena3DScene.updateCamera`'s non-capture branch /
/// `stabilizedCameraForward`) with the bag standing in for the opponent, so the framing/composition matches
/// the main game even though the map dressing (wood floor, mats, mirror wall, jump ropes, a coach watching
/// from the back) is entirely gym-themed. Uses a custom parameterized `init(engine:outfit:)` rather than
/// overriding `SCNScene`'s bare `init()`, the same safe pattern `Arena3DScene` already uses (see its own
/// `init(engine:)`).
@MainActor
final class PracticeScene: SCNScene {
    weak var controller: PracticeController?
    let cameraNode = SCNNode()

    // The bag hangs at the practice engine's (bagX, bagY) center, i.e. world origin — see
    // `PracticeEngine.bagX/bagY` and `BoxerRig.update()`'s identical `(fighter.x - 295) * scale` convention.
    private static let bagWorldPosition = SIMD3<Float>(0, 1.35, 0)
    private static let bagPivotHeight: Float = 4.2
    private static let coachFighterPosition = (x: 295.0, y: 125.0)

    private let engine: PracticeEngine
    private let playerRig = BoxerRig(team: .player)
    private let bagPivot = SCNNode()
    private let coachNode = SCNNode()
    private var lastUpdateTime = 0.0
    private var publishTimer = 0.0
    private var cameraTarget = SIMD3<Float>(0, 1.35, 0)
    private var cameraForward = SIMD3<Float>(0, 0, -1)
    private var impactTimer = 0.0
    private var impactStrength: Float = 0
    private var impactPhase: Float = 0
    private var bagSwingAngle: Float = 0
    private var bagSwingVelocity: Float = 0
    private var bagSwingAxis = SIMD3<Float>(1, 0, 0)

    // Rotating speech-bubble tutorial tips shown above the coach's head, cycling every 12s. Messages are
    // pulled live from `L.coachTipMessages(for:)` (see `updateCoachTip`) so they follow the app's current
    // language instead of being frozen in Korean.
    private let coachTipTextGeometry = SCNText(string: "", extrusionDepth: 0.004)
    private let coachTipBackgroundNode = SCNNode(geometry: SCNPlane(width: 1, height: 0.4))
    private let coachTipTextNode = SCNNode()
    private var coachTipLanguage: AppLanguage = LocalizationManager.shared.language
    private var coachTipTimer: Double = 0
    private var coachTipIndex = -1

    init(engine: PracticeEngine, outfit: OutfitID) {
        self.engine = engine
        super.init()
        background.contents = UIColor(red: 0.058, green: 0.052, blue: 0.048, alpha: 1)
        fogColor = UIColor(red: 0.058, green: 0.052, blue: 0.048, alpha: 1)
        fogStartDistance = 13
        fogEndDistance = 21
        buildGym()
        buildLighting()
        buildCamera()
        rootNode.addChildNode(playerRig.root)

        // Practice room always dresses the player in the full gray gym outfit, regardless of whatever
        // outfit is equipped for the real match.
        playerRig.setPracticeAppearance(true)
        engine.onHit = { [weak self] punch, damage in
            self?.handleHit(punch: punch, damage: damage)
        }
        synchronizeVisuals(deltaTime: 1.0 / 60.0, elapsedTime: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setOutfit(_ outfit: OutfitID) {
        playerRig.setPracticeAppearance(true)
    }

    func update(at time: TimeInterval) {
        let deltaTime = lastUpdateTime == 0 ? 1.0 / 60.0 : min(0.05, time - lastUpdateTime)
        lastUpdateTime = time
        controller?.synchronizeHeldControls()
        engine.update(deltaTime: deltaTime)
        impactTimer = max(0, impactTimer - deltaTime)
        impactPhase += Float(deltaTime) * 84
        synchronizeVisuals(deltaTime: deltaTime, elapsedTime: time)

        publishTimer += deltaTime
        if publishTimer >= 0.08 {
            publishTimer = 0
            controller?.publishState()
        }
    }

    /// Called (via `engine.onHit`) the instant a punch lands on the bag: pops a floating damage number,
    /// gives the bag a pendulum swing impulse away from the punch, and nudges the camera the same way a
    /// landed hit jolts the camera in the real match.
    private func handleHit(punch: Punch, damage: Int) {
        let playerPos = worldPosition(engine.player)
        var direction = Self.bagWorldPosition - playerPos
        direction.y = 0
        if simd_length(direction) > 0.001 {
            direction = simd_normalize(direction)
        }
        // Swing axis perpendicular to the punch's travel direction, in the horizontal plane. Rotating the
        // pivot around `(-direction.z, 0, direction.x)` by a positive angle tilts the BOTTOM of the bag along
        // `+direction` (i.e. further away from the puncher, the same way a real bag recoils from a hit).
        bagSwingAxis = SIMD3<Float>(-direction.z, 0, direction.x)
        let punchWeight = Float(damage) / 8
        bagSwingVelocity += min(2.6, 1.1 + punchWeight * 0.5)

        impactTimer = 0.17
        impactStrength = min(1.35, 0.4 + Float(damage) / 16)
        impactPhase = 0

        spawnDamagePopup(damage: damage)
        controller?.notifyBagHit(damage: damage)
    }

    private func synchronizeVisuals(deltaTime: Double, elapsedTime: TimeInterval) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        playerRig.update(from: engine.player, deltaTime: deltaTime, elapsedTime: elapsedTime)
        updateBagSwing(deltaTime: deltaTime)
        updateCoach()
        updateCoachTip(deltaTime: deltaTime)
        updateCamera(deltaTime: deltaTime)
        SCNTransaction.commit()
    }

    /// Simple spring-damper pendulum: `bagSwingAngle` decays back to 0 (hanging straight) after each hit's
    /// impulse, rotated around the axis recorded at the moment of impact.
    private func updateBagSwing(deltaTime: Double) {
        let stiffness: Float = 34
        let damping: Float = 6.2
        let dt = Float(min(0.05, deltaTime))
        bagSwingVelocity += (-stiffness * bagSwingAngle - damping * bagSwingVelocity) * dt
        bagSwingAngle += bagSwingVelocity * dt
        bagPivot.simdOrientation = simd_quatf(angle: bagSwingAngle, axis: bagSwingAxis)
    }

    /// The coach keeps a fixed arms-crossed pose but continuously turns to face wherever the player is
    /// currently standing, using the same `atan2(dx, dy)` yaw convention `BoxerRig.update()` uses.
    private func updateCoach() {
        let dx = engine.player.x - Self.coachFighterPosition.x
        let dy = engine.player.y - Self.coachFighterPosition.y
        coachNode.eulerAngles.y = Float(atan2(dx, dy))
    }

    /// Cycles through the coach's tips every 12s, always re-reading `L.coachTipMessages(for:)` so a language
    /// change is picked up immediately (re-rendering the CURRENT tip in the new language right away) instead
    /// of leaving stale Korean text on screen until the next scheduled rotation.
    private func updateCoachTip(deltaTime: Double) {
        let language = LocalizationManager.shared.language
        let messages = L.coachTipMessages(for: language)
        if language != coachTipLanguage {
            coachTipLanguage = language
            if coachTipIndex < 0 || coachTipIndex >= messages.count { coachTipIndex = 0 }
            coachTipTextGeometry.string = messages[coachTipIndex]
            resizeCoachTipBubble()
        }
        coachTipTimer -= deltaTime
        if coachTipTimer <= 0 {
            coachTipIndex = (coachTipIndex + 1) % messages.count
            coachTipTextGeometry.string = messages[coachTipIndex]
            resizeCoachTipBubble()
            coachTipTimer = 12
        }
    }

    // Camera composition intentionally mirrors `Arena3DScene.updateCamera()`'s main-match formula exactly
    // (same spread mapping, distance/height/shoulder-offset constants) with the fixed bag standing in for
    // the live opponent, so the practice room reads as the same wide, elevated, shoulder-line tracking shot
    // as a real fight instead of the room's earlier tighter, scaled-down version.
    private func updateCamera(deltaTime: Double) {
        let player = worldPosition(engine.player)
        let bag = Self.bagWorldPosition
        let separation = simd_distance(player, bag)
        var desiredForward = bag - player
        desiredForward.y = 0
        if simd_length(desiredForward) > 0.001 {
            desiredForward = simd_normalize(desiredForward)
        } else {
            desiredForward = cameraForward
        }
        cameraForward = stabilizedCameraForward(
            current: cameraForward,
            desired: desiredForward,
            separation: separation,
            deltaTime: deltaTime
        )
        let forward = cameraForward
        let right = SIMD3<Float>(forward.z, 0, -forward.x)

        let spread = min(1, max(0, (separation - 2.0) / 5.0))
        let focusPull = 0.34 + 0.24 * spread
        let midpoint = (player + bag) * 0.5
        var target = player * Float(1 - focusPull) + midpoint * Float(focusPull)
        target += right * 0.16
        target.y = 1.42

        var distance = 6.75 + 1.55 * Float(spread)
        if separation < 2.25 { distance -= 0.22 }
        if engine.player.attack != nil { target += forward * 0.18 }
        let shoulderOffset: Float = separation < 2.6 ? 1.32 : 1.05
        var desiredPosition = player - forward * distance + right * shoulderOffset + SIMD3<Float>(0, 5.05, 0)
        if impactTimer > 0 {
            let decay = Float(impactTimer / 0.17)
            let impulse = impactStrength * decay * decay
            desiredPosition += right * sin(impactPhase) * 0.10 * impulse
            desiredPosition.y += cos(impactPhase * 1.37) * 0.055 * impulse
            target += forward * 0.045 * impulse
        }

        let positionBlend = Float(1 - exp(-deltaTime * 5.5))
        let targetBlend = Float(1 - exp(-deltaTime * 7.0))
        cameraNode.simdPosition += (desiredPosition - cameraNode.simdPosition) * positionBlend
        cameraTarget += (target - cameraTarget) * targetBlend
        cameraNode.look(at: SCNVector3(cameraTarget), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }

    private func worldPosition(_ fighter: FighterModel) -> SIMD3<Float> {
        let scale: Float = 0.025
        return SIMD3<Float>(Float(fighter.x - 295) * scale, 0.13, Float(fighter.y - 295) * scale)
    }

    /// A billboarded, rising, fading number spawned right above the bag each time it's hit, showing exactly
    /// how much damage that punch would have dealt in a real match.
    private func spawnDamagePopup(damage: Int) {
        let root = SCNNode()
        let textGeometry = SCNText(string: "-\(damage)", extrusionDepth: 0.008)
        textGeometry.font = UIFont.systemFont(ofSize: 13, weight: .black)
        textGeometry.flatness = 0.12
        let material = SCNMaterial()
        material.lightingModel = .constant
        let heavy = damage >= 11
        material.diffuse.contents = heavy ? UIColor(red: 1, green: 0.32, blue: 0.18, alpha: 1) : UIColor(red: 1, green: 0.86, blue: 0.30, alpha: 1)
        material.emission.contents = material.diffuse.contents
        material.emission.intensity = 0.5
        material.isDoubleSided = true
        material.readsFromDepthBuffer = false
        material.writesToDepthBuffer = false
        textGeometry.materials = [material]
        let textNode = SCNNode(geometry: textGeometry)
        let bounds = textNode.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation((bounds.min.x + bounds.max.x) * 0.5, (bounds.min.y + bounds.max.y) * 0.5, 0)
        let scale: Float = heavy ? 0.021 : 0.017
        textNode.scale = SCNVector3(scale, scale, scale)
        textNode.renderingOrder = 200
        root.renderingOrder = 200
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        root.constraints = [billboard]
        root.addChildNode(textNode)
        root.position = SCNVector3(
            Self.bagWorldPosition.x + Float.random(in: -0.12...0.12),
            Self.bagWorldPosition.y + 0.35,
            Self.bagWorldPosition.z
        )
        rootNode.addChildNode(root)

        let rise = SCNAction.moveBy(x: 0, y: 0.62, z: 0, duration: 0.75)
        rise.timingMode = .easeOut
        let fade = SCNAction.sequence([
            SCNAction.wait(duration: 0.3),
            SCNAction.fadeOut(duration: 0.45),
        ])
        root.runAction(SCNAction.group([rise, fade])) {
            root.removeFromParentNode()
        }
    }

    private func buildGym() {
        let woodFloor = UIColor(red: 0.38, green: 0.26, blue: 0.15, alpha: 1)
        let woodPlank = UIColor(red: 0.33, green: 0.22, blue: 0.13, alpha: 1)
        let wallColor = UIColor(red: 0.10, green: 0.095, blue: 0.10, alpha: 1)
        let matBlue = UIColor(red: 0.035, green: 0.29, blue: 0.62, alpha: 1)
        let matRed = UIColor(red: 0.60, green: 0.06, blue: 0.10, alpha: 1)

        let floor = box(width: 30, height: 0.1, length: 30, radius: 0, color: woodFloor, roughness: 0.7)
        floor.position = SCNVector3(0, -0.05, 0)
        rootNode.addChildNode(floor)

        // Alternating plank stripes for a simple wood-floor read without needing a texture asset.
        for i in stride(from: -14, through: 14, by: 2) {
            let plank = box(width: 1.0, height: 0.01, length: 30, radius: 0, color: woodPlank, roughness: 0.72)
            plank.position = SCNVector3(Float(i), 0.006, 0)
            rootNode.addChildNode(plank)
        }

        // Round two-tone boxing mat centered under the bag, matching the ring canvas's inset-circle motif.
        let matOuter = SCNCylinder(radius: 3.4, height: 0.03)
        matOuter.firstMaterial = material(color: matBlue, roughness: 0.75)
        let matOuterNode = SCNNode(geometry: matOuter)
        matOuterNode.position = SCNVector3(0, 0.017, 0)
        rootNode.addChildNode(matOuterNode)
        let matInner = SCNCylinder(radius: 1.7, height: 0.033)
        matInner.firstMaterial = material(color: matRed, roughness: 0.75)
        let matInnerNode = SCNNode(geometry: matInner)
        matInnerNode.position = SCNVector3(0, 0.018, 0)
        rootNode.addChildNode(matInnerNode)

        buildWalls(color: wallColor)
        buildHeavyBag()
        buildJumpRopes()
        buildDecorBags()
        rootNode.addChildNode(buildCoach())
    }

    private func buildWalls(color: UIColor) {
        let padColor = UIColor(red: 0.62, green: 0.09, blue: 0.13, alpha: 1)
        let mirrorFrame = UIColor(red: 0.32, green: 0.30, blue: 0.28, alpha: 1)

        let walls: [(SCNVector3, SCNVector3)] = [
            (SCNVector3(15, 2.1, 0), SCNVector3(0.15, 4.2, 30)),
            (SCNVector3(-15, 2.1, 0), SCNVector3(0.15, 4.2, 30)),
            (SCNVector3(0, 2.1, 15), SCNVector3(30, 4.2, 0.15)),
            (SCNVector3(0, 2.1, -15), SCNVector3(30, 4.2, 0.15)),
        ]
        for (position, size) in walls {
            let wall = box(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), radius: 0, color: color, roughness: 0.9)
            wall.position = position
            rootNode.addChildNode(wall)
        }

        // Low wall padding around the base, like a real gym's impact mats.
        for (position, size) in walls {
            let pad = box(width: CGFloat(size.x * 0.94), height: 0.9, length: CGFloat(size.z * 0.94), radius: 0.04, color: padColor, roughness: 0.6)
            pad.position = SCNVector3(position.x * 0.985, 0.5, position.z * 0.985)
            rootNode.addChildNode(pad)
        }

        // A glossy "mirror" panel on the back wall (north, -Z) the player faces while circling the bag.
        let mirror = box(width: 5.6, height: 3.0, length: 0.05, radius: 0, color: UIColor(red: 0.72, green: 0.80, blue: 0.86, alpha: 1), roughness: 0.06)
        mirror.geometry?.firstMaterial?.metalness.contents = 0.85
        mirror.position = SCNVector3(0, 2.3, -14.85)
        rootNode.addChildNode(mirror)
        let mirrorFrameNode = box(width: 5.8, height: 3.2, length: 0.08, radius: 0.02, color: mirrorFrame, roughness: 0.4, metalness: 0.5) as SCNNode
        mirrorFrameNode.position = SCNVector3(0, 2.3, -14.9)
        rootNode.addChildNode(mirrorFrameNode)
    }

    private func buildHeavyBag() {
        let gloveRed = UIColor(red: 0.68, green: 0.035, blue: 0.11, alpha: 1)
        let capColor = UIColor(red: 0.16, green: 0.15, blue: 0.16, alpha: 1)
        let chainColor = UIColor(red: 0.5, green: 0.51, blue: 0.53, alpha: 1)

        bagPivot.position = SCNVector3(0, Self.bagPivotHeight, 0)
        rootNode.addChildNode(bagPivot)

        let ceilingMount = box(width: 0.3, height: 0.1, length: 0.3, radius: 0.02, color: capColor, roughness: 0.55, metalness: 0.35)
        ceilingMount.position = SCNVector3(0, 0.05, 0)
        bagPivot.addChildNode(ceilingMount)

        // A much longer suspension chain than before, so the bag visibly hangs from the ceiling rather than
        // looking bolted directly to it.
        let chainLength: Float = 1.6
        let chain = SCNCylinder(radius: 0.024, height: CGFloat(chainLength))
        chain.firstMaterial = material(color: chainColor, roughness: 0.45, metalness: 0.55)
        let chainNode = SCNNode(geometry: chain)
        chainNode.position = SCNVector3(0, -0.83, 0)
        bagPivot.addChildNode(chainNode)

        let topCap = SCNNode(geometry: SCNCylinder(radius: 0.21, height: 0.1))
        topCap.geometry?.firstMaterial = material(color: capColor, roughness: 0.6, metalness: 0.25)
        topCap.position = SCNVector3(0, -1.68, 0)
        bagPivot.addChildNode(topCap)

        // A cylindrical body (real heavy bags are much more straight-sided than a rounded capsule/pill) with
        // small flattened dome caps at just the very top/bottom for a subtle rounded finish. Roughened up
        // (vs. a shinier finish) so the overhead spotlight doesn't throw a hard, pale specular highlight
        // across it.
        let bodyRadius: CGFloat = 0.45
        let bodyHeight: Float = 1.72
        let bodyCenterY: Float = -2.25
        let body = SCNNode(geometry: SCNCylinder(radius: bodyRadius, height: CGFloat(bodyHeight)))
        body.geometry?.firstMaterial = material(color: gloveRed, roughness: 0.75)
        body.position = SCNVector3(0, bodyCenterY, 0)
        bagPivot.addChildNode(body)

        let topDome = SCNNode(geometry: SCNSphere(radius: bodyRadius))
        topDome.geometry?.firstMaterial = material(color: gloveRed, roughness: 0.75)
        topDome.scale = SCNVector3(1, 0.32, 1)
        // Sunk slightly INTO the cylinder (rather than sitting exactly on its flat cap plane) so the dome's
        // widest ring (its equator) is fully submerged and only its curved cap pokes out -- an exact
        // coplanar sphere-equator/cylinder-cap edge is prone to floating-point z-fighting, which is the most
        // likely real cause of the reported "white ring" seam around the bag.
        topDome.position = SCNVector3(0, bodyCenterY + bodyHeight / 2 - 0.03, 0)
        bagPivot.addChildNode(topDome)

        let bottomDome = topDome.clone()
        bottomDome.position = SCNVector3(0, bodyCenterY - bodyHeight / 2 + 0.03, 0)
        bagPivot.addChildNode(bottomDome)

        // Horizontal stitch seams, purely cosmetic, to read clearly as a boxing heavy bag from a distance.
        // Recessed flush with (rather than protruding past) the body's own radius, and matte, so they don't
        // catch a bright specular highlight ring under the overhead spotlight.
        for offsetY in [-1.65, -2.25, -2.85] as [Float] {
            let seam = SCNNode(geometry: SCNTorus(ringRadius: 0.434, pipeRadius: 0.012))
            seam.geometry?.firstMaterial = material(color: capColor, roughness: 0.9)
            seam.position = SCNVector3(0, offsetY, 0)
            bagPivot.addChildNode(seam)
        }
    }

    /// A few jump ropes casually dropped on the mat/floor -- coiled loops with trailing tails and handles,
    /// laid flat against the ground -- instead of neatly hung on wall pegs, so they read as spare gym gear
    /// left lying around rather than stiff wall decor. Positions stay outside the player's circling path
    /// (`PracticeEngine.maxRadius` keeps the player within ~4.6 world units of the bag).
    private func buildJumpRopes() {
        let drops: [(x: Float, z: Float, rotation: Float)] = [
            (5.6, 3.2, 0.5),
        ]
        for drop in drops {
            let rope = buildScatteredJumpRope()
            rope.position = SCNVector3(drop.x, 0.02, drop.z)
            rope.eulerAngles.y = drop.rotation
            rootNode.addChildNode(rope)
        }
    }

    /// One jump rope modeled as a loose curl lying flat on the floor: two overlapping coiled loops (so it
    /// doesn't read as one perfect ring) plus a straight tail leading out to a handle on each end.
    private func buildScatteredJumpRope() -> SCNNode {
        let ropeColor = UIColor(red: 0.72, green: 0.10, blue: 0.14, alpha: 1)
        let handleColor = UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
        let root = SCNNode()

        let coil = SCNNode(geometry: SCNTorus(ringRadius: 0.22, pipeRadius: 0.014))
        coil.geometry?.firstMaterial = material(color: ropeColor, roughness: 0.55)
        coil.eulerAngles.x = .pi / 2
        coil.position = SCNVector3(0, 0.014, 0)
        root.addChildNode(coil)

        let coil2 = SCNNode(geometry: SCNTorus(ringRadius: 0.15, pipeRadius: 0.013))
        coil2.geometry?.firstMaterial = material(color: ropeColor, roughness: 0.55)
        coil2.eulerAngles.x = .pi / 2
        coil2.position = SCNVector3(0.16, 0.013, 0.1)
        root.addChildNode(coil2)

        for side: Float in [-1, 1] {
            let tail = SCNNode(geometry: SCNCylinder(radius: 0.013, height: 0.62))
            tail.geometry?.firstMaterial = material(color: ropeColor, roughness: 0.55)
            tail.eulerAngles.z = .pi / 2
            tail.position = SCNVector3(side * 0.5, 0.013, side * 0.12)
            root.addChildNode(tail)

            let handle = SCNNode(geometry: SCNCapsule(capRadius: 0.032, height: 0.22))
            handle.geometry?.firstMaterial = material(color: handleColor, roughness: 0.6)
            handle.eulerAngles.z = .pi / 2
            handle.position = SCNVector3(side * 0.83, 0.032, side * 0.16)
            root.addChildNode(handle)
        }
        return root
    }

    /// A couple of smaller, static decorative heavy bags in the back corners (not hittable — just set
    /// dressing) so the room reads unmistakably as a boxing gym rather than an empty mat with one bag.
    private func buildDecorBags() {
        let darkBrown = UIColor(red: 0.24, green: 0.16, blue: 0.11, alpha: 1)
        let chainColor = UIColor(red: 0.45, green: 0.46, blue: 0.48, alpha: 1)
        for x: Float in [-12.5, 12.5] {
            let chain = SCNNode(geometry: SCNCylinder(radius: 0.016, height: 0.7))
            chain.geometry?.firstMaterial = material(color: chainColor, roughness: 0.4, metalness: 0.7)
            chain.position = SCNVector3(x, 3.35, -12.5)
            rootNode.addChildNode(chain)

            let body = SCNNode(geometry: SCNCapsule(capRadius: 0.26, height: 1.05))
            body.geometry?.firstMaterial = material(color: darkBrown, roughness: 0.6)
            body.position = SCNVector3(x, 2.4, -12.5)
            rootNode.addChildNode(body)
        }
    }

    /// A static, arms-crossed gym coach standing behind the bag, always turned to face wherever the player
    /// currently is (see `updateCoach()`). Built from plain primitives rather than a full `BoxerRig` since
    /// the pose never animates and the coach shouldn't be mistaken for a fighting-team rig (neutral
    /// tracksuit colors instead of the player/rival blue/red).
    private func buildCoach() -> SCNNode {
        let skin = material(color: UIColor(red: 0.70, green: 0.51, blue: 0.37, alpha: 1), roughness: 0.65)
        let tracksuit = material(color: UIColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1), roughness: 0.55)
        let shoe = material(color: UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1), roughness: 0.5)
        // Grizzled gray hair/eyebrows/mustache (instead of solid dark-brown) so the coach reads as
        // noticeably older/more experienced rather than a young trainer.
        let hair = material(color: UIColor(red: 0.72, green: 0.72, blue: 0.74, alpha: 1), roughness: 0.6)
        let dark = material(color: UIColor(red: 0.05, green: 0.04, blue: 0.05, alpha: 1), roughness: 0.4)

        coachNode.name = "gymCoach"
        coachNode.position = SCNVector3(
            Float(Self.coachFighterPosition.x - 295) * 0.025,
            0.13,
            Float(Self.coachFighterPosition.y - 295) * 0.025
        )

        let torso = SCNNode(geometry: SCNCapsule(capRadius: 0.34, height: 1.0))
        torso.geometry?.materials = [tracksuit]
        torso.position = SCNVector3(0, 1.5, 0)
        coachNode.addChildNode(torso)

        let neck = SCNNode(geometry: SCNCylinder(radius: 0.13, height: 0.14))
        neck.geometry?.materials = [skin]
        neck.position = SCNVector3(0, 2.02, 0)
        coachNode.addChildNode(neck)

        let head = SCNNode(geometry: SCNSphere(radius: 0.26))
        head.geometry?.materials = [skin]
        head.position = SCNVector3(0, 2.28, 0.01)
        head.scale = SCNVector3(0.9, 1.05, 0.92)
        coachNode.addChildNode(head)

        // Face -- everything below is parented to `head` so it automatically inherits its position/scale.
        for side: Float in [-1, 1] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.03))
            eye.geometry?.materials = [dark]
            eye.position = SCNVector3(side * 0.1, 0.03, 0.235)
            head.addChildNode(eye)

            let brow = SCNNode(geometry: SCNBox(width: 0.09, height: 0.02, length: 0.02, chamferRadius: 0.008))
            brow.geometry?.materials = [hair]
            brow.position = SCNVector3(side * 0.1, 0.09, 0.225)
            brow.eulerAngles.z = side * 0.12
            head.addChildNode(brow)

            let ear = SCNNode(geometry: SCNSphere(radius: 0.05))
            ear.geometry?.materials = [skin]
            ear.position = SCNVector3(side * 0.265, 0, -0.01)
            head.addChildNode(ear)
        }
        let mouth = SCNNode(geometry: SCNBox(width: 0.11, height: 0.018, length: 0.02, chamferRadius: 0.008))
        mouth.geometry?.materials = [dark]
        mouth.position = SCNVector3(0, -0.12, 0.24)
        head.addChildNode(mouth)

        let nose = SCNNode(geometry: SCNCone(topRadius: 0.006, bottomRadius: 0.028, height: 0.05))
        nose.geometry?.materials = [skin]
        nose.position = SCNVector3(0, -0.02, 0.25)
        nose.eulerAngles.x = .pi / 2
        head.addChildNode(nose)

        // A gray mustache sitting right above the mouth -- one of the clearest, cheapest "older" markers
        // achievable with plain primitives.
        let mustache = SCNNode(geometry: SCNBox(width: 0.13, height: 0.028, length: 0.03, chamferRadius: 0.012))
        mustache.geometry?.materials = [hair]
        mustache.position = SCNVector3(0, -0.075, 0.245)
        head.addChildNode(mustache)

        let hairCap = SCNNode(geometry: SCNSphere(radius: 0.27))
        hairCap.geometry?.materials = [hair]
        hairCap.scale = SCNVector3(1.03, 0.55, 1.05)
        hairCap.position = SCNVector3(0, 0.09, -0.04)
        head.addChildNode(hairCap)

        // Shoulder joints smooth the transition from torso to arm, matching `BoxerRig`'s own approach.
        let leftShoulder = SCNVector3(0.34, 1.86, 0.05)
        let rightShoulder = SCNVector3(-0.34, 1.86, 0.05)
        for shoulderPoint in [leftShoulder, rightShoulder] {
            let joint = SCNNode(geometry: SCNSphere(radius: 0.145))
            joint.geometry?.materials = [tracksuit]
            joint.position = shoulderPoint
            coachNode.addChildNode(joint)
        }

        // Crossed arms built as two real upper-arm/forearm segments per side (instead of one stiff angled
        // capsule) so the elbow bend reads naturally, with the right arm resting slightly in front (larger
        // Z) so it visibly layers on top of the left, and small hands where each forearm comes to rest.
        let leftElbow = SCNVector3(0.08, 1.62, 0.30)
        let leftHandPoint = SCNVector3(-0.30, 1.68, 0.33)
        let rightElbow = SCNVector3(-0.08, 1.58, 0.34)
        let rightHandPoint = SCNVector3(0.30, 1.64, 0.38)

        coachNode.addChildNode(limbSegment(from: leftShoulder, to: leftElbow, radius: 0.105, material: tracksuit))
        coachNode.addChildNode(limbSegment(from: leftElbow, to: leftHandPoint, radius: 0.09, material: tracksuit))
        let leftHand = SCNNode(geometry: SCNSphere(radius: 0.075))
        leftHand.geometry?.materials = [skin]
        leftHand.position = leftHandPoint
        coachNode.addChildNode(leftHand)

        coachNode.addChildNode(limbSegment(from: rightShoulder, to: rightElbow, radius: 0.105, material: tracksuit))
        coachNode.addChildNode(limbSegment(from: rightElbow, to: rightHandPoint, radius: 0.09, material: tracksuit))
        let rightHand = SCNNode(geometry: SCNSphere(radius: 0.075))
        rightHand.geometry?.materials = [skin]
        rightHand.position = rightHandPoint
        coachNode.addChildNode(rightHand)

        for side: Float in [-1, 1] {
            let leg = SCNNode(geometry: SCNCapsule(capRadius: 0.14, height: 0.95))
            leg.geometry?.materials = [tracksuit]
            leg.position = SCNVector3(side * 0.16, 0.62, 0)
            coachNode.addChildNode(leg)

            let foot = SCNNode(geometry: SCNBox(width: 0.18, height: 0.12, length: 0.32, chamferRadius: 0.05))
            foot.geometry?.materials = [shoe]
            foot.position = SCNVector3(side * 0.16, 0.08, 0.08)
            coachNode.addChildNode(foot)
        }

        coachNode.addChildNode(buildCoachTipLabel())

        return coachNode
    }

    /// Builds a single static capsule spanning two fixed points, used for the coach's crossed-arm segments
    /// (which never animate, unlike `BoneNode`'s per-frame version used by `BoxerRig`).
    private func limbSegment(from start: SCNVector3, to end: SCNVector3, radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let a = SIMD3<Float>(start.x, start.y, start.z)
        let b = SIMD3<Float>(end.x, end.y, end.z)
        let delta = b - a
        let length = max(0.01, simd_length(delta))
        let node = SCNNode(geometry: SCNCapsule(capRadius: radius, height: CGFloat(length)))
        node.geometry?.firstMaterial = material
        node.simdPosition = (a + b) * 0.5
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: delta / length)
        return node
    }

    /// A billboarded speech-bubble label floating above the coach's head, showing rotating boxing-technique
    /// tips in white text (see `L.coachTipMessages`/`updateCoachTip`). Styled after `BoxerRig.identityLabel`
    /// (dark backdrop, billboard constraint, unlit/no-depth-test materials so it always reads clearly), but
    /// with no decorative tail shape and a size that's recomputed to fit each message exactly (see
    /// `resizeCoachTipBubble`) rather than a single fixed guessed box.
    private func buildCoachTipLabel() -> SCNNode {
        let root = SCNNode()
        guard let background = coachTipBackgroundNode.geometry as? SCNPlane else { return root }
        background.cornerRadius = 0.12
        let backgroundMaterial = SCNMaterial()
        backgroundMaterial.lightingModel = .constant
        backgroundMaterial.diffuse.contents = UIColor.black.withAlphaComponent(0.72)
        backgroundMaterial.isDoubleSided = true
        backgroundMaterial.readsFromDepthBuffer = false
        backgroundMaterial.writesToDepthBuffer = false
        background.materials = [backgroundMaterial]
        coachTipBackgroundNode.name = "coachTipBackground"
        coachTipBackgroundNode.renderingOrder = 100

        // Wraps within a generous max width but an effectively unbounded height, so long sentences wrap to
        // multiple lines while the ACTUAL rendered bounds (measured in `resizeCoachTipBubble`) -- not this
        // container -- determine the bubble's final size and the text's centering.
        coachTipTextGeometry.font = UIFont.systemFont(ofSize: 9, weight: .bold)
        coachTipTextGeometry.flatness = 0.15
        coachTipTextGeometry.isWrapped = true
        coachTipTextGeometry.containerFrame = CGRect(x: 0, y: 0, width: 130, height: 400)
        coachTipTextGeometry.truncationMode = "none"
        coachTipTextGeometry.alignmentMode = "center"
        let textMaterial = SCNMaterial()
        textMaterial.lightingModel = .constant
        textMaterial.diffuse.contents = UIColor.white
        textMaterial.isDoubleSided = true
        textMaterial.readsFromDepthBuffer = false
        textMaterial.writesToDepthBuffer = false
        coachTipTextGeometry.materials = [textMaterial]
        coachTipTextNode.geometry = coachTipTextGeometry
        coachTipTextNode.name = "coachTipText"
        coachTipTextNode.scale = SCNVector3(0.021, 0.021, 0.021)
        coachTipTextNode.position = SCNVector3(0, 0, 0.008)
        coachTipTextNode.renderingOrder = 101

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        root.constraints = [billboard]
        root.addChildNode(coachTipBackgroundNode)
        root.addChildNode(coachTipTextNode)
        root.position = SCNVector3(0, 3.0, 0)
        root.name = "coachTipRoot"

        let language = LocalizationManager.shared.language
        coachTipLanguage = language
        let messages = L.coachTipMessages(for: language)
        coachTipIndex = 0
        coachTipTextGeometry.string = messages[coachTipIndex]
        coachTipTimer = 12
        resizeCoachTipBubble()

        return root
    }

    /// Resizes the bubble background and recenters the text to exactly fit whatever message is currently
    /// showing, by measuring the text geometry's own actual bounding box rather than assuming a fixed size --
    /// fixes both short messages looking stranded near the top of an oversized box, and long messages
    /// needing more room, in one general-purpose pass.
    private func resizeCoachTipBubble() {
        guard let background = coachTipBackgroundNode.geometry as? SCNPlane else { return }
        let textScale: Float = 0.021
        let bounds = coachTipTextGeometry.boundingBox
        let rawWidth = Float(max(0.1, bounds.max.x - bounds.min.x))
        let rawHeight = Float(max(0.1, bounds.max.y - bounds.min.y))
        let horizontalPadding: Float = 0.4
        let verticalPadding: Float = 0.34
        background.width = CGFloat(rawWidth * textScale + horizontalPadding)
        background.height = CGFloat(rawHeight * textScale + verticalPadding)

        let midX = (bounds.max.x + bounds.min.x) / 2
        let midY = (bounds.max.y + bounds.min.y) / 2
        coachTipTextNode.pivot = SCNMatrix4MakeTranslation(midX, midY, 0)
    }

    private func buildCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 50
        camera.zNear = 0.08
        camera.zFar = 70
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3<Float>(0, 5.18, 9.1)
        cameraNode.look(at: SCNVector3(cameraTarget), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        rootNode.addChildNode(cameraNode)
    }

    private func buildLighting() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 330
        ambient.color = UIColor(white: 0.88, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 950
        key.color = UIColor(red: 1, green: 0.95, blue: 0.86, alpha: 1)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = SIMD3<Float>(-3, 5, 3)
        keyNode.look(at: SCNVector3(0, 1.3, 0))
        rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 320
        fill.color = UIColor(red: 0.58, green: 0.66, blue: 0.80, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.simdPosition = SIMD3<Float>(3.5, 3.5, -3)
        fillNode.look(at: SCNVector3(0, 1.3, 0))
        rootNode.addChildNode(fillNode)

        let bagSpot = SCNLight()
        bagSpot.type = .spot
        bagSpot.intensity = 550
        bagSpot.spotInnerAngle = 25
        bagSpot.spotOuterAngle = 80
        bagSpot.color = UIColor(red: 1, green: 0.96, blue: 0.90, alpha: 1)
        let bagSpotNode = SCNNode()
        bagSpotNode.light = bagSpot
        bagSpotNode.position = SCNVector3(0, 4.8, 1.5)
        bagSpotNode.look(at: SCNVector3(0, 1.35, 0))
        rootNode.addChildNode(bagSpotNode)
    }
}

/// SwiftUI wrapper around `PracticeScene`, mirroring `Arena3DView`'s CADisplayLink-driven update loop.
struct PracticeSceneView: UIViewRepresentable {
    @ObservedObject var controller: PracticeController

    func makeCoordinator() -> Coordinator {
        Coordinator(scene: controller.scene3D)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.scene.cameraNode
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.allowsCameraControl = false
        context.coordinator.start()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stop()
        view.isPlaying = false
    }

    @MainActor
    final class Coordinator: NSObject {
        let scene: PracticeScene
        private var displayLink: CADisplayLink?

        init(scene: PracticeScene) {
            self.scene = scene
        }

        func start() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func tick(_ link: CADisplayLink) {
            scene.update(at: link.timestamp)
        }
    }
}