/*
 PixelBoxingApp.swift

 파일 설명:
 - 앱의 진입점(App)과 루트 뷰 계층을 정의합니다. 앱 생명주기(state restoration, scene phases)와
     전역 환경(Localization, Settings, GameCenter 등)을 구성하는 초기화 코드가 포함됩니다.

 사용 영향 및 주의사항:
 - 앱 초기화 단계에서 설정/데이터 로드 실패는 전체 앱 실행에 영향을 줄 수 있으므로
     여기서 수행하는 작업은 비동기 처리나 오류 폴백을 권장합니다.
 - 주석 추가만으로 런타임 동작은 변경되지 않습니다.
*/
// - `RootView`: 현재 화면 스택(로딩, 메인 메뉴, 대결 등)을 관리하고 `GameController` 인스턴스를 보유합니다.

import SwiftUI
import SceneKit

private enum PromotionVideoCapture {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["RIVAL_PROMO_CAPTURE"] == "1"
        #else
        false
        #endif
    }

    @MainActor
    static func export() async throws {
        #if DEBUG
        let probeOnly = ProcessInfo.processInfo.environment["RIVAL_PROMO_PROBE"] == "1"
        let directory = URL.documentsDirectory.appendingPathComponent(
            probeOnly ? "PromotionCaptureProbe" : "PromotionCapture", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var reports: [[String: Any]] = []
        for scenario in ["counter", "exchange"] {
            let controller = GameController(persistsProgress: false, feedbackEnabled: false)
            let engine = controller.engine
            engine.startSession()
            engine.player.x = 280
            engine.player.y = 295
            engine.enemy.x = 330
            engine.enemy.y = 295
            let scene = controller.scene3D
            scene.controller = nil
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = scene
            let captureCamera = SCNNode()
            captureCamera.camera = scene.cameraNode.camera?.copy() as? SCNCamera
            captureCamera.simdPosition = SIMD3<Float>(-1.8, 3.7, 6.8)
            captureCamera.look(at: SCNVector3(0.25, 1.2, 0))
            scene.rootNode.addChildNode(captureCamera)
            renderer.pointOfView = captureCamera
            let scenarioDirectory = directory.appendingPathComponent(scenario, isDirectory: true)
            try FileManager.default.createDirectory(at: scenarioDirectory, withIntermediateDirectories: true)
            var counterFrame: Int?
            var counterAttackStarted = false
            let frameCount = scenario == "counter" ? 480 : 360
            for frame in 0..<frameCount {
                if scenario == "counter" {
                    if frame == 0 {
                        let started = engine.startAttack(engine.enemy, punch: .cross)
                        print("RIVAL_PROMO enemy cross accepted=\(started) phase=\(engine.phase)")
                    }
                    if frame == 3 { engine.setDuck(-1, active: true) }
                    if !counterAttackStarted, engine.lastPlayerDodgeGrade == .perfect {
                        counterAttackStarted = engine.startAttack(engine.player, punch: .jab)
                        print("RIVAL_PROMO counter input frame=\(frame) accepted=\(counterAttackStarted)")
                    }
                    if frame == 210 { engine.setDuck(0, active: false) }
                } else {
                    if frame == 12 || frame == 180 { _ = engine.startAttack(engine.player, punch: .jab) }
                    if frame == 38 || frame == 215 { _ = engine.startAttack(engine.player, punch: .cross) }
                    if frame == 100 { engine.setDuck(1, active: true) }
                    if frame == 135 { _ = engine.startAttack(engine.player, punch: .leftHook) }
                    if frame == 165 { engine.setDuck(0, active: false) }
                }
                let time = 1 + Double(frame) / 60
                scene.update(at: time)
                if counterFrame == nil, engine.perfectCounterCount > 0 { counterFrame = frame }
                if !probeOnly {
                    try autoreleasepool {
                        let image = renderer.snapshot(atTime: time, with: CGSize(width: 3840, height: 2160),
                            antialiasingMode: .multisampling4X)
                        guard let data = image.pngData() else {
                            throw NSError(domain: "RIVAL.PromotionCapture", code: 1)
                        }
                        let filename = String(format: "frame-%05d.png", frame)
                        try data.write(to: scenarioDirectory.appendingPathComponent(filename))
                    }
                }
                if frame % 30 == 0 {
                    print("RIVAL_PROMO \(scenario) frame \(frame)/\(frameCount)")
                    await Task.yield()
                }
            }
            if scenario == "counter", counterFrame == nil {
                throw NSError(domain: "RIVAL.PromotionCapture", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No actual perfect counter occurred"])
            }
            reports.append([
                "scenario": scenario, "frames": frameCount, "fps": 60,
                "width": 3840, "height": 2160,
                "perfectCounterFrame": counterFrame ?? -1,
                "perfectCounterCount": engine.perfectCounterCount
            ])
        }
        let report = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
        try report.write(to: directory.appendingPathComponent("capture.json"))
        print("RIVAL_PROMO COMPLETE \(directory.path)")
        #endif
    }
}
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .landscape
    }
}

