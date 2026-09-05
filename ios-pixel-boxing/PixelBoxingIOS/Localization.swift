import Foundation
import UIKit

/// The 3 UI languages the app can display in. Chosen explicitly from Settings — deliberately independent of
/// the device's system locale, since the picker only ever offers these 3 options.
enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case korean = "ko"
    case english = "en"
    case japanese = "ja"

    /// Always shown in its OWN script regardless of which language is currently active — the standard
    /// convention for a language picker (e.g. "日本語" isn't translated into Korean just because Korean
    /// happens to be selected right now).
    var nativeName: String {
        switch self {
        case .korean: "한국어"
        case .english: "English"
        case .japanese: "日本語"
        }
    }
}

/// Central place the whole app reads its current display language from. A single `@MainActor` singleton
/// (rather than per-view `@State`) so non-view code that builds user-facing text itself — `CombatEngine`'s
/// live commentary/HUD messages — can also read the active language, not just SwiftUI views.
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    private static let defaultsKey = "pixelBoxingLanguage"

    @Published private(set) var language: AppLanguage

    private init() {
        if let raw = UserDefaults.standard.string(forKey: LocalizationManager.defaultsKey),
           let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            language = .korean
        }
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: LocalizationManager.defaultsKey)
    }

    /// Shorthand for `key.text(for: language)` so call sites read as `loc.t(.someKey)`.
    func t(_ key: L) -> String {
        key.text(for: language)
    }
}

/// Guards every haptic feedback call in the app behind one on/off preference, the same way `SoundManager`'s
/// `isMuted` guards audio. Kept separate from sound (a player may want buzzes off but sound on, or vice
/// versa) and separate from `GameController` since the practice room's `PracticeController` needs the same
/// preference without holding a reference to the battle controller.
@MainActor
final class HapticsManager: ObservableObject {
    static let shared = HapticsManager()
    private static let defaultsKey = "pixelBoxingHapticsEnabled"

    @Published private(set) var isEnabled: Bool

    private init() {
        if UserDefaults.standard.object(forKey: HapticsManager.defaultsKey) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: HapticsManager.defaultsKey)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: HapticsManager.defaultsKey)
    }

    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
    }

    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

/// One case per static UI string shown anywhere in the app. Keeping every string behind a key — instead of
/// scattering literals through the SwiftUI views and `CombatEngine` — is what makes the 3-language switch
/// actually reach every screen instead of just the settings menu itself.
enum L {
    case tagline
    case introSubtitle
    case moveDefenseTitle
    case jabCrossTitle
    case waitingRoomButton
    case pausedTitle
    case resumeButton
    case fightingStyleLabel
    case outfitLabel
    case close
    case settingsTitle
    case settingsSubtitle
    case soundOn
    case soundOff
    case hapticsOn
    case hapticsOff
    case language
    case exitToMenu
    case resetConfirmTitle
    case resetConfirmBody
    case cancel
    case resetConfirmButton
    case continueButton
    case newGameButton
    case newGameSubtitle
    case waitingRoomSubtitle
    case practiceRoomButton
    case practiceRoomSubtitle
    case exitButton
    case learningResetMessage
    case roundLostMessage
    case drawMessage
    case roundStatsDodgeLabel
    case roundStatsTopAttackLabel
    case roundStatsNoAttack
    case nextRoundButton
    case roundStatsFinishingBlowLabel
    case roundStatsRivalReadLabel
    case roundStatsRivalCornerLabel
    case cinematicSkip
    case moveForwardAccessibility
    case moveBackAccessibility
    case moveLeftAccessibility
    case moveRightAccessibility
    case guardAccessibility
    case duckLeftAccessibility
    case duckRightAccessibility
    case backstepAccessibility
    case playerAccessibility
    case exitGymAccessibility
    case leaderboardButton
    case leaderboardSubtitle
    case leaderboardTitle
    case leaderboardWinsLabel
    case leaderboardSignInPrompt
    case leaderboardSignInButton
    case leaderboardLoadError
    case leaderboardEmptyState
    case leaderboardYouLabel

