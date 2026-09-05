import SwiftUI
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
}

struct RootView: View {
    @StateObject private var controller = GameController()
    @State private var screen: AppScreen = .loading

    var body: some View {
        Group {
            if Arena3DScene.isIconCaptureMode {
                Arena3DView(controller: controller).ignoresSafeArea()
            } else {
                switch screen {
                case .loading:
                    LoadingScreenView(controller: controller) {
                        screen = .mainMenu
                    }
                case .mainMenu:
                    MainMenuView(controller: controller, screen: $screen)
                case .vsSplash:
                    VSSplashView(controller: controller) {
                        screen = .battle
                    }
                case .battle:
                    GameView(controller: controller, screen: $screen)
                case .practice:
                    PracticeView(
                        style: controller.playerStyle, outfit: controller.equippedOutfit, screen: $screen,
                        recordGymSeconds: controller.addGymSeconds
                    )
                }
            }
        }
    }
}
