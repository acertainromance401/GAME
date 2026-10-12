/*
 GameCenterManager.swift

 파일 설명:
 - Game Center와의 연동을 담당합니다 (인증, 리더보드 제출, 업적 처리 등).
 - 비동기적 외부 서비스이므로 실패/타임아웃 처리 로직이 필요합니다.

 사용 영향 및 주의사항:
 - Game Center는 네트워크와 사용자 계정 상태에 의존하므로, 비활성 상태에서도 앱 흐름이
     끊기지 않도록 폴백(fallback) 경로를 준비해야 합니다.
 - 이 파일의 로직 변경은 원격 제출/인증 동작에 직접적 영향을 줍니다.
*/
import GameKit
import UIKit

/// Wraps all Apple Game Center (GameKit) integration behind one small surface so the rest of the app never
/// touches GameKit types directly. This is deliberately an OPTIONAL, best-effort layer: the game itself is a
/// fully offline, no-wifi-required local experience. Score failures never interrupt gameplay; authentication
/// and leaderboard failures are exposed only to the optional ranking screen so the player can retry.
///
/// Leaderboard ID: create a leaderboard with EXACTLY this ID in App Store Connect (My Apps -> RIVAL ->
/// Features -> Game Center) before scores submitted here will actually show up online. Until that ID
/// exists, `submit(totalWins:preferredStyle:)` calls simply fail quietly and `loadTopEntries()` returns
/// `.notConfigured`.
@MainActor
final class GameCenterManager: NSObject, ObservableObject {
    static let shared = GameCenterManager()

    static let totalWinsLeaderboardID = "com.acertainromance401.pixelboxing.totalWins"

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var authenticationError: String?

    enum LoadError: Error {
        case notAuthenticated
        case notConfigured
        case networkOrLoadFailed
    }

    struct Row: Identifiable {
        let id: String
        let rank: Int
        let displayName: String
        let wins: Int
        let style: FightStyle?
        let highestRound: Int
        let isLocalPlayer: Bool
    }

    private var pendingScore: (wins: Int, context: Int)?
    private var scoreSubmissionTask: Task<Void, Never>?
    private var pendingAuthenticationController: UIViewController?

    private override init() {}

