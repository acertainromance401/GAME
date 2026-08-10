import Foundation

enum Punch: String, CaseIterable, Codable, Sendable {
    case jab
    case cross
    case leftBody = "left_body"
    case rightBody = "right_body"
    case leftHook = "left_hook"
    case rightHook = "right_hook"
    case leftUppercut = "left_uppercut"
    case rightUppercut = "right_uppercut"

    var label: String {
        switch self {
        case .jab: "JAB"
        case .cross: "CROSS"
        case .leftBody: "L BODY"
        case .rightBody: "R BODY"
        case .leftHook: "L HOOK"
        case .rightHook: "R HOOK"
        case .leftUppercut: "L UPPER"
        case .rightUppercut: "R UPPER"
        }
    }
}

enum TargetZone: Sendable {
    case head
    case body
}

enum AttackFamily: Sendable {
    case straight
    case body
    case hook
    case uppercut
}

struct AttackSpec: Equatable, Sendable {
    let duration: Double
    let activeStart: Double
    let activeEnd: Double
    let damage: Int
    let range: Double
    let halfAngle: Double
    let staminaCost: Double
    let targetZone: TargetZone
    let fistRadius: Double
    let family: AttackFamily
}

enum CombatData {
    static let roundSeconds = 45.0
    static let dodgeStaminaCost = 17.0
    static let enemyDuckDuration = 0.32
    static let backstepStaminaCost = 31.0
    static let staminaRecoveryPerSecond = 8.5
    static let exhaustionDuration = 1.1
    static let exhaustionExposed = 0.28
    static let whiffRecovery = 0.22
    static let duckCounterWindow = 0.42
    static let exposedDamageMultiplier = 1.4
    static let bodyHookCounterMultiplier = 1.2
    static let staggerLock = 0.16
    static let staleThreshold = 2
    static let staleDecay = 0.85
    static let staleFloor = 0.5
    static let guardDamageMultiplier = 0.4
    static let guardStaminaDamageMultiplier = 0.9
    static let minimumGuardStaminaDamage = 5.0
    static let ringMinimum = 70.0
    static let ringMaximum = 520.0
    static let fighterMargin = 34.0
    static let minimumFighterSeparation = 50.0

    static let attacks: [Punch: AttackSpec] = [
        .jab: AttackSpec(duration: 0.24, activeStart: 0.08, activeEnd: 0.15, damage: 6, range: 78, halfAngle: 26, staminaCost: 13, targetZone: .head, fistRadius: 5, family: .straight),
        .cross: AttackSpec(duration: 0.34, activeStart: 0.14, activeEnd: 0.24, damage: 11, range: 60, halfAngle: 20, staminaCost: 18, targetZone: .head, fistRadius: 5.4, family: .straight),
        .leftBody: AttackSpec(duration: 0.32, activeStart: 0.12, activeEnd: 0.22, damage: 9, range: 54, halfAngle: 40, staminaCost: 16, targetZone: .body, fistRadius: 5.2, family: .body),
        .rightBody: AttackSpec(duration: 0.35, activeStart: 0.14, activeEnd: 0.24, damage: 10, range: 56, halfAngle: 38, staminaCost: 17, targetZone: .body, fistRadius: 5.4, family: .body),
        .leftHook: AttackSpec(duration: 0.36, activeStart: 0.16, activeEnd: 0.26, damage: 11, range: 50, halfAngle: 56, staminaCost: 18, targetZone: .head, fistRadius: 5.6, family: .hook),
        .rightHook: AttackSpec(duration: 0.38, activeStart: 0.17, activeEnd: 0.28, damage: 12, range: 52, halfAngle: 50, staminaCost: 19, targetZone: .head, fistRadius: 5.8, family: .hook),
        .leftUppercut: AttackSpec(duration: 0.40, activeStart: 0.18, activeEnd: 0.30, damage: 13, range: 44, halfAngle: 26, staminaCost: 20, targetZone: .head, fistRadius: 5.4, family: .uppercut),
        .rightUppercut: AttackSpec(duration: 0.42, activeStart: 0.19, activeEnd: 0.31, damage: 14, range: 46, halfAngle: 24, staminaCost: 21, targetZone: .head, fistRadius: 5.8, family: .uppercut),
    ]