    private static func pick(ko: String, en: String, ja: String, language: AppLanguage) -> String {
        switch language {
        case .korean: ko
        case .english: en
        case .japanese: ja
        }
    }

    func text(for language: AppLanguage) -> String {
        switch self {
        case .tagline:
            L.pick(ko: "상대는 당신을 기억한다", en: "Your opponent remembers you.", ja: "相手はあなたを覚えている。", language: language)
        case .introSubtitle:
            L.pick(ko: "반복하는 공격과 방어 습관을 RIVAL이 학습합니다.", en: "RIVAL learns from your repeated attack and defense habits.", ja: "繰り返す攻撃と防御の癖をRIVALが学習します。", language: language)
        case .moveDefenseTitle:
            L.pick(ko: "MOVE & DEFENSE", en: "MOVE & DEFENSE", ja: "MOVE & DEFENSE", language: language)
        case .jabCrossTitle:
            L.pick(ko: "JAB / CROSS 조합", en: "JAB / CROSS combos", ja: "JAB / CROSSのコンボ", language: language)
        case .waitingRoomButton:
            L.pick(ko: "대기실", en: "Waiting Room", ja: "待機室", language: language)
        case .pausedTitle:
            L.pick(ko: "PAUSED", en: "PAUSED", ja: "PAUSED", language: language)
        case .resumeButton:
            L.pick(ko: "RESUME", en: "RESUME", ja: "RESUME", language: language)
        case .fightingStyleLabel:
            L.pick(ko: "파이팅 스타일", en: "Fighting Style", ja: "ファイティングスタイル", language: language)
        case .outfitLabel:
            L.pick(ko: "복장", en: "Outfit", ja: "衣装", language: language)
        case .close:
            L.pick(ko: "닫기", en: "Close", ja: "閉じる", language: language)
        case .settingsTitle:
            L.pick(ko: "설정", en: "Settings", ja: "設定", language: language)
        case .settingsSubtitle:
            L.pick(ko: "사운드 등", en: "Sound, etc.", ja: "サウンドなど", language: language)
        case .soundOn:
            L.pick(ko: "사운드 켜짐", en: "Sound On", ja: "サウンドオン", language: language)
        case .soundOff:
            L.pick(ko: "사운드 꺼짐", en: "Sound Off", ja: "サウンドオフ", language: language)
        case .hapticsOn:
            L.pick(ko: "햅틱 켜짐", en: "Haptics On", ja: "触覚オン", language: language)
        case .hapticsOff:
            L.pick(ko: "햅틱 꺼짐", en: "Haptics Off", ja: "触覚オフ", language: language)
        case .language:
            L.pick(ko: "언어", en: "Language", ja: "言語", language: language)
        case .exitToMenu:
            L.pick(ko: "메인 메뉴로 나가기", en: "Exit to Main Menu", ja: "メインメニューへ戻る", language: language)
        case .resetConfirmTitle:
            L.pick(ko: "라이벌 학습을 초기화할까요?", en: "Reset RIVAL's learning?", ja: "RIVALの学習をリセットしますか?", language: language)
        case .resetConfirmBody:
            L.pick(ko: "학습 메모리와 현재 점수가 삭제되고 ROUND 1부터 다시 시작됩니다.", en: "Learning memory and the current score will be deleted, restarting from ROUND 1.", ja: "学習メモリと現在のスコアが削除され、ROUND 1からやり直します。", language: language)
        case .cancel:
            L.pick(ko: "취소", en: "Cancel", ja: "キャンセル", language: language)
        case .resetConfirmButton:
            L.pick(ko: "초기화 · ROUND 1", en: "Reset · ROUND 1", ja: "リセット・ROUND 1", language: language)
        case .continueButton:
            L.pick(ko: "이어하기", en: "Continue", ja: "続ける", language: language)
        case .newGameButton:
            L.pick(ko: "새로하기", en: "New Game", ja: "はじめから", language: language)
        case .newGameSubtitle:
            L.pick(ko: "라이벌 학습 초기화 · ROUND 1부터", en: "Reset RIVAL's learning · From ROUND 1", ja: "RIVALの学習をリセット・ROUND 1から", language: language)
        case .waitingRoomSubtitle:
            L.pick(ko: "파이팅 스타일 · 복장 선택", en: "Choose fighting style · outfit", ja: "ファイティングスタイル・衣装選択", language: language)
        case .practiceRoomButton:
            L.pick(ko: "체육관", en: "Practice Room", ja: "練習室", language: language)
        case .practiceRoomSubtitle:
            L.pick(ko: "거울 앞에서 조작 · 콤보 연습", en: "Practice controls & combos in front of the mirror", ja: "鏡の前で操作・コンボ練習", language: language)
        case .exitButton:
            L.pick(ko: "나가기", en: "Exit", ja: "退出", language: language)
        case .learningResetMessage:
            L.pick(ko: "학습 메모리 초기화 · ROUND 1", en: "Learning memory reset · ROUND 1", ja: "学習メモリ初期化・ROUND 1", language: language)
        case .roundLostMessage:
            L.pick(ko: "ROUND LOST - RIVAL 학습 롤백", en: "ROUND LOST - RIVAL learning rolled back", ja: "ROUND LOST - RIVAL学習ロールバック", language: language)
        case .drawMessage:
            L.pick(ko: "DRAW - 동일 HP", en: "DRAW - Equal HP", ja: "DRAW - HP互角", language: language)
        case .roundStatsDodgeLabel:
            L.pick(ko: "회피 성공", en: "Dodges", ja: "回避成功", language: language)
        case .roundStatsTopAttackLabel:
            L.pick(ko: "주요 공격", en: "Top Attack", ja: "主な攻撃", language: language)
        case .roundStatsNoAttack:
            L.pick(ko: "없음", en: "None", ja: "なし", language: language)
        case .nextRoundButton:
            L.pick(ko: "다음 라운드로", en: "Next Round", ja: "次のラウンドへ", language: language)
        case .roundStatsFinishingBlowLabel:
            L.pick(ko: "결정타", en: "Finishing Blow", ja: "決め手", language: language)
        case .roundStatsRivalReadLabel:
            L.pick(ko: "RIVAL 학습도", en: "RIVAL Read", ja: "RIVAL習熟度", language: language)
        case .roundStatsRivalCornerLabel:
            L.pick(ko: "RIVAL 코너", en: "RIVAL'S CORNER", ja: "RIVALコーナー", language: language)
        case .cinematicSkip:
            L.pick(ko: "입장 연출 건너뛰기", en: "Skip entrance", ja: "入場演出をスキップ", language: language)
        case .moveForwardAccessibility:
            L.pick(ko: "전진", en: "Forward", ja: "前進", language: language)
        case .moveBackAccessibility:
            L.pick(ko: "후퇴", en: "Back", ja: "後退", language: language)
        case .moveLeftAccessibility:
            L.pick(ko: "왼쪽 이동", en: "Move Left", ja: "左移動", language: language)
        case .moveRightAccessibility:
            L.pick(ko: "오른쪽 이동", en: "Move Right", ja: "右移動", language: language)
        case .guardAccessibility:
            L.pick(ko: "가드", en: "Guard", ja: "ガード", language: language)
        case .duckLeftAccessibility:
            L.pick(ko: "왼쪽 더킹", en: "Duck Left", ja: "左ダッキング", language: language)
        case .duckRightAccessibility:
            L.pick(ko: "오른쪽 더킹", en: "Duck Right", ja: "右ダッキング", language: language)
        case .backstepAccessibility:
            L.pick(ko: "백스텝", en: "Backstep", ja: "バックステップ", language: language)
        case .playerAccessibility:
            L.pick(ko: "플레이어", en: "Player", ja: "プレイヤー", language: language)
        case .exitGymAccessibility:
            L.pick(ko: "체육관 나가기, 메인 메뉴로", en: "Exit Gym, back to Main Menu", ja: "ジムを出る、メインメニューへ", language: language)
        case .leaderboardButton:
            L.pick(ko: "랭킹", en: "Leaderboard", ja: "ランキング", language: language)
        case .leaderboardSubtitle:
            L.pick(ko: "Game Center · 전 세계 순위", en: "Game Center · Global rankings", ja: "Game Center・世界ランキング", language: language)
        case .leaderboardTitle:
            L.pick(ko: "랭킹", en: "Leaderboard", ja: "ランキング", language: language)
        case .leaderboardWinsLabel:
            L.pick(ko: "승", en: "wins", ja: "勝", language: language)
        case .leaderboardSignInPrompt:
            L.pick(ko: "Game Center에 로그인하면 전 세계 랭킹을 볼 수 있어요.\n와이파이 없이도 게임은 그대로 즐길 수 있습니다.", en: "Sign in to Game Center to see global rankings.\nThe game itself still works fully offline either way.", ja: "Game Centerにサインインすると世界ランキングが見られます。\nオフラインでもゲーム自体はそのまま楽しめます。", language: language)
        case .leaderboardSignInButton:
            L.pick(ko: "Game Center 로그인", en: "Sign in to Game Center", ja: "Game Centerにサインイン", language: language)
        case .leaderboardLoadError:
            L.pick(ko: "랭킹을 불러오지 못했어요. 네트워크를 확인해 주세요.", en: "Couldn't load the leaderboard. Check your network.", ja: "ランキングを読み込めませんでした。ネットワークをご確認ください。", language: language)
        case .leaderboardEmptyState:
            L.pick(ko: "아직 등록된 랭킹이 없어요. 첫 승리를 기록해 보세요!", en: "No rankings yet. Be the first to log a win!", ja: "まだランキングがありません。最初の勝利を記録しましょう!", language: language)
        case .leaderboardYouLabel:
            L.pick(ko: "나", en: "You", ja: "あなた", language: language)
        }
    }