@main
struct RIVALApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .persistentSystemOverlays(.hidden)
                .statusBarHidden()
        }
    }
}

enum AppScreen {
    case loading
    case mainMenu
    case vsSplash
    case battle
    case practice
    case storySelection
    case storyBattle
    case storySceneReplay
}

private enum OutfitUnlockReward: Identifiable, Equatable {
    static let storyAccessID = "story-access"

    case storyAccess(isLegacyCustomer: Bool)
    case outfit(OutfitID)
    case appearance(StoryOpponent)
    case championBelt

    var id: String {
        switch self {
        case .storyAccess: Self.storyAccessID
        case .outfit(let outfit): "outfit-\(outfit.rawValue)"
        case .appearance(let opponent): "appearance-\(opponent.rawValue)"
        case .championBelt: "champion-belt"
        }
    }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .storyAccess: RewardNotificationText.storyMode.text(for: language)
        case .outfit(let outfit): outfit.label(for: language)
        case .appearance(let opponent): StoryPurchaseReward.appearance(opponent).title(for: language)
        case .championBelt: StoryText.championBelt.text(for: language)
        }
    }

    var heading: RewardNotificationText {
        if case .storyAccess(let isLegacyCustomer) = self {
            return isLegacyCustomer ? .legacyCustomerBenefit : .storyAccessConfirmed
        }
        return self == .outfit(.storyStarter) ? .purchaseBonus : .achievementComplete
    }

    var message: RewardNotificationText {
        if case .storyAccess = self { return .storyUnlocked }
        return self == .championBelt ? .beltUnlocked : .outfitUnlocked
    }

    var symbol: String {
        switch self {
        case .storyAccess: "lock.open.fill"
        case .outfit: "tshirt.fill"
        case .appearance: "person.crop.square"
        case .championBelt: "medal.fill"
        }
    }
}

struct RootView: View {
    private static let unlockNoticesDefaultsKey = "rival.outfitUnlockNotices.v1"
    @StateObject private var controller: GameController
    @StateObject private var storyStore: StoryProgressStore
    @StateObject private var purchases = StoryPurchaseStore.shared
    @State private var storyController: GameController?
    @State private var screen: AppScreen = .loading
    @State private var knownUnlockIDs: Set<String>?
    @State private var pendingUnlocks: [OutfitUnlockReward] = []
    @Environment(\.scenePhase) private var scenePhase
    @RivalReducedMotion private var reducedMotion

    private var presentedUnlock: OutfitUnlockReward? {
        guard scenePhase == .active, screen != .loading, screen != .vsSplash,
              screen != .storySceneReplay, !Arena3DScene.isIconCaptureMode else { return nil }
        return pendingUnlocks.first
    }

    private var unlockAnimation: Animation? {
        reducedMotion || motionTestOverride ? nil : .easeOut(duration: UIStyleKit.fastDuration)
    }