    /// Registers GameKit's authentication handler. Safe to call multiple times (e.g. once at app launch) --
    /// GameKit only ever presents its sign-in sheet if the player isn't already signed in and hasn't
    /// previously dismissed it, and never blocks or interrupts local (offline) gameplay.
    func authenticate() {
        if isAuthenticating {
            resumeAuthentication()
            return
        }
        authenticationError = nil
        isAuthenticated = GKLocalPlayer.local.isAuthenticated
        isAuthenticating = true
        if isAuthenticated { submitPendingScore() }
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    self.pendingAuthenticationController = viewController
                    self.resumeAuthentication()
                    return
                }
                self.pendingAuthenticationController = nil
                self.isAuthenticating = false
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                self.authenticationError = self.isAuthenticated ? nil : error?.localizedDescription
                if self.isAuthenticated { self.submitPendingScore() }
                if let error {
                    print("GameCenterManager: authentication error: \(error.localizedDescription)")
                }
            }
        }
    }

    func resumeAuthentication() {
        isAuthenticated = GKLocalPlayer.local.isAuthenticated
        if isAuthenticated {
            authenticationError = nil
            submitPendingScore()
        } else if let pendingAuthenticationController {
            present(pendingAuthenticationController)
        }
    }

    /// Submits the player's cumulative win count, tagging the entry's `context` with an integer encoding
    /// both their most-used fighting style and their highest round reached (the round number is this game's
    /// stand-in for "AI difficulty" -- a higher round means the rival AI has learned more) so a custom
    /// leaderboard UI can show both next to each rank without needing any server of our own.
    func submit(totalWins: Int, preferredStyle: FightStyle?, highestRound: Int) {
        let context = Self.contextValue(for: preferredStyle, highestRound: highestRound)
        pendingScore = (max(0, totalWins), context)
        submitPendingScore()
    }

    private func submitPendingScore() {
        guard isAuthenticated, scoreSubmissionTask == nil, pendingScore != nil else { return }
        scoreSubmissionTask = Task { [weak self] in
            guard let self else { return }
            defer { self.scoreSubmissionTask = nil }
            while self.isAuthenticated, let score = self.pendingScore {
                do {
                    try await GKLeaderboard.submitScore(score.wins, context: score.context,
                        player: GKLocalPlayer.local, leaderboardIDs: [Self.totalWinsLeaderboardID])
                    if self.pendingScore?.wins == score.wins, self.pendingScore?.context == score.context {
                        self.pendingScore = nil
                    }
                } catch {
                    print("GameCenterManager: score submission failed: \(error.localizedDescription)")
                    return
                }
            }
        }
    }

    /// Loads the top global entries for the total-wins leaderboard, decoding each entry's preferred style
    /// back out of its `context` value.
    func loadTopEntries(count: Int = 25) async -> Result<[Row], LoadError> {
        guard isAuthenticated, GKLocalPlayer.local.isAuthenticated else {
            isAuthenticated = false
            return .failure(.notAuthenticated)
        }
        submitPendingScore()
        await scoreSubmissionTask?.value
        guard isAuthenticated, GKLocalPlayer.local.isAuthenticated else {
            isAuthenticated = false
            return .failure(.notAuthenticated)
        }
        do {
            let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [Self.totalWinsLeaderboardID])
            guard let leaderboard = leaderboards.first else { return .failure(.notConfigured) }
            let localPlayerID = GKLocalPlayer.local.gamePlayerID
            let (localEntry, entries, _) = try await leaderboard.loadEntries(
                for: .global,
                timeScope: .allTime,
                range: NSRange(location: 1, length: min(100, max(1, count)))
            )
            var visibleEntries = entries
            if let localEntry, !entries.contains(where: { $0.player.gamePlayerID == localPlayerID }) {
                visibleEntries.append(localEntry)
            }
            let rows = visibleEntries.map { entry in
                let (style, highestRound) = Self.decode(context: entry.context)
                return Row(
                    id: entry.player.gamePlayerID,
                    rank: entry.rank,
                    displayName: entry.player.displayName,
                    wins: entry.score,
                    style: style,
                    highestRound: highestRound,
                    isLocalPlayer: entry.player.gamePlayerID == localPlayerID
                )
            }
            return .success(rows)
        } catch {
            print("GameCenterManager: leaderboard load failed: \(error.localizedDescription)")
            if let gameKitError = error as? GKError {
                if gameKitError.code == .notAuthenticated {
                    isAuthenticated = false
                    return .failure(.notAuthenticated)
                }
                if gameKitError.code == .gameUnrecognized { return .failure(.notConfigured) }
            }
            return .failure(.networkOrLoadFailed)
        }
    }

    /// Packs the preferred style and highest round reached into GameKit's single `context: Int` field so
    /// both can be shown per leaderboard row without a server: `styleCode` (0 = none, else style index + 1)
    /// occupies the high digits, `highestRound` the low digits. A million-sized multiplier leaves effectively
    /// unlimited headroom for the round number.
    private static let contextRoundMultiplier = 1_000_000

    private static func contextValue(for style: FightStyle?, highestRound: Int) -> Int {
        let styleCode = style.flatMap { FightStyle.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        return styleCode * contextRoundMultiplier + max(0, highestRound)
    }

    private static func decode(context: Int) -> (style: FightStyle?, highestRound: Int) {
        guard context >= 0 else { return (nil, 0) }
        let styleCode = context / contextRoundMultiplier
        let highestRound = context % contextRoundMultiplier
        let index = styleCode - 1
        let style = (index >= 0 && index < FightStyle.allCases.count) ? FightStyle.allCases[index] : nil
        return (style, highestRound)
    }

    private func present(_ viewController: UIViewController) {
        guard viewController.presentingViewController == nil, !viewController.isBeingPresented else { return }
        guard
            let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        guard !top.isBeingPresented, !top.isBeingDismissed, top.viewIfLoaded?.window != nil else { return }
        top.present(viewController, animated: true)
    }
}