    static let requiredDuck: [Punch: Int] = [
        .jab: 1,
        .leftHook: 1,
        .leftUppercut: 1,
        .cross: -1,
        .rightHook: -1,
        .rightUppercut: -1,
    ]

    static func comboPunch(base: Punch, guarding: Bool, duckDirection: Int) -> Punch {
        guard base == .jab || base == .cross else { return base }
        if guarding {
            return base == .jab ? .leftUppercut : .rightUppercut
        }
        if duckDirection < 0 {
            return base == .jab ? .leftBody : .rightHook
        }
        if duckDirection > 0 {
            return base == .jab ? .leftHook : .rightBody
        }
        return base == .jab ? .jab : .cross
    }

    static func roundOutcome(playerHP: Int, enemyHP: Int) -> RoundOutcome {
        if playerHP > enemyHP { return .playerWin }
        if playerHP < enemyHP { return .playerLoss }
        return .draw
    }
}

enum CombatCommentary {
    static func attackCall(_ punch: Punch, attacker: String) -> String {
        switch punch {
        case .jab: "\(attacker)의 빠른 왼손 잽! 긴 리치로 거리를 잽니다."
        case .cross: "\(attacker)의 오른손 크로스! 골반 회전까지 실립니다."
        case .leftBody, .rightBody: "\(attacker)가 자세를 낮추고 몸통을 노립니다!"
        case .leftHook, .rightHook: "\(attacker)의 훅! 바깥에서 사각으로 감아칩니다."
        case .leftUppercut, .rightUppercut: "\(attacker)의 어퍼컷! 하체에서 힘을 끌어올립니다."
        }
    }

    static func impact(_ punch: Punch, attacker: String) -> String {
        switch punch {
        case .jab: "\(attacker)의 왼손 잽이 정확히 꽂힙니다!"
        case .cross: "묵직한 오른손 크로스, 제대로 들어갔습니다!"
        case .leftBody, .rightBody: "보디샷이 복부에 박힙니다! 호흡이 흔들립니다."
        case .leftHook, .rightHook: "훅이 옆에서 감아 들어갑니다! 각도가 좋았어요."
        case .leftUppercut, .rightUppercut: "어퍼컷이 턱을 강타합니다! 짧지만 강력합니다."
        }
    }

    static func counter(attacker: String, damage: Int, bodyHookBonus: Bool) -> String {
        if bodyHookBonus {
            return "카운터 적중! \(attacker)의 바디/훅 보너스 피해 \(damage)!"
        }
        return "카운터! \(attacker)가 열린 틈에 \(damage) 피해를 줍니다!"
    }

    static func guardBlock(defender: String) -> String {
        "\(defender)의 단단한 가드! 충격을 크게 줄였습니다."
    }

    static func duckEvade(defender: String) -> String {
        "\(defender)의 완벽한 더킹! 지금이 카운터 타이밍입니다."
    }

    static func whiff(attacker: String) -> String {
        "\(attacker)의 주먹이 허공을 가릅니다. 지금은 카운터 기회!"
    }

    static func knockout(winner: String) -> String {
        "끝났습니다! \(winner)의 완벽한 K.O.!"
    }
}

enum FightPhase: Equatable, Sendable {
    case intro
    case fight
    case paused
    case roundBreak
}

enum RoundOutcome: Equatable, Sendable {
    case playerWin
    case playerLoss
    case draw
}

final class FighterModel {
    let name: String
    let colorName: String
    var x: Double
    var y: Double
    var hp = 100
    var stamina = 100.0
    var facingX = 1.0
    var facingY = 0.0
    var attack: Punch?
    var actionTime = 0.0
    var acted = false
    var guarding = false
    var duckDirection = 0
    var duckTime = 0.0
    var invulnerable = 0.0
    var exhausted = 0.0
    var exposed = 0.0
    var stagger = 0.0
    var hitReaction = 0.0
    var knockedOut = false
    var knockdown = 0.0
    var streakAttack: Punch?
    var streakCount = 0
    var whiffed = false

    init(name: String, colorName: String, x: Double, y: Double) {
        self.name = name
        self.colorName = colorName
        self.x = x
        self.y = y
    }