    private var unlockedRewards: [OutfitUnlockReward] {
        var rewards: [OutfitUnlockReward] = []
        if purchases.hasStoryAccess {
            rewards.append(.storyAccess(isLegacyCustomer: purchases.isLegacyPaidCustomer))
        }
        rewards += OutfitID.allCases.filter { $0 != .classic && controller.isOutfitUnlocked($0) }
            .map(OutfitUnlockReward.outfit)
        for opponent in StoryOpponent.allCases where controller.isAppearanceUnlocked(opponent) {
            rewards.append(.appearance(opponent))
        }
        if controller.championBeltUnlocked { rewards.append(.championBelt) }
        return rewards
    }

    private var motionTestOverride: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["RIVAL_REDUCED_MOTION_TEST"] == "1" { return true }
        #endif
        return false
    }

    init() {
        #if DEBUG
        if PromotionVideoCapture.isEnabled {
            let storyStore = StoryProgressStore(defaults: nil)
            _storyStore = StateObject(wrappedValue: storyStore)
            _controller = StateObject(wrappedValue: GameController(persistsProgress: false,
                feedbackEnabled: false, storyStore: storyStore))
            _screen = State(initialValue: .battle)
            return
        }
        let fixture = ProcessInfo.processInfo.environment["RIVAL_PRESENTATION_TEST"]
        if fixture == "menu" || fixture == "fight" || fixture == "knockout" {
            let storyStore = StoryProgressStore(defaults: nil)
            _storyStore = StateObject(wrappedValue: storyStore)
            // UI-test fixtures never load, overwrite or reset the installed player's paid-app progress.
            let controller = GameController(persistsProgress: false, feedbackEnabled: false, storyStore: storyStore)
            if fixture != "menu" {
                controller.start()
                controller.engine.player.x = 280
                controller.engine.enemy.x = 330
                controller.engine.enemy.stagger = 1000
                if fixture == "knockout" { controller.engine.enemy.hp = 5 }
                controller.publishSnapshot()
            }
            _controller = StateObject(wrappedValue: controller)
            _screen = State(initialValue: fixture == "menu" ? .mainMenu : .battle)
            return
        }
        if StoryProgress.temporarilyUnlockStory {
            let storyStore = StoryProgressStore(defaults: UserDefaults(suiteName: "rival.story.preview.v1"))
            _storyStore = StateObject(wrappedValue: storyStore)
            _controller = StateObject(wrappedValue: GameController(persistsProgress: false, storyStore: storyStore))
            return
        }
        #endif
        let storyStore = StoryProgressStore()
        _storyStore = StateObject(wrappedValue: storyStore)
        _controller = StateObject(wrappedValue: GameController(storyStore: storyStore))
    }

    var body: some View {
        Group {
            if PromotionVideoCapture.isEnabled {
                Color.black.ignoresSafeArea()
                    .overlay(Text("Rendering promotional footage").foregroundStyle(.white))
                    .task {
                        do {
                            try await PromotionVideoCapture.export()
                            exit(0)
                        } catch {
                            print("RIVAL_PROMO FAILED \(error)")
                            exit(1)
                        }
                    }
            } else if Arena3DScene.isIconCaptureMode {
                Arena3DView(controller: controller).ignoresSafeArea()
            } else {
                switch screen {
                case .loading:
                    LoadingScreenView(controller: controller) {
                        screen = .mainMenu
                    }
                case .mainMenu:
                    MainMenuView(controller: controller, screen: $screen, storyProgress: storyStore.progress)
                case .vsSplash:
                    VSSplashView(controller: controller) {
                        screen = .battle
                    }
                case .battle:
                    GameView(controller: controller, screen: $screen)
                case .practice:
                    PracticeView(
                        style: controller.playerStyle, screen: $screen,
                        recordGymSeconds: controller.addGymSeconds
                    )
                case .storySelection:
                    if purchases.hasStoryAccess || StoryProgress.temporarilyUnlockCutscenes {
                        StorySelectionView(store: storyStore, controller: controller, onClose: { screen = .mainMenu },
                            onChallenge: { startStory($0, resumingStory: true) },
                            onNewChallenge: { startStory($0, resumingStory: false) },
                            onRematch: { startStory($0, resumingStory: false, shortIntroduction: true) },
                            onReplayIntroduction: replayStoryIntroduction,
                            onReplayRivalScene: replayStoryRivalScene)
                    } else {
                        MainMenuView(controller: controller, screen: $screen, storyProgress: storyStore.progress)
                    }
                case .storyBattle:
                    if let storyController, purchases.hasStoryAccess {
                        GameView(controller: storyController, screen: $screen)
                    }
                case .storySceneReplay:
                    if let storyController, purchases.hasStoryAccess || StoryProgress.temporarilyUnlockCutscenes {
                        StorySceneReplayView(controller: storyController, onClose: { screen = .storySelection })
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let reward = presentedUnlock {
                OutfitUnlockBanner(reward: reward)
                    .id(reward.id)
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 16)
                    .padding(.top, screen == .battle || screen == .storyBattle ? 84 : 8)
                    .transition(reducedMotion || motionTestOverride ? .opacity
                        : .move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(unlockAnimation, value: presentedUnlock?.id)
        .environment(\.rivalReducedMotionOverride, motionTestOverride)
        .task {
            beginUnlockTracking()
            await purchases.refreshAccess()
        }
        .onChange(of: unlockedRewards) { _, rewards in
            enqueueUnlockNotices(rewards)
        }
        .task(id: presentedUnlock?.id) {
            guard let reward = presentedUnlock else { return }
            markStoryAccessNoticePresented(reward)
            if UIAccessibility.isVoiceOverRunning {
                let language = LocalizationManager.shared.language
                UIAccessibility.post(notification: .announcement,
                    argument: "\(reward.heading.text(for: language)). \(reward.title(for: language)). \(reward.message.text(for: language))")
            }
            do {
                try await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 6 : 3.2))
            } catch {
                return
            }
            guard !Task.isCancelled, pendingUnlocks.first?.id == reward.id else { return }
            pendingUnlocks.removeFirst()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                controller.suspendForInactivity()
                storyController?.suspendForInactivity()
            } else {
                Task { await purchases.refreshAccess() }
                controller.resumeStoryIntroduction()
                storyController?.resumeStoryIntroduction()
            }
        }
        .onChange(of: screen) { previous, current in
                if (previous == .storyBattle || previous == .storySceneReplay),
                    current != .storyBattle && current != .storySceneReplay {
                if let storyController { controller.setSoundMuted(storyController.isSoundMuted) }
                storyController?.suspendForInactivity()
                storyController = nil
            }
        }
        .onChange(of: purchases.hasStoryAccess) { _, unlocked in
            if !unlocked && (screen == .storyBattle
                || (screen == .storySceneReplay && !StoryProgress.temporarilyUnlockCutscenes)) {
                storyController?.suspendForInactivity()
                screen = .mainMenu
            }
        }
    }

    private func beginUnlockTracking() {
        #if DEBUG
        if StoryProgress.temporarilyUnlockStory { return }
        #endif
        guard knownUnlockIDs == nil, storyStore.persistsProgress else { return }
        let saved = UserDefaults.standard.stringArray(forKey: Self.unlockNoticesDefaultsKey) ?? []
        let rewards = unlockedRewards
        knownUnlockIDs = Set(saved).union(rewards.filter { $0.id != OutfitUnlockReward.storyAccessID }.map(\.id))
        enqueueUnlockNotices(rewards)
    }

    private func enqueueUnlockNotices(_ rewards: [OutfitUnlockReward]) {
        let availableIDs = Set(rewards.map(\.id))
        pendingUnlocks.removeAll { !availableIDs.contains($0.id) }
        guard var known = knownUnlockIDs else { return }
        let presented = Set(UserDefaults.standard.stringArray(forKey: Self.unlockNoticesDefaultsKey) ?? [])
        if !presented.contains(OutfitUnlockReward.storyAccessID),
           !pendingUnlocks.contains(where: { $0.id == OutfitUnlockReward.storyAccessID }) {
            known.remove(OutfitUnlockReward.storyAccessID)
        }
        let newlyUnlocked = rewards.filter { known.insert($0.id).inserted }
        knownUnlockIDs = known
        guard !newlyUnlocked.isEmpty else { return }
        pendingUnlocks.insert(contentsOf: newlyUnlocked.filter { $0.id == OutfitUnlockReward.storyAccessID }, at: 0)
        pendingUnlocks.append(contentsOf: newlyUnlocked.filter { $0.id != OutfitUnlockReward.storyAccessID })
        let recorded = known.filter { $0 != OutfitUnlockReward.storyAccessID || presented.contains($0) }
        UserDefaults.standard.set(recorded.sorted(), forKey: Self.unlockNoticesDefaultsKey)
    }

    private func markStoryAccessNoticePresented(_ reward: OutfitUnlockReward) {
        guard reward.id == OutfitUnlockReward.storyAccessID, storyStore.persistsProgress else { return }
        var saved = Set(UserDefaults.standard.stringArray(forKey: Self.unlockNoticesDefaultsKey) ?? [])
        guard saved.insert(reward.id).inserted else { return }
        UserDefaults.standard.set(saved.sorted(), forKey: Self.unlockNoticesDefaultsKey)
    }

    private func startStory(_ opponent: StoryOpponent, resumingStory: Bool, shortIntroduction: Bool = false) {
          guard purchases.hasStoryAccess, opponent.isAvailable,
              storyStore.progress.isUnlocked(opponent) else { return }
        let session = GameController(persistsProgress: storyStore.persistsProgress && !StoryProgress.temporarilyUnlockStory,
            feedbackEnabled: storyStore.persistsProgress, storyOpponent: opponent, storyStore: storyStore)
        session.setPlayerStyle(controller.playerStyle)
        session.start(resumingStory: resumingStory, shortStoryIntroduction: shortIntroduction)
        storyController = session
        screen = .storyBattle
    }

    private func replayStoryIntroduction(_ opponent: StoryOpponent) {
          guard purchases.hasStoryAccess || StoryProgress.temporarilyUnlockCutscenes,
              opponent.isAvailable, storyStore.progress.canReplayIntroduction(opponent),
              StoryIntroClip.clip(for: opponent) != nil else { return }
        let session = GameController(persistsProgress: storyStore.persistsProgress && !StoryProgress.temporarilyUnlockStory,
            feedbackEnabled: storyStore.persistsProgress, storyOpponent: opponent, storyStore: storyStore)
        session.setPlayerStyle(controller.playerStyle)
        session.beginStoryIntroduction(previewOnly: true)
        storyController = session
        screen = .storySceneReplay
    }

    private func replayStoryRivalScene(_ opponent: StoryOpponent) {
          guard purchases.hasStoryAccess || StoryProgress.temporarilyUnlockCutscenes,
              storyStore.progress.canReplayRivalScene(opponent),
              StoryIntroClip.rivalScene(for: opponent) != nil else { return }
        let session = GameController(persistsProgress: storyStore.persistsProgress && !StoryProgress.temporarilyUnlockStory,
            feedbackEnabled: storyStore.persistsProgress, storyOpponent: opponent, storyStore: storyStore)
        session.setPlayerStyle(controller.playerStyle)
        session.beginStoryRivalScene(replay: true)
        storyController = session
        screen = .storySceneReplay
    }
}

private struct OutfitUnlockBanner: View {
    let reward: OutfitUnlockReward
    @ObservedObject private var loc = LocalizationManager.shared
    @ScaledMetric(relativeTo: .caption2) private var headingSize: CGFloat = 10
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 13

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: reward.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(MainMenuPalette.story)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(reward.heading.text(for: loc.language))
                    .font(.system(size: headingSize, weight: .bold))
                    .foregroundStyle(MainMenuPalette.story)
                Text("\(reward.title(for: loc.language)) · \(reward.message.text(for: loc.language))")
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(MainMenuPalette.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(MainMenuPalette.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(MainMenuPalette.story.opacity(0.55), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(reward.id == OutfitUnlockReward.storyAccessID ? "storyUnlockBanner" : "outfitUnlockBanner")
    }
}
