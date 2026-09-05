import SwiftUI
import UIKit

/// Cumulative win record kept purely on-device (no server), used both to show the player their own progress
/// and as the score submitted to the optional Game Center leaderboard. `winsByStyle` (rather than a single
/// counter) also lets us derive the player's most-used fighting style to show alongside their rank. Also
/// tracks the other reward-unlock stats: cumulative time spent in the practice Gym, how many rounds were
/// won without taking a single hit ("perfect" rounds), and the player's best-ever consecutive win streak
/// (`bestWinStreak` only ever grows, even if the live streak later breaks -- once a streak outfit is
/// unlocked via `bestWinStreak`, it can never re-lock).
struct PlayerStats: Codable, Equatable {
    var winsByStyle: [String: Int] = [:]
    var gymSeconds: Double = 0
    var perfectRoundWins: Int = 0
    var currentWinStreak: Int = 0
    var bestWinStreak: Int = 0

    var totalWins: Int { winsByStyle.values.reduce(0, +) }

    var preferredStyle: FightStyle? {
        winsByStyle.max { $0.value < $1.value }.flatMap { FightStyle(rawValue: $0.key) }
    }
}

@MainActor
final class GameController: ObservableObject {
    private struct MovementControl: Hashable {
        let forward: Int
        let strafe: Int
    }

    private static let outfitDefaultsKey = "pixelBoxingEquippedOutfit"
    private static let soundMutedDefaultsKey = "pixelBoxingSoundMuted"
    private static let statsDefaultsKey = "pixelBoxingPlayerStats"

    let engine = CombatEngine()
    let sound = SoundManager()
    @Published private(set) var snapshot: CombatSnapshot
    @Published private(set) var playerStyle: FightStyle
    @Published private(set) var equippedOutfit: OutfitID
    @Published private(set) var isSoundMuted: Bool
    @Published private(set) var playerStats: PlayerStats
    private var heldMovement: Set<MovementControl> = []
    private var guardHeld = false
    private var duckDirectionHeld = 0

    lazy var scene3D: Arena3DScene = {
        let scene = Arena3DScene(engine: engine)
        scene.controller = self
        return scene
    }()

    init() {
        snapshot = engine.snapshot
        playerStyle = engine.player.style
        equippedOutfit = OutfitID(rawValue: UserDefaults.standard.string(forKey: GameController.outfitDefaultsKey) ?? "") ?? .classic
        isSoundMuted = UserDefaults.standard.bool(forKey: GameController.soundMutedDefaultsKey)
        if let data = UserDefaults.standard.data(forKey: GameController.statsDefaultsKey),
           let saved = try? JSONDecoder().decode(PlayerStats.self, from: data) {
            playerStats = saved
        } else {
            playerStats = PlayerStats()
        }
        sound.isMuted = isSoundMuted
    }

    func publishSnapshot() {
        let nextSnapshot = engine.snapshot
        if nextSnapshot.phase != snapshot.phase {
            if nextSnapshot.phase == .fight, snapshot.phase != .paused {
                sound.playRoundStart()
            } else if nextSnapshot.phase == .roundBreak {
                sound.playRoundResult(outcome: nextSnapshot.lastRoundOutcome, knockout: nextSnapshot.lastRoundWasKnockout)
                if nextSnapshot.lastRoundOutcome == .playerWin {
                    recordWin(perfectRound: nextSnapshot.roundPlayerWasUnhit)
                } else if nextSnapshot.lastRoundOutcome == .playerLoss {
                    recordLoss()
                }
            }
        }
        if nextSnapshot.phase == .fight {
            let previousCeil = Int(ceil(snapshot.time))
            let nextCeil = Int(ceil(nextSnapshot.time))
            if nextCeil != previousCeil, (1...3).contains(nextCeil) {
                sound.playCountdownTick()
            }
        }
        if nextSnapshot.successfulDodgeCount > snapshot.successfulDodgeCount {
            sound.playDuckEvade(pan: pan(forPlayer: true))
            HapticsManager.shared.notify(.success)
        } else if nextSnapshot.enemyHP < snapshot.enemyHP {
            let damage = snapshot.enemyHP - nextSnapshot.enemyHP
            if nextSnapshot.enemyHP == 0 {
                sound.playKnockout()
            } else {
                sound.playImpact(damage: damage, guarded: nextSnapshot.lastImpactGuarded, pan: pan(forPlayer: false))
            }
            HapticsManager.shared.impact(style: .heavy, intensity: min(1, 0.45 + CGFloat(damage) / 20))
        } else if nextSnapshot.playerHP < snapshot.playerHP {
            let damage = snapshot.playerHP - nextSnapshot.playerHP
            if nextSnapshot.playerHP == 0 {
                sound.playKnockout()
            } else {
                sound.playImpact(damage: damage, guarded: nextSnapshot.lastImpactGuarded, pan: pan(forPlayer: true))
            }
            HapticsManager.shared.impact(style: .medium, intensity: min(1, 0.4 + CGFloat(damage) / 22))
        }
        if nextSnapshot.whiffCount > snapshot.whiffCount {
            sound.playWhiff(pan: pan(forPlayer: nextSnapshot.lastWhiffByPlayer))
        }
        if nextSnapshot.guardBreakCount > snapshot.guardBreakCount {
            sound.playGuardBreak(pan: pan(forPlayer: nextSnapshot.lastGuardBreakByPlayer))
        } else if nextSnapshot.exhaustionCount > snapshot.exhaustionCount {
            sound.playExhausted(pan: pan(forPlayer: nextSnapshot.lastExhaustedByPlayer))
        }
        snapshot = nextSnapshot
    }