    func reset(x: Double, y: Double) {
        self.x = x
        self.y = y
        hp = 100
        stamina = 100
        facingX = name == "PLAYER" ? 1 : -1
        facingY = 0
        attack = nil
        actionTime = 0
        acted = false
        guarding = false
        duckDirection = 0
        duckTime = 0
        invulnerable = 0
        exhausted = 0
        exposed = 0
        stagger = 0
        hitReaction = 0
        knockedOut = false
        knockdown = 0
        streakAttack = nil
        streakCount = 0
        whiffed = false
    }
}

struct HabitMemory: Codable, Sendable {
    var attackCounts = Dictionary(uniqueKeysWithValues: Punch.allCases.map { ($0, 0.0) })
    var guardSamples = 0.0
    var duckLeftSamples = 0.0
    var duckRightSamples = 0.0
    var backstepSamples = 0.0
    var pressureSamples = 0.0
    var retreatSamples = 0.0
    var totalSamples = 0.0
    var recentAttack: Punch?
    var repeatStreak = 0

    mutating func noteAttack(_ punch: Punch) {
        attackCounts[punch, default: 0] += 1
        if recentAttack == punch {
            repeatStreak += 1
        } else {
            recentAttack = punch
            repeatStreak = 1
        }
    }

    mutating func sample(deltaTime: Double, guarding: Bool, duckDirection: Int, backstep: Bool, forwardAxis: Double) {
        let sample = max(deltaTime * 8, 0)
        totalSamples += sample
        if guarding { guardSamples += sample }
        if duckDirection < 0 { duckLeftSamples += sample }
        if duckDirection > 0 { duckRightSamples += sample }
        if backstep { backstepSamples += sample }
        if forwardAxis > 0 { pressureSamples += sample * abs(forwardAxis) }
        if forwardAxis < 0 { retreatSamples += sample * abs(forwardAxis) }
    }

    var snapshot: HabitSnapshot {
        let totalAttacks = max(attackCounts.values.reduce(0, +), 1)
        let sampleTotal = max(totalSamples, 1)
        let favorite = Punch.allCases.max { attackCounts[$0, default: 0] < attackCounts[$1, default: 0] } ?? .jab
        return HabitSnapshot(
            favoriteAttack: favorite,
            jabRatio: attackCounts[.jab, default: 0] / totalAttacks,
            bodyRatio: (attackCounts[.leftBody, default: 0] + attackCounts[.rightBody, default: 0]) / totalAttacks,
            guardRatio: guardSamples / sampleTotal,
            duckLeftRatio: duckLeftSamples / sampleTotal,
            duckRightRatio: duckRightSamples / sampleTotal,
            backstepRatio: backstepSamples / sampleTotal,
            pressureRatio: pressureSamples / sampleTotal,
            retreatRatio: retreatSamples / sampleTotal,
            repeatStreak: repeatStreak,
            sampleStrength: min(1, sampleTotal / 18)
        )
    }
}

struct HabitSnapshot: Sendable {
    let favoriteAttack: Punch
    let jabRatio: Double
    let bodyRatio: Double
    let guardRatio: Double
    let duckLeftRatio: Double
    let duckRightRatio: Double
    let backstepRatio: Double
    let pressureRatio: Double
    let retreatRatio: Double
    let repeatStreak: Int
    let sampleStrength: Double

    func adaptation(round: Int) -> Double {
        min(1, max(0.18, 0.18 + 0.16 * Double(max(0, round - 1)) + 0.58 * sampleStrength))
    }

