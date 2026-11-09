import SceneKit
import SwiftUI
import XCTest
@testable import RIVAL

@MainActor
final class CombatPresentationTests: XCTestCase {
    func testCompactTopHUDKeepsClocksMetersAndFeedbackInsideShortBounds() throws {
        let loc = LocalizationManager.shared
        let originalLanguage = loc.language
        defer { loc.setLanguage(originalLanguage) }
        for language in AppLanguage.allCases {
            loc.setLanguage(language)
            let presentation = CombatPresentation()
            let clock = try XCTUnwrap(ImageRenderer(content:
                CombatRoundClock(snapshot: closeRangeEngine().snapshot, presentation: presentation)
            ).uiImage)
            XCTAssertEqual(clock.size.width, 100)
            XCTAssertLessThanOrEqual(clock.size.height, 45)
            let meter = try XCTUnwrap(ImageRenderer(content:
                FighterMeter(health: 100, maximumHealth: 100, stamina: 67, color: FightNightPalette.blue,
                    reverse: false, displayName: loc.t(.leaderboardYouLabel), accessibilityName: loc.t(.playerAccessibility),
                    onRing: true).frame(width: 220)
            ).uiImage)
            XCTAssertEqual(meter.size.width, 220)
            XCTAssertLessThanOrEqual(meter.size.height, 46)
            var corner = StoryBoutState(opponent: .pressure)
            corner.finishRound()
            for bout in [StoryBoutState(opponent: .pressure), corner] {
                let storyClock = try XCTUnwrap(ImageRenderer(content:
                    StoryRoundClock(bout: bout, remainingTime: 60, presentation: presentation)
                ).uiImage)
                XCTAssertEqual(storyClock.size.width, 126)
                XCTAssertLessThanOrEqual(storyClock.size.height, 61)
                XCTAssertGreaterThanOrEqual(
                    CombatFeedbackView.topInset(safeAreaTop: 0, isStory: true),
                    storyClock.size.height + 6 + 5 + 5)
            }
            XCTAssertGreaterThanOrEqual(CombatFeedbackView.topInset(safeAreaTop: 0, isStory: false),
                                        max(clock.size.height + 6, meter.size.height) + 5 + 5)
        }
        XCTAssertEqual(CombatFeedbackView.height, 18)
        XCTAssertEqual(CombatFeedbackView.topInset(safeAreaTop: 0, isStory: false) + CombatFeedbackView.height, 79)
        XCTAssertEqual(CombatFeedbackView.topInset(safeAreaTop: 0, isStory: true) + CombatFeedbackView.height, 95)
    }

