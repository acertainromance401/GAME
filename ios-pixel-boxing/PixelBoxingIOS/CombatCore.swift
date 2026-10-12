/*
 CombatCore.swift

 파일 설명:
 - 게임의 핵심 전투 모델과 규칙을 정의하는 파일입니다. 주요 타입(FighterModel, Punch, Combo, Style 등)
     과 데미지/확률/상태 전환 규칙이 여기서 선언됩니다.
 - 이 파일의 타입과 함수들은 게임 플레이의 규칙적 동작(점수, 데미지, 타격 콜리전 판정 등)에 직접 영향을 줍니다.

 사용 영향 및 주의사항:
 - 이 파일을 변경하면 게임 밸런스와 룰에 영향이 있으므로 테스트 커버리지가 필요합니다.
 - 현재는 주석만 추가되므로 동작에는 영향이 없습니다.
*/
//   사용되는 순수 모델 값들을 포함합니다.
// - UI와 분리된 순수 모델로 설계되어 있어, 저장/로컬화/비즈니스 로직에서 재사용됩니다.

import Foundation
import simd

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
    case storyStarter
    case champion
    case storyChampion
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
        case .storyStarter:
            switch language {
            case .korean: "퍼스트 벨"
            case .english: "First Bell"
            case .japanese: "ファーストベル"
            }
        case .champion:
            switch language {
            case .korean: "챔피언 골드"
            case .english: "Champion Gold"
            case .japanese: "チャンピオンゴールド"
            }
        case .storyChampion:
            switch language {
            case .korean: "파이널 챔피언"
            case .english: "Final Champion"
            case .japanese: "ファイナルチャンピオン"
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
        case storyPurchase
        case storyVictory
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
        case .storyStarter: .storyPurchase
        case .champion: .highestRound(15)
        case .storyChampion: .storyVictory
        case .blackout: .totalWins(75)
        case .gymGray: .gymSeconds(3 * 3600)
        case .unscathed: .perfectRoundWins(7)
        case .champ: .totalWins(500)
        case .streak: .winStreak(12)
        case .masteryInFighter: .styleWins(.standard, 35)
        case .masteryOutboxer: .styleWins(.outboxing, 35)
        case .masterySlugger: .styleWins(.infighting, 35)
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
        case .storyPurchase, .storyVictory: false
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
        case .storyPurchase:
            switch language {
            case .korean: "스토리 구매 즉시 해금 · 클리어 불필요"
            case .english: "Unlocks with Story purchase · No wins required"
            case .japanese: "ストーリー購入ですぐ解放・クリア不要"
            }
        case .storyVictory:
            switch language {
            case .korean: "스토리 챔피언 결정전 우승 시 해제"
            case .english: "Win the Story championship to unlock"
            case .japanese: "ストーリーの王座決定戦に優勝で解放"
            }
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
    let deliveryStart: Double
    let followThroughEnd: Double
    let recoveryEnd: Double
    let damage: Int
    /// Base fighter-root to glove-center reach in game units, before the shared chest extension.
    /// Target surface allowance is separate from both parts of the punch's reach.
    let range: Double
    let halfAngle: Double
    let staminaCost: Double
    let targetZone: TargetZone
    let fistRadius: Double
    let family: AttackFamily

    init(duration: Double, activeStart: Double, activeEnd: Double,
         damage: Int, range: Double, halfAngle: Double, staminaCost: Double,
         targetZone: TargetZone, fistRadius: Double, family: AttackFamily,
         deliveryStart: Double? = nil, followThroughEnd: Double? = nil,
         recoveryEnd: Double? = nil) {
        self.duration = duration
        self.activeStart = activeStart
        self.activeEnd = activeEnd
        self.damage = damage
        self.range = range
        self.halfAngle = halfAngle
        self.staminaCost = staminaCost
        self.targetZone = targetZone
        self.fistRadius = fistRadius
        self.family = family

        let deliveryFraction: Double
        let followThroughFraction: Double
        let recoveryFraction: Double
        switch family {
        case .straight:
            deliveryFraction = 0.28
            followThroughFraction = 0
            recoveryFraction = 0.92
        case .body:
            deliveryFraction = 0.40
            followThroughFraction = 0.09
            recoveryFraction = 0.88
        case .hook:
            deliveryFraction = 0.32
            followThroughFraction = 0.08
            recoveryFraction = 0.94
        case .uppercut:
            deliveryFraction = 0.36
            followThroughFraction = 0.08
            recoveryFraction = 0.96
        }
        self.deliveryStart = deliveryStart ?? activeStart * deliveryFraction
        self.followThroughEnd = followThroughEnd ?? activeStart + duration * followThroughFraction
        self.recoveryEnd = recoveryEnd ?? duration * recoveryFraction
    }
}

enum CombatData {
    static let sceneScale = 0.025
    /// Equal extra GAME units for all eight punches and all styles, after the style multiplier.
    /// Rendering supplies the same additional travel through the chest, never arm-length scaling.
    static let punchReachExtension = 14.0
    // Shared geometric contact allowances, not an extra invisible arm extension.
    static let fighterContactRadius = 0.34
    static let bagContactRadius = 0.60
    static let roundSeconds = 45.0
    static let movementSpeed = 210.0
    static let backstepDistance = 34.0
    static let backstepDuration = 0.22
    static let dodgeStaminaCost = 17.0
    static let enemyDuckDuration = 0.32
    static let backstepStaminaCost = 31.0
    /// Retreating (moving straight back) is slower than closing distance, so backpedaling alone is a
    /// weaker substitute for guarding/ducking and players can't rely purely on distance control to stay safe.
    static let backwardMoveSpeedMultiplier = 0.5
    static let staminaRecoveryPerSecond = 11.0
    static let exhaustionDuration = 1.1
    static let exhaustionExposed = 0.28
    static let whiffRecovery = 0.22
    static let duckCounterWindow = 0.42
    /// A dedicated, stronger slow-motion + camera-zoom beat for the blow that actually lands a knockout,
    /// separate from the RIVAL MOMENT dodge beat above -- so the player reads "this is the finishing shot"
    /// a beat before the round-break overlay appears, not just after the fact.
    static let koMomentDuration = 0.62
    static let koMomentTimeScale = 0.14
    static let koMomentCameraZoom: Float = 1.9
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
    // Root spacing still keeps the torso volumes apart, while allowing short bent-arm punches.
    static let minimumFighterSeparation = 34.0

    static let attacks: [Punch: AttackSpec] = [
        .jab: AttackSpec(duration: 0.24, activeStart: 0.08, activeEnd: 0.15, damage: 6, range: 44, halfAngle: 26, staminaCost: 13, targetZone: .head, fistRadius: 5, family: .straight, deliveryStart: 0.008, recoveryEnd: 0.1728),
        .cross: AttackSpec(duration: 0.38, activeStart: 0.17, activeEnd: 0.27, damage: 11, range: 38, halfAngle: 20, staminaCost: 18, targetZone: .head, fistRadius: 5.4, family: .straight, deliveryStart: 0.06, followThroughEnd: 0.19, recoveryEnd: 0.35),
        .leftBody: AttackSpec(duration: 0.36, activeStart: 0.15, activeEnd: 0.25, damage: 9, range: 29, halfAngle: 40, staminaCost: 16, targetZone: .body, fistRadius: 5.2, family: .body, deliveryStart: 0.055, followThroughEnd: 0.18, recoveryEnd: 0.33),
        .rightBody: AttackSpec(duration: 0.39, activeStart: 0.17, activeEnd: 0.27, damage: 10, range: 30, halfAngle: 38, staminaCost: 17, targetZone: .body, fistRadius: 5.4, family: .body, deliveryStart: 0.065, followThroughEnd: 0.20, recoveryEnd: 0.36),
        .leftHook: AttackSpec(duration: 0.40, activeStart: 0.19, activeEnd: 0.29, damage: 11, range: 26, halfAngle: 56, staminaCost: 18, targetZone: .head, fistRadius: 5.6, family: .hook, deliveryStart: 0.060, followThroughEnd: 0.22, recoveryEnd: 0.37),
        .rightHook: AttackSpec(duration: 0.43, activeStart: 0.21, activeEnd: 0.32, damage: 12, range: 27, halfAngle: 50, staminaCost: 19, targetZone: .head, fistRadius: 5.8, family: .hook, deliveryStart: 0.075, followThroughEnd: 0.24, recoveryEnd: 0.40),
        .leftUppercut: AttackSpec(duration: 0.44, activeStart: 0.22, activeEnd: 0.34, damage: 13, range: 25, halfAngle: 26, staminaCost: 20, targetZone: .head, fistRadius: 5.4, family: .uppercut, deliveryStart: 0.080, followThroughEnd: 0.25, recoveryEnd: 0.41),
        .rightUppercut: AttackSpec(duration: 0.47, activeStart: 0.24, activeEnd: 0.36, damage: 14, range: 26, halfAngle: 24, staminaCost: 21, targetZone: .head, fistRadius: 5.8, family: .uppercut, deliveryStart: 0.090, followThroughEnd: 0.27, recoveryEnd: 0.44),
    ]