    func enemyWeights(distance: Double, round: Int, playerExposed: Bool) -> [String: Double] {
        let adapt = adaptation(round: round)
        var weights: [String: Double] = [
            Punch.jab.rawValue: 0.1, Punch.cross.rawValue: 0.1,
            Punch.leftBody.rawValue: 0.08, Punch.rightBody.rawValue: 0.08,
            Punch.leftHook.rawValue: 0.08, Punch.rightHook.rawValue: 0.08,
            Punch.leftUppercut.rawValue: 0.06, Punch.rightUppercut.rawValue: 0.06,
            "dodge_left": 0.04, "dodge_right": 0.04, "dodge_back": 0.04,
            "wait": max(0.05, 0.34 - 0.16 * adapt),
        ]

        func add(_ key: String, _ amount: Double) { weights[key, default: 0] += amount }
        if distance > 115 {
            add(Punch.jab.rawValue, 1.55); add(Punch.cross.rawValue, 0.45)
        } else if distance > 78 {
            add(Punch.jab.rawValue, 1); add(Punch.cross.rawValue, 0.95)
            add(Punch.leftHook.rawValue, 0.35); add(Punch.rightHook.rawValue, 0.55)
            add("dodge_left", 0.22); add("dodge_right", 0.22)
        } else {
            add(Punch.leftBody.rawValue, 0.95); add(Punch.rightBody.rawValue, 1.15)
            add(Punch.leftHook.rawValue, 0.8); add(Punch.rightHook.rawValue, 0.95)
            add(Punch.leftUppercut.rawValue, 0.45); add(Punch.rightUppercut.rawValue, 0.65)
            add("dodge_back", 0.28)
        }
        if guardRatio > 0.22 { add(Punch.leftBody.rawValue, 0.95 * adapt); add(Punch.rightBody.rawValue, 1.2 * adapt) }
        if duckRightRatio > 0.16 { add(Punch.cross.rawValue, 1.05 * adapt); add(Punch.rightHook.rawValue, 0.95 * adapt); add(Punch.rightUppercut.rawValue, 0.7 * adapt) }
        if duckLeftRatio > 0.16 { add(Punch.jab.rawValue, 0.85 * adapt); add(Punch.leftHook.rawValue, 0.8 * adapt); add(Punch.leftUppercut.rawValue, 0.6 * adapt) }
        if jabRatio > 0.34 || favoriteAttack == .jab { add(Punch.cross.rawValue, 0.9 * adapt); add(Punch.rightHook.rawValue, 0.55 * adapt); add("dodge_right", 0.35 * adapt) }
        if bodyRatio > 0.3 { add(Punch.leftUppercut.rawValue, 0.45 * adapt); add(Punch.rightUppercut.rawValue, 0.7 * adapt) }
        if pressureRatio > 0.2 { add("dodge_back", 0.75 * adapt); add(Punch.rightHook.rawValue, 0.55 * adapt); add(Punch.leftHook.rawValue, 0.45 * adapt) }
        if backstepRatio > 0.14 || retreatRatio > 0.18 { add(Punch.jab.rawValue, 0.7 * adapt); add(Punch.cross.rawValue, 0.45 * adapt); weights["wait", default: 0] *= 0.8 }
        if repeatStreak >= 3 { add("dodge_left", 0.35 * adapt); add("dodge_right", 0.35 * adapt) }
        if playerExposed {
            add(Punch.cross.rawValue, 1.8); add(Punch.rightUppercut.rawValue, 1.4); add(Punch.rightHook.rawValue, 0.9)
            weights["wait"] = 0.05
        }
        return weights
    }
}

struct CombatSnapshot: Sendable {
    let phase: FightPhase
    let round: Int
    let time: Double
    let playerHP: Int
    let enemyHP: Int
    let playerStamina: Double
    let enemyStamina: Double
    let playerScore: Int
    let enemyScore: Int
    let adaptation: Double
    let favoriteAttack: Punch
    let message: String
    let successfulDodgeCount: Int
}

@MainActor
final class CombatEngine {
    let player = FighterModel(name: "PLAYER", colorName: "cyan", x: 170, y: 295)
    let enemy = FighterModel(name: "RIVAL", colorName: "red", x: 420, y: 295)

    private(set) var phase = FightPhase.intro
    private(set) var round = 1
    private(set) var roundTime = CombatData.roundSeconds
    private(set) var playerScore = 0
    private(set) var enemyScore = 0
    private(set) var successfulDodgeCount = 0
    private(set) var message = "상대는 당신을 기억한다"
    private(set) var habits: HabitMemory
    var moveX = 0.0
    var moveY = 0.0

