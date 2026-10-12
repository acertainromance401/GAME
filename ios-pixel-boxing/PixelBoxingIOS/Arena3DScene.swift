/*
 Arena3DScene.swift

 파일 설명:
 - SceneKit 기반의 3D 아레나 구현 파일입니다. 카메라, 라이트, 링, 관중, 복서 리그(BoxerRig) 등을 구성하고
     `CombatEngine`의 상태를 읽어 매 프레임 씬을 갱신합니다.
 - `BoxerRig`는 복서의 시각적 리그(뼈대/관절/글러브/의상)를 관리하며, 애니메이션과 포즈 갱신을 수행합니다.

 사용 영향 및 주의사항:
 - 이 파일은 시각적 표현과 연출을 담당하며, 게임 규칙의 변경은 여기서 이루어지지 않습니다.
 - SceneKit 노드/트랜잭션 관련 변경은 렌더링과 성능에 민감하므로 실제 장비에서 성능을 확인하세요.
*/

import QuartzCore
@preconcurrency import SceneKit
import SwiftUI
import UIKit

enum ArenaCinematicPresentation {
    case matchIntro
    case appOpening
    case menuPortrait
    case storyIntroduction
    case storyRivalScene
}

private enum BoxerAppearance {
    case classic
    case pressure
    case outboxer
    case counter
    case slugger
    case rival

    init(opponent: StoryOpponent?) {
        switch opponent {
        case .pressure: self = .pressure
        case .outboxer: self = .outboxer
        case .counter: self = .counter
        case .slugger: self = .slugger
        case .rival: self = .rival
        default: self = .classic
        }
    }
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
    /// `Arena3DScene`
    /// - 역할: 게임 엔진 상태를 3D 씬으로 시각화합니다. 엔진(CombatEngine)에서 위치·애니메이션 상태를 가져와
    ///   `BoxerRig`와 카메라를 업데이트하고, 씬을 렌더링 가능한 상태로 유지합니다.
    weak var controller: GameController?
    let cameraNode = SCNNode()

    /// TEMP (icon/splash capture only): when set, pulls the two fighters closer together and locks the
    /// camera to a tight face-off framing instead of the normal dynamic tracking shot, so a single
    /// screenshot can be cropped into app icon / loading screen art. Remove once art is captured.
    static let isIconCaptureMode = ProcessInfo.processInfo.environment["RIVAL_ICON_CAPTURE"] != nil

    private let engine: CombatEngine
    private let presentation: CombatPresentation
    private var playerRig: BoxerRig
    private var playerAppearance: StoryOpponent?
    private var playerOutfit = OutfitID.classic
    private let enemyRig: BoxerRig
    private let portraitFighter = FighterModel(name: "RIVAL", x: 295, y: 295)
    private var lightBaselines: [(light: SCNLight, intensity: CGFloat)] = []
    private var lastUpdateTime = 0.0
    private var publishTimer = 0.0
    private var cameraTarget = SIMD3<Float>(0, 1.35, 0)
    private var cameraForward = SIMD3<Float>(1, 0, 0)
    private var cameraContactOffset = SIMD3<Float>.zero
    private var visualElapsedTime = 0.0
    private var reducedMotion = false
    private var cinematicMode = false
    private var cinematicElapsed = 0.0
    private var cinematicPresentation = ArenaCinematicPresentation.matchIntro
    private var openingPlayerState: CinematicFighterState?
    private var openingEnemyState: CinematicFighterState?
    private var openingImpactPulse: Float = 0
    private let introductionPlayer = FighterModel(name: "PLAYER", x: 170, y: 295)
    private let introductionEnemy = FighterModel(name: "PRESSURE", x: 420, y: 295)
    private var introductionClip: StoryIntroClip?
    private var introductionShort = false
    private var introductionSuspended = false
    private var introductionEntranceDuration = 0.0
    private var introductionDuration = 0.0
    private var rivalSceneClip: StoryIntroClip?
    private var rivalSceneDuration = 0.0
    private var rivalSceneChapter = StoryOpponent.pressure
    private lazy var rivalSceneRig = BoxerRig(team: .rival)
    private var championshipPlayerRig: BoxerRig?
    private var championshipVictoryRig: BoxerRig?
    private var championshipApplauseRigs: [(rig: BoxerRig, style: FightStyle)] = []
    private lazy var storyCoachRig = GymCoachRig()
    private lazy var championshipIntroBelt = makeRivalChampionshipBelt()
    private lazy var championshipCornerSeat = makeChampionshipCornerSeat()
    private let championshipCorner = SIMD3<Float>(4.5, 0.13, -4.5)
    private let championshipHeading: Float = -.pi / 4
    private var playerBeltEquipped = false
    private lazy var rivalTrainingStage = makeRivalTrainingStage()
    private lazy var rivalReplayMonitor = makeRivalReplayMonitor()
    private lazy var rivalTargetBag = makeRivalTargetBag()
    private lazy var rivalChampionshipBelt = makeRivalChampionshipBelt()
    private var rivalReplaySurface: SCNMaterial?
    private var rivalReplayProgress: SCNNode?
    private var rivalReplayFrames: [UIImage] = []
    private var rivalSceneHiddenNodes: [(node: SCNNode, hidden: Bool)] = []

    private var usesPressureGym: Bool { engine.storyBout?.opponent == .pressure }
    private var usesRegionalHall: Bool {
        switch engine.storyBout?.opponent {
        case .outboxer, .counter, .slugger, .rival: true
        default: false
        }
    }

    private var usesOpeningCaptureBeat: Bool {
        ProcessInfo.processInfo.environment["RIVAL_OPENING_CAPTURE_BEAT"] == "1"
    }

