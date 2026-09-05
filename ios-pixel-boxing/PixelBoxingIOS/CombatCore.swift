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

enum FightStyle: String, Codable, CaseIterable, Sendable {
    case standard
    case outboxing = "out_boxing"
    case infighting = "in_fighting"

    // NOTE: the underlying `standard`/`infighting` case identifiers (and their Codable rawValues) are kept
    // unchanged on purpose so existing saved profiles/settings don't break, even though their DISPLAYED
    // names were renamed: `.standard` now reads as "인파이터"/"In-Fighter" and `.infighting` now reads as
    // "슬러거"/"Slugger".
    func label(for language: AppLanguage) -> String {
        switch self {
        case .standard:
            switch language {
            case .korean: "인파이터"
            case .english: "In-Fighter"
            case .japanese: "インファイター"
            }
        case .outboxing:
            switch language {
            case .korean: "아웃복싱"
            case .english: "Outboxing"
            case .japanese: "アウトボクシング"
            }
        case .infighting:
            switch language {
            case .korean: "슬러거"
            case .english: "Slugger"
            case .japanese: "スラッガー"
            }
        }
    }

    func summary(for language: AppLanguage) -> String {
        switch self {
        case .standard:
            switch language {
            case .korean: "균형 잡힌 기본 폼 · 낮은 스태미나 소모로 연타에 유리"
            case .english: "Balanced fundamentals · Low stamina cost for rapid combos"
            case .japanese: "バランスの取れた基本フォーム・低スタミナ消費で連打に有利"
            }
        case .outboxing:
            switch language {
            case .korean: "빠른 풋워크와 넓은 리치 · 공격력은 다소 약함"
            case .english: "Fast footwork, long reach · Trades away some power"
            case .japanese: "俊敏なフットワークと長いリーチ・パワーはやや控えめ"
            }
        case .infighting:
            switch language {
            case .korean: "느리지만 강한 한 방 · 가드를 낮춘 저돌적인 자세"
            case .english: "Slow but hard-hitting · An aggressive, low-guard stance"
            case .japanese: "遅いが一撃が重い・ガードを下げた獰猛な構え"
            }
        }
    }

    var reachMultiplier: Double {
        switch self {
        case .standard: 1.0
        case .outboxing: 1.12
        case .infighting: 0.90
        }
    }

    // Slugger (`.infighting`) trades reach/mobility for flat, unconditional power -- every landed punch
    // simply hits harder everywhere, not just up close, unlike the old close-range-only framing.
    var damageMultiplier: Double {
        switch self {
        case .standard: 1.0
        case .outboxing: 0.90
        case .infighting: 1.16
        }
    }

    /// Punch stamina cost. In-Fighter (`.standard`) gets a modest discount so it can throw rapid combo
    /// strings without gassing out. Slugger's (`.infighting`) aggressive up-close identity needs its own
    /// offensive payoff too, so it keeps an even bigger discount to sustain combos once it closes distance.
    var punchStaminaMultiplier: Double {
        switch self {
        case .standard: 0.88
        case .outboxing: 1.0
        case .infighting: 0.85
        }
    }

    var backstepStaminaMultiplier: Double {
        switch self {
        case .standard: 1.0
        case .outboxing: 0.6
        case .infighting: 1.0
        }
    }

    var guardStaminaMultiplier: Double {
        switch self {
        case .standard: 1.0
        case .outboxing: 1.0
        case .infighting: 0.7
        }
    }

    var guardDamageMultiplier: Double {
        switch self {
        case .standard: 1.0
        case .outboxing: 1.2
        case .infighting: 0.8
        }
    }

    /// Overall footwork/backstep speed. The single biggest "felt" difference — outboxers are noticeably
    /// quicker on their feet every time the joystick is used, infighters are noticeably more sluggish.
    var moveSpeedMultiplier: Double {
        switch self {
        case .standard: 1.0
        case .outboxing: 1.22
        case .infighting: 0.86
        }
    }

    /// Amplitude of a continuous idle weave/sway applied even while standing still, so the stance keeps
    /// reading as a different style over time and not just as a single static pose.
    var idleWeaveAmount: Float {
        switch self {
        case .standard: 0.015
        case .outboxing: 0.05
        case .infighting: 0.006
        }
    }

    /// Lateral foot/knee spread. Outboxers plant a wider, bouncier base; infighters keep a tight, compact base.
    var stanceWidth: Float {
        switch self {
        case .standard: 0
        case .outboxing: 0.075
        case .infighting: -0.045
        }
    }

    /// Persistent torso roll bias. Infighters hunch in toward their opponent; outboxers lean away, staying upright.
    var leanBias: Float {
        switch self {
        case .standard: 0
        case .outboxing: -0.07
        case .infighting: 0.11
        }
    }

    /// Persistent forward/back torso pitch. Infighters bend forward at the waist; outboxers stand tall.
    var pitchBias: Float {
        switch self {
        case .standard: 0
        case .outboxing: -0.08
        case .infighting: 0.15
        }
    }

    /// Torso build scale (width, height, depth) layered on top of the rig's base torso proportions, so each
    /// style reads as a visibly different physique rather than just a different stance. Standard keeps the
    /// rig's neutral baseline; outboxing reads leaner/taller; infighting reads stockier/bulkier.
    var torsoWidthScale: Float {
        switch self {
        case .standard: 1.0
        case .outboxing: 0.90
        case .infighting: 1.09
        }
    }

    var torsoHeightScale: Float {
        switch self {
        case .standard: 1.0
        case .outboxing: 1.03
        case .infighting: 0.97
        }
    }

    var torsoDepthScale: Float {
        switch self {
        case .standard: 1.0
        case .outboxing: 0.88
        case .infighting: 1.10
        }
    }

    /// Limb (arm/leg) thickness scale layered on top of each bone's base radius — pairs with the torso build
    /// scale above so outboxers read leaner-limbed and infighters read thicker/stockier-limbed.
    var limbRadiusScale: Float {
        switch self {
        case .standard: 1.0
        case .outboxing: 0.88
        case .infighting: 1.18
        }
    }

    /// Shoulder-joint ball scale, layered separately from `limbRadiusScale` so the shoulder bump specifically
    /// can be tuned (e.g. toned down slightly for Slugger) without also changing arm/leg bone thickness.
    var shoulderJointScale: Float {
        switch self {
        case .standard: 1.0
        case .outboxing: 0.88
        case .infighting: 1.06
        }
    }
}

enum OutfitID: String, Codable, CaseIterable, Sendable {
    case classic
    case champion
    case blackout
    case gymGray
    case unscathed
    case champ
    case streak
    case masteryInFighter
    case masteryOutboxer
    case masterySlugger

    func label(for language: AppLanguage) -> String {
        switch self {
        case .classic:
            switch language {
            case .korean: "클래식"
            case .english: "Classic"
            case .japanese: "クラシック"
            }
        case .champion:
            switch language {
            case .korean: "챔피언 골드"
            case .english: "Champion Gold"
            case .japanese: "チャンピオンゴールド"
            }
        case .blackout:
            switch language {
            case .korean: "블랙아웃"
            case .english: "Blackout"
            case .japanese: "ブラックアウト"
            }
        case .gymGray:
            switch language {
            case .korean: "짐 그레이"
            case .english: "Gym Gray"
            case .japanese: "ジムグレー"
            }
        case .unscathed:
            switch language {
            case .korean: "언터처블"
            case .english: "Untouchable"
            case .japanese: "アンタッチャブル"
            }
        case .champ:
            switch language {
            case .korean: "챔프"
            case .english: "Champ"
            case .japanese: "チャンプ"
            }
        case .streak:
            switch language {
            case .korean: "블레이즈"
            case .english: "Blaze"
            case .japanese: "ブレイズ"
            }
        case .masteryInFighter:
            switch language {
            case .korean: "스틸가드"
            case .english: "Steel Guard"
            case .japanese: "スチールガード"
            }
        case .masteryOutboxer:
            switch language {
            case .korean: "고스트 스텝"
            case .english: "Ghost Step"
            case .japanese: "ゴーストステップ"
            }
        case .masterySlugger:
            switch language {
            case .korean: "헤비웨이트"
            case .english: "Heavyweight"
            case .japanese: "ヘビー級"
            }
        }
    }