    private var previousPhase: FightPhase?
    private var enemyDecisionTimer = 0.5
    private var roundBreakTimer = 0.0
    private var advancesRoundAfterBreak = false
    private var roundStartHabits: HabitMemory
    private let defaults: UserDefaults?

    init(persistHabits: Bool = true) {
        defaults = persistHabits ? .standard : nil
        let initialHabits: HabitMemory
        if let data = defaults?.data(forKey: "pixelBoxingHabitMemory"),
           let decoded = try? JSONDecoder().decode(HabitMemory.self, from: data) {
            initialHabits = decoded
        } else {
            initialHabits = HabitMemory()
        }
        habits = initialHabits
        roundStartHabits = initialHabits
    }

    var snapshot: CombatSnapshot {
        let habit = habits.snapshot
        return CombatSnapshot(
            phase: phase, round: round, time: roundTime,
            playerHP: player.hp, enemyHP: enemy.hp,
            playerStamina: player.stamina, enemyStamina: enemy.stamina,
            playerScore: playerScore, enemyScore: enemyScore,
            adaptation: habit.adaptation(round: round),
            favoriteAttack: habit.favoriteAttack, message: message,
            successfulDodgeCount: successfulDodgeCount
        )
    }

    func startSession() {
        round = 1
        playerScore = 0
        enemyScore = 0
        successfulDodgeCount = 0
        startRound()
    }

    func startRound() {
        player.reset(x: 170, y: 295)
        enemy.reset(x: 420, y: 295)
        phase = .fight
        roundTime = CombatData.roundSeconds
        roundBreakTimer = 0
        advancesRoundAfterBreak = false
        enemyDecisionTimer = 0.55
        roundStartHabits = habits
        message = "FIGHT"
    }

    func togglePause() {
        if phase == .fight {
            previousPhase = phase
            phase = .paused
            message = "PAUSED"
        } else if phase == .paused {
            phase = previousPhase ?? .fight
            message = "FIGHT"
        }
    }

    func resetLearning() {
        habits = HabitMemory()
        roundStartHabits = habits
        defaults?.removeObject(forKey: "pixelBoxingHabitMemory")
        startSession()
        message = "학습 메모리 초기화 · ROUND 1"
    }

    func setMove(x: Double, y: Double) {
        moveX = x
        moveY = y
    }

    func setGuarding(_ active: Bool) {
        if !active {
            player.guarding = false
            return
        }
        guard phase == .fight, player.attack == nil, player.exhausted <= 0 else { return }
        player.guarding = true
    }

    func setDuck(_ direction: Int, active: Bool) {
        if !active {
            player.duckDirection = 0
            return
        }
        guard phase == .fight, player.attack == nil, player.exhausted <= 0 else { return }
        player.duckDirection = min(1, max(-1, direction))
    }

    @discardableResult
    func backstep() -> Bool {
        guard phase == .fight, player.attack == nil, player.stagger <= 0, player.exhausted <= 0,
              player.stamina >= CombatData.backstepStaminaCost else { return false }
        player.stamina -= CombatData.backstepStaminaCost
        player.invulnerable = 0.22
        let dx = -player.facingX * 34
        let dy = -player.facingY * 34
        player.x = clampToRing(player.x + dx)
        player.y = clampToRing(player.y + dy)
        message = "BACKSTEP"
        if player.stamina <= 0 { exhaust(player) }
        return true
    }

    @discardableResult
    func startAttack(_ fighter: FighterModel, punch: Punch, recordsHabit: Bool = false) -> Bool {
        guard phase == .fight, fighter.attack == nil, fighter.stagger <= 0, fighter.exhausted <= 0,
              let spec = CombatData.attacks[punch], fighter.stamina >= spec.staminaCost else { return false }
        if fighter.streakAttack == punch {
            fighter.streakCount += 1
        } else {
            fighter.streakAttack = punch
            fighter.streakCount = 1
        }
        fighter.attack = punch
        fighter.actionTime = 0
        fighter.acted = false
        fighter.whiffed = false
        fighter.guarding = false
        fighter.stamina = max(0, fighter.stamina - spec.staminaCost)
        message = CombatCommentary.attackCall(punch, attacker: fighter.name)
        if fighter.stamina <= 0 { exhaust(fighter) }
        if recordsHabit {
            habits.noteAttack(punch)
        }
        return true
    }