    init(engine: CombatEngine, presentation: CombatPresentation = CombatPresentation()) {
        // Arena3DScene 초기화
        // - `engine`: 시뮬레이션 엔진(CombatEngine)으로부터 매 프레임 위치/애니메이션 상태를 읽습니다.
        // - `presentation`: CombatPresentation(프레젠테이션 레이어)을 주입하면 카메라 임펄스/임팩트 가시화 등
        //   연출 정보를 받아 씬 연출에 반영합니다.
        // 초기화는 씬 그래프(링/포스트/관중/라이팅/카메라/복서 리그)를 구성하고 첫 프레임 동기화를 수행합니다.
        self.engine = engine
        self.presentation = presentation
        playerRig = BoxerRig(team: .player)
        enemyRig = BoxerRig(team: .rival, identityText: engine.storyBout?.opponent.title(for: LocalizationManager.shared.language),
                    appearance: BoxerAppearance(opponent: engine.storyBout?.opponent))
        super.init()
        portraitFighter.facingX = 0
        portraitFighter.facingY = 1
        portraitFighter.guarding = engine.storyBout?.opponent == .pressure
        switch engine.storyBout?.opponent {
        case .outboxer: portraitFighter.style = .outboxing
        case .slugger: portraitFighter.style = .infighting
        default: portraitFighter.style = .standard
        }
        background.contents = UIColor(red: 0.018, green: 0.028, blue: 0.055, alpha: 1)
        fogColor = UIColor(red: 0.025, green: 0.035, blue: 0.065, alpha: 1)
        fogStartDistance = 19
        fogEndDistance = 34
        if usesPressureGym {
            background.contents = UIColor(white: 0.14, alpha: 1)
            fogColor = UIColor(white: 0.17, alpha: 1)
            fogStartDistance = 30
            fogEndDistance = 48
        } else if usesRegionalHall {
            background.contents = UIColor(white: 0.12, alpha: 1)
            fogColor = UIColor(white: 0.18, alpha: 1)
            fogStartDistance = 38
            fogEndDistance = 58
            switch engine.storyBout?.opponent {
            case .counter:
                background.contents = UIColor(red: 0.17, green: 0.20, blue: 0.18, alpha: 1)
                fogColor = UIColor(red: 0.24, green: 0.28, blue: 0.26, alpha: 1)
            case .slugger:
                background.contents = UIColor(white: 0.055, alpha: 1)
                fogColor = UIColor(white: 0.10, alpha: 1)
                fogStartDistance = 30
                fogEndDistance = 54
            case .rival:
                background.contents = UIColor(white: 0.025, alpha: 1)
                fogColor = UIColor(red: 0.045, green: 0.050, blue: 0.060, alpha: 1)
                fogStartDistance = 50
                fogEndDistance = 82
            default: break
            }
        }
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
        synchronizeVisuals(deltaTime: 1.0 / 60.0, elapsedTime: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Recolors the player's rig to reflect a newly equipped outfit choice.
    func setPlayerOutfit(_ outfit: OutfitID) {
        playerOutfit = outfit
        playerRig.applyOutfit(outfit)
    }

    func setPlayerAppearance(_ opponent: StoryOpponent?) {
        guard playerAppearance != opponent else { return }
        let hidden = playerRig.root.isHidden
        let labelHidden = playerRig.root.childNode(withName: "playerIdentityLabel", recursively: false)?.isHidden ?? false
        playerRig.root.removeFromParentNode()
        playerRig = BoxerRig(team: .player, appearance: BoxerAppearance(opponent: opponent))
        playerAppearance = opponent
        playerRig.applyOutfit(playerOutfit)
        playerRig.setChampionBeltVisible(playerBeltEquipped)
        playerRig.root.isHidden = hidden
        playerRig.root.childNode(withName: "playerIdentityLabel", recursively: false)?.isHidden = labelHidden
        rootNode.addChildNode(playerRig.root)
        synchronizeVisuals(deltaTime: 0, elapsedTime: visualElapsedTime)
    }

    func setPlayerChampionBelt(_ equipped: Bool) {
        playerBeltEquipped = equipped
        playerRig.setChampionBeltVisible(equipped)
    }

    func setReducedMotion(_ enabled: Bool) {
        reducedMotion = enabled
    }

    func resetFrameClock() {
        lastUpdateTime = 0
    }

    func beginStoryIntroduction(short: Bool) -> Double {
        introductionClip = StoryIntroClip.clip(for: engine.storyBout?.opponent)
        introductionShort = short
        introductionSuspended = false
        introductionEntranceDuration = short ? 1.9 : (introductionClip?.duration ?? 1.9)
        introductionDuration = introductionEntranceDuration + StoryIntroduction.coachDuration(short: short)
        if engine.storyBout?.opponent == .rival, !short {
            championshipIntroBelt.simdPosition = SIMD3<Float>(0, 0.27, 7.5)
            championshipIntroBelt.simdOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            rootNode.addChildNode(championshipIntroBelt)
        }
        for (source, target) in [(engine.player, introductionPlayer), (engine.enemy, introductionEnemy)] {
            target.x = source.x
            target.y = source.y
            target.facingX = source.facingX
            target.facingY = source.facingY
            target.style = source.style
            target.guarding = true
        }
        let distance = max(0.001, hypot(introductionEnemy.x - introductionPlayer.x, introductionEnemy.y - introductionPlayer.y))
        introductionPlayer.facingX = (introductionEnemy.x - introductionPlayer.x) / distance
        introductionPlayer.facingY = (introductionEnemy.y - introductionPlayer.y) / distance
        introductionEnemy.facingX = -introductionPlayer.facingX
        introductionEnemy.facingY = -introductionPlayer.facingY
        resetFrameClock()
        setCinematicMode(true, presentation: .storyIntroduction)
        rootNode.addChildNode(storyCoachRig.root)
        storyCoachRig.root.isHidden = true
        synchronizeVisuals(deltaTime: 1.0 / 60.0, elapsedTime: visualElapsedTime)
        return introductionDuration
    }

    func setStoryIntroductionSuspended(_ suspended: Bool) {
        introductionSuspended = suspended
        resetFrameClock()
    }

    @discardableResult
    func beginStoryRivalScene(clip: StoryIntroClip, chapter: StoryOpponent) -> Double {
        rivalSceneClip = clip
        rivalSceneDuration = chapter == .rival ? max(clip.duration, ChampionshipEndingTiming.duration) : clip.duration
        rivalSceneChapter = chapter
        introductionSuspended = false
        rivalSceneHiddenNodes = rootNode.childNodes.filter { $0 !== cameraNode }
            .map { (node: $0, hidden: $0.isHidden) }
        rootNode.addChildNode(rivalTrainingStage)
        let showsReplay = chapter == .outboxer || chapter == .counter || chapter == .slugger
        if showsReplay {
            rivalTrainingStage.addChildNode(rivalReplayMonitor)
            rivalReplayMonitor.simdPosition = chapter == .slugger
                ? SIMD3<Float>(0, 2.28, 1.65) : SIMD3<Float>(0.45, 1.99, 1.04)
            rivalReplayFrames = chapter == .slugger ? makeRivalOpeningReplayFrames() : makeRivalReplayFrames()
            rivalReplayMonitor.isHidden = false
        } else {
            rivalReplayMonitor.removeFromParentNode()
        }
        if chapter == .rival {
            championshipPlayerRig = BoxerRig(team: .player, appearance: BoxerAppearance(opponent: playerAppearance))
            championshipPlayerRig?.applyOutfit(playerOutfit)
            if let championshipPlayerRig {
                rootNode.addChildNode(championshipPlayerRig.root)
                championshipPlayerRig.root.childNode(withName: "playerIdentityLabel", recursively: false)?.isHidden = true
            }
            let victoryRig = BoxerRig(team: .player)
            victoryRig.applyOutfit(.storyChampion)
            victoryRig.setChampionBeltVisible(true)
            victoryRig.root.isHidden = true
            victoryRig.root.childNode(withName: "playerIdentityLabel", recursively: false)?.isHidden = true
            championshipVictoryRig = victoryRig
            rootNode.addChildNode(victoryRig.root)
            championshipApplauseRigs = [StoryOpponent.pressure, .outboxer, .counter, .slugger, .rival].map { opponent in
                let rig = BoxerRig(team: .rival, appearance: BoxerAppearance(opponent: opponent))
                rig.root.name = "championshipApplause_\(opponent.rawValue)"
                rig.root.isHidden = true
                rig.root.childNode(withName: "rivalIdentityLabel", recursively: false)?.isHidden = true
                rootNode.addChildNode(rig.root)
                let style: FightStyle = switch opponent {
                case .outboxer: .outboxing
                case .slugger: .infighting
                default: .standard
                }
                return (rig: rig, style: style)
            }
            championshipCornerSeat.simdPosition = championshipCorner
            championshipCornerSeat.simdOrientation = simd_quatf(angle: championshipHeading, axis: SIMD3<Float>(0, 1, 0))
            rootNode.addChildNode(championshipCornerSeat)
        } else {
            rivalReplayProgress?.isHidden = false
        }
        if chapter == .slugger {
            rivalTrainingStage.addChildNode(rivalTargetBag)
            rivalTrainingStage.addChildNode(rivalChampionshipBelt)
        }
        rivalTargetBag.isHidden = chapter != .slugger
        rivalChampionshipBelt.isHidden = chapter != .slugger
        let keyLight = rivalTrainingStage.childNode(withName: "rivalTrainingKey", recursively: false)?.light
        keyLight?.color = chapter == .counter ? UIColor(red: 0.93, green: 0.97, blue: 1, alpha: 1)
            : chapter == .slugger ? UIColor(red: 1, green: 0.94, blue: 0.84, alpha: 1)
            : UIColor(red: 1, green: 0.96, blue: 0.9, alpha: 1)
        rootNode.addChildNode(rivalSceneRig.root)
        rivalSceneRig.root.childNode(withName: "rivalIdentityLabel", recursively: false)?.isHidden = true
        resetFrameClock()
        setCinematicMode(true, presentation: .storyRivalScene)
        if chapter == .rival {
            rootNode.addChildNode(storyCoachRig.root)
            storyCoachRig.root.isHidden = true
        }
        synchronizeVisuals(deltaTime: 0, elapsedTime: visualElapsedTime)
        return rivalSceneDuration
    }

    func setCinematicMode(_ active: Bool, presentation: ArenaCinematicPresentation = .matchIntro) {
        if cinematicMode && cinematicPresentation == .storyIntroduction
            && (!active || presentation != .storyIntroduction) {
            championshipIntroBelt.removeFromParentNode()
            storyCoachRig.root.removeFromParentNode()
        }
        if cinematicMode && cinematicPresentation == .storyRivalScene
            && (!active || presentation != .storyRivalScene) {
            for entry in rivalSceneHiddenNodes { entry.node.isHidden = entry.hidden }
            rivalSceneHiddenNodes.removeAll()
            rivalSceneRig.root.removeFromParentNode()
            championshipPlayerRig?.root.removeFromParentNode()
            championshipPlayerRig = nil
            championshipVictoryRig?.root.removeFromParentNode()
            championshipVictoryRig = nil
            for entry in championshipApplauseRigs { entry.rig.root.removeFromParentNode() }
            championshipApplauseRigs.removeAll()
            storyCoachRig.root.removeFromParentNode()
            championshipCornerSeat.removeFromParentNode()
            rivalTrainingStage.removeFromParentNode()
            rivalSceneClip = nil
            rivalSceneDuration = 0
            rivalReplayFrames.removeAll()
            rivalReplaySurface?.diffuse.contents = UIColor.black
        }
        let wasAppOpening = cinematicMode && cinematicPresentation == .appOpening
        if active && presentation == .appOpening && openingPlayerState == nil {
            openingPlayerState = CinematicFighterState(engine.player)
            openingEnemyState = CinematicFighterState(engine.enemy)
        }
        if wasAppOpening && (!active || presentation != .appOpening) {
            openingPlayerState?.restore(to: engine.player)
            openingEnemyState?.restore(to: engine.enemy)
            openingPlayerState = nil
            openingEnemyState = nil
            openingImpactPulse = 0
        }
        cinematicMode = active
        cinematicElapsed = 0
        cinematicPresentation = presentation
        let isPortrait = active && presentation == .menuPortrait
        let isRivalScene = active && presentation == .storyRivalScene
        playerRig.root.isHidden = isPortrait || isRivalScene
        enemyRig.root.isHidden = isRivalScene
        for (index, entry) in lightBaselines.enumerated() {
            entry.light.intensity = entry.intensity * (isPortrait ? (index == 0 ? 0.45 : 0.62) : 1)
        }
        cameraNode.camera?.exposureOffset = isPortrait ? -0.5 : -0.25
        cameraNode.camera?.wantsExposureAdaptation = !isPortrait
        cameraNode.camera?.bloomIntensity = isPortrait ? 0 : 0.22
        let hidesIdentityLabels = active && presentation != .matchIntro
        playerRig.root.childNode(withName: "playerIdentityLabel", recursively: false)?.isHidden = hidesIdentityLabels || Arena3DScene.isIconCaptureMode
        enemyRig.root.childNode(withName: "rivalIdentityLabel", recursively: false)?.isHidden = hidesIdentityLabels
    }

    func update(at time: TimeInterval) {
        // 매 디스플레이 틱에서 호출되는 주 업데이트 루프입니다.
        // - `time`은 CADisplayLink/타이밍 소스에서 전달되는 타임스탬프입니다.
        // 이 메서드는 엔진의 advance/update 순서를 관리하고, 프레젠테이션을 전진시키며
        // 최종적으로 `synchronizeVisuals`를 호출해 SceneKit 노드 변환을 적용합니다.
        // 또한 적당한 빈도로(0.08s) 컨트롤러에 스냅샷을 게시합니다.
        let deltaTime = lastUpdateTime == 0 ? 1.0 / 60.0 : max(0, min(0.05, time - lastUpdateTime))
        lastUpdateTime = time
        let visualDeltaTime: Double
        if cinematicMode {
            let isStoryScene = cinematicPresentation == .storyIntroduction || cinematicPresentation == .storyRivalScene
            visualDeltaTime = isStoryScene && introductionSuspended ? 0 : deltaTime
            cinematicElapsed += visualDeltaTime
            controller?.updateCinematicSound(elapsed: cinematicElapsed)
        } else {
            if engine.phase == .fight || engine.phase == .roundBreak {
                presentation.advance(deltaTime: deltaTime)
            }
            controller?.synchronizeHeldControls()
            engine.update(deltaTime: deltaTime)
            visualDeltaTime = engine.phase == .intro ? deltaTime : engine.lastSimulationDeltaTime
        }
        controller?.updateStoryRoundTransition()
        controller?.updateAudioMix(deltaTime: deltaTime)
        visualElapsedTime += visualDeltaTime
        synchronizeVisuals(deltaTime: deltaTime, elapsedTime: visualElapsedTime, rigDeltaTime: visualDeltaTime)

        if cinematicMode && cinematicPresentation == .storyIntroduction {
            publishTimer += deltaTime
            if publishTimer >= 0.08 {
                publishTimer = 0
                controller?.updateStoryIntroduction(elapsed: cinematicElapsed)
            }
            if cinematicElapsed >= introductionDuration {
                controller?.finishStoryIntroduction()
            }
        }
        if cinematicMode && cinematicPresentation == .storyRivalScene {
            publishTimer += deltaTime
            if publishTimer >= 0.08 {
                publishTimer = 0
                controller?.updateStoryRivalScene(elapsed: cinematicElapsed)
            }
            if cinematicElapsed >= rivalSceneDuration {
                controller?.finishStoryRivalScene()
            }
        }
        if !cinematicMode {
            publishTimer += deltaTime
            if publishTimer >= 0.08 {
                publishTimer = 0
                controller?.publishSnapshot()
            }
        }
    }

    private func synchronizeVisuals(deltaTime: Double, elapsedTime: TimeInterval, rigDeltaTime: Double? = nil) {
        // SceneKit 관련 상태를 즉시 적용하는 동기화 포인트입니다.
        // - `deltaTime`: 물리/엔진 타이밍(보통 display delta)
        // - `elapsedTime`: 누적된 시각(애니메이션 루프용)
        // - `rigDeltaTime`: 리그(캐릭터 포즈) 업데이트 전용 델타(애니메이션 스무딩에 사용)
        // 이 블록에서는 SCNTransaction을 0초로 설정해 노드 변환을 즉시 반영하고,
        // 카메라/리그/임팩트 가시화/트레일 등을 모두 업데이트합니다.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        if cinematicMode && cinematicPresentation == .appOpening {
            updateAppOpeningChoreography()
        }
        let poseDeltaTime = rigDeltaTime ?? deltaTime
        if cinematicMode && cinematicPresentation == .storyRivalScene, let rivalSceneClip {
            let championship = rivalSceneChapter == .rival
            let training = championship ? cinematicElapsed >= ChampionshipEndingTiming.gymCut
                : rivalSceneChapter != .pressure || cinematicElapsed >= 3.2
            let ceremony = championship && cinematicElapsed >= ChampionshipEndingTiming.ceremonyStart && !training
            rivalTrainingStage.isHidden = !training
            rivalSceneRig.root.isHidden = ceremony
            for entry in rivalSceneHiddenNodes {
                entry.node.isHidden = training || entry.hidden || entry.node === playerRig.root || entry.node === enemyRig.root
            }
            let sample = rivalSceneClip.sample(at: cinematicElapsed)
            let heading: Float = training ? 0 : championship ? championshipHeading : -.pi / 2
            let rotation = simd_quatf(angle: heading, axis: SIMD3<Float>(0, 1, 0))
            let position = training ? (championship ? SIMD3<Float>(0, 0.13, 0) : .zero)
                : championship ? championshipCorner : SIMD3<Float>(7.5, -0.60, 1.5)
            if championship && training {
                let shadowboxing = ChampionshipShadowboxingMotion.sample(at: cinematicElapsed - ChampionshipEndingTiming.gymCut)
                rivalSceneRig.updateAuthoredPose(shadowboxing.pose,
                    position: position + shadowboxing.root, heading: shadowboxing.heading, usesProceduralPose: true)
            } else {
                rivalSceneRig.updateAuthoredPose(sample.pose,
                    position: position + rotation.act(sample.root), heading: heading + sample.heading)
            }
            if championship {
                championshipCornerSeat.isHidden = training || ceremony
                championshipPlayerRig?.root.isHidden = training || ceremony
                championshipVictoryRig?.root.isHidden = !ceremony
                for entry in championshipApplauseRigs { entry.rig.root.isHidden = !ceremony }
                storyCoachRig.root.isHidden = !ceremony
                if ceremony { updateChampionshipApplause() }
                if !training, let playerClip = StoryIntroClip.championshipEndingPlayer {
                    let playerSample = playerClip.sample(at: cinematicElapsed)
                    if ceremony {
                        championshipVictoryRig?.updateAuthoredPose(playerSample.pose,
                            position: SIMD3<Float>(0, 0.13, 0), heading: 0)
                    } else {
                        championshipPlayerRig?.updateAuthoredPose(playerSample.pose,
                            position: position + rotation.act(playerSample.root), heading: heading + playerSample.heading)
                        championshipPlayerRig?.setChampionBeltVisible(cinematicElapsed >= ChampionshipEndingTiming.beltAward)
                    }
                }
            }
            if rivalSceneChapter == .outboxer || rivalSceneChapter == .counter || rivalSceneChapter == .slugger {
                updateRivalReplayMonitor()
            }
            if rivalSceneChapter == .slugger { updateRivalTargetBag() }
        } else if cinematicMode && cinematicPresentation == .storyIntroduction {
            championshipIntroBelt.isHidden = introductionShort || cinematicElapsed >= 1.8
            updateStoryIntroductionCoach()
            playerRig.update(from: introductionPlayer, deltaTime: poseDeltaTime, elapsedTime: elapsedTime,
                reducedMotion: reducedMotion, idleMotion: MenuIdleMotion.sample(at: cinematicElapsed, reducedMotion: reducedMotion),
                usesPresentationDefense: true)
            if let introductionClip {
                let sample = introductionClip.sample(at: introductionShort ? introductionClip.duration : cinematicElapsed)
                let rotation = simd_quatf(angle: Float(atan2(introductionEnemy.facingX, introductionEnemy.facingY)),
                                         axis: SIMD3<Float>(0, 1, 0))
                enemyRig.updateAuthoredPose(sample.pose,
                    position: worldPosition(introductionEnemy) + rotation.act(sample.root),
                    heading: Float(atan2(introductionEnemy.facingX, introductionEnemy.facingY)) + sample.heading)
            } else {
                enemyRig.update(from: introductionEnemy, deltaTime: poseDeltaTime, elapsedTime: elapsedTime,
                    reducedMotion: reducedMotion, usesPresentationDefense: true)
            }
        } else if cinematicMode && cinematicPresentation == .menuPortrait {
            // This presentation model is never a participant in the live CombatEngine.
            enemyRig.update(
                from: portraitFighter, deltaTime: poseDeltaTime, elapsedTime: elapsedTime,
                reducedMotion: reducedMotion, idleMotion: MenuIdleMotion.sample(at: cinematicElapsed, reducedMotion: reducedMotion),
                usesPresentationDefense: engine.storyBout?.opponent == .pressure
            )
        } else {
            let separation = simd_distance(worldPosition(engine.player), worldPosition(engine.enemy))
            let allowsContactBeat = !cinematicMode && engine.koMomentTime <= 0 && engine.rivalMomentTime <= 0
            let usesPresentationDefense = cinematicMode && cinematicPresentation == .appOpening
            playerRig.update(from: engine.player, deltaTime: poseDeltaTime, elapsedTime: elapsedTime,
                             reducedMotion: reducedMotion, impact: cinematicMode ? nil : presentation.playerHit,
                             contactVisible: !cinematicMode && presentation.playerContactTime > 0, opponentDistance: separation,
                             strike: presentation.playerStrike, allowsContactBeat: allowsContactBeat,
                             usesPresentationDefense: usesPresentationDefense)
            enemyRig.update(from: engine.enemy, deltaTime: poseDeltaTime, elapsedTime: elapsedTime,
                            reducedMotion: reducedMotion, impact: cinematicMode ? nil : presentation.rivalHit,
                            contactVisible: !cinematicMode && presentation.rivalContactTime > 0, opponentDistance: separation,
                            strike: presentation.rivalStrike, allowsContactBeat: allowsContactBeat,
                            usesPresentationDefense: usesPresentationDefense)
        }
        if cinematicMode {
            updateCinematicCamera()
        } else {
            updateCamera(deltaTime: deltaTime)
        }
        SCNTransaction.commit()
    }

    private func updateStoryIntroductionCoach() {
        let coaching = cinematicElapsed >= introductionEntranceDuration
        storyCoachRig.root.isHidden = !coaching
        let forward = SIMD3<Float>(-Float(introductionEnemy.facingX), 0, -Float(introductionEnemy.facingY))
        let right = SIMD3<Float>(forward.z, 0, -forward.x)
        let playerPosition = worldPosition(introductionPlayer)
        let coachPosition = playerPosition - forward * 0.85 + right * 1.2
        storyCoachRig.root.simdPosition = coachPosition
        let coachFacing = playerPosition - coachPosition
        storyCoachRig.root.simdOrientation = simd_quatf(angle: atan2(coachFacing.x, coachFacing.z),
            axis: SIMD3<Float>(0, 1, 0))
        let time = max(0, cinematicElapsed - introductionEntranceDuration)
        let duration = StoryIntroduction.coachDuration(short: introductionShort)
        if coaching { storyCoachRig.updateBriefing(at: time, duration: duration, reducedMotion: reducedMotion) }
        let envelope = coaching ? Float(min(1, max(0, min(time / 0.7, (duration - time) / 0.9)))) : 0
        let turn = reducedMotion ? (coaching && time < duration - 0.9 ? Float(1) : 0)
            : envelope * envelope * (3 - 2 * envelope)
        let baseHeading = atan2(forward.x, forward.z)
        let coachHeading = atan2(-coachFacing.x, -coachFacing.z)
        let turnAngle = atan2(sin(coachHeading - baseHeading), cos(coachHeading - baseHeading))
        let heading = baseHeading + turnAngle * turn
        introductionPlayer.facingX = Double(sin(heading))
        introductionPlayer.facingY = Double(cos(heading))
        introductionPlayer.guarding = !coaching || time >= duration - 0.9
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
        cameraNode.simdPosition -= cameraContactOffset
        cameraContactOffset = .zero
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
        let countingSide = engine.storyBout?.phase == .counting ? engine.storyBout?.countingSide : nil
        let followsKnockout = engine.lastRoundWasKnockout
            && (engine.storyBout == nil || engine.storyBout?.phase == .finished)
        if engine.phase == .roundBreak, followsKnockout || countingSide != nil {
            // Follow the falling subject without orbiting away from the approved shoulder composition.
            let countedFighter = countingSide.map { $0 == .player ? engine.player : engine.enemy }
            let fall = countedFighter.map { fighter in
                fighter.getupProgress > 0
                    ? FighterKnockdownMotion.sampleRecovery(progress: Float(fighter.getupProgress), reducedMotion: reducedMotion).fall
                    : Float(fighter.knockdown)
            } ?? Float(max(engine.player.knockdown, engine.enemy.knockdown))
            var fallTarget = countedFighter.map { worldPosition($0) } ?? midpoint
            fallTarget.y = 1.42 - 0.62 * fall
            target = mix(target, fallTarget, amount: 0.6)
        }

        var distance = 6.75 + 1.55 * Float(spread)
        if separation < 2.25 { distance -= 0.22 }
        if engine.player.attack != nil { target += forward * 0.18 }
        let shoulderOffset: Float = separation < 2.6 ? 1.32 : 1.05
        var desiredPosition = player - forward * distance + right * shoulderOffset + SIMD3<Float>(0, 5.05, 0)
        let focus = CombatCameraFocus.sample(
            dodgeGrade: engine.rivalMomentGrade, dodgeTime: engine.rivalMomentTime,
            knockoutTime: engine.koMomentTime, reducedMotion: reducedMotion
        )
        let focusZoom = focus.push
        if focusZoom > 0 {
            desiredPosition += forward * focusZoom
            target += forward * focusZoom * 0.19
            target.y += focusZoom * 0.08
        }
        if !reducedMotion, presentation.cameraImpulse > 0 {
            let impulse = presentation.cameraImpulse
            // One short recoil instead of high-frequency oscillation. The existing KO/dodge zoom wins.
            desiredPosition -= forward * 0.09 * impulse
            desiredPosition.y += 0.035 * impulse
            target += forward * 0.05 * impulse
        }

        // While a dodge-focus or KO beat is pushing the camera in, snap the blend response noticeably
        // faster so the zoom itself reads as a decisive, immediate punch-in rather than a slow drift --
        // reinforcing the "this is the moment" cue instead of diluting it.
        let inFocusBeat = focusZoom > 0 || (!reducedMotion && presentation.cameraImpulse > 0)
        let positionResponse: Double = inFocusBeat ? 10.5 : 5.5
        let targetResponse: Double = inFocusBeat ? 12.5 : 7.0
        let positionBlend = Float(1 - exp(-deltaTime * positionResponse))
        let targetBlend = Float(1 - exp(-deltaTime * targetResponse))
        cameraNode.simdPosition += (desiredPosition - cameraNode.simdPosition) * positionBlend
        cameraTarget += (target - cameraTarget) * targetBlend
        if let camera = cameraNode.camera {
            camera.fieldOfView += (CGFloat(focus.fieldOfView) - camera.fieldOfView) * CGFloat(1 - exp(-deltaTime * 16))
        }
        if !reducedMotion, engine.koMomentTime <= 0, engine.rivalMomentTime <= 0 {
            let kick = presentation.cameraContactKick
            cameraContactOffset = -forward * 0.035 * kick + SIMD3<Float>(0, 0.014 * kick, 0)
            cameraNode.simdPosition += cameraContactOffset
        }
        cameraNode.look(at: SCNVector3(cameraTarget), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }

    private func updateCinematicCamera() {
        cameraContactOffset = .zero
        cameraNode.camera?.fieldOfView = 50
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
        let progress = reducedMotion ? 0 : Float(min(1, max(0, cinematicElapsed / cinematicDuration)))
        let eased = progress * progress * (3 - 2 * progress)
        let midpoint = (player + enemy) * 0.5
        cameraForward = forward
        switch cinematicPresentation {
        case .storyRivalScene:
            if rivalSceneChapter == .rival {
                let training = cinematicElapsed >= ChampionshipEndingTiming.gymCut
                if training {
                    cameraNode.simdPosition = SIMD3<Float>(-3.4, 2.4, 4.8)
                    cameraTarget = SIMD3<Float>(0.1, 1.50, 0.2)
                    cameraNode.camera?.fieldOfView = 43
                } else if cinematicElapsed >= ChampionshipEndingTiming.ceremonyStart {
                    let progress = Float(min(1, max(0, (cinematicElapsed - ChampionshipEndingTiming.ceremonyStart) / 7.0)))
                    let blend = reducedMotion ? Float(1) : progress * progress * (3 - 2 * progress)
                    let widePosition = mix(SIMD3<Float>(-5.2, 3.4, 8.5), SIMD3<Float>(-6.2, 4.1, 10.0), amount: blend)
                    let congratulations = Float(min(1, max(0,
                        (cinematicElapsed - ChampionshipEndingTiming.coachCongratulations) / 0.85)))
                    let closeBlend = reducedMotion ? (congratulations > 0 ? Float(1) : 0)
                        : congratulations * congratulations * (3 - 2 * congratulations)
                    cameraNode.simdPosition = mix(widePosition, SIMD3<Float>(-3.3, 2.95, 5.7), amount: closeBlend)
                    cameraTarget = mix(SIMD3<Float>(0, 1.50, -1.0), SIMD3<Float>(0.55, 1.65, 0.10), amount: closeBlend)
                    cameraNode.camera?.fieldOfView = CGFloat(54 - 10 * closeBlend)
                } else {
                    let rotation = simd_quatf(angle: championshipHeading, axis: SIMD3<Float>(0, 1, 0))
                    let seated = cinematicElapsed < 2.2
                    let rewarding = cinematicElapsed >= ChampionshipEndingTiming.beltAward
                    let rivalPosition = rivalSceneRig.root.simdPosition
                    let playerPosition = championshipPlayerRig?.root.simdPosition ?? championshipCorner
                    let pairCenter = (rivalPosition + playerPosition) * 0.5
                    let localCamera = seated ? SIMD3<Float>(-4.4, 2.45, 0.45)
                        : rewarding ? SIMD3<Float>(-4.9, 2.60, 1.15) : SIMD3<Float>(-4.7, 2.65, 0.20)
                    cameraNode.simdPosition = pairCenter + rotation.act(localCamera)
                    cameraTarget = pairCenter + SIMD3<Float>(0, seated ? 1.15 : 1.50, 0)
                    cameraNode.camera?.fieldOfView = seated ? 48 : 50
                }
                break
            }
            if rivalSceneChapter == .outboxer || rivalSceneChapter == .counter {
                let watching = rivalSceneChapter == .counter
                    ? (cinematicElapsed >= 2.15 && cinematicElapsed < 3.45) : cinematicElapsed < 4.15
                let segmentTime = rivalSceneChapter == .counter
                    ? (watching ? cinematicElapsed - 2.15 : cinematicElapsed < 2.15 ? cinematicElapsed : cinematicElapsed - 3.45)
                    : watching ? cinematicElapsed : cinematicElapsed - 4.15
                let progress = reducedMotion ? Float(0) : Float(min(1, max(0, segmentTime / 4.15)))
                let blend = progress * progress * (3 - 2 * progress)
                let wide = watching ? SIMD3<Float>(-2.8, 2.65, -4.8) : SIMD3<Float>(-3.8, 2.5, 5.1)
                let close = watching ? SIMD3<Float>(-2.3, 2.4, -4.0) : SIMD3<Float>(-3.3, 2.3, 4.7)
                cameraNode.simdPosition = mix(wide, close, amount: blend)
                cameraTarget = SIMD3<Float>(0.15, watching ? 1.75 : 1.45, watching ? 0.45 : 0)
                cameraNode.camera?.fieldOfView = 43
                break
            }
            if rivalSceneChapter == .slugger {
                let watching = cinematicElapsed < 1.3
                let revealingBelt = cinematicElapsed >= 8.15
                let reveal = Float(min(1, max(0, (cinematicElapsed - 8.15) / 1.25)))
                let blend = reveal * reveal * (3 - 2 * reveal)
                if watching {
                    cameraNode.simdPosition = SIMD3<Float>(-2.5, 2.55, -3.2)
                    cameraTarget = SIMD3<Float>(0, 1.95, 0.75)
                    cameraNode.camera?.fieldOfView = 34
                } else {
                    let revealAmount: Float = revealingBelt ? (reducedMotion ? 1 : blend) : 0
                    let beltCenter = rivalChampionshipBelt.simdConvertPosition(SIMD3<Float>(0, 0.20, 0), to: rootNode)
                    cameraNode.simdPosition = mix(SIMD3<Float>(-3.8, 2.55, -1.8),
                        SIMD3<Float>(-4.7, 1.65, -1.9), amount: revealAmount)
                    cameraTarget = mix(SIMD3<Float>(0, 1.75, 0.55),
                        beltCenter, amount: revealAmount)
                    cameraNode.camera?.fieldOfView = CGFloat(34 + 8 * revealAmount)
                }
                break
            }
            let training = cinematicElapsed >= 3.2
            let subject = rivalSceneRig.root.simdPosition
            let progress = reducedMotion ? Float(0) : Float(min(1, max(0,
                training ? (cinematicElapsed - 3.2) / 5 : cinematicElapsed / 3.2)))
            let blend = progress * progress * (3 - 2 * progress)
            let wide = training ? SIMD3<Float>(3.2, 2.5, 6.0) : SIMD3<Float>(11.8, 2.0, 5.8)
            let close = training ? SIMD3<Float>(2.6, 2.3, 5.3) : SIMD3<Float>(11.2, 1.9, 5.2)
            cameraNode.simdPosition = mix(wide, close, amount: blend)
            cameraTarget = subject + SIMD3<Float>(0, 1.45, 0)
            cameraNode.camera?.fieldOfView = 44
        case .storyIntroduction:
            if cinematicElapsed >= introductionEntranceDuration {
                let coachingTime = cinematicElapsed - introductionEntranceDuration
                let coachingDuration = StoryIntroduction.coachDuration(short: introductionShort)
                let coach = storyCoachRig.root.simdPosition
                let listener = worldPosition(introductionPlayer)
                let pairCenter = (coach + listener) * 0.5
                let pairDirection = simd_normalize(listener - coach)
                let cameraSide = SIMD3<Float>(pairDirection.z, 0, -pairDirection.x)
                let push: Float = reducedMotion ? 0 : Float(min(1, coachingTime / coachingDuration)) * 0.18
                let briefingPosition = pairCenter + cameraSide * (5.0 - push) + SIMD3<Float>(0, 2.7, 0)
                let briefingTarget = pairCenter + SIMD3<Float>(0, 1.7, 0)
                let handoff = Float(min(1, max(0, (coachingTime - coachingDuration + 0.9) / 0.9)))
                let blend = reducedMotion ? (handoff > 0 ? Float(1) : 0) : handoff * handoff * (3 - 2 * handoff)
                let fightPosition = player - forward * 7.8 + right * 1.25 + SIMD3<Float>(0, 5.05, 0)
                let fightTarget = player * 0.5 + enemy * 0.5 + SIMD3<Float>(0, 1.42, 0)
                cameraNode.simdPosition = mix(briefingPosition, fightPosition, amount: blend)
                cameraTarget = mix(briefingTarget, fightTarget, amount: blend)
                cameraNode.camera?.fieldOfView = CGFloat(44 + 6 * blend)
                break
            }
            let subjectRotation = simd_quatf(angle: Float(atan2(introductionEnemy.facingX, introductionEnemy.facingY)),
                axis: SIMD3<Float>(0, 1, 0))
            let rootOffset = usesRegionalHall ? introductionClip?.sample(at:
                introductionShort ? introductionClip?.duration ?? 0 : cinematicElapsed).root ?? .zero : .zero
            let subject = worldPosition(introductionEnemy) + subjectRotation.act(rootOffset)
            let subjectForward = SIMD3<Float>(Float(introductionEnemy.facingX), 0, Float(introductionEnemy.facingY))
            let subjectRight = SIMD3<Float>(subjectForward.z, 0, -subjectForward.x)
            if engine.storyBout?.opponent == .rival {
                if !introductionShort && cinematicElapsed < 1.8 {
                    cameraNode.simdPosition = SIMD3<Float>(1.8, 1.70, 10.6)
                    cameraTarget = SIMD3<Float>(0, 0.45, 7.5)
                    cameraNode.camera?.fieldOfView = 42
                } else {
                    let close = subject + subjectForward * 3.8 + subjectRight * 1.3 + SIMD3<Float>(0, 2.45, 0)
                    let wide = (worldPosition(introductionPlayer) + subject) * 0.5
                        + subjectRight * 6.6 + SIMD3<Float>(0, 3.7, 0)
                    let blend = introductionShort ? Float(1) : Float(min(1, max(0, (cinematicElapsed - 7.9) / 1.1)))
                    cameraNode.simdPosition = mix(close, wide, amount: reducedMotion ? (blend >= 1 ? 1 : 0) : blend)
                    cameraTarget = mix(subject + SIMD3<Float>(0, 1.7, 0),
                        (worldPosition(introductionPlayer) + subject) * 0.5 + SIMD3<Float>(0, 1.4, 0), amount: blend)
                    cameraNode.camera?.fieldOfView = CGFloat(39 + 8 * blend)
                }
                break
            }
            let isCounterIntro = engine.storyBout?.opponent == .counter
            let isSluggerIntro = engine.storyBout?.opponent == .slugger
            let widePosition = isCounterIntro ? SIMD3<Float>(-7.4, 5.8, 10.8)
                : isSluggerIntro ? SIMD3<Float>(-8.0, 4.6, 11.2)
                : usesRegionalHall ? SIMD3<Float>(-9.0, 6.5, 12.5) : SIMD3<Float>(-7.5, 6.0, 11.5)
            let closeDistance: Float = isCounterIntro ? 3.8 : isSluggerIntro ? 4.4 : usesRegionalHall ? 3.6 : 3.8
            let sideDistance: Float = isCounterIntro ? 3.7 : isSluggerIntro ? 4.6 : usesRegionalHall ? 4.3 : 4.5
            let cameraHeight: Float = isCounterIntro ? 2.75 : isSluggerIntro ? 2.45 : usesRegionalHall ? 2.5 : 2.8
            let closePosition = subject + subjectForward * closeDistance
                + subjectRight * sideDistance + SIMD3<Float>(0, cameraHeight, 0)
            let approachStart = isCounterIntro ? 0.7 : isSluggerIntro ? 0.85 : 1.0
            let approachDuration = isCounterIntro ? 3.0 : isSluggerIntro ? 4.0 : usesRegionalHall ? 3.3 : 2.8
            let cameraProgress = reducedMotion ? Float(0) : (introductionShort ? Float(1)
                : Float(min(1, max(0, (cinematicElapsed - approachStart) / approachDuration))))
            let cameraBlend = cameraProgress * cameraProgress * (3 - 2 * cameraProgress)
            cameraNode.simdPosition = mix(widePosition, closePosition, amount: cameraBlend)
            cameraTarget = mix(SIMD3<Float>(0, 1.1, 0), subject + SIMD3<Float>(0, 1.6, 0), amount: cameraBlend)
            cameraNode.camera?.fieldOfView = isCounterIntro ? 44 : isSluggerIntro ? 46 : 48
        case .menuPortrait:
            let driftX: Float = reducedMotion ? 0 : Float(sin(cinematicElapsed * 0.37)) * 0.014
            let driftY: Float = reducedMotion ? 0 : Float(sin(cinematicElapsed * 0.29)) * 0.008
            cameraNode.camera?.fieldOfView = 34
            cameraNode.simdPosition = SIMD3<Float>(1.45 + driftX, 1.95 + driftY, 3.6)
            cameraTarget = SIMD3<Float>(0, 1.60, 0)
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
            let impact: Float = reducedMotion ? 0 : openingImpactPulse
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

    private func makeRivalReplayMonitor() -> SCNNode {
        let monitor = SCNNode()
        monitor.name = "rivalReplayMonitor"
        monitor.simdPosition = SIMD3<Float>(0.45, 1.99, 1.04)
        monitor.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        monitor.addChildNode(box(width: 1.42, height: 0.90, length: 0.14, radius: 0.025,
            color: UIColor(white: 0.09, alpha: 1), roughness: 0.65))
        let screen = SCNPlane(width: 1.26, height: 0.72)
        let surface = SCNMaterial()
        surface.lightingModel = .constant
        surface.diffuse.contents = UIColor.black
        screen.firstMaterial = surface
        rivalReplaySurface = surface
        let display = SCNNode(geometry: screen)
        display.position = SCNVector3(0, 0.03, 0.075)
        monitor.addChildNode(display)
        let controls = box(width: 0.80, height: 0.10, length: 0.60, radius: 0.02,
            color: UIColor(white: 0.17, alpha: 1), roughness: 0.78)
        controls.position = SCNVector3(0, -0.39, 0.23)
        monitor.addChildNode(controls)
        let button = box(width: 0.14, height: 0.025, length: 0.12, radius: 0.015,
            color: UIColor(red: 0.16, green: 0.58, blue: 0.73, alpha: 1), roughness: 0.55)
        button.position = SCNVector3(0, -0.33, 0.40)
        monitor.addChildNode(button)
        let pedestal = box(width: 0.14, height: 1.48, length: 0.20, radius: 0.015,
            color: UIColor(white: 0.13, alpha: 1), roughness: 0.70)
        pedestal.position = SCNVector3(0, -1.20, 0)
        monitor.addChildNode(pedestal)
        let base = box(width: 0.90, height: 0.08, length: 0.70, radius: 0.025,
            color: UIColor(white: 0.10, alpha: 1), roughness: 0.88)
        base.position = SCNVector3(0, -1.95, 0)
        monitor.addChildNode(base)
        let progress = box(width: 1.20, height: 0.025, length: 0.012, radius: 0,
            color: UIColor(red: 0.20, green: 0.77, blue: 0.90, alpha: 1), roughness: 1)
        progress.geometry?.firstMaterial?.lightingModel = .constant
        progress.position = SCNVector3(0, -0.35, 0.08)
        monitor.addChildNode(progress)
        rivalReplayProgress = progress
        return monitor
    }

    private func makeRivalReplayFrames() -> [UIImage] {
        guard let clip = StoryIntroClip.outboxer else { return [] }
        let replayScene = SCNScene()
        replayScene.background.contents = UIColor(white: 0.16, alpha: 1)
        let rig = BoxerRig(team: .player, appearance: BoxerAppearance(opponent: playerAppearance))
        rig.applyOutfit(playerOutfit)
        rig.root.childNode(withName: "playerIdentityLabel", recursively: false)?.isHidden = true
        replayScene.rootNode.addChildNode(rig.root)
        let floor = box(width: 5, height: 0.08, length: 5, radius: 0,
            color: UIColor(white: 0.48, alpha: 1), roughness: 0.95)
        floor.position.y = -0.04
        replayScene.rootNode.addChildNode(floor)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 3.9
        camera.position = SCNVector3(4.0, 2.3, 5.0)
        camera.look(at: SCNVector3(0, 1.35, -0.5))
        replayScene.rootNode.addChildNode(camera)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        replayScene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 1_050
        key.position = SCNVector3(-3, 5, 4)
        replayScene.rootNode.addChildNode(key)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = replayScene
        renderer.pointOfView = camera
        return (0..<24).map { index in
            let time = 2.0 + Double(index) * 2.1 / 23.0
            let sample = clip.sample(at: time)
            rig.updateAuthoredPose(sample.pose, position: sample.root, heading: sample.heading)
            return renderer.snapshot(atTime: time, with: CGSize(width: 384, height: 216), antialiasingMode: .multisampling2X)
        }
    }

    private func updateRivalReplayMonitor() {
        guard !rivalReplayFrames.isEmpty else { return }
        if rivalSceneChapter == .slugger {
            let start = cinematicElapsed < 1.3 ? 0 : 1.3 + floor((cinematicElapsed - 1.3) / 2) * 2
            let progress = Float(min(1, max(0, (cinematicElapsed - start) / 2)))
            let index = min(rivalReplayFrames.count - 1, Int(progress * Float(rivalReplayFrames.count - 1)))
            rivalReplaySurface?.diffuse.contents = rivalReplayFrames[index]
            rivalReplayProgress?.scale.x = max(0.001, progress)
            rivalReplayProgress?.position.x = -0.60 + 0.60 * progress
            return
        }
        let restarts = rivalSceneChapter == .counter ? [0.0, 2.15, 3.45, 5.10] : [0.0, 1.05, 2.40, 3.55]
        let start = restarts.last(where: { cinematicElapsed >= $0 }) ?? 0
        let progress = Float(min(1, max(0, (cinematicElapsed - start) / 2.1)))
        let index = min(rivalReplayFrames.count - 1, Int(progress * Float(rivalReplayFrames.count - 1)))
        rivalReplaySurface?.diffuse.contents = rivalReplayFrames[index]
        rivalReplayProgress?.scale.x = max(0.001, progress)
        rivalReplayProgress?.position.x = -0.60 + 0.60 * progress
    }

    private func makeRivalOpeningReplayFrames() -> [UIImage] {
        guard let hook = CombatData.attacks[.leftHook], let cross = CombatData.attacks[.cross] else { return [] }
        let replayScene = SCNScene()
        replayScene.background.contents = UIColor(white: 0.16, alpha: 1)
        let player = FighterModel(name: "PLAYER", x: 281, y: 295)
        let opponent = FighterModel(name: "OPPONENT", x: 309, y: 295)
        player.facingX = 1
        opponent.facingX = -1
        player.guardAmount = 1
        opponent.guardAmount = 1
        player.guarding = true
        opponent.guarding = true
        let playerRig = BoxerRig(team: .player, appearance: BoxerAppearance(opponent: playerAppearance))
        let opponentRig = BoxerRig(team: .rival, appearance: .counter)
        playerRig.applyOutfit(playerOutfit)
        playerRig.root.childNode(withName: "playerIdentityLabel", recursively: false)?.isHidden = true
        opponentRig.root.childNode(withName: "rivalIdentityLabel", recursively: false)?.isHidden = true
        replayScene.rootNode.addChildNode(playerRig.root)
        replayScene.rootNode.addChildNode(opponentRig.root)
        let floor = box(width: 5, height: 0.08, length: 5, radius: 0,
            color: UIColor(white: 0.48, alpha: 1), roughness: 0.95)
        floor.position.y = -0.04
        replayScene.rootNode.addChildNode(floor)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 2.8
        camera.position = SCNVector3(-0.9, 2.55, 4.4)
        camera.look(at: SCNVector3(0, 1.95, 0))
        replayScene.rootNode.addChildNode(camera)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 650
        replayScene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 1_050
        key.position = SCNVector3(-3, 5, 4)
        replayScene.rootNode.addChildNode(key)
        PunchContactGeometry.begin(player, target: PunchContactGeometry.target(opponent, zone: .head),
            radius: PunchContactGeometry.radius(.head))
        PunchContactGeometry.begin(opponent, target: PunchContactGeometry.target(player, zone: .head),
            radius: PunchContactGeometry.radius(.head))
        player.guarding = false
        player.guardAmount = 0
        player.attack = .leftHook
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = replayScene
        renderer.pointOfView = camera
        return (0..<32).map { index in
            let progress = Double(index) / 31
            player.actionTime = hook.duration * (0.20 + 0.64 * min(1, progress / 0.60))
            let interrupt = min(1, max(0, (progress - 0.40) / 0.30))
            opponent.attack = interrupt > 0 ? .cross : nil
            opponent.actionTime = cross.duration * 0.62 * interrupt
            opponent.guarding = opponent.attack == nil
            opponent.guardAmount = opponent.guarding ? 1 : 0
            playerRig.updateAuthoredPose(PunchContactGeometry.samplePose(player),
                position: SIMD3<Float>(-0.35, 0, 0), heading: .pi / 2)
            opponentRig.updateAuthoredPose(PunchContactGeometry.samplePose(opponent),
                position: SIMD3<Float>(0.35, 0, 0), heading: -.pi / 2)
            return renderer.snapshot(atTime: progress * 2, with: CGSize(width: 384, height: 216), antialiasingMode: .multisampling2X)
        }
    }

    private func makeRivalTargetBag() -> SCNNode {
        let hanger = SCNNode()
        hanger.name = "rivalTargetBag"
        hanger.position = SCNVector3(-0.18, 4.8, 0.94)
        let pad = box(width: 0.50, height: 0.48, length: 0.18, radius: 0.07,
            color: UIColor(white: 0.13, alpha: 1), roughness: 0.88)
        pad.position.y = -2.92
        pad.castsShadow = true
        hanger.addChildNode(pad)
        let marker = SCNCylinder(radius: 0.11, height: 0.012)
        marker.radialSegmentCount = 24
        marker.firstMaterial = material(color: UIColor(red: 0.035, green: 0.30, blue: 0.70, alpha: 1), roughness: 0.82)
        let target = SCNNode(geometry: marker)
        target.position = SCNVector3(0, 0, -0.095)
        target.eulerAngles.x = .pi / 2
        pad.addChildNode(target)
        for positionX: Float in [-0.16, 0.16] {
            hanger.addChildNode(cylinderBetween(SIMD3<Float>(positionX, 0, 0),
                SIMD3<Float>(positionX, -2.68, 0), radius: 0.018,
                color: UIColor(white: 0.42, alpha: 1), roughness: 0.55, metalness: 0.45))
        }
        return hanger
    }

    private func updateRivalTargetBag() {
        let response = [2.40, 4.40, 6.40].reduce(0.0) { result, strike in
            let elapsed = cinematicElapsed - strike
            guard elapsed >= 0, elapsed < 0.65 else { return result }
            return result + exp(-elapsed * 5) * sin(elapsed * 10)
        }
        rivalTargetBag.eulerAngles.x = -0.025 * Float(response)
    }

    private func makeChampionshipCornerSeat() -> SCNNode {
        let stool = SCNNode()
        stool.name = "championshipCornerSeat"
        let seat = box(width: 0.62, height: 0.10, length: 0.62, radius: 0.025,
            color: UIColor(white: 0.10, alpha: 1), roughness: 0.85)
        seat.position = SCNVector3(0, 0.20, -0.12)
        stool.addChildNode(seat)
        for positionX: Float in [-0.24, 0.24] {
            for positionZ: Float in [-0.36, 0.12] {
                let leg = box(width: 0.045, height: 0.15, length: 0.045, radius: 0,
                    color: UIColor(white: 0.55, alpha: 1), roughness: 0.32, metalness: 0.7)
                leg.position = SCNVector3(positionX, 0.075, positionZ)
                stool.addChildNode(leg)
            }
        }
        return stool
    }

    private func makeRivalChampionshipBelt() -> SCNNode {
        let display = SCNNode()
        display.name = "rivalChampionshipBelt"
        display.position = SCNVector3(-3.1, 0.92, 0.35)
        display.simdOrientation = simd_quatf(angle: -.pi * 0.82, axis: SIMD3<Float>(0, 1, 0))
        let shelf = box(width: 2.50, height: 0.10, length: 0.65, radius: 0.025,
            color: UIColor(white: 0.12, alpha: 1), roughness: 0.86)
        shelf.position.y = -0.30
        display.addChildNode(shelf)
        for positionX: Float in [-0.95, 0.95] {
            let leg = box(width: 0.10, height: 0.57, length: 0.50, radius: 0,
                color: UIColor(white: 0.10, alpha: 1), roughness: 0.72)
            leg.position = SCNVector3(positionX, -0.62, 0)
            display.addChildNode(leg)
        }
        for positionX: Float in [-0.70, 0.70] {
            let support = box(width: 0.10, height: 0.35, length: 0.16, radius: 0.018,
                color: UIColor(white: 0.08, alpha: 1), roughness: 0.90)
            support.position = SCNVector3(positionX, -0.075, 0.06)
            display.addChildNode(support)
        }
        let belt = ChampionshipBeltDesign.displayBelt()
        belt.position.y = 0.20
        display.addChildNode(belt)
        let fill = SCNNode()
        fill.name = "championshipBeltDisplayLight"
        fill.light = SCNLight()
        fill.light?.type = .spot
        fill.light?.intensity = 320
        fill.light?.color = UIColor(red: 1, green: 0.98, blue: 0.94, alpha: 1)
        fill.light?.spotInnerAngle = 30
        fill.light?.spotOuterAngle = 62
        fill.light?.attenuationStartDistance = 1
        fill.light?.attenuationEndDistance = 5
        fill.light?.castsShadow = false
        fill.position = SCNVector3(-1.1, 2.1, 2.8)
        fill.look(at: SCNVector3(0, 0.20, 0))
        display.addChildNode(fill)
        return display
    }

    private func makeRivalTrainingStage() -> SCNNode {
        let stage = SCNNode()
        stage.name = "rivalTrainingStage"
        let floor = box(width: 14, height: 0.12, length: 14, radius: 0,
            color: UIColor(white: 0.24, alpha: 1), roughness: 0.96)
        floor.position.y = -0.06
        stage.addChildNode(floor)
        let wall = box(width: 14, height: 6, length: 0.2, radius: 0,
            color: UIColor(white: 0.33, alpha: 1), roughness: 0.98)
        wall.position = SCNVector3(0, 3, -4.8)
        stage.addChildNode(wall)
        let padding = box(width: 14, height: 1.4, length: 0.25, radius: 0.03,
            color: UIColor(red: 0.26, green: 0.055, blue: 0.07, alpha: 1), roughness: 0.92)
        padding.position = SCNVector3(0, 0.7, -4.6)
        stage.addChildNode(padding)
        let bench = box(width: 2.4, height: 0.16, length: 0.65, radius: 0.03,
            color: UIColor(white: 0.16, alpha: 1), roughness: 0.9)
        bench.position = SCNVector3(-3.6, 0.48, -3.1)
        stage.addChildNode(bench)
        for positionX: Float in [-4.5, -2.7] {
            let leg = box(width: 0.10, height: 0.42, length: 0.55, radius: 0,
                color: UIColor(white: 0.12, alpha: 1), roughness: 0.7)
            leg.position = SCNVector3(positionX, 0.21, -3.1)
            stage.addChildNode(leg)
        }
        let bag = SCNCylinder(radius: 0.36, height: 1.7)
        bag.radialSegmentCount = 16
        bag.firstMaterial = material(color: UIColor(white: 0.08, alpha: 1), roughness: 0.86)
        let bagNode = SCNNode(geometry: bag)
        bagNode.position = SCNVector3(3.6, 1.9, -2.8)
        bagNode.castsShadow = true
        stage.addChildNode(bagNode)
        stage.addChildNode(cylinderBetween(SIMD3<Float>(3.6, 2.75, -2.8),
            SIMD3<Float>(3.6, 5.5, -2.8), radius: 0.025,
            color: UIColor(white: 0.44, alpha: 1), roughness: 0.5))
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 360
        ambient.light?.color = UIColor(white: 0.96, alpha: 1)
        stage.addChildNode(ambient)
        let key = SCNNode()
        key.name = "rivalTrainingKey"
        key.light = SCNLight()
        key.light?.type = .spot
        key.light?.intensity = 1_350
        key.light?.spotInnerAngle = 25
        key.light?.spotOuterAngle = 75
        key.light?.castsShadow = true
        key.light?.shadowRadius = 4
        key.light?.color = UIColor(red: 1, green: 0.96, blue: 0.9, alpha: 1)
        key.position = SCNVector3(-3.5, 5.8, 3)
        key.look(at: SCNVector3(0, 1.1, 0))
        stage.addChildNode(key)
        return stage
    }

    private func buildArena() {
        let ground = SCNFloor()
        ground.reflectivity = 0.08
        ground.reflectionFalloffEnd = 9
        ground.firstMaterial = material(color: UIColor(red: 0.018, green: 0.025, blue: 0.044, alpha: 1), roughness: 0.88)
        if usesPressureGym {
            ground.reflectivity = 0
            ground.firstMaterial = material(color: UIColor(white: 0.22, alpha: 1), roughness: 0.95)
        }
        let groundNode = SCNNode(geometry: ground)
        groundNode.position.y = -0.68
        groundNode.name = "arenaFloor"
        if !usesPressureGym && !usesRegionalHall { rootNode.addChildNode(groundNode) }

        let apronColor: UIColor = switch engine.storyBout?.opponent {
        case .counter: UIColor(red: 0.025, green: 0.14, blue: 0.095, alpha: 1)
        case .slugger: UIColor(white: 0.06, alpha: 1)
        case .rival: UIColor(white: 0.045, alpha: 1)
        default: UIColor(red: 0.055, green: 0.075, blue: 0.12, alpha: 1)
        }
        let apronRoughness: CGFloat = switch engine.storyBout?.opponent {
        case .counter, .slugger, .rival: 0.82
        default: 0.60
        }
        let apron = box(width: 13.5, height: 0.72, length: 13.5, radius: 0.08, color: apronColor, roughness: apronRoughness)
        apron.name = "ringApron"
        apron.position.y = -0.36
        rootNode.addChildNode(apron)

        let canvas = box(width: 12.35, height: 0.14, length: 12.35, radius: 0.03, color: UIColor(red: 0.78, green: 0.84, blue: 0.86, alpha: 1), roughness: 0.78)
        canvas.geometry?.firstMaterial = MapDressing.storyCanvasMaterial(for: engine.storyBout?.opponent)
        canvas.name = "ringCanvas"
        canvas.position.y = 0.04
        rootNode.addChildNode(canvas)

        rootNode.addChildNode(MapDressing.storyCenterMark(for: engine.storyBout?.opponent))
        if let ringDetails = MapDressing.storyRingDetails(for: engine.storyBout?.opponent) {
            rootNode.addChildNode(ringDetails)
        }

        buildPostsAndRopes()
        rootNode.addChildNode(MapDressing.arenaDetails())
        if usesPressureGym {
            rootNode.addChildNode(MapDressing.pressureGym())
        } else if usesRegionalHall {
            rootNode.addChildNode(MapDressing.regionalHall(opponent: engine.storyBout?.opponent ?? .outboxer))
        } else {
            buildArenaWalls()
            rootNode.addChildNode(MapDressing.audience())
        }
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

    private func buildLighting() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 260
        ambient.color = UIColor(red: 0.30, green: 0.39, blue: 0.57, alpha: 1)
        if usesPressureGym {
            ambient.intensity = 440
            ambient.color = UIColor(white: 0.94, alpha: 1)
        } else if usesRegionalHall {
            ambient.intensity = 380
            ambient.color = UIColor(red: 0.94, green: 0.96, blue: 0.95, alpha: 1)
            switch engine.storyBout?.opponent {
            case .counter:
                ambient.intensity = 340
                ambient.color = UIColor(red: 0.91, green: 0.96, blue: 0.93, alpha: 1)
            case .slugger:
                ambient.intensity = 300
                ambient.color = UIColor(red: 0.91, green: 0.87, blue: 0.81, alpha: 1)
            case .rival:
                ambient.intensity = 300
                ambient.color = UIColor(red: 0.82, green: 0.87, blue: 0.94, alpha: 1)
            default: break
            }
        }
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)
        lightBaselines.append((ambient, ambient.intensity))

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
            if usesPressureGym {
                light.color = index.isMultiple(of: 2)
                    ? UIColor(red: 0.94, green: 0.97, blue: 1, alpha: 1)
                    : UIColor(red: 1, green: 0.95, blue: 0.90, alpha: 1)
                light.intensity = index == 0 ? 1_400 : 950
            } else if usesRegionalHall {
                light.color = index.isMultiple(of: 2)
                    ? UIColor(red: 0.93, green: 0.97, blue: 1, alpha: 1)
                    : UIColor(red: 1, green: 0.97, blue: 0.93, alpha: 1)
                light.intensity = index == 0 ? 1_550 : 1_000
                if engine.storyBout?.opponent == .counter {
                    light.color = index.isMultiple(of: 2)
                        ? UIColor(red: 0.91, green: 1, blue: 0.96, alpha: 1)
                        : UIColor(white: 0.97, alpha: 1)
                    light.intensity = index == 0 ? 1_200 : 800
                } else if engine.storyBout?.opponent == .slugger {
                    light.color = index.isMultiple(of: 2)
                        ? UIColor(red: 1, green: 0.91, blue: 0.75, alpha: 1)
                        : UIColor(red: 0.94, green: 0.97, blue: 1, alpha: 1)
                    light.intensity = index == 0 ? 1_250 : 850
                } else if engine.storyBout?.opponent == .rival {
                    light.color = index.isMultiple(of: 2)
                        ? UIColor(red: 0.94, green: 0.97, blue: 1, alpha: 1)
                        : UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
                    light.intensity = index == 0 ? 1_650 : 1_100
                    light.spotInnerAngle = 32
                    light.spotOuterAngle = 78
                    light.attenuationStartDistance = 7
                    light.attenuationEndDistance = 24
                }
            }
            light.castsShadow = index == 0
            light.shadowRadius = 5
            light.shadowColor = UIColor.black.withAlphaComponent(0.65)
            light.shadowMapSize = CGSize(width: 1024, height: 1024)
            let node = SCNNode()
            node.light = light
            node.simdPosition = entry.0
            switch engine.storyBout?.opponent {
            case .counter: node.simdPosition.y = 6.2
            case .slugger: node.simdPosition.y = 6.45
            case .rival: node.simdPosition.y = 10.55
            default: break
            }
            node.look(at: SCNVector3(0, 0, 0))
            rootNode.addChildNode(node)
            lightBaselines.append((light, light.intensity))
        }
        if let opponent = engine.storyBout?.opponent,
           opponent == .counter || opponent == .slugger || opponent == .rival {
            let championship = opponent == .rival
            let lightRadius: Float = championship ? 9.0 : 8.0
            let lightHeight: Float = championship ? 8.5 : 6.0
            let targetRadius: Float = championship ? 17.0 : opponent == .counter ? 10.5 : 12.0
            let targetHeight: Float = championship ? 3.5 : 1.1
            for side in 0..<4 {
                if opponent == .counter && !side.isMultiple(of: 2) { continue }
                let light = SCNLight()
                light.type = .spot
                light.intensity = championship ? 950 : 600
                light.color = side.isMultiple(of: 2)
                    ? UIColor(red: 0.88, green: 0.93, blue: 1, alpha: 1)
                    : UIColor(red: 1, green: 0.95, blue: 0.86, alpha: 1)
                light.spotInnerAngle = 44
                light.spotOuterAngle = 100
                light.attenuationStartDistance = 4
                light.attenuationEndDistance = championship ? 28 : 18
                light.castsShadow = false
                let node = SCNNode()
                node.name = "storyAudienceLight\(side)"
                node.light = light
                let angle = Float(side) * .pi / 2
                node.simdPosition = SIMD3<Float>(sin(angle) * lightRadius, lightHeight, cos(angle) * lightRadius)
                node.look(at: SCNVector3(sin(angle) * targetRadius, targetHeight, cos(angle) * targetRadius))
                rootNode.addChildNode(node)
                lightBaselines.append((light, light.intensity))
            }
        }
    }

    private func updateChampionshipApplause() {
        let time = max(0, cinematicElapsed - ChampionshipEndingTiming.ceremonyStart)
        for (index, entry) in championshipApplauseRigs.enumerated() {
            let lateral = Float(index - 2) * 1.65
            let position = SIMD3<Float>(lateral, 0.13, -2.6 + abs(lateral) * 0.38)
            let cycle = (time + ChampionshipEndingTiming.applauseOffset(for: index))
                / ChampionshipEndingTiming.applausePeriod(for: index)
            let opening = Float((1 + cos(cycle * .pi * 2)) * 0.5)
            let handHeight: Float = 1.68 + Float(sin(cycle * .pi * 2)) * 0.012
            let handSpacing: Float = 0.195 + opening * 0.135
            var pose = FightPose.neutral(stride: 0, style: entry.style,
                stanceWidth: entry.style.stanceWidth, leanBias: entry.style.leanBias, pitchBias: entry.style.pitchBias)
            pose.torsoYaw *= 0.35
            pose.hipYaw *= 0.5
            pose.headBob = reducedMotion ? 0 : Float(sin(time * 2.4 + Double(index))) * 0.005
            pose.leftGlove = pose.torsoPoint(SIMD3<Float>(handSpacing, handHeight, 0.56))
            pose.rightGlove = pose.torsoPoint(SIMD3<Float>(-handSpacing, handHeight, 0.56))
            pose.leftElbow = pose.torsoPoint(SIMD3<Float>(0.52, 1.30, 0.22))
            pose.rightElbow = pose.torsoPoint(SIMD3<Float>(-0.52, 1.30, 0.22))
            pose.resolveArmLengths()
            entry.rig.updateAuthoredPose(pose, position: position, heading: atan2(-position.x, -position.z))
        }
        storyCoachRig.root.simdPosition = SIMD3<Float>(1.55, 0.13, 0.55)
        storyCoachRig.root.simdOrientation = simd_quatf(angle: atan2(-Float(1.55), -Float(0.55)),
            axis: SIMD3<Float>(0, 1, 0))
        storyCoachRig.updateApplause(at: time, reducedMotion: reducedMotion)
    }

    private func worldPosition(_ fighter: FighterModel) -> SIMD3<Float> {
        let scale: Float = 0.025
        return SIMD3<Float>(Float(fighter.x - 295) * scale, 0.13, Float(fighter.y - 295) * scale)
    }
}

@MainActor
private enum ChampionshipBeltDesign {
    private static let leather = material(color: UIColor(red: 0.035, green: 0.040, blue: 0.048, alpha: 1), roughness: 0.88)
    private static let gold = material(color: UIColor(red: 0.76, green: 0.59, blue: 0.24, alpha: 1), roughness: 0.60, metalness: 0.42)
    private static let paleGold = material(color: UIColor(red: 0.86, green: 0.72, blue: 0.45, alpha: 1), roughness: 0.56, metalness: 0.40)
    private static let antiqueGold = material(color: UIColor(red: 0.52, green: 0.38, blue: 0.14, alpha: 1), roughness: 0.64, metalness: 0.42)
    private static let enamel = material(color: UIColor(red: 0.025, green: 0.060, blue: 0.053, alpha: 1), roughness: 0.72)
    private static let ink = material(color: UIColor(white: 0.065, alpha: 1), roughness: 0.90)
    private static let thread = material(color: UIColor(red: 0.62, green: 0.51, blue: 0.31, alpha: 1), roughness: 0.92)
    private static let centerTemplate = makeCenterPlate()
    private static let sideTemplate = makeSidePlate()

    static func displayBelt() -> SCNNode {
        let root = SCNNode()
        root.name = "championshipDisplayBelt"
        let strap = SCNNode(geometry: SCNBox(width: 2.20, height: 0.38, length: 0.10, chamferRadius: 0.07))
        strap.geometry?.materials = [leather]
        root.addChildNode(strap)
        for row: Float in [-0.15, 0.15] {
            for index in 0..<36 {
                let stitch = SCNNode(geometry: SCNBox(width: 0.020, height: 0.007, length: 0.005, chamferRadius: 0.002))
                stitch.geometry?.materials = [thread]
                stitch.position = SCNVector3(Float(index) * 0.057 - 0.9975, row, 0.052)
                root.addChildNode(stitch)
            }
        }
        let center = plate(centerTemplate, width: 0.86)
        center.position.z = 0.075
        root.addChildNode(center)
        for side: Float in [-1, 1] {
            let panel = plate(sideTemplate, width: 0.30)
            panel.position = SCNVector3(side * 0.73, 0, 0.077)
            root.addChildNode(panel)
            for height: Float in [-0.070, 0.070] {
                root.addChildNode(stud(radius: 0.014, at: SCNVector3(side * 1.01, height, 0.058)))
            }
        }
        return root.flattenedClone()
    }

    static func wornBelt() -> SCNNode {
        let root = SCNNode()
        root.name = "championBeltAccessory"
        let strap = SCNCylinder(radius: 0.475, height: 0.17)
        strap.radialSegmentCount = 48
        strap.firstMaterial = leather
        let band = SCNNode(geometry: strap)
        band.scale.z = 0.84
        root.addChildNode(band)
        for height: Float in [-0.069, 0.069] {
            let seam = SCNTorus(ringRadius: 0.476, pipeRadius: 0.0035)
            seam.ringSegmentCount = 48
            seam.pipeSegmentCount = 6
            seam.firstMaterial = thread
            let node = SCNNode(geometry: seam)
            node.position.y = height
            node.scale.z = 0.84
            root.addChildNode(node)
        }
        let center = plate(centerTemplate, width: 0.42)
        center.position.z = 0.414
        root.addChildNode(center)
        for side: Float in [-1, 1] {
            let panel = plate(sideTemplate, width: 0.14)
            panel.position = SCNVector3(side * 0.31, 0, 0.322)
            panel.eulerAngles.y = side * .pi / 5
            root.addChildNode(panel)
        }
        for index in 0..<12 {
            let angle = Float(index) / 12 * .pi * 2
            let node = stud(radius: 0.006, at: SCNVector3(sin(angle) * 0.479, 0, cos(angle) * 0.403))
            node.eulerAngles.y = angle
            root.addChildNode(node)
        }
        return root.flattenedClone()
    }

    static func crown(material: SCNMaterial) -> SCNGeometry {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -0.075, y: -0.025))
        for point in [CGPoint(x: -0.095, y: 0.035), CGPoint(x: -0.035, y: 0.010),
                      CGPoint(x: 0, y: 0.075), CGPoint(x: 0.035, y: 0.010),
                      CGPoint(x: 0.095, y: 0.035), CGPoint(x: 0.075, y: -0.025)] {
            path.addLine(to: point)
        }
        path.close()
        let geometry = SCNShape(path: path, extrusionDepth: 0.006)
        geometry.chamferRadius = 0.002
        geometry.firstMaterial = material
        return geometry
    }

