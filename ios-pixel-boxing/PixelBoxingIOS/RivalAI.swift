import Foundation

enum RivalDefense: Equatable, Codable, Sendable {
    case duck
    case weave
    case backstep
}

enum RivalMissReason: Equatable, Codable, Sendable {
    case distance
    case angle
    case contact
    case unavailable
}

enum RivalAttackOutcome: Equatable, Codable, Sendable {
    case hit
    case guarded
    case evaded(RivalDefense)
    case missed(RivalMissReason)

    var landed: Bool {
        switch self {
        case .hit, .guarded: true
        case .evaded, .missed: false
        }
    }
}

struct RivalAttackRecord: Codable, Sendable {
    let punch: Punch
    let outcome: RivalAttackOutcome
}

struct RivalAttackEvidence {
    var samples = 0.0
    var hits = 0.0
    var guarded = 0.0
    var headEvades = 0.0
    var backsteps = 0.0
    var distanceMisses = 0.0
    var angleMisses = 0.0
    var contactMisses = 0.0

    var confidence: Double { min(1, max(0, (samples - 2) / 6)) }
    var total: Double { max(1, samples) }

    mutating func note(_ outcome: RivalAttackOutcome, weight: Double) {
        samples += weight
        switch outcome {
        case .hit: hits += weight
        case .guarded: guarded += weight
        case .evaded(.duck), .evaded(.weave): headEvades += weight
        case .evaded(.backstep): backsteps += weight
        case .missed(.distance): distanceMisses += weight
        case .missed(.angle): angleMisses += weight
        case .missed(.contact): contactMisses += weight
        case .missed(.unavailable): samples -= weight
        }
    }
}

struct RivalAttackMemory: Codable, Sendable {
    private(set) var records: [RivalAttackRecord] = []

    mutating func note(_ punch: Punch, outcome: RivalAttackOutcome) {
        guard outcome != .missed(.unavailable) else { return }
        records.append(RivalAttackRecord(punch: punch, outcome: outcome))
        if records.count > 32 { records.removeFirst(records.count - 32) }
    }

    mutating func incorporateRound(_ round: RivalAttackMemory) {
        for record in round.records {
            note(record.punch, outcome: record.outcome)
        }
    }

    func evidence(for punch: Punch? = nil, zone: TargetZone? = nil) -> RivalAttackEvidence {
        var result = RivalAttackEvidence()
        var weight = 1.0
        for record in records.reversed() {
            if (punch == nil || record.punch == punch),
               (zone == nil || CombatData.attacks[record.punch]?.targetZone == zone) {
                result.note(record.outcome, weight: weight)
            }
            weight *= 0.94
        }
        return result
    }

    func adjustWeights(_ weights: inout [String: Double], against opponent: RivalAttackMemory,
                       policy: RivalDifficulty) {
        let learning = min(1, max(0, policy.learningWeight / 2.3))
        for punch in Punch.allCases {
            let own = evidence(for: punch)
            let strength = own.confidence * learning
            let failure = (own.headEvades + own.backsteps + own.distanceMisses
                + own.angleMisses + own.contactMisses) / own.total
            let multiplier = 1 + strength * (0.20 * own.hits / own.total
                - 0.50 * failure - 0.20 * own.guarded / own.total)
            weights[punch.rawValue, default: 0] *= min(1.20, max(0.50, multiplier))

            let observed = opponent.evidence(for: punch)
            let threat = observed.confidence * learning * observed.hits / observed.total
            weights["guard", default: 0] += 0.30 * threat
            if let direction = CombatData.requiredDuck[punch] {
                weights[direction < 0 ? "dodge_left" : "dodge_right", default: 0] += 0.25 * threat
            } else {
                weights["retreat", default: 0] += 0.20 * threat
            }
        }
        let head = evidence(zone: .head)
        let bodySwitch = head.confidence * learning * (head.guarded + head.headEvades) / head.total
        weights[Punch.leftBody.rawValue, default: 0] += 0.75 * bodySwitch
        weights[Punch.rightBody.rawValue, default: 0] += 0.85 * bodySwitch
        let all = evidence()
        let strength = all.confidence * learning / all.total
        weights["advance", default: 0] += strength * (all.distanceMisses + all.backsteps) * 0.60
        weights["cut_off", default: 0] += strength * all.backsteps * 0.65
        weights["circle_left", default: 0] += strength * all.angleMisses * 0.35
        weights["circle_right", default: 0] += strength * all.angleMisses * 0.35
    }
}

struct RivalLearningProfile: Codable, Sendable {
    let playerAttacks: RivalAttackMemory
    let rivalAttacks: RivalAttackMemory
}

/// Opponent execution skill, NOT confidence that a player habit was observed. Bounded, gradual
/// progression keeps early bouts forgiving without giving late rivals extra HP, damage or reach.
struct RivalDifficulty: Equatable {
    let experience: Double
    let championship: Bool

    init(round: Int, championship: Bool = false) {
        experience = 1 - exp(-Double(max(1, round) - 1) / 55)
        self.championship = championship
    }

