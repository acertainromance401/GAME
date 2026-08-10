import SwiftUI
import UIKit

@MainActor
final class GameController: ObservableObject {
    private struct MovementControl: Hashable {
        let forward: Int
        let strafe: Int
    }

    let engine = CombatEngine()
    @Published private(set) var snapshot: CombatSnapshot
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
    }

    func publishSnapshot() {
        let nextSnapshot = engine.snapshot
        if nextSnapshot.successfulDodgeCount > snapshot.successfulDodgeCount {
            let feedback = UINotificationFeedbackGenerator()
            feedback.prepare()
            feedback.notificationOccurred(.success)
        } else if nextSnapshot.enemyHP < snapshot.enemyHP {
            let damage = snapshot.enemyHP - nextSnapshot.enemyHP
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: min(1, 0.45 + CGFloat(damage) / 20))
        } else if nextSnapshot.playerHP < snapshot.playerHP {
            let damage = snapshot.playerHP - nextSnapshot.playerHP
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: min(1, 0.4 + CGFloat(damage) / 22))
        }
        snapshot = nextSnapshot
    }

    func start() {
        engine.startSession()
        publishSnapshot()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func pause() {
        engine.togglePause()
        publishSnapshot()
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
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
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
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.58)
        }
    }

    func comboAttack(base: Punch) {
        attack(CombatData.comboPunch(base: base, guarding: guardHeld, duckDirection: duckDirectionHeld))
    }

    func backstep() {
        if engine.backstep() {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.72)
            publishSnapshot()
        }
    }

    func synchronizeHeldControls() {
        guard engine.player.attack == nil else { return }
        engine.setGuarding(guardHeld)
        engine.setDuck(duckDirectionHeld, active: duckDirectionHeld != 0)
    }
}