    private static func makeCenterPlate() -> SCNNode {
        let root = SCNNode()
        root.name = "championshipCenterPlate"
        let outline = UIBezierPath()
        outline.move(to: CGPoint(x: -0.40, y: 0.34))
        outline.addLine(to: CGPoint(x: 0.40, y: 0.34))
        outline.addQuadCurve(to: CGPoint(x: 0.50, y: 0.20), controlPoint: CGPoint(x: 0.50, y: 0.34))
        outline.addLine(to: CGPoint(x: 0.46, y: -0.17))
        outline.addQuadCurve(to: CGPoint(x: 0, y: -0.36), controlPoint: CGPoint(x: 0.36, y: -0.32))
        outline.addQuadCurve(to: CGPoint(x: -0.46, y: -0.17), controlPoint: CGPoint(x: -0.36, y: -0.32))
        outline.addLine(to: CGPoint(x: -0.50, y: 0.20))
        outline.addQuadCurve(to: CGPoint(x: -0.40, y: 0.34), controlPoint: CGPoint(x: -0.50, y: 0.34))
        outline.close()
        let base = SCNShape(path: outline, extrusionDepth: 0.040)
        base.chamferRadius = 0.010
        base.firstMaterial = antiqueGold
        root.addChildNode(SCNNode(geometry: base))
        let inset = SCNShape(path: outline, extrusionDepth: 0.018)
        inset.chamferRadius = 0.006
        inset.firstMaterial = gold
        let face = SCNNode(geometry: inset)
        face.scale = SCNVector3(0.92, 0.91, 1)
        face.position.z = 0.028
        root.addChildNode(face)
        let letteringDepth = face.position.z + inset.boundingBox.max.z + 0.0008
        let medallion = SCNCylinder(radius: 0.18, height: 0.016)
        medallion.radialSegmentCount = 32
        medallion.firstMaterial = enamel
        let seal = SCNNode(geometry: medallion)
        seal.eulerAngles.x = .pi / 2
        seal.position.z = 0.049
        root.addChildNode(seal)
        let rim = SCNTorus(ringRadius: 0.183, pipeRadius: 0.008)
        rim.ringSegmentCount = 32
        rim.pipeSegmentCount = 6
        rim.firstMaterial = paleGold
        let ring = SCNNode(geometry: rim)
        ring.eulerAngles.x = .pi / 2
        ring.position.z = 0.059
        root.addChildNode(ring)
        let emblem = SCNNode(geometry: crown(material: paleGold))
        emblem.scale = SCNVector3(1.4, 1.4, 1.4)
        emblem.position = SCNVector3(0, -0.025, 0.062)
        root.addChildNode(emblem)
        let leafMesh = SCNSphere(radius: 0.023)
        leafMesh.segmentCount = 10
        leafMesh.firstMaterial = paleGold
        for side: Float in [-1, 1] {
            for index in 0..<7 {
                let progress = Float(index) / 6
                let leaf = SCNNode(geometry: leafMesh)
                leaf.scale = SCNVector3(0.65, 1.6, 0.25)
                leaf.position = SCNVector3(side * (0.22 + 0.05 * sin(progress * .pi)), -0.15 + progress * 0.29, 0.051)
                leaf.eulerAngles.z = side * (0.58 - progress * 0.24)
                root.addChildNode(leaf)
            }
            for height: Float in [-0.14, 0.17] {
                root.addChildNode(stud(radius: 0.014, at: SCNVector3(side * 0.36, height, 0.043)))
            }
        }
        root.addChildNode(lettering("RIVAL", width: 0.54, height: 0.086, at: SCNVector3(0, 0.235, letteringDepth)))
        root.addChildNode(lettering("CHAMPION", width: 0.49, height: 0.056, at: SCNVector3(0, -0.255, letteringDepth)))
        return root.flattenedClone()
    }