    /// The 4-line "MOVE & DEFENSE" instruction column shown on the pre-fight intro overlay.
    static func moveDefenseLines(for language: AppLanguage) -> [String] {
        [
            pick(ko: "↑ 전진  ·  ↓ 후퇴", en: "↑ Forward  ·  ↓ Back", ja: "↑ 前進  ·  ↓ 後退", language: language),
            pick(ko: "← / → 좌우 이동", en: "← / → Move left/right", ja: "← / → 左右移動", language: language),
            pick(ko: "L / R DUCK 회피", en: "L / R DUCK to evade", ja: "L / R DUCKで回避", language: language),
            pick(ko: "GUARD 방어  ·  BACKSTEP", en: "GUARD to block  ·  BACKSTEP", ja: "GUARDで防御・BACKSTEP", language: language),
        ]
    }

    /// The 4-line "JAB / CROSS combos" instruction column shown on the pre-fight intro overlay.
    static func jabCrossLines(for language: AppLanguage) -> [String] {
        [
            pick(ko: "단독: 잽 / 크로스", en: "Alone: Jab / Cross", ja: "単独:ジャブ/クロス", language: language),
            pick(ko: "GUARD: 좌 / 우 어퍼컷", en: "GUARD: Left / Right uppercut", ja: "GUARD:左/右アッパー", language: language),
            pick(ko: "L DUCK: 좌 바디 / 우 훅", en: "L DUCK: Left body / Right hook", ja: "L DUCK:左ボディ/右フック", language: language),
            pick(ko: "R DUCK: 좌 훅 / 우 바디", en: "R DUCK: Left hook / Right body", ja: "R DUCK:左フック/右ボディ", language: language),
        ]
    }

