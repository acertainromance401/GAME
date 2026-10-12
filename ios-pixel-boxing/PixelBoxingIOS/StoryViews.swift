import SwiftUI

struct StorySelectionView: View {
    @ObservedObject var store: StoryProgressStore
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var purchases = StoryPurchaseStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedOpponent = StoryOpponent.pressure
    @State private var preparingOpponent: StoryOpponent?
    @State private var preparingRematch = false
    @State private var showsStoryPurchase = false
    let onClose: () -> Void
    let onChallenge: (StoryOpponent) -> Void
    let onNewChallenge: (StoryOpponent) -> Void
    let onRematch: (StoryOpponent) -> Void
    var onReplayIntroduction: ((StoryOpponent) -> Void)? = nil
    var onReplayRivalScene: ((StoryOpponent) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                RivalScreenHeader(kicker: "RIVAL", title: loc.story(.title), closeTitle: loc.t(.exitButton),
                    closeID: "storyBack", onClose: onClose)
                HStack(spacing: 16) {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(StoryOpponent.allCases) { opponent in opponentRow(opponent) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: min(290, max(180, proxy.size.width * 0.35)))
                    ZStack(alignment: .bottomLeading) {
                        if selectedOpponent.isAvailable || selectedOpponent == .rival {
                            RivalPortraitView(isActive: scenePhase == .active && preparingOpponent == nil, storyOpponent: selectedOpponent)
                                .id(selectedOpponent)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "figure.boxing")
                                .font(.system(size: 72, weight: .light))
                                .foregroundStyle(MainMenuPalette.rule)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(selectedOpponent.title(for: loc.language))
                                .font(.system(size: 28, weight: .black)).fontWidth(.condensed)
                                .lineLimit(1).minimumScaleFactor(0.65)
                            Text("\(selectedOpponent.maximumRounds) \(loc.story(.rounds)) / 60s")
                                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                            if selectedOpponent == .pressure {
                                Text(loc.story(.firstBout)).font(.system(size: 11, weight: .medium))
                            }
                        }
                        .foregroundStyle(MainMenuPalette.paper)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MainMenuPalette.background.opacity(0.86))
                    }
                    .clipped()
                }
                .frame(maxHeight: .infinity)
                HStack {
                    Text("\(store.progress.clearedOpponents.filter { $0 != .rival }.count) / 4")
                        .font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(MainMenuPalette.secondary)
                    Spacer()
                          if selectedOpponent.isAvailable,
                              store.progress.canReplayIntroduction(selectedOpponent),
                              StoryIntroClip.clip(for: selectedOpponent) != nil, onReplayIntroduction != nil {
                        Button { onReplayIntroduction?(selectedOpponent) } label: {
                            Image(systemName: "play.rectangle")
                                .frame(width: 24, height: 20)
                        }
                        .buttonStyle(RivalMenuButtonStyle())
                        .accessibilityLabel(loc.story(.replayIntroduction))
                        .help(loc.story(.replayIntroduction))
                        .accessibilityIdentifier("storyReplayIntroduction")
                    }
                    if store.progress.canReplayRivalScene(selectedOpponent),
                       StoryIntroClip.rivalScene(for: selectedOpponent) != nil, onReplayRivalScene != nil {
                        Button { onReplayRivalScene?(selectedOpponent) } label: {
                            Image(systemName: "film")
                                .frame(width: 24, height: 20)
                        }
                        .buttonStyle(RivalMenuButtonStyle())
                        .accessibilityLabel(loc.story(.replayRivalScene))
                        .help(loc.story(.replayRivalScene))
                        .accessibilityIdentifier("storyReplayRivalScene")
                    }
                    if canResume {
                        Button { onChallenge(selectedOpponent) } label: {
                            Label(loc.story(.resume), systemImage: "play.fill")
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .buttonStyle(RivalMenuButtonStyle())
                        .accessibilityIdentifier("storyResume")
                    }
                    Button {
                        if purchases.hasStoryAccess {
                            preparingRematch = isRematch
                            preparingOpponent = selectedOpponent
                        } else {
                            showsStoryPurchase = true
                        }
                    } label: {
                        Label(actionTitle, systemImage: canChallenge ? "arrow.right" : "lock.fill")
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    .buttonStyle(RivalMenuButtonStyle(primary: true))
                    .disabled(purchases.hasStoryAccess && !canChallenge)
                    .opacity(canChallenge || !purchases.hasStoryAccess ? 1 : 0.45)
                    .accessibilityIdentifier("storyChallenge")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(MainMenuPalette.background)
            .allowsHitTesting(preparingOpponent == nil && !showsStoryPurchase)
            .accessibilityHidden(preparingOpponent != nil || showsStoryPurchase)
        }
        .overlay {
            if showsStoryPurchase {
                StoryPurchaseView(store: purchases, onClose: { showsStoryPurchase = false },
                    onUnlocked: { showsStoryPurchase = false })
            } else if let opponent = preparingOpponent {
                WaitingRoomView(controller: controller, storyOpponent: opponent, onChallenge: {
                    let rematch = preparingRematch
                    preparingOpponent = nil
                    preparingRematch = false
                    if rematch {
                        onRematch(opponent)
                    } else {
                        onNewChallenge(opponent)
                    }
                }, onClose: {
                    preparingOpponent = nil
                    preparingRematch = false
                })
            }
        }
        .onAppear {
            selectedOpponent = store.progress.activeBout?.bout.opponent
                ?? StoryOpponent.allCases.first(where: {
                    store.progress.isUnlocked($0) && !store.progress.clearedOpponents.contains($0)
                }) ?? .pressure
        }
    }

    private var canChallenge: Bool {
        purchases.hasStoryAccess && selectedOpponent.isAvailable && store.progress.isUnlocked(selectedOpponent)
    }

    private var canResume: Bool {
        canChallenge && store.progress.activeBout?.bout.opponent == selectedOpponent
    }

    private var isRematch: Bool {
        !canResume && store.progress.clearedOpponents.contains(selectedOpponent)
    }

    private var actionTitle: String {
        if !purchases.hasStoryAccess { return loc.purchase(.purchaseBenefits) }
        if !store.progress.isUnlocked(selectedOpponent) { return loc.story(.locked) }
        if !selectedOpponent.isAvailable { return loc.story(.unavailable) }
        if canResume { return loc.story(.newChallenge) }
        return loc.story(isRematch ? .replay : .challenge)
    }

    private func opponentRow(_ opponent: StoryOpponent) -> some View {
        let unlocked = store.progress.isUnlocked(opponent)
        let cleared = store.progress.clearedOpponents.contains(opponent)
        let index = (StoryOpponent.allCases.firstIndex(of: opponent) ?? 0) + 1
        return Button { selectedOpponent = opponent } label: {
            HStack(spacing: 10) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(MainMenuPalette.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(opponent.title(for: loc.language)).font(.system(size: 16, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(cleared ? loc.story(.cleared) : (unlocked ? "\(opponent.maximumRounds) R" : loc.story(.locked)))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(MainMenuPalette.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: cleared ? "checkmark.circle.fill" : (unlocked ? "chevron.right" : "lock.fill"))
                    .font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(MainMenuPalette.paper)
            .padding(.horizontal, 10).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
            .background(selectedOpponent == opponent ? MainMenuPalette.paper.opacity(0.09) : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(MainMenuPalette.rule).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("storyOpponent_\(opponent.rawValue)")
        .accessibilityAddTraits(selectedOpponent == opponent ? .isSelected : [])
    }
}

struct StoryIntroductionOverlay: View {
    let introduction: StoryIntroduction
    let onSkip: () -> Void
    let onExit: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack {
                    Button(action: onExit) { Image(systemName: "chevron.left") }
                        .accessibilityLabel(loc.story(.opponents))
                        .accessibilityIdentifier("storyIntroductionExit")
                        .frame(width: 44, height: 38)
                    Spacer()
                    Button(action: onSkip) {
                        Label(loc.story(.skip), systemImage: "forward.end.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                    }
                    .accessibilityIdentifier("storyIntroductionSkip")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, max(12, max(proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing)))
                .padding(.top, proxy.safeAreaInsets.top)
                .background(.black.opacity(0.84))
                Spacer()
                VStack(spacing: 5) {
                    if introduction.isCoachBriefing {
                        if introduction.coachElapsed >= 0.35 && introduction.elapsed < introduction.duration - 0.9 {
                            Text("\(loc.story(.coach)): \(loc.story(introduction.opponent.coachAdviceText(at: introduction.coachAdviceIndex)))")
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(3).minimumScaleFactor(0.85)
                                .multilineTextAlignment(.center)
                        }
                    } else if !introduction.short && introduction.elapsed < 2.0 {
                        Text(loc.story(introduction.opponent.introductionVenueText))
                            .font(.system(size: 16, weight: .bold))
                        Text(introduction.opponent == .pressure ? loc.story(.firstBout)
                            : "\(introduction.opponent.maximumRounds) \(loc.story(.rounds))")
                            .font(.system(size: 11, weight: .medium))
                    } else if introduction.elapsed >= introduction.dialogueStartTime || introduction.short {
                        Text("\(introduction.opponent.title(for: loc.language)): \(loc.story(introduction.opponent.introductionLineText))")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(introduction.opponent == .rival ? 3 : 2).minimumScaleFactor(0.85)
                            .multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 520, minHeight: 48)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .padding(.bottom, max(8, proxy.safeAreaInsets.bottom))
                .background(.black.opacity(0.84))
                .allowsHitTesting(false)
            }
            .background(Color.black.opacity(introduction.transitionOpacity).ignoresSafeArea().allowsHitTesting(false))
        }
    }
}

struct StoryRivalSceneOverlay: View {
    let scene: StoryRivalScene
    let onSkip: () -> Void
    @ObservedObject private var loc = LocalizationManager.shared

    private var caption: String {
        if scene.chapter == .rival {
            if scene.elapsed >= ChampionshipEndingTiming.coachCongratulations + 0.45,
               scene.elapsed < ChampionshipEndingTiming.gymCut - 0.25 {
                return "\(loc.story(.coach)): \(loc.story(.championshipCoachCongratulations))"
            }
            if scene.elapsed >= ChampionshipEndingTiming.beltAward,
               scene.elapsed < ChampionshipEndingTiming.ceremonyStart + 1.2 {
                return loc.story(.championshipReward)
            }
        }
        return scene.elapsed >= scene.duration - 2.0
            ? "RIVAL: \(loc.story(scene.chapter.rivalSceneLineText))" : ""
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onSkip) {
                        Label(loc.story(.skip), systemImage: "forward.end.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("storyRivalSceneSkip")
                }
                .padding(.horizontal, max(12, max(proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing)))
                .padding(.top, proxy.safeAreaInsets.top)
                .background(.black.opacity(0.84))
                Spacer()
                Text(caption)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(3).minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520, minHeight: 48)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, max(8, proxy.safeAreaInsets.bottom))
                    .background(.black.opacity(0.84))
                    .allowsHitTesting(false)
            }
            .foregroundStyle(.white)
        }
    }
}

struct StorySceneReplayView: View {
    @ObservedObject var controller: GameController
    @Environment(\.scenePhase) private var scenePhase
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Arena3DView(controller: controller).ignoresSafeArea()
            if let scene = controller.storyRivalScene {
                StoryRivalSceneOverlay(scene: scene, onSkip: controller.finishStoryRivalScene)
            } else if let introduction = controller.storyIntroduction {
                StoryIntroductionOverlay(introduction: introduction,
                    onSkip: controller.finishStoryIntroduction, onExit: onClose)
            }
        }
        .onChange(of: controller.isPlayingStoryScene) { wasPlaying, isPlaying in
            if wasPlaying && !isPlaying { onClose() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.resumeStoryIntroduction() }
        }
    }
}