    var decisionInterval: Double { championship ? min(0.28, 1.0 - 0.80 * experience) : 1.0 - 0.80 * experience }
    var decisionJitter: Double { championship ? min(0.07, 0.16 - 0.10 * experience) : 0.16 - 0.10 * experience }
    var reactionDelay: Double { championship ? min(0.025, 0.24 - 0.18 * experience) : 0.24 - 0.18 * experience }
    var reactionChance: Double { championship ? max(0.66, 0.08 + 0.62 * experience) : 0.08 + 0.62 * experience }
    var learningWeight: Double { championship ? max(1.75, 0.45 + 1.85 * experience) : 0.45 + 1.85 * experience }
    /// Fraction of the same movement speed budget the player has; never faster than that budget.
    var movementEffort: Double { championship ? max(0.84, 0.36 + 0.57 * experience) : 0.36 + 0.57 * experience }
    var combinationChance: Double { championship ? max(0.68, 0.04 + 0.66 * experience) : 0.04 + 0.66 * experience }
    var attackCommitment: Double { championship ? max(1.40, 0.24 + 1.36 * experience) : 0.24 + 1.36 * experience }
    var tacticDuration: Double { championship ? 0.85 : 0.9 + 0.8 * experience }

    func preferredDistance(read: RivalRead, stamina: Double, style: FightStyle = .standard) -> Double {
        // Between exchanges, stay near jab range instead of parking at a body/uppercut distance.
        // A committed entry or queued combination supplies its own shorter target in CombatEngine.
        // Preserve the current standoff: moving it out by the new extension would cancel the
        // player's reach improvement. Entry/follow-up masks still use the actual enlarged range.
        let jab = CombatData.hitRange(.jab, style: style) - CombatData.punchReachExtension
        if stamina < 25 { return jab + 12 }
        switch read {
        case .pressurePattern: return jab + 2
        case .retreatPattern: return jab - 5
        default: return jab - 4 + 2 * (1 - experience)
        }
    }

    /// Prepare one attack when an advance/cutoff is actually selected, not on every movement tick.
    /// The existing next-decision range/stamina checks can execute or discard this intention.
    func entryPunch(read: RivalRead) -> Punch {
        switch read {
        case .guardShell, .retreatPattern: return .rightBody
        case .bodyPattern: return .leftUppercut
        case .duckLeftPattern: return .leftHook
        case .duckRightPattern: return .rightHook
        case .none, .jabPattern, .pressurePattern: return .cross
        }
    }

    func learnedDecision(read: RivalRead, distance: Double, style: FightStyle) -> String? {
        guard championship else { return nil }
        let punch: Punch
        switch read {
        case .none:
            return nil
        case .jabPattern:
            return distance <= CombatData.hitRange(.jab, style: style) + 8 ? "circle_right" : "cut_off"
        case .retreatPattern:
            return "cut_off"
        case .pressurePattern:
            return distance < CombatData.minimumFighterSeparation + 8 ? "dodge_back" : "circle_left"
        case .bodyPattern:
            punch = .leftUppercut
        case .guardShell:
            punch = .rightBody
        case .duckLeftPattern:
            punch = .leftHook
        case .duckRightPattern:
            punch = .cross
        }
        return distance <= CombatData.hitRange(punch, style: style) ? punch.rawValue : "advance"
    }

    func followUp(after punch: Punch, read: RivalRead) -> Punch {
        if championship {
            switch read {
            case .guardShell:
                return [.jab, .cross, .leftHook, .leftUppercut].contains(punch) ? .rightBody : .leftBody
            case .bodyPattern:
                return punch == .leftUppercut ? .rightBody : .leftUppercut
            case .duckLeftPattern:
                return punch == .leftHook ? .rightBody : .leftHook
            case .duckRightPattern:
                return punch == .rightHook ? .leftBody : .rightHook
            case .jabPattern, .retreatPattern:
                if punch == .jab { return .cross }
            case .pressurePattern:
                if punch == .jab || punch == .cross { return .leftHook }
            case .none:
                break
            }
        }
        switch punch {
        case .jab: return read == .guardShell ? .rightBody : .cross
        case .cross: return .leftBody
        case .leftBody: return .rightHook
        case .rightBody: return .leftHook
        case .leftHook, .leftUppercut: return .rightBody
        case .rightHook, .rightUppercut: return .jab
        }
    }

    func recoveryChoice(after punch: Punch, outcome: RivalAttackOutcome, read: RivalRead,
                        stamina: Double, style: FightStyle) -> String? {
        let leading = [.jab, .leftBody, .leftHook, .leftUppercut].contains(punch)
        let reserve = CombatData.dodgeStaminaCost
        func attackChoice(_ next: Punch) -> String {
            let cost = (CombatData.attacks[next]?.staminaCost ?? 100) * style.punchStaminaMultiplier
            return stamina >= cost + reserve ? next.rawValue : "retreat"
        }
        switch outcome {
        case .hit:
            return attackChoice(followUp(after: punch, read: read))
        case .guarded:
            if CombatData.attacks[punch]?.targetZone == .head {
                return attackChoice(leading ? .rightBody : .leftBody)
            }
            return leading ? "circle_right" : "circle_left"
        case .evaded(.duck), .evaded(.weave):
            return stamina > CombatData.minimumGuardStaminaDamage ? "guard" : "retreat"
        case .evaded(.backstep):
            return stamina >= reserve + 10 ? "cut_off" : "retreat"
        case .missed(.distance):
            return stamina >= reserve + 10 ? "advance" : "retreat"
        case .missed(.angle):
            return leading ? "circle_right" : "circle_left"
        case .missed(.contact):
            return "retreat"
        case .missed(.unavailable):
            return nil
        }
    }
}

/// SplitMix64: explicit seeds reproduce isolated combat probes; a normal session supplies a random seed.
struct RivalRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func unit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992
    }
}