    /// What stat (and threshold) permanently unlocks this outfit. `.none` (Classic) is always available.
    private enum UnlockRequirement {
        case none
        case highestRound(Int)
        case totalWins(Int)
        case gymSeconds(Double)
        case perfectRoundWins(Int)
        case winStreak(Int)
        case styleWins(FightStyle, Int)
    }

    private var unlockRequirement: UnlockRequirement {
        switch self {
        case .classic: .none
        case .champion: .highestRound(20)
        case .blackout: .totalWins(100)
        case .gymGray: .gymSeconds(24 * 3600)
        case .unscathed: .perfectRoundWins(10)
        case .champ: .totalWins(1000)
        case .streak: .winStreak(20)
        case .masteryInFighter: .styleWins(.standard, 50)
        case .masteryOutboxer: .styleWins(.outboxing, 50)
        case .masterySlugger: .styleWins(.infighting, 50)
        }
    }

    /// Checks this outfit's unlock condition against the player's current stats. All stats are passed in
    /// (rather than this type reaching into `GameController`/`CombatEngine` itself) so `OutfitID` stays a
    /// plain, dependency-free model type.
    func isUnlocked(
        highestRound: Int, totalWins: Int, gymSeconds: Double, perfectRoundWins: Int,
        bestWinStreak: Int, winsByStyle: [String: Int]
    ) -> Bool {
        switch unlockRequirement {
        case .none: true
        case .highestRound(let required): highestRound >= required
        case .totalWins(let required): totalWins >= required
        case .gymSeconds(let required): gymSeconds >= required
        case .perfectRoundWins(let required): perfectRoundWins >= required
        case .winStreak(let required): bestWinStreak >= required
        case .styleWins(let style, let required): (winsByStyle[style.rawValue] ?? 0) >= required
        }
    }

    /// A short human-readable description of this outfit's unlock condition, shown next to it while locked.
    /// Empty for `.classic`, which has no condition (always available).
    func unlockDescription(for language: AppLanguage) -> String {
        switch unlockRequirement {
        case .none:
            ""
        case .highestRound(let required):
            switch language {
            case .korean: "ROUND \(required) 도달 시 해제"
            case .english: "Unlocks at ROUND \(required)"
            case .japanese: "ROUND \(required)到達で解放"
            }
        case .totalWins(let required):
            switch language {
            case .korean: "누적 승수 \(required)판 달성 시 해제"
            case .english: "Unlocks after \(required) total wins"
            case .japanese: "累計勝利\(required)勝で解放"
            }
        case .gymSeconds(let required):
            switch language {
            case .korean: "체육관 누적 이용 \(Int(required / 3600))시간 달성 시 해제"
            case .english: "Unlocks after \(Int(required / 3600)) cumulative hours in the Gym"
            case .japanese: "ジム累計利用\(Int(required / 3600))時間で解放"
            }
        case .perfectRoundWins(let required):
            switch language {
            case .korean: "무피격 승리 라운드 \(required)회 달성 시 해제"
            case .english: "Unlocks after winning \(required) rounds without taking a hit"
            case .japanese: "無被弾勝利ラウンド\(required)回で解放"
            }
        case .winStreak(let required):
            switch language {
            case .korean: "\(required)연승 달성 시 해제"
            case .english: "Unlocks after a \(required)-win streak"
            case .japanese: "\(required)連勝達成で解放"
            }
        case .styleWins(let style, let required):
            switch language {
            case .korean: "\(style.label(for: .korean)) 스타일로 \(required)판 승리 시 해제"
            case .english: "Unlocks after \(required) wins using \(style.label(for: .english))"
            case .japanese: "\(style.label(for: .japanese))スタイルで\(required)勝達成で解放"
            }
        }
    }
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
    /// Retreating (moving straight back) is slower than closing distance, so backpedaling alone is a
    /// weaker substitute for guarding/ducking and players can't rely purely on distance control to stay safe.
    static let backwardMoveSpeedMultiplier = 0.5
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
    static func attackCall(_ punch: Punch, attacker: String, language: AppLanguage) -> String {
        switch punch {
        case .jab:
            switch language {
            case .korean: "\(attacker)의 빠른 왼손 잽! 긴 리치로 거리를 잽니다."
            case .english: "\(attacker)'s quick left jab! Using the long reach to gauge distance."
            case .japanese: "\(attacker)の素早い左ジャブ!長いリーチで距離を測ります。"
            }
        case .cross:
            switch language {
            case .korean: "\(attacker)의 오른손 크로스! 골반 회전까지 실립니다."
            case .english: "\(attacker)'s right cross! Full hip rotation behind it."
            case .japanese: "\(attacker)の右クロス!腰の回転まで乗っています。"
            }
        case .leftBody, .rightBody:
            switch language {
            case .korean: "\(attacker)가 자세를 낮추고 몸통을 노립니다!"
            case .english: "\(attacker) drops low, going for the body!"
            case .japanese: "\(attacker)が姿勢を落として胴を狙います!"
            }
        case .leftHook, .rightHook:
            switch language {
            case .korean: "\(attacker)의 훅! 바깥에서 사각으로 감아칩니다."
            case .english: "\(attacker)'s hook! Wrapping in from a blind angle."
            case .japanese: "\(attacker)のフック!外側から死角を突いて振り抜きます。"
            }
        case .leftUppercut, .rightUppercut:
            switch language {
            case .korean: "\(attacker)의 어퍼컷! 하체에서 힘을 끌어올립니다."
            case .english: "\(attacker)'s uppercut! Driving the power up from the legs."
            case .japanese: "\(attacker)のアッパーカット!下半身から力を引き上げます。"
            }
        }
    }

    static func impact(_ punch: Punch, attacker: String, language: AppLanguage) -> String {
        switch punch {
        case .jab:
            switch language {
            case .korean: "\(attacker)의 왼손 잽이 정확히 꽂힙니다!"
            case .english: "\(attacker)'s left jab lands clean!"
            case .japanese: "\(attacker)の左ジャブが正確に決まります!"
            }
        case .cross:
            switch language {
            case .korean: "묵직한 오른손 크로스, 제대로 들어갔습니다!"
            case .english: "A heavy right cross lands clean!"
            case .japanese: "重い右クロスが本物に決まりました!"
            }
        case .leftBody, .rightBody:
            switch language {
            case .korean: "보디샷이 복부에 박힙니다! 호흡이 흔들립니다."
            case .english: "The body shot digs in! The breath gets knocked out."
            case .japanese: "ボディブローが腹に突き刺さります!呼吸が乱れます。"
            }
        case .leftHook, .rightHook:
            switch language {
            case .korean: "훅이 옆에서 감아 들어갑니다! 각도가 좋았어요."
            case .english: "The hook wraps in from the side! Great angle."
            case .japanese: "フックが横から巻き込みます!角度が良かったです。"
            }
        case .leftUppercut, .rightUppercut:
            switch language {
            case .korean: "어퍼컷이 턱을 강타합니다! 짧지만 강력합니다."
            case .english: "The uppercut crashes into the chin! Short but powerful."
            case .japanese: "アッパーカットが顎を強打します!短いが強烈です。"
            }
        }
    }