struct StoryRoundClock: View {
    let bout: StoryBoutState
    let remainingTime: Double
    @ObservedObject var presentation: CombatPresentation
    @ObservedObject private var loc = LocalizationManager.shared

    private var clockText: String {
        if bout.phase == .counting { return "\(bout.displayedCount)" }
        if bout.phase == .corner {
            return String(format: "%02d", Int(ceil(max(0, bout.rules.cornerSeconds - bout.cornerElapsed))))
        }
        if bout.finish == .technicalKnockout,
           presentation.knockoutClockPhase == .visible || presentation.knockoutClockPhase == .finished {
            return "T.K.O."
        }
        return String(format: "%02d", Int(ceil(max(0, remainingTime))))
    }

    private var clockCaption: String {
        if bout.phase == .counting {
            return "\(bout.countingSide == .player ? "ME" : bout.opponent.title(for: loc.language)) \(loc.story(.knockdown))"
        }
        if bout.phase == .corner { return loc.story(.corner) }
        return loc.story(bout.advantage > 0 ? .ahead : (bout.advantage < 0 ? .behind : .even))
    }

    private var clockAccent: Color {
        bout.phase != .fighting || remainingTime <= 10
            ? Color(red: 1, green: 0.78, blue: 0.12) : .white
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("ROUND \(bout.round) / \(bout.opponent.maximumRounds)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.12))
            Group {
                if bout.phase == .corner, bout.canStartNextRound {
                    Image(systemName: "checkmark")
                        .accessibilityLabel(loc.story(.nextRound))
                } else {
                    Text(clockText).monospacedDigit()
                }
            }
            .font(.system(size: 24, weight: .black)).fontWidth(.condensed)
            .foregroundStyle(clockAccent)
            .frame(width: 126, height: 30)
            .accessibilityIdentifier(bout.phase == .counting ? "storyDownCount" : "storyClockValue")
            Text(clockCaption)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(clockAccent)
                .frame(width: 126, height: 14)
                .allowsHitTesting(false)
            Text("\(loc.story(.downs))  \(bout.stats.playerDowns) : \(bout.stats.opponentDowns)")
                .font(.system(size: 8, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .frame(width: 126)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("storyRoundClock")
    }
}

struct StoryBoutOverlay: View {
    let bout: StoryBoutState
    let showsResult: Bool
    let onContinue: () -> Void
    let onRetry: () -> Void
    let onExit: () -> Void
    var onRivalScene: (() -> Void)? = nil
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        Group {
            switch bout.phase {
            case .counting:
                EmptyView()
            case .corner:
                VStack(spacing: 10) {
                    Text(loc.story(.corner)).font(.system(size: 26, weight: .black))
                    Text("ROUND \(bout.round) / \(bout.opponent.maximumRounds)")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    Text(loc.story(bout.advantage > 0 ? .ahead : (bout.advantage < 0 ? .behind : .even)))
                        .font(.system(size: 13, weight: .medium))
                    HStack(spacing: 8) {
                        ProgressView(value: bout.cornerElapsed, total: max(0.001, bout.rules.cornerSeconds))
                            .tint(MainMenuPalette.paper)
                        Group {
                            if bout.canStartNextRound {
                                Image(systemName: "checkmark")
                                    .accessibilityLabel(loc.story(.nextRound))
                            } else {
                                Text("\(Int(ceil(max(0, bout.rules.cornerSeconds - bout.cornerElapsed))))s")
                                    .monospacedDigit()
                            }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(bout.canStartNextRound ? MainMenuPalette.paper : MainMenuPalette.secondary)
                        .frame(width: 26, alignment: .trailing)
                    }
                    .frame(width: 168)
                    Button(action: onContinue) {
                        Label(loc.story(.nextRound), systemImage: "arrow.right")
                    }
                    .buttonStyle(RivalMenuButtonStyle(primary: true))
                    .disabled(!bout.canStartNextRound)
                    .opacity(bout.canStartNextRound ? 1 : 0.45)
                    .animation(.easeOut(duration: UIStyleKit.microDuration), value: bout.canStartNextRound)
                    .accessibilityIdentifier("storyNextRound")
                }
                .padding(24)
                .background(MainMenuPalette.background, in: RoundedRectangle(cornerRadius: 4))
            case .finished:
                if showsResult { result }
            case .fighting:
                EmptyView()
            }
        }
        .foregroundStyle(MainMenuPalette.paper)
    }

    private var result: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.story(bout.verdict == .win ? .win : (bout.verdict == .loss ? .loss : .draw)))
                        .font(.system(size: 26, weight: .black)).fontWidth(.condensed)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(bout.finish == .technicalKnockout ? "T.K.O." : loc.story(.decision))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MainMenuPalette.secondary)
                }
                Spacer(minLength: 12)
                Text("\(bout.playerPoints) : \(bout.opponentPoints)")
                    .font(.system(size: 24, weight: .bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            if bout.verdict == .win, bout.opponent.hasAppearance {
                Text(bout.opponent == .rival ? loc.story(.championshipReward)
                    : "\(bout.opponent.title(for: loc.language)) · \(loc.story(.appearanceUnlocked))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MainMenuPalette.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("R").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MainMenuPalette.secondary).frame(height: 14)
                    Text("ME").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.82, blue: 1)).frame(height: 18)
                    Text(bout.opponent.title(for: loc.language))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .foregroundStyle(Color(red: 1, green: 0.25, blue: 0.40)).frame(height: 18)
                }
                .frame(width: 72, alignment: .leading)
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(bout.cards) { card in
                            VStack(spacing: 4) {
                                Text("\(card.round)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(MainMenuPalette.secondary).frame(height: 14)
                                Text("\(card.playerPoints)")
                                    .foregroundStyle(Color(red: 0.18, green: 0.82, blue: 1)).frame(height: 18)
                                Text("\(card.opponentPoints)")
                                    .foregroundStyle(Color(red: 1, green: 0.25, blue: 0.40)).frame(height: 18)
                            }
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                            .frame(width: 32)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(MainMenuPalette.rule).frame(width: 1)
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
            .frame(height: 64)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    resultStoryAction
                    resultNavigationActions
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(spacing: 8) {
                    resultStoryAction
                    resultNavigationActions
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: 520)
        .background(MainMenuPalette.background, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(MainMenuPalette.rule, lineWidth: 1))
        .accessibilityIdentifier("storyBoutResult")
    }

    @ViewBuilder private var resultStoryAction: some View {
        if let onRivalScene {
            Button(action: onRivalScene) {
                Label(loc.story(.continueStory), systemImage: "arrow.right")
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .buttonStyle(RivalMenuButtonStyle(primary: true))
            .accessibilityIdentifier("storyContinueToRivalScene")
        }
    }

    private var resultNavigationActions: some View {
        HStack(spacing: 8) {
            Button(action: onExit) {
                Label(loc.story(.opponents), systemImage: "list.bullet")
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .buttonStyle(RivalMenuButtonStyle())
            Button(action: onRetry) {
                Label(loc.story(bout.verdict == .win ? .replay : .retry), systemImage: "arrow.clockwise")
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .buttonStyle(RivalMenuButtonStyle(primary: onRivalScene == nil))
            .accessibilityIdentifier("storyRetry")
        }
    }
}