    /// Maps a fighter's arena x-position to a rough left/right stereo pan (-1...1) so effect sounds hint
    /// at where the action happened in the ring instead of always playing dead-center.
    private func pan(forPlayer isPlayer: Bool) -> Float {
        let x = isPlayer ? engine.player.x : engine.enemy.x
        return Float(max(-1, min(1, (x - 295) / 125)))
    }

    func start() {
        engine.resumeSession()
        publishSnapshot()
        HapticsManager.shared.notify(.success)
    }

    func setCinematicMode(_ active: Bool, presentation: ArenaCinematicPresentation = .matchIntro) {
        scene3D.setCinematicMode(active, presentation: presentation)
    }

    func pause() {
        engine.togglePause()
        publishSnapshot()
    }

    func continueToNextRound() {
        engine.requestNextRound()
        publishSnapshot()
        HapticsManager.shared.notify(.success)
    }

    func resetLearning() {
        heldMovement.removeAll()
        guardHeld = false
        duckDirectionHeld = 0
        engine.setMove(x: 0, y: 0)
        engine.setGuarding(false)
        engine.setDuck(0, active: false)
        engine.resetLearning()
        publishSnapshot()
        HapticsManager.shared.notify(.warning)
    }

    func move(x: Double, y: Double, active: Bool) {
        let control = MovementControl(forward: Int(x), strafe: Int(y))
        if active {
            heldMovement.insert(control)
        } else {
            heldMovement.remove(control)
        }
        let forward = heldMovement.reduce(0) { $0 + $1.forward }
        let strafe = heldMovement.reduce(0) { $0 + $1.strafe }
        engine.setMove(x: Double(forward), y: Double(strafe))
    }

    func guardButton(active: Bool) {
        guardHeld = active
        engine.setGuarding(active)
    }

    func duckButton(direction: Int, active: Bool) {
        duckDirectionHeld = active ? direction : (duckDirectionHeld == direction ? 0 : duckDirectionHeld)
        engine.setDuck(duckDirectionHeld, active: duckDirectionHeld != 0)
    }

    func attack(_ punch: Punch) {
        if engine.startAttack(engine.player, punch: punch, recordsHabit: true) {
            HapticsManager.shared.impact(style: .rigid, intensity: 0.58)
        }
    }

    func comboAttack(base: Punch) {
        attack(CombatData.comboPunch(base: base, guarding: guardHeld, duckDirection: duckDirectionHeld))
    }

    func backstep() {
        if engine.backstep() {
            sound.playBackstep(pan: pan(forPlayer: true))
            HapticsManager.shared.impact(style: .rigid, intensity: 0.72)
            publishSnapshot()
        }
    }

    func synchronizeHeldControls() {
        guard engine.player.attack == nil else { return }
        engine.setGuarding(guardHeld)
        engine.setDuck(duckDirectionHeld, active: duckDirectionHeld != 0)
    }

    func setPlayerStyle(_ style: FightStyle) {
        engine.setPlayerStyle(style)
        playerStyle = style
    }

    func setEquippedOutfit(_ outfit: OutfitID) {
        guard outfit.isUnlocked(
            highestRound: engine.highestRound,
            totalWins: playerStats.totalWins,
            gymSeconds: playerStats.gymSeconds,
            perfectRoundWins: playerStats.perfectRoundWins,
            bestWinStreak: playerStats.bestWinStreak,
            winsByStyle: playerStats.winsByStyle
        ) else { return }
        equippedOutfit = outfit
        scene3D.setPlayerOutfit(outfit)
        UserDefaults.standard.set(outfit.rawValue, forKey: GameController.outfitDefaultsKey)
    }

    func setSoundMuted(_ muted: Bool) {
        isSoundMuted = muted
        sound.isMuted = muted
        UserDefaults.standard.set(muted, forKey: GameController.soundMutedDefaultsKey)
    }

    /// Bumps the on-device win record for the round's outcome and best-effort submits the updated total
    /// (plus the player's most-used style) to the optional Game Center leaderboard. Never blocks or affects
    /// local gameplay if the submission fails (offline, not signed in, leaderboard not yet configured).
    private func recordWin(perfectRound: Bool) {
        playerStats.winsByStyle[playerStyle.rawValue, default: 0] += 1
        if perfectRound {
            playerStats.perfectRoundWins += 1
        }
        playerStats.currentWinStreak += 1
        playerStats.bestWinStreak = max(playerStats.bestWinStreak, playerStats.currentWinStreak)
        persistStats()
        GameCenterManager.shared.submit(
            totalWins: playerStats.totalWins,
            preferredStyle: playerStats.preferredStyle,
            highestRound: engine.highestRound
        )
    }

    /// Breaks the player's live win streak on a round loss. Only `currentWinStreak` resets here --
    /// `bestWinStreak` (used for the streak outfit's unlock check) is never decreased.
    private func recordLoss() {
        guard playerStats.currentWinStreak != 0 else { return }
        playerStats.currentWinStreak = 0
        persistStats()
    }

    /// Adds elapsed practice-room time toward the Gym's cumulative-hours outfit unlock. Called once when the
    /// player leaves the practice room (see `PracticeView`'s appear/disappear timing).
    func addGymSeconds(_ seconds: Double) {
        guard seconds > 0 else { return }
        playerStats.gymSeconds += seconds
        persistStats()
    }

    private func persistStats() {
        if let data = try? JSONEncoder().encode(playerStats) {
            UserDefaults.standard.set(data, forKey: GameController.statsDefaultsKey)
        }
    }
}