    static func counter(attacker: String, damage: Int, bodyHookBonus: Bool, language: AppLanguage) -> String {
        if bodyHookBonus {
            switch language {
            case .korean: return "카운터 적중! \(attacker)의 바디/훅 보너스 피해 \(damage)!"
            case .english: return "Counter lands! \(attacker)'s body/hook bonus damage: \(damage)!"
            case .japanese: return "カウンター命中!\(attacker)のボディ/フックボーナスダメージ\(damage)!"
            }
        }
        switch language {
        case .korean: return "카운터! \(attacker)가 열린 틈에 \(damage) 피해를 줍니다!"
        case .english: return "Counter! \(attacker) exploits the opening for \(damage) damage!"
        case .japanese: return "カウンター!\(attacker)が隙を突いて\(damage)ダメージ!"
        }
    }

    static func guardBlock(defender: String, language: AppLanguage) -> String {
        switch language {
        case .korean: "\(defender)의 단단한 가드! 충격을 크게 줄였습니다."
        case .english: "\(defender)'s solid guard! The impact is heavily reduced."
        case .japanese: "\(defender)の堅いガード!衝撃を大きく減らしました。"
        }
    }

    // The duck-evade message means opposite things for the human player depending on who dodged: when THEY
    // duck an incoming punch, the attacker (the AI) is the one left exposed, so it really is the player's
    // counter window. But when the AI dodges the PLAYER's punch, it's the other way around -- the player
    // (the attacker who just got evaded) is the one left exposed, and the AI is the one who can now counter
    // THEM. The old single message text was shown identically for both cases and told the player "now's
    // the counter window" even in the second case, which is actively misleading right when the player is
    // the one who needs to be careful instead.
    static func duckEvade(defender: String, isPlayerDefender: Bool, language: AppLanguage) -> String {
        if isPlayerDefender {
            switch language {
            case .korean: return "\(defender)의 완벽한 더킹! 지금이 카운터 타이밍입니다."
            case .english: return "\(defender)'s perfect duck! Now's the counter window."
            case .japanese: return "\(defender)の完璧なダッキング!今がカウンターのタイミングです。"
            }
        }
        switch language {
        case .korean: return "\(defender)이(가) 완벽하게 피했습니다! 지금 당신이 노출됐어요, 조심하세요!"
        case .english: return "\(defender) dodges perfectly! You're the one exposed now -- watch out!"
        case .japanese: return "\(defender)が見事に避けました!今はあなたが隙だらけです、気をつけて!"
        }
    }

    // Same asymmetry as `duckEvade` above: whiffing exposes the fighter who threw the punch, not their
    // opponent. So "a counter chance now!" is only true information when the AI is the one who whiffed --
    // if the PLAYER whiffs, THEY are the one left exposed and the AI gets the counter chance, so the old
    // single message (which told the player "counter chance!" even on their own whiff) was actively
    // encouraging them to press forward at the exact moment they're most vulnerable instead of warning them.
    static func whiff(attacker: String, isPlayerAttacker: Bool, language: AppLanguage) -> String {
        if isPlayerAttacker {
            switch language {
            case .korean: return "\(attacker)의 주먹이 허공을 가릅니다! 지금 조심하세요, 반격당할 수 있어요!"
            case .english: return "\(attacker)'s punch cuts through empty air! Watch out, you're open to a counter now!"
            case .japanese: return "\(attacker)のパンチが空を切ります!今は危険です、反撃されるかも!"
            }
        }
        switch language {
        case .korean: return "\(attacker)의 주먹이 허공을 가릅니다. 지금은 카운터 기회!"
        case .english: return "\(attacker)'s punch cuts through empty air. A counter chance now!"
        case .japanese: return "\(attacker)のパンチが空を切ります。今がカウンターチャンス!"
        }
    }

    static func knockout(winner: String, language: AppLanguage) -> String {
        switch language {
        case .korean: "끝났습니다! \(winner)의 완벽한 K.O.!"
        case .english: "It's over! A perfect K.O. for \(winner)!"
        case .japanese: "決着!\(winner)の完璧なK.O.!"
        }
    }

    static func guardBreak(defender: String, language: AppLanguage) -> String {
        switch language {
        case .korean: "가드 브레이크! \(defender)의 방어가 무너집니다."
        case .english: "Guard break! \(defender)'s defense collapses."
        case .japanese: "ガードブレイク!\(defender)の防御が崩れます。"
        }
    }

    static func enemyDuck(direction: Int, language: AppLanguage) -> String {
        let isLeft = direction < 0
        switch language {
        case .korean: return "RIVAL의 \(isLeft ? "왼쪽" : "오른쪽") 더킹!"
        case .english: return "RIVAL ducks \(isLeft ? "left" : "right")!"
        case .japanese: return "RIVALの\(isLeft ? "左" : "右")ダッキング!"
        }
    }

    static func enemyBackstep(language: AppLanguage) -> String {
        switch language {
        case .korean: "RIVAL이 백스텝으로 거리를 벌립니다."
        case .english: "RIVAL creates distance with a backstep."
        case .japanese: "RIVALがバックステップで距離を取ります。"
        }
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
    /// Boxing style preference. Not touched by reset()/round transitions so it persists for the whole session.
    var style: FightStyle = .standard

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
    private static let winRetention = 0.82

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

    /// Promotes a completed round into the persistent player profile. Keeping part of the existing
    /// profile lets RIVAL remember the player while giving recent behavior more influence.
    mutating func incorporateRound(_ round: HabitMemory) {
        for punch in Punch.allCases {
            attackCounts[punch, default: 0] = attackCounts[punch, default: 0] * Self.winRetention
                + round.attackCounts[punch, default: 0]
        }
        guardSamples = guardSamples * Self.winRetention + round.guardSamples
        duckLeftSamples = duckLeftSamples * Self.winRetention + round.duckLeftSamples
        duckRightSamples = duckRightSamples * Self.winRetention + round.duckRightSamples
        backstepSamples = backstepSamples * Self.winRetention + round.backstepSamples
        pressureSamples = pressureSamples * Self.winRetention + round.pressureSamples
        retreatSamples = retreatSamples * Self.winRetention + round.retreatSamples
        totalSamples = totalSamples * Self.winRetention + round.totalSamples
        recentAttack = nil
        repeatStreak = 0
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
            sampleStrength: min(1, sampleTotal / 900)
        )
    }

    var rivalRead: RivalReadProfile {
        let snapshot = snapshot
        return RivalReadProfile.infer(
            favoriteAttack: snapshot.favoriteAttack,
            jabRatio: snapshot.jabRatio,
            bodyRatio: snapshot.bodyRatio,
            guardRatio: snapshot.guardRatio,
            duckLeftRatio: snapshot.duckLeftRatio,
            duckRightRatio: snapshot.duckRightRatio,
            pressureRatio: snapshot.pressureRatio,
            retreatRatio: snapshot.retreatRatio,
            repeatStreak: snapshot.repeatStreak,
            attackCount: attackCounts.values.reduce(0, +),
            sampleSeconds: totalSamples / 8
        )
    }
}

enum RivalRead: Equatable, Sendable {
    case none
    case jabPattern
    case bodyPattern
    case guardShell
    case duckLeftPattern
    case duckRightPattern
    case retreatPattern
    case pressurePattern