    /// The coach's rotating speech-bubble tutorial tips shown in the practice room (see
    /// `PracticeScene.updateCoachTip`), fully translated per-language so switching languages mid-session
    /// replaces the coach's messages too, not just static UI chrome.
    static func coachTipMessages(for language: AppLanguage) -> [String] {
        switch language {
        case .korean:
            return [
                "더킹을 하면서 같은 방향의 주먹을 내지르면 바디샷을 날릴 수 있어",
                "잽은 짧고 빠르게, 거리를 재는 용도로 써봐",
                "훅을 던질 땐 발끝과 골반을 함께 돌려야 힘이 실려",
                "어퍼컷은 상대가 가까이 붙었을 때 가장 위력적이야",
                "가드는 절대 내리지 마, 턱을 감싸고 팔꿈치로 몸통을 막아",
                "스텝은 항상 가볍게, 발이 땅에 오래 붙어있지 않게 해",
                "펀치를 낼 때마다 숨을 참지 말고 짧게 내쉬어봐",
                "백스텝으로 거리를 벌린 다음 바로 반격을 준비해",
                "카운터는 타이밍이 전부야, 상대 펀치가 끝나는 순간을 노려",
                "체중 이동 없이 팔 힘만으로 치면 데미지가 약해져",
                "더킹 후 바로 몸을 세우지 말고 잠깐 낮은 자세를 유지해봐",
                "같은 패턴만 반복하면 상대가 읽어버려, 콤보를 섞어봐",
                "크로스는 반대쪽 발로 바닥을 밀어내면서 던져야 회전력이 붙어",
                "시야는 상대 눈이 아니라 가슴 쪽을 봐야 다음 동작이 먼저 보여",
                "원투 콤보 후엔 곧바로 가드로 돌아오는 습관을 들여",
                "몸통을 노리는 바디샷은 상대의 스태미나를 서서히 갉아먹어",
                "팔꿈치를 몸에 붙이고 있어야 옆구리가 뚫리지 않아",
                "상대가 전진할 땐 무리하게 맞서지 말고 각도를 바꿔 피해봐",
                "잽으로 거리를 재고 크로스로 마무리하는 게 기본 중의 기본이야",
                "한 방을 노리기보다 꾸준히 맞히는 편이 판정에서 유리해",
                // Motivational lines.
                "포기하지 마, 챔피언은 가장 지쳤을 때 한 걸음 더 나아간 사람이야",
                "오늘 흘린 땀이 내일의 한 방이 된다",
                "넘어져도 다시 일어나는 게 진짜 복서야",
                "실수를 두려워하지 마, 링 위에서 배우는 거야",
                "매일 조금씩 나아지면 결국 최고가 돼",
                "너 자신을 믿어봐, 그게 가장 강력한 첫 펀치야",
                // Boxing jokes.
                "샌드백은 절대 반격 안 해, 그래서 내가 제일 좋아하는 상대야",
                "복싱 격언 하나 알려줄까? 맞기 전까진 다 계획이 있어",
                "오늘도 샌드백한테 완승했네, 축하해",
                "내가 젊었을 때는 말이야... 아니다, 계속 쳐봐",
                "펀치보다 내 아재개그가 더 아플 때도 있지",
                "살살 친 거 맞지? 샌드백이 대답을 안 하네",
            ]
        case .english:
            return [
                "Duck and throw a punch on the same side at the same time to land a body shot.",
                "Keep your jab short and fast -- use it to measure distance.",
                "Rotate your hips and toes together when you throw a hook, or it loses power.",
                "An uppercut hits hardest when your opponent is right up close.",
                "Never drop your guard -- tuck your chin and block your body with your elbows.",
                "Keep your steps light -- don't let your feet stay planted too long.",
                "Don't hold your breath on every punch, exhale sharply instead.",
                "Backstep to create distance, then get ready to counter right away.",
                "Countering is all about timing -- strike the instant their punch ends.",
                "Punching with arm strength alone, without shifting your weight, weakens the damage.",
                "After ducking, stay low for a beat instead of standing straight back up.",
                "Repeating the same pattern lets your opponent read you -- mix up your combos.",
                "Push off your back foot when throwing a cross for extra rotational power.",
                "Watch your opponent's chest, not their eyes -- you'll see the next move sooner.",
                "Get in the habit of returning to guard right after a one-two combo.",
                "Body shots slowly grind down your opponent's stamina.",
                "Keep your elbows tucked in, or your ribs stay wide open.",
                "When your opponent charges in, change your angle instead of meeting them head-on.",
                "Measure with the jab, finish with the cross -- that's boxing 101.",
                "Landing steady hits beats chasing one big knockout blow on the scorecards.",
                // Motivational lines.
                "Don't give up -- a champion is the one who takes one more step when they're most exhausted.",
                "The sweat you drop today becomes tomorrow's power punch.",
                "Getting knocked down doesn't matter -- getting back up is what makes you a real boxer.",
                "Don't be afraid of mistakes -- the ring is where you learn.",
                "Get a little better every day and eventually you'll be the best.",
                "Believe in yourself -- that's the strongest first punch you can throw.",
                // Boxing jokes.
                "The bag never hits back, that's why it's my favorite sparring partner.",
                "Want to hear a boxing saying? Everyone's got a plan until they get hit.",
                "Another clean win over the heavy bag today, congratulations.",
                "Back in my day... nah, never mind, just keep punching.",
                "Sometimes my jokes land harder than your punches.",
                "That was a light tap, right? The bag's not answering.",
            ]
        case .japanese:
            return [
                "ダッキングしながら同じ方向のパンチを打つとボディが決まるよ",
                "ジャブは短く速く、距離を測るために使おう",
                "フックを打つときは足先と骨盤を一緒に回して",
                "アッパーは相手が近づいた時に一番効くよ",
                "ガードは絶対下げるな、あごを引いて肘で体を守れ",
                "ステップは常に軽く、足を長く地面につけないで",
                "パンチのたびに息を止めず、短く吐いてみて",
                "バックステップで距離を取ったらすぐ反撃の準備を",
                "カウンターはタイミングが全て、相手のパンチが終わる瞬間を狙え",
                "体重移動せず腕の力だけで打つとダメージが弱くなる",
                "ダッキングの後はすぐ立たず少し低い姿勢を保って",
                "同じパターンばかりだと読まれる、コンビネーションを混ぜよう",
                "クロスは逆足で地面を蹴ると回転力がつく",
                "相手の目じゃなく胸を見ると次の動きが早く分かる",
                "ワンツーの後はすぐガードに戻る癖をつけて",
                "ボディブローは相手のスタミナをじわじわ削るよ",
                "肘を体につけていないと脇腹が空いてしまう",
                "相手が突っ込んできたら無理せず角度を変えてかわして",
                "ジャブで距離を測りクロスで仕留めるのが基本中の基本",
                "一発を狙うより着実に当てる方が判定で有利だよ",
                // Motivational lines.
                "諦めるな、チャンピオンは一番疲れた時にもう一歩踏み出せる人だ",
                "今日流した汗が明日の一撃になる",
                "倒れても、また立ち上がるのが本物のボクサーだ",
                "ミスを恐れるな、リングの上で学べばいい",
                "毎日少しずつ良くなれば、最後には最強になれる",
                "自分を信じろ、それが一番強い最初のパンチだ",
                // Boxing jokes.
                "サンドバッグは絶対に反撃してこない、だから一番好きな相手なんだ",
                "ボクシングの格言を教えようか? 殴られるまでは誰でも作戦がある",
                "今日もサンドバッグに完勝したな、おめでとう",
                "俺が若い頃はな...いや、やめとこう、続けて打って",
                "俺のギャグの方がパンチより効くこともあるぞ",
                "今の軽く当てただけだよな? サンドバッグは返事しないな",
            ]
        }
    }
}
