import QuartzCore
import SceneKit
import SwiftUI
import UIKit

@MainActor
final class Arena3DScene: SCNScene {
    weak var controller: GameController?
    let cameraNode = SCNNode()

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
        synchronizeVisuals(deltaTime: 1.0 / 60.0, elapsedTime: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(at time: TimeInterval) {
        let deltaTime = lastUpdateTime == 0 ? 1.0 / 60.0 : min(0.05, time - lastUpdateTime)
        lastUpdateTime = time
        controller?.synchronizeHeldControls()
        engine.update(deltaTime: deltaTime)
        updateImpact(deltaTime: deltaTime)
        synchronizeVisuals(deltaTime: deltaTime, elapsedTime: time)

        publishTimer += deltaTime
        if publishTimer >= 0.08 {
            publishTimer = 0
            controller?.publishSnapshot()
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
        playerRig.update(from: engine.player, deltaTime: deltaTime, elapsedTime: elapsedTime)
        enemyRig.update(from: engine.enemy, deltaTime: deltaTime, elapsedTime: elapsedTime)
        updateCamera(deltaTime: deltaTime)
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
    private let neck: SCNNode
    private let head: SCNNode
    private let identityLabel: SCNNode
    private let leftEye: SCNNode
    private let rightEye: SCNNode
    private let leftGlove: SCNNode
    private let rightGlove: SCNNode
    private let leftFoot: SCNNode
    private let rightFoot: SCNNode
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
        skinMaterial = material(color: UIColor(red: 0.74, green: 0.42, blue: 0.26, alpha: 1), roughness: 0.62)
        teamMaterial = material(color: teamColor, roughness: 0.34, metalness: 0.08)
        let gloveMaterial = material(color: gloveColor, roughness: 0.24, metalness: 0.10)
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

        leftGlove = BoxerRig.glove(material: gloveMaterial, handedness: 1)
        rightGlove = BoxerRig.glove(material: gloveMaterial, handedness: -1)
        leftFoot = BoxerRig.shoe(material: teamMaterial, sole: darkMaterial)
        rightFoot = BoxerRig.shoe(material: teamMaterial, sole: darkMaterial)
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
            leftUpperArm.node, leftForearm.node, rightUpperArm.node, rightForearm.node,
            leftThigh.node, leftShin.node, rightThigh.node, rightShin.node,
            leftTrail.node, rightTrail.node,
        ] {
            node.castsShadow = true
            poseRoot.addChildNode(node)
        }
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
        let duckBlend = Float(1 - exp(-deltaTime * 15))
        duckVisual += (Float(fighter.duckDirection) - duckVisual) * duckBlend

        var pose = FightPose.neutral(stride: stride)
        pose.torsoY += idle
        if moving, fighter.attack == nil, !fighter.guarding {
            pose.applyMovement(forward: forwardMotion, strafe: strafeMotion, strideCycle: strideCycle)
        }
        if fighter.guarding { pose.applyGuard() }
        if abs(duckVisual) > 0.01 { pose.applyDuck(direction: duckVisual) }
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
        trunks.simdPosition = SIMD3<Float>(0, 0.86 - pose.bodyDrop * 0.72, 0)
        waistband.simdPosition = SIMD3<Float>(0, 1.08 - pose.bodyDrop * 0.82, 0)
        neck.simdPosition = SIMD3<Float>(0, 2.02 + idle - pose.bodyDrop, 0.015)
        head.simdPosition = SIMD3<Float>(0, 2.28 + idle - pose.bodyDrop, 0.04)
        head.eulerAngles.z = -pose.torsoLean * 0.45
        identityLabel.simdPosition = SIMD3<Float>(0, fighter.knockedOut ? 0.62 : 2.80 + idle - pose.bodyDrop, 0)
        leftEye.simdPosition = SIMD3<Float>(-0.11, 2.34 + idle - pose.bodyDrop, 0.265)
        rightEye.simdPosition = SIMD3<Float>(0.11, 2.34 + idle - pose.bodyDrop, 0.265)

        updateArm(shoulder: pose.leftShoulder, elbow: pose.leftElbow, glove: pose.leftGlove, upper: leftUpperArm, lower: leftForearm, gloveNode: leftGlove)
        updateArm(shoulder: pose.rightShoulder, elbow: pose.rightElbow, glove: pose.rightGlove, upper: rightUpperArm, lower: rightForearm, gloveNode: rightGlove)
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
                let end = leadLeft ? pose.leftGlove : pose.rightGlove
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

    private static func glove(material: SCNMaterial, handedness: Float) -> SCNNode {
        let node = SCNNode()
        let palm = SCNNode(geometry: SCNSphere(radius: 0.18))
        palm.name = "glovePalm"
        palm.geometry?.materials = [material]
        palm.scale = SCNVector3(1.02, 1.02, 1.20)
        palm.position.z = 0.025

        let knuckles = SCNNode(geometry: SCNSphere(radius: 0.16))
        knuckles.name = "gloveKnuckles"
        knuckles.geometry?.materials = [material]
        knuckles.scale = SCNVector3(1.23, 0.78, 0.88)
        knuckles.position = SCNVector3(0, 0.07, 0.15)

        let thumb = SCNNode(geometry: SCNCapsule(capRadius: 0.065, height: 0.20))
        thumb.name = "gloveThumb"
        thumb.geometry?.materials = [material]
        thumb.position = SCNVector3(-0.13 * handedness, -0.015, 0.085)
        thumb.eulerAngles.z = 0.55 * handedness

        let cuff = SCNNode(geometry: SCNCylinder(radius: 0.135, height: 0.22))
        cuff.name = "gloveCuff"
        cuff.geometry?.materials = [material]
        cuff.position.y = -0.18

        let cuffRim = SCNNode(geometry: SCNTorus(ringRadius: 0.12, pipeRadius: 0.018))
        cuffRim.name = "gloveCuffRim"
        cuffRim.geometry?.materials = [material]
        cuffRim.position.y = -0.29

        node.addChildNode(palm)
        node.addChildNode(knuckles)
        node.addChildNode(thumb)
        node.addChildNode(cuff)
        node.addChildNode(cuffRim)
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

    static func neutral(stride: Float) -> FightPose {
        var pose = FightPose()
        pose.leftKnee.z += stride
        pose.rightKnee.z -= stride
        pose.leftFoot.z += stride
        pose.rightFoot.z -= stride
        return pose
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

    mutating func applyGuard() {
        leftElbow = SIMD3<Float>(0.34, 1.66, 0.14)
        rightElbow = SIMD3<Float>(-0.34, 1.66, 0.14)
        leftGlove = SIMD3<Float>(0.20, 2.16, 0.30)
        rightGlove = SIMD3<Float>(-0.20, 2.16, 0.30)
        torsoLean = -0.05
    }

    mutating func applyDuck(direction: Float) {
        let amount = min(1, abs(direction))
        bodyDrop = 0.42 * amount
        rootZ = -0.08 * amount
        torsoY -= 0.40 * amount
        torsoLean = -direction * 0.28
        torsoPitch = 0.16 * amount
        let shift = -direction * 0.24
        leftShoulder.x += shift
        rightShoulder.x += shift
        leftGlove.x += shift
        rightGlove.x += shift
        leftShoulder.y -= 0.38 * amount
        rightShoulder.y -= 0.38 * amount
        leftElbow.y -= 0.34 * amount
        rightElbow.y -= 0.34 * amount
        leftGlove.y -= 0.30 * amount
        rightGlove.y -= 0.30 * amount
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

    init(radius: CGFloat, material: SCNMaterial) {
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

private func material(color: UIColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNMaterial {
    let result = SCNMaterial()
    result.lightingModel = .physicallyBased
    result.diffuse.contents = color
    result.roughness.contents = roughness
    result.metalness.contents = metalness
    return result
}

private func box(width: CGFloat, height: CGFloat, length: CGFloat, radius: CGFloat, color: UIColor, roughness: CGFloat) -> SCNNode {
    let geometry = SCNBox(width: width, height: height, length: length, chamferRadius: radius)
    geometry.firstMaterial = material(color: color, roughness: roughness)
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