    func cornerReport(for language: AppLanguage) -> String? {
        switch self {
        case .none:
            nil
        case .jabPattern:
            switch language {
            case .korean: "RIVAL이 왼손 리듬을 읽고 크로스를 준비합니다."
            case .english: "RIVAL has timed the lead hand and is loading the cross."
            case .japanese: "RIVALはリードハンドのリズムを読み、クロスを狙っています。"
            }
        case .bodyPattern:
            switch language {
            case .korean: "바디 공격이 반복됩니다. RIVAL이 어퍼컷을 준비합니다."
            case .english: "The body attack is repeating. RIVAL is readying uppercuts."
            case .japanese: "ボディ攻撃が続いています。RIVALはアッパーを狙っています。"
            }
        case .guardShell:
            switch language {
            case .korean: "RIVAL이 높은 가드를 낮은 바디샷으로 공략합니다."
            case .english: "RIVAL is working the body beneath the high guard."
            case .japanese: "RIVALは高いガードの下、ボディを狙っています。"
            }
        case .duckLeftPattern:
            switch language {
            case .korean: "왼쪽 더킹을 읽었습니다. RIVAL이 리드 훅을 얹습니다."
            case .english: "The left duck is telegraphed. RIVAL is setting the lead hook."
            case .japanese: "左へのダッキングを読まれました。RIVALはリードフックを狙います。"
            }
        case .duckRightPattern:
            switch language {
            case .korean: "오른쪽 더킹을 읽었습니다. RIVAL이 크로스를 준비합니다."
            case .english: "The right duck is telegraphed. RIVAL is setting the cross."
            case .japanese: "右へのダッキングを読まれました。RIVALはクロスを狙います。"
            }
        case .retreatPattern:
            switch language {
            case .korean: "RIVAL이 물러나는 발을 따라 잽과 크로스를 뻗습니다."
            case .english: "RIVAL is tracking the retreat with the jab and cross."
            case .japanese: "RIVALは下がる足をジャブとクロスで追っています。"
            }
        case .pressurePattern:
            switch language {
            case .korean: "RIVAL이 압박을 흘리며 훅을 맞출 각을 만듭니다."
            case .english: "RIVAL is giving ground to create a hook angle."
            case .japanese: "RIVALは圧力を流し、フックの角度を作っています。"
            }
        }
    }
}

struct RivalReadProfile: Equatable, Sendable {
    static let none = RivalReadProfile(kind: .none, confidence: 0)

    let kind: RivalRead
    let confidence: Double

    static func infer(
        favoriteAttack: Punch,
        jabRatio: Double,
        bodyRatio: Double,
        guardRatio: Double,
        duckLeftRatio: Double,
        duckRightRatio: Double,
        pressureRatio: Double,
        retreatRatio: Double,
        repeatStreak: Int,
        attackCount: Double,
        sampleSeconds: Double
    ) -> RivalReadProfile {
        let attackConfidence = min(1, attackCount / 6)
        let sampleConfidence = min(1, sampleSeconds / 3)

        if favoriteAttack == .jab, attackCount >= 4, jabRatio >= 0.65 {
            return RivalReadProfile(kind: .jabPattern, confidence: max(0.65, attackConfidence))
        }
        if attackCount >= 4, bodyRatio >= 0.65 {
            return RivalReadProfile(kind: .bodyPattern, confidence: max(0.65, attackConfidence))
        }
        if sampleSeconds >= 1.5, guardRatio >= 0.42 {
            return RivalReadProfile(kind: .guardShell, confidence: max(0.6, guardRatio * sampleConfidence))
        }
        if sampleSeconds >= 1.5, duckLeftRatio >= 0.22 {
            return RivalReadProfile(kind: .duckLeftPattern, confidence: max(0.6, duckLeftRatio * sampleConfidence))
        }
        if sampleSeconds >= 1.5, duckRightRatio >= 0.22 {
            return RivalReadProfile(kind: .duckRightPattern, confidence: max(0.6, duckRightRatio * sampleConfidence))
        }
        if sampleSeconds >= 1.5, retreatRatio >= 0.22 {
            return RivalReadProfile(kind: .retreatPattern, confidence: max(0.6, retreatRatio * sampleConfidence))
        }
        if sampleSeconds >= 1.5, pressureRatio >= 0.22 {
            return RivalReadProfile(kind: .pressurePattern, confidence: max(0.6, pressureRatio * sampleConfidence))
        }
        if repeatStreak >= 4, favoriteAttack == .jab {
            return RivalReadProfile(kind: .jabPattern, confidence: 0.65)
        }
        return .none
    }
}

private struct RecentHabitMemory {
    private static let maxAttackHistory = 6
    private static let sampleHalfLife = 8.0

    private var attackHistory: [Punch] = []
    private var guardSamples = 0.0
    private var duckLeftSamples = 0.0
    private var duckRightSamples = 0.0
    private var pressureSamples = 0.0
    private var retreatSamples = 0.0
    private var totalSamples = 0.0

    mutating func noteAttack(_ punch: Punch) {
        attackHistory.append(punch)
        if attackHistory.count > Self.maxAttackHistory {
            attackHistory.removeFirst(attackHistory.count - Self.maxAttackHistory)
        }
    }

    mutating func sample(
        deltaTime: Double,
        guarding: Bool,
        duckDirection: Int,
        forwardAxis: Double
    ) {
        let sample = min(0.05, max(0, deltaTime))
        guard sample > 0 else { return }
        let retention = exp(-log(2) * sample / Self.sampleHalfLife)
        guardSamples *= retention
        duckLeftSamples *= retention
        duckRightSamples *= retention
        pressureSamples *= retention
        retreatSamples *= retention
        totalSamples = totalSamples * retention + sample

        if guarding { guardSamples += sample }
        if duckDirection < 0 { duckLeftSamples += sample }
        if duckDirection > 0 { duckRightSamples += sample }
        if forwardAxis > 0 { pressureSamples += sample * abs(forwardAxis) }
        if forwardAxis < 0 { retreatSamples += sample * abs(forwardAxis) }
    }

