import GameKit
import UIKit

/// Wraps all Apple Game Center (GameKit) integration behind one small surface so the rest of the app never
/// touches GameKit types directly. This is deliberately an OPTIONAL, best-effort layer: the game itself is a
/// fully offline, no-wifi-required local experience (per design), and every method here silently no-ops on
/// any failure (not signed into Game Center, no network, leaderboard ID not yet created in App Store
/// Connect, etc.) instead of surfacing an error to the player.
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

    private override init() {}

    /// Registers GameKit's authentication handler. Safe to call multiple times (e.g. once at app launch) --
    /// GameKit only ever presents its sign-in sheet if the player isn't already signed in and hasn't
    /// previously dismissed it, and never blocks or interrupts local (offline) gameplay.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    self.present(viewController)
                    return
                }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                if let error {
                    // Best-effort feature -- log only, never surface to the player.
                    print("GameCenterManager: authentication error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Submits the player's cumulative win count, tagging the entry's `context` with an integer encoding
    /// both their most-used fighting style and their highest round reached (the round number is this game's
    /// stand-in for "AI difficulty" -- a higher round means the rival AI has learned more) so a custom
    /// leaderboard UI can show both next to each rank without needing any server of our own.
    func submit(totalWins: Int, preferredStyle: FightStyle?, highestRound: Int) {
        guard isAuthenticated else { return }
        let context = Self.contextValue(for: preferredStyle, highestRound: highestRound)
        Task {
            do {
                try await GKLeaderboard.submitScore(
                    totalWins,
                    context: context,
                    player: GKLocalPlayer.local,
                    leaderboardIDs: [Self.totalWinsLeaderboardID]
                )
            } catch {
                print("GameCenterManager: score submission failed: \(error.localizedDescription)")
            }
        }
    }

    /// Loads the top global entries for the total-wins leaderboard, decoding each entry's preferred style
    /// back out of its `context` value.
    func loadTopEntries(count: Int = 25) async -> Result<[Row], LoadError> {
        guard isAuthenticated else { return .failure(.notAuthenticated) }
        do {
            let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [Self.totalWinsLeaderboardID])
            guard let leaderboard = leaderboards.first else { return .failure(.notConfigured) }
            let localPlayerID = GKLocalPlayer.local.gamePlayerID
            let (_, entries, _) = try await leaderboard.loadEntries(
                for: .global,
                timeScope: .allTime,
                range: NSRange(location: 1, length: max(1, count))
            )
            let rows = entries.map { entry in
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
        guard
            let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(viewController, animated: true)
    }
}