    private static func makeSidePlate() -> SCNNode {
        let root = SCNNode()
        root.name = "championshipSidePlate"
        let frame = SCNBox(width: 1, height: 0.75, length: 0.065, chamferRadius: 0.10)
        frame.firstMaterial = gold
        root.addChildNode(SCNNode(geometry: frame))
        let inset = SCNBox(width: 0.82, height: 0.57, length: 0.018, chamferRadius: 0.07)
        inset.firstMaterial = enamel
        let face = SCNNode(geometry: inset)
        face.position.z = 0.041
        root.addChildNode(face)
        let emblem = SCNNode(geometry: crown(material: paleGold))
        emblem.scale = SCNVector3(2, 2, 2)
        emblem.position = SCNVector3(0, -0.040, 0.052)
        root.addChildNode(emblem)
        for side: Float in [-1, 1] {
            for height: Float in [-0.25, 0.25] {
                root.addChildNode(stud(radius: 0.023, at: SCNVector3(side * 0.37, height, 0.038)))
            }
        }
        return root.flattenedClone()
    }

    private static func plate(_ template: SCNNode, width: Float) -> SCNNode {
        let node = template.clone()
        node.simdScale = SIMD3<Float>(repeating: width)
        return node
    }

    private static func stud(radius: CGFloat, at position: SCNVector3) -> SCNNode {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 10
        geometry.firstMaterial = paleGold
        let node = SCNNode(geometry: geometry)
        node.position = position
        node.scale.z = 0.4
        return node
    }

    private static func lettering(_ text: String, width: Float, height: Float, at position: SCNVector3) -> SCNNode {
        let size = CGSize(width: 768, height: 768 * CGFloat(height / width))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let label = text as NSString
        let baseFont = UIFont.systemFont(ofSize: 100, weight: .black)
        let bounds = label.size(withAttributes: [.font: baseFont])
        let fontScale = min(size.width / max(1, bounds.width), size.height / max(1, bounds.height)) * 0.92
        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont.withSize(baseFont.pointSize * fontScale),
            .foregroundColor: ink.diffuse.contents as? UIColor ?? UIColor.black
        ]
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let textSize = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: (size.width - textSize.width) * 0.5,
                y: (size.height - textSize.height) * 0.5), withAttributes: attributes)
        }
        let printMaterial = SCNMaterial()
        printMaterial.lightingModel = .constant
        printMaterial.diffuse.contents = image
        printMaterial.blendMode = .alpha
        printMaterial.writesToDepthBuffer = false
        let geometry = SCNPlane(width: CGFloat(width), height: CGFloat(height))
        geometry.firstMaterial = printMaterial
        let node = SCNNode(geometry: geometry)
        node.position = position
        node.castsShadow = false
        return node
    }
}

