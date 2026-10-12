/// Held intent, independent of a punch temporarily clearing the fighter's defensive pose.
/// Last-pressed duck wins; releasing it restores the other finger's still-held direction.
struct CombatModifiers: Equatable {
    var guarding = false
    private var ducks: [Int] = []
    var duckDirection: Int { ducks.last ?? 0 }

    mutating func setDuck(_ direction: Int, active: Bool) {
        guard direction == -1 || direction == 1 else { return }
        if active {
            guard !ducks.contains(direction) else { return }
            ducks.append(direction)
        } else {
            ducks.removeAll { $0 == direction }
        }
    }

    func punch(base: Punch) -> Punch {
        CombatData.comboPunch(base: base, guarding: guarding, duckDirection: duckDirection)
    }

    mutating func reset() { self = CombatModifiers() }
}