    func update(deltaTime rawDeltaTime: Double) {
        let deltaTime = min(0.05, max(0, rawDeltaTime))
        guard deltaTime > 0 else { return }
        if phase == .roundBreak {
            roundBreakTimer -= deltaTime
            updateKnockdowns(deltaTime)
            if roundBreakTimer <= 0 {
                if advancesRoundAfterBreak { round += 1 }
                startRound()
            }
            return
        }
        guard phase == .fight else { return }

        roundTime = max(0, roundTime - deltaTime)
        updateFacing()
        updatePlayerMovement(deltaTime)
        sampleHabits(deltaTime)
        updateFighter(player, deltaTime)
        updateFighter(enemy, deltaTime)
        updateEnemy(deltaTime)

        if roundTime <= 0 {
            finishRound(
                outcome: CombatData.roundOutcome(playerHP: player.hp, enemyHP: enemy.hp),
                knockout: false
            )
        }
    }

    private func updatePlayerMovement(_ deltaTime: Double) {
        guard player.attack == nil, player.stagger <= 0, player.exhausted <= 0, !player.guarding else { return }
        let magnitude = hypot(moveX, moveY)
        guard magnitude > 0.01 else { return }
        let forward = moveX / max(1, magnitude)
        let strafe = moveY / max(1, magnitude)
        let rightX = -player.facingY
        let rightY = player.facingX
        let worldX = forward * player.facingX + strafe * rightX
        let worldY = forward * player.facingY + strafe * rightY
        let speed = player.duckDirection == 0 ? 210.0 : 105.0
        moveFighter(
            player,
            byX: worldX * speed * deltaTime,
            byY: worldY * speed * deltaTime,
            avoiding: enemy
        )
    }

    private func updateFacing() {
        let dx = enemy.x - player.x
        let dy = enemy.y - player.y
        let magnitude = max(0.001, hypot(dx, dy))
        player.facingX = dx / magnitude
        player.facingY = dy / magnitude
        enemy.facingX = -player.facingX
        enemy.facingY = -player.facingY
    }

    private func updateFighter(_ fighter: FighterModel, _ deltaTime: Double) {
        if fighter === enemy, fighter.duckTime > 0 {
            fighter.duckTime = max(0, fighter.duckTime - deltaTime)
            if fighter.duckTime == 0 { fighter.duckDirection = 0 }
        }
        fighter.invulnerable = max(0, fighter.invulnerable - deltaTime)
        fighter.exhausted = max(0, fighter.exhausted - deltaTime)
        fighter.exposed = max(0, fighter.exposed - deltaTime)
        fighter.stagger = max(0, fighter.stagger - deltaTime)
        fighter.hitReaction = max(0, fighter.hitReaction - deltaTime)
        if fighter.exhausted <= 0, fighter.attack == nil, !fighter.guarding, fighter.duckDirection == 0 {
            fighter.stamina = min(100, fighter.stamina + CombatData.staminaRecoveryPerSecond * deltaTime)
        }
        guard let punch = fighter.attack, let spec = CombatData.attacks[punch] else { return }
        let previous = fighter.actionTime
        fighter.actionTime += deltaTime
        if !fighter.acted, previous < spec.activeStart, fighter.actionTime >= spec.activeStart {
            fighter.acted = attemptHit(attacker: fighter, defender: fighter === player ? enemy : player, punch: punch)
        }
        if fighter.actionTime >= spec.duration {
            if !fighter.acted {
                fighter.whiffed = true
                fighter.exposed = max(fighter.exposed, CombatData.whiffRecovery)
                message = CombatCommentary.whiff(attacker: fighter.name)
            }
            fighter.attack = nil
            fighter.actionTime = 0
            fighter.acted = false
        }
    }