    func testFightCommentaryRendersActualLocalizedCallsAndPreservesCuePriority() throws {
        let loc = LocalizationManager.shared
        let originalLanguage = loc.language
        defer { loc.setLanguage(originalLanguage) }
        for language in AppLanguage.allCases {
            loc.setLanguage(language)
            let engine = closeRangeEngine()
            let startingMessage = engine.snapshot.message
            XCTAssertTrue(engine.startAttack(engine.player, punch: .jab, recordsHabit: true))
            let attackMessage = engine.snapshot.message
            XCTAssertNotEqual(attackMessage, startingMessage)
            let presentation = CombatPresentation()
            func render(_ message: String?) throws -> UIImage {
                try XCTUnwrap(ImageRenderer(content:
                    CombatFeedbackView(presentation: presentation, message: message)
                        .frame(width: CombatFeedbackView.maximumWidth)
                        .background(Color.black)
                ).uiImage)
            }
            let blank = try render(nil)
            for message in [startingMessage, attackMessage] {
                let unscaledWidth = (message as NSString).size(withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .medium)
                ]).width
                XCTAssertLessThanOrEqual(unscaledWidth * 0.82, CombatFeedbackView.maximumWidth - 20)
                let image = try render(message)
                XCTAssertEqual(image.size, CGSize(width: 500, height: 18))
                XCTAssertNotEqual(image.pngData(), blank.pngData())
                let attachment = XCTAttachment(image: image)
                attachment.name = "restored-commentary-\(language.rawValue)-\(message == attackMessage ? "attack" : "start")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let commentary = try render(attackMessage)
            presentation.receive(.dodge(fighter: .player, grade: .perfect))
            XCTAssertEqual(presentation.signature, .counterWindow)
            let counter = try render(attackMessage)
            XCTAssertNotEqual(counter.pngData(), commentary.pngData())
            presentation.receive(.impact(impact(knockout: true)))
            XCTAssertEqual(try render(attackMessage).pngData(), blank.pngData(),
                           "KO suppresses both the small cue and commentary; the existing KO clock owns the moment.")
        }
    }

    func testFightCommentaryLaneClearsActualFighterBoundsWithUnchangedCamera() throws {
        let controller = isolatedController()
        controller.pause()
        let scene = controller.scene3D
        let size = CGSize(width: 956, height: 440)
        let view = SCNView(frame: CGRect(origin: .zero, size: size))
        view.scene = scene
        view.pointOfView = scene.cameraNode
        let rigs = try ["playerIdentityLabel", "rivalIdentityLabel"].map { name in
            try XCTUnwrap(scene.rootNode.childNodes.first {
                $0.childNode(withName: name, recursively: false) != nil
            })
        }
        var time = 1.0
        for (distance, playerX, rivalX) in [("close", 280.0, 330.0), ("long", 180.0, 400.0)] {
            controller.engine.player.x = playerX
            controller.engine.enemy.x = rivalX
            controller.engine.player.attack = nil
            for _ in 0..<120 {
                scene.update(at: time)
                time += 1.0 / 60
            }
            for punch in [Punch?.none] + Punch.allCases.map(Optional.some) {
                controller.engine.player.attack = punch
                if let punch {
                    controller.engine.player.actionTime = try XCTUnwrap(CombatData.attacks[punch]).activeStart
                }
                scene.update(at: time)
                time += 0.02
                let image = view.snapshot()
                for (index, rig) in rigs.enumerated() {
                    var meshes: [SCNNode] = []
                    func collectBodyMeshes(_ node: SCNNode) {
                        guard !node.isHidden, node.opacity > 0,
                              node.name != "playerIdentityLabel", node.name != "rivalIdentityLabel" else { return }
                        if node.geometry != nil { meshes.append(node) }
                        for child in node.childNodes { collectBodyMeshes(child) }
                    }
                    collectBodyMeshes(rig)
                    XCTAssertGreaterThan(meshes.count, 10)
                    var minX = Float.greatestFiniteMagnitude
                    var minY = Float.greatestFiniteMagnitude
                    var maxX = -Float.greatestFiniteMagnitude
                    var maxY = -Float.greatestFiniteMagnitude
                    for mesh in meshes {
                        let box = try XCTUnwrap(mesh.geometry).boundingBox
                        for x in [box.min.x, box.max.x] {
                            for y in [box.min.y, box.max.y] {
                                for z in [box.min.z, box.max.z] {
                                    let point = view.projectPoint(mesh.convertPosition(SCNVector3(x, y, z), to: nil))
                                    XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                                    minX = min(minX, point.x)
                                    minY = min(minY, point.y)
                                    maxX = max(maxX, point.x)
                                    maxY = max(maxY, point.y)
                                }
                            }
                        }
                    }
                    let bounds = CGRect(x: CGFloat(minX), y: CGFloat(minY),
                                        width: CGFloat(maxX - minX), height: CGFloat(maxY - minY))
                    XCTAssertGreaterThan(bounds.width, 10)
                    XCTAssertGreaterThan(bounds.height, 10)
                    for isStory in [false, true] {
                        let lane = CGRect(x: (size.width - CombatFeedbackView.maximumWidth) / 2,
                                          y: CombatFeedbackView.topInset(safeAreaTop: 0, isStory: isStory),
                                          width: CombatFeedbackView.maximumWidth, height: CombatFeedbackView.height)
                        XCTAssertFalse(lane.intersects(bounds.insetBy(dx: -8, dy: -8)),
                                       "\(distance), \(String(describing: punch)), fighter \(index), story \(isStory): \(bounds)")
                    }
                }
                if punch == nil || punch == .rightUppercut {
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "commentary-clearance-\(distance)-\(punch?.rawValue ?? "idle")"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testMenuFeedbackPreservesLayoutAcrossInteractionAndMotionStates() throws {
        for reducedMotion in [false, true] {
            for state in 0..<3 {
                let content = Text("Select")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MainMenuPalette.paper)
                    .frame(width: 140, height: 48)
                    .rivalSelection(isSelected: state == 1)
                    .rivalPressFeedback(isPressed: state != 0)
                    .environment(\.isEnabled, state != 2)
                    .padding(16)
                    .background(MainMenuPalette.background)
                    .environment(\.rivalReducedMotionOverride, reducedMotion)
                let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
                XCTAssertEqual(image.size, CGSize(width: 172, height: 80))
                let attachment = XCTAttachment(image: image)
                attachment.name = "menu-feedback-reduced-\(reducedMotion)-state-\(state)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        for language in AppLanguage.allCases {
            XCTAssertFalse(StoryText.coachAdvice.text(for: language).isEmpty)
            XCTAssertFalse(StoryText.progressRequired.text(for: language).isEmpty)
        }
    }

    func testCombatControlCopyIsLocalizedAndCompact() {
        for language in AppLanguage.allCases {
            for key: L in [.duckLeftControl, .duckRightControl, .weaveLeftControl, .weaveRightControl] {
                let lines = key.text(for: language).split(separator: "\n")
                XCTAssertEqual(lines.count, 2)
                XCTAssertLessThanOrEqual(lines[1].count, 6)
            }
            XCTAssertFalse(L.combinationControl.text(for: language).isEmpty)
        }
        XCTAssertEqual(L.duckLeftControl.text(for: .korean), "L\n더킹")
        XCTAssertEqual(L.duckRightControl.text(for: .english), "R\nDUCK")
        XCTAssertEqual(L.duckLeftControl.text(for: .japanese), "左\nダック")
    }

    func testRoundTimeUsesBoxingClockWithoutChangingSecondBoundaries() {
        for (remainingTime, expected) in [
            (-1.0, "00:00"), (0, "00:00"), (0.01, "00:01"),
            (44.01, "00:45"), (45, "00:45"), (60, "01:00"), (90, "01:30")
        ] {
            XCTAssertEqual(CombatText.roundTime(remainingTime), expected)
        }
    }

    func testRingHoldCallbacksRemainIdempotentWithCurrentFighterStyle() {
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
        controller.start()
        controller.engine.enemy.stagger = 100
        let initialStamina = controller.engine.player.stamina
        controller.weaveButton(direction: -1, active: true)
        let staminaAfterFirstPress = controller.engine.player.stamina
        XCTAssertLessThan(staminaAfterFirstPress, initialStamina)
        XCTAssertTrue(controller.engine.player.weave.isActive)
        XCTAssertEqual(controller.selectedPunch(base: .jab), .leftHook)
        controller.weaveButton(direction: -1, active: true)
        XCTAssertEqual(controller.engine.player.stamina, staminaAfterFirstPress)
        controller.comboAttack(base: .jab)
        controller.releaseHeldControls()
        XCTAssertEqual(controller.modifiers, CombatModifiers())
        XCTAssertEqual(controller.engine.player.weave.comboDirection, 0)
        for _ in 0..<40 { controller.engine.update(deltaTime: 1.0 / 60) }
        XCTAssertNil(controller.engine.player.attack)
        XCTAssertTrue(controller.engine.roundPlayerPunchCounts.isEmpty)
    }

    func testRingControlStylingRetainsOriginalButtonBounds() throws {
        for language in AppLanguage.allCases {
            for state in 0..<3 {
                let hold = HoldButton(
                    text: L.duckLeftControl.text(for: language), label: L.duckLeftAccessibility.text(for: language),
                    accent: FightNightPalette.blue, width: 58, height: 54,
                    locked: state == 2, isHeld: state == 1, onRing: true, onPress: { _ in }
                )
                let attack = ActionButton(
                    text: (state == 1 ? Punch.leftBody : .jab).controlLabel(for: language),
                    color: RingControlPalette.jab, foreground: FightNightPalette.ink, width: 94, height: 76,
                    locked: state == 2, subtitle: state == 1 ? L.combinationControl.text(for: language) : nil,
                    onRing: true, action: {}
                )
                let holdImage = try XCTUnwrap(ImageRenderer(content: hold).uiImage)
                let attackImage = try XCTUnwrap(ImageRenderer(content: attack).uiImage)
                XCTAssertEqual(holdImage.size, CGSize(width: 58, height: 54))
                XCTAssertEqual(attackImage.size, CGSize(width: 94, height: 76))
                let image = try XCTUnwrap(ImageRenderer(content:
                    HStack(spacing: 16) { hold; attack }
                        .padding(16).background(FightNightPalette.ink)
                ).uiImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "ring-controls-\(language.rawValue)-state-\(state)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testRoundClockRetainsReservedBoundsAcrossKnockoutPhases() throws {
        let phases: [(String, Double?)] = [
            ("fight", nil), ("waiting", 0.1), ("visible", 0.3), ("finished", 1.0)
        ]
        for (name, elapsed) in phases {
            let presentation = CombatPresentation()
            if let elapsed {
                presentation.receive(.impact(impact(knockout: true)))
                presentation.advance(deltaTime: elapsed)
            }
            let content = CombatRoundClock(snapshot: closeRangeEngine().snapshot, presentation: presentation)
                .frame(width: 100, height: 44)
                .background(FightNightPalette.ink)
            let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
            XCTAssertEqual(image.size, CGSize(width: 100, height: 44))
            let attachment = XCTAttachment(image: image)
            attachment.name = "ring-clock-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testRoundSummaryIncludesRoundAndDoesNotInventACornerRead() {
        let engine = closeRangeEngine()
        engine.finishRound(outcome: .playerWin, knockout: false)
        XCTAssertEqual(engine.snapshot.rivalRead, .none)
        for language in AppLanguage.allCases {
            let text = CombatText.roundResult(engine.snapshot, language: language)
            XCTAssertTrue(text.contains("\(L.roundLabel.text(for: language)) \(engine.snapshot.round)"))
            XCTAssertTrue(text.contains(L.roundStatsDodgeLabel.text(for: language)))
            XCTAssertTrue(text.contains(L.roundStatsTopAttackLabel.text(for: language)))
            XCTAssertFalse(text.contains(L.roundStatsRivalCornerLabel.text(for: language)))
        }
    }

    func testPaperRecordTableRendersRealEmptyAndAttackRecordsInEveryLanguage() throws {
        let loc = LocalizationManager.shared
        let originalLanguage = loc.language
        defer { loc.setLanguage(originalLanguage) }
        for language in AppLanguage.allCases {
            loc.setLanguage(language)
            for hasAttack in [false, true] {
                let engine = closeRangeEngine()
                engine.enemy.stagger = 1000
                if hasAttack {
                    XCTAssertTrue(engine.startAttack(engine.player, punch: .jab, recordsHabit: true))
                    for _ in 0..<40 { engine.update(deltaTime: 1.0 / 60) }
                }
                engine.finishRound(outcome: .playerWin, knockout: false)
                let snapshot = engine.snapshot
                XCTAssertEqual(snapshot.roundPlayerTopAttack, hasAttack ? .jab : nil)
                XCTAssertNil(snapshot.roundEnemyTopAttack)
                XCTAssertEqual(snapshot.roundPlayerDodgeCount, 0)
                XCTAssertEqual(snapshot.roundEnemyDodgeCount, 0)
                let content = RoundRecordTable(snapshot: snapshot, opponentName: StoryOpponent.pressure.fighterName(for: language))
                    .padding(20)
                    .frame(width: 460, height: 150)
                    .rivalPaperSurface()
                let image = try XCTUnwrap(ImageRenderer(content: content).uiImage)
                XCTAssertEqual(image.size, CGSize(width: 460, height: 150))
                let attachment = XCTAttachment(image: image)
                attachment.name = "paper-round-record-\(language.rawValue)-attack-\(hasAttack)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testPaperRecordTextAndCornerColorsMeetReadableContrast() {
        func luminance(_ color: Color) -> Double {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            func linear(_ channel: CGFloat) -> Double {
                let value = Double(channel)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return linear(red) * 0.2126 + linear(green) * 0.7152 + linear(blue) * 0.0722
        }
        let paper = luminance(PreparationPalette.paper)
        for ink in [PreparationPalette.ink, PreparationPalette.secondary, PreparationPalette.player, PreparationPalette.rival] {
            let foreground = luminance(ink)
            let contrast = (max(paper, foreground) + 0.05) / (min(paper, foreground) + 0.05)
            XCTAssertGreaterThanOrEqual(contrast, 4.5)
        }
    }

    func testStoryCornerCountdownStillGatesTheNextRound() {
        var bout = StoryBoutState(opponent: .pressure)
        bout.finishRound()
        XCTAssertEqual(bout.phase, .corner)
        XCTAssertFalse(bout.canStartNextRound)
        bout.beginNextRound()
        XCTAssertEqual(bout.round, 1)
        bout.advanceCorner(bout.rules.cornerSeconds - 0.01)
        XCTAssertFalse(bout.canStartNextRound)
        bout.advanceCorner(0.01)
        XCTAssertTrue(bout.canStartNextRound)
        bout.beginNextRound()
        XCTAssertEqual(bout.round, 2)
        XCTAssertEqual(bout.phase, .fighting)
    }

    func testSharedControlsRenderReleasedHeldAndUnavailableStates() throws {
        for language in AppLanguage.allCases {
            let content = HStack(alignment: .top, spacing: 24) {
                ForEach(0..<3) { state in
                    VStack(spacing: 12) {
                        Text((state == 0 ? L.controlReleased : (state == 1 ? .controlHeld : .inputUnavailable)).text(for: language))
                            .font(.system(size: 12, weight: .semibold))
                        HoldButton(symbol: "shield.fill", label: L.guardAccessibility.text(for: language),
                            accent: FightNightPalette.gold, width: 76, height: 54,
                            locked: state == 2, isHeld: state == 1, onPress: { _ in })
                        ActionButton(text: (state == 1 ? Punch.leftBody : .jab).controlLabel(for: language),
                            color: Color(red: 0.035, green: 0.29, blue: 0.70), width: 120, height: 76,
                            locked: state == 2, subtitle: state == 1 ? L.combinationControl.text(for: language) : nil,
                            action: {})
                    }
                    .frame(width: 140)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 520, height: 240)
            .background(FightNightPalette.ink)
            .environment(\.rivalReducedMotionOverride, true)
            let renderer = ImageRenderer(content: content)
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size, CGSize(width: 520, height: 240))
            let attachment = XCTAttachment(image: image)
            attachment.name = "combat-ui-control-states-\(language.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testLegacyStatsKeepWinsWhenNewRewardKeysAreMissing() throws {
        let data = Data(#"{"winsByStyle":{"standard":72,"out_boxing":28}}"#.utf8)
        let stats = try JSONDecoder().decode(PlayerStats.self, from: data)

        XCTAssertEqual(stats.totalWins, 100)
        XCTAssertEqual(stats.gymSeconds, 0)
        XCTAssertEqual(stats.perfectRoundWins, 0)
        XCTAssertEqual(stats.currentWinStreak, 0)
        XCTAssertEqual(stats.bestWinStreak, 0)
        XCTAssertTrue(OutfitID.blackout.isUnlocked(
            highestRound: 1, totalWins: stats.totalWins, gymSeconds: stats.gymSeconds,
            perfectRoundWins: stats.perfectRoundWins, bestWinStreak: stats.bestWinStreak,
            winsByStyle: stats.winsByStyle
        ))
    }

    func testCurrentStatsRoundTripPreservesAllRewards() throws {
        let stats = PlayerStats(
            winsByStyle: [FightStyle.infighting.rawValue: 55], gymSeconds: 86400,
            perfectRoundWins: 12, currentWinStreak: 4, bestWinStreak: 20
        )
        let data = try JSONEncoder().encode(stats)
        XCTAssertEqual(try JSONDecoder().decode(PlayerStats.self, from: data), stats)
    }

    func testOlderStreakWithoutBestKeepsItsUnlockProgress() throws {
        let data = Data(#"{"winsByStyle":{},"currentWinStreak":23}"#.utf8)
        let stats = try JSONDecoder().decode(PlayerStats.self, from: data)
        XCTAssertEqual(stats.bestWinStreak, 23)
    }

    func testStatsDecodeIgnoresUnknownFutureKeys() throws {
        let data = Data(#"{"gymSeconds":7200,"bestWinStreak":11,"futureField":999,"flags":{"x":1}}"#.utf8)
        let stats = try JSONDecoder().decode(PlayerStats.self, from: data)

        XCTAssertEqual(stats.totalWins, 0)
        XCTAssertEqual(stats.gymSeconds, 7200, accuracy: 0.001)
        XCTAssertEqual(stats.currentWinStreak, 0)
        XCTAssertEqual(stats.bestWinStreak, 11)
    }

    func testPreferredStyleFallsBackToKnownStyleWhenUnknownKeyHasHigherWins() throws {
        let data = Data(#"{"winsByStyle":{"future_style":40,"standard":3,"in_fighting":2}}"#.utf8)
        let stats = try JSONDecoder().decode(PlayerStats.self, from: data)

        XCTAssertEqual(stats.totalWins, 45)
        XCTAssertEqual(stats.preferredStyle, .standard)
    }

    func testHitEventIsEmittedOnceAtActiveFrame() {
        let engine = closeRangeEngine()
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        engine.update(deltaTime: 0.05)
        XCTAssertTrue(impacts(in: events).isEmpty)
        engine.update(deltaTime: 0.05)

        let hits = impacts(in: events)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.attacker, .player)
        XCTAssertEqual(hits.first?.punch, .jab)
        XCTAssertEqual(hits.first?.damage, 6)
        XCTAssertEqual(hits.first?.level, .light)
        advance(engine, until: { engine.player.attack == nil })
        XCTAssertEqual(impacts(in: events).count, 1)
    }

    func testDodgeAndCounterAreNotLostBetweenHUDPublications() {
        let controller = isolatedController()
        let engine = controller.engine
        performPerfectDodge(engine)
        XCTAssertEqual(controller.snapshot.successfulDodgeCount, 0, "No HUD publication since start")
        XCTAssertEqual(controller.presentation.signature, .counterWindow)

        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        XCTAssertNil(controller.presentation.signature, "The counter opportunity was accepted")
        advance(engine, until: { engine.perfectCounterCount == 1 })
        XCTAssertEqual(controller.presentation.signature, .perfectCounter)
        XCTAssertEqual(controller.presentation.impactLevel, .perfectCounter)
        XCTAssertEqual(controller.snapshot.enemyHP, 100, "Feedback is independent of HUD polling")
    }

    func testGuardBreakHasOneImpactAndNoRedundantExhaustionCue() {
        let engine = closeRangeEngine()
        engine.player.stamina = 5
        engine.setGuarding(true)
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        XCTAssertTrue(engine.startAttack(engine.enemy, punch: .jab))
        engine.update(deltaTime: 0.05)
        engine.update(deltaTime: 0.05)

        let hits = impacts(in: events)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.guarded, true)
        XCTAssertEqual(hits.first?.guardBroken, true)
        XCTAssertEqual(hits.first?.level, .guardBreak)
        XCTAssertEqual(engine.exhaustionCount, 1, "Gameplay still records exhaustion")
        XCTAssertFalse(events.contains { if case .exhausted = $0 { return true }; return false })
    }

    func testMissDoesNotProduceImpactFeedback() {
        let engine = CombatEngine(persistHabits: false)
        engine.startRound()
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        advance(engine, until: { engine.player.attack == nil })
        XCTAssertTrue(impacts(in: events).isEmpty)
        XCTAssertTrue(events.contains(.whiff(fighter: .player)))
    }

    func testRejectedAttackDoesNotProducePresentationEvent() {
        let engine = closeRangeEngine()
        engine.player.stamina = 0
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        XCTAssertFalse(engine.startAttack(engine.player, punch: .cross))
        XCTAssertTrue(events.isEmpty)
    }

    func testOrdinaryAndBlockedHitsDoNotShakeCamera() {
        let presentation = CombatPresentation()
        presentation.receive(.impact(impact(damage: 6)))
        XCTAssertEqual(presentation.cameraImpulse, 0)
        presentation.receive(.roundStarted)
        presentation.receive(.impact(impact(damage: 4, guarded: true)))
        XCTAssertEqual(presentation.cameraImpulse, 0)
        presentation.receive(.impact(impact(damage: 14)))
        XCTAssertGreaterThan(presentation.cameraImpulse, 0)
        XCTAssertLessThan(presentation.cameraImpulse, 0.5)
    }

    func testKnockoutPreemptsCounterAndNormalFeedback() {
        let presentation = CombatPresentation()
        presentation.receive(.dodge(fighter: .player, grade: .perfect))
        presentation.receive(.impact(impact(perfectCounter: true)))
        presentation.receive(.impact(impact(knockout: true)))
        presentation.receive(.impact(impact(damage: 6)))
        presentation.receive(.dodge(fighter: .player, grade: .perfect))

        XCTAssertEqual(presentation.signature, .knockout)
        XCTAssertEqual(presentation.impactLevel, .knockout)
        XCTAssertEqual(presentation.cameraImpulse, ImpactLevel.knockout.cameraStrength, accuracy: 0.0001)
        presentation.advance(deltaTime: ImpactLevel.knockout.duration / 2)
        XCTAssertEqual(presentation.cameraImpulse, ImpactLevel.knockout.cameraStrength / 4, accuracy: 0.0001)
    }

    func testKnockoutClockWaitsThenAppearsAndFinishesOnRealTime() {
        let presentation = CombatPresentation()
        presentation.receive(.impact(impact(knockout: true)))
        XCTAssertEqual(presentation.signature, .knockout, "Priority is immediate, not the large banner")
        XCTAssertEqual(presentation.knockoutClockPhase, .waiting)
        presentation.advance(deltaTime: 0.19)
        XCTAssertEqual(presentation.knockoutClockPhase, .waiting)
        presentation.advance(deltaTime: 0.011)
        XCTAssertEqual(presentation.knockoutClockPhase, .visible)
        presentation.advance(deltaTime: 0.58)
        XCTAssertEqual(presentation.knockoutClockPhase, .visible)
        presentation.advance(deltaTime: 0.02)
        XCTAssertEqual(presentation.knockoutClockPhase, .finished)
        XCTAssertNil(presentation.signature)
        presentation.receive(.roundStarted)
        XCTAssertEqual(presentation.knockoutClockPhase, .inactive)
    }

    func testKnockoutClockResetCancelsPendingDisplayAndPauseDoesNotAdvanceIt() {
        let presentation = CombatPresentation()
        for beforeReset in [0.10, 0.25, 1.0] {
            presentation.receive(.impact(impact(knockout: true)))
            presentation.advance(deltaTime: beforeReset)
            let phase = presentation.knockoutClockPhase
            for invalidTime in [0.0, -1, Double.nan, Double.infinity] {
                presentation.advance(deltaTime: invalidTime)
                XCTAssertEqual(presentation.knockoutClockPhase, phase)
            }
            presentation.receive(.roundStarted)
            presentation.advance(deltaTime: 1)
            XCTAssertEqual(presentation.knockoutClockPhase, .inactive)
            XCTAssertNil(presentation.signature)
        }
        presentation.receive(.impact(impact(perfectCounter: true)))
        XCTAssertEqual(presentation.signature, .perfectCounter)
        XCTAssertEqual(presentation.knockoutClockPhase, .inactive)
        XCTAssertEqual(CombatPresentationTiming.knockoutResultReveal, 0.95)
        XCTAssertEqual(CombatPresentationTiming.decisionResultReveal, 0.35)
    }

    func testPresentationExpiresAndRoundResetClearsAllEffects() {
        let presentation = CombatPresentation()
        presentation.receive(.impact(impact(perfectCounter: true)))
        for _ in 0..<60 { presentation.advance(deltaTime: 1.0 / 60) }
        XCTAssertNil(presentation.signature)
        XCTAssertNil(presentation.impactLevel)
        XCTAssertEqual(presentation.cameraImpulse, 0)
        presentation.receive(.impact(impact(knockout: true)))
        presentation.receive(.roundStarted)
        XCTAssertNil(presentation.signature)
        XCTAssertEqual(presentation.impactTime, 0)
    }

    func testCameraFocusUsesFastEntryHoldAndReturn() {
        let duration = DodgeGrade.perfect.focusDuration
        XCTAssertEqual(CombatCameraFocus.envelope(remaining: duration, duration: duration), 0)
        XCTAssertGreaterThan(CombatCameraFocus.envelope(remaining: duration - 0.03, duration: duration), 0.8)
        XCTAssertEqual(CombatCameraFocus.envelope(remaining: 0.30, duration: duration), 1)
        XCTAssertLessThan(CombatCameraFocus.envelope(remaining: 0.03, duration: duration), 0.1)
        XCTAssertEqual(CombatCameraFocus.envelope(remaining: 0, duration: duration), 0)
    }

    func testKnockoutCameraOwnsFocusEvenDuringItsEntry() {
        let remaining = CombatData.koMomentDuration - 0.01
        let focus = CombatCameraFocus.sample(dodgeGrade: .perfect, dodgeTime: 0.3, knockoutTime: remaining, reducedMotion: false)
        let expected = CombatData.koMomentCameraZoom * CombatCameraFocus.envelope(remaining: remaining, duration: CombatData.koMomentDuration)
        XCTAssertEqual(focus.push, expected, accuracy: 0.0001)
        XCTAssertLessThan(focus.push, DodgeGrade.perfect.cameraZoom, "Must choose KO, not max of two unrelated envelopes")
    }

    func testReducedMotionRemovesCameraEffectsButKeepsCounterCue() {
        let focus = CombatCameraFocus.sample(dodgeGrade: .perfect, dodgeTime: 0.3, knockoutTime: 0.3, reducedMotion: true)
        XCTAssertEqual(focus.push, 0)
        XCTAssertEqual(focus.fieldOfView, 50)
        let controller = isolatedController()
        controller.scene3D.setReducedMotion(true)
        performPerfectDodge(controller.engine)
        XCTAssertEqual(controller.presentation.signature, .counterWindow)
        controller.engine.update(deltaTime: 0.05)
        XCTAssertEqual(controller.engine.lastSimulationDeltaTime, 0.05 * DodgeGrade.perfect.timeScale, accuracy: 0.0001)
        controller.scene3D.update(at: 1)
        XCTAssertEqual(controller.scene3D.cameraNode.camera?.fieldOfView, 50)
    }

    func testFinalDodgeFocusFrameStillUsesItsOriginalScale() {
        let engine = closeRangeEngine()
        performPerfectDodge(engine)
        while engine.rivalMomentTime > 0.05 { engine.update(deltaTime: 0.025) }
        let remaining = engine.rivalMomentTime
        XCTAssertGreaterThan(remaining, 0)
        let roundTime = engine.roundTime
        engine.update(deltaTime: remaining)
        XCTAssertEqual(engine.lastSimulationDeltaTime, remaining * DodgeGrade.perfect.timeScale, accuracy: 0.000001)
        XCTAssertEqual(roundTime - engine.roundTime, remaining * DodgeGrade.perfect.timeScale, accuracy: 0.000001)
        XCTAssertNil(engine.rivalMomentGrade)
    }

    func testKnockoutFallPrecedesResultAndWinnerFinishesPunch() {
        let engine = closeRangeEngine()
        engine.enemy.hp = 5
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        XCTAssertTrue(engine.startAttack(engine.player, punch: .jab))
        advance(engine, until: { engine.phase == .roundBreak })
        XCTAssertFalse(engine.snapshot.showsRoundResult)
        XCTAssertNotNil(engine.player.attack)
        for _ in 0..<13 { engine.update(deltaTime: 0.05) }
        XCTAssertFalse(engine.snapshot.showsRoundResult, "The slowed fall must not be hidden by the result card")
        advance(engine, until: { engine.snapshot.showsRoundResult })
        XCTAssertEqual(engine.enemy.knockdown, 1)
        XCTAssertNil(engine.player.attack, "The finishing hand returns instead of freezing in extension")
        XCTAssertEqual(impacts(in: events).count, 1, "Post-round animation never resolves more hits")
        XCTAssertEqual(engine.playerScore, 1)
        XCTAssertFalse(engine.snapshot.canAdvanceRound)
        engine.requestNextRound()
        XCTAssertEqual(engine.phase, .roundBreak)
        advance(engine, until: { engine.snapshot.canAdvanceRound })
        engine.requestNextRound()
        XCTAssertEqual(engine.phase, .fight)
        XCTAssertFalse(engine.snapshot.showsRoundResult)
        XCTAssertEqual(engine.koMomentTime, 0)
    }

    func testDecisionBreakHasNoKnockoutEffect() {
        let engine = closeRangeEngine()
        engine.finishRound(outcome: .draw, knockout: false)
        XCTAssertFalse(engine.snapshot.showsRoundResult)
        advance(engine, until: { engine.snapshot.showsRoundResult })
        XCTAssertEqual(engine.koMomentTime, 0)
        XCTAssertFalse(engine.lastRoundWasKnockout)
        XCTAssertFalse(engine.snapshot.canAdvanceRound)
    }

    func testRivalCannotMakeNewDecisionsAfterRoundEnds() {
        let engine = closeRangeEngine()
        engine.finishRound(outcome: .playerLoss, knockout: true)
        let position = engine.enemy.x
        let stamina = engine.enemy.stamina
        for decision in ["circle_left", "dodge_left", "dodge_back", Punch.jab.rawValue] {
            XCTAssertFalse(engine.performEnemyDecision(decision))
        }
        XCTAssertEqual(engine.enemy.x, position)
        XCTAssertEqual(engine.enemy.stamina, stamina)
    }

    func testRoundRecordUpdatesOnceWithoutWaitingForHUD() {
        let controller = isolatedController()
        controller.engine.finishRound(outcome: .playerWin, knockout: false)
        XCTAssertEqual(controller.playerStats.totalWins, 1)
        XCTAssertEqual(controller.playerStats.perfectRoundWins, 1)
        controller.publishSnapshot()
        controller.publishSnapshot()
        controller.engine.finishRound(outcome: .playerWin, knockout: false)
        XCTAssertEqual(controller.playerStats.totalWins, 1)
    }

    func testInactivityClearsHeldInputAndPausesPresentationClock() {
        let controller = isolatedController()
        controller.move(x: 1, y: 0, active: true)
        controller.guardButton(active: true)
        controller.duckButton(direction: 1, active: true)
        controller.presentation.receive(.impact(impact(perfectCounter: true)))
        controller.suspendForInactivity()
        XCTAssertEqual(controller.engine.phase, .paused)
        XCTAssertEqual(controller.engine.moveX, 0)
        XCTAssertFalse(controller.engine.player.guarding)
        XCTAssertEqual(controller.engine.player.duckDirection, 0)
        controller.scene3D.update(at: 1)
        controller.scene3D.update(at: 1.05)
        XCTAssertEqual(controller.presentation.impactTime, ImpactLevel.perfectCounter.duration)
        XCTAssertEqual(controller.engine.lastSimulationDeltaTime, 0)
        controller.pause()
        controller.synchronizeHeldControls()
        XCTAssertFalse(controller.engine.player.guarding)
        XCTAssertEqual(controller.engine.moveX, 0)
    }

    func testOpeningCinematicDoesNotAdvanceGameplayOrEmitHits() {
        let engine = closeRangeEngine()
        let scene = Arena3DScene(engine: engine)
        var events: [CombatEvent] = []
        engine.onCombatEvent = { events.append($0) }
        let initialTime = engine.roundTime
        let initialPosition = engine.player.x
        scene.setCinematicMode(true, presentation: .appOpening)
        for frame in 0..<100 { scene.update(at: 1 + Double(frame) / 60) }
        scene.setCinematicMode(false)
        XCTAssertEqual(engine.roundTime, initialTime)
        XCTAssertEqual(engine.player.hp, 100)
        XCTAssertEqual(engine.enemy.hp, 100)
        XCTAssertEqual(engine.player.x, initialPosition)
        XCTAssertTrue(events.isEmpty)
    }

    func testPunchTrailIsShortAndDisabledForReducedMotion() throws {
        let controller = isolatedController()
        let scene = controller.scene3D
        controller.engine.enemy.stagger = 1000
        XCTAssertTrue(controller.engine.startAttack(controller.engine.player, punch: .cross))
        let trail = try XCTUnwrap(scene.rootNode.childNode(withName: "playerRightPunchTrail", recursively: true))
        var visibleSamples = 0
        for frame in 0..<15 {
            scene.update(at: 1 + Double(frame) / 60)
            if !trail.isHidden {
                visibleSamples += 1
                let capsule = try XCTUnwrap(trail.geometry as? SCNCapsule)
                XCTAssertLessThanOrEqual(capsule.height, 0.321)
                XCTAssertEqual(capsule.firstMaterial?.blendMode, .alpha)
            }
        }
        XCTAssertGreaterThan(visibleSamples, 0)
        scene.setReducedMotion(true)
        scene.update(at: 1.25)
        XCTAssertTrue(trail.isHidden)
    }

    private func impact(
        damage: Int = 12, guarded: Bool = false, perfectCounter: Bool = false, knockout: Bool = false
    ) -> CombatImpact {
        CombatImpact(attacker: .player, punch: .cross, damage: damage, guarded: guarded,
                     guardBroken: false, counter: perfectCounter, perfectCounter: perfectCounter, knockout: knockout)
    }

    private func impacts(in events: [CombatEvent]) -> [CombatImpact] {
        events.compactMap { if case let .impact(hit) = $0 { return hit }; return nil }
    }

    private func isolatedController() -> GameController {
        let controller = GameController(persistsProgress: false, feedbackEnabled: false)
        controller.start()
        controller.engine.player.x = 280
        controller.engine.enemy.x = 330
        return controller
    }

    private func closeRangeEngine() -> CombatEngine {
        let engine = CombatEngine(persistHabits: false)
        engine.startRound()
        engine.player.x = 280
        engine.enemy.x = 330
        return engine
    }

    private func performPerfectDodge(_ engine: CombatEngine) {
        XCTAssertTrue(engine.startAttack(engine.enemy, punch: .cross))
        engine.update(deltaTime: 0.05)
        engine.setDuck(-1, active: true)
        engine.update(deltaTime: 0.05)
        engine.update(deltaTime: 0.05)
        XCTAssertEqual(engine.lastPlayerDodgeGrade, .perfect)
    }

    private func advance(
        _ engine: CombatEngine, until condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line
    ) {
        for _ in 0..<240 {
            if condition() { return }
            engine.update(deltaTime: 0.01)
        }
        XCTAssertTrue(condition(), "Combat event did not resolve within the bounded time", file: file, line: line)
    }
}