    /// Returns GAME units for FighterModel.x/y distance checks. Radius is in scene units,
    /// so divide it by sceneScale here; only the renderer multiplies range by sceneScale.
    static func hitRange(_ punch: Punch, style: FightStyle, targetRadius: Double = fighterContactRadius) -> Double {
        guard let spec = attacks[punch] else { return 0 }
        return spec.range * style.reachMultiplier + punchReachExtension + targetRadius / sceneScale
    }

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
        return base
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
            case .korean: return "\(defender)의 더킹 성공! 지금이 카운터 타이밍입니다."
            case .english: return "\(defender) slips the punch! Now's the counter window."
            case .japanese: return "\(defender)のダッキング成功!今がカウンターのタイミングです。"
            }
        }
        switch language {
        case .korean: return "\(defender)이(가) 공격을 피했습니다! 지금 당신이 노출됐어요, 조심하세요!"
        case .english: return "\(defender) slips your punch! You're exposed now -- watch out!"
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

enum DodgeGrade: String, Codable, Equatable, Sendable {
    case normal
    case good
    case accurate
    case perfect

    var counterWindow: Double {
        switch self {
        case .normal: 0.18
        case .good: 0.28
        case .accurate: 0.60
        case .perfect: 0.80
        }
    }

    var focusDuration: Double {
        switch self {
        case .normal: 0
        case .good: 0.16
        case .accurate: 0.48
        case .perfect: 0.65
        }
    }

    /// How much simulation time slows during the focus beat. Accurate/Perfect are deliberately pushed
    /// much closer to a full freeze than before so the counter-timing cue reads as unmistakable rather
    /// than a subtle wobble.
    var timeScale: Double {
        switch self {
        case .normal, .good: 1
        case .accurate: 0.40
        case .perfect: 0.20
        }
    }

    /// Forward camera push during the focus beat. Bumped up substantially for Accurate/Perfect so the
    /// zoom itself is an unmissable, bold cue -- not just the slow motion -- per the "확실하게 걸어서" /
    /// "줌인도 과감하게" direction.
    var cameraZoom: Float {
        switch self {
        case .normal: 0
        case .good: 0.30
        case .accurate: 1.05
        case .perfect: 1.75
        }
    }
}

final class FighterModel {
    let name: String
    let maximumHealth: Int
    let punchReachBonus: Double
    let punchDamageMultiplier: Double
    var x: Double
    var y: Double
    var hp: Int
    var stamina = 100.0
    var facingX = 1.0
    var facingY = 0.0
    var attack: Punch?
    var attackSerial: UInt64 = 0
    var attackAim: SIMD3<Float>?
    var attackEntryPose: FightPose?
    var poseTransition: FighterPoseTransition?
    var actionTime = 0.0
    var acted = false
    var attackOutcome: RivalAttackOutcome?
    var attackContactFrame: PunchContactFrame?
    var guarding = false
    var guardAmount: Float = 0
    var duckDirection = 0
    var duckTime = 0.0
    var duckMotion = DuckMotion()
    var weave = WeaveState()
    var weaveOrigin: SIMD2<Double>?
    var backstep = BackstepState()
    var invulnerable = 0.0
    var exhausted = 0.0
    var exposed = 0.0
    var stagger = 0.0
    var hitReaction = 0.0
    var lastImpact: CombatImpact?
    var knockedOut = false
    var knockdown = 0.0
    var getupProgress = 0.0
    var streakAttack: Punch?
    var streakCount = 0
    var pendingDodgeCounter = false
    var isAligningCross: Bool {
        guard attack == .cross, let spec = CombatData.attacks[.cross] else { return false }
        return actionTime < spec.deliveryStart
    }
    /// Boxing style preference. Not touched by reset()/round transitions so it persists for the whole session.
    var style: FightStyle = .standard

    init(name: String, x: Double, y: Double, maximumHealth: Int = 100,
         punchReachBonus: Double = 0, punchDamageMultiplier: Double = 1) {
        self.name = name
        self.x = x
        self.y = y
        self.maximumHealth = maximumHealth
        self.punchReachBonus = punchReachBonus
        self.punchDamageMultiplier = punchDamageMultiplier
        hp = maximumHealth
    }

    func reachMultiplier(for punch: Punch) -> Double {
        guard let spec = CombatData.attacks[punch] else { return style.reachMultiplier }
        return style.reachMultiplier + punchReachBonus / spec.range
    }

    func hitRange(_ punch: Punch, targetRadius: Double = CombatData.fighterContactRadius) -> Double {
        CombatData.hitRange(punch, style: style, targetRadius: targetRadius) + punchReachBonus
    }

    func reset(x: Double, y: Double) {
        self.x = x
        self.y = y
        hp = maximumHealth
        stamina = 100
        facingX = name == "PLAYER" ? 1 : -1
        facingY = 0
        attack = nil
        attackSerial = 0
        attackAim = nil
        attackEntryPose = nil
        poseTransition = nil
        actionTime = 0
        acted = false
        attackOutcome = nil
        attackContactFrame = nil
        guarding = false
        guardAmount = 0
        duckDirection = 0
        duckTime = 0
        duckMotion = DuckMotion()
        weave.reset()
        weaveOrigin = nil
        backstep.cancel()
        invulnerable = 0
        exhausted = 0
        exposed = 0
        stagger = 0
        hitReaction = 0
        lastImpact = nil
        knockedOut = false
        knockdown = 0
        getupProgress = 0
        streakAttack = nil
        streakCount = 0
        pendingDodgeCounter = false
    }

    func advancePoseTransition(_ deltaTime: Double) {
        guard var transition = poseTransition else { return }
        transition.advance(deltaTime)
        poseTransition = transition.isActive ? transition : nil
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
        if forwardAxis > 0 { pressureSamples += sample * forwardAxis }
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
        let attackCount = attackCounts.values.reduce(0, +)
        let totalAttacks = max(attackCount, 1)
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
            sampleStrength: min(1, max(0, totalSamples) / 900),
            attackCount: attackCount
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
            attackCount: snapshot.attackCount,
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
    var attackCount: Double = 0

    func adaptation() -> Double {
        min(0.75, max(0.18, 0.18 + 0.57 * sampleStrength))
    }

    func enemyWeights(
        distance: Double,
        playerExposed: Bool,
        rivalRead: RivalReadProfile = .none,
        learningMultiplier: Double = 1,
        style: FightStyle = .standard
    ) -> [String: Double] {
        let learning = min(2.5, max(0, learningMultiplier))
        let adapt = adaptation() * learning
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
        if distance > CombatData.hitRange(.jab, style: style) + 12 {
            add(Punch.jab.rawValue, 1.55); add(Punch.cross.rawValue, 0.45); add("advance", 1.2)
        } else if distance > CombatData.hitRange(.cross, style: style) - 4 {
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
        if jabRatio > 0.34 || (attackCount > 0 && favoriteAttack == .jab) { add(Punch.cross.rawValue, 0.9 * adapt); add(Punch.rightHook.rawValue, 0.55 * adapt); add("dodge_right", 0.35 * adapt) }
        if bodyRatio > 0.3 { add(Punch.leftUppercut.rawValue, 0.45 * adapt); add(Punch.rightUppercut.rawValue, 0.7 * adapt) }
        if pressureRatio > 0.2 { add("dodge_back", 0.75 * adapt); add("retreat", 0.5 * adapt); add("circle_left", 0.55 * adapt); add("circle_right", 0.55 * adapt); add(Punch.rightHook.rawValue, 0.55 * adapt); add(Punch.leftHook.rawValue, 0.45 * adapt) }
        if backstepRatio > 0.14 || retreatRatio > 0.18 { add("cut_off", 1.05 * adapt); add("advance", 0.45 * adapt); add(Punch.jab.rawValue, 0.7 * adapt); add(Punch.cross.rawValue, 0.45 * adapt); weights["wait", default: 0] *= 0.8 }
        if repeatStreak >= 3 { add("dodge_left", 0.35 * adapt); add("dodge_right", 0.35 * adapt) }
        let readStrength = (0.65 + 0.35 * rivalRead.confidence) * learning
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
    let showsRoundResult: Bool
    let lastPlayerDodgeGrade: DodgeGrade?
    let perfectCounterCount: Int
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

    let player = FighterModel(name: "PLAYER", x: 170, y: 295)
    let enemy: FighterModel
    private(set) var storyBout: StoryBoutState?
    private(set) var storyRoundTransition: StoryRoundTransition?

    /// Synchronous facts only; the observer must not advance or mutate the combat simulation.
    var onCombatEvent: ((CombatEvent) -> Void)?
    private(set) var lastSimulationDeltaTime = 0.0
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
    private(set) var lastPlayerDodgeGrade: DodgeGrade?
    private(set) var rivalMomentTime = 0.0
    private(set) var rivalMomentGrade: DodgeGrade?
    private(set) var perfectCounterImpactTime = 0.0
    private(set) var perfectCounterCount = 0
    /// Real-seconds remaining in the dedicated knockout finishing-blow slow-motion + zoom beat.
    private(set) var koMomentTime = 0.0
    private(set) var message = LocalizationManager.shared.t(.tagline)
    private(set) var habits: HabitMemory
    var moveX = 0.0
    var moveY = 0.0

    private var previousPhase: FightPhase?
    private var enemyDecisionTimer = 0.5
    private var enemyFootwork = EnemyFootwork.none
    private var enemyFootworkTime = 0.0
    private var enemyGuardTime = 0.0
    private var enemyTacticTime = 0.0
    private var enemyCircleDirection = 1.0
    /// Next-decision intent: a timed entry or a short combination, never a permanent close stance.
    private var enemyFollowUp: Punch?
    private var enemyRecoveryChoice: String?
    private var observedPlayerAttackSerial: UInt64 = 0
    private var reactedToPlayerAttack = false
    private var random: RivalRandom
    private(set) var tacticalRead = RivalReadProfile.none
    private var storyLearning = StoryLearningState()
    private var storyRoundCommitted = false
    private var storyPolicyRound = 30
    private var usesAdaptiveRival: Bool { storyBout == nil || storyBout?.opponent == .rival }
    private var isStoryRival: Bool { storyBout?.opponent == .rival }
    var rivalDifficulty: RivalDifficulty {
        RivalDifficulty(round: storyBout == nil ? round : storyBout?.opponent == .rival ? storyPolicyRound : 8,
            championship: isStoryRival)
    }
    private var storyPressureRecovering = false
    private var storyPressureCombination = 0
    private var storyOutboxerRecovering = false
    private var storyOutboxerCombination = 0
    private var storyOutboxerExitTime = 0.0
    private var storyOutboxerStepTime = 0.0
    private var storyOutboxerStepCooldown = 0.0
    private var storyOutboxerStepTravel = 0.0
    private var storyOutboxerAngleTime = 0.0
    private var storyCounterRecovering = false
    private var storyCounterRetreatTime = 0.0
    private var storyCounterRecoveryPending = false
    private var storyCounterPunishDelay = 0.0
    private var storyCounterPunishTime = 0.0
    private var storyCounterProbeTime = 0.0
    private var storySluggerRecovering = false
    private var storySluggerCombination = 0
    private var storySluggerRecoveryTime = 0.0
    private var storySluggerAdvanceTime = 0.0
    private var storySluggerAdvanceCooldown = 0.0
    private var storySluggerEntryPending = false
    private var storyRivalCombination = 0
    private var storyRivalRecoveryTime = 0.0
    private var storyRivalReadCooldown = 0.0
    private var roundBreakTimer = 0.0
    private var roundBreakElapsedTime = 0.0
    private var advancesRoundAfterBreak = false
    private var roundHabits = HabitMemory()
    private(set) var playerAttackResults = RivalAttackMemory()
    private(set) var rivalAttackResults = RivalAttackMemory()
    private var roundPlayerAttackResults = RivalAttackMemory()
    private var roundRivalAttackResults = RivalAttackMemory()
    private var combatElapsedTime = 0.0
    private var playerDuckStartedAt: Double?
    private var playerWeaveStartedAt: Double?
    private var playerCounterWindowTime = 0.0
    private let defaults: UserDefaults?

    init(persistHabits: Bool = true, initialRound: Int = 1,
         randomSeed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max),
            storyOpponent: StoryOpponent? = nil, storyLearning: StoryLearningState = StoryLearningState()) {
        enemy = FighterModel(name: storyOpponent?.rawValue.uppercased() ?? "RIVAL", x: 420, y: 295,
            maximumHealth: storyOpponent == .slugger ? 120 : 100,
            punchReachBonus: storyOpponent == .slugger ? 4 : 0,
            punchDamageMultiplier: storyOpponent == .slugger ? 1.15 : 1)
        if storyOpponent == .outboxer { enemy.style = .outboxing }
        if storyOpponent == .slugger { enemy.style = .infighting }
        storyBout = storyOpponent.map { StoryBoutState(opponent: $0) }
        self.storyLearning = storyLearning
        defaults = persistHabits && storyOpponent == nil ? .standard : nil
        random = RivalRandom(seed: randomSeed)
        let initialHabits: HabitMemory
        if storyOpponent != nil {
            initialHabits = storyLearning.habits
        } else if let data = defaults?.data(forKey: "pixelBoxingHabitMemory"),
           let decoded = try? JSONDecoder().decode(HabitMemory.self, from: data) {
            initialHabits = decoded
        } else {
            initialHabits = HabitMemory()
        }
        habits = initialHabits
        if storyOpponent != nil {
            playerAttackResults = storyLearning.playerAttacks
            rivalAttackResults = storyLearning.opponentAttacks
        } else if let data = defaults?.data(forKey: "pixelBoxingRivalResults"),
           let profile = try? JSONDecoder().decode(RivalLearningProfile.self, from: data) {
            playerAttackResults = profile.playerAttacks
            rivalAttackResults = profile.rivalAttacks
        }
        round = max(1, initialRound)
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
        let rivalRead = tacticalRead
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
            playerLocked: player.exhausted > 0 || player.stagger > 0 || (storyBout.map { $0.phase != .fighting } ?? false),
            roundPlayerDodgeCount: roundPlayerDodgeCount,
            roundEnemyDodgeCount: roundEnemyDodgeCount,
            roundPlayerTopAttack: Self.topAttack(from: roundPlayerPunchCounts),
            roundEnemyTopAttack: Self.topAttack(from: roundEnemyPunchCounts),
            roundFinishingPunch: roundFinishingPunch,
            roundFinishingBlowByPlayer: roundFinishingBlowByPlayer,
            canAdvanceRound: storyRoundTransition == nil
                && (storyBout?.canStartNextRound ?? (phase == .roundBreak && roundBreakTimer <= 0)),
            showsRoundResult: phase == .roundBreak && (storyBout == nil || storyBout?.phase == .finished) && roundBreakElapsedTime >= (
                lastRoundWasKnockout
                    ? CombatPresentationTiming.knockoutResultReveal
                    : CombatPresentationTiming.decisionResultReveal
            ),
            lastPlayerDodgeGrade: lastPlayerDodgeGrade,
            perfectCounterCount: perfectCounterCount,
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
        if let storyBout { self.storyBout = StoryBoutState(opponent: storyBout.opponent, rules: storyBout.rules) }
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

    func startRound(emitsStartEvent: Bool = true) {
        storyRoundTransition = nil
        player.reset(x: 170, y: 295)
        enemy.reset(x: 420, y: 295)
        if let storyBout {
            round = storyBout.round
            habits = storyLearning.habits
            playerAttackResults = storyLearning.playerAttacks
            rivalAttackResults = storyLearning.opponentAttacks
            storyPolicyRound = 30 + min(100, storyLearning.championshipRounds) * 2
            switch storyBout.opponent {
            case .outboxer: enemy.style = .outboxing
            case .slugger: enemy.style = .infighting
            case .pressure, .counter, .rival: enemy.style = .standard
            }
        }
        phase = .fight
        roundTime = storyBout?.rules.roundSeconds ?? CombatData.roundSeconds
        roundBreakTimer = 0
        roundBreakElapsedTime = 0
        lastSimulationDeltaTime = 0
        advancesRoundAfterBreak = false
        enemyDecisionTimer = 0.55
        enemyFootwork = .none
        enemyFootworkTime = 0
        enemyGuardTime = 0
        enemyTacticTime = 0
        enemyCircleDirection = random.unit() < 0.5 ? -1 : 1
        enemyFollowUp = nil
        enemyRecoveryChoice = nil
        observedPlayerAttackSerial = 0
        reactedToPlayerAttack = false
        tacticalRead = usesAdaptiveRival ? habits.rivalRead : .none
        storyRoundCommitted = false
        storyPressureRecovering = false
        storyPressureCombination = 0
        storyOutboxerRecovering = false
        storyOutboxerCombination = 0
        storyOutboxerExitTime = 0
        storyOutboxerStepTime = 0
        storyOutboxerStepCooldown = 0.35
        storyOutboxerStepTravel = 0
        storyOutboxerAngleTime = 0
        storyCounterRecovering = false
        storyCounterRetreatTime = 0
        storyCounterRecoveryPending = false
        storyCounterPunishDelay = 0
        storyCounterPunishTime = 0
        storyCounterProbeTime = storyBout?.opponent == .counter ? 8 + random.unit() * 4 : 0
        storySluggerRecovering = false
        storySluggerCombination = 0
        storySluggerRecoveryTime = 0
        storySluggerAdvanceTime = 0
        storySluggerAdvanceCooldown = 0.70
        storySluggerEntryPending = false
        storyRivalCombination = 0
        storyRivalRecoveryTime = 0
        storyRivalReadCooldown = 0.50
        roundHabits = HabitMemory()
        roundPlayerAttackResults = RivalAttackMemory()
        roundRivalAttackResults = RivalAttackMemory()
        roundPlayerDodgeCount = 0
        roundEnemyDodgeCount = 0
        roundPlayerPunchCounts = [:]
        roundEnemyPunchCounts = [:]
        roundFinishingPunch = nil
        roundFinishingBlowByPlayer = false
        lastPlayerDodgeGrade = nil
        rivalMomentTime = 0
        rivalMomentGrade = nil
        perfectCounterImpactTime = 0
        koMomentTime = 0
        playerCounterWindowTime = 0
        playerDuckStartedAt = nil
        playerWeaveStartedAt = nil
        combatElapsedTime = 0
        message = LocalizationManager.shared.t(.fightStarted)
        if emitsStartEvent { onCombatEvent?(.roundStarted) }
    }

    func togglePause() {
        if phase == .fight || (storyBout != nil && phase == .roundBreak && storyBout?.phase != .finished) {
            cancelWeaveInput()
            previousPhase = phase
            phase = .paused
            message = LocalizationManager.shared.t(.pausedTitle)
        } else if phase == .paused {
            phase = previousPhase ?? .fight
            message = LocalizationManager.shared.t(.fightStarted)
        }
    }

    func resetLearning() {
        habits = HabitMemory()
        playerAttackResults = RivalAttackMemory()
        rivalAttackResults = RivalAttackMemory()
        defaults?.removeObject(forKey: "pixelBoxingHabitMemory")
        defaults?.removeObject(forKey: "pixelBoxingRivalResults")
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
        guard phase == .fight, player.attack == nil, player.exhausted <= 0, !player.weave.isActive else { return }
        player.guarding = true
    }

    func setDuck(_ direction: Int, active: Bool) {
        let clampedDirection = min(1, max(-1, direction))
        if !active || clampedDirection == 0 {
            player.duckDirection = 0
            if abs(player.duckMotion.direction) < DuckMotion.minimumEvadeAmount {
                playerDuckStartedAt = nil
            }
            return
        }
        guard phase == .fight, player.attack == nil, player.exhausted <= 0, !player.weave.isActive else { return }
        if player.duckDirection != clampedDirection {
            playerDuckStartedAt = combatElapsedTime
        }
        player.duckDirection = clampedDirection
    }

    @discardableResult
    func weave(direction: Int) -> Bool {
        guard phase == .fight else { return false }
        updateFacing()
        guard player.beginWeave(direction: direction) else { return false }
        playerDuckStartedAt = nil
        playerWeaveStartedAt = combatElapsedTime
        // A prior graded duck cannot lend its counter token to a new weave or its hook.
        playerCounterWindowTime = 0
        message = LocalizationManager.shared.t(direction < 0 ? .weaveLeftAccessibility : .weaveRightAccessibility)
        if player.stamina <= 0 { exhaust(player) }
        return true
    }

    @discardableResult
    func requestWeaveHook(base: Punch) -> Bool {
        guard phase == .fight, player.queueWeaveHook(base: base) else { return false }
        launchWeaveHook(player)
        return true
    }

    /// Called by pause/leave/suspend input. No refund and no queued motion on resume.
    func cancelWeaveInput() {
        player.weave.cancel()
        enemy.weave.cancel()
        playerWeaveStartedAt = nil
        moveX = 0
        moveY = 0
    }

    private func launchWeaveHook(_ fighter: FighterModel) {
        guard let hook = fighter.weave.takeReadyHook() else { return }
        _ = executeAttack(fighter, punch: hook, recordsHabit: fighter === player, fromWeave: true)
    }

    @discardableResult
    func backstep() -> Bool {
        let staminaCost = CombatData.backstepStaminaCost * player.style.backstepStaminaMultiplier
        guard phase == .fight, player.attack == nil, player.stagger <= 0, player.exhausted <= 0,
              !player.weave.isActive, !player.backstep.isActive, player.stamina >= staminaCost else { return false }
        player.weave.cancel()
        player.stamina -= staminaCost
        player.backstep.start(facingX: player.facingX, facingY: player.facingY)
        message = LocalizationManager.shared.t(.backstepAccessibility)
        if player.stamina <= 0 { exhaust(player) }
        return true
    }

    @discardableResult
    func startAttack(_ fighter: FighterModel, punch: Punch, recordsHabit: Bool = false) -> Bool {
        executeAttack(fighter, punch: punch, recordsHabit: recordsHabit, fromWeave: false)
    }

    private func executeAttack(_ fighter: FighterModel, punch: Punch, recordsHabit: Bool, fromWeave: Bool) -> Bool {
        guard phase == .fight, fighter.attack == nil, fighter.stagger <= 0, fighter.exhausted <= 0,
              fighter.hp > 0, !fighter.knockedOut, !fighter.backstep.isActive, (!fighter.weave.isActive || fromWeave),
              let spec = CombatData.attacks[punch] else { return false }
          if fighter === enemy, isStoryRival, storyRivalRecoveryTime > 0 { return false }
        let staminaCost = spec.staminaCost * fighter.style.punchStaminaMultiplier
        guard fighter.stamina >= staminaCost else { return false }
        let defender = fighter === player ? enemy : player
        updateFacing()
        PunchContactGeometry.begin(fighter,
            target: PunchContactGeometry.target(defender, zone: spec.targetZone, defended: false),
            radius: PunchContactGeometry.radius(spec.targetZone))
        if !fromWeave { fighter.weave.cancel() }
        if fighter.streakAttack == punch {
            fighter.streakCount += 1
        } else {
            fighter.streakAttack = punch
            fighter.streakCount = 1
        }
        fighter.attack = punch
        fighter.attackSerial &+= 1
        fighter.actionTime = 0
        fighter.acted = false
        fighter.attackOutcome = nil
        fighter.pendingDodgeCounter = fighter === player && playerCounterWindowTime > 0
        if fighter.pendingDodgeCounter { playerCounterWindowTime = 0 }
        fighter.guarding = false
        fighter.stamina = max(0, fighter.stamina - staminaCost)
        fighter.attackContactFrame = PunchContactGeometry.contactFrame(fighter, defender: defender,
            punch: punch, spec: spec, time: 0)
        message = CombatCommentary.attackCall(punch, attacker: fighter.name, language: LocalizationManager.shared.language)
        if fighter.stamina <= 0 { exhaust(fighter) }
        if recordsHabit {
            roundHabits.noteAttack(punch)
        }
        if fighter === player {
            roundPlayerPunchCounts[punch, default: 0] += 1
        } else {
            enemyRecoveryChoice = nil
            roundEnemyPunchCounts[punch, default: 0] += 1
            if isStoryRival {
                storyRivalCombination += 1
                if storyRivalCombination >= 3 {
                    storyRivalCombination = 0
                    storyRivalRecoveryTime = spec.duration + 0.45
                    enemyFollowUp = nil
                }
            }
            // Consume the approach when the punch really starts (including queued weave hooks).
            // A separately queued follow-up may still close distance; otherwise recover jab spacing.
            switch enemyFootwork {
            case .advance, .cutOff:
                enemyFootwork = .none
                enemyFootworkTime = 0
            default:
                break
            }
        }
        onCombatEvent?(.attackStarted(fighter: fighter === player ? .player : .rival))
        return true
    }

    /// Manually advances out of `.roundBreak` into the next round. Round advancement used to happen
    /// automatically once `roundBreakTimer` expired; it now only clears the knockdown-fall animation and
    /// unlocks the round-result overlay's "next round" button, waiting for the player to explicitly confirm.
    func requestNextRound() {
        if let storyBout {
            guard phase == .roundBreak, storyBout.canStartNextRound, storyRoundTransition == nil else { return }
            storyRoundTransition = StoryRoundTransition(round: storyBout.round + 1)
            return
        }
        guard phase == .roundBreak, roundBreakTimer <= 0 else { return }
        if advancesRoundAfterBreak { round += 1 }
        highestRound = max(highestRound, round)
        persistProgress()
        startRound()
    }

    func update(deltaTime rawDeltaTime: Double) {
        lastSimulationDeltaTime = 0
        guard rawDeltaTime.isFinite else { return }
        let realDeltaTime = min(0.05, max(0, rawDeltaTime))
        guard realDeltaTime > 0 else { return }
        guard phase == .fight || phase == .roundBreak else { return }
        if phase == .fight { combatElapsedTime += realDeltaTime }
        // Read the active scale before expiring its grade; the last slowed frame must not jump to 1x.
        let rivalTimeScale = rivalMomentTime > 0 ? (rivalMomentGrade?.timeScale ?? 1) : 1
        rivalMomentTime = max(0, rivalMomentTime - realDeltaTime)
        if rivalMomentTime == 0 { rivalMomentGrade = nil }
        perfectCounterImpactTime = max(0, perfectCounterImpactTime - realDeltaTime)
        let hasKoMoment = koMomentTime > 0
        koMomentTime = max(0, koMomentTime - realDeltaTime)
        // The knockout finishing-blow beat always wins over a dodge focus beat -- a KO landed during a
        // perfect-counter window should read as "this finished him", not just "nice dodge".
        let timeScale: Double
        if hasKoMoment {
            timeScale = CombatData.koMomentTimeScale
        } else {
            timeScale = rivalTimeScale
        }
        let deltaTime = realDeltaTime * timeScale
        playerCounterWindowTime = max(0, playerCounterWindowTime - deltaTime)
        lastSimulationDeltaTime = deltaTime
        if phase == .roundBreak {
            if storyBout != nil {
                updateStoryIntermission(realDeltaTime, simulationDelta: deltaTime)
                return
            }
            roundBreakTimer = max(0, roundBreakTimer - deltaTime)
            roundBreakElapsedTime += deltaTime
            updateKnockdowns(deltaTime)
            return
        }
        guard phase == .fight else { return }

        roundTime = max(0, roundTime - (storyBout == nil ? deltaTime : realDeltaTime))
        updateFacing()
        let enemyWasWeaving = enemy.weave.isActive
        updatePlayerMovement(deltaTime)
        sampleHabits(storyBout == nil ? deltaTime : realDeltaTime)
        // Both weave clocks/positions must describe this frame before EITHER fighter can hit.
        for (fighter, other) in [(player, enemy), (enemy, player)] {
            if fighter === enemy, fighter.duckTime > 0 {
                fighter.duckTime = max(0, fighter.duckTime - deltaTime)
                if fighter.duckTime == 0 { fighter.duckDirection = 0 }
            }
            fighter.duckMotion.advance(direction: fighter.duckDirection, deltaTime: deltaTime)
            fighter.advancePoseTransition(deltaTime)
            fighter.guardAmount = DefensiveMotion.guardBlend(current: fighter.guardAmount,
                raised: fighter.guarding, deltaTime: deltaTime, reducedMotion: false)
            let retreat = fighter.backstep.advance(deltaTime)
            if retreat.x != 0 || retreat.y != 0 {
                moveFighter(fighter, byX: retreat.x, byY: retreat.y, avoiding: other)
            }
            let step = fighter.advanceWeave(deltaTime)
            if step.x != 0 || step.y != 0 {
                moveFighter(fighter, byX: step.x, byY: step.y, avoiding: other)
            }
        }
        if storyBout?.opponent == .outboxer { advanceStoryOutboxerMovement(deltaTime) }
        let playerPreviousTime = player.actionTime
        let enemyPreviousTime = enemy.actionTime
        advanceFighter(player, deltaTime)
        advanceFighter(enemy, deltaTime)
        let playerContact = prepareContact(player, previous: playerPreviousTime)
        let enemyContact = prepareContact(enemy, previous: enemyPreviousTime)
        let enemyFirst = (enemyContact?.frameOffset ?? .infinity) < (playerContact?.frameOffset ?? .infinity)
        let first = enemyFirst ? (fighter: enemy, contact: enemyContact) : (fighter: player, contact: playerContact)
        let second = enemyFirst ? (fighter: player, contact: playerContact) : (fighter: enemy, contact: enemyContact)
        updateFighter(first.fighter, contact: first.contact)
        guard phase == .fight else { return }
        updateFighter(second.fighter, contact: second.contact)
        guard phase == .fight else { return }
        // Newly launched hooks start at zero; don't credit them a full frame of attack time.
        // A hit earlier in this frame has already cancelled its recipient's buffer.
        launchWeaveHook(player)
        launchWeaveHook(enemy)
        // Like player movement above, don't add a full ordinary step on the weave's final tick.
        if !enemyWasWeaving { updateEnemy(deltaTime) }

        if roundTime <= 0 {
            finishRound(
                outcome: CombatData.roundOutcome(playerHP: player.hp, enemyHP: enemy.hp),
                knockout: false
            )
        }
    }

    private func updatePlayerMovement(_ deltaTime: Double) {
        guard player.attack == nil, player.stagger <= 0, player.exhausted <= 0,
              !player.guarding, !player.weave.isActive, !player.backstep.isActive else { return }
        let magnitude = hypot(moveX, moveY)
        guard magnitude > 0.01 else { return }
        let forward = moveX / max(1, magnitude)
        let strafe = moveY / max(1, magnitude)
        let baseSpeed = CombatData.movementSpeed * (player.duckDirection == 0 ? 1 : 0.5)
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
        if player.attack == nil {
            player.facingX = dx / magnitude
            player.facingY = dy / magnitude
        }
        if enemy.attack == nil {
            enemy.facingX = -dx / magnitude
            enemy.facingY = -dy / magnitude
        }
    }

    private enum AttackContactEvent {
        case hit(PunchContactFrame)
        case evaded(RivalDefense, PunchContactFrame)
        case missed(RivalMissReason)

        var frame: PunchContactFrame? {
            switch self {
            case .hit(let frame), .evaded(_, let frame): frame
            case .missed: nil
            }
        }
    }

    private struct AttackContactAttempt {
        let punch: Punch
        let serial: UInt64
        let previousTime: Double
        let event: AttackContactEvent?

        var frameOffset: Double { event?.frame.map { $0.time - previousTime } ?? .infinity }
    }

    private func prepareContact(_ fighter: FighterModel, previous: Double) -> AttackContactAttempt? {
        guard let punch = fighter.attack, let spec = CombatData.attacks[punch] else {
            fighter.attackContactFrame = nil
            return nil
        }
        guard fighter.attackOutcome == nil else {
            return AttackContactAttempt(punch: punch, serial: fighter.attackSerial, previousTime: previous, event: nil)
        }
        let defender = fighter === player ? enemy : player
        let previousFrame = fighter.attackContactFrame ?? PunchContactGeometry.contactFrame(fighter,
            defender: defender, punch: punch, spec: spec, time: previous)
        let currentFrame = PunchContactGeometry.contactFrame(fighter, defender: defender,
            punch: punch, spec: spec, time: fighter.actionTime)
        fighter.attackContactFrame = currentFrame
        let event = previous <= spec.activeEnd && fighter.actionTime >= spec.activeStart
            ? evaluateContact(attacker: fighter, defender: defender, punch: punch, from: previousFrame, to: currentFrame) : nil
        return AttackContactAttempt(punch: punch, serial: fighter.attackSerial, previousTime: previous, event: event)
    }

    private func evaluateContact(attacker: FighterModel, defender: FighterModel, punch: Punch,
                                 from previous: PunchContactFrame, to current: PunchContactFrame) -> AttackContactEvent {
        guard let spec = CombatData.attacks[punch], current.defense.invulnerable <= 0 else {
            return .missed(.unavailable)
        }
        let hit = PunchContactGeometry.sweptContact(attacker, punch: punch, from: previous, to: current)
        var evasion: (defense: RivalDefense, frame: PunchContactFrame)?
        func consider(_ frame: PunchContactFrame?, defense: RivalDefense) {
            guard let frame,
                  hit == nil || frame.time < hit!.time || (defense == .backstep && frame.time == hit!.time),
                  evasion == nil || frame.time < evasion!.frame.time else { return }
            evasion = (defense: defense, frame: frame)
        }
        if previous.defense.backstep.isActive || current.defense.backstep.isActive {
            consider(PunchContactGeometry.sweptContact(attacker, punch: punch, from: previous, to: current,
                defense: .backstep), defense: .backstep)
            consider(PunchContactGeometry.sweptContact(attacker, punch: punch, from: previous, to: current,
                defended: false, defense: .backstep), defense: .backstep)
        }
        if let required = CombatData.requiredDuck[punch] {
            if max(previous.defense.duck.direction * Float(required), current.defense.duck.direction * Float(required))
                >= DuckMotion.minimumEvadeAmount {
                consider(PunchContactGeometry.sweptContact(attacker, punch: punch, from: previous, to: current,
                    defended: false, defense: .duck), defense: .duck)
            }
            if previous.defense.weave.direction == required || current.defense.weave.direction == required {
                consider(PunchContactGeometry.sweptContact(attacker, punch: punch, from: previous, to: current,
                    defended: false, defense: .weave), defense: .weave)
                if let origin = defender.weaveOrigin {
                    let scale = Float(CombatData.sceneScale)
                    let worldOrigin = SIMD3<Float>(Float(origin.x) * scale, 0, Float(origin.y) * scale)
                    func atOrigin(_ frame: PunchContactFrame) -> PunchContactFrame {
                        var result = frame
                        let defenderPosition = frame.attackerPosition
                            + SIMD3<Float>(frame.rootDelta.x * scale, 0, frame.rootDelta.y * scale)
                        result.standingTarget += worldOrigin - defenderPosition
                        result.rootDelta = SIMD2<Float>((worldOrigin.x - frame.attackerPosition.x) / scale,
                            (worldOrigin.z - frame.attackerPosition.z) / scale)
                        return result
                    }
                    consider(PunchContactGeometry.sweptContact(attacker, punch: punch, from: atOrigin(previous),
                        to: atOrigin(current), defended: false, defense: .weave), defense: .weave)
                }
            }
        }
        if let evasion { return .evaded(evasion.defense, evasion.frame) }
        if let hit { return .hit(hit) }
        let distance = simd_length(current.rootDelta)
        guard Double(distance) <= attacker.hitRange(punch) else { return .missed(.distance) }
        let facing = SIMD2<Float>(Float(attacker.facingX), Float(attacker.facingY))
        let dot = min(1, max(-1, simd_dot(current.rootDelta, facing) / max(0.001, distance)))
        guard acos(Double(dot)) * 180 / .pi <= spec.halfAngle else { return .missed(.angle) }
        return .missed(.contact)
    }

    private func advanceFighter(_ fighter: FighterModel, _ deltaTime: Double) {
        fighter.invulnerable = max(0, fighter.invulnerable - deltaTime)
        fighter.exhausted = max(0, fighter.exhausted - deltaTime)
        fighter.exposed = max(0, fighter.exposed - deltaTime)
        fighter.stagger = max(0, fighter.stagger - deltaTime)
        fighter.hitReaction = max(0, fighter.hitReaction - deltaTime)
        let isSluggerRecovery = fighter === enemy && storyBout?.opponent == .slugger
            && storySluggerRecovering
        if fighter.exhausted <= 0, fighter.attack == nil, (!fighter.guarding || isSluggerRecovery),
           fighter.duckDirection == 0, !fighter.weave.isActive {
            let recoveryPerSecond = isSluggerRecovery
                ? (fighter.guarding ? 6.0 : CombatData.staminaRecoveryPerSecond * 1.5)
                : CombatData.staminaRecoveryPerSecond
            fighter.stamina = min(100, fighter.stamina
                + recoveryPerSecond * deltaTime)
        }
        guard let punch = fighter.attack, let spec = CombatData.attacks[punch] else { return }
        let previous = fighter.actionTime
        fighter.actionTime += deltaTime
        let swingTime = PunchSwingTiming.cueTime(spec: spec)
        // Cross this boundary once on the simulation clock; cancelled/paused attacks cannot queue audio.
        if previous < swingTime, fighter.actionTime >= swingTime {
            onCombatEvent?(.punchSwing(fighter: fighter === player ? .player : .rival, punch: punch))
        }
    }

    private func updateFighter(_ fighter: FighterModel, contact: AttackContactAttempt?) {
        guard let punch = fighter.attack, let spec = CombatData.attacks[punch] else {
            fighter.attackContactFrame = nil
            return
        }
        guard let contact, contact.serial == fighter.attackSerial, contact.punch == punch else { return }
        let defender = fighter === player ? enemy : player
        if fighter.attackOutcome == nil, let event = contact.event {
            let outcome = attemptHit(attacker: fighter, defender: defender, punch: punch, event: event)
            let resolved: Bool
            if case .missed = outcome {
                resolved = fighter.actionTime >= spec.activeEnd
            } else {
                resolved = true
            }
            if resolved {
                fighter.attackOutcome = outcome
                fighter.acted = outcome.landed
                if fighter === player {
                    roundPlayerAttackResults.note(punch, outcome: outcome)
                } else {
                    roundRivalAttackResults.note(punch, outcome: outcome)
                }
                if storyBout?.phase == .finished {
                    announceStoryResult()
                }
                if storyBout == nil, outcome.landed, defender.knockedOut {
                    finishRound(outcome: defender === enemy ? .playerWin : .playerLoss, knockout: true)
                }
            }
        }
        if fighter.actionTime >= spec.duration {
            if !fighter.acted {
                fighter.exposed = max(fighter.exposed, CombatData.whiffRecovery)
                message = CombatCommentary.whiff(attacker: fighter.name, isPlayerAttacker: fighter === player, language: LocalizationManager.shared.language)
                whiffCount += 1
                lastWhiffByPlayer = fighter === player
                onCombatEvent?(.whiff(fighter: fighter === player ? .player : .rival))
            }
            if fighter === enemy, phase == .fight, let outcome = fighter.attackOutcome {
                planEnemyRecovery(after: punch, outcome: outcome)
            }
            fighter.attack = nil
            fighter.attackAim = nil
            fighter.attackEntryPose = nil
            fighter.actionTime = 0
            fighter.acted = false
            fighter.attackOutcome = nil
            fighter.attackContactFrame = nil
            fighter.pendingDodgeCounter = false
        }
    }

    @discardableResult
    private func attemptHit(attacker: FighterModel, defender: FighterModel, punch: Punch,
                            event: AttackContactEvent) -> RivalAttackOutcome {
        guard let spec = CombatData.attacks[punch], defender.hp > 0 else {
            return .missed(.unavailable)
        }
        let contactFrame: PunchContactFrame
        switch event {
        case .missed(let reason):
            return .missed(reason)
        case .evaded(.backstep, _):
            return .evaded(.backstep)
        case .evaded(let defense, _):
            let startedAt = defense == .weave ? playerWeaveStartedAt : playerDuckStartedAt
            let grade = defender === player
                ? playerDodgeGrade(startedAt: startedAt, entryDuration: DuckMotion.entryDuration) : .normal
            message = defense == .weave ? LocalizationManager.shared.t(.weaveEvadeMessage)
                : CombatCommentary.duckEvade(defender: defender.name, isPlayerDefender: defender === player,
                    language: LocalizationManager.shared.language)
            rewardDodge(attacker: attacker, defender: defender, grade: grade)
            return .evaded(defense)
        case .hit(let frame):
            contactFrame = frame
        }
        let contact = contactFrame.glove
        let interruptedPose = defender.attack != nil || defender.weave.isActive || defender.backstep.isActive
            ? PunchContactGeometry.samplePose(defender) : nil
        let dodgeCounter = attacker === player && attacker.pendingDodgeCounter
        let countered = defender.exposed > 0 || dodgeCounter
        let perfectCounter = dodgeCounter && lastPlayerDodgeGrade == .perfect
        let wasGuarding = contactFrame.defense.guarding && contactFrame.defense.guardAmount >= 0.65
        var guardBroken = false
        lastImpactGuarded = wasGuarding
        let staleStage = max(0, attacker.streakCount - CombatData.staleThreshold)
        let staleMultiplier = max(CombatData.staleFloor, pow(CombatData.staleDecay, Double(staleStage)))
        var damage = max(1, Int((Double(spec.damage) * staleMultiplier * attacker.style.damageMultiplier
            * attacker.punchDamageMultiplier).rounded()))
        if defender.exposed > 0 {
            damage = Int((Double(damage) * CombatData.exposedDamageMultiplier).rounded())
            if spec.family == .body || spec.family == .hook {
                damage = Int((Double(damage) * CombatData.bodyHookCounterMultiplier).rounded())
            }
        }
        if wasGuarding {
            let guardDamageMultiplier = CombatData.guardDamageMultiplier * defender.style.guardDamageMultiplier
            damage = max(1, Int((Double(damage) * guardDamageMultiplier).rounded()))
            let staminaDamage = max(
                CombatData.minimumGuardStaminaDamage,
                Double(spec.damage) * CombatData.guardStaminaDamageMultiplier * defender.style.guardStaminaMultiplier
            )
            defender.stamina = max(0, defender.stamina - staminaDamage)
            if defender.stamina <= 0 {
                defender.guarding = false
                guardBroken = true
                exhaust(defender, emitsFeedback: false)
                message = CombatCommentary.guardBreak(defender: defender.name, language: LocalizationManager.shared.language)
                guardBreakCount += 1
                lastGuardBreakByPlayer = defender === player
            } else {
                message = CombatCommentary.guardBlock(defender: defender.name, language: LocalizationManager.shared.language)
            }
        } else if perfectCounter {
            message = LocalizationManager.shared.t(.perfectCounter)
            perfectCounterCount += 1
            perfectCounterImpactTime = 0.24
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
        let appliedDamage = min(defender.hp, damage)
        defender.hp = max(0, defender.hp - damage)
        defender.hitReaction = 0.24
        defender.stagger = max(defender.stagger, CombatData.staggerLock)
        defender.weave.cancel()
        defender.backstep.cancel()
        if let interruptedPose {
            defender.poseTransition = FighterPoseTransition(source: interruptedPose,
                facingAngle: Float(atan2(defender.facingX, defender.facingY)))
        }
        if defender.attack != nil {
            defender.attack = nil
            defender.attackAim = nil
            defender.attackEntryPose = nil
            defender.attackOutcome = nil
            defender.attackContactFrame = nil
            defender.exposed = max(defender.exposed, CombatData.whiffRecovery)
        }
        if defender === enemy {
            enemyRecoveryChoice = nil
            enemyFollowUp = nil
        }
        let incoming = PunchContactGeometry.direction(attacker, punch: punch, contact: contact,
            progress: Float(contactFrame.time / spec.duration))
        let defenderOrigin = PunchContactGeometry.worldPoint(.zero, fighter: defender)
        storyBout?.recordImpact(by: attacker === player ? .player : .opponent,
                               damage: appliedDamage, guarded: wasGuarding, counter: countered && !wasGuarding)
        if defender.hp == 0 {
            storyBout?.knockdown(defender === player ? .player : .opponent, resolvedDamage: damage)
        }
        let resolvedImpact = CombatImpact(
            attacker: attacker === player ? .player : .rival,
            punch: punch,
            damage: appliedDamage,
            guarded: wasGuarding,
            guardBroken: guardBroken,
            counter: countered && !wasGuarding,
            perfectCounter: perfectCounter && !wasGuarding,
            knockout: defender.hp == 0 && (storyBout == nil || storyBout?.phase == .finished),
            contactPoint: PunchContactGeometry.localPoint(contact, fighter: defender),
            incomingDirection: PunchContactGeometry.localPoint(defenderOrigin + incoming, fighter: defender)
        )
        defender.lastImpact = resolvedImpact
        onCombatEvent?(.impact(resolvedImpact))
        if defender.hp == 0 {
            defender.knockedOut = true
            defender.poseTransition = nil
            roundFinishingPunch = punch
            roundFinishingBlowByPlayer = attacker === player
            if storyBout != nil {
                phase = .roundBreak
                roundBreakElapsedTime = 0
                cancelWeaveInput()
                player.backstep.cancel()
                enemy.backstep.cancel()
                rivalMomentTime = 0
                rivalMomentGrade = nil
                playerCounterWindowTime = 0
            }
        }
        return wasGuarding && !guardBroken ? .guarded : .hit
    }

    private func rewardDodge(attacker: FighterModel, defender: FighterModel, grade: DodgeGrade) {
        if defender === player {
            attacker.exposed = max(attacker.exposed, grade.counterWindow)
            successfulDodgeCount += 1
            roundPlayerDodgeCount += 1
            lastPlayerDodgeGrade = grade
            playerCounterWindowTime = grade.counterWindow
            if grade.focusDuration > 0, rivalMomentTime <= 0 {
                rivalMomentTime = grade.focusDuration
                rivalMomentGrade = grade
            }
        } else {
            attacker.exposed = max(attacker.exposed, CombatData.duckCounterWindow)
            roundEnemyDodgeCount += 1
            if storyBout?.opponent == .counter {
                storyCounterRecoveryPending = false
                storyCounterPunishDelay = 0
                storyCounterPunishTime = max(storyCounterPunishTime, 0.55)
                storyCounterRetreatTime = 0
                enemyDecisionTimer = min(enemyDecisionTimer, 0.04)
                let direction = defender.weave.comboDirection
                let base: Punch = direction < 0 ? .jab : .cross
                if defender.weave.isActive,
                   let hook = WeaveState.hook(base: base, direction: direction),
                   let spec = CombatData.attacks[hook],
                   defender.stamina >= spec.staminaCost * defender.style.punchStaminaMultiplier + 8,
                   PunchContactGeometry.canReach(defender, defender: attacker, punch: hook),
                   defender.queueWeaveHook(base: base) {
                    storyCounterPunishTime = 0
                    storyCounterRetreatTime = 0.35
                    enemyDecisionTimer = 0.55
                }
            }
        }
        if defender === enemy, isStoryRival, storyRivalRecoveryTime <= 0 {
            enemyRecoveryChoice = nil
            enemyDecisionTimer = min(enemyDecisionTimer, 0.04)
            let direction = defender.weave.comboDirection
            let base: Punch = direction < 0 ? .jab : .cross
            if defender.weave.isActive,
               let hook = WeaveState.hook(base: base, direction: direction),
               let spec = CombatData.attacks[hook],
               defender.stamina >= spec.staminaCost * defender.style.punchStaminaMultiplier + 8,
               PunchContactGeometry.canReach(defender, defender: attacker, punch: hook),
               defender.queueWeaveHook(base: base) {
                enemyFollowUp = nil
                enemyDecisionTimer = 0.32
            }
        }
        onCombatEvent?(.dodge(fighter: defender === player ? .player : .rival,
                             grade: defender === player ? grade : nil))
    }

    private func playerDodgeGrade(startedAt: Double?, entryDuration: Double) -> DodgeGrade {
        guard let startedAt else { return .normal }
        let leadTime = max(0, combatElapsedTime - startedAt - entryDuration)
        return switch leadTime {
        case ...0.12: .perfect
        case ...0.22: .accurate
        case ...0.36: .good
        default: .normal
        }
    }

    private func planEnemyRecovery(after punch: Punch, outcome: RivalAttackOutcome) {
        enemyRecoveryChoice = nil
        enemyFollowUp = nil
        guard usesAdaptiveRival else { return }
        if isStoryRival {
            guard storyRivalRecoveryTime <= 0 else { return }
            let remaining = max(0, (CombatData.attacks[punch]?.duration ?? 0) - enemy.actionTime)
            switch outcome {
            case .evaded, .missed:
                storyRivalCombination = 0
                storyRivalRecoveryTime = remaining + 0.24
                return
            case .hit, .guarded:
                if storyRivalCombination >= 2, enemy.stamina < 40 {
                    storyRivalCombination = 0
                    storyRivalRecoveryTime = remaining + 0.35
                    return
                }
            }
        }
        let policy = rivalDifficulty
        switch outcome {
        case .hit, .guarded:
            guard random.unit() < policy.combinationChance else { return }
        case .evaded, .missed:
            break
        }
        enemyRecoveryChoice = policy.recoveryChoice(after: punch, outcome: outcome,
            read: tacticalRead.kind, stamina: enemy.stamina, style: enemy.style)
    }

    private func updateEnemy(_ deltaTime: Double) {
        if let opponent = storyBout?.opponent, opponent != .rival {
            switch opponent {
            case .pressure: updateStoryPressure(deltaTime)
            case .outboxer: updateStoryOutboxer(deltaTime)
            case .counter: updateStoryCounter(deltaTime)
            case .slugger: updateStorySlugger(deltaTime)
            case .rival: break
            }
            return
        }
        if isStoryRival {
            storyRivalRecoveryTime = max(0, storyRivalRecoveryTime - deltaTime)
            storyRivalReadCooldown = max(0, storyRivalReadCooldown - deltaTime)
            if enemy.stagger > 0 || enemy.exhausted > 0 {
                storyRivalCombination = 0
                storyRivalRecoveryTime = max(storyRivalRecoveryTime, 0.20)
                enemyFollowUp = nil
                enemyRecoveryChoice = nil
            }
        }
        // Decision time continues during a punch, but never bypasses its existing recovery/lock.
        // Beginners still leave gaps; experienced rivals can connect two legal attacks.
        enemyDecisionTimer = max(0, enemyDecisionTimer - deltaTime)
        enemyFootworkTime = max(0, enemyFootworkTime - deltaTime)
        if enemyGuardTime > 0 {
            enemyGuardTime = max(0, enemyGuardTime - deltaTime)
            if enemyGuardTime == 0 { enemy.guarding = false }
        }
        enemyTacticTime = max(0, enemyTacticTime - deltaTime)
        let policy = rivalDifficulty
        if enemyTacticTime == 0 {
            enemyTacticTime = policy.tacticDuration
            if random.unit() < 0.35 { enemyCircleDirection *= -1 }
        }
          guard enemy.attack == nil, enemy.stagger <= 0, enemy.exhausted <= 0,
              !enemy.weave.isActive, !enemy.backstep.isActive else { return }
        if isStoryRival, enemy.exposed > 0 || storyRivalRecoveryTime > 0 {
            enemyFollowUp = nil
            enemyRecoveryChoice = nil
            enemyFootwork = .retreat
            enemyFootworkTime = max(enemyFootworkTime, 0.12)
            applyEnemyFootwork(deltaTime, distance: hypot(player.x - enemy.x, player.y - enemy.y))
            return
        }
        guard !enemy.guarding else { return }
        guard enemy.duckDirection == 0 else { return }
        if reactToVisibleAttack(policy: policy) {
            enemyRecoveryChoice = nil
            return
        }
        let initialDistance = hypot(player.x - enemy.x, player.y - enemy.y)
        applyEnemyFootwork(deltaTime, distance: initialDistance)
        let distance = hypot(player.x - enemy.x, player.y - enemy.y)
        guard enemyDecisionTimer <= 0 else { return }
        enemyDecisionTimer = policy.decisionInterval + random.unit() * policy.decisionJitter
        let weights = enemyActionWeights(distance: distance)
        if let choice = enemyRecoveryChoice {
            enemyRecoveryChoice = nil
            let canGuard = choice == "guard" && enemy.stamina > CombatData.minimumGuardStaminaDamage
                && distance <= CombatData.hitRange(.jab, style: player.style) + 7
            if (weights[choice, default: 0] > 0 || canGuard), performEnemyDecision(choice) { return }
        }
        if let followUp = enemyFollowUp {
            enemyFollowUp = nil
            if weights[followUp.rawValue, default: 0] > 0,
               enemy.stamina >= (CombatData.attacks[followUp]?.staminaCost ?? 100) * enemy.style.punchStaminaMultiplier + 10,
               performEnemyDecision(followUp.rawValue) { return }
        }
          if isStoryRival, storyRivalReadCooldown <= 0, tacticalRead.confidence >= 0.60,
              let response = policy.learnedDecision(read: tacticalRead.kind, distance: distance, style: enemy.style) {
                storyRivalReadCooldown = 1.1 + random.unit() * 0.50
                if random.unit() < 0.50 + 0.25 * tacticalRead.confidence,
                    weights[response, default: 0] > 0, performEnemyDecision(response) { return }
          }
        let choice = weightedChoice(weights)
        _ = performEnemyDecision(choice)
    }

    /// Only public combat state after visible windup is observed: no queued touch input or future hits.
    /// One probabilistic reaction attempt per swing, with real startup delay even at very high rounds.
    /// A weave's pending hook is intentionally invisible here; observe it only after execution.
    private func reactToVisibleAttack(policy: RivalDifficulty) -> Bool {
        guard let punch = player.attack, let spec = CombatData.attacks[punch] else {
            reactedToPlayerAttack = false
            return false
        }
        if observedPlayerAttackSerial != player.attackSerial {
            observedPlayerAttackSerial = player.attackSerial
            reactedToPlayerAttack = false
        }
        guard !reactedToPlayerAttack, player.actionTime >= policy.reactionDelay else { return false }
        reactedToPlayerAttack = true
        let distance = hypot(player.x - enemy.x, player.y - enemy.y)
        guard player.actionTime < spec.activeStart,
              distance <= CombatData.hitRange(punch, style: player.style) + 7 else { return false }
          let remaining = spec.activeStart - player.actionTime
        let evidenceBonus = tacticalRead.kind == .none ? 0 : 0.10 * tacticalRead.confidence * policy.experience
        guard random.unit() < min(0.82, policy.reactionChance + evidenceBonus) else { return false }
                if isStoryRival, remaining >= WeaveState.evadeStart + 0.012,
                     remaining < WeaveState.evadeEnd - 0.02,
                     let direction = CombatData.requiredDuck[punch], enemy.stamina >= WeaveState.staminaCost + 22,
                     random.unit() < 0.55, performEnemyDecision(direction < 0 ? "weave_left" : "weave_right") {
                        return true
                }
          if remaining >= DuckMotion.entryDuration + 0.015,
              let direction = CombatData.requiredDuck[punch], enemy.stamina > CombatData.dodgeStaminaCost + 8 {
            if performEnemyDecision(direction < 0 ? "dodge_left" : "dodge_right") {
                enemyFollowUp = direction < 0 ? .rightBody : .leftBody
                return true
            }
        }
          if remaining >= BackstepState.evadeStart + 0.015, spec.targetZone == .body,
              enemy.stamina > CombatData.backstepStaminaCost * enemy.style.backstepStaminaMultiplier + 12,
           random.unit() < 0.45, performEnemyDecision("dodge_back") { return true }
        return performEnemyDecision("guard")
    }

    /// Runtime action mask: don't burn a whole decision on an unaffordable/out-of-range punch.
    /// Both fighters use the shared hit range and unchanged stamina/attack timing rules.
    func enemyActionWeights(distance: Double) -> [String: Double] {
        let policy = rivalDifficulty
        var weights = habits.snapshot.enemyWeights(distance: distance, playerExposed: player.exposed > 0,
                                                  rivalRead: tacticalRead, learningMultiplier: policy.learningWeight,
                                                  style: enemy.style)
        rivalAttackResults.adjustWeights(&weights, against: playerAttackResults, policy: policy)
        var hasReachableAttack = false
        var headTarget: SIMD3<Float>?
        var bodyTarget: SIMD3<Float>?
        var entryPose: FightPose?
        for punch in Punch.allCases {
            guard let spec = CombatData.attacks[punch] else { continue }
            if enemy.stamina < spec.staminaCost * enemy.style.punchStaminaMultiplier ||
                distance > CombatData.hitRange(punch, style: enemy.style) {
                weights[punch.rawValue] = 0
                continue
            }
            let center: SIMD3<Float>
            if spec.targetZone == .head {
                center = headTarget ?? PunchContactGeometry.target(player, zone: .head, defended: false)
                headTarget = center
            } else {
                center = bodyTarget ?? PunchContactGeometry.target(player, zone: .body, defended: false)
                bodyTarget = center
            }
            if entryPose == nil { entryPose = PunchContactGeometry.stance(enemy) }
            if !PunchContactGeometry.canReach(enemy, defender: player, punch: punch,
                                             targetCenter: center, entryPose: entryPose) {
                weights[punch.rawValue] = 0
            } else {
                hasReachableAttack = true
                weights[punch.rawValue, default: 0] *= policy.attackCommitment
                if enemy.streakAttack == punch, enemy.streakCount >= CombatData.staleThreshold {
                    weights[punch.rawValue, default: 0] *= 0.25
                }
            }
        }
        let threatDistance = CombatData.hitRange(.jab, style: player.style) + 7
        if enemy.stamina < CombatData.dodgeStaminaCost || distance > threatDistance {
            weights["dodge_left"] = 0
            weights["dodge_right"] = 0
        }
        if enemy.stamina < CombatData.backstepStaminaCost * enemy.style.backstepStaminaMultiplier || distance > threatDistance {
            weights["dodge_back"] = 0
        }
        if enemy.stamina <= CombatData.minimumGuardStaminaDamage || distance > threatDistance {
            weights["guard"] = 0
        }
        if enemy.stamina < 25 {
            weights["retreat", default: 0] += 2
            weights["wait", default: 0] += 1
        }
        weights["wait", default: 0] += (1 - policy.experience) * 1.4
        if distance > CombatData.hitRange(.jab, style: enemy.style) { weights["advance", default: 0] += 2 }
        if !hasReachableAttack, enemy.stamina >= 25 { weights["advance", default: 0] += 2 }
        if distance <= CombatData.minimumFighterSeparation + 2 { weights["advance"] = 0 }
        return weights
    }

    @discardableResult
    func performEnemyDecision(_ choice: String) -> Bool {
        guard phase == .fight, !enemy.knockedOut, enemy.attack == nil,
              enemy.stagger <= 0, enemy.exhausted <= 0, !enemy.weave.isActive,
              !enemy.backstep.isActive else { return false }
        if let punch = Punch(rawValue: choice) {
            return startAttack(enemy, punch: punch)
        } else if let footwork = EnemyFootwork(decision: choice) {
            if isStoryRival {
                switch footwork {
                case .advance, .cutOff, .circleLeft, .circleRight:
                    guard enemy.stamina >= 34 else { return false }
                    enemy.stamina -= 4
                case .none, .retreat:
                    break
                }
            }
            enemyFootwork = footwork
            enemyFootworkTime = isStoryRival ? 0.18 + random.unit() * 0.10 : 0.40 + random.unit() * 0.35
            if isStoryRival { enemyDecisionTimer = min(enemyDecisionTimer, enemyFootworkTime + 0.02) }
            switch footwork {
            case .advance, .cutOff:
                let punch = rivalDifficulty.entryPunch(read: tacticalRead.kind)
                if enemyFollowUp == nil, enemy.stamina >= 25,
                   let spec = CombatData.attacks[punch],
                   enemy.stamina >= spec.staminaCost * enemy.style.punchStaminaMultiplier + 10 {
                    // One legal attempt at the next decision, not continuous tactical crowding.
                    enemyFollowUp = punch
                }
            case .circleLeft, .circleRight:
                if isStoryRival { enemyFollowUp = rivalDifficulty.entryPunch(read: tacticalRead.kind) }
            default:
                break
            }
            return true
        } else if choice == "guard" {
            guard enemy.stamina > CombatData.minimumGuardStaminaDamage else { return false }
            enemy.guarding = true
            let incomingContact = player.attack.flatMap { CombatData.attacks[$0]?.activeStart } ?? 0
            enemyGuardTime = max(0.18 + random.unit() * 0.12, incomingContact - player.actionTime + 0.08)
            return true
        } else if choice == "dodge_left" || choice == "dodge_right" {
            guard enemy.stamina >= CombatData.dodgeStaminaCost else { return false }
            enemy.stamina -= CombatData.dodgeStaminaCost
            enemy.duckDirection = choice == "dodge_left" ? -1 : 1
            enemy.duckTime = CombatData.enemyDuckDuration
            if enemy.stamina <= 0 {
                exhaust(enemy)
                enemy.duckDirection = 0
            }
            message = CombatCommentary.enemyDuck(direction: choice == "dodge_left" ? -1 : 1, language: LocalizationManager.shared.language)
            return true
        } else if choice == "weave_left" || choice == "weave_right" {
            return enemy.beginWeave(direction: choice == "weave_left" ? -1 : 1)
        } else if choice == "dodge_back" {
            let cost = CombatData.backstepStaminaCost * enemy.style.backstepStaminaMultiplier
            guard enemy.stamina >= cost else { return false }
            enemy.stamina -= cost
            enemy.backstep.start(facingX: enemy.facingX, facingY: enemy.facingY)
            if enemy.stamina <= 0 { exhaust(enemy) }
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
        let policy = rivalDifficulty
        var targetDistance = policy.preferredDistance(read: tacticalRead.kind, stamina: enemy.stamina, style: enemy.style)
        if let punch = enemyFollowUp, enemy.stamina >= 25 {
            targetDistance = min(targetDistance, CombatData.hitRange(punch, style: enemy.style) * 0.82)
        }
        targetDistance = max(CombatData.minimumFighterSeparation + 1, targetDistance)
        var forward = min(1, max(-1, (distance - targetDistance) / 18))
        var strafe = enemyCircleDirection * (0.18 + 0.40 * policy.experience)
        let footwork = enemyFootworkTime > 0 ? enemyFootwork : .none
        switch footwork {
        case .none:
            if tacticalRead.kind == .retreatPattern { strafe = -moveY * 0.6 }
        case .advance:
            // Advancing must not suppress backward correction after an overshoot/player approach.
            forward = distance > targetDistance ? 1 : forward
            strafe *= 0.35
        case .retreat:
            forward = distance < CombatData.hitRange(.jab, style: player.style) + 10 ? -0.8 : forward
        case .circleLeft:
            strafe = -0.8
        case .circleRight:
            strafe = 0.8
        case .cutOff:
            // moveY is ALREADY player-relative strafe. The rival's right basis is its opposite.
            forward = distance > targetDistance ? 1 : forward
            strafe = -moveY / max(1, hypot(moveX, moveY)) * 0.65
        }
        if distance > CombatData.hitRange(.jab, style: enemy.style) + 12 { forward = 1; strafe *= 0.3 }
        let magnitude = max(1, hypot(forward, strafe))
        forward /= magnitude
        strafe /= magnitude
        let speed = CombatData.movementSpeed * policy.movementEffort
        let forwardSpeed = speed * (forward < 0 ? CombatData.backwardMoveSpeedMultiplier : enemy.style.moveSpeedMultiplier)
        let strafeSpeed = speed * enemy.style.moveSpeedMultiplier
        let oldX = enemy.x
        let oldY = enemy.y
        moveFighter(enemy,
                    byX: (towardPlayerX * forward * forwardSpeed + rightX * strafe * strafeSpeed) * deltaTime,
                    byY: (towardPlayerY * forward * forwardSpeed + rightY * strafe * strafeSpeed) * deltaTime,
                    avoiding: player)
        if hypot(enemy.x - oldX, enemy.y - oldY) < speed * deltaTime * 0.1 {
            enemyCircleDirection *= -1
            enemyFootwork = enemyCircleDirection < 0 ? .circleLeft : .circleRight
            enemyFootworkTime = 0.35
        }
    }

    private func weightedChoice(_ weights: [String: Double]) -> String {
        let total = weights.values.reduce(0, +)
        var cursor = random.unit() * max(total, 0.001)
        for (key, weight) in weights.sorted(by: { $0.key < $1.key }) {
            guard weight > 0 else { continue }
            cursor -= weight
            if cursor <= 0 { return key }
        }
        return "wait"
    }

    private func sampleHabits(_ deltaTime: Double) {
        // Input is already (forward, strafe), not a world-space vector. Don't learn movement that
        // was blocked by attack/guard/exhaustion, or rotate the same intent differently around the ring.
        let canMove = player.attack == nil && player.stagger <= 0 && player.exhausted <= 0
            && !player.guarding && !player.weave.isActive && !player.backstep.isActive
        let forwardAxis = canMove ? moveX / max(1, hypot(moveX, moveY)) : 0
        let duckDirection = storyBout != nil && player.weave.isActive ? player.weave.direction : player.duckDirection
        roundHabits.sample(deltaTime: deltaTime, guarding: player.guarding, duckDirection: duckDirection,
                   backstep: player.backstep.isActive, forwardAxis: forwardAxis)
    }

    func finishRound(outcome: RoundOutcome, knockout: Bool) {
        guard phase == .fight else { return }
        if storyBout != nil {
            storyBout?.finishRound()
            commitStoryRoundLearning()
            cancelWeaveInput()
            player.backstep.cancel()
            enemy.backstep.cancel()
            phase = .roundBreak
            roundBreakElapsedTime = 0
            if storyBout?.phase == .finished { announceStoryResult() }
            return
        }
        cancelWeaveInput()
        player.backstep.cancel()
        enemy.backstep.cancel()
        phase = .roundBreak
        roundBreakElapsedTime = 0
        lastRoundOutcome = outcome
        lastRoundWasKnockout = knockout
        if knockout {
            koMomentTime = CombatData.koMomentDuration
        }
        advancesRoundAfterBreak = outcome == .playerWin
        habits.incorporateRound(roundHabits)
        playerAttackResults.incorporateRound(roundPlayerAttackResults)
        rivalAttackResults.incorporateRound(roundRivalAttackResults)
        tacticalRead = habits.rivalRead
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
            case .playerWin: message = LocalizationManager.shared.t(.roundWon)
            case .playerLoss: message = LocalizationManager.shared.t(.roundLostMessage)
            case .draw: message = LocalizationManager.shared.t(.drawMessage)
            }
        }
        saveHabits()
        persistProgress()
        onCombatEvent?(.roundEnded(outcome: outcome, knockout: knockout))
    }

    private func chooseStoryOutboxerDirection() {
        enemyCircleDirection = random.unit() < 0.5 ? -1 : 1
        enemyTacticTime = 0.40 + random.unit() * 1.40
    }

    private func advanceStoryOutboxerMovement(_ deltaTime: Double) {
        storyOutboxerExitTime = max(0, storyOutboxerExitTime - deltaTime)
        storyOutboxerStepCooldown = max(0, storyOutboxerStepCooldown - deltaTime)
        storyOutboxerAngleTime = max(0, storyOutboxerAngleTime - deltaTime)
        enemyTacticTime = max(0, enemyTacticTime - deltaTime)
        if enemy.stamina < 28 { storyOutboxerRecovering = true }
        if enemy.stamina >= 56 { storyOutboxerRecovering = false }
        if enemy.stagger > 0 || enemy.exhausted > 0 {
            storyOutboxerStepTime = 0
            storyOutboxerStepTravel = 0
            storyOutboxerAngleTime = 0
            storyOutboxerCombination = 0
        }
        if storyOutboxerRecovering || storyOutboxerExitTime > 0 || enemy.exposed > 0 {
            storyOutboxerStepTime = 0
            storyOutboxerStepTravel = 0
            storyOutboxerAngleTime = 0
        }
        let movingPunch = enemy.attack == .jab || enemy.attack == .cross
        guard enemy.attack == nil || movingPunch,
              enemy.stagger <= 0, enemy.exhausted <= 0, !enemy.guarding,
              enemy.duckDirection == 0, !enemy.weave.isActive, !enemy.backstep.isActive else { return }
        if movingPunch, storyOutboxerRecovering || enemy.exposed > 0 { return }
        if enemyTacticTime == 0, storyOutboxerStepTime <= 0, enemy.attack == nil {
            chooseStoryOutboxerDirection()
        }
        let distance = hypot(player.x - enemy.x, player.y - enemy.y)
        let targetDistance = enemy.hitRange(.jab) * 0.79
        let stepping = storyOutboxerStepTime > 0
        var forward = min(0.75, max(-0.80, (distance - targetDistance) / 20))
        var strafe = enemyCircleDirection * (stepping ? 0.85 : 0.52)
        if stepping { forward = min(0.35, max(-0.35, forward)) }
        if movingPunch {
            forward = min(0.15, max(-0.20, forward))
            strafe = enemyCircleDirection * (stepping ? 0.75 : 0.60)
        } else if storyOutboxerRecovering || storyOutboxerExitTime > 0 {
            forward = distance < targetDistance + 9 ? -0.70 : 0
            strafe = enemyCircleDirection * (storyOutboxerRecovering ? 0.36 : 0.72)
        }
        if enemy.exposed > 0 { forward = 0; strafe *= 0.30 }
        let edge = CombatData.ringMinimum + CombatData.fighterMargin + 26
        let farEdge = CombatData.ringMaximum - CombatData.fighterMargin - 26
        if enemy.x < edge || enemy.x > farEdge || enemy.y < edge || enemy.y > farEdge {
            let centerX = 295 - enemy.x
            let centerY = 295 - enemy.y
            let centerDistance = max(1, hypot(centerX, centerY))
            forward = min(0.65, max(-0.65,
                (centerX * enemy.facingX + centerY * enemy.facingY) / centerDistance))
            strafe = min(0.80, max(-0.80,
                (-centerX * enemy.facingY + centerY * enemy.facingX) / centerDistance))
            if abs(strafe) > 0.1 { enemyCircleDirection = strafe < 0 ? -1 : 1 }
            if movingPunch { forward = min(0.15, max(-0.20, forward)) }
        }
        let effort = movingPunch ? 0.42 : stepping || storyOutboxerExitTime > 0 ? 0.76 : 0.62
        let speed = CombatData.movementSpeed * enemy.style.moveSpeedMultiplier * effort
        let forwardSpeed = forward < 0 ? speed * CombatData.backwardMoveSpeedMultiplier : speed
        let strafeSpeed = speed * (movingPunch ? 1.50 : stepping ? 1.35 : 1.40)
        let previousX = enemy.x
        let previousY = enemy.y
        moveFighter(enemy,
            byX: (enemy.facingX * forward * forwardSpeed - enemy.facingY * strafe * strafeSpeed) * deltaTime,
            byY: (enemy.facingY * forward * forwardSpeed + enemy.facingX * strafe * strafeSpeed) * deltaTime,
            avoiding: player)
        if stepping {
            storyOutboxerStepTravel += abs(-(enemy.x - previousX) * enemy.facingY
                + (enemy.y - previousY) * enemy.facingX)
            storyOutboxerStepTime = max(0, storyOutboxerStepTime - deltaTime)
            if storyOutboxerStepTime == 0 {
                if storyOutboxerStepTravel >= 8 {
                    storyOutboxerAngleTime = 0.40
                    enemyDecisionTimer = min(enemyDecisionTimer, 0.04)
                } else {
                    enemyTacticTime = min(enemyTacticTime, 0.12 + random.unit() * 0.15)
                }
                storyOutboxerStepTravel = 0
            }
        }
    }

    private func beginStoryOutboxerStep() -> Bool {
        guard !storyOutboxerRecovering, storyOutboxerExitTime <= 0,
              storyOutboxerStepTime <= 0, storyOutboxerStepCooldown <= 0,
              enemy.attack == nil, !enemy.guarding, enemy.duckDirection == 0,
              enemy.stagger <= 0, enemy.exhausted <= 0, enemy.exposed <= 0,
              !enemy.weave.isActive, !enemy.backstep.isActive, enemy.stamina >= 34 else { return false }
        enemy.stamina -= 4
        chooseStoryOutboxerDirection()
        storyOutboxerStepTime = 0.22 + random.unit() * 0.14
        storyOutboxerStepTravel = 0
        storyOutboxerStepCooldown = 0.55 + random.unit() * 0.65
        storyOutboxerAngleTime = 0
        return true
    }

    private func updateStoryOutboxer(_ deltaTime: Double) {
        enemyDecisionTimer = max(0, enemyDecisionTimer - deltaTime)
        if enemyGuardTime > 0 {
            enemyGuardTime = max(0, enemyGuardTime - deltaTime)
            if enemyGuardTime == 0 { enemy.guarding = false }
        }
        guard enemy.attack == nil, enemy.stagger <= 0, enemy.exhausted <= 0,
              !enemy.guarding, enemy.duckDirection == 0, !enemy.weave.isActive,
              !enemy.backstep.isActive else { return }
        let distance = hypot(player.x - enemy.x, player.y - enemy.y)
        if storyOutboxerStepTime <= 0, let punch = player.attack, let spec = CombatData.attacks[punch] {
            if observedPlayerAttackSerial != player.attackSerial {
                observedPlayerAttackSerial = player.attackSerial
                reactedToPlayerAttack = false
            }
            if !reactedToPlayerAttack,
               player.actionTime >= min(0.02, spec.activeStart * 0.15),
               player.actionTime < spec.activeStart,
               distance <= player.hitRange(punch) + 6, enemy.stamina > 30 {
                reactedToPlayerAttack = true
                if random.unit() < 0.60 {
                    let remaining = spec.activeStart - player.actionTime
                    if spec.targetZone == .head, remaining >= 0.02, beginStoryOutboxerStep() {
                        storyOutboxerCombination = 0
                        enemyDecisionTimer = min(enemyDecisionTimer, 0.04)
                    } else if spec.targetZone == .body, remaining >= BackstepState.evadeStart + 0.01,
                              performEnemyDecision("dodge_back") {
                        storyOutboxerCombination = 0
                        storyOutboxerAngleTime = 0
                        storyOutboxerExitTime = 0.25
                        return
                    } else if remaining >= 0.02, performEnemyDecision("guard") {
                        storyOutboxerCombination = 0
                        storyOutboxerAngleTime = 0
                        return
                    }
                }
            }
        }
        if player.attack == nil, enemyDecisionTimer <= 0, storyOutboxerCombination == 0,
           storyOutboxerAngleTime <= 0, distance <= enemy.hitRange(.jab) + 6,
           distance > CombatData.minimumFighterSeparation + 3 {
            _ = beginStoryOutboxerStep()
        }
          guard !storyOutboxerRecovering, storyOutboxerExitTime <= 0,
              enemy.exposed <= 0, enemyDecisionTimer <= 0 else { return }
          let attackDistance = hypot(player.x - enemy.x, player.y - enemy.y)
        var weights: [String: Double] = ["wait": 0.20, Punch.jab.rawValue: 4.2,
            Punch.cross.rawValue: 1.8, Punch.leftBody.rawValue: 0.45,
            Punch.rightBody.rawValue: 0.30, Punch.leftHook.rawValue: 0.35, Punch.rightHook.rawValue: 0.25]
        if storyOutboxerAngleTime > 0 || storyOutboxerStepTime > 0 {
            weights["wait"] = 0.08
            weights[Punch.jab.rawValue] = 4.8
            weights[Punch.cross.rawValue] = 2.4
        }
        for punch in Punch.allCases {
            guard let spec = CombatData.attacks[punch], weights[punch.rawValue] != nil else { continue }
            if enemy.stamina < spec.staminaCost * enemy.style.punchStaminaMultiplier + 10
                || attackDistance > enemy.hitRange(punch)
                || !PunchContactGeometry.canReach(enemy, defender: player, punch: punch) {
                weights[punch.rawValue] = 0
            }
        }
        let choice = storyOutboxerCombination == 1 && enemy.streakAttack == .jab
            && weights[Punch.cross.rawValue, default: 0] > 0 && random.unit() < 0.68
            ? Punch.cross.rawValue : weightedChoice(weights)
        if let punch = Punch(rawValue: choice), performEnemyDecision(choice) {
            storyOutboxerAngleTime = 0
            storyOutboxerCombination += 1
            let duration = CombatData.attacks[punch]?.duration ?? 0.24
            if storyOutboxerCombination >= 2 {
                storyOutboxerCombination = 0
                storyOutboxerExitTime = duration + 0.18 + random.unit() * 0.16
                enemyTacticTime = 0
                enemyDecisionTimer = storyOutboxerExitTime + 0.04 + random.unit() * 0.10
            } else {
                enemyDecisionTimer = duration + 0.02 + random.unit() * 0.05
            }
        } else {
            if storyOutboxerCombination > 0 {
                storyOutboxerExitTime = 0.18 + random.unit() * 0.16
                enemyTacticTime = 0
                enemyDecisionTimer = storyOutboxerExitTime + 0.08
            } else {
                enemyDecisionTimer = 0.14 + random.unit() * 0.10
            }
            storyOutboxerCombination = 0
        }
    }

    private func updateStoryPressure(_ deltaTime: Double) {
        enemyDecisionTimer = max(0, enemyDecisionTimer - deltaTime)
        if enemyGuardTime > 0 {
            enemyGuardTime = max(0, enemyGuardTime - deltaTime)
            if enemyGuardTime == 0 { enemy.guarding = false }
        }
        guard enemy.attack == nil, enemy.stagger <= 0, enemy.exhausted <= 0,
              !enemy.guarding, enemy.duckDirection == 0, !enemy.backstep.isActive else { return }
        if enemy.stamina < 25 { storyPressureRecovering = true }
        if enemy.stamina >= 50 { storyPressureRecovering = false }
        let distance = hypot(player.x - enemy.x, player.y - enemy.y)
        let targetDistance = max(CombatData.minimumFighterSeparation + 3,
                                 CombatData.hitRange(.leftHook, style: enemy.style) * 0.76)
        let reapproaching = !storyPressureRecovering && distance > targetDistance + 8
        let forward = storyPressureRecovering
            ? (distance < CombatData.hitRange(.jab, style: player.style) + 12 ? -0.65 : 0)
            : min(reapproaching ? 0.90 : 0.85, max(0, (distance - targetDistance) / 16))
        let strafe = enemyCircleDirection * (storyPressureRecovering ? 0.40 : 0.18)
        let speed = CombatData.movementSpeed * (reapproaching ? 0.70 : 0.60)
        let forwardSpeed = forward < 0 ? speed * CombatData.backwardMoveSpeedMultiplier : speed
        moveFighter(enemy,
            byX: (enemy.facingX * forward * forwardSpeed - enemy.facingY * strafe * speed) * deltaTime,
            byY: (enemy.facingY * forward * forwardSpeed + enemy.facingX * strafe * speed) * deltaTime,
            avoiding: player)
        if storyPressureRecovering { return }
        if let punch = player.attack, let spec = CombatData.attacks[punch] {
            if observedPlayerAttackSerial != player.attackSerial {
                observedPlayerAttackSerial = player.attackSerial
                reactedToPlayerAttack = false
            }
            if !reactedToPlayerAttack, player.actionTime >= 0.12, player.actionTime < spec.activeStart {
                reactedToPlayerAttack = true
                if distance <= CombatData.hitRange(punch, style: player.style) + 7,
                   enemy.stamina > 30, random.unit() < 0.16,
                   performEnemyDecision("guard") { return }
            }
        }
        guard enemyDecisionTimer <= 0 else { return }
        let attackDistance = hypot(player.x - enemy.x, player.y - enemy.y)
        var weights: [String: Double] = ["wait": 0.45, Punch.jab.rawValue: 1.7,
            Punch.cross.rawValue: 0.8, Punch.leftBody.rawValue: 2.1, Punch.rightBody.rawValue: 1.6,
            Punch.leftHook.rawValue: 1.4, Punch.rightHook.rawValue: 1.0]
        for punch in Punch.allCases {
            guard let spec = CombatData.attacks[punch], weights[punch.rawValue] != nil else { continue }
            if enemy.stamina < spec.staminaCost * enemy.style.punchStaminaMultiplier + 8
                || attackDistance > enemy.hitRange(punch)
                || !PunchContactGeometry.canReach(enemy, defender: player, punch: punch) {
                weights[punch.rawValue] = 0
            }
        }
        let choice = weightedChoice(weights)
        if let punch = Punch(rawValue: choice), performEnemyDecision(choice) {
            storyPressureCombination += 1
            let extendsCombination = storyPressureCombination == 2 && enemy.stamina >= 42
                && enemy.exposed <= 0 && attackDistance <= enemy.hitRange(.leftBody) && random.unit() < 0.35
            if storyPressureCombination >= 2 && !extendsCombination {
                storyPressureCombination = 0
                enemyDecisionTimer = 1.02
            } else {
                enemyDecisionTimer = (CombatData.attacks[punch]?.duration ?? 0.36) + 0.10
            }
        } else {
            enemyDecisionTimer = storyPressureCombination > 0 ? 0.45 : 0.18
            storyPressureCombination = 0
        }
    }

    private func updateStoryCounter(_ deltaTime: Double) {
        enemyDecisionTimer = max(0, enemyDecisionTimer - deltaTime)
        storyCounterRetreatTime = max(0, storyCounterRetreatTime - deltaTime)
        storyCounterPunishTime = max(0, storyCounterPunishTime - deltaTime)
        storyCounterProbeTime = max(0, storyCounterProbeTime - deltaTime)
        if storyCounterPunishDelay > 0 {
            storyCounterPunishDelay = max(0, storyCounterPunishDelay - deltaTime)
            if storyCounterPunishDelay == 0 { storyCounterPunishTime = max(storyCounterPunishTime, 0.45) }
        }
        if enemyGuardTime > 0 {
            enemyGuardTime = max(0, enemyGuardTime - deltaTime)
            if enemyGuardTime == 0 { enemy.guarding = false }
        }
        if let punch = player.attack, let spec = CombatData.attacks[punch], player.actionTime > 0 {
            if observedPlayerAttackSerial != player.attackSerial {
                observedPlayerAttackSerial = player.attackSerial
                reactedToPlayerAttack = false
                storyCounterRecoveryPending = true
                storyCounterPunishDelay = 0
                storyCounterPunishTime = 0
            }
            if storyCounterRecoveryPending, player.actionTime >= spec.activeEnd {
                storyCounterRecoveryPending = false
                storyCounterPunishDelay = 0.07
            }
        } else if player.attack == nil, storyCounterRecoveryPending {
            storyCounterRecoveryPending = false
            storyCounterPunishDelay = 0.07
        }
        if enemy.stamina < 28 { storyCounterRecovering = true }
        if enemy.stamina >= 56 { storyCounterRecovering = false }
        if enemy.stagger > 0 || enemy.exhausted > 0 {
            storyCounterRecoveryPending = false
            storyCounterPunishDelay = 0
            storyCounterPunishTime = 0
            return
        }
        guard enemy.attack == nil, !enemy.guarding, enemy.duckDirection == 0,
              !enemy.weave.isActive, !enemy.backstep.isActive else { return }
        let distance = hypot(player.x - enemy.x, player.y - enemy.y)
        let targetDistance = CombatData.hitRange(.cross, style: enemy.style) * 0.84
        var forward = min(0.55, max(-0.65, (distance - targetDistance) / 20))
        var strafe = enemyCircleDirection * 0.16
        if storyCounterRecovering || (storyCounterRetreatTime > 0 && storyCounterPunishTime <= 0) {
            forward = distance < targetDistance + 9 ? -0.60 : 0
            strafe = enemyCircleDirection * 0.12
        }
        if enemy.exposed > 0 { forward = 0; strafe = 0 }
        let speed = CombatData.movementSpeed * enemy.style.moveSpeedMultiplier * 0.52
        let forwardSpeed = forward < 0 ? speed * CombatData.backwardMoveSpeedMultiplier : speed
        moveFighter(enemy,
            byX: (enemy.facingX * forward * forwardSpeed - enemy.facingY * strafe * speed) * deltaTime,
            byY: (enemy.facingY * forward * forwardSpeed + enemy.facingX * strafe * speed) * deltaTime,
            avoiding: player)
        if !storyCounterRecovering, enemy.exposed <= 0,
           let punch = player.attack, let spec = CombatData.attacks[punch],
           observedPlayerAttackSerial == player.attackSerial, !reactedToPlayerAttack,
                            player.actionTime >= min(0.012, spec.activeStart * 0.10), player.actionTime < spec.activeStart {
                let remaining = spec.activeEnd - player.actionTime
            if distance <= CombatData.hitRange(punch, style: player.style) + 5,
                    enemy.stamina > 32 {
                     reactedToPlayerAttack = true
                                         guard random.unit() < (spec.targetZone == .body ? 0.80 : 0.92) else { return }
                if let direction = CombatData.requiredDuck[punch] {
                          if remaining >= WeaveState.evadeStart + 0.012,
                                                            spec.activeStart - player.actionTime < WeaveState.evadeEnd - 0.025, random.unit() < 0.70,
                       enemy.beginWeave(direction: direction) {
                        storyCounterRetreatTime = 0
                        enemyDecisionTimer = min(enemyDecisionTimer, 0.08)
                        return
                    }
                          if remaining >= DuckMotion.entryDuration * Double(DuckMotion.minimumEvadeAmount) + 0.010,
                       performEnemyDecision(direction < 0 ? "dodge_left" : "dodge_right") {
                                enemy.duckTime = max(0.18, remaining + 0.025)
                        storyCounterRetreatTime = 0
                        enemyDecisionTimer = min(enemyDecisionTimer, 0.08)
                        return
                    }
                }
                if spec.targetZone == .body, remaining >= BackstepState.evadeStart + 0.02,
                   enemy.stamina > CombatData.backstepStaminaCost * enemy.style.backstepStaminaMultiplier + 16,
                   random.unit() < 0.45, performEnemyDecision("dodge_back") {
                    storyCounterRetreatTime = 0.26
                    enemyDecisionTimer = min(enemyDecisionTimer, 0.08)
                    return
                }
                if remaining >= 0.045, performEnemyDecision("guard") {
                    storyCounterRetreatTime = 0.30
                    enemyDecisionTimer = min(enemyDecisionTimer, 0.12)
                    return
                }
            }
        }
        guard !storyCounterRecovering, enemy.exposed <= 0, enemyDecisionTimer <= 0 else { return }
        if storyCounterPunishTime > 0 {
            if let punch = player.attack, let spec = CombatData.attacks[punch],
               !(player.acted && player.exposed > 0) {
                guard observedPlayerAttackSerial == player.attackSerial,
                      player.actionTime >= spec.activeEnd + 0.07 else { return }
            }
            var weights: [String: Double] = ["wait": 0.25, Punch.jab.rawValue: player.attack == .jab ? 3.8 : 1.2,
                Punch.cross.rawValue: 3.4,
                Punch.leftHook.rawValue: 1.5, Punch.rightHook.rawValue: 1.7, Punch.rightBody.rawValue: 0.8]
            for punch in Punch.allCases {
                guard let spec = CombatData.attacks[punch], weights[punch.rawValue] != nil else { continue }
                if enemy.stamina < spec.staminaCost * enemy.style.punchStaminaMultiplier + 16
                    || !PunchContactGeometry.canReach(enemy, defender: player, punch: punch) {
                    weights[punch.rawValue] = 0
                }
            }
            let choice = weightedChoice(weights)
            if performEnemyDecision(choice) {
                if choice == Punch.jab.rawValue { storyCounterProbeTime = 8 + random.unit() * 4 }
                storyCounterPunishTime = 0
                storyCounterRetreatTime = 0.42
                enemyDecisionTimer = 0.65 + random.unit() * 0.15
            } else {
                enemyDecisionTimer = 0.12
            }
            return
        }
        guard player.attack == nil, storyCounterRetreatTime <= 0 else { return }
        if storyCounterProbeTime <= 0, storyCounterPunishDelay <= 0,
           let spec = CombatData.attacks[.jab],
           enemy.stamina >= spec.staminaCost * enemy.style.punchStaminaMultiplier + 24,
           hypot(player.x - enemy.x, player.y - enemy.y) <= enemy.hitRange(.jab),
           PunchContactGeometry.canReach(enemy, defender: player, punch: .jab),
           performEnemyDecision(Punch.jab.rawValue) {
            storyCounterProbeTime = 8 + random.unit() * 4
            storyCounterRetreatTime = 0.30
            enemyDecisionTimer = spec.duration + 0.30
            return
        }
        var weights: [String: Double] = ["wait": 1.8]
        if distance <= player.hitRange(.jab) + 4 {
            if enemy.stamina >= WeaveState.staminaCost + 22 {
                weights["weave_left"] = 0.45
                weights["weave_right"] = 0.45
            }
            if enemy.stamina >= CombatData.dodgeStaminaCost + 22 {
                weights["dodge_left"] = 0.25
                weights["dodge_right"] = 0.25
            }
        }
        _ = performEnemyDecision(weightedChoice(weights))
        enemyDecisionTimer = 0.55 + random.unit() * 0.20
    }

    private func updateStorySlugger(_ deltaTime: Double) {
        enemyDecisionTimer = max(0, enemyDecisionTimer - deltaTime)
        storySluggerRecoveryTime = max(0, storySluggerRecoveryTime - deltaTime)
        storySluggerAdvanceTime = max(0, storySluggerAdvanceTime - deltaTime)
        storySluggerAdvanceCooldown = max(0, storySluggerAdvanceCooldown - deltaTime)
        enemyGuardTime = max(0, enemyGuardTime - deltaTime)
        if enemyGuardTime == 0 { enemy.guarding = false }
        let minimumAttackCost = (CombatData.attacks.values.lazy.map(\.staminaCost).min() ?? 100)
            * enemy.style.punchStaminaMultiplier
        if enemy.stamina < minimumAttackCost, !storySluggerRecovering {
            storySluggerRecovering = true
            enemyGuardTime = 2.0
        }
        if storySluggerRecovering, enemy.stamina >= 45 {
            storySluggerRecovering = false
            storySluggerCombination = 0
            enemyDecisionTimer = 0
            enemy.guarding = false
            enemyGuardTime = 0
        }
        if enemy.stagger > 0 || enemy.exhausted > 0 {
            storySluggerCombination = 0
            storySluggerRecoveryTime = max(storySluggerRecoveryTime, 0.45)
            storySluggerAdvanceTime = 0
            storySluggerEntryPending = false
            return
        }
        guard enemy.attack == nil, (!enemy.guarding || storySluggerRecovering), enemy.duckDirection == 0,
              !enemy.weave.isActive, !enemy.backstep.isActive else { return }
        let distance = hypot(player.x - enemy.x, player.y - enemy.y)
        let targetDistance = max(CombatData.minimumFighterSeparation + 4,
                           enemy.hitRange(.leftHook) * 0.72)
        let canAdvance = !storySluggerRecovering && storySluggerRecoveryTime <= 0 && enemy.exposed <= 0
        if !canAdvance {
            storySluggerAdvanceTime = 0
            storySluggerEntryPending = false
        } else if storySluggerAdvanceCooldown <= 0, storySluggerCombination == 0,
                  !storySluggerEntryPending, enemy.invulnerable <= 0, enemy.stamina >= 48,
                  distance > targetDistance + 10, distance <= enemy.hitRange(.jab) + 60 {
            enemy.stamina -= 10
            storySluggerAdvanceTime = 0.52
            storySluggerAdvanceCooldown = 1.4 + random.unit() * 0.5
            storySluggerEntryPending = true
        }
        let advancing = storySluggerAdvanceTime > 0
        let closing = distance > enemy.hitRange(.leftHook)
        var forward = min(advancing ? 1 : closing ? 0.90 : 0.72,
            max(0, (distance - targetDistance) / (advancing ? 8 : closing ? 16 : 24)))
        var strafe = advancing ? 0 : enemyCircleDirection * 0.08
        if !canAdvance {
            forward = 0
            strafe = enemyCircleDirection * 0.04
        }
        let movementEffort = advancing ? 1.20 : closing ? 0.82 : 0.43
        let speed = CombatData.movementSpeed * enemy.style.moveSpeedMultiplier * movementEffort
        moveFighter(enemy,
            byX: (enemy.facingX * forward - enemy.facingY * strafe) * speed * deltaTime,
            byY: (enemy.facingY * forward + enemy.facingX * strafe) * speed * deltaTime,
            avoiding: player)
        let attackDistance = hypot(player.x - enemy.x, player.y - enemy.y)
        if storySluggerRecovering {
            storySluggerCombination = 0
            enemy.guarding = enemyGuardTime > 0
                && enemy.stamina > CombatData.minimumGuardStaminaDamage
            enemy.exposed = max(enemy.exposed, 0.16)
            return
        }
        guard storySluggerRecoveryTime <= 0, enemy.exposed <= 0 else { return }
        var weights: [String: Double] = ["wait": 0.40, Punch.jab.rawValue: 0.15,
            Punch.cross.rawValue: 0.35, Punch.leftHook.rawValue: 3.4, Punch.rightHook.rawValue: 3.8,
            Punch.leftBody.rawValue: 1.5, Punch.rightBody.rawValue: 1.4,
            Punch.leftUppercut.rawValue: 1.8, Punch.rightUppercut.rawValue: 2.0]
        if storySluggerEntryPending {
            weights = ["wait": 0.05, Punch.jab.rawValue: 0.15, Punch.cross.rawValue: 0.45,
                Punch.leftHook.rawValue: 4.6, Punch.rightHook.rawValue: 5.2,
                Punch.leftBody.rawValue: 1.6, Punch.rightBody.rawValue: 1.8,
                Punch.leftUppercut.rawValue: 2.4, Punch.rightUppercut.rawValue: 2.8]
        } else if storySluggerCombination > 0 {
            weights["wait"] = 0.15
            weights[Punch.jab.rawValue] = 0.15
            weights[Punch.cross.rawValue] = 0.35
            weights[Punch.leftHook.rawValue] = 4.6
            weights[Punch.rightHook.rawValue] = 5.2
            weights[Punch.leftUppercut.rawValue] = 2.6
            weights[Punch.rightUppercut.rawValue] = 3.0
        }
        var hasAvailableAttack = false
        for punch in Punch.allCases {
            guard let spec = CombatData.attacks[punch] else { continue }
            if enemy.stamina < spec.staminaCost * enemy.style.punchStaminaMultiplier
                || attackDistance > enemy.hitRange(punch)
                || !PunchContactGeometry.canReach(enemy, defender: player, punch: punch) {
                weights[punch.rawValue] = 0
            } else if (weights[punch.rawValue] ?? 0) > 0 {
                hasAvailableAttack = true
            }
        }
        if hasAvailableAttack {
            storySluggerAdvanceTime = 0
            enemyDecisionTimer = 0
            weights.removeValue(forKey: "wait")
        }
        guard storySluggerAdvanceTime <= 0, enemyDecisionTimer <= 0 else { return }
        let choice = weightedChoice(weights)
        if let punch = Punch(rawValue: choice), performEnemyDecision(choice) {
            storySluggerEntryPending = false
            storySluggerCombination += 1
            enemyDecisionTimer = CombatData.attacks[punch]?.duration ?? 0.43
        } else {
            storySluggerEntryPending = false
            enemyDecisionTimer = 0.08
        }
    }

    private func updateStoryIntermission(_ realDeltaTime: Double, simulationDelta: Double) {
        updateKnockdowns(simulationDelta)
        guard let storyBout else { return }
        if var transition = storyRoundTransition {
            transition.elapsed = min(StoryRoundTransition.duration, transition.elapsed + realDeltaTime)
            if transition.elapsed >= StoryRoundTransition.resetTime, storyBout.phase == .corner {
                self.storyBout?.beginNextRound()
                startRound(emitsStartEvent: false)
                phase = .roundBreak
            }
            if transition.elapsed >= StoryRoundTransition.duration {
                storyRoundTransition = nil
                phase = .fight
                onCombatEvent?(.roundStarted)
            } else {
                storyRoundTransition = transition
            }
            return
        }
        switch storyBout.phase {
        case .counting:
            let side = storyBout.countingSide
            if self.storyBout?.advanceCount(realDeltaTime) == true, let side {
                let fighter = side == .player ? player : enemy
                fighter.reset(x: fighter.x, y: fighter.y)
                fighter.hp = min(fighter.maximumHealth, max(1, storyBout.rules.getupHealth))
                fighter.stamina = min(100, max(0, storyBout.rules.getupStamina))
                fighter.invulnerable = 0.35
                phase = .fight
                enemyDecisionTimer = 0.55
                if storyBout.opponent == .outboxer {
                    storyOutboxerRecovering = false
                    storyOutboxerCombination = 0
                    storyOutboxerExitTime = 0
                    storyOutboxerStepTime = 0
                    storyOutboxerStepCooldown = 0.35
                    storyOutboxerStepTravel = 0
                    storyOutboxerAngleTime = 0
                    enemyGuardTime = 0
                    enemyTacticTime = 0
                    enemy.guarding = false
                    observedPlayerAttackSerial = 0
                    reactedToPlayerAttack = false
                }
                if storyBout.opponent == .counter || storyBout.opponent == .slugger || storyBout.opponent == .rival {
                    enemy.style = storyBout.opponent == .slugger ? .infighting : .standard
                    enemyFootwork = .none
                    enemyFootworkTime = 0
                    enemyGuardTime = 0
                    enemyTacticTime = 0
                    enemy.guarding = false
                    enemyFollowUp = nil
                    enemyRecoveryChoice = nil
                    observedPlayerAttackSerial = 0
                    reactedToPlayerAttack = false
                    storyCounterRecovering = false
                    storyCounterRetreatTime = 0
                    storyCounterRecoveryPending = false
                    storyCounterPunishDelay = 0
                    storyCounterPunishTime = 0
                    storyCounterProbeTime = storyBout.opponent == .counter ? 8 + random.unit() * 4 : 0
                    storySluggerRecovering = false
                    storySluggerCombination = 0
                    storySluggerRecoveryTime = 0
                    storySluggerAdvanceTime = 0
                    storySluggerAdvanceCooldown = 0.70
                    storySluggerEntryPending = false
                    storyRivalCombination = 0
                    storyRivalRecoveryTime = 0
                    storyRivalReadCooldown = 0.50
                }
                updateFacing()
                message = LocalizationManager.shared.t(.fightStarted)
            } else if let side, let countingBout = self.storyBout, countingBout.getupKnockdownAmount < 1 {
                let fighter = side == .player ? player : enemy
                fighter.knockdown = countingBout.getupKnockdownAmount
                fighter.getupProgress = countingBout.getupProgress
            }
        case .corner:
            self.storyBout?.advanceCorner(realDeltaTime)
        case .finished:
            roundBreakElapsedTime += simulationDelta
        case .fighting:
            break
        }
    }

    private func commitStoryRoundLearning() {
        guard let storyBout, !storyRoundCommitted,
              storyBout.phase == .corner || storyBout.phase == .finished else { return }
        storyLearning.habits.incorporateRound(roundHabits)
        storyLearning.playerAttacks.incorporateRound(roundPlayerAttackResults)
        storyLearning.opponentAttacks.incorporateRound(roundRivalAttackResults)
        storyLearning.completedRounds = min(10_000, storyLearning.completedRounds + 1)
        if storyBout.opponent == .rival {
            storyLearning.championshipRounds = min(10_000, storyLearning.championshipRounds + 1)
        }
        storyRoundCommitted = true
    }

    private func announceStoryResult() {
        guard let storyBout, storyBout.phase == .finished else { return }
        commitStoryRoundLearning()
        switch storyBout.verdict {
        case .win: lastRoundOutcome = .playerWin
        case .loss: lastRoundOutcome = .playerLoss
        case .draw, .none: lastRoundOutcome = .draw
        }
        lastRoundWasKnockout = storyBout.finish == .technicalKnockout
        if lastRoundWasKnockout { koMomentTime = CombatData.koMomentDuration }
        onCombatEvent?(.roundEnded(outcome: lastRoundOutcome, knockout: lastRoundWasKnockout))
    }

    func storyCheckpoint() -> StoryCheckpoint? {
        guard let storyBout else { return nil }
        func checkpoint(_ fighter: FighterModel) -> StoryFighterCheckpoint {
            StoryFighterCheckpoint(health: fighter.hp, stamina: fighter.stamina,
                positionX: fighter.x, positionY: fighter.y, facingX: fighter.facingX, facingY: fighter.facingY,
                exhausted: fighter.exhausted, stagger: fighter.stagger, exposed: fighter.exposed,
                invulnerable: fighter.invulnerable, repeatedPunch: fighter.streakAttack?.rawValue,
                repetitionCount: fighter.streakCount)
        }
        let counterWindow = player.pendingDodgeCounter && !player.acted
            ? max(playerCounterWindowTime, lastPlayerDodgeGrade?.counterWindow ?? 0.18) : playerCounterWindowTime
        var observations = StoryRoundObservations()
        observations.habits = roundHabits
        observations.playerAttacks = roundPlayerAttackResults
        observations.opponentAttacks = roundRivalAttackResults
        observations.committed = storyRoundCommitted
        observations.policyRound = storyPolicyRound
        return StoryCheckpoint(bout: storyBout, remainingTime: roundTime,
            player: checkpoint(player), opponent: checkpoint(enemy), playerStyle: player.style.rawValue,
            counterWindow: counterWindow, lastDodgeGrade: lastPlayerDodgeGrade?.rawValue,
            focusTime: rivalMomentTime, focusGrade: rivalMomentGrade?.rawValue,
            learning: storyLearning, observations: observations)
    }

    func restoreStory(_ checkpoint: StoryCheckpoint) {
        guard storyBout?.opponent == checkpoint.bout.opponent,
              (1...checkpoint.bout.opponent.maximumRounds).contains(checkpoint.bout.round),
              checkpoint.bout.phase != .finished else { return }
        storyBout = checkpoint.bout
        if let learning = checkpoint.learning { storyLearning = learning }
        if let style = FightStyle(rawValue: checkpoint.playerStyle) { player.style = style }
        startRound(emitsStartEvent: false)
        if let observations = checkpoint.observations {
            roundHabits = observations.habits
            roundPlayerAttackResults = observations.playerAttacks
            roundRivalAttackResults = observations.opponentAttacks
            storyRoundCommitted = observations.committed
            storyPolicyRound = observations.policyRound
        } else {
            storyRoundCommitted = checkpoint.bout.phase == .corner
        }
        for (fighter, saved) in [(player, checkpoint.player), (enemy, checkpoint.opponent)] {
            fighter.x = clampToRing(saved.positionX)
            fighter.y = clampToRing(saved.positionY)
            fighter.hp = min(fighter.maximumHealth, max(0, saved.health))
            fighter.stamina = min(100, max(0, saved.stamina))
            fighter.facingX = saved.facingX
            fighter.facingY = saved.facingY
            fighter.exhausted = max(0, saved.exhausted)
            fighter.stagger = max(0, saved.stagger)
            fighter.exposed = max(0, saved.exposed)
            fighter.invulnerable = max(0, saved.invulnerable)
            fighter.streakAttack = saved.repeatedPunch.flatMap(Punch.init(rawValue:))
            fighter.streakCount = max(0, saved.repetitionCount)
            fighter.knockedOut = fighter.hp == 0
            fighter.knockdown = fighter.knockedOut ? 1 : 0
        }
        if checkpoint.bout.phase == .counting, let side = checkpoint.bout.countingSide {
            let fighter = side == .player ? player : enemy
            fighter.knockdown = checkpoint.bout.getupKnockdownAmount
            fighter.getupProgress = checkpoint.bout.getupProgress
        }
        roundTime = min(checkpoint.bout.rules.roundSeconds, max(0, checkpoint.remainingTime))
        playerCounterWindowTime = max(0, checkpoint.counterWindow)
        lastPlayerDodgeGrade = checkpoint.lastDodgeGrade.flatMap(DodgeGrade.init(rawValue:))
        rivalMomentGrade = checkpoint.focusGrade.flatMap(DodgeGrade.init(rawValue:))
        rivalMomentTime = rivalMomentGrade == nil ? 0 : max(0, checkpoint.focusTime)
        phase = checkpoint.bout.phase == .fighting ? .fight : .roundBreak
    }

    private func updateKnockdowns(_ deltaTime: Double) {
        for fighter in [player, enemy] {
            fighter.advancePoseTransition(deltaTime)
            fighter.hitReaction = max(0, fighter.hitReaction - deltaTime)
            if fighter.knockedOut {
                fighter.knockdown = min(1, fighter.knockdown + deltaTime / 0.9)
            } else if let punch = fighter.attack, let spec = CombatData.attacks[punch] {
                // Cosmetic follow-through only: never call attemptHit, AI, stamina or habit sampling.
                fighter.actionTime += deltaTime
                if fighter.actionTime >= spec.duration {
                    fighter.attack = nil
                    fighter.attackAim = nil
                    fighter.attackEntryPose = nil
                    fighter.actionTime = 0
                    fighter.acted = false
                    fighter.pendingDodgeCounter = false
                }
            }
        }
    }

    private func exhaust(_ fighter: FighterModel, emitsFeedback: Bool = true) {
        fighter.exhausted = max(fighter.exhausted, CombatData.exhaustionDuration)
        fighter.exposed = max(fighter.exposed, CombatData.exhaustionExposed)
        fighter.weave.cancel()
        exhaustionCount += 1
        lastExhaustedByPlayer = fighter === player
        if fighter === player { message = LocalizationManager.shared.t(.exhausted) }
        if emitsFeedback { onCombatEvent?(.exhausted(fighter: fighter === player ? .player : .rival)) }
    }

    private func saveHabits() {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(habits) {
            defaults.set(data, forKey: "pixelBoxingHabitMemory")
        }
        let profile = RivalLearningProfile(playerAttacks: playerAttackResults, rivalAttacks: rivalAttackResults)
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: "pixelBoxingRivalResults")
        }
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
/// against a stationary target. All training actions, including weaves and linked hooks, are free:
/// no stamina spending/exhaustion, and stamina stays at 100 on every simulation update.
@MainActor
final class PracticeEngine {
    // Reuses the same (295, 295) center convention `BoxerRig`/`worldPosition` assume is the arena's origin,
    // so the heavy bag (fixed at this same point) lands at the room's own world origin with no extra
    // offset math needed, and the player rig starts a short distance south of it.
    static let bagX = 295.0
    static let bagY = 295.0

    let player = FighterModel(name: "PLAYER", x: bagX, y: bagY + 95)

    /// Notified with `(punch, damage)` the instant a punch lands on the bag, so the scene can pop a floating
    /// damage number and give the bag a physical swing impulse.
    var onHit: ((Punch, Int) -> Void)?

    /// Emitted once when an actual punch extends, including misses and buffered weave hooks.
    var onPunchSwing: ((Punch) -> Void)?

    // Player position is clamped to an annulus around the bag instead of a rectangular room, so movement
    // input naturally reads as "walk in / back away / circle around" the fixed target.
    //
    // The bag's larger surface uses its own contact allowance. All styles, including the
    // shortest Slugger uppercut, can enter range without putting the torso inside the bag.
    private let minRadius = CombatData.minimumFighterSeparation
    private let maxRadius = 185.0
    var moveX = 0.0
    var moveY = 0.0
    private(set) var isPaused = false
    private(set) var message = ""

    var playerLocked: Bool {
        player.stagger > 0 || player.exhausted > 0 || player.knockedOut || player.hp <= 0
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
        guard !isPaused, !playerLocked, player.attack == nil, !player.weave.isActive else { return }
        player.guarding = true
    }

    func setDuck(_ direction: Int, active: Bool) {
        if !active {
            player.duckDirection = 0
            return
        }
        guard !isPaused, !playerLocked, player.attack == nil, !player.weave.isActive else { return }
        player.duckDirection = min(1, max(-1, direction))
    }

    @discardableResult
    func weave(direction: Int) -> Bool {
        guard !isPaused else { return false }
        updateFacing()
        guard player.beginWeave(direction: direction, spendsStamina: false) else { return false }
        message = LocalizationManager.shared.t(direction < 0 ? .weaveLeftAccessibility : .weaveRightAccessibility)
        return true
    }

    @discardableResult
    func requestWeaveHook(base: Punch) -> Bool {
        guard !isPaused, player.queueWeaveHook(base: base) else { return false }
        launchWeaveHook()
        return true
    }

    func cancelWeaveInput() {
        player.weave.cancel()
        moveX = 0
        moveY = 0
    }

    func togglePause() {
        if !isPaused { cancelWeaveInput() }
        isPaused.toggle()
    }

    private func launchWeaveHook() {
        guard let hook = player.weave.takeReadyHook() else { return }
        _ = executeAttack(hook, fromWeave: true)
    }

    @discardableResult
    func backstep() -> Bool {
        guard !isPaused, !playerLocked, player.attack == nil, !player.weave.isActive,
              !player.backstep.isActive else { return false }
        updateFacing()
        player.weave.cancel()
        player.backstep.start(facingX: player.facingX, facingY: player.facingY)
        return true
    }

    @discardableResult
    func startAttack(_ punch: Punch) -> Bool {
        executeAttack(punch, fromWeave: false)
    }

    private func executeAttack(_ punch: Punch, fromWeave: Bool) -> Bool {
        guard !isPaused, !playerLocked, player.attack == nil, (!player.weave.isActive || fromWeave),
              !player.backstep.isActive, let spec = CombatData.attacks[punch] else { return false }
          updateFacing()
          PunchContactGeometry.begin(player,
            target: SIMD3<Float>(Float(Self.bagX * CombatData.sceneScale),
                            spec.targetZone == .body ? 1.40 : 2.20,
                            Float(Self.bagY * CombatData.sceneScale)),
            radius: Float(CombatData.bagContactRadius))
        if !fromWeave { player.weave.cancel() }
        player.attack = punch
        player.attackSerial &+= 1
        player.actionTime = 0
        player.acted = false
        player.guarding = false
        return true
    }

    func update(deltaTime rawDeltaTime: Double) {
        guard !isPaused, rawDeltaTime.isFinite else { return }
        let deltaTime = min(0.05, max(0, rawDeltaTime))
        guard deltaTime > 0 else { return }
        updateFacing()
        updatePlayerMovement(deltaTime)
        player.duckMotion.advance(direction: player.duckDirection, deltaTime: deltaTime)
        player.guardAmount = DefensiveMotion.guardBlend(current: player.guardAmount,
            raised: player.guarding, deltaTime: deltaTime, reducedMotion: false)
        let retreat = player.backstep.advance(deltaTime)
        if retreat.x != 0 || retreat.y != 0 { moveToClamped(x: player.x + retreat.x, y: player.y + retreat.y) }
        let step = player.advanceWeave(deltaTime)
        if step.x != 0 || step.y != 0 { moveToClamped(x: player.x + step.x, y: player.y + step.y) }
        player.invulnerable = max(0, player.invulnerable - deltaTime)
        player.exhausted = max(0, player.exhausted - deltaTime)
        player.exposed = max(0, player.exposed - deltaTime)
        player.stagger = max(0, player.stagger - deltaTime)
        player.hitReaction = max(0, player.hitReaction - deltaTime)
        player.stamina = 100 // Free training, including active defense, weaves and linked hooks.

        if let punch = player.attack, let spec = CombatData.attacks[punch] {
            let previous = player.actionTime
            player.actionTime += deltaTime
            let swingTime = PunchSwingTiming.cueTime(spec: spec)
            if previous < swingTime, player.actionTime >= swingTime {
                onPunchSwing?(punch)
            }
            if !player.acted, previous < spec.activeStart, player.actionTime >= spec.activeStart {
                player.acted = attemptHitBag(punch: punch, spec: spec)
            }
            if player.actionTime >= spec.duration {
                player.attack = nil
                player.attackAim = nil
                player.attackEntryPose = nil
                player.actionTime = 0
                player.acted = false
            }
        }
        launchWeaveHook()
    }

    /// Player always faces the fixed bag (there's no opponent to track), recomputed every frame the same
    /// way `CombatEngine.updateFacing()` keeps the two live fighters looking at each other.
    private func updateFacing() {
        guard player.attack == nil else { return }
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
        guard distance <= CombatData.hitRange(punch, style: player.style,
                             targetRadius: CombatData.bagContactRadius) else { return false }
        let glove = PunchContactGeometry.glove(player, punch: punch)
        let bagCenter = SIMD2<Float>(Float(Self.bagX * CombatData.sceneScale), Float(Self.bagY * CombatData.sceneScale))
        guard simd_distance(SIMD2<Float>(glove.x, glove.z), bagCenter)
            <= Float(CombatData.bagContactRadius + spec.fistRadius * CombatData.sceneScale) else { return false }
        let damage = max(1, Int((Double(spec.damage) * player.style.damageMultiplier).rounded()))
        player.hitReaction = 0.16
        onHit?(punch, damage)
        return true
    }

    private func updatePlayerMovement(_ deltaTime: Double) {
          guard player.attack == nil, !playerLocked, !player.guarding,
              !player.weave.isActive, !player.backstep.isActive else { return }
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