    @discardableResult
    private func attemptHit(attacker: FighterModel, defender: FighterModel, punch: Punch) -> Bool {
        guard let spec = CombatData.attacks[punch], defender.invulnerable <= 0 else { return false }
        let dx = defender.x - attacker.x
        let dy = defender.y - attacker.y
        let distance = hypot(dx, dy)
        guard distance <= spec.range + 17 else { return false }
        let direction = max(0.001, distance)
        let dot = max(-1, min(1, (dx / direction) * attacker.facingX + (dy / direction) * attacker.facingY))
        guard acos(dot) * 180 / .pi <= spec.halfAngle else { return false }

        if let requiredDuck = CombatData.requiredDuck[punch], defender.duckDirection == requiredDuck {
            attacker.exposed = max(attacker.exposed, CombatData.duckCounterWindow)
            if defender === player { successfulDodgeCount += 1 }
            message = CombatCommentary.duckEvade(defender: defender.name)
            return false
        }

        let countered = defender.exposed > 0
        let staleStage = max(0, attacker.streakCount - CombatData.staleThreshold)
        let staleMultiplier = max(CombatData.staleFloor, pow(CombatData.staleDecay, Double(staleStage)))
        var damage = max(1, Int((Double(spec.damage) * staleMultiplier).rounded()))
        if defender.exposed > 0 {
            damage = Int((Double(damage) * CombatData.exposedDamageMultiplier).rounded())
            if spec.family == .body || spec.family == .hook {
                damage = Int((Double(damage) * CombatData.bodyHookCounterMultiplier).rounded())
            }
        }
        if defender.guarding {
            damage = max(1, Int((Double(damage) * CombatData.guardDamageMultiplier).rounded()))
            let staminaDamage = max(
                CombatData.minimumGuardStaminaDamage,
                Double(spec.damage) * CombatData.guardStaminaDamageMultiplier
            )
            defender.stamina = max(0, defender.stamina - staminaDamage)
            if defender.stamina <= 0 {
                defender.guarding = false
                exhaust(defender)
                message = "가드 브레이크! \(defender.name)의 방어가 무너집니다."
            } else {
                message = CombatCommentary.guardBlock(defender: defender.name)
            }
        } else if countered {
            message = CombatCommentary.counter(
                attacker: attacker.name,
                damage: damage,
                bodyHookBonus: spec.family == .body || spec.family == .hook
            )
        } else {
            message = CombatCommentary.impact(punch, attacker: attacker.name)
        }
        defender.hp = max(0, defender.hp - damage)
        defender.hitReaction = 0.24
        defender.stagger = max(defender.stagger, CombatData.staggerLock)
        if defender.attack != nil {
            defender.attack = nil
            defender.exposed = max(defender.exposed, CombatData.whiffRecovery)
        }
        if defender.hp == 0 {
            defender.knockedOut = true
            finishRound(outcome: defender === enemy ? .playerWin : .playerLoss, knockout: true)
        }
        return true
    }

    private func updateEnemy(_ deltaTime: Double) {
        guard enemy.attack == nil, enemy.stagger <= 0, enemy.exhausted <= 0 else { return }
        guard enemy.duckDirection == 0 else { return }
        let dx = player.x - enemy.x
        let dy = player.y - enemy.y
        let distance = hypot(dx, dy)
        if distance > 86 {
            let speed = 46 + 22 * habits.snapshot.adaptation(round: round)
            moveFighter(
                enemy,
                byX: dx / max(1, distance) * speed * deltaTime,
                byY: dy / max(1, distance) * speed * deltaTime,
                avoiding: player
            )
        }
        enemyDecisionTimer -= deltaTime
        guard enemyDecisionTimer <= 0 else { return }
        let adaptation = habits.snapshot.adaptation(round: round)
        enemyDecisionTimer = max(0.18, 0.68 - 0.28 * adaptation) + Double.random(in: 0...0.18)
        let choice = weightedChoice(habits.snapshot.enemyWeights(distance: distance, round: round, playerExposed: player.exposed > 0))
        performEnemyDecision(choice)
    }