@MainActor
private final class BoxerRig {
    private var championBelt: SCNNode?
    private var storyChampionDetails: [SCNNode] = []
    private var storyStarterDetails: [SCNNode] = []
    private lazy var storyChampionGold = material(color: UIColor(red: 0.86, green: 0.69, blue: 0.29, alpha: 1), roughness: 0.40, metalness: 0.52)
    private lazy var storyStarterWhite = material(color: UIColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1), roughness: 0.88)
    private lazy var storyStarterCrimson = material(color: UIColor(red: 0.72, green: 0.035, blue: 0.08, alpha: 1), roughness: 0.82)

    func setChampionBeltVisible(_ visible: Bool) {
        if visible, championBelt == nil {
            let belt = ChampionshipBeltDesign.wornBelt()
            waistband.addChildNode(belt)
            championBelt = belt
        }
        championBelt?.isHidden = !visible
    }
    /// `BoxerRig`
    /// - 역할: 단일 복서의 3D 리그를 구성하고, 엔진의 `FighterModel`로부터 매 프레임
    ///   시각적 포즈(어깨/팔/글러브/다리/머리/의상 등)를 계산해 SceneKit 노드를 업데이트합니다.
    /// - 주의: 이 클래스는 연출/렌더링 전용입니다. 리그 업데이트는 엔진의 물리/게임 룰을 변경하지 않습니다.
    enum Team {
        case player
        case rival
    }

    let root = SCNNode()
    private let team: Team
    private let appearance: BoxerAppearance
    private var cosmeticStyle: FightStyle {
        switch appearance {
        case .outboxer: .outboxing
        case .slugger: .infighting
        default: .standard
        }
    }
    private var usesHeavyAppearance: Bool { appearance == .pressure || appearance == .slugger }
    private var eyeDepth: Float { appearance == .counter ? 0.254 : appearance == .slugger ? 0.242 : 0.225 }
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
    private let impactMark = SCNNode()
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
    private var footPlant = FootPlantMotion()
    private var previousStyle: FightStyle?
    private var movementVisual: Float = 0
    private var duckVisual: Float = 0
    private var guardVisual: Float = 0
    private var observedAttackSerial: UInt64 = 0
    private var straightAnatomy: StraightPunchAnatomy?
    private var straightPunchEntry: FightPose?
    private var previousStancePose: FightPose?
    private var weaveHookEntry = WeaveMotion()
    private var previousLeftGlove: SIMD3<Float>?
    private var previousRightGlove: SIMD3<Float>?
    private var olderLeftGlove: SIMD3<Float>?
    private var olderRightGlove: SIMD3<Float>?
    private var previousSkinFlash: Bool?
    private var previousLegacyFlash: Bool?
    private var previousExposure: Bool?

    init(team: Team, identityText: String? = nil, appearance: BoxerAppearance = .classic) {
        // 리그 생성자: 팀에 따라 색상/글러브/라벨 등을 초기화합니다.
        // - 노드 트리(root/poreRoot/torso/limbs 등)를 구성하고, 기본 재질(material)을 설정합니다.
        // - 의상(champBadge, practice shirt) 같은 선택적 장식을 초기상태로 준비합니다.
        self.team = team
        self.appearance = appearance
        let isPressure = appearance == .pressure
        let isOutboxer = appearance == .outboxer
        let isCounter = appearance == .counter
        let isSlugger = appearance == .slugger
        let cosmeticTeam: Team = appearance == .rival ? .rival : team
        let teamColor = isPressure ? UIColor(red: 0.34, green: 0.025, blue: 0.10, alpha: 1)
            : isOutboxer ? UIColor(red: 0.025, green: 0.18, blue: 0.54, alpha: 1)
            : isCounter ? UIColor(red: 0.075, green: 0.13, blue: 0.18, alpha: 1)
            : isSlugger ? UIColor(white: 0.065, alpha: 1) : cosmeticTeam == .player
            ? UIColor(red: 0.025, green: 0.20, blue: 0.52, alpha: 1)
            : UIColor(red: 0.52, green: 0.025, blue: 0.07, alpha: 1)
        let gloveColor = isPressure ? UIColor(red: 0.43, green: 0.035, blue: 0.13, alpha: 1)
            : isOutboxer ? UIColor(red: 0.035, green: 0.30, blue: 0.72, alpha: 1)
            : isCounter ? UIColor(red: 0.49, green: 0.69, blue: 0.78, alpha: 1)
            : isSlugger ? UIColor(white: 0.10, alpha: 1) : cosmeticTeam == .player
            ? UIColor(red: 0.035, green: 0.29, blue: 0.70, alpha: 1)
            : UIColor(red: 0.68, green: 0.035, blue: 0.11, alpha: 1)
        let labelColor = isPressure ? UIColor(red: 0.96, green: 0.93, blue: 0.90, alpha: 1)
            : isCounter ? UIColor(red: 0.70, green: 0.87, blue: 0.95, alpha: 1) : team == .player
            ? UIColor(red: 0.28, green: 0.80, blue: 1, alpha: 1)
            : UIColor(red: 1, green: 0.30, blue: 0.43, alpha: 1)
        // A noticeably darker shade of the glove color, used for the wrist strap/seam/logo-patch details
        // that break up the glove's single flat color into distinct, more detailed-looking sections.
        let gloveAccentColor = isSlugger ? UIColor(red: 0.82, green: 0.66, blue: 0.23, alpha: 1)
            : isCounter ? UIColor(red: 0.84, green: 0.90, blue: 0.93, alpha: 1)
            : isPressure || isOutboxer ? UIColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1) : cosmeticTeam == .player
            ? UIColor(red: 0.02, green: 0.16, blue: 0.39, alpha: 1)
            : UIColor(red: 0.37, green: 0.02, blue: 0.06, alpha: 1)
        skinMaterial = material(color: isOutboxer
            ? UIColor(red: 0.78, green: 0.53, blue: 0.35, alpha: 1)
            : isCounter ? UIColor(red: 0.84, green: 0.78, blue: 0.75, alpha: 1)
            : isSlugger ? UIColor(red: 0.63, green: 0.37, blue: 0.23, alpha: 1)
            : UIColor(red: 0.74, green: 0.42, blue: 0.26, alpha: 1), roughness: isCounter ? 0.74 : 0.62)
        let usesClothFinish = isPressure || isOutboxer || isCounter || isSlugger
        teamMaterial = material(color: teamColor,
            roughness: isCounter ? 0.86 : isSlugger ? 0.91 : isPressure ? 0.88 : isOutboxer ? 0.80 : 0.34,
            metalness: usesClothFinish ? 0 : 0.08)
        gloveMaterial = material(color: gloveColor,
            roughness: isCounter ? 0.66 : isSlugger ? 0.60 : isPressure ? 0.62 : isOutboxer ? 0.68 : 0.24,
            metalness: usesClothFinish ? 0 : 0.10)
        gloveAccentMaterial = material(color: gloveAccentColor,
            roughness: isCounter ? 0.78 : isSlugger ? 0.72 : isPressure ? 0.78 : 0.42,
            metalness: isPressure || isCounter || isSlugger ? 0 : 0.04)
        let trailMaterial = material(color: gloveColor.withAlphaComponent(0.7), roughness: 0.15)
        trailMaterial.lightingModel = .constant
        trailMaterial.blendMode = .alpha
        trailMaterial.writesToDepthBuffer = false
        let darkMaterial = material(color: UIColor(red: 0.025, green: 0.035, blue: 0.055, alpha: 1), roughness: 0.75)

        torso = SCNNode(geometry: SCNCapsule(capRadius: 0.40, height: 0.94))
        torso.geometry?.materials = [skinMaterial]
        torso.scale = isCounter ? SCNVector3(1.14, 1, 0.77) : SCNVector3(1.08, 1, 0.72)
        trunks = SCNNode(geometry: SCNBox(width: 0.84, height: 0.45, length: 0.56, chamferRadius: 0.09))
        trunks.geometry?.materials = [teamMaterial]
        waistband = SCNNode(geometry: SCNBox(width: 0.88, height: 0.13, length: 0.59, chamferRadius: 0.025))
        waistband.geometry?.materials = [teamMaterial]
        if isCounter || isSlugger { waistband.geometry?.materials = [gloveAccentMaterial] }
        // A small gold-embossed "CHAMP" text plate mounted flush on the waistband's front face -- only shown
        // when the "Champ" outfit (500 cumulative wins) is equipped, toggled in `applyOutfit`.
        champBadge = BoxerRig.champBadge()
        waistband.addChildNode(champBadge)
        neck = SCNNode(geometry: SCNCylinder(radius: isCounter ? 0.16 : isOutboxer ? 0.13 : isSlugger ? 0.17 : 0.15, height: 0.24))
        neck.geometry?.materials = [skinMaterial]
        head = SCNNode(geometry: SCNSphere(radius: 0.30))
        head.geometry?.materials = [skinMaterial]
        head.scale = isCounter ? SCNVector3(0.95, 1.00, 0.93)
            : isSlugger ? SCNVector3(0.94, 1.02, 0.93)
            : isOutboxer ? SCNVector3(0.82, 1.12, 0.84) : SCNVector3(0.86, 1.08, 0.88)
        identityLabel = BoxerRig.identityLabel(text: identityText ?? (team == .player ? "ME" : "RIVAL"), color: labelColor)
        leftEye = SCNNode(geometry: SCNSphere(radius: 0.026))
        rightEye = SCNNode(geometry: SCNSphere(radius: 0.026))
        let eyeMaterial = isCounter
            ? material(color: UIColor(red: 0.10, green: 0.18, blue: 0.23, alpha: 1), roughness: 0.75) : darkMaterial
        leftEye.geometry?.materials = [eyeMaterial]
        rightEye.geometry?.materials = [eyeMaterial]
        if isCounter {
            leftEye.scale = SCNVector3(1.05, 0.62, 0.76)
            rightEye.scale = SCNVector3(1.05, 0.62, 0.76)
        }

        leftGlove = BoxerRig.glove(material: gloveMaterial, accentMaterial: gloveAccentMaterial, handedness: 1)
        rightGlove = BoxerRig.glove(material: gloveMaterial, accentMaterial: gloveAccentMaterial, handedness: -1)
        leftFoot = BoxerRig.shoe(material: teamMaterial, sole: darkMaterial)
        rightFoot = BoxerRig.shoe(material: teamMaterial, sole: darkMaterial)
        // A rounded joint sphere sits exactly at the shoulder anchor so the upper arm bone (which starts
        // at that same point) always reads as visually attached to the body, even though the torso capsule
        // is a separate piece of geometry that only approximately lines up with the pose's shoulder point.
        leftShoulderJoint = SCNNode(geometry: SCNSphere(radius: isCounter ? 0.185 : 0.175))
        leftShoulderJoint.geometry?.materials = [skinMaterial]
        rightShoulderJoint = SCNNode(geometry: SCNSphere(radius: isCounter ? 0.185 : 0.175))
        rightShoulderJoint.geometry?.materials = [skinMaterial]
        leftUpperArm = BoneNode(radius: isCounter ? 0.15 : 0.14, material: skinMaterial)
        leftForearm = BoneNode(radius: isCounter ? 0.125 : 0.12, material: skinMaterial)
        rightUpperArm = BoneNode(radius: isCounter ? 0.15 : 0.14, material: skinMaterial)
        rightForearm = BoneNode(radius: isCounter ? 0.125 : 0.12, material: skinMaterial)
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
        let prefix = team == .player ? "player" : "rival"
        torso.name = prefix + "Torso"
        trunks.name = prefix + "Pelvis"
        head.name = prefix + "Head"
        leftFoot.name = prefix + "LeftFoot"
        rightFoot.name = prefix + "RightFoot"
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
        let ink = SCNMaterial()
        ink.lightingModel = .constant
        ink.diffuse.contents = UIColor(red: 0.95, green: 0.94, blue: 0.90, alpha: 1)
        ink.writesToDepthBuffer = false
        for index in -1...1 {
            let stroke = SCNBox(width: 0.012, height: 0.095, length: 0.008, chamferRadius: 0)
            stroke.materials = [ink]
            let node = SCNNode(geometry: stroke)
            node.position = SCNVector3(Float(index) * 0.07, abs(Float(index)) * -0.018, 0)
            node.eulerAngles.z = Float(index) * -0.45
            impactMark.addChildNode(node)
        }
        impactMark.name = prefix + "ImpactMark"
        impactMark.constraints = [SCNBillboardConstraint()]
        impactMark.opacity = 0.8
        impactMark.isHidden = true
        poseRoot.addChildNode(impactMark)
        if isPressure { buildPressureDetails() }
        if isOutboxer { buildOutboxerDetails() }
        if isCounter || isSlugger { buildContenderDetails() }
    }

    private func buildPressureDetails() {
        let hairMaterial = material(color: UIColor(red: 0.055, green: 0.045, blue: 0.043, alpha: 1), roughness: 0.96)
        let trimMaterial = material(color: UIColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1), roughness: 0.88)
        let faceMaterial = material(color: UIColor(red: 0.29, green: 0.12, blue: 0.085, alpha: 1), roughness: 0.85)
        let hair = SCNNode(geometry: Self.croppedHair(material: hairMaterial))
        hair.name = "pressureCroppedHair"
        head.addChildNode(hair)
        for side: Float in [-1, 1] {
            let browGeometry = SCNBox(width: 0.11, height: 0.023, length: 0.025, chamferRadius: 0.008)
            browGeometry.materials = [hairMaterial]
            let brow = SCNNode(geometry: browGeometry)
            brow.position = SCNVector3(side * 0.126, 0.105, 0.268)
            brow.eulerAngles.z = side * 0.12
            head.addChildNode(brow)
            let ear = SCNNode(geometry: SCNSphere(radius: 0.047))
            ear.geometry?.materials = [skinMaterial]
            ear.scale = SCNVector3(0.65, 1, 0.58)
            ear.position = SCNVector3(side * 0.287, -0.025, 0)
            head.addChildNode(ear)
            let panelGeometry = SCNBox(width: 0.055, height: 0.35, length: 0.40, chamferRadius: 0.014)
            panelGeometry.materials = [trimMaterial]
            let panel = SCNNode(geometry: panelGeometry)
            panel.position = SCNVector3(side * 0.402, -0.015, 0)
            trunks.addChildNode(panel)
        }
        let nose = SCNNode(geometry: SCNSphere(radius: 0.040))
        nose.geometry?.materials = [skinMaterial]
        nose.scale = SCNVector3(0.74, 1.18, 1.10)
        nose.position = SCNVector3(0, -0.005, 0.29)
        head.addChildNode(nose)
        let mouthGeometry = SCNBox(width: 0.092, height: 0.013, length: 0.014, chamferRadius: 0.006)
        mouthGeometry.materials = [faceMaterial]
        let mouth = SCNNode(geometry: mouthGeometry)
        mouth.position = SCNVector3(0, -0.103, 0.279)
        head.addChildNode(mouth)
        waistband.geometry?.materials = [trimMaterial]
        for foot in [leftFoot, rightFoot] {
            let stripeGeometry = SCNBox(width: 0.045, height: 0.17, length: 0.016, chamferRadius: 0.005)
            stripeGeometry.materials = [trimMaterial]
            let stripe = SCNNode(geometry: stripeGeometry)
            stripe.position = SCNVector3(0, 0, 0.323)
            foot.addChildNode(stripe)
        }
    }

    private func buildOutboxerDetails() {
        let hairMaterial = material(color: UIColor(red: 0.10, green: 0.075, blue: 0.055, alpha: 1), roughness: 0.92)
        let trimMaterial = material(color: UIColor(white: 0.95, alpha: 1), roughness: 0.84)
        let faceMaterial = material(color: UIColor(red: 0.34, green: 0.17, blue: 0.12, alpha: 1), roughness: 0.88)
        let hair = SCNNode(geometry: Self.croppedHair(material: hairMaterial, swept: true))
        hair.name = "outboxerSweptHair"
        head.addChildNode(hair)
        for side: Float in [-1, 1] {
            let browGeometry = SCNBox(width: 0.10, height: 0.019, length: 0.023, chamferRadius: 0.006)
            browGeometry.materials = [hairMaterial]
            let brow = SCNNode(geometry: browGeometry)
            brow.position = SCNVector3(side * 0.12, 0.10, 0.27)
            brow.eulerAngles.z = side * 0.06
            head.addChildNode(brow)
            let ear = SCNNode(geometry: SCNSphere(radius: 0.043))
            ear.geometry?.materials = [skinMaterial]
            ear.scale = SCNVector3(0.60, 1, 0.52)
            ear.position = SCNVector3(side * 0.288, -0.02, 0)
            head.addChildNode(ear)
            let panelGeometry = SCNBox(width: 0.042, height: 0.35, length: 0.40, chamferRadius: 0.012)
            panelGeometry.materials = [trimMaterial]
            let panel = SCNNode(geometry: panelGeometry)
            panel.position = SCNVector3(side * 0.404, -0.015, 0)
            trunks.addChildNode(panel)
        }
        let nose = SCNNode(geometry: SCNSphere(radius: 0.036))
        nose.geometry?.materials = [skinMaterial]
        nose.scale = SCNVector3(0.70, 1.30, 1.06)
        nose.position = SCNVector3(0, -0.01, 0.29)
        head.addChildNode(nose)
        let mouthGeometry = SCNBox(width: 0.082, height: 0.011, length: 0.013, chamferRadius: 0.005)
        mouthGeometry.materials = [faceMaterial]
        let mouth = SCNNode(geometry: mouthGeometry)
        mouth.position = SCNVector3(0, -0.105, 0.282)
        head.addChildNode(mouth)
        waistband.geometry?.materials = [trimMaterial]
        for foot in [leftFoot, rightFoot] {
            let stripeGeometry = SCNBox(width: 0.045, height: 0.18, length: 0.018, chamferRadius: 0.005)
            stripeGeometry.materials = [trimMaterial]
            let stripe = SCNNode(geometry: stripeGeometry)
            stripe.position = SCNVector3(0, 0, 0.323)
            foot.addChildNode(stripe)
        }
    }

    private func buildContenderDetails() {
        let heavy = appearance == .slugger
        let prefix = heavy ? "slugger" : "counter"
        let hairMaterial = material(color: heavy
            ? UIColor(red: 0.055, green: 0.045, blue: 0.038, alpha: 1)
            : UIColor(red: 0.035, green: 0.040, blue: 0.043, alpha: 1), roughness: 0.96)
        let trimMaterial = material(color: heavy
            ? UIColor(red: 0.79, green: 0.63, blue: 0.24, alpha: 1)
            : UIColor(red: 0.75, green: 0.86, blue: 0.90, alpha: 1), roughness: 0.84)
        let seamMaterial = material(color: heavy ? UIColor(white: 0.09, alpha: 1)
            : UIColor(red: 0.045, green: 0.08, blue: 0.11, alpha: 1), roughness: 0.91)
        let faceMaterial = material(color: heavy
            ? UIColor(red: 0.27, green: 0.14, blue: 0.095, alpha: 1)
            : UIColor(red: 0.44, green: 0.36, blue: 0.38, alpha: 1), roughness: 0.90)
        if heavy {
            let hair = SCNNode(geometry: Self.croppedHair(material: hairMaterial, buzz: true))
            hair.name = prefix + "Hair"
            head.addChildNode(hair)
        } else {
            buildCounterHair()
        }
        for side: Float in [-1, 1] {
            let brow = box(width: heavy ? 0.128 : 0.113, height: heavy ? 0.030 : 0.019,
                length: 0.024, radius: 0.007, color: .black, roughness: 0.96)
            brow.geometry?.materials = [hairMaterial]
            brow.name = prefix + "Brow"
            brow.position = SCNVector3(side * 0.123, 0.104, 0.268)
            brow.eulerAngles.z = side * (heavy ? 0.13 : 0.015)
            head.addChildNode(brow)
            let ear = SCNNode(geometry: SCNSphere(radius: heavy ? 0.049 : 0.041))
            ear.geometry?.materials = [skinMaterial]
            ear.scale = SCNVector3(0.60, 1, 0.52)
            ear.position = SCNVector3(side * 0.287, -0.025, 0)
            ear.name = prefix + "Ear"
            head.addChildNode(ear)
            let earInset = SCNNode(geometry: SCNSphere(radius: heavy ? 0.025 : 0.020))
            earInset.geometry?.materials = [faceMaterial]
            earInset.scale = SCNVector3(0.30, 0.75, 0.55)
            earInset.position = SCNVector3(side * 0.025, 0, 0.013)
            ear.addChildNode(earInset)
            let panel = box(width: heavy ? 0.072 : 0.064, height: 0.35, length: 0.40,
                radius: 0.012, color: .white, roughness: 0.84)
            panel.geometry?.materials = [trimMaterial]
            panel.position = SCNVector3(side * 0.405, -0.015, 0)
            panel.name = prefix + "TrunkPanel"
            trunks.addChildNode(panel)
            if heavy {
                let seam = box(width: 0.018, height: 0.33, length: 0.41, radius: 0.006, color: .black, roughness: 0.91)
                seam.geometry?.materials = [seamMaterial]
                seam.position = SCNVector3(side * 0.438, -0.015, 0)
                trunks.addChildNode(seam)
            } else {
                let panelMaterial = material(color: UIColor(red: 0.29, green: 0.43, blue: 0.51, alpha: 1), roughness: 0.89)
                for face: Float in [-1, 1] {
                    let inset = box(width: 0.13, height: 0.29, length: 0.016, radius: 0.006,
                        color: .white, roughness: 0.89)
                    inset.geometry?.materials = [panelMaterial]
                    inset.position = SCNVector3(side * 0.27, -0.015, face * 0.282)
                    inset.eulerAngles.z = side * 0.16
                    inset.name = "counterAngledTrunkInset"
                    trunks.addChildNode(inset)
                }
            }
        }
        let nose = SCNNode(geometry: SCNSphere(radius: heavy ? 0.044 : 0.039))
        nose.geometry?.materials = [skinMaterial]
        nose.scale = heavy ? SCNVector3(0.92, 0.96, 1.03) : SCNVector3(0.82, 1.03, 1.16)
        nose.position = SCNVector3(0, -0.008, 0.288)
        nose.name = prefix + "Nose"
        head.addChildNode(nose)
        let mouth = box(width: heavy ? 0.108 : 0.078, height: heavy ? 0.015 : 0.010,
            length: 0.014, radius: 0.005, color: .black, roughness: 0.90)
        mouth.geometry?.materials = [faceMaterial]
        mouth.position = SCNVector3(0, -0.104, 0.282)
        mouth.name = prefix + "Mouth"
        head.addChildNode(mouth)
        if heavy {
            let stubbleMaterial = material(color: UIColor(red: 0.16, green: 0.105, blue: 0.074, alpha: 1), roughness: 0.97)
            let stubble = SCNNode(geometry: Self.jawStubble(material: stubbleMaterial))
            stubble.name = "sluggerJawStubble"
            head.addChildNode(stubble)
        }
        let waistPatch = box(width: heavy ? 0.18 : 0.14, height: 0.065, length: 0.018,
            radius: 0.006, color: .black, roughness: 0.91)
        waistPatch.geometry?.materials = [seamMaterial]
        waistPatch.position = SCNVector3(0, 0, 0.304)
        waistPatch.name = prefix + "WaistPatch"
        waistband.addChildNode(waistPatch)
        for positionX: Float in [-0.022, 0.022] {
            let stitch = box(width: 0.012, height: 0.033, length: 0.005, radius: 0.002, color: .white, roughness: 0.84)
            stitch.geometry?.materials = [trimMaterial]
            stitch.position = SCNVector3(positionX, 0, 0.013)
            stitch.eulerAngles.z = heavy ? (positionX < 0 ? -.pi / 6 : .pi / 6) : 0
            waistPatch.addChildNode(stitch)
        }
        for foot in [leftFoot, rightFoot] {
            let stripe = box(width: heavy ? 0.062 : 0.038, height: heavy ? 0.18 : 0.17,
                length: 0.018, radius: 0.005, color: .white, roughness: 0.84)
            stripe.geometry?.materials = [trimMaterial]
            stripe.position = SCNVector3(0, 0, 0.323)
            stripe.name = prefix + "BootStripe"
            foot.addChildNode(stripe)
            for row in 0..<3 {
                let lace = box(width: heavy ? 0.105 : 0.080, height: 0.012, length: 0.012,
                    radius: 0.003, color: .white, roughness: 0.84)
                lace.geometry?.materials = [trimMaterial]
                lace.position = SCNVector3(0, Float(row) * 0.038 - 0.022, 0.338)
                foot.addChildNode(lace)
            }
        }
    }

    private func buildCounterHair() {
        let hairMaterial = material(color: UIColor(red: 0.025, green: 0.030, blue: 0.035, alpha: 1), roughness: 0.94)
        let hair = SCNNode()
        hair.name = "counterAsymmetricHair"
        let undercut = SCNNode(geometry: Self.counterHairSurface(material: hairMaterial, undercut: true))
        undercut.name = "counterShortUndercut"
        let crown = SCNNode(geometry: Self.counterHairSurface(material: hairMaterial, undercut: false))
        crown.name = "counterCroppedCrown"
        let fringe = SCNNode(geometry: Self.counterHairFringe(material: hairMaterial))
        fringe.name = "counterAngularFringe"
        for section in [undercut, crown, fringe] { hair.addChildNode(section) }
        head.addChildNode(hair)
    }

    private static func counterHairSurface(material: SCNMaterial, undercut: Bool) -> SCNGeometry {
        let rows = 20
        let columns = 64
        let radius: Float = undercut ? 0.305 : 0.308
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for row in 0...rows {
            for column in 0...columns {
                let longitude = Float(column) / Float(columns) * .pi * 2
                let front = max(0, cos(longitude))
                let boundary: Float = undercut ? 1.70 - front * 0.60 : 1.28 - front * 0.30
                let start: Float = undercut ? 0.88 : 0
                let latitude = start + Float(row) / Float(rows) * (boundary - start)
                let normal = SIMD3<Float>(sin(latitude) * sin(longitude), cos(latitude), sin(latitude) * cos(longitude))
                let crownLift: Float = undercut ? 0 : 0.002 * max(0, normal.y)
                vertices.append(SCNVector3(normal * radius + SIMD3<Float>(0, crownLift, 0)))
                normals.append(SCNVector3(normal))
                if row < rows, column < columns {
                    let current = Int32(row * (columns + 1) + column)
                    let next = current + Int32(columns + 1)
                    indices.append(contentsOf: [current, next, current + 1, current + 1, next, next + 1])
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return geometry
    }

    private static func counterHairFringe(material: SCNMaterial) -> SCNGeometry {
        let locks: [(left: Float, right: Float, top: Float, tip: Float)] = [
            (-0.245, -0.155, 0.175, 0.100),
            (-0.160, -0.065, 0.192, 0.135),
            (-0.070, 0.025, 0.210, 0.160),
            (0.020, 0.120, 0.205, 0.175),
            (0.115, 0.225, 0.188, 0.178)
        ]
        let faces = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [3, 7, 6, 2], [0, 4, 7, 3], [1, 2, 6, 5]]
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for lock in locks {
            let outline = [SIMD2<Float>(lock.left, lock.top), SIMD2<Float>(lock.right, lock.top + 0.004),
                SIMD2<Float>(lock.right + 0.010, lock.tip + 0.014), SIMD2<Float>(lock.left + 0.024, lock.tip)]
            let front = outline.map { point in
                SIMD3<Float>(point.x, point.y, sqrt(max(0.001, 0.310 * 0.310 - point.x * point.x - point.y * point.y)))
            }
            let corners = front + front.map { $0 - SIMD3<Float>(0, 0, 0.009) }
            for face in faces {
                let normal = simd_normalize(simd_cross(corners[face[1]] - corners[face[0]], corners[face[2]] - corners[face[0]]))
                let start = Int32(vertices.count)
                for corner in face {
                    vertices.append(SCNVector3(corners[corner]))
                    normals.append(SCNVector3(normal))
                }
                indices.append(contentsOf: [start, start + 1, start + 2, start, start + 2, start + 3])
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return geometry
    }

    private static func jawStubble(material: SCNMaterial) -> SCNGeometry {
        let rows = 8
        let columns = 24
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for row in 0...rows {
            for column in 0...columns {
                let longitude = (Float(column) / Float(columns) - 0.5) * .pi * 1.05
                let upperLatitude = Float.pi * 0.56 + 0.045 * max(0, cos(longitude))
                let latitude = upperLatitude + Float(row) / Float(rows) * (.pi * 0.84 - upperLatitude)
                let normal = SIMD3<Float>(sin(latitude) * sin(longitude), cos(latitude), sin(latitude) * cos(longitude))
                vertices.append(SCNVector3(normal * 0.302))
                normals.append(SCNVector3(normal))
                if row < rows, column < columns {
                    let current = Int32(row * (columns + 1) + column)
                    let next = current + Int32(columns + 1)
                    indices.append(contentsOf: [current, next, current + 1, current + 1, next, next + 1])
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return geometry
    }

    private static func croppedHair(material: SCNMaterial, swept: Bool = false,
                                    parted: Bool = false, buzz: Bool = false) -> SCNGeometry {
        let rows = 10
        let columns = 32
        let radius: Float = buzz ? 0.303 : 0.306
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for row in 0...rows {
            for column in 0...columns {
                let longitude = Float(column) / Float(columns) * .pi * 2
                let hairline = buzz ? Float(1.76) - max(0, cos(longitude)) * 0.40
                    : parted ? Float(1.67) - max(0, cos(longitude)) * (0.27 + 0.035 * sin(longitude))
                    : swept ? Float(1.64) - max(0, cos(longitude)) * 0.28
                    : Float(1.74) - max(0, cos(longitude)) * 0.50
                let latitude = Float(row) / Float(rows) * hairline
                let normal = SIMD3<Float>(sin(latitude) * sin(longitude), cos(latitude),
                                         sin(latitude) * cos(longitude))
                let crown = swept ? max(0, normal.y) : 0
                let partDistance = abs(normal.x + 0.22)
                let part = parted ? max(0, 1 - partDistance / 0.085) * crown : 0
                let lift = crown * (parted ? 0.041 : 0.030) - part * 0.022
                vertices.append(SCNVector3(normal * radius + SIMD3<Float>(crown * 0.022, lift, 0)))
                normals.append(SCNVector3(normal))
                if row < rows, column < columns {
                    let current = Int32(row * (columns + 1) + column)
                    let next = current + Int32(columns + 1)
                    indices.append(contentsOf: [current, next, current + 1, current + 1, next, next + 1])
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return geometry
    }

    func update(
        from fighter: FighterModel, deltaTime: Double, elapsedTime: TimeInterval,
        reducedMotion: Bool = false, idleMotion: MenuIdleMotion? = nil,
        impact: CombatImpact? = nil, contactVisible: Bool = false, opponentDistance: Float? = nil,
        targetRadius: Float = Float(CombatData.fighterContactRadius), strike: CombatImpact? = nil, allowsContactBeat: Bool = true,
        showsLegacyReaction: Bool = true, usesPresentationDefense: Bool = false
    ) {
        // 리그의 메인 업데이트 루틴
        // - `fighter`의 물리/애니메이션 상태를 읽어 노드 변환(위치/회전/스케일/재질 발광 등)을 적용합니다.
        // - 이동/스트라이드/걷기 사이클, 안면/타격 반응, 펀치 트레일, 글러브 강조, 충돌 마크 표시, 의상 색상/방출 등을 모두 관리합니다.
        // - `reducedMotion`이 true면 일부 장식적 모션을 억제해 접근성 요구를 만족시킵니다.
        let worldScale = Float(CombatData.sceneScale)
        root.simdPosition = SIMD3<Float>(Float(fighter.x - 295) * worldScale, 0.13, Float(fighter.y - 295) * worldScale)
        root.simdOrientation = simd_quatf(angle: Float(atan2(fighter.facingX, fighter.facingY)),
            axis: SIMD3<Float>(0, 1, 0))

        let movementX = fighter.x - previousPosition.x
        let movementY = fighter.y - previousPosition.y
        let movement = hypot(movementX, movementY)
        let backstep = BackstepMotion.sample(elapsed: fighter.backstep.elapsed)
        previousPosition = SIMD2<Double>(fighter.x, fighter.y)
        let moving = movement > 0.05 && movement < 20
        let movementScale = moving ? 1 / max(0.001, movement) : 0
        let normalizedX = movementX * movementScale
        let normalizedY = movementY * movementScale
        let forwardMotion = Float(normalizedX * fighter.facingX + normalizedY * fighter.facingY)
        let strafeMotion = Float(-normalizedX * fighter.facingY + normalizedY * fighter.facingX)
        let activity: Float = fighter.attack != nil || moving || fighter.hitReaction > 0 ? 1 : 0
        let readiness = BoxingIdleMotion.sample(at: elapsedTime, activity: activity,
                                               reducedMotion: reducedMotion || fighter.knockedOut)
        let idle = idleMotion?.breath ?? readiness.breath
        let recoveryDefenseWeight: Float = fighter.knockedOut ? 1 - Float(fighter.getupProgress) : 1
        duckVisual = usesPresentationDefense
            ? DefensiveMotion.duckBlend(current: duckVisual, direction: fighter.duckDirection,
                                        deltaTime: deltaTime, reducedMotion: reducedMotion)
            : fighter.duckMotion.direction
        if deltaTime > 0 {
            movementVisual += ((moving ? Float(1) : 0) - movementVisual) * Float(1 - exp(-deltaTime * 24))
        }

        var pose = FightPose.neutral(
            stride: 0,
            style: fighter.style,
            stanceWidth: fighter.style.stanceWidth,
            leanBias: fighter.style.leanBias,
            pitchBias: fighter.style.pitchBias
        )
        if idleMotion == nil {
            pose.applyReadiness(motion: readiness)
        } else {
            pose.torsoY += idle
            pose.headBob = idle
        }
        guardVisual = usesPresentationDefense
            ? DefensiveMotion.guardBlend(current: guardVisual, raised: fighter.guarding,
                                         deltaTime: deltaTime, reducedMotion: reducedMotion)
            : fighter.guardAmount
        if guardVisual > 0 { pose.applyGuard(style: fighter.style, amount: guardVisual * recoveryDefenseWeight) }
        var weaveMotion = WeaveMotion.sample(direction: fighter.weave.direction,
                                             elapsed: fighter.weave.elapsed, reducedMotion: reducedMotion)
        let attackChanged = fighter.attackSerial != observedAttackSerial
        if fighter.attack == nil || fighter.knockedOut {
            weaveHookEntry = WeaveMotion()
        } else if attackChanged {
            weaveHookEntry = fighter.attack.flatMap { CombatData.attacks[$0]?.family } == .hook
                ? weaveMotion : WeaveMotion()
        }
        observedAttackSerial = fighter.attackSerial
        if let punch = fighter.attack, let spec = CombatData.attacks[punch], weaveHookEntry.amount > 0 {
            let carried = weaveHookEntry.carryingHook(progress: Float(fighter.actionTime / spec.duration),
                                                     contactProgress: Float(spec.activeStart / spec.duration))
            if carried.amount > weaveMotion.amount { weaveMotion = carried }
        }
        pose.applyDuck(direction: duckVisual * recoveryDefenseWeight * (1 - weaveMotion.amount), style: fighter.style)
        pose.applyWeave(weaveMotion, style: fighter.style)
        pose.applyBackstep(backstep)
        if let idleMotion { pose.applyMenuIdle(idleMotion) }
        pose.resolveArmLengths()
        let liveStance = pose
        if previousStyle != fighter.style { previousStancePose = nil }
        var attackProgress: Float?
        if let punch = fighter.attack, let spec = CombatData.attacks[punch] {
            let recovery = fighter.actionTime - spec.activeStart
            let beatImpact = allowsContactBeat && fighter.acted && strike?.punch == punch ? strike : nil
            let visualTime = recovery > 0
                ? spec.activeStart + ImpactMotionBeat.elapsed(recovery, impact: beatImpact, reducedMotion: reducedMotion)
                : fighter.actionTime
            let clockProgress = Float(min(1, visualTime / spec.duration))
            let progress = idleMotion == nil
                ? PunchRecoveryMotion.progress(punch, progress: clockProgress, landed: fighter.acted) : clockProgress
            attackProgress = progress
            if let entry = fighter.attackEntryPose, !fighter.knockedOut, idleMotion == nil {
                pose.blendAttackEntry(entry, punch: punch, progress: progress)
                straightPunchEntry = nil
            } else if spec.family == .straight, !fighter.knockedOut, idleMotion == nil {
                if attackChanged || straightPunchEntry == nil || previousStyle != fighter.style {
                    straightPunchEntry = previousStancePose ?? liveStance
                }
                if let entry = straightPunchEntry {
                    pose.blendStraightPunchEntry(entry, punch: punch, progress: progress)
                }
            } else {
                straightPunchEntry = nil
            }
            if !fighter.knockedOut {
                if attackChanged || straightAnatomy == nil || previousStyle != fighter.style {
                    straightAnatomy = StraightPunchAnatomy(pose: pose)
                }
            } else {
                straightAnatomy = nil
            }
            pose.applyAttack(punch, progress: progress, opponentDistance: opponentDistance,
                             reachMultiplier: Float(fighter.reachMultiplier(for: punch)), targetRadius: targetRadius,
                             straightAnatomy: straightAnatomy,
                             contactTarget: PunchContactGeometry.aim(fighter, punch: punch))
            if idleMotion == nil {
                pose.applyPunchRecovery(punch, progress: progress, landed: fighter.acted, reducedMotion: reducedMotion)
            }
        } else {
            straightPunchEntry = nil
            straightAnatomy = nil
        }
        previousStancePose = !fighter.knockedOut && fighter.hitReaction <= 0 && idleMotion == nil
            ? liveStance : nil

        if !fighter.knockedOut, idleMotion == nil {
            fighter.poseTransition?.apply(to: &pose, facingAngle: Float(atan2(fighter.facingX, fighter.facingY)))
        }
        let typedReaction = FighterImpactMotion.sample(impact ?? fighter.lastImpact, remaining: fighter.hitReaction,
                                   reducedMotion: reducedMotion, allowsContactBeat: allowsContactBeat)
        pose.applyImpact(typedReaction)
        // Finish an already-started step beneath any upper-body action. No movement is added to the engine.
        let restLeft = pose.leftFoot
        let restRight = pose.rightFoot
        let feet = footPlant.sample(
            rootPosition: root.simdPosition, rootRotation: root.simdOrientation,
            left: restLeft, right: restRight, deltaTime: deltaTime, moving: moving,
            reset: fighter.knockedOut || idleMotion != nil || previousStyle != fighter.style
                || movement > 20,
            reducedMotion: reducedMotion
        )
        previousStyle = fighter.style
        pose.leftFoot = feet.left
        pose.rightFoot = feet.right
        pose.leftKnee += (feet.left - restLeft) * 0.50
        pose.rightKnee += (feet.right - restRight) * 0.50
        // Weight follows the support leg; never swing the guard like a walking arm cycle.
        let stepLift = max(0, max(feet.left.y - restLeft.y, feet.right.y - restRight.y))
        pose.leftHip.x -= strafeMotion * movementVisual * 0.025
        pose.rightHip.x -= strafeMotion * movementVisual * 0.025
        pose.rootY += stepLift * (reducedMotion ? 0 : 0.18)
        if fighter.attack == nil, !fighter.guarding, !fighter.weave.isActive {
            pose.torsoPitch -= forwardMotion * movementVisual * 0.035
            pose.torsoLean += strafeMotion * movementVisual * 0.035
        }
        let reaction = impact == nil && showsLegacyReaction ? Float(min(1, fighter.hitReaction / 0.24)) : 0
        let reactionDirection: Float = team == .player ? -1 : 1
        let contactRoot = FighterPoseRoot(pose: pose, reaction: typedReaction,
            legacyAmount: reaction, legacyDirection: reactionDirection)
        poseRoot.simdPosition = contactRoot.position
        poseRoot.simdOrientation = contactRoot.rotation
        var knockdownFall: Float = 0
        if fighter.knockedOut {
            let knockdown = fighter.getupProgress > 0
                ? FighterKnockdownMotion.sampleRecovery(progress: Float(fighter.getupProgress), reducedMotion: reducedMotion)
                : FighterKnockdownMotion.sample(progress: Float(fighter.knockdown),
                                               reducedMotion: reducedMotion, impact: fighter.lastImpact)
            pose.applyKnockdown(knockdown)
            let fall = knockdown.fall
            knockdownFall = fall
            poseRoot.eulerAngles.x = -fall * (.pi / 2)
            poseRoot.eulerAngles.z += knockdown.roll
            let fallenRoot = SIMD3<Float>(contactRoot.position.x, 0.36, -0.25)
            poseRoot.simdPosition = contactRoot.position + (fallenRoot - contactRoot.position) * fall
        }

        let contacts = fighter.knockedOut ? (left: pose.leftFoot, right: pose.rightFoot)
            : pose.resolveContactSupport(rootPosition: poseRoot.simdPosition, rootRotation: poseRoot.simdOrientation)
        let leftContact = contacts.left
        let rightContact = contacts.right

        torso.simdPosition = SIMD3<Float>(0, pose.torsoY, 0) + pose.torsoOffset
        let torsoRotation = pose.torsoOrientation
        torso.simdOrientation = torsoRotation
        let hipRotation = simd_quatf(angle: pose.hipYaw, axis: SIMD3<Float>(0, 1, 0))
        let appearanceStyle: FightStyle = appearance == .classic ? fighter.style : cosmeticStyle
        torso.simdScale = SIMD3<Float>(
            (usesHeavyAppearance ? 1.15 : 1.08) * appearanceStyle.torsoWidthScale,
            appearanceStyle.torsoHeightScale,
            (usesHeavyAppearance ? 0.78 : 0.72) * appearanceStyle.torsoDepthScale
        )
        trunks.simdPosition = SIMD3<Float>(0, 0.86 - pose.bodyDrop * 0.72, 0)
        trunks.simdOrientation = hipRotation
        trunks.simdScale = SIMD3<Float>(appearanceStyle.torsoWidthScale, 1, appearanceStyle.torsoDepthScale)
        waistband.simdPosition = SIMD3<Float>(0, 1.08 - pose.bodyDrop * 0.82, 0)
        waistband.simdOrientation = hipRotation
        waistband.simdScale = SIMD3<Float>(appearanceStyle.torsoWidthScale, 1, appearanceStyle.torsoDepthScale)
        let headPivot = SIMD3<Float>(0, pose.torsoY, 0)
        // Head and neck used to remain upright while the torso folded/turned underneath them.
        // A partial torso rotation keeps the chin tucked and eyes on the rival rather than over-rotating.
        let headRotation = simd_slerp(simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)), torsoRotation, 0.55)
        func headPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
            headRotation.act(point - headPivot) + headPivot + pose.torsoOffset
        }
        neck.simdPosition = headPoint(SIMD3<Float>(0, 2.02 + pose.headBob - pose.bodyDrop, 0.015))
        head.simdPosition = headPoint(SIMD3<Float>(0, 2.28 + pose.headBob - pose.bodyDrop, 0.04))
        neck.simdOrientation = headRotation
        head.simdOrientation = simd_quatf(angle: -pose.torsoLean * 0.45 + typedReaction.headRoll,
                                         axis: SIMD3<Float>(0, 0, 1))
            * simd_quatf(angle: typedReaction.headYaw, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: typedReaction.headPitch, axis: SIMD3<Float>(1, 0, 0))
        let standingLabelHeight = 2.80 + pose.headBob - pose.bodyDrop
        let labelHeight = fighter.knockedOut
            ? 0.62 + (standingLabelHeight - 0.62) * (1 - knockdownFall) : standingLabelHeight
        identityLabel.simdPosition = SIMD3<Float>(0, labelHeight, 0)
        // Eye nodes are siblings, so translate with the head instead of orbiting independently.
        leftEye.simdPosition = head.simdPosition + head.simdOrientation.act(SIMD3<Float>(-0.11, 0.06, eyeDepth))
        rightEye.simdPosition = head.simdPosition + head.simdOrientation.act(SIMD3<Float>(0.11, 0.06, eyeDepth))
        neck.simdPosition += typedReaction.headOffset * 0.4
        head.simdPosition += typedReaction.headOffset
        leftEye.simdPosition += typedReaction.headOffset
        rightEye.simdPosition += typedReaction.headOffset
        if let idleMotion {
            neck.position.x += idleMotion.headSway * 0.5
            head.position.x += idleMotion.headSway
            leftEye.position.x += idleMotion.headSway
            rightEye.position.x += idleMotion.headSway
        }

        // Use the same translated/rotated chest frame as target solving, guards and the head.
        let leftShoulderPosition = pose.facingPoint(pose.leftShoulder)
        let leftElbowPosition = pose.facingPoint(pose.leftElbow)
        let leftGlovePosition = pose.facingPoint(pose.leftGlove)
        let rightShoulderPosition = pose.facingPoint(pose.rightShoulder)
        let rightElbowPosition = pose.facingPoint(pose.rightElbow)
        let rightGlovePosition = pose.facingPoint(pose.rightGlove)

        // Give each style a visibly different limb thickness to match its torso build scale above. The
        // shoulder joint ball uses its own (separate) scale so it can be tuned independently of arm/leg
        // bone thickness.
        let limbScale = appearanceStyle.limbRadiusScale * (usesHeavyAppearance ? 1.12 : 1)
        let shoulderScale = appearanceStyle.shoulderJointScale * (usesHeavyAppearance ? 1.08 : 1)
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

        // Every punch and resting guard shares fixed anatomy. No attack-time bone extension.
        let leftOverlap: Float = 0
        let rightOverlap: Float = 0
        updateArm(shoulder: leftShoulderPosition, elbow: leftElbowPosition, glove: leftGlovePosition, upper: leftUpperArm, lower: leftForearm, gloveNode: leftGlove, overlap: leftOverlap)
        updateArm(shoulder: rightShoulderPosition, elbow: rightElbowPosition, glove: rightGlovePosition, upper: rightUpperArm, lower: rightForearm, gloveNode: rightGlove, overlap: rightOverlap)
        if !leftSleeveUpper.node.isHidden {
            updateSleeve(shoulder: leftShoulderPosition, elbow: leftElbowPosition, glove: leftGlovePosition, upper: leftSleeveUpper, lower: leftSleeveLower, overlap: leftOverlap)
        }
        if !rightSleeveUpper.node.isHidden {
            updateSleeve(shoulder: rightShoulderPosition, elbow: rightElbowPosition, glove: rightGlovePosition, upper: rightSleeveUpper, lower: rightSleeveLower, overlap: rightOverlap)
        }
        updateLeg(hip: attachToTorso(pose.leftHip, pivotY: 0.86, rotation: hipRotation),
                  knee: pose.leftKnee, foot: leftContact, thigh: leftThigh, shin: leftShin, footNode: leftFoot)
        updateLeg(hip: attachToTorso(pose.rightHip, pivotY: 0.86, rotation: hipRotation),
                  knee: pose.rightKnee, foot: rightContact, thigh: rightThigh, shin: rightShin, footNode: rightFoot)
        let footBase = fighter.knockedOut ? simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)) : poseRoot.simdOrientation.inverse
        leftFoot.simdOrientation = footBase * simd_quatf(angle: pose.leftFootYaw, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: pose.leftFootPitch, axis: SIMD3<Float>(1, 0, 0))
        rightFoot.simdOrientation = footBase * simd_quatf(angle: pose.rightFootYaw, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: pose.rightFootPitch, axis: SIMD3<Float>(1, 0, 0))

        impactMark.isHidden = reducedMotion || !contactVisible || impact == nil
        if let impact, !impactMark.isHidden {
            if let point = impact.contactPoint {
                impactMark.simdPosition = poseRoot.simdOrientation.inverse.act(point - poseRoot.simdPosition)
            } else if impact.guarded && !impact.guardBroken {
                impactMark.simdPosition = (leftGlovePosition + rightGlovePosition) * 0.5 + SIMD3<Float>(0, 0.08, 0.22)
            } else if CombatData.attacks[impact.punch]?.targetZone == .body {
                impactMark.simdPosition = torso.simdPosition + SIMD3<Float>(0, -0.05, 0.38)
            } else {
                impactMark.simdPosition = head.simdPosition + SIMD3<Float>(0, -0.04, 0.28)
            }
        }

        leftTrail.node.isHidden = true
        rightTrail.node.isHidden = true
        leftGlove.scale = SCNVector3(1, 1, 1)
        rightGlove.scale = SCNVector3(1, 1, 1)
        if !reducedMotion, !fighter.knockedOut, deltaTime > 0, let punch = fighter.attack, let attackProgress {
            let extensionAmount = PunchMotion.sample(punch, progress: attackProgress).reach
            if extensionAmount > 0.06 {
                let leadLeft = [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch)
                let trail = leadLeft ? leftTrail : rightTrail
                let previous = leadLeft ? (olderLeftGlove ?? previousLeftGlove) : (olderRightGlove ?? previousRightGlove)
                let end = leadLeft ? leftGlovePosition : rightGlovePosition
                if let previous {
                    let displacement = previous - end
                    let length = simd_length(displacement)
                    // Two rendered samples, capped in length: a short motion trace, never a glowing beam.
                    if length > 0.025, length < 0.85 {
                        let start = end + displacement * min(1, 0.32 / length)
                        trail.update(from: start, to: end)
                        trail.node.opacity = 0.18
                        trail.node.isHidden = false
                    }
                }
                // Keep the same rigid glove/cuff geometry for every attack; no size inflation.
            }
        }

        olderLeftGlove = previousLeftGlove
        olderRightGlove = previousRightGlove
        previousLeftGlove = leftGlovePosition
        previousRightGlove = rightGlovePosition
        let skinFlash = fighter.hitReaction > 0.16
        let legacyFlash = showsLegacyReaction && impact == nil && !reducedMotion && skinFlash
        let exposed = fighter.exposed > 0
        if previousSkinFlash != skinFlash {
            skinMaterial.emission.contents = skinFlash ? UIColor.white : UIColor.black
            previousSkinFlash = skinFlash
        }
        if previousLegacyFlash != legacyFlash {
            skinMaterial.emission.intensity = legacyFlash ? 0.22 : 0
            previousLegacyFlash = legacyFlash
        }
        if previousExposure != exposed {
            teamMaterial.emission.contents = exposed ? UIColor(red: 0.95, green: 0.56, blue: 0.08, alpha: 1) : UIColor.black
            teamMaterial.emission.intensity = exposed ? 0.28 : 0
            previousExposure = exposed
        }
    }

    func updateAuthoredPose(_ pose: FightPose, position: SIMD3<Float>, heading: Float, usesProceduralPose: Bool = false) {
        root.simdPosition = position
        root.simdOrientation = simd_quatf(angle: heading, axis: SIMD3<Float>(0, 1, 0))
        poseRoot.simdPosition = SIMD3<Float>(pose.rootX, pose.rootY, pose.rootZ)
        poseRoot.simdOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        torso.simdPosition = SIMD3<Float>(0, pose.torsoY, 0) + pose.torsoOffset
        torso.simdOrientation = pose.torsoOrientation
        let appearanceStyle = cosmeticStyle
        torso.simdScale = SIMD3<Float>(
            (usesHeavyAppearance ? 1.15 : 1.08) * appearanceStyle.torsoWidthScale,
            appearanceStyle.torsoHeightScale,
            (usesHeavyAppearance ? 0.78 : 0.72) * appearanceStyle.torsoDepthScale)
        let hips = simd_quatf(angle: pose.hipYaw, axis: SIMD3<Float>(0, 1, 0))
        let pelvisPosition = (pose.leftHip + pose.rightHip) * 0.5
        trunks.simdPosition = pelvisPosition
        trunks.simdOrientation = hips
        trunks.simdScale = SIMD3<Float>(appearanceStyle.torsoWidthScale, 1, appearanceStyle.torsoDepthScale)
        waistband.simdPosition = pelvisPosition + SIMD3<Float>(0, 0.22, 0)
        waistband.simdOrientation = hips
        waistband.simdScale = SIMD3<Float>(appearanceStyle.torsoWidthScale, 1, appearanceStyle.torsoDepthScale)
        let headRotation = simd_slerp(simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)), pose.torsoOrientation, 0.55)
        let pivot = SIMD3<Float>(0, pose.torsoY, 0)
        let headDrop: Float = usesProceduralPose ? pose.bodyDrop : 0
        let headOffset: SIMD3<Float> = usesProceduralPose ? pose.torsoOffset : .zero
        neck.simdPosition = headRotation.act(SIMD3<Float>(0, 2.02 + pose.headBob - headDrop, 0.015) - pivot) + pivot + headOffset
        neck.simdOrientation = headRotation
        head.simdPosition = headRotation.act(SIMD3<Float>(0, 2.28 + pose.headBob - headDrop, 0.04) - pivot) + pivot + headOffset
        head.simdOrientation = simd_quatf(angle: -pose.torsoLean * 0.45, axis: SIMD3<Float>(0, 0, 1))
        leftEye.simdPosition = head.simdPosition + head.simdOrientation.act(SIMD3<Float>(-0.11, 0.06, eyeDepth))
        rightEye.simdPosition = head.simdPosition + head.simdOrientation.act(SIMD3<Float>(0.11, 0.06, eyeDepth))
        identityLabel.simdPosition = SIMD3<Float>(0, 2.8 + pose.headBob - headDrop, 0)
        let leftShoulderPosition = pose.facingPoint(pose.leftShoulder)
        let rightShoulderPosition = pose.facingPoint(pose.rightShoulder)
        leftShoulderJoint.simdPosition = leftShoulderPosition
        rightShoulderJoint.simdPosition = rightShoulderPosition
        let shoulderScale = appearanceStyle.shoulderJointScale * (usesHeavyAppearance ? 1.08 : 1)
        leftShoulderJoint.simdScale = SIMD3<Float>(repeating: shoulderScale)
        rightShoulderJoint.simdScale = SIMD3<Float>(repeating: shoulderScale)
        for bone in [leftUpperArm, leftForearm, rightUpperArm, rightForearm, leftThigh, leftShin, rightThigh, rightShin] {
            bone.setRadiusScale(appearanceStyle.limbRadiusScale * (usesHeavyAppearance ? 1.12 : 1))
        }
        updateArm(shoulder: leftShoulderPosition, elbow: pose.facingPoint(pose.leftElbow), glove: pose.facingPoint(pose.leftGlove),
                  upper: leftUpperArm, lower: leftForearm, gloveNode: leftGlove, overlap: 0)
        updateArm(shoulder: rightShoulderPosition, elbow: pose.facingPoint(pose.rightElbow), glove: pose.facingPoint(pose.rightGlove),
                  upper: rightUpperArm, lower: rightForearm, gloveNode: rightGlove, overlap: 0)
        updateLeg(hip: attachToTorso(pose.leftHip, pivotY: 0.86, rotation: hips), knee: pose.leftKnee, foot: pose.leftFoot,
                  thigh: leftThigh, shin: leftShin, footNode: leftFoot)
        updateLeg(hip: attachToTorso(pose.rightHip, pivotY: 0.86, rotation: hips), knee: pose.rightKnee, foot: pose.rightFoot,
                  thigh: rightThigh, shin: rightShin, footNode: rightFoot)
        leftFoot.simdOrientation = simd_quatf(angle: pose.leftFootYaw, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: pose.leftFootPitch, axis: SIMD3<Float>(1, 0, 0))
        rightFoot.simdOrientation = simd_quatf(angle: pose.rightFootYaw, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: pose.rightFootPitch, axis: SIMD3<Float>(1, 0, 0))
        leftTrail.node.isHidden = true
        rightTrail.node.isHidden = true
        impactMark.isHidden = true
        previousPosition = SIMD2<Double>(Double(position.x) / CombatData.sceneScale + 295,
                                         Double(position.z) / CombatData.sceneScale + 295)
        previousStancePose = nil
        previousStyle = nil
    }

    /// Recolors the cosmetic surfaces (trunks/waistband/shoes/gloves) to reflect an unlocked outfit choice.
    /// Only meaningful for the player rig — the rival always keeps its default look.
    func applyOutfit(_ outfit: OutfitID) {
        // 플레이어 전용 의상 적용: 장착 가능한 의상에 따라 재질 색상을 교체하고
        // 챔프 배지를 토글합니다. 라이벌은 기본 외형을 고정 유지합니다.
        guard team == .player, appearance == .classic else { return }
        // The "Gym Gray" outfit reuses the exact same long-sleeve shirt overlay the practice room always
        // forces on -- enabling it here (main match rig) also sets the gray team/glove colors as a side
        // effect; every other outfit case below then overrides those colors with its own.
        setPracticeAppearance(outfit == .gymGray)
        teamMaterial.roughness.contents = 0.34
        teamMaterial.metalness.contents = 0.08
        gloveMaterial.roughness.contents = 0.24
        gloveMaterial.metalness.contents = 0.10
        gloveAccentMaterial.diffuse.contents = UIColor(red: 0.02, green: 0.16, blue: 0.39, alpha: 1)
        gloveAccentMaterial.roughness.contents = 0.42
        gloveAccentMaterial.metalness.contents = 0.04
        waistband.geometry?.materials = [teamMaterial]
        if outfit == .storyChampion { buildStoryChampionOutfit() }
        for node in storyChampionDetails { node.isHidden = outfit != .storyChampion }
        if outfit == .storyStarter { buildStoryStarterOutfit() }
        for node in storyStarterDetails { node.isHidden = outfit != .storyStarter }
        switch outfit {
        case .classic:
            teamMaterial.diffuse.contents = UIColor(red: 0.025, green: 0.20, blue: 0.52, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.035, green: 0.29, blue: 0.70, alpha: 1)
        case .storyStarter:
            teamMaterial.diffuse.contents = UIColor(red: 0.035, green: 0.04, blue: 0.045, alpha: 1)
            teamMaterial.roughness.contents = 0.88
            teamMaterial.metalness.contents = 0
            gloveMaterial.diffuse.contents = UIColor(red: 0.72, green: 0.035, blue: 0.08, alpha: 1)
            gloveMaterial.roughness.contents = 0.64
            gloveMaterial.metalness.contents = 0
            gloveAccentMaterial.diffuse.contents = UIColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1)
            gloveAccentMaterial.roughness.contents = 0.88
            gloveAccentMaterial.metalness.contents = 0
            waistband.geometry?.materials = [storyStarterWhite]
        case .champion:
            teamMaterial.diffuse.contents = UIColor(red: 0.62, green: 0.47, blue: 0.06, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.83, green: 0.65, blue: 0.10, alpha: 1)
        case .storyChampion:
            teamMaterial.diffuse.contents = UIColor(red: 0.91, green: 0.92, blue: 0.94, alpha: 1)
            teamMaterial.roughness.contents = 0.84
            teamMaterial.metalness.contents = 0
            gloveMaterial.diffuse.contents = UIColor(red: 0.055, green: 0.065, blue: 0.08, alpha: 1)
            gloveMaterial.roughness.contents = 0.63
            gloveMaterial.metalness.contents = 0
            gloveAccentMaterial.diffuse.contents = UIColor(red: 0.87, green: 0.72, blue: 0.34, alpha: 1)
            gloveAccentMaterial.roughness.contents = 0.78
            gloveAccentMaterial.metalness.contents = 0
            waistband.geometry?.materials = [storyChampionGold]
        case .blackout:
            // 75 cumulative wins: a plain, matte near-black -- no text, no shine, just a stealthy "seen it
            // all" look that reads as noticeably darker than every other outfit at a glance.
            teamMaterial.diffuse.contents = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        case .gymGray:
            break // colors + shirt visibility already handled by setPracticeAppearance(true) above.
        case .unscathed:
            // 7 rounds won without taking a hit: a pristine off-white/platinum base with a bright sky-blue
            // glove accent -- reads as "spotless", i.e. never touched, in contrast to every other outfit's
            // darker palette.
            teamMaterial.diffuse.contents = UIColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.25, green: 0.55, blue: 0.85, alpha: 1)
        case .champ:
            // 500 cumulative wins: a deep black-and-gold combo (darker/richer than Champion Gold) plus the
            // embossed "CHAMP" waistband badge toggled below -- the game's top cosmetic tier.
            teamMaterial.diffuse.contents = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.55, green: 0.42, blue: 0.08, alpha: 1)
        case .streak:
            // 12-win streak ("Blaze"): a hot orange-red base with a bright yellow-orange glove accent, read
            // as "on fire" -- distinct from the golden Champion/Champ palettes by leaning fully into red.
            teamMaterial.diffuse.contents = UIColor(red: 0.62, green: 0.14, blue: 0.03, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.95, green: 0.42, blue: 0.05, alpha: 1)
        case .masteryInFighter:
            // 35 wins as In-Fighter ("Steel Guard"): a cool steel blue-gray, evoking a sturdy, balanced
            // defensive stance.
            teamMaterial.diffuse.contents = UIColor(red: 0.24, green: 0.29, blue: 0.36, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.42, green: 0.49, blue: 0.58, alpha: 1)
        case .masteryOutboxer:
            // 35 wins as Outboxing ("Ghost Step"): a sleek cyan/teal, evoking speed and evasive footwork.
            teamMaterial.diffuse.contents = UIColor(red: 0.04, green: 0.32, blue: 0.34, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.10, green: 0.62, blue: 0.64, alpha: 1)
        case .masterySlugger:
            // 35 wins as Slugger ("Heavyweight"): a deep maroon, evoking raw, unconditional power.
            teamMaterial.diffuse.contents = UIColor(red: 0.32, green: 0.03, blue: 0.07, alpha: 1)
            gloveMaterial.diffuse.contents = UIColor(red: 0.55, green: 0.06, blue: 0.12, alpha: 1)
        }
        champBadge.isHidden = outfit != .champ
    }

    private func buildStoryStarterOutfit() {
        guard storyStarterDetails.isEmpty else { return }
        func attach(_ node: SCNNode, to parent: SCNNode) {
            parent.addChildNode(node)
            storyStarterDetails.append(node)
        }
        for side: Float in [-1, 1] {
            let panel = box(width: 0.068, height: 0.37, length: 0.42, radius: 0.012,
                color: .red, roughness: 0.82)
            panel.geometry?.materials = [storyStarterCrimson]
            panel.position = SCNVector3(side * 0.407, -0.016, 0)
            panel.name = "firstBellTrunkPanel"
            attach(panel, to: trunks)
            for front: Float in [-1, 1] {
                let face = box(width: 0.09, height: 0.34, length: 0.014, radius: 0.004,
                    color: .red, roughness: 0.82)
                face.geometry?.materials = [storyStarterCrimson]
                face.position = SCNVector3(side * 0.34, -0.016, front * 0.275)
                attach(face, to: trunks)
                let piping = box(width: 0.014, height: 0.32, length: 0.014, radius: 0.004,
                    color: .white, roughness: 0.88)
                piping.geometry?.materials = [storyStarterWhite]
                piping.position = SCNVector3(side * 0.283, -0.016, front * 0.283)
                attach(piping, to: trunks)
            }
        }
        for front: Float in [-1, 1] {
            let hem = box(width: 0.57, height: 0.014, length: 0.014, radius: 0.004,
                color: .white, roughness: 0.88)
            hem.geometry?.materials = [storyStarterWhite]
            hem.position = SCNVector3(0, -0.200, front * 0.269)
            attach(hem, to: trunks)
        }
        let size = CGSize(width: 512, height: 96)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let label = "FIRST BELL" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 60, weight: .black),
            .foregroundColor: UIColor(red: 0.035, green: 0.04, blue: 0.045, alpha: 1)
        ]
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let textSize = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: (size.width - textSize.width) * 0.5,
                y: (size.height - textSize.height) * 0.5), withAttributes: attributes)
        }
        let printMaterial = SCNMaterial()
        printMaterial.lightingModel = .constant
        printMaterial.diffuse.contents = image
        printMaterial.blendMode = .alpha
        printMaterial.writesToDepthBuffer = false
        let lettering = SCNNode(geometry: SCNPlane(width: 0.32, height: 0.060))
        lettering.geometry?.materials = [printMaterial]
        lettering.position = SCNVector3(0, 0, 0.305)
        lettering.name = "firstBellWaistLettering"
        lettering.castsShadow = false
        attach(lettering, to: waistband)
        for glove in [leftGlove, rightGlove] {
            for stripe: Float in [-1, 1] {
                let mark = box(width: 0.012, height: 0.075, length: 0.007, radius: 0.003,
                    color: .white, roughness: 0.88)
                mark.geometry?.materials = [storyStarterWhite]
                mark.position = SCNVector3(stripe * 0.017, 0.012, 0.246)
                mark.eulerAngles.z = -0.28
                mark.name = "firstBellGloveMark"
                attach(mark, to: glove)
            }
            let cuff = SCNNode(geometry: SCNCylinder(radius: 0.139, height: 0.022))
            cuff.geometry?.materials = [storyStarterWhite]
            cuff.position.y = -0.273
            attach(cuff, to: glove)
        }
        for foot in [leftFoot, rightFoot] {
            let tongue = box(width: 0.13, height: 0.014, length: 0.18, radius: 0.006,
                color: .red, roughness: 0.82)
            tongue.geometry?.materials = [storyStarterCrimson]
            tongue.position = SCNVector3(0, 0.114, 0.125)
            tongue.name = "firstBellBootTongue"
            attach(tongue, to: foot)
            for row in 0..<4 {
                let lace = box(width: 0.13, height: 0.009, length: 0.012, radius: 0.003,
                    color: .white, roughness: 0.88)
                lace.geometry?.materials = [storyStarterWhite]
                lace.position = SCNVector3(0, 0.125, Float(row) * 0.038 + 0.064)
                attach(lace, to: foot)
            }
        }
    }

    private func buildStoryChampionOutfit() {
        guard storyChampionDetails.isEmpty else { return }
        let black = material(color: UIColor(red: 0.055, green: 0.06, blue: 0.07, alpha: 1), roughness: 0.90)
        let stitching = material(color: UIColor(red: 0.84, green: 0.68, blue: 0.28, alpha: 1), roughness: 0.85)
        func attach(_ node: SCNNode, to parent: SCNNode) {
            node.castsShadow = true
            parent.addChildNode(node)
            storyChampionDetails.append(node)
        }
        for side: Float in [-1, 1] {
            let panel = box(width: 0.064, height: 0.38, length: 0.42, radius: 0.014, color: .black, roughness: 0.90)
            panel.geometry?.materials = [black]
            panel.position = SCNVector3(side * 0.405, -0.015, 0)
            panel.name = "championshipTrunkPanel"
            attach(panel, to: trunks)
            for front: Float in [-1, 1] {
                let piping = box(width: 0.016, height: 0.34, length: 0.016, radius: 0.005, color: .white, roughness: 0.85)
                piping.geometry?.materials = [stitching]
                piping.position = SCNVector3(side * 0.315, -0.015, front * 0.282)
                attach(piping, to: trunks)
            }
        }
        for front: Float in [-1, 1] {
            let hem = box(width: 0.57, height: 0.020, length: 0.016, radius: 0.005, color: .white, roughness: 0.85)
            hem.geometry?.materials = [stitching]
            hem.position = SCNVector3(0, -0.197, front * 0.266)
            attach(hem, to: trunks)
        }
        let crestBacking = box(width: 0.23, height: 0.10, length: 0.02, radius: 0.012, color: .black, roughness: 0.90)
        crestBacking.geometry?.materials = [black]
        crestBacking.position = SCNVector3(0, 0, 0.305)
        crestBacking.name = "championshipWaistCrest"
        let crown = SCNNode(geometry: Self.championCrown(material: storyChampionGold))
        crown.scale = SCNVector3(0.75, 0.75, 0.75)
        crown.position = SCNVector3(0, -0.008, 0.014)
        crestBacking.addChildNode(crown)
        attach(crestBacking, to: waistband)
        let title = SCNText(string: "CHAMPION", extrusionDepth: 0.012)
        title.font = UIFont.systemFont(ofSize: 10, weight: .black)
        title.flatness = 0.20
        title.firstMaterial = black
        let lettering = SCNNode(geometry: title)
        let bounds = title.boundingBox
        lettering.pivot = SCNMatrix4MakeTranslation((bounds.min.x + bounds.max.x) * 0.5,
            (bounds.min.y + bounds.max.y) * 0.5, 0)
        lettering.scale = SCNVector3(0.0065, 0.0065, 0.0065)
        lettering.position = SCNVector3(0, 0.09, 0.284)
        lettering.name = "championshipTrunkLettering"
        attach(lettering, to: trunks)
        for glove in [leftGlove, rightGlove] {
            let knuckles = SCNNode(geometry: Self.championGlovePanel(material: storyChampionGold))
            knuckles.name = "championshipGoldKnuckles"
            let mark = SCNNode(geometry: Self.championCrown(material: black))
            mark.scale = SCNVector3(0.45, 0.45, 0.45)
            mark.position = SCNVector3(0, -0.005, 0.249)
            knuckles.addChildNode(mark)
            attach(knuckles, to: glove)
            let cuff = SCNNode(geometry: SCNCylinder(radius: 0.139, height: 0.020))
            cuff.geometry?.materials = [stitching]
            cuff.position.y = -0.273
            attach(cuff, to: glove)
        }
        for foot in [leftFoot, rightFoot] {
            let tongue = box(width: 0.13, height: 0.014, length: 0.18, radius: 0.006, color: .black, roughness: 0.90)
            tongue.geometry?.materials = [black]
            tongue.position = SCNVector3(0, 0.114, 0.125)
            tongue.name = "championshipBootTongue"
            attach(tongue, to: foot)
            for row in 0..<4 {
                let lace = box(width: 0.13, height: 0.009, length: 0.012, radius: 0.003, color: .white, roughness: 0.85)
                lace.geometry?.materials = [stitching]
                lace.position = SCNVector3(0, 0.125, Float(row) * 0.038 + 0.064)
                attach(lace, to: foot)
            }
            for side: Float in [-1, 1] {
                let seam = box(width: 0.012, height: 0.027, length: 0.27, radius: 0.006, color: .white, roughness: 0.85)
                seam.geometry?.materials = [stitching]
                seam.position = SCNVector3(side * 0.154, -0.058, 0.08)
                attach(seam, to: foot)
            }
        }
    }

    private static func championCrown(material: SCNMaterial) -> SCNGeometry {
        ChampionshipBeltDesign.crown(material: material)
    }

    private static func championGlovePanel(material: SCNMaterial) -> SCNGeometry {
        let rows = 6
        let columns = 24
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [Int32] = []
        for row in 0...rows {
            let latitude = Float(row) / Float(rows) * 0.91
            for column in 0...columns {
                let longitude = Float(column) / Float(columns) * .pi * 2
                let normal = SIMD3<Float>(sin(latitude) * cos(longitude), sin(latitude) * sin(longitude), cos(latitude))
                vertices.append(SCNVector3(normal * SIMD3<Float>(0.185, 0.185, 0.218) + SIMD3<Float>(0, 0, 0.025)))
                normals.append(SCNVector3(simd_normalize(normal / SIMD3<Float>(0.185, 0.185, 0.218))))
                if row < rows, column < columns {
                    let current = Int32(row * (columns + 1) + column)
                    let next = current + Int32(columns + 1)
                    indices.append(contentsOf: [current, next, current + 1, current + 1, next, next + 1])
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return geometry
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
        // 연습실 전용 외형 토글: 긴소매 셔츠/소매/글러브 색상 등 연습용 외형을 강제 적용합니다.
        // - 호출 위치: PracticeScene 초기화/의상 변경 흐름
        guard team == .player else { return }
        if enabled {
            for node in storyStarterDetails { node.isHidden = true }
        }
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
    private func attachToTorso(_ point: SIMD3<Float>, pivotY: Float, rotation: simd_quatf) -> SIMD3<Float> {
        let pivot = SIMD3<Float>(0, pivotY, 0)
        return rotation.act(point - pivot) + pivot
    }

    private func updateArm(shoulder: SIMD3<Float>, elbow: SIMD3<Float>, glove: SIMD3<Float>, upper: BoneNode, lower: BoneNode, gloveNode: SCNNode, overlap: Float) {
        // 상완/전완/손목(글러브) 노드의 위치 및 방향을 계산해 BoneNode와 gloveNode에 적용합니다.
        // `overlap`은 관절 겹침을 제어해 연속된 캡슐 지오메트리가 자연스럽게 보이도록 합니다.
        let wristVector = elbow - glove
        let wristDirection = simd_length(wristVector) > 0.001
            ? simd_normalize(wristVector)
            : SIMD3<Float>(0, -1, 0)
        let cuffOpening = glove + wristDirection * StraightPunchAnatomy.cuffOffset
        updateArmSegments(shoulder: shoulder, elbow: elbow, wrist: cuffOpening, upper: upper, lower: lower, overlap: overlap)
        gloveNode.simdPosition = glove
        gloveNode.simdOrientation = simd_quatf(from: SIMD3<Float>(0, -1, 0), to: wristDirection)
    }

    private func updateLeg(hip: SIMD3<Float>, knee: SIMD3<Float>, foot: SIMD3<Float>, thigh: BoneNode, shin: BoneNode, footNode: SCNNode) {
        // 다리(허벅지/정강이/발) 분절을 BoneNode로 갱신하고, 발 노드의 위치를 설정합니다.
        thigh.update(from: hip, to: knee)
        shin.update(from: knee, to: foot + SIMD3<Float>(0, 0.16, 0))
        footNode.simdPosition = foot
    }

    /// Runs a long-sleeve shirt sleeve (upper arm + forearm) along the exact same shoulder/elbow/glove points
    /// the skin arm bones use, extending slightly past the wrist toward the glove for a long-sleeve look. Kept
    /// as a separate pair of `BoneNode`s (rather than just thickening the skin arm) so the sleeves can be
    /// shown only in the practice room while the real-match bare-arm look is untouched.
    private func updateSleeve(shoulder: SIMD3<Float>, elbow: SIMD3<Float>, glove: SIMD3<Float>, upper: BoneNode, lower: BoneNode, overlap: Float) {
        // 셔츠 소매 업데이트: 팔 본(upper/lower)을 따라 소매가 자연스럽게 따라오도록 갱신합니다.
        // 소매는 피부 팔과 거의 동일한 매핑을 사용하되 커프(cuff) 쪽에서 살짝 더 글러브에 가깝게 위치합니다.
        let wristVector = elbow - glove
        let wristDirection = simd_length(wristVector) > 0.001
            ? simd_normalize(wristVector)
            : SIMD3<Float>(0, -1, 0)
        // Kept CLOSER to the glove than the skin arm's own cuff point (`updateArm`'s `cuffOpening` at 0.29)
        // so the gray sleeve fully overlaps the bare forearm all the way down to the wrist, with no exposed
        // skin gap at the cuff -- a previous, larger offset (0.36) stopped short of the skin arm's own
        // visible extent and left a sliver of bare forearm showing right above the glove.
        let cuffEdge = glove + wristDirection * 0.20
        updateArmSegments(shoulder: shoulder, elbow: elbow, wrist: cuffEdge, upper: upper, lower: lower, overlap: overlap)
    }

    private func updateArmSegments(shoulder: SIMD3<Float>, elbow: SIMD3<Float>, wrist: SIMD3<Float>, upper: BoneNode, lower: BoneNode, overlap: Float) {
        // Rounded capsule tips only touching at a point read as a split elbow in extension. Overlap
        // the existing segments slightly; do not add a new joint model or move the contact target.
        let upperAxis = (elbow - shoulder) / max(0.001, simd_length(elbow - shoulder))
        let forearmAxis = (wrist - elbow) / max(0.001, simd_length(wrist - elbow))
        upper.update(from: shoulder, to: elbow + upperAxis * overlap)
        lower.update(from: elbow - forearmAxis * overlap, to: wrist)
    }

    /// Builds the small gold-embossed "CHAMP" text plate mounted flush on the waistband's front face, shown
    /// only when the "Champ" outfit (500 cumulative wins) is equipped. A static child of the waistband
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
        let width: CGFloat = text == "ME" ? 0.48 : (text == "PRESSURE" ? 1.12 : 0.78)
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

extension FightPose {
    mutating func applyMenuIdle(_ motion: MenuIdleMotion) {
        torsoLean += motion.weightShift * 0.7
        torsoPitch += motion.breath * 0.5
        leftShoulder.y += motion.breath * 0.8
        rightShoulder.y += motion.breath * 0.8
        leftElbow.y += motion.breath * 0.5 + motion.leftGuard * 0.5
        rightElbow.y += motion.breath * 0.5 + motion.rightGuard * 0.5
        leftGlove.y += motion.leftGuard
        rightGlove.y += motion.rightGuard
        leftGlove.z += motion.leftGuard * 0.45
        rightGlove.z += motion.rightGuard * 0.45
        leftHip.y -= max(0, motion.weightShift) * 0.4
        rightHip.y -= max(0, -motion.weightShift) * 0.4
        leftKnee.y -= max(0, motion.weightShift) * 0.5
        rightKnee.y -= max(0, -motion.weightShift) * 0.5
        // Both feet stay planted. This is breathing/settling, not a sliding or bouncing idle loop.
    }
}

@MainActor
private final class BoneNode {
    let node: SCNNode
    private let geometry: SCNCapsule
    private let baseRadius: CGFloat
    private var displayedHeight: CGFloat
    private var radiusScale: Float = 1

    init(radius: CGFloat, material: SCNMaterial) {
        baseRadius = radius
        displayedHeight = radius * 2.2
        geometry = SCNCapsule(capRadius: radius, height: radius * 2.2)
        geometry.radialSegmentCount = 10
        geometry.capSegmentCount = 5
        geometry.materials = [material]
        node = SCNNode(geometry: geometry)
    }

    func update(from start: SIMD3<Float>, to end: SIMD3<Float>) {
        let direction = end - start
        let length = max(0.01, simd_length(direction))
        let height = CGFloat(length)
        if abs(height - displayedHeight) > 0.0001 {
            geometry.height = height
            displayedHeight = height
        }
        node.simdPosition = (start + end) * 0.5
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction / length)
    }

    /// Scales the bone's thickness relative to its original radius, used to give each fighting style a
    /// visibly different limb thickness (leaner for outboxing, stockier for infighting).
    func setRadiusScale(_ scale: Float) {
        guard radiusScale != scale else { return }
        geometry.capRadius = baseRadius * CGFloat(scale)
        radiusScale = scale
    }
}

@MainActor
private final class GymCoachRig {
    let root = SCNNode()
    private let head = SCNNode(geometry: SCNSphere(radius: 0.26))
    private let leftArm: Arm
    private let rightArm: Arm

    @MainActor
    private struct Arm {
        let shoulder: SIMD3<Float>
        let upperLength: Float
        let forearmLength: Float
        let neutralUpper: SIMD3<Float>
        let neutralForearm: SIMD3<Float>
        let upper: BoneNode
        let forearm: BoneNode
        let hand: SCNNode

        init(shoulder: SIMD3<Float>, elbow: SIMD3<Float>, handPosition: SIMD3<Float>,
             fabric: SCNMaterial, skin: SCNMaterial) {
            self.shoulder = shoulder
            upperLength = simd_distance(shoulder, elbow)
            forearmLength = simd_distance(elbow, handPosition)
            neutralUpper = simd_normalize(elbow - shoulder)
            neutralForearm = simd_normalize(handPosition - elbow)
            upper = BoneNode(radius: 0.105, material: fabric)
            forearm = BoneNode(radius: 0.09, material: fabric)
            hand = SCNNode(geometry: SCNSphere(radius: 0.075))
            hand.geometry?.materials = [skin]
        }

        func update(upperDirection: SIMD3<Float>? = nil, forearmDirection: SIMD3<Float>? = nil,
                    amount: Float = 0) {
            let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
            let upperRotation = simd_quatf(from: neutralUpper, to: simd_normalize(upperDirection ?? neutralUpper))
            let forearmRotation = simd_quatf(from: neutralForearm, to: simd_normalize(forearmDirection ?? neutralForearm))
            let blend = min(1, max(0, amount))
            let elbow = shoulder + simd_slerp(identity, upperRotation, blend).act(neutralUpper) * upperLength
            let handPosition = elbow + simd_slerp(identity, forearmRotation, blend).act(neutralForearm) * forearmLength
            upper.update(from: shoulder, to: elbow)
            forearm.update(from: elbow, to: handPosition)
            hand.simdPosition = handPosition
        }
    }

    init() {
        let skin = material(color: UIColor(red: 0.70, green: 0.51, blue: 0.37, alpha: 1), roughness: 0.65)
        let tracksuit = material(color: UIColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1), roughness: 0.55)
        let shoe = material(color: UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1), roughness: 0.5)
        let hair = material(color: UIColor(red: 0.72, green: 0.72, blue: 0.74, alpha: 1), roughness: 0.6)
        let dark = material(color: UIColor(red: 0.05, green: 0.04, blue: 0.05, alpha: 1), roughness: 0.4)
        leftArm = Arm(shoulder: SIMD3<Float>(0.34, 1.86, 0.05), elbow: SIMD3<Float>(0.08, 1.62, 0.30),
            handPosition: SIMD3<Float>(-0.30, 1.68, 0.33), fabric: tracksuit, skin: skin)
        rightArm = Arm(shoulder: SIMD3<Float>(-0.34, 1.86, 0.05), elbow: SIMD3<Float>(-0.08, 1.58, 0.34),
            handPosition: SIMD3<Float>(0.30, 1.64, 0.38), fabric: tracksuit, skin: skin)

        root.name = "gymCoach"
        let torso = SCNNode(geometry: SCNCapsule(capRadius: 0.34, height: 1.0))
        torso.geometry?.materials = [tracksuit]
        torso.position = SCNVector3(0, 1.5, 0)
        root.addChildNode(torso)
        let neck = SCNNode(geometry: SCNCylinder(radius: 0.13, height: 0.14))
        neck.geometry?.materials = [skin]
        neck.position = SCNVector3(0, 2.02, 0)
        root.addChildNode(neck)
        head.geometry?.materials = [skin]
        head.position = SCNVector3(0, 2.28, 0.01)
        head.scale = SCNVector3(0.9, 1.05, 0.92)
        root.addChildNode(head)
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
        let mustache = SCNNode(geometry: SCNBox(width: 0.13, height: 0.028, length: 0.03, chamferRadius: 0.012))
        mustache.geometry?.materials = [hair]
        mustache.position = SCNVector3(0, -0.075, 0.245)
        head.addChildNode(mustache)
        let hairCap = SCNNode(geometry: SCNSphere(radius: 0.27))
        hairCap.geometry?.materials = [hair]
        hairCap.scale = SCNVector3(1.03, 0.55, 1.05)
        hairCap.position = SCNVector3(0, 0.09, -0.04)
        head.addChildNode(hairCap)
        for arm in [leftArm, rightArm] {
            let joint = SCNNode(geometry: SCNSphere(radius: 0.145))
            joint.geometry?.materials = [tracksuit]
            joint.simdPosition = arm.shoulder
            for node in [joint, arm.upper.node, arm.forearm.node, arm.hand] {
                root.addChildNode(node)
            }
            arm.update()
        }
        for side: Float in [-1, 1] {
            let leg = SCNNode(geometry: SCNCapsule(capRadius: 0.14, height: 0.95))
            leg.geometry?.materials = [tracksuit]
            leg.position = SCNVector3(side * 0.16, 0.62, 0)
            root.addChildNode(leg)
            let foot = SCNNode(geometry: SCNBox(width: 0.18, height: 0.12, length: 0.32, chamferRadius: 0.05))
            foot.geometry?.materials = [shoe]
            foot.position = SCNVector3(side * 0.16, 0.08, 0.08)
            root.addChildNode(foot)
        }
    }

    func updateBriefing(at time: Double, duration: Double, reducedMotion: Bool) {
        let envelope = Float(min(1, max(0, min(time / 0.65, (duration - time) / 0.65))))
        let blend = envelope * envelope * (3 - 2 * envelope)
        let emphasis: Float = reducedMotion ? 1 : 0.94 + Float(sin(time * 2.6)) * 0.06
        leftArm.update(upperDirection: SIMD3<Float>(0.20, -0.56, 0.80),
            forearmDirection: SIMD3<Float>(-0.42, 0.62, 0.66), amount: blend * emphasis)
        rightArm.update(upperDirection: SIMD3<Float>(-0.20, -0.78, 0.59),
            forearmDirection: SIMD3<Float>(0.30, 0.10, 0.95), amount: blend * 0.7)
        head.eulerAngles.x = reducedMotion ? 0 : -Float(sin(time * 2.3)) * 0.045 * blend
    }

    func updateApplause(at time: Double, reducedMotion: Bool) {
        let arrival = Float(min(1, max(0, time / 0.65)))
        let blend = arrival * arrival * (3 - 2 * arrival)
        let closing: Float = reducedMotion ? 0.5
            : 0.5 - Float(cos(time / ChampionshipEndingTiming.coachApplausePeriod * .pi * 2)) * 0.5
        for (arm, side) in [(leftArm, Float(1)), (rightArm, Float(-1))] {
            let lowerDirection = SIMD3<Float>(-side * (0.10 + 0.56 * closing), 0.20, 0.98 - 0.25 * closing)
            arm.update(upperDirection: SIMD3<Float>(-side * 0.16, -0.72, 0.68),
                forearmDirection: lowerDirection, amount: blend)
        }
        head.eulerAngles.x = reducedMotion ? 0 : -Float(sin(time * 1.9)) * 0.035 * blend
    }
}

struct Arena3DView: UIViewRepresentable {
    @ObservedObject var controller: GameController
    @RivalReducedMotion private var reducedMotion

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
        controller.scene3D.setReducedMotion(reducedMotion)
        context.coordinator.start()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        view.pointOfView = controller.scene3D.cameraNode
        controller.scene3D.setReducedMotion(reducedMotion)
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

/// Menu rendering is owned by the view, not GameController.scene3D. There is no path from its
/// display link to live combat, saved records, sound or haptics. Hidden/inactive menus stop rendering.
struct RivalPortraitView: UIViewRepresentable {
    let isActive: Bool
    var storyOpponent: StoryOpponent? = nil
    @RivalReducedMotion private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase

    func makeCoordinator() -> Coordinator {
        Coordinator(scene: Arena3DScene(engine: CombatEngine(persistHabits: false, storyOpponent: storyOpponent)))
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.scene.cameraNode
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let animate = isActive && scenePhase == .active && !reducedMotion
        context.coordinator.configure(animate: animate, reducedMotion: reducedMotion)
        view.isPlaying = animate
        view.rendersContinuously = animate
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stop()
        view.isPlaying = false
        view.rendersContinuously = false
        view.scene = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        let scene: Arena3DScene
        private var displayLink: CADisplayLink?

        init(scene: Arena3DScene) {
            self.scene = scene
            super.init()
            scene.setCinematicMode(true, presentation: .menuPortrait)
        }

        func configure(animate: Bool, reducedMotion: Bool) {
            scene.setReducedMotion(reducedMotion)
            if animate {
                guard displayLink == nil else { return }
                scene.resetFrameClock()
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
                link.add(to: .main, forMode: .common)
                displayLink = link
            } else {
                stop()
            }
            scene.update(at: CACurrentMediaTime())
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
            scene.resetFrameClock()
        }

        @objc private func tick(_ link: CADisplayLink) {
            scene.update(at: link.timestamp)
        }
    }
}

/// A small standalone scene showing just the player rig in its guard stance, used to preview each fighting
/// style (and equipped outfit) in the waiting room without needing the full arena or an opponent.
@MainActor
final class StylePreviewScene: SCNScene {
    let cameraNode = SCNNode()
    private var rig = BoxerRig(team: .player)
    private var appearance: StoryOpponent?
    // BoxerRig.update() positions the root at (fighter.x - 295, _, fighter.y - 295) since 295 is the arena's
    // center coordinate — use that same center here so the standalone preview rig lands at world origin,
    // right where the camera below is aimed.
    private let fighter = FighterModel(name: "PREVIEW", x: 295, y: 295)
    private var startTime: TimeInterval?
    // Tracks when the current style's turntable spin began; reset to nil whenever the style changes so the
    // character snaps back to facing the camera and restarts its 360° turn from the beginning.
    private var turntableStartTime: TimeInterval?
    private var isConfigured = false
    private var reducedMotion = false
    // Full 360° turn every 16 seconds, applied purely as a Y-axis rotation on the rig itself — never on the
    // camera — so it always reads as a clean turntable spin instead of an orbiting-camera illusion.
    private let turntableSpeed: Float = (2 * .pi) / 16

    /// Builds lighting/camera/rig and performs the first pose update. Safe to call multiple times; only
    /// runs once. Not done in `init()` because overriding `SCNScene`'s parameterless `init()` with
    /// `@MainActor` isolation conflicts with its nonisolated `NSObject` declaration.
    func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        background.contents = UIColor(red: 0.035, green: 0.039, blue: 0.047, alpha: 1)
        fighter.guarding = true
        buildLighting()
        buildCamera()
        rootNode.addChildNode(rig.root)
        rig.update(from: fighter, deltaTime: 1.0 / 60.0, elapsedTime: 0,
                   reducedMotion: reducedMotion, usesPresentationDefense: true)
    }

    func setStyle(_ style: FightStyle) {
        guard fighter.style != style else { return }
        fighter.style = style
        turntableStartTime = nil
    }

    func setOutfit(_ outfit: OutfitID) {
        rig.applyOutfit(outfit)
    }

    func setChampionBelt(_ equipped: Bool) {
        rig.setChampionBeltVisible(equipped)
    }

    func setAppearance(_ opponent: StoryOpponent?) {
        guard appearance != opponent else { return }
        rig.root.removeFromParentNode()
        rig = BoxerRig(team: .player, appearance: BoxerAppearance(opponent: opponent))
        appearance = opponent
        turntableStartTime = nil
        rootNode.addChildNode(rig.root)
    }

    func setReducedMotion(_ enabled: Bool) {
        if enabled != reducedMotion { turntableStartTime = nil }
        reducedMotion = enabled
    }

    func update(at time: TimeInterval) {
        if startTime == nil { startTime = time }
        if turntableStartTime == nil { turntableStartTime = time }
        let elapsed = reducedMotion ? 0 : time - (startTime ?? time)
        rig.update(from: fighter, deltaTime: 1.0 / 60.0, elapsedTime: elapsed,
               reducedMotion: reducedMotion, usesPresentationDefense: true)
        // rig.update() restores the fighter's facing before the turntable rotation is applied.
        let turntableElapsed = reducedMotion ? 0 : Float(time - (turntableStartTime ?? time))
        rig.root.simdOrientation = simd_quatf(angle: turntableElapsed * turntableSpeed,
            axis: SIMD3<Float>(0, 1, 0)) * rig.root.simdOrientation
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
    var appearance: StoryOpponent? = nil
    var championBelt = false
    @RivalReducedMotion private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        context.coordinator.scene.configure()
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.scene.cameraNode
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.allowsCameraControl = false
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.scene.setAppearance(appearance)
        context.coordinator.scene.setStyle(style)
        context.coordinator.scene.setOutfit(outfit)
        context.coordinator.scene.setChampionBelt(championBelt)
        context.coordinator.scene.setReducedMotion(reducedMotion)
        let animate = !reducedMotion && scenePhase == .active
        if animate { context.coordinator.start() } else { context.coordinator.stop() }
        context.coordinator.scene.update(at: CACurrentMediaTime())
        view.isPlaying = animate
        view.rendersContinuously = animate
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stop()
        view.isPlaying = false
        view.rendersContinuously = false
    }

    @MainActor
    final class Coordinator: NSObject {
        let scene = StylePreviewScene()
        private var displayLink: CADisplayLink?

        func start() {
            scene.configure()
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
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
/// from the back) is entirely gym-themed. Uses a custom parameterized `init(engine:)` rather than
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
    private let coachRig = GymCoachRig()
    private var coachNode: SCNNode { coachRig.root }
    private var lastUpdateTime = 0.0
    private var publishTimer = 0.0
    private var cameraTarget = SIMD3<Float>(0, 1.35, 0)
    private var cameraForward = SIMD3<Float>(0, 0, -1)
    private let presentation = CombatPresentation()
    private var cameraContactOffset = SIMD3<Float>.zero
    private var reducedMotion = false
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

    init(engine: PracticeEngine) {
        self.engine = engine
        super.init()
        background.contents = UIColor(red: 0.058, green: 0.052, blue: 0.048, alpha: 1)
        fogColor = UIColor(red: 0.058, green: 0.052, blue: 0.048, alpha: 1)
        // Keep the 30-unit room's walls readable from the orbiting practice camera.
        fogStartDistance = 32
        fogEndDistance = 50
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

    func setReducedMotion(_ enabled: Bool) {
        reducedMotion = enabled
    }

    func update(at time: TimeInterval) {
        let deltaTime = lastUpdateTime == 0 ? 1.0 / 60.0 : max(0, min(0.05, time - lastUpdateTime))
        lastUpdateTime = time
        controller?.synchronizeHeldControls()
        presentation.advance(deltaTime: deltaTime)
        if engine.player.actionTime == 0 {
            presentation.receive(.attackStarted(fighter: .player))
        }
        engine.update(deltaTime: deltaTime)
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

        let impact = CombatImpact(attacker: .player, punch: punch, damage: damage, guarded: false,
                      guardBroken: false, counter: false, perfectCounter: false, knockout: false)
        presentation.receive(.impact(impact))

        spawnDamagePopup(damage: damage)
        controller?.notifyBagHit(punch: punch, damage: damage)
    }

    private func synchronizeVisuals(deltaTime: Double, elapsedTime: TimeInterval) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        let distance = Float(hypot(engine.player.x - PracticeEngine.bagX, engine.player.y - PracticeEngine.bagY) * CombatData.sceneScale)
        playerRig.update(from: engine.player, deltaTime: deltaTime, elapsedTime: elapsedTime,
                 reducedMotion: reducedMotion, opponentDistance: distance, targetRadius: Float(CombatData.bagContactRadius),
                 strike: presentation.playerStrike, showsLegacyReaction: false)
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
        cameraNode.simdPosition -= cameraContactOffset
        cameraContactOffset = .zero
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
        if !reducedMotion, presentation.cameraImpulse > 0 {
            let impulse = presentation.cameraImpulse
            desiredPosition -= forward * 0.09 * impulse
            desiredPosition.y += 0.035 * impulse
            target += forward * 0.045 * impulse
        }

        let positionBlend = Float(1 - exp(-deltaTime * 5.5))
        let targetBlend = Float(1 - exp(-deltaTime * 7.0))
        cameraNode.simdPosition += (desiredPosition - cameraNode.simdPosition) * positionBlend
        cameraTarget += (target - cameraTarget) * targetBlend
        if !reducedMotion {
            let kick = presentation.cameraContactKick
            cameraContactOffset = -forward * 0.035 * kick + SIMD3<Float>(0, 0.014 * kick, 0)
            cameraNode.simdPosition += cameraContactOffset
        }
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
        let wallColor = UIColor(red: 0.10, green: 0.095, blue: 0.10, alpha: 1)
        let matBlue = UIColor(red: 0.035, green: 0.29, blue: 0.62, alpha: 1)
        let matRed = UIColor(red: 0.60, green: 0.06, blue: 0.10, alpha: 1)

        rootNode.addChildNode(MapDressing.gymFloor())

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
        rootNode.addChildNode(MapDressing.gymDetails())
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
        let mirrorFrameNode = box(width: 5.8, height: 3.2, length: 0.08, radius: 0.02, color: mirrorFrame, roughness: 0.4, metalness: 0.5)
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

    private func buildCoach() -> SCNNode {
        coachNode.position = SCNVector3(
            Float(Self.coachFighterPosition.x - 295) * 0.025,
            0.13,
            Float(Self.coachFighterPosition.y - 295) * 0.025
        )
        coachNode.addChildNode(buildCoachTipLabel())
        return coachNode
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
        ambient.intensity = 520
        ambient.color = UIColor(white: 0.96, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 950
        // Gym only: one restrained shadow source grounds feet and the bag without adding lights.
        key.castsShadow = true
        key.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.shadowRadius = 4
        key.shadowColor = UIColor.black.withAlphaComponent(0.22)
        key.color = UIColor(red: 1, green: 0.95, blue: 0.86, alpha: 1)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = SIMD3<Float>(-3, 5, 3)
        keyNode.look(at: SCNVector3(0, 1.3, 0))
        rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 550
        fill.color = UIColor(red: 0.80, green: 0.86, blue: 0.95, alpha: 1)
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
    @RivalReducedMotion private var reducedMotion

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
        context.coordinator.scene.setReducedMotion(reducedMotion)
        context.coordinator.start()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.scene.setReducedMotion(reducedMotion)
    }

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