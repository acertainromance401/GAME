import SwiftUI

/// Full-screen modal overlay showing the optional Game Center "total wins" leaderboard. Styled to match
/// the other overlays (`WaitingRoomView`, `SettingsMenuView`): a `glowPanel` card over the same dark
/// backdrop. Entirely optional/best-effort -- if the player isn't signed into Game Center, or the
/// leaderboard hasn't been configured in App Store Connect yet, this shows a friendly prompt/empty-state
/// instead of an error, and the core offline game is completely unaffected either way.
struct LeaderboardView: View {
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var gameCenter = GameCenterManager.shared
    let onClose: () -> Void

    @State private var rows: [GameCenterManager.Row] = []
    @State private var loadError: GameCenterManager.LoadError?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { onClose() }

                VStack(spacing: 16) {
                    HStack {
                        Text(loc.t(.leaderboardTitle))
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Button(loc.t(.close), action: onClose)
                            .buttonStyle(ModalButtonStyle(accent: .white.opacity(0.26)))
                    }

                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(22)
                // Fixed 420pt height overflowed past the top/bottom of the screen on landscape iPhones
                // (short-axis height is often well under 420pt once safe-area insets are subtracted), so
                // the panel is now clamped to whatever vertical room is actually available.
                .frame(width: 340, height: max(260, min(420, proxy.size.height - 24)))
                .glowPanel(accent: Color(red: 1.0, green: 0.78, blue: 0.12))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task { await load() }
        .onChange(of: gameCenter.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated else { return }
            Task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !gameCenter.isAuthenticated {
            signInPrompt
        } else if isLoading {
            ProgressView().tint(.white)
        } else if let loadError {
            Text(loadError == .notConfigured ? loc.t(.leaderboardEmptyState) : loc.t(.leaderboardLoadError))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.67, green: 0.76, blue: 0.88))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        } else if rows.isEmpty {
            Text(loc.t(.leaderboardEmptyState))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.67, green: 0.76, blue: 0.88))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
            }
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.12))
            Text(loc.t(.leaderboardSignInPrompt))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.67, green: 0.76, blue: 0.88))
                .multilineTextAlignment(.center)
            Button(loc.t(.leaderboardSignInButton)) {
                gameCenter.authenticate()
            }
            .buttonStyle(ModalButtonStyle(accent: Color(red: 1.0, green: 0.78, blue: 0.12)))
        }
        .padding(.horizontal, 12)
    }

    private func rowView(_ row: GameCenterManager.Row) -> some View {
        HStack(spacing: 10) {
            Text("#\(row.rank)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.12))
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.isLocalPlayer ? "\(row.displayName) (\(loc.t(.leaderboardYouLabel)))" : row.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let style = row.style {
                        Text(style.label(for: loc.language))
                    }
                    if row.highestRound > 0 {
                        Text("· ROUND \(row.highestRound)")
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.67, green: 0.76, blue: 0.88))
            }

            Spacer(minLength: 4)

            Text("\(row.wins) \(loc.t(.leaderboardWinsLabel))")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .selectableChip(isSelected: row.isLocalPlayer, accent: Color(red: 1.0, green: 0.78, blue: 0.12))
    }

    private func load() async {
        guard gameCenter.isAuthenticated else { return }
        isLoading = true
        loadError = nil
        switch await gameCenter.loadTopEntries() {
        case .success(let loaded):
            rows = loaded
        case .failure(let error):
            loadError = error
        }
        isLoading = false
    }
}