    @discardableResult
    func performEnemyDecision(_ choice: String) -> Bool {
        if let punch = Punch(rawValue: choice) {
            return startAttack(enemy, punch: punch)
        } else if choice == "dodge_left" || choice == "dodge_right" {
            guard enemy.stamina >= CombatData.dodgeStaminaCost else { return false }
            enemy.stamina -= CombatData.dodgeStaminaCost
            enemy.duckDirection = choice == "dodge_left" ? -1 : 1
            enemy.duckTime = CombatData.enemyDuckDuration
            message = "RIVAL의 \(choice == "dodge_left" ? "왼쪽" : "오른쪽") 더킹!"
            return true
        } else if choice == "dodge_back", enemy.stamina >= CombatData.dodgeStaminaCost {
            enemy.stamina -= CombatData.dodgeStaminaCost
            enemy.invulnerable = 0.18
            enemy.x = clampToRing(enemy.x - enemy.facingX * 24)
            enemy.y = clampToRing(enemy.y - enemy.facingY * 24)
            message = "RIVAL이 백스텝으로 거리를 벌립니다."
            return true
        }
        return false
    }

    private func weightedChoice(_ weights: [String: Double]) -> String {
        let total = weights.values.reduce(0, +)
        var cursor = Double.random(in: 0..<max(total, 0.001))
        for (key, weight) in weights.sorted(by: { $0.key < $1.key }) {
            cursor -= max(0, weight)
            if cursor <= 0 { return key }
        }
        return "wait"
    }

    private func sampleHabits(_ deltaTime: Double) {
        let forwardAxis = moveX * player.facingX + moveY * player.facingY
        habits.sample(deltaTime: deltaTime, guarding: player.guarding, duckDirection: player.duckDirection, backstep: player.invulnerable > 0, forwardAxis: forwardAxis)
    }

    func finishRound(outcome: RoundOutcome, knockout: Bool) {
        guard phase == .fight else { return }
        phase = .roundBreak
        advancesRoundAfterBreak = outcome == .playerWin
        switch outcome {
        case .playerWin:
            playerScore += 1
        case .playerLoss:
            enemyScore += 1
            habits = roundStartHabits
        case .draw:
            break
        }
        roundBreakTimer = knockout ? 2.2 : 1.7
        if knockout {
            message = CombatCommentary.knockout(winner: outcome == .playerWin ? player.name : enemy.name)
        } else {
            switch outcome {
            case .playerWin: message = "ROUND WON"
            case .playerLoss: message = "ROUND LOST - RIVAL 학습 롤백"
            case .draw: message = "DRAW - 동일 HP"
            }
        }
        saveHabits()
    }

    private func updateKnockdowns(_ deltaTime: Double) {
        for fighter in [player, enemy] where fighter.knockedOut {
            fighter.knockdown = min(1, fighter.knockdown + deltaTime / 0.9)
        }
    }

    private func exhaust(_ fighter: FighterModel) {
        fighter.exhausted = max(fighter.exhausted, CombatData.exhaustionDuration)
        fighter.exposed = max(fighter.exposed, CombatData.exhaustionExposed)
        if fighter === player { message = "GASSED OUT" }
    }

    private func saveHabits() {
        guard let defaults, let data = try? JSONEncoder().encode(habits) else { return }
        defaults.set(data, forKey: "pixelBoxingHabitMemory")
    }

    private func moveFighter(_ fighter: FighterModel, byX deltaX: Double, byY deltaY: Double, avoiding other: FighterModel) {
        var candidateX = clampToRing(fighter.x + deltaX)
        var candidateY = clampToRing(fighter.y + deltaY)
        let separationX = candidateX - other.x
        let separationY = candidateY - other.y
        let distance = hypot(separationX, separationY)

        if distance < CombatData.minimumFighterSeparation {
            let fallbackX = fighter.x - other.x
            let fallbackY = fighter.y - other.y
            let fallbackDistance = hypot(fallbackX, fallbackY)
            let directionX = distance > 0.001 ? separationX / distance : fallbackX / max(0.001, fallbackDistance)
            let directionY = distance > 0.001 ? separationY / distance : fallbackY / max(0.001, fallbackDistance)
            candidateX = clampToRing(other.x + directionX * CombatData.minimumFighterSeparation)
            candidateY = clampToRing(other.y + directionY * CombatData.minimumFighterSeparation)
        }

        fighter.x = candidateX
        fighter.y = candidateY
    }

    private func clampToRing(_ value: Double) -> Double {
        min(CombatData.ringMaximum - CombatData.fighterMargin, max(CombatData.ringMinimum + CombatData.fighterMargin, value))
    }
}
