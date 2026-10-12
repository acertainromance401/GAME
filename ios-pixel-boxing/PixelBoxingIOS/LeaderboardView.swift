/*
 LeaderboardView.swift

 파일 설명:
 - 리더보드 및 경기 기록을 표시하는 전체 화면 뷰입니다. Game Center와 연동된 경우 원격 순위를, 아니면
     로컬 기록을 보여줍니다.

 사용 영향 및 주의사항:
 - Game Center 연동 유무에 따른 데이터 소스 차이를 처리해야 합니다.
 - UI 변경은 사용자의 점수 조회 흐름에 영향을 미칩니다.
*/
import SwiftUI

/// Full-screen sports record sheet. Game Center remains optional; no invented rows or ratings.
struct LeaderboardView: View {
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var gameCenter = GameCenterManager.shared
    @Environment(\.scenePhase) private var scenePhase
    let onClose: () -> Void

    @State private var rows: [GameCenterManager.Row] = []
    @State private var loadError: GameCenterManager.LoadError?
    @State private var isLoading = false
    @State private var loadRequestID = UUID()
    @ScaledMetric(relativeTo: .subheadline) private var labelSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 12

    var body: some View {
        ZStack {
            MainMenuPalette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                RivalScreenHeader(kicker: loc.t(.leaderboardKicker), title: loc.t(.leaderboardTitle),
                                  closeTitle: loc.t(.close), closeID: "leaderboardClose", onClose: onClose)
                HStack(spacing: 12) {
                    Text(loc.t(.leaderboardSubtitle))
                        .font(.system(size: detailSize, weight: .medium))
                        .foregroundStyle(MainMenuPalette.secondary)
                    Spacer(minLength: 8)
                    if gameCenter.isAuthenticated {
                        Button { Task { await load() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(RivalMenuButtonStyle())
                        .disabled(isLoading)
                        .accessibilityLabel(loc.t(.leaderboardRefreshButton))
                        .accessibilityIdentifier("leaderboardRefresh")
                        .help(loc.t(.leaderboardRefreshButton))
                    }
                }
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .task { gameCenter.authenticate() }
        .task(id: gameCenter.isAuthenticated) { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { gameCenter.resumeAuthentication() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !gameCenter.isAuthenticated {
            signInPrompt
        } else if isLoading {
            ProgressView().tint(MainMenuPalette.paper)
        } else if let loadError {
            Text(loadError == .notConfigured ? loc.t(.leaderboardNotConfigured) : loc.t(.leaderboardLoadError))
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(MainMenuPalette.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        } else if rows.isEmpty {
            Text(loc.t(.leaderboardEmptyState))
                .font(.system(size: labelSize, weight: .medium))
                .foregroundStyle(MainMenuPalette.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text(loc.t(.leaderboardRankLabel)).frame(width: 54, alignment: .leading)
                    Text(loc.t(.leaderboardFighterLabel))
                    Spacer()
                    Text(loc.t(.menuTotalWins))
                }
                .font(.system(size: detailSize, weight: .semibold))
                .foregroundStyle(MainMenuPalette.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(rows) { row in rowView(row) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var signInPrompt: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(MainMenuPalette.secondary)
                    .accessibilityHidden(true)
                Text(loc.t(.leaderboardSignInPrompt))
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundStyle(MainMenuPalette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = gameCenter.authenticationError {
                    Text(error)
                        .font(.system(size: detailSize, weight: .medium))
                        .foregroundStyle(MainMenuPalette.rival)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { gameCenter.authenticate() } label: {
                    HStack(spacing: 8) {
                        if gameCenter.isAuthenticating {
                            ProgressView().tint(MainMenuPalette.background).frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark").frame(width: 16, height: 16)
                        }
                        Text(loc.t(.leaderboardSignInButton))
                    }
                }
                .buttonStyle(RivalMenuButtonStyle(primary: true))
                .accessibilityIdentifier("leaderboardSignIn")
            }
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private func rowView(_ row: GameCenterManager.Row) -> some View {
        HStack(spacing: 10) {
            Text("#\(row.rank)")
                .font(.system(size: 23, weight: .bold))
                .fontWidth(.condensed)
                .monospacedDigit()
                .foregroundStyle(MainMenuPalette.paper)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.isLocalPlayer ? "\(row.displayName) (\(loc.t(.leaderboardYouLabel)))" : row.displayName)
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(MainMenuPalette.paper)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let style = row.style {
                        Text(style.label(for: loc.language))
                    }
                    if row.highestRound > 0 {
                        Text("· ROUND \(row.highestRound)")
                    }
                }
                .font(.system(size: detailSize, weight: .regular))
                .foregroundStyle(MainMenuPalette.secondary)
            }

            Spacer(minLength: 4)

            Text("\(row.wins) \(loc.t(.leaderboardWinsLabel))")
                .font(.system(size: labelSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(MainMenuPalette.paper)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(row.isLocalPlayer ? MainMenuPalette.surface : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(MainMenuPalette.rule).frame(height: 1) }
    }

    @MainActor private func load() async {
        let requestID = UUID()
        loadRequestID = requestID
        guard gameCenter.isAuthenticated else {
            rows = []
            loadError = nil
            isLoading = false
            return
        }
        isLoading = true
        loadError = nil
        defer {
            if loadRequestID == requestID { isLoading = false }
        }
        controller.synchronizeGameCenterScore()
        let result = await gameCenter.loadTopEntries()
        guard !Task.isCancelled, loadRequestID == requestID else { return }
        switch result {
        case .success(let loaded):
            rows = loaded
        case .failure(let error):
            loadError = error
        }
    }
}
