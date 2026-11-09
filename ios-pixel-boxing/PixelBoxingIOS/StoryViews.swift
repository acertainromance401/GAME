import SwiftUI

struct StorySelectionView: View {
    @ObservedObject var store: StoryProgressStore
    @ObservedObject var controller: GameController
    @ObservedObject private var loc = LocalizationManager.shared
    @ObservedObject private var purchases = StoryPurchaseStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicType
    @RivalReducedMotion private var reducedMotion
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 24
    @ScaledMetric(relativeTo: .subheadline) private var rowSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 12
    @State private var selectedOpponent = StoryOpponent.basic
    @State private var preparingOpponent: StoryOpponent?
    @State private var preparingRematch = false
    @State private var showsStoryPurchase = false
    @State private var showsLineup = true
    let onClose: () -> Void
    let onChallenge: (StoryOpponent) -> Void
    let onNewChallenge: (StoryOpponent) -> Void
    let onRematch: (StoryOpponent) -> Void
    var onReplayIntroduction: ((StoryOpponent) -> Void)? = nil
    var onReplayRivalScene: ((StoryOpponent) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MainMenuPalette.background.ignoresSafeArea()
                if !dynamicType.isAccessibilitySize { presentationArtwork(size: proxy.size) }
                VStack(spacing: 8) {
                    selectionHeader
                    if dynamicType.isAccessibilitySize {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                selectedDetails
                                ForEach(StoryOpponent.allCases) { opponentRow($0) }
                            }
                        }
                        .accessibilityIdentifier("storyOpponentList")
                    } else {
                        HStack {
                            ScrollView { selectedDetails }
                                .scrollIndicators(.visible)
                                .accessibilityIdentifier("storyOpponentDetails")
                                .frame(width: proxy.size.width * (showsLineup ? 0.30 : 0.38))
                            Spacer(minLength: 0)
                        }
                        .frame(maxHeight: .infinity)
                        opponentRoster
                    }
                    storyActions
                }
                .foregroundStyle(MainMenuPalette.paper)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .allowsHitTesting(preparingOpponent == nil && !showsStoryPurchase)
            .accessibilityHidden(preparingOpponent != nil || showsStoryPurchase)
        }
        .overlay {
            if showsStoryPurchase {
                StoryPurchaseView(store: purchases, onClose: { showsStoryPurchase = false },
                    onUnlocked: { showsStoryPurchase = false })
                    .rivalPanelTransition()
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
                .rivalPanelTransition()
            }
        }
        .animation(.easeOut(duration: reducedMotion ? UIStyleKit.microDuration : UIStyleKit.fastDuration),
                   value: showsStoryPurchase)
        .animation(.easeOut(duration: reducedMotion ? UIStyleKit.microDuration : UIStyleKit.fastDuration),
                   value: preparingOpponent)
        .onAppear {
            selectedOpponent = purchases.hasStoryAccess ? store.progress.nextOpponent : .basic
        }
    }

    private var selectionHeader: some View {
        HStack(spacing: 12) {
            RivalWordmark(width: 56)
                .accessibilityIdentifier("storyWordmark")
            Text(loc.story(.opponents))
                .font(.system(size: titleSize, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            replayControls
            if !dynamicType.isAccessibilitySize {
                Button { showsLineup = true } label: {
                    Image(systemName: "person.3")
                }
                .buttonStyle(RivalMenuButtonStyle())
                .accessibilityLabel(loc.story(.showLineup))
                .accessibilityIdentifier("storyShowLineup")
            }
            Button(action: onClose) { Label(loc.t(.exitButton), systemImage: "arrow.left") }
                .buttonStyle(RivalMenuButtonStyle())
                .accessibilityIdentifier("storyBack")
        }
        .frame(minHeight: 44)
    }

    private func presentationArtwork(size: CGSize) -> some View {
        ZStack {
            Image("StoryArena")
                .resizable().scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped().opacity(0.26)
            Image(showsLineup ? "StoryLineup" : selectedOpponent.storyPortraitAssetName)
                .resizable().scaledToFit()
                .frame(width: size.width * (showsLineup ? 0.68 : 0.50), height: max(0, size.height - (showsLineup ? 170 : 180)))
                .position(x: size.width * (showsLineup ? 0.66 : 0.73), y: size.height * (showsLineup ? 0.34 : 0.38))
                .id(showsLineup ? "lineup" : selectedOpponent.rawValue)
                .transition(.opacity)
        }
        .animation(reducedMotion ? nil : .easeOut(duration: UIStyleKit.fastDuration), value: selectedOpponent)
        .animation(reducedMotion ? nil : .easeOut(duration: UIStyleKit.fastDuration), value: showsLineup)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var selectedDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsLineup && !dynamicType.isAccessibilitySize {
                Text(loc.story(.lineupTitle))
                    .font(.system(size: titleSize, weight: .semibold))
                Text(loc.story(.lineupDetail))
                    .font(.system(size: rowSize))
                    .foregroundStyle(MainMenuPalette.secondary)
            }
            Text(selectedOpponent.title(for: loc.language))
                .font(.system(size: rowSize, weight: .semibold))
                .accessibilityIdentifier("storySelectedOpponent")
            Text("\(selectedOpponent.maximumRounds) \(loc.story(.rounds)) / 60s")
                .font(.system(size: detailSize, weight: .medium)).monospacedDigit()
                .foregroundStyle(MainMenuPalette.secondary)
            Text(purchases.hasStoryAccess
                ? "\(store.progress.clearedOpponents.filter { $0.isAvailable && $0 != .rival }.count) / \(StoryOpponent.allCases.filter { $0.isAvailable && $0 != .rival }.count)"
                : loc.purchase(.previewBouts))
                .font(.system(size: detailSize, weight: .medium)).monospacedDigit()
                .foregroundStyle(MainMenuPalette.secondary)
            if !showsLineup || dynamicType.isAccessibilitySize { opponentAdvice.padding(.top, 4) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var opponentRoster: some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(StoryOpponent.allCases) { opponent in
                        opponentRow(opponent).frame(width: 172).id(opponent)
                    }
                }
            }
            .scrollIndicators(.visible)
            .frame(height: dynamicType > .large ? 90 : 76)
            .background(MainMenuPalette.background.opacity(0.97))
            .accessibilityIdentifier("storyOpponentList")
            .onAppear { scroll.scrollTo(selectedOpponent, anchor: .center) }
            .onChange(of: selectedOpponent) { _, opponent in
                withAnimation(reducedMotion ? nil : .easeOut(duration: UIStyleKit.fastDuration)) {
                    scroll.scrollTo(opponent, anchor: .center)
                }
            }
        }
    }

    private var opponentAdvice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc.story(.coachAdvice))
                .font(.system(size: detailSize, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(loc.story(selectedOpponent == .basic ? .basicPreviewProfile : selectedOpponent.coachAdviceText(at: 0)))
                .foregroundStyle(MainMenuPalette.secondary)
                .accessibilityIdentifier("storyOpponentAdvice")
            Text("\(loc.story(.victoryReward)): \(previewVictoryReward)")
                .foregroundStyle(MainMenuPalette.story)
            if !selectedOpponent.isAvailable {
                Text(loc.story(.unavailable))
                    .foregroundStyle(MainMenuPalette.secondary)
            } else if !purchases.hasStoryAccess {
                Text(loc.purchase(.previewAccessRequirement))
                    .foregroundStyle(MainMenuPalette.secondary)
            } else if !store.progress.isUnlocked(selectedOpponent) {
                Text(loc.story(.progressRequired))
                    .foregroundStyle(MainMenuPalette.secondary)
            }
        }
        .font(.system(size: detailSize, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var replayControls: some View {
        if purchases.hasStoryAccess || StoryProgress.temporarilyUnlockCutscenes,
           selectedOpponent.isAvailable,
           store.progress.canReplayIntroduction(selectedOpponent),
           StoryIntroClip.clip(for: selectedOpponent) != nil, onReplayIntroduction != nil {
            Button { onReplayIntroduction?(selectedOpponent) } label: {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(RivalMenuButtonStyle())
            .accessibilityLabel(loc.story(.replayIntroduction))
            .help(loc.story(.replayIntroduction))
            .accessibilityIdentifier("storyReplayIntroduction")
        }
        if purchases.hasStoryAccess || StoryProgress.temporarilyUnlockCutscenes,
           store.progress.canReplayRivalScene(selectedOpponent),
           StoryIntroClip.rivalScene(for: selectedOpponent) != nil, onReplayRivalScene != nil {
            Button { onReplayRivalScene?(selectedOpponent) } label: {
                Image(systemName: "film")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(RivalMenuButtonStyle())
            .accessibilityLabel(loc.story(.replayRivalScene))
            .help(loc.story(.replayRivalScene))
            .accessibilityIdentifier("storyReplayRivalScene")
        }
    }

    private var storyActions: some View {
        HStack(spacing: 8) {
            if canResume {
                Button { onChallenge(selectedOpponent) } label: {
                    Label(loc.story(.resume), systemImage: "play.fill")
                        .lineLimit(2)
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
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(RivalMenuButtonStyle(primary: true))
            .disabled(purchases.hasStoryAccess && !canChallenge)
            .opacity(canChallenge || !purchases.hasStoryAccess ? 1 : 0.45)
            .accessibilityIdentifier("storyChallenge")
        }
    }

    private var previewVictoryReward: String {
        switch selectedOpponent {
        case .basic:
            loc.story(.nextBoutReward)
        case .southpaw:
            "\(StoryPurchaseReward.appearance(.southpaw).title(for: loc.language)) · \(loc.story(.southpawStance))"
        case .rival:
            "\(StoryPurchaseReward.appearance(.rival).title(for: loc.language)) · \(StoryPurchaseReward.championOutfit.title(for: loc.language)) · \(StoryPurchaseReward.championBelt.title(for: loc.language))"
        default:
            StoryPurchaseReward.appearance(selectedOpponent).title(for: loc.language)
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
        if !purchases.hasStoryAccess { return loc.purchase(.viewStoryAccess) }
        if !selectedOpponent.isAvailable { return loc.story(.unavailable) }
        if !store.progress.isUnlocked(selectedOpponent) { return loc.story(.locked) }
        if canResume { return loc.story(.newChallenge) }
        return loc.story(isRematch ? .replay : .prepare)
    }

    private func opponentRow(_ opponent: StoryOpponent) -> some View {
        let unlocked = purchases.hasStoryAccess && store.progress.isUnlocked(opponent)
        let cleared = store.progress.clearedOpponents.contains(opponent)
        let index = (StoryOpponent.allCases.firstIndex(of: opponent) ?? 0) + 1
        return Button {
            selectedOpponent = opponent
            showsLineup = false
        } label: {
            HStack(spacing: 10) {
                if !dynamicType.isAccessibilitySize {
                    Image(opponent.storyBustAssetName)
                        .resizable().scaledToFit()
                        .frame(width: 36, height: 48)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(opponent.title(for: loc.language)).font(.system(size: rowSize, weight: .semibold))
                        .lineLimit(dynamicType.isAccessibilitySize ? nil : 2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(!opponent.isAvailable ? loc.story(.unavailable) : "\(index) · \(opponent.maximumRounds) R"
                        + (cleared ? " · \(loc.story(.cleared))" : !unlocked ? " · \(loc.story(.locked))" : ""))
                        .font(.system(size: detailSize, weight: .medium)).foregroundStyle(MainMenuPalette.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: !opponent.isAvailable ? "clock" : cleared ? "checkmark.circle.fill" : (unlocked ? "chevron.right" : "lock.fill"))
                    .font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(MainMenuPalette.paper)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
            .rivalSelection(isSelected: selectedOpponent == opponent)
        }
        .buttonStyle(RivalPlainButtonStyle())
        .accessibilityIdentifier("storyOpponent_\(opponent.rawValue)")
        .accessibilityAddTraits(selectedOpponent == opponent ? .isSelected : [])
    }
}

extension StoryOpponent {
    var storyPortraitAssetName: String { "StoryPortrait-\(rawValue)" }
    var storyBustAssetName: String { "StoryBust-\(rawValue)" }
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
                        Text(introduction.opponent == .basic ? loc.story(.firstSparring)
                            : introduction.opponent == .pressure ? loc.story(.firstBout)
                            : "\(introduction.opponent.maximumRounds) \(loc.story(.rounds))")
                            .font(.system(size: 11, weight: .medium))
                    } else if introduction.elapsed >= introduction.dialogueStartTime || introduction.short {
                        Text("\(introduction.opponent.fighterName(for: loc.language)): \(loc.story(introduction.opponent.introductionLineText))")
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
        let line: StoryText = scene.sparringKnockout ? .basicRecoveryLine : scene.chapter.rivalSceneLineText
        return scene.elapsed >= scene.duration - 2.0 ? "RIVAL: \(loc.story(line))" : ""
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
        return CombatText.roundTime(remainingTime)
    }

    private var clockCaption: String {
        if bout.phase == .counting {
            return "\(bout.countingSide == .player ? "ME" : bout.opponent.fighterName(for: loc.language)) \(loc.story(.knockdown))"
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
            HStack(spacing: 4) {
                Text("\(loc.t(.roundLabel)) \(bout.round) / \(bout.opponent.maximumRounds)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FightNightPalette.paper.opacity(0.7))
                Spacer(minLength: 0)
                Text("\(loc.story(.downs))  \(bout.stats.playerDowns) : \(bout.stats.opponentDowns)")
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            Group {
                if bout.phase == .corner, bout.canStartNextRound {
                    Image(systemName: "checkmark")
                        .accessibilityLabel(loc.story(.nextRound))
                } else {
                    Text(clockText).monospacedDigit()
                }
            }
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(clockAccent)
            .frame(width: 126, height: 30)
            .accessibilityIdentifier(bout.phase == .counting ? "storyDownCount" : "storyClockValue")
            Text(clockCaption)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(clockAccent)
                .frame(width: 126, height: 14)
                .allowsHitTesting(false)
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
    var roundRecord: CombatSnapshot? = nil
    @ObservedObject private var loc = LocalizationManager.shared
    @ScaledMetric(relativeTo: .body) private var cornerPanelHeight: CGFloat = 340

    var body: some View {
        Group {
            switch bout.phase {
            case .counting:
                EmptyView()
            case .corner:
                corner
            case .finished:
                if showsResult { result }
            case .fighting:
                EmptyView()
            }
        }
        .foregroundStyle(PreparationPalette.ink)
    }

    private var corner: some View {
        GeometryReader { proxy in
            Color.black.opacity(0.42).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 14) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loc.story(.corner)).font(.title2.weight(.semibold))
                                Text("\(loc.t(.roundLabel)) \(bout.round) / \(bout.opponent.maximumRounds)")
                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(PreparationPalette.secondary)
                            }
                            Spacer(minLength: 12)
                            Text("\(bout.playerPoints) : \(bout.opponentPoints)")
                                .font(.title2.weight(.bold)).monospacedDigit()
                        }
                        roundDetails
                        Text(loc.story(bout.advantage > 0 ? .ahead : (bout.advantage < 0 ? .behind : .even)))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PreparationPalette.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
                HStack(spacing: 8) {
                    ProgressView(value: bout.cornerElapsed, total: max(0.001, bout.rules.cornerSeconds))
                        .tint(PreparationPalette.ink)
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
                    .frame(width: 26, alignment: .trailing)
                }
                .frame(width: 168)
                Button(action: onContinue) {
                    Text(loc.story(.nextRound))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RivalMenuButtonStyle(primary: true, onPaper: true))
                .disabled(!bout.canStartNextRound)
                .opacity(bout.canStartNextRound ? 1 : 0.45)
                .animation(.easeOut(duration: UIStyleKit.microDuration), value: bout.canStartNextRound)
                .accessibilityIdentifier("storyNextRound")
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: 420, maxHeight: min(cornerPanelHeight, proxy.size.height - 24))
            .rivalPaperSurface()
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var result: some View {
        GeometryReader { proxy in
            Color.black.opacity(0.42).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 0) {
                ScrollView {
                    resultSummary
                        .padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
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
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
            }
            .frame(maxWidth: 600, maxHeight: min(340, proxy.size.height - 24))
            .rivalPaperSurface()
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("storyBoutResult")
        }
    }

    private var resultSummary: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.story(bout.verdict == .win ? .win : (bout.verdict == .loss ? .loss : .draw)))
                        .font(.title.weight(.semibold))
                    Text(bout.finish == .technicalKnockout ? "T.K.O." : loc.story(.decision))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PreparationPalette.secondary)
                }
                Spacer(minLength: 12)
                Text("\(bout.playerPoints) : \(bout.opponentPoints)")
                    .font(.title2.weight(.bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            if let roundRecord {
                Text("\(loc.t(.roundLabel)) \(roundRecord.round)")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                roundDetails
            }
            if bout.verdict == .win, bout.opponent.hasAppearance {
                Text(bout.opponent == .rival ? loc.story(.championshipReward)
                    : bout.opponent == .southpaw ? (StoryPurchaseStore.shared.hasStoryAccess
                        ? loc.story(.southpawReward) : loc.purchase(.southpawUnlockRequirement))
                    : "\(bout.opponent.title(for: loc.language)) · \(loc.story(.appearanceUnlocked))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PreparationPalette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("R").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PreparationPalette.secondary).frame(height: 14)
                    Text(loc.t(.leaderboardYouLabel)).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PreparationPalette.player).frame(height: 18)
                    Text(bout.opponent.fighterName(for: loc.language))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .foregroundStyle(PreparationPalette.rival).frame(height: 18)
                }
                .frame(width: 72, alignment: .leading)
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(bout.cards) { card in
                            VStack(spacing: 4) {
                                Text("\(card.round)")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(PreparationPalette.secondary).frame(height: 14)
                                Text("\(card.playerPoints)")
                                    .foregroundStyle(PreparationPalette.player).frame(height: 18)
                                Text("\(card.opponentPoints)")
                                    .foregroundStyle(PreparationPalette.rival).frame(height: 18)
                            }
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                            .frame(width: 32)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(PreparationPalette.rule).frame(width: 1)
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
            .frame(height: 64)
        }
    }

    @ViewBuilder private var roundDetails: some View {
        if let roundRecord {
            VStack(alignment: .leading, spacing: 12) {
                RoundRecordTable(snapshot: roundRecord, opponentName: bout.opponent.fighterName(for: loc.language))
                if let report = roundRecord.rivalRead.cornerReport(for: loc.language) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.t(.roundStatsRivalCornerLabel)).font(.subheadline.weight(.semibold))
                        Text(report).font(.subheadline)
                            .foregroundStyle(PreparationPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder private var resultStoryAction: some View {
        if let onRivalScene {
            Button(action: onRivalScene) {
                Label(loc.story(.continueStory), systemImage: "arrow.right")
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .buttonStyle(RivalMenuButtonStyle(primary: true, onPaper: true))
            .accessibilityIdentifier("storyContinueToRivalScene")
        }
    }

    private var resultNavigationActions: some View {
        HStack(spacing: 8) {
            Button(action: onExit) {
                Label(loc.story(.opponents), systemImage: "list.bullet")
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .buttonStyle(RivalMenuButtonStyle(onPaper: true))
            .accessibilityIdentifier("storyResultExit")
            Button(action: onRetry) {
                Label(loc.story(bout.verdict == .win ? .replay : .retry), systemImage: "arrow.clockwise")
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .buttonStyle(RivalMenuButtonStyle(primary: onRivalScene == nil, onPaper: true))
            .accessibilityIdentifier("storyRetry")
        }
    }
}