    var rivalRead: RivalReadProfile {
        let attackCount = Double(attackHistory.count)
        let totalAttacks = max(attackCount, 1)
        let counts = Dictionary(attackHistory.map { ($0, 1) }, uniquingKeysWith: +)
        let favorite = Punch.allCases.max { counts[$0, default: 0] < counts[$1, default: 0] } ?? .jab
        var repeatStreak = 0
        for punch in attackHistory.reversed() {
            guard punch == favorite else { break }
            repeatStreak += 1
        }
        let sampleTotal = max(totalSamples, 0.001)
        return RivalReadProfile.infer(
            favoriteAttack: favorite,
            jabRatio: Double(counts[.jab, default: 0]) / totalAttacks,
            bodyRatio: Double(counts[.leftBody, default: 0] + counts[.rightBody, default: 0]) / totalAttacks,
            guardRatio: guardSamples / sampleTotal,
            duckLeftRatio: duckLeftSamples / sampleTotal,
            duckRightRatio: duckRightSamples / sampleTotal,
            pressureRatio: pressureSamples / sampleTotal,
            retreatRatio: retreatSamples / sampleTotal,
            repeatStreak: repeatStreak,
            attackCount: attackCount,
            sampleSeconds: totalSamples
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

    func adaptation() -> Double {
        min(0.75, max(0.18, 0.18 + 0.57 * sampleStrength))
    }

    func enemyWeights(
        distance: Double,
        playerExposed: Bool,
        rivalRead: RivalReadProfile = .none
    ) -> [String: Double] {
        let adapt = adaptation()
        var weights: [String: Double] = [
            Punch.jab.rawValue: 0.1, Punch.cross.rawValue: 0.1,
            Punch.leftBody.rawValue: 0.08, Punch.rightBody.rawValue: 0.08,
            Punch.leftHook.rawValue: 0.08, Punch.rightHook.rawValue: 0.08,
            Punch.leftUppercut.rawValue: 0.06, Punch.rightUppercut.rawValue: 0.06,
            "dodge_left": 0.04, "dodge_right": 0.04, "dodge_back": 0.04,
            "advance": 0.08, "retreat": 0.08, "circle_left": 0.12, "circle_right": 0.12,
            "cut_off": 0.06,
            "wait": max(0.05, 0.34 - 0.16 * adapt),
        ]

        func add(_ key: String, _ amount: Double) { weights[key, default: 0] += amount }
        if distance > 115 {
            add(Punch.jab.rawValue, 1.55); add(Punch.cross.rawValue, 0.45); add("advance", 1.2)
        } else if distance > 78 {
            add(Punch.jab.rawValue, 1); add(Punch.cross.rawValue, 0.95)
            add(Punch.leftHook.rawValue, 0.35); add(Punch.rightHook.rawValue, 0.55)
            add("dodge_left", 0.22); add("dodge_right", 0.22); add("circle_left", 0.22); add("circle_right", 0.22)
        } else {
            add(Punch.leftBody.rawValue, 0.95); add(Punch.rightBody.rawValue, 1.15)
            add(Punch.leftHook.rawValue, 0.8); add(Punch.rightHook.rawValue, 0.95)
            add(Punch.leftUppercut.rawValue, 0.45); add(Punch.rightUppercut.rawValue, 0.65)
            add("dodge_back", 0.28); add("retreat", 0.18); add("circle_left", 0.18); add("circle_right", 0.18)
        }
        if guardRatio > 0.22 { add(Punch.leftBody.rawValue, 0.95 * adapt); add(Punch.rightBody.rawValue, 1.2 * adapt); add("circle_left", 0.3 * adapt); add("circle_right", 0.3 * adapt) }
        if duckRightRatio > 0.16 { add(Punch.cross.rawValue, 1.05 * adapt); add(Punch.rightHook.rawValue, 0.95 * adapt); add(Punch.rightUppercut.rawValue, 0.7 * adapt) }
        if duckLeftRatio > 0.16 { add(Punch.jab.rawValue, 0.85 * adapt); add(Punch.leftHook.rawValue, 0.8 * adapt); add(Punch.leftUppercut.rawValue, 0.6 * adapt) }
        if jabRatio > 0.34 || favoriteAttack == .jab { add(Punch.cross.rawValue, 0.9 * adapt); add(Punch.rightHook.rawValue, 0.55 * adapt); add("dodge_right", 0.35 * adapt) }
        if bodyRatio > 0.3 { add(Punch.leftUppercut.rawValue, 0.45 * adapt); add(Punch.rightUppercut.rawValue, 0.7 * adapt) }
        if pressureRatio > 0.2 { add("dodge_back", 0.75 * adapt); add("retreat", 0.5 * adapt); add("circle_left", 0.55 * adapt); add("circle_right", 0.55 * adapt); add(Punch.rightHook.rawValue, 0.55 * adapt); add(Punch.leftHook.rawValue, 0.45 * adapt) }
        if backstepRatio > 0.14 || retreatRatio > 0.18 { add("cut_off", 1.05 * adapt); add("advance", 0.45 * adapt); add(Punch.jab.rawValue, 0.7 * adapt); add(Punch.cross.rawValue, 0.45 * adapt); weights["wait", default: 0] *= 0.8 }
        if repeatStreak >= 3 { add("dodge_left", 0.35 * adapt); add("dodge_right", 0.35 * adapt) }
        let readStrength = 0.65 + 0.35 * rivalRead.confidence
        switch rivalRead.kind {
        case .none:
            break
        case .jabPattern:
            add(Punch.cross.rawValue, 1.05 * readStrength)
            add(Punch.rightHook.rawValue, 0.7 * readStrength)
            add("dodge_right", 0.4 * readStrength)
        case .bodyPattern:
            add(Punch.leftUppercut.rawValue, 0.75 * readStrength)
            add(Punch.rightUppercut.rawValue, 1.05 * readStrength)
        case .guardShell:
            add(Punch.leftBody.rawValue, 0.85 * readStrength)
            add(Punch.rightBody.rawValue, 1.1 * readStrength)
        case .duckLeftPattern:
            add(Punch.jab.rawValue, 0.9 * readStrength)
            add(Punch.leftHook.rawValue, 0.65 * readStrength)
        case .duckRightPattern:
            add(Punch.cross.rawValue, 1.0 * readStrength)
            add(Punch.rightHook.rawValue, 0.75 * readStrength)
        case .retreatPattern:
            add("cut_off", 1.15 * readStrength)
            add("advance", 0.45 * readStrength)
            add(Punch.jab.rawValue, 0.8 * readStrength)
            add(Punch.cross.rawValue, 0.6 * readStrength)
        case .pressurePattern:
            add("dodge_back", 0.8 * readStrength)
            add("retreat", 0.55 * readStrength)
            add("circle_left", 0.65 * readStrength)
            add("circle_right", 0.65 * readStrength)
            add(Punch.leftHook.rawValue, 0.5 * readStrength)
            add(Punch.rightHook.rawValue, 0.65 * readStrength)
        }
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
    let highestRound: Int
    let time: Double
    let playerHP: Int
    let enemyHP: Int
    let playerStamina: Double
    let enemyStamina: Double
    let playerScore: Int
    let enemyScore: Int
    let adaptation: Double
    let favoriteAttack: Punch
    let rivalRead: RivalRead
    let rivalReadConfidence: Double
    let message: String
    let successfulDodgeCount: Int
    let lastImpactGuarded: Bool
    let whiffCount: Int
    let lastWhiffByPlayer: Bool
    let guardBreakCount: Int
    let lastGuardBreakByPlayer: Bool
    let exhaustionCount: Int
    let lastExhaustedByPlayer: Bool
    let lastRoundOutcome: RoundOutcome
    let lastRoundWasKnockout: Bool
    let playerLocked: Bool
    let roundPlayerDodgeCount: Int
    let roundEnemyDodgeCount: Int
    let roundPlayerTopAttack: Punch?
    let roundEnemyTopAttack: Punch?
    let roundFinishingPunch: Punch?
    let roundFinishingBlowByPlayer: Bool
    let canAdvanceRound: Bool
    /// True only when the round just ended in a player win AND the player's HP is still full (100) --
    /// since HP resets to 100 at the start of every round (see `FighterModel.reset`), this cleanly means
    /// the rival never landed a single hit the whole round. Used to unlock the "Untouchable" outfit.
    let roundPlayerWasUnhit: Bool
}

@MainActor
final class CombatEngine {
    private enum EnemyFootwork {
        case none
        case advance
        case retreat
        case circleLeft
        case circleRight
        case cutOff

        init?(decision: String) {
            switch decision {
            case "advance": self = .advance
            case "retreat": self = .retreat
            case "circle_left": self = .circleLeft
            case "circle_right": self = .circleRight
            case "cut_off": self = .cutOff
            default: return nil
            }
        }
    }

    let player = FighterModel(name: "PLAYER", colorName: "cyan", x: 170, y: 295)
    let enemy = FighterModel(name: "RIVAL", colorName: "red", x: 420, y: 295)

    private(set) var phase = FightPhase.intro
    private(set) var round = 1
    private(set) var highestRound = 1
    private(set) var roundTime = CombatData.roundSeconds
    private(set) var playerScore = 0
    private(set) var enemyScore = 0
    private(set) var successfulDodgeCount = 0
    private(set) var lastImpactGuarded = false
    private(set) var whiffCount = 0
    private(set) var lastWhiffByPlayer = false
    private(set) var guardBreakCount = 0
    private(set) var lastGuardBreakByPlayer = false
    private(set) var exhaustionCount = 0
    private(set) var lastExhaustedByPlayer = false
    private(set) var lastRoundOutcome = RoundOutcome.draw
    private(set) var lastRoundWasKnockout = false
    private(set) var roundPlayerDodgeCount = 0
    private(set) var roundEnemyDodgeCount = 0
    private(set) var roundPlayerPunchCounts: [Punch: Int] = [:]
    private(set) var roundEnemyPunchCounts: [Punch: Int] = [:]
    /// The punch that landed the knockout blow this round, if the round ended in a K.O. Reset each round.
    private(set) var roundFinishingPunch: Punch?
    private(set) var roundFinishingBlowByPlayer = false
    private(set) var message = L.tagline.text(for: .korean)
    private(set) var habits: HabitMemory
    var moveX = 0.0
    var moveY = 0.0

    private var previousPhase: FightPhase?
    private var enemyDecisionTimer = 0.5
    private var enemyFootwork = EnemyFootwork.none
    private var enemyFootworkTime = 0.0
    private var roundBreakTimer = 0.0
    private var advancesRoundAfterBreak = false
    private var roundHabits = HabitMemory()
    private var recentHabits = RecentHabitMemory()
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
        if let savedRound = defaults?.integer(forKey: "pixelBoxingRound"), savedRound > 0 {
            round = savedRound
        }
        playerScore = defaults?.integer(forKey: "pixelBoxingPlayerScore") ?? 0
        enemyScore = defaults?.integer(forKey: "pixelBoxingEnemyScore") ?? 0
        highestRound = max(round, defaults?.integer(forKey: "pixelBoxingHighestRound") ?? 1)
        if let styleRaw = defaults?.string(forKey: "pixelBoxingPlayerStyle"), let savedStyle = FightStyle(rawValue: styleRaw) {
            player.style = savedStyle
        }
    }

    var snapshot: CombatSnapshot {
        let habit = habits.snapshot
        let rivalRead = recentHabits.rivalRead
        return CombatSnapshot(
            phase: phase, round: round, highestRound: highestRound, time: roundTime,
            playerHP: player.hp, enemyHP: enemy.hp,
            playerStamina: player.stamina, enemyStamina: enemy.stamina,
            playerScore: playerScore, enemyScore: enemyScore,
            adaptation: habit.adaptation(),
            favoriteAttack: habit.favoriteAttack,
            rivalRead: rivalRead.kind, rivalReadConfidence: rivalRead.confidence,
            message: message,
            successfulDodgeCount: successfulDodgeCount,
            lastImpactGuarded: lastImpactGuarded,
            whiffCount: whiffCount, lastWhiffByPlayer: lastWhiffByPlayer,
            guardBreakCount: guardBreakCount, lastGuardBreakByPlayer: lastGuardBreakByPlayer,
            exhaustionCount: exhaustionCount, lastExhaustedByPlayer: lastExhaustedByPlayer,
            lastRoundOutcome: lastRoundOutcome, lastRoundWasKnockout: lastRoundWasKnockout,
            playerLocked: player.exhausted > 0 || player.stagger > 0,
            roundPlayerDodgeCount: roundPlayerDodgeCount,
            roundEnemyDodgeCount: roundEnemyDodgeCount,
            roundPlayerTopAttack: Self.topAttack(from: roundPlayerPunchCounts),
            roundEnemyTopAttack: Self.topAttack(from: roundEnemyPunchCounts),
            roundFinishingPunch: roundFinishingPunch,
            roundFinishingBlowByPlayer: roundFinishingBlowByPlayer,
            canAdvanceRound: phase == .roundBreak && roundBreakTimer <= 0,
            roundPlayerWasUnhit: lastRoundOutcome == .playerWin && player.hp == 100
        )
    }

    /// Picks the most-thrown punch this round for a simple "signature attack" stat, breaking ties by
    /// `Punch`'s declaration order (jab first) so the result is deterministic rather than dictionary-order-dependent.
    private static func topAttack(from counts: [Punch: Int]) -> Punch? {
        Punch.allCases
            .compactMap { punch -> (Punch, Int)? in
                guard let count = counts[punch], count > 0 else { return nil }
                return (punch, count)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    func startSession() {
        round = 1
        playerScore = 0
        enemyScore = 0
        successfulDodgeCount = 0
        startRound()
        persistProgress()
    }

    /// Continues play using whatever round/score was already loaded (from a previous app launch), without
    /// resetting progress. Used by the normal FIGHT button flow so round advancement survives app restarts.
    func resumeSession() {
        startRound()
    }

    func setPlayerStyle(_ style: FightStyle) {
        player.style = style
        defaults?.set(style.rawValue, forKey: "pixelBoxingPlayerStyle")
    }

    func startRound() {
        player.reset(x: 170, y: 295)
        enemy.reset(x: 420, y: 295)
        phase = .fight
        roundTime = CombatData.roundSeconds
        roundBreakTimer = 0
        advancesRoundAfterBreak = false
        enemyDecisionTimer = 0.55
        enemyFootwork = .none
        enemyFootworkTime = 0
        roundHabits = HabitMemory()
        recentHabits = RecentHabitMemory()
        roundPlayerDodgeCount = 0
        roundEnemyDodgeCount = 0
        roundPlayerPunchCounts = [:]
        roundEnemyPunchCounts = [:]
        roundFinishingPunch = nil
        roundFinishingBlowByPlayer = false
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
        roundHabits = HabitMemory()
        defaults?.removeObject(forKey: "pixelBoxingHabitMemory")
        startSession()
        message = LocalizationManager.shared.t(.learningResetMessage)
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
        let staminaCost = CombatData.backstepStaminaCost * player.style.backstepStaminaMultiplier
        guard phase == .fight, player.attack == nil, player.stagger <= 0, player.exhausted <= 0,
              player.stamina >= staminaCost else { return false }
        player.stamina -= staminaCost
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
              let spec = CombatData.attacks[punch] else { return false }
        let staminaCost = spec.staminaCost * fighter.style.punchStaminaMultiplier
        guard fighter.stamina >= staminaCost else { return false }
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
        fighter.stamina = max(0, fighter.stamina - staminaCost)
        message = CombatCommentary.attackCall(punch, attacker: fighter.name, language: LocalizationManager.shared.language)
        if fighter.stamina <= 0 { exhaust(fighter) }
        if recordsHabit {
            roundHabits.noteAttack(punch)
            recentHabits.noteAttack(punch)
        }
        if fighter === player {
            roundPlayerPunchCounts[punch, default: 0] += 1
        } else {
            roundEnemyPunchCounts[punch, default: 0] += 1
        }
        return true
    }

    /// Manually advances out of `.roundBreak` into the next round. Round advancement used to happen
    /// automatically once `roundBreakTimer` expired; it now only clears the knockdown-fall animation and
    /// unlocks the round-result overlay's "next round" button, waiting for the player to explicitly confirm.
    func requestNextRound() {
        guard phase == .roundBreak, roundBreakTimer <= 0 else { return }
        if advancesRoundAfterBreak { round += 1 }
        highestRound = max(highestRound, round)
        persistProgress()
        startRound()
    }

    func update(deltaTime rawDeltaTime: Double) {
        let deltaTime = min(0.05, max(0, rawDeltaTime))
        guard deltaTime > 0 else { return }
        if phase == .roundBreak {
            roundBreakTimer = max(0, roundBreakTimer - deltaTime)
            updateKnockdowns(deltaTime)
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
        let baseSpeed = player.duckDirection == 0 ? 210.0 : 105.0
        // Retreating never benefits from a style's mobility bonus, so no style can back away faster than
        // the shared baseline backpedal speed — the mobility upside only applies advancing or strafing.
        let forwardSpeed = forward < 0
            ? baseSpeed * CombatData.backwardMoveSpeedMultiplier
            : baseSpeed * player.style.moveSpeedMultiplier
        let strafeSpeed = baseSpeed * player.style.moveSpeedMultiplier
        let rightX = -player.facingY
        let rightY = player.facingX
        let worldX = forward * player.facingX * forwardSpeed + strafe * rightX * strafeSpeed
        let worldY = forward * player.facingY * forwardSpeed + strafe * rightY * strafeSpeed
        moveFighter(
            player,
            byX: worldX * deltaTime,
            byY: worldY * deltaTime,
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
                message = CombatCommentary.whiff(attacker: fighter.name, isPlayerAttacker: fighter === player, language: LocalizationManager.shared.language)
                whiffCount += 1
                lastWhiffByPlayer = fighter === player
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
        let effectiveRange = spec.range * attacker.style.reachMultiplier
        guard distance <= effectiveRange + 17 else { return false }
        let direction = max(0.001, distance)
        let dot = max(-1, min(1, (dx / direction) * attacker.facingX + (dy / direction) * attacker.facingY))
        guard acos(dot) * 180 / .pi <= spec.halfAngle else { return false }

        if let requiredDuck = CombatData.requiredDuck[punch], defender.duckDirection == requiredDuck {
            attacker.exposed = max(attacker.exposed, CombatData.duckCounterWindow)
            if defender === player {
                successfulDodgeCount += 1
                roundPlayerDodgeCount += 1
            } else {
                roundEnemyDodgeCount += 1
            }
            message = CombatCommentary.duckEvade(defender: defender.name, isPlayerDefender: defender === player, language: LocalizationManager.shared.language)
            return false
        }

        let countered = defender.exposed > 0
        lastImpactGuarded = defender.guarding
        let staleStage = max(0, attacker.streakCount - CombatData.staleThreshold)
        let staleMultiplier = max(CombatData.staleFloor, pow(CombatData.staleDecay, Double(staleStage)))
        var damage = max(1, Int((Double(spec.damage) * staleMultiplier * attacker.style.damageMultiplier).rounded()))
        if defender.exposed > 0 {
            damage = Int((Double(damage) * CombatData.exposedDamageMultiplier).rounded())
            if spec.family == .body || spec.family == .hook {
                damage = Int((Double(damage) * CombatData.bodyHookCounterMultiplier).rounded())
            }
        }
        if defender.guarding {
            let guardDamageMultiplier = CombatData.guardDamageMultiplier * defender.style.guardDamageMultiplier
            damage = max(1, Int((Double(damage) * guardDamageMultiplier).rounded()))
            let staminaDamage = max(
                CombatData.minimumGuardStaminaDamage,
                Double(spec.damage) * CombatData.guardStaminaDamageMultiplier * defender.style.guardStaminaMultiplier
            )
            defender.stamina = max(0, defender.stamina - staminaDamage)
            if defender.stamina <= 0 {
                defender.guarding = false
                exhaust(defender)
                message = CombatCommentary.guardBreak(defender: defender.name, language: LocalizationManager.shared.language)
                guardBreakCount += 1
                lastGuardBreakByPlayer = defender === player
            } else {
                message = CombatCommentary.guardBlock(defender: defender.name, language: LocalizationManager.shared.language)
            }
        } else if countered {
            message = CombatCommentary.counter(
                attacker: attacker.name,
                damage: damage,
                bodyHookBonus: spec.family == .body || spec.family == .hook,
                language: LocalizationManager.shared.language
            )
        } else {
            message = CombatCommentary.impact(punch, attacker: attacker.name, language: LocalizationManager.shared.language)
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
            roundFinishingPunch = punch
            roundFinishingBlowByPlayer = attacker === player
            finishRound(outcome: defender === enemy ? .playerWin : .playerLoss, knockout: true)
        }
        return true
    }

    private func updateEnemy(_ deltaTime: Double) {
        guard enemy.attack == nil, enemy.stagger <= 0, enemy.exhausted <= 0 else { return }
        guard enemy.duckDirection == 0 else { return }
        let initialDistance = hypot(player.x - enemy.x, player.y - enemy.y)
        applyEnemyFootwork(deltaTime, distance: initialDistance)
        let distance = hypot(player.x - enemy.x, player.y - enemy.y)
        enemyDecisionTimer -= deltaTime
        guard enemyDecisionTimer <= 0 else { return }
        let adaptation = habits.snapshot.adaptation()
        enemyDecisionTimer = max(0.18, 0.68 - 0.28 * adaptation) + Double.random(in: 0...0.18)
        let choice = weightedChoice(
            habits.snapshot.enemyWeights(
                distance: distance,
                playerExposed: player.exposed > 0,
                rivalRead: recentHabits.rivalRead
            )
        )
        performEnemyDecision(choice)
    }

    @discardableResult
    func performEnemyDecision(_ choice: String) -> Bool {
        if let punch = Punch(rawValue: choice) {
            return startAttack(enemy, punch: punch)
        } else if let footwork = EnemyFootwork(decision: choice) {
            enemyFootwork = footwork
            enemyFootworkTime = Double.random(in: 0.32...0.58)
            return true
        } else if choice == "dodge_left" || choice == "dodge_right" {
            guard enemy.stamina >= CombatData.dodgeStaminaCost else { return false }
            enemy.stamina -= CombatData.dodgeStaminaCost
            enemy.duckDirection = choice == "dodge_left" ? -1 : 1
            enemy.duckTime = CombatData.enemyDuckDuration
            message = CombatCommentary.enemyDuck(direction: choice == "dodge_left" ? -1 : 1, language: LocalizationManager.shared.language)
            return true
        } else if choice == "dodge_back", enemy.stamina >= CombatData.dodgeStaminaCost {
            enemy.stamina -= CombatData.dodgeStaminaCost
            enemy.invulnerable = 0.18
            enemy.x = clampToRing(enemy.x - enemy.facingX * 24)
            enemy.y = clampToRing(enemy.y - enemy.facingY * 24)
            message = CombatCommentary.enemyBackstep(language: LocalizationManager.shared.language)
            return true
        }
        return false
    }

    private func applyEnemyFootwork(_ deltaTime: Double, distance: Double) {
        let towardPlayerX = (player.x - enemy.x) / max(1, distance)
        let towardPlayerY = (player.y - enemy.y) / max(1, distance)
        let rightX = -enemy.facingY
        let rightY = enemy.facingX
        let speed = 62 + 28 * habits.snapshot.adaptation()

        guard enemyFootworkTime > 0 else {
            guard distance > 112 else { return }
            moveFighter(
                enemy,
                byX: towardPlayerX * speed * deltaTime,
                byY: towardPlayerY * speed * deltaTime,
                avoiding: player
            )
            return
        }

        enemyFootworkTime = max(0, enemyFootworkTime - deltaTime)
        var directionX = 0.0
        var directionY = 0.0
        switch enemyFootwork {
        case .none:
            return
        case .advance:
            guard distance > 70 else { return }
            directionX = towardPlayerX
            directionY = towardPlayerY
        case .retreat:
            guard distance < 145 else { return }
            directionX = -towardPlayerX
            directionY = -towardPlayerY
        case .circleLeft:
            let radialCorrection = distance < 76 ? -0.28 : (distance > 110 ? 0.22 : 0)
            directionX = -rightX + towardPlayerX * radialCorrection
            directionY = -rightY + towardPlayerY * radialCorrection
        case .circleRight:
            let radialCorrection = distance < 76 ? -0.28 : (distance > 110 ? 0.22 : 0)
            directionX = rightX + towardPlayerX * radialCorrection
            directionY = rightY + towardPlayerY * radialCorrection
        case .cutOff:
            let playerStrafe = moveX * (-player.facingY) + moveY * player.facingX
            let lateralDirection = playerStrafe >= 0 ? 1.0 : -1.0
            directionX = towardPlayerX * 0.82 + rightX * lateralDirection * 0.58
            directionY = towardPlayerY * 0.82 + rightY * lateralDirection * 0.58
        }
        moveFighter(
            enemy,
            byX: directionX * speed * deltaTime,
            byY: directionY * speed * deltaTime,
            avoiding: player
        )
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
        roundHabits.sample(deltaTime: deltaTime, guarding: player.guarding, duckDirection: player.duckDirection, backstep: player.invulnerable > 0, forwardAxis: forwardAxis)
        recentHabits.sample(
            deltaTime: deltaTime,
            guarding: player.guarding,
            duckDirection: player.duckDirection,
            forwardAxis: forwardAxis
        )
    }

    func finishRound(outcome: RoundOutcome, knockout: Bool) {
        guard phase == .fight else { return }
        phase = .roundBreak
        lastRoundOutcome = outcome
        lastRoundWasKnockout = knockout
        advancesRoundAfterBreak = outcome == .playerWin
        habits.incorporateRound(roundHabits)
        switch outcome {
        case .playerWin:
            playerScore += 1
        case .playerLoss:
            enemyScore += 1
        case .draw:
            break
        }
        roundBreakTimer = knockout ? 2.2 : 1.7
        if knockout {
            message = CombatCommentary.knockout(winner: outcome == .playerWin ? player.name : enemy.name, language: LocalizationManager.shared.language)
        } else {
            switch outcome {
            case .playerWin: message = "ROUND WON"
            case .playerLoss: message = LocalizationManager.shared.t(.roundLostMessage)
            case .draw: message = LocalizationManager.shared.t(.drawMessage)
            }
        }
        saveHabits()
        persistProgress()
    }

    private func updateKnockdowns(_ deltaTime: Double) {
        for fighter in [player, enemy] where fighter.knockedOut {
            fighter.knockdown = min(1, fighter.knockdown + deltaTime / 0.9)
        }
    }

    private func exhaust(_ fighter: FighterModel) {
        fighter.exhausted = max(fighter.exhausted, CombatData.exhaustionDuration)
        fighter.exposed = max(fighter.exposed, CombatData.exhaustionExposed)
        exhaustionCount += 1
        lastExhaustedByPlayer = fighter === player
        if fighter === player { message = "GASSED OUT" }
    }

    private func saveHabits() {
        guard let defaults, let data = try? JSONEncoder().encode(habits) else { return }
        defaults.set(data, forKey: "pixelBoxingHabitMemory")
    }

    private func persistProgress() {
        defaults?.set(round, forKey: "pixelBoxingRound")
        defaults?.set(playerScore, forKey: "pixelBoxingPlayerScore")
        defaults?.set(enemyScore, forKey: "pixelBoxingEnemyScore")
        defaults?.set(highestRound, forKey: "pixelBoxingHighestRound")
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

/// A minimal single-fighter engine for the practice room: no opponent, no round timer/score, no AI — just
/// the player's own movement/guard/duck/backstep/attack state, circling a fixed heavy bag hung at the
/// gym's center. Deliberately NOT built on top of `CombatEngine` (which is tightly coupled to always having
/// a live opponent to face/hit) — reimplements only the subset of per-fighter update logic that makes sense
/// against a stationary target. Stamina is never actually spent here (see `startAttack`/`backstep`) so
/// players can freely drill combos without being locked out.
@MainActor
final class PracticeEngine {
    // Reuses the same (295, 295) center convention `BoxerRig`/`worldPosition` assume is the arena's origin,
    // so the heavy bag (fixed at this same point) lands at the room's own world origin with no extra
    // offset math needed, and the player rig starts a short distance south of it.
    static let bagX = 295.0
    static let bagY = 295.0

    let player = FighterModel(name: "PLAYER", colorName: "cyan", x: bagX, y: bagY + 95)

    /// Notified with `(punch, damage)` the instant a punch lands on the bag, so the scene can pop a floating
    /// damage number and give the bag a physical swing impulse.
    var onHit: ((Punch, Int) -> Void)?

    // Player position is clamped to an annulus around the bag instead of a rectangular room, so movement
    // input naturally reads as "walk in / back away / circle around" the fixed target.
    //
    // `minRadius` must stay comfortably under the SHORTEST punch's worst-case effective range (left uppercut,
    // Slugger's (`.infighting`) tight lead-hand jab-up: `range 44 * infighting reachMultiplier 0.90 + the
    // shared 17 fudge margin in `attemptHitBag` == 56.6`) or that punch becomes mathematically unable to ever
    // land on the bag -- this was exactly the bug where a Slugger's left uppercut never connected, since the
    // old `minRadius` of 58 was already past that punch's max reach before the player even started swinging.
    private let minRadius = 54.0
    private let maxRadius = 185.0
    var moveX = 0.0
    var moveY = 0.0

    var playerLocked: Bool {
        player.stagger > 0
    }

    func setStyle(_ style: FightStyle) {
        player.style = style
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
        guard player.attack == nil else { return }
        player.guarding = true
    }

    func setDuck(_ direction: Int, active: Bool) {
        if !active {
            player.duckDirection = 0
            return
        }
        guard player.attack == nil else { return }
        player.duckDirection = min(1, max(-1, direction))
    }

    @discardableResult
    func backstep() -> Bool {
        guard player.attack == nil, player.stagger <= 0 else { return false }
        player.invulnerable = 0.22
        moveToClamped(x: player.x - player.facingX * 34, y: player.y - player.facingY * 34)
        return true
    }

    @discardableResult
    func startAttack(_ punch: Punch) -> Bool {
        guard player.attack == nil, player.stagger <= 0, CombatData.attacks[punch] != nil else { return false }
        player.attack = punch
        player.actionTime = 0
        player.acted = false
        player.guarding = false
        return true
    }

    func update(deltaTime rawDeltaTime: Double) {
        let deltaTime = min(0.05, max(0, rawDeltaTime))
        guard deltaTime > 0 else { return }
        updateFacing()
        updatePlayerMovement(deltaTime)
        player.invulnerable = max(0, player.invulnerable - deltaTime)
        player.stagger = max(0, player.stagger - deltaTime)
        player.hitReaction = max(0, player.hitReaction - deltaTime)
        player.stamina = 100

        if let punch = player.attack, let spec = CombatData.attacks[punch] {
            let previous = player.actionTime
            player.actionTime += deltaTime
            if !player.acted, previous < spec.activeStart, player.actionTime >= spec.activeStart {
                player.acted = attemptHitBag(punch: punch, spec: spec)
            }
            if player.actionTime >= spec.duration {
                player.attack = nil
                player.actionTime = 0
                player.acted = false
            }
        }
    }

    /// Player always faces the fixed bag (there's no opponent to track), recomputed every frame the same
    /// way `CombatEngine.updateFacing()` keeps the two live fighters looking at each other.
    private func updateFacing() {
        let dx = Self.bagX - player.x
        let dy = Self.bagY - player.y
        let magnitude = max(0.001, hypot(dx, dy))
        player.facingX = dx / magnitude
        player.facingY = dy / magnitude
    }

    @discardableResult
    private func attemptHitBag(punch: Punch, spec: AttackSpec) -> Bool {
        let dx = Self.bagX - player.x
        let dy = Self.bagY - player.y
        let distance = hypot(dx, dy)
        let effectiveRange = spec.range * player.style.reachMultiplier
        guard distance <= effectiveRange + 17 else { return false }
        let damage = max(1, Int((Double(spec.damage) * player.style.damageMultiplier).rounded()))
        player.hitReaction = 0.16
        onHit?(punch, damage)
        return true
    }

    private func updatePlayerMovement(_ deltaTime: Double) {
        guard player.attack == nil, player.stagger <= 0, !player.guarding else { return }
        let magnitude = hypot(moveX, moveY)
        guard magnitude > 0.01 else { return }
        let forward = moveX / max(1, magnitude)
        let strafe = moveY / max(1, magnitude)
        let baseSpeed = player.duckDirection == 0 ? 210.0 : 105.0
        let forwardSpeed = forward < 0
            ? baseSpeed * CombatData.backwardMoveSpeedMultiplier
            : baseSpeed * player.style.moveSpeedMultiplier
        let strafeSpeed = baseSpeed * player.style.moveSpeedMultiplier
        let rightX = -player.facingY
        let rightY = player.facingX
        let worldX = forward * player.facingX * forwardSpeed + strafe * rightX * strafeSpeed
        let worldY = forward * player.facingY * forwardSpeed + strafe * rightY * strafeSpeed
        moveToClamped(x: player.x + worldX * deltaTime, y: player.y + worldY * deltaTime)
    }

    /// Clamps a candidate position to the annulus around the fixed bag: never closer than `minRadius`
    /// (so the player can't walk through it) and never farther than `maxRadius` (the gym floor's edge).
    private func moveToClamped(x: Double, y: Double) {
        let dx = x - Self.bagX
        let dy = y - Self.bagY
        let distance = hypot(dx, dy)
        guard distance > 0.001 else {
            player.x = Self.bagX
            player.y = Self.bagY + minRadius
            return
        }
        let clampedDistance = min(maxRadius, max(minRadius, distance))
        let scale = clampedDistance / distance
        player.x = Self.bagX + dx * scale
        player.y = Self.bagY + dy * scale
    }
}
