import Foundation

// Short boxing/brand glyphs (JAB, CROSS, ME, RIVAL, HP, ROUND) stay on the fight controls.
// Their spoken names and all explanatory sentences follow the selected app language.
extension Punch {
    /// Short visible labels fit the existing thumb targets; full spoken names remain below.
    func controlLabel(for language: AppLanguage) -> String {
        switch self {
        case .jab: L.pick(ko: "잽", en: "JAB", ja: "ジャブ", language: language)
        case .cross: L.pick(ko: "크로스", en: "CROSS", ja: "クロス", language: language)
        case .leftBody: L.pick(ko: "왼 바디", en: "L BODY", ja: "左ボディ", language: language)
        case .rightBody: L.pick(ko: "오른 바디", en: "R BODY", ja: "右ボディ", language: language)
        case .leftHook: L.pick(ko: "왼 훅", en: "L HOOK", ja: "左フック", language: language)
        case .rightHook: L.pick(ko: "오른 훅", en: "R HOOK", ja: "右フック", language: language)
        case .leftUppercut: L.pick(ko: "왼 어퍼", en: "L UPPER", ja: "左アッパー", language: language)
        case .rightUppercut: L.pick(ko: "오른 어퍼", en: "R UPPER", ja: "右アッパー", language: language)
        }
    }

    func localizedName(for language: AppLanguage) -> String {
        switch self {
        case .jab: L.pick(ko: "왼손 잽", en: "Left jab", ja: "左ジャブ", language: language)
        case .cross: L.pick(ko: "오른손 크로스", en: "Right cross", ja: "右クロス", language: language)
        case .leftBody: L.pick(ko: "왼손 바디샷", en: "Left body shot", ja: "左ボディ", language: language)
        case .rightBody: L.pick(ko: "오른손 바디샷", en: "Right body shot", ja: "右ボディ", language: language)
        case .leftHook: L.pick(ko: "왼손 훅", en: "Left hook", ja: "左フック", language: language)
        case .rightHook: L.pick(ko: "오른손 훅", en: "Right hook", ja: "右フック", language: language)
        case .leftUppercut: L.pick(ko: "왼손 어퍼컷", en: "Left uppercut", ja: "左アッパー", language: language)
        case .rightUppercut: L.pick(ko: "오른손 어퍼컷", en: "Right uppercut", ja: "右アッパー", language: language)
        }
    }
}

extension RoundOutcome {
    func title(knockout: Bool, language: AppLanguage) -> String {
        let key: L
        switch self {
        case .playerWin: key = knockout ? .knockoutWin : .roundWin
        case .playerLoss: key = knockout ? .knockoutLoss : .roundLoss
        case .draw: key = .roundDraw
        }
        return key.text(for: language)
    }
}

extension CombatSignature {
    func title(for language: AppLanguage) -> String {
        switch self {
        case .counterWindow: L.counterOpportunity.text(for: language)
        case .perfectCounter: L.perfectCounter.text(for: language)
        case .knockout: "K.O."
        }
    }
}

enum CombatText {
    static func clock(_ snapshot: CombatSnapshot, language: AppLanguage) -> String {
        let seconds = Int(ceil(snapshot.time))
        return L.pick(
            ko: "라운드 \(snapshot.round), 남은 시간 \(seconds)초, 스코어 \(snapshot.playerScore) 대 \(snapshot.enemyScore)",
            en: "Round \(snapshot.round), \(seconds) seconds left, score \(snapshot.playerScore) to \(snapshot.enemyScore)",
            ja: "ラウンド\(snapshot.round)、残り\(seconds)秒、スコア\(snapshot.playerScore)対\(snapshot.enemyScore)", language: language
        )
    }

    static func fighter(name: String, health: Int, stamina: Double, language: AppLanguage) -> String {
        "\(name), \(L.healthLabel.text(for: language)) \(health), \(L.staminaLabel.text(for: language)) \(Int(stamina))"
    }

    static func roundResult(_ snapshot: CombatSnapshot, language: AppLanguage) -> String {
        let player = L.playerAccessibility.text(for: language)
        let rival = L.rivalAccessibility.text(for: language)
        let none = L.roundStatsNoAttack.text(for: language)
        var parts = [
            snapshot.lastRoundOutcome.title(knockout: snapshot.lastRoundWasKnockout, language: language),
            "\(L.scoreLabel.text(for: language)) \(snapshot.playerScore) : \(snapshot.enemyScore)",
            "\(player), \(L.roundStatsDodgeLabel.text(for: language)) \(snapshot.roundPlayerDodgeCount), \(L.roundStatsTopAttackLabel.text(for: language)) \(snapshot.roundPlayerTopAttack?.localizedName(for: language) ?? none)",
            "\(rival), \(L.roundStatsDodgeLabel.text(for: language)) \(snapshot.roundEnemyDodgeCount), \(L.roundStatsTopAttackLabel.text(for: language)) \(snapshot.roundEnemyTopAttack?.localizedName(for: language) ?? none)"
        ]
        if snapshot.lastRoundWasKnockout, let punch = snapshot.roundFinishingPunch {
            parts.append("\(L.roundStatsFinishingBlowLabel.text(for: language)), \(snapshot.roundFinishingBlowByPlayer ? player : rival), \(punch.localizedName(for: language))")
        }
        if let report = snapshot.rivalRead.cornerReport(for: language) {
            parts.append("\(L.roundStatsRivalCornerLabel.text(for: language)), \(report)")
        }
        return parts.joined(separator: ". ")
    }
}