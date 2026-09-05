import SwiftUI
import UIKit

/// Drives the practice room screen: owns a `PracticeEngine` (no opponent, no round/score) plus the
/// `PracticeScene` that renders it, and composes the same held-button input pattern `GameController` uses
/// for the real fight (a `Set` of held directional controls combined every frame into one move vector).
@MainActor
final class PracticeController: ObservableObject {
    private struct MovementControl: Hashable {
        let forward: Int
        let strafe: Int
    }

    let engine = PracticeEngine()
    let outfit: OutfitID
    let sound = SoundManager()
    @Published private(set) var playerLocked = false
    @Published private(set) var stamina = 100.0
    private var heldMovement: Set<MovementControl> = []
    private var guardHeld = false
    private var duckDirectionHeld = 0

    lazy var scene3D: PracticeScene = {
        let scene = PracticeScene(engine: engine, outfit: outfit)
        scene.controller = self
        return scene
    }()

    init(style: FightStyle, outfit: OutfitID) {
        self.outfit = outfit
        engine.setStyle(style)
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

    func comboAttack(base: Punch) {
        let punch = CombatData.comboPunch(base: base, guarding: guardHeld, duckDirection: duckDirectionHeld)
        if engine.startAttack(punch) {
            HapticsManager.shared.impact(style: .rigid, intensity: 0.55)
        }
    }

    func backstep() {
        if engine.backstep() {
            HapticsManager.shared.impact(style: .rigid, intensity: 0.68)
        }
    }

    /// Called by `PracticeScene` the instant a punch lands on the heavy bag, so landing a hit feels
    /// distinct (heavier haptic buzz + an impact sound) from just throwing a punch.
    func notifyBagHit(damage: Int) {
        let intensity = min(1, 0.5 + Double(damage) / 24)
        HapticsManager.shared.impact(style: .heavy, intensity: intensity)
        sound.playImpact(damage: damage, guarded: false)
    }

    func synchronizeHeldControls() {
        guard engine.player.attack == nil else { return }
        engine.setGuarding(guardHeld)
        engine.setDuck(duckDirectionHeld, active: duckDirectionHeld != 0)
    }

    func publishState() {
        playerLocked = engine.playerLocked
        stamina = engine.player.stamina
    }
}
