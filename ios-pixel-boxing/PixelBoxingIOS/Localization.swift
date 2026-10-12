/*
 Localization.swift

 파일 설명:
 - 다국어 텍스트와 로컬라이제이션 헬퍼를 제공하는 모듈입니다. 앱 전역에서 사용하는 사용자-facing 문자열
     을 관리하고, 런타임에 언어 변경을 반영하는 유틸리티를 포함합니다.

 사용 영향 및 주의사항:
 - 이 파일의 문자열 키/메시지를 변경하면 앱 내 텍스트가 바뀌므로 번역 관리에 유의하세요.
 - 런타임에 언어 전환이 필요하면 관련 뷰들이 즉시 재렌더링되도록 관찰자 패턴을 사용합니다.
*/
import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

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

enum StoryText {
    case title, challenge, resume, replay, locked, cleared, unavailable, rounds, downs
    case ahead, even, behind, knockdown, corner, decision, win, loss, draw, retry, opponents, nextRound, firstBout
    case appearance, defaultAppearance, appearanceRequirement, appearanceUnlocked
    case skip, replayIntroduction, replayRivalScene, pressureVenue, pressureIntroductionLine
    case outboxerVenue, outboxerIntroductionLine
    case counterVenue, counterIntroductionLine, sluggerVenue, sluggerIntroductionLine
    case newChallenge
    case continueStory, rivalAdmirationLine, rivalComparisonLine, rivalImitationLine, rivalObsessionLine
    case championshipVenue, championshipIntroductionLine, rivalOwnWayLine, championshipReward, championBelt
    case coach, coachPressureRead, coachPressurePlan, coachOutboxerRead, coachOutboxerPlan
    case coachCounterRead, coachCounterPlan, coachSluggerRead, coachSluggerPlan, coachRivalRead, coachRivalPlan
    case championshipCoachCongratulations

    func text(for language: AppLanguage) -> String {
        let translations: (String, String, String)
        switch self {
        case .title: translations = ("스토리", "STORY", "ストーリー")
        case .challenge: translations = ("도전", "CHALLENGE", "挑戦")
        case .resume: translations = ("경기 이어하기", "RESUME BOUT", "試合を再開")
        case .newChallenge: translations = ("처음부터 도전", "START OVER", "最初から挑戦")
        case .continueStory: translations = ("계속", "CONTINUE", "続ける")
        case .rivalAdmirationLine: translations = ("언젠가 나도 너처럼.", "Someday, I'll be like you.", "いつか、僕も君のように。")
        case .rivalComparisonLine: translations = ("같은 동작인데... 왜 난 다르지?", "The moves are the same. Why am I different?", "動きは同じなのに...なぜ僕は違う？")
        case .rivalImitationLine: translations = ("내 방식으론... 안 되는 건가.", "My own way... isn't enough.", "僕のやり方では...だめなのか。")
        case .rivalObsessionLine: translations = ("네 움직임은 하나도 놓치지 않아.", "I won't miss a single move you make.", "君の動きは一つも見逃さない。")
        case .championshipVenue: translations = ("챔피언십 아레나", "CHAMPIONSHIP ARENA", "チャンピオンシップアリーナ")
        case .championshipIntroductionLine: translations = ("처음에는 네가 되고 싶었어. 이제는 네가 나를 보게 만들 거야.", "At first, I wanted to be you. Now I'll make you see me.", "最初は君になりたかった。今度は君に僕を見てもらう。")
        case .rivalOwnWayLine: translations = ("다음에는... 내 방식으로.", "Next time... my own way.", "次は...僕のやり方で。")
        case .championshipReward: translations = ("파이널 챔피언 복장 · 벨트 해금", "FINAL CHAMPION OUTFIT + BELT UNLOCKED", "ファイナルチャンピオン衣装・ベルト解放")
        case .championBelt: translations = ("챔피언 벨트", "CHAMPION BELT", "チャンピオンベルト")
        case .replay: translations = ("다시 대결", "REMATCH", "再戦")
        case .locked: translations = ("잠김", "LOCKED", "ロック中")
        case .cleared: translations = ("승리", "CLEARED", "クリア")
        case .unavailable: translations = ("준비 중", "UNAVAILABLE", "準備中")
        case .rounds: translations = ("라운드", "ROUNDS", "ラウンド")
        case .downs: translations = ("다운", "DOWNS", "ダウン")
        case .ahead: translations = ("우세", "AHEAD", "優勢")
        case .even: translations = ("접전", "EVEN", "互角")
        case .behind: translations = ("열세", "BEHIND", "劣勢")
        case .knockdown: translations = ("다운", "KNOCKDOWN", "ダウン")
        case .corner: translations = ("코너", "CORNER", "コーナー")
        case .decision: translations = ("판정", "DECISION", "判定")
        case .win: translations = ("승리", "VICTORY", "勝利")
        case .loss: translations = ("패배", "DEFEAT", "敗北")
        case .draw: translations = ("무승부", "DRAW", "引き分け")
        case .retry: translations = ("재도전", "RETRY", "再挑戦")
        case .opponents: translations = ("상대 선택", "OPPONENTS", "対戦相手")
        case .nextRound: translations = ("다음 라운드", "NEXT ROUND", "次のラウンド")
        case .firstBout: translations = ("첫 공식 경기", "FIRST BOUT", "初の公式戦")
        case .appearance: translations = ("외형", "LOOK", "外見")
        case .defaultAppearance: translations = ("기본 외형", "DEFAULT", "標準の外見")
        case .appearanceRequirement: translations = ("이 상대에게 승리", "Defeat this opponent", "この相手に勝利")
        case .appearanceUnlocked: translations = ("외형 해금", "LOOK UNLOCKED", "外見アンロック")
        case .skip: translations = ("스킵", "SKIP", "スキップ")
        case .replayIntroduction: translations = ("등장 장면", "INTRO SCENE", "登場シーン")
        case .replayRivalScene: translations = ("RIVAL 컷씬 다시 보기", "REPLAY RIVAL SCENE", "RIVALシーンを再生")
        case .pressureVenue: translations = ("RIVAL 복싱 체육관", "RIVAL BOXING CLUB", "RIVAL ボクシングジム")
        case .pressureIntroductionLine: translations = ("이 링에서 물러설 생각은 없어.", "I'm not giving ground in this ring.", "このリングで退くつもりはない。")
        case .outboxerVenue: translations = ("지역 대회장", "REGIONAL HALL", "地域大会会場")
        case .outboxerIntroductionLine: translations = ("거리를 좁혀 봐. 난 여기서 기다릴게.", "Close the distance. I'll be waiting.", "距離を詰めてみな。ここで待ってる。")
        case .counterVenue: translations = ("컨텐더스 홀", "CONTENDERS HALL", "コンテンダーズホール")
        case .counterIntroductionLine: translations = ("기다릴게. 먼저 쳐.", "Go ahead. I'll be waiting.", "待ってるよ。先に打ちな。")
        case .sluggerVenue: translations = ("파이트 나이트 아레나", "FIGHT NIGHT ARENA", "ファイトナイトアリーナ")
        case .sluggerIntroductionLine: translations = ("한 방이면 충분해.", "One clean shot is all I need.", "一発で十分だ。")
        case .coach: translations = ("관장", "COACH", "会長")
        case .coachPressureRead: translations = ("붙어서 바디와 훅을 두세 발씩 친다. 뒤로만 빠지면 계속 쫓아온다.", "He crowds you with body shots and hooks, sometimes a third punch. Don't retreat straight back.", "接近してボディとフックを二、三発続ける。後ろに下がるだけでは追ってくるぞ。")
        case .coachPressurePlan: translations = ("옆으로 빠져 연타를 흘려. 끝난 뒤 한두 발만 치고 다시 거리를 벌려.", "Sidestep his combination. Answer with one or two shots, then get out of range.", "横へ動いて連打をかわし、打ち終わりに一、二発返せ。すぐに距離を取り直すんだ。")
        case .coachOutboxerRead: translations = ("빠르게 옆으로 움직이며 잽과 스트레이트를 친다. 두 발 뒤엔 거리를 벌린다.", "He jabs and crosses while moving sideways, then backs out after two punches.", "素早く横へ動きながらジャブとストレートを打ち、二発の後は距離を取る。")
        case .coachOutboxerPlan: translations = ("잽은 옆으로 피하고 빠질 길을 막아. 붙었을 때 바디를 짧게 쳐.", "Sidestep the jab and cut off his exit. Get close for short body shots.", "ジャブを横にかわして逃げ道を塞げ。接近したらボディを短く打つんだ。")
        case .coachCounterRead: translations = ("머리 공격을 더킹과 위빙으로 피하고 반격한다. 헛친 뒤 무리하게 연타하지 마.", "He ducks and weaves under head shots, then counters. Don't keep swinging after a miss.", "顔へのパンチをダッキングやウィービングで避け、反撃してくる。空振りの後は打ち続けるな。")
        case .coachCounterPlan: translations = ("가까이서 바디를 노려. 반격을 막거나 피한 뒤 짧게 되받아쳐.", "Work the body up close. Block or evade the counter before punching again.", "接近してボディを狙え。反撃を防ぐか避けた後、短く打ち返せ。")
        case .coachSluggerRead: translations = ("붙으면 지칠 때까지 훅과 어퍼컷을 이어 친다. 스태미나가 부족해지면 공격을 멈추고 쉰다.", "Up close, he chains heavy punches until his stamina runs low. Then he stops to recover.", "接近するとスタミナが足りなくなるまで強打を続ける。疲れると攻撃を止めて回復する。")
        case .coachSluggerPlan: translations = ("연타 중엔 옆으로 빠져 버텨. 지쳐서 공격을 멈추면 짧게 반격하고 다시 빠져.", "Stay off his line during the barrage. When he stops to recover, strike briefly and get out.", "連打中は横へ動いてしのげ。疲れて攻撃が止まったら、短く反撃して離れろ。")
        case .coachRivalRead: translations = ("이전 경기에서 네 습관을 배웠다. 같은 수를 반복하면 다음 라운드에서 읽힌다.", "He knows your habits from earlier bouts. Repeat the same moves and he'll read them next round.", "これまでの試合でお前の癖を覚えてきた。同じ動きを繰り返すと、次のラウンドで読まれるぞ。")
        case .coachRivalPlan: translations = ("머리와 바디, 회피 방향을 바꿔. 연타가 끝나고 쉬는 틈에 짧게 반격해.", "Mix head and body shots and vary your evasions. Counter briefly when he rests after a combo.", "顔とボディ、回避方向を変えろ。連打が終わって休む隙に短く反撃するんだ。")
        case .championshipCoachCongratulations: translations = ("잘했다. 끝까지 네 방식으로 싸웠구나. 축하한다, 챔피언.", "You fought your own way to the end. Well done, champion.", "よくやった。最後まで自分のやり方を貫いたな。おめでとう、チャンピオン。")
        }
        switch language {
        case .korean: return translations.0
        case .english: return translations.1
        case .japanese: return translations.2
        }
    }
}

enum StoryPurchaseText {
    case offerTitle, oneTimePurchase, availableContent, campaignTitle, campaignDetail
    case instantRewards, starterOutfitDetail
    case scenesTitle, scenesDetail, earnedRewards, rewardsRequireVictory, victoryOnlyNotice
    case freeRewards, freeRewardsDetail, storyRewards, storyRewardsDetail, storyAccessRequired, purchaseToEarn
    case victoryRequirement, championshipVictory, freePlay, storyButtonSubtitle, purchaseBenefits
    case buy, restorePurchases, loadingPrice, checkingAccess, accessUnavailable
    case productUnavailable, verificationFailed, purchaseFailed, restoreFailed, noPurchasesFound, pendingPurchase
    case tryAgain

    func text(for language: AppLanguage) -> String {
        let translations: (String, String, String)
        switch self {
        case .offerTitle: translations = ("스토리 모드 해금", "UNLOCK STORY MODE", "ストーリーモードを解放")
        case .oneTimePurchase: translations = ("한 번 구매 · 영구 이용 · 구독 없음", "One purchase. Permanent access. No subscription.", "買い切り・永続利用・サブスクリプションなし")
        case .instantRewards: translations = ("구매 즉시 지급", "INCLUDED WITH PURCHASE", "購入ですぐ獲得")
        case .starterOutfitDetail: translations = ("매트 블랙 쇼츠, 진홍색 패널·글러브, 흰색 허리밴드의 스토리 전용 시작 복장. 구매 즉시 해금되며, 클리어 없이 착용할 수 있습니다.", "A Story-exclusive starter kit with matte black trunks, crimson panels and gloves, and a white waistband. Unlocks on purchase, with no Story wins required.", "マットブラックのトランクス、深紅のパネル・グローブ、白いウエストバンドのストーリー専用スタート衣装。購入ですぐ解放され、クリア不要で着用できます。")
        case .availableContent: translations = ("구매로 열리는 콘텐츠", "YOUR STORY ACCESS", "購入で利用できるコンテンツ")
        case .campaignTitle: translations = ("챔피언십까지 이어지는 스토리", "THE ROAD TO THE CHAMPIONSHIP", "王座へ続くストーリー")
        case .campaignDetail: translations = ("서로 다른 \(StoryOpponent.allCases.count)명의 상대와 순서대로 대결. 경기 진행을 저장하고 이어서 도전할 수 있습니다.", "Face \(StoryOpponent.allCases.count) distinct opponents in sequence. Save your bout progress and resume your campaign.", "個性の異なる\(StoryOpponent.allCases.count)人と順番に対戦。試合の進行を保存して再開できます。")
        case .scenesTitle: translations = ("스토리 컷씬과 다시 보기", "STORY SCENES AND REPLAYS", "ストーリーシーンとリプレイ")
        case .scenesDetail: translations = ("진행에 따라 등장 장면과 RIVAL의 이야기를 감상하고, 해금한 장면을 다시 볼 수 있습니다.", "Discover entrances and RIVAL's story as you progress, then replay the scenes you unlock.", "進行に応じて登場シーンとRIVALの物語を楽しみ、解放したシーンを再生できます。")
        case .earnedRewards: translations = ("상대별 스토리 클리어 보상", "STORY CLEAR REWARDS", "対戦相手別のストーリークリア報酬")
        case .rewardsRequireVictory: translations = ("상대별 복장은 해당 상대의 스토리 대결을 직접 클리어해야 해금됩니다. 파이널 챔피언 복장과 벨트는 챔피언십 우승 보상이며, 구매만으로 지급되지 않습니다. 스토리 이용권이 있으면 얻은 보상을 RIVAL에서도 착용할 수 있습니다.", "Opponent outfits unlock only by winning their Story bouts. Final Champion and the belt require a championship victory, not just a purchase. With Story access, earned rewards can also be worn in RIVAL.", "相手ごとの衣装は、その相手のストーリー対戦をクリアして解放。ファイナルチャンピオン衣装とベルトは王座決定戦の勝利報酬で、購入だけでは獲得できません。ストーリー利用権があれば、獲得した報酬はRIVALでも着用できます。")
        case .victoryOnlyNotice: translations = ("퍼스트 벨만 구매 즉시 지급됩니다. 상대별 복장·챔피언 복장·벨트는 스토리 클리어가 필요합니다.", "Only First Bell unlocks on purchase. Opponent outfits, Final Champion and the belt require Story wins.", "購入ですぐ獲得できるのはファーストベルのみ。相手の衣装・チャンピオン衣装・ベルトにはストーリーのクリアが必要です。")
        case .freeRewards: translations = ("무료 플레이 보상", "FREE PLAY REWARDS", "無料プレイ報酬")
        case .freeRewardsDetail: translations = ("RIVAL 경기와 체육관 기록으로 해금합니다. 스토리 구매가 필요하지 않습니다.", "Earn these through RIVAL bouts and Gym records. No Story purchase is required.", "RIVALの試合とジムの記録で解放。ストーリーの購入は不要です。")
        case .storyRewards: translations = ("스토리 전용 보상", "STORY REWARDS", "ストーリー専用報酬")
        case .storyRewardsDetail: translations = ("스토리 전용 복장·벨트 착용에는 스토리 이용권이 필요합니다. 미해금 복장도 미리 볼 수 있습니다.", "Story access is required to equip Story outfits and the belt. Locked outfits can still be previewed.", "ストーリー専用衣装・ベルトの着用にはストーリー利用権が必要です。未解放の衣装もプレビューできます。")
        case .storyAccessRequired: translations = ("착용에는 스토리 이용권이 필요합니다. 클리어 기록은 유지됩니다.", "Story access is required to equip this reward. Cleared progress is kept.", "着用にはストーリー利用権が必要です。クリア記録は保持されます。")
        case .purchaseToEarn: translations = ("스토리와 시작 복장 구매", "UNLOCK STORY + STARTER KIT", "ストーリーとスタート衣装を購入")
        case .victoryRequirement: translations = ("해당 상대의 스토리 대결 클리어: ", "Win this opponent's Story bout: ", "この相手のストーリー対戦をクリア：")
        case .championshipVictory: translations = ("스토리 챔피언십 우승", "Win the Story championship", "ストーリー王座決定戦に優勝")
        case .freePlay: translations = ("무료 플레이", "FREE PLAY", "無料プレイ")
        case .storyButtonSubtitle: translations = ("스토리 · 전용 복장과 클리어 보상", "CAMPAIGN + STORY REWARDS", "ストーリー・専用衣装とクリア報酬")
        case .purchaseBenefits: translations = ("구매 혜택", "VIEW BENEFITS", "購入特典")
        case .buy: translations = ("스토리 구매", "UNLOCK STORY", "ストーリーを購入")
        case .restorePurchases: translations = ("구매 복원", "RESTORE PURCHASES", "購入を復元")
        case .loadingPrice: translations = ("가격 확인 중", "LOADING PRICE", "価格を確認中")
        case .checkingAccess: translations = ("구매 내역 확인 중", "Checking your purchases", "購入履歴を確認中")
        case .accessUnavailable: translations = ("기존 구매 내역을 확인하지 못했습니다. 다시 확인하거나 구매를 복원해주세요.", "Your existing purchases could not be verified. Retry or restore your purchases.", "既存の購入を確認できません。再確認するか購入を復元してください。")
        case .productUnavailable: translations = ("현재 스토리 상품 정보를 불러올 수 없습니다. RIVAL과 체육관은 계속 이용할 수 있습니다.", "Story purchase information is currently unavailable. RIVAL and the Gym remain available.", "現在ストーリーの商品情報を取得できません。RIVALとジムは引き続き利用できます。")
        case .verificationFailed: translations = ("구매 내역을 검증하지 못했습니다. 구매 복원을 다시 시도해주세요.", "The purchase could not be verified. Please try restoring your purchases.", "購入を検証できません。購入の復元を再度お試しください。")
        case .purchaseFailed: translations = ("구매를 완료하지 못했습니다. 잠시 후 다시 시도해주세요.", "The purchase could not be completed. Please try again later.", "購入を完了できません。しばらくしてから再度お試しください。")
        case .restoreFailed: translations = ("구매를 복원하지 못했습니다. 구매에 사용한 App Store 계정을 확인해주세요.", "Purchases could not be restored. Check the App Store account used for your purchase.", "購入を復元できません。購入に使用したApp Storeアカウントをご確認ください。")
        case .noPurchasesFound: translations = ("복원할 스토리 구매 또는 기존 유료 앱 구매가 없습니다.", "No Story purchase or eligible paid-app purchase was found to restore.", "復元できるストーリー購入または対象の有料アプリ購入がありません。")
        case .pendingPurchase: translations = ("구매 승인 대기 중입니다. 승인되면 스토리와 시작 복장이 자동으로 해금됩니다.", "Purchase approval is pending. Story and your starter kit will unlock when approved.", "購入の承認待ちです。承認後、ストーリーとスタート衣装が自動的に解放されます。")
        case .tryAgain: translations = ("다시 확인", "CHECK AGAIN", "再確認")
        }
        switch language {
        case .korean: return translations.0
        case .english: return translations.1
        case .japanese: return translations.2
        }
    }
}

extension LocalizationManager {
    func purchase(_ text: StoryPurchaseText) -> String { text.text(for: language) }
}

enum RewardNotificationText {
    case achievementComplete, purchaseBonus, outfitUnlocked, beltUnlocked
    case legacyCustomerBenefit, storyAccessConfirmed, storyMode, storyUnlocked

    func text(for language: AppLanguage) -> String {
        let translations: (String, String, String)
        switch self {
        case .achievementComplete: translations = ("도전과제 달성", "ACHIEVEMENT COMPLETE", "実績達成")
        case .purchaseBonus: translations = ("구매 보상 지급", "PURCHASE REWARD", "購入特典を獲得")
        case .outfitUnlocked: translations = ("복장 잠금 해제", "Outfit unlocked", "衣装を解放")
        case .beltUnlocked: translations = ("벨트 잠금 해제", "Belt unlocked", "ベルトを解放")
        case .legacyCustomerBenefit: translations = ("기존 구매자 혜택", "PREVIOUS PURCHASE BENEFIT", "既存購入者特典")
        case .storyAccessConfirmed: translations = ("스토리 이용권 확인", "STORY ACCESS CONFIRMED", "ストーリー利用権を確認")
        case .storyMode: translations = ("스토리 모드", "STORY MODE", "ストーリーモード")
        case .storyUnlocked: translations = ("잠금 해제", "Unlocked", "解放")
        }
        switch language {
        case .korean: return translations.0
        case .english: return translations.1
        case .japanese: return translations.2
        }
    }
}

extension StoryOpponent {
    func coachAdviceText(at index: Int) -> StoryText {
        switch self {
        case .pressure: index == 0 ? .coachPressureRead : .coachPressurePlan
        case .outboxer: index == 0 ? .coachOutboxerRead : .coachOutboxerPlan
        case .counter: index == 0 ? .coachCounterRead : .coachCounterPlan
        case .slugger: index == 0 ? .coachSluggerRead : .coachSluggerPlan
        case .rival: index == 0 ? .coachRivalRead : .coachRivalPlan
        }
    }

    var rivalSceneLineText: StoryText {
        switch self {
        case .outboxer: .rivalComparisonLine
        case .counter: .rivalImitationLine
        case .slugger: .rivalObsessionLine
        case .rival: .rivalOwnWayLine
        default: .rivalAdmirationLine
        }
    }

    var introductionVenueText: StoryText {
        switch self {
        case .outboxer: .outboxerVenue
        case .counter: .counterVenue
        case .slugger: .sluggerVenue
        case .rival: .championshipVenue
        default: .pressureVenue
        }
    }

    var introductionLineText: StoryText {
        switch self {
        case .outboxer: .outboxerIntroductionLine
        case .counter: .counterIntroductionLine
        case .slugger: .sluggerIntroductionLine
        case .rival: .championshipIntroductionLine
        default: .pressureIntroductionLine
        }
    }

    func title(for language: AppLanguage) -> String {
        let translations: (String, String, String)
        switch self {
        case .pressure: translations = ("압박형", "PRESSURE", "プレッシャー")
        case .outboxer: translations = ("견제형", "RANGE", "牽制型")
        case .counter: translations = ("카운터형", "COUNTER", "カウンター型")
        case .slugger: translations = ("강타형", "POWER", "強打型")
        case .rival: translations = ("RIVAL", "RIVAL", "RIVAL")
        }
        switch language {
        case .korean: return translations.0
        case .english: return translations.1
        case .japanese: return translations.2
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

    func story(_ key: StoryText) -> String {
        key.text(for: language)
    }
}

/// Guards every haptic feedback call in the app behind one on/off preference, the same way `SoundManager`'s
/// `isMuted` guards audio. Kept separate from sound (a player may want buzzes off but sound on, or vice
/// versa) and separate from `GameController` since the practice room's `PracticeController` needs the same
/// preference without holding a reference to the battle controller.
#if canImport(UIKit)
@MainActor
final class HapticsManager: ObservableObject {
    static let shared = HapticsManager()
    private static let defaultsKey = "pixelBoxingHapticsEnabled"

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()

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
        let generator = generator(for: style)
        generator.impactOccurred(intensity: min(1, max(0, intensity)))
        generator.prepare()
    }

    /// Prime the heavier contact generators while the much lighter input tap is being felt.
    func prepareContact() {
        guard isEnabled else { return }
        medium.prepare()
        heavy.prepare()
        soft.prepare()
    }

    func playImpact(_ hit: CombatImpact) {
        let feedback = ImpactFeedback.sample(hit)
        let style: UIImpactFeedbackGenerator.FeedbackStyle
        switch feedback.haptic {
        case .light: style = .light
        case .medium: style = .medium
        case .heavy: style = .heavy
        case .soft: style = .soft
        case .rigid: style = .rigid
        }
        self.impact(style: style, intensity: CGFloat(feedback.intensity))
    }

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light: light
        case .medium: medium
        case .heavy: heavy
        case .soft: soft
        case .rigid: rigid
        @unknown default: medium
        }
    }

    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        notification.notificationOccurred(type)
        notification.prepare()
    }
}
#endif

/// One case per static UI string shown anywhere in the app. Keeping every string behind a key — instead of
/// scattering literals through the SwiftUI views and `CombatEngine` — is what makes the 3-language switch
/// actually reach every screen instead of just the settings menu itself.
enum L: CaseIterable {
    case tagline
    case waitingRoomButton
    case pausedTitle
    case resumeButton
    case outfitLabel
    case close
    case settingsTitle
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
    case roundStatsRivalCornerLabel
    case cinematicSkip
    case moveForwardAccessibility
    case moveBackAccessibility
    case moveLeftAccessibility
    case moveRightAccessibility
    case guardAccessibility
    case duckLeftAccessibility
    case duckRightAccessibility
    case weaveLeftAccessibility
    case weaveRightAccessibility
    case weaveEvadeMessage
    case weaveLeftControl
    case weaveRightControl
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
    case leaderboardNotConfigured
    case leaderboardRefreshButton
    case leaderboardEmptyState
    case leaderboardYouLabel
    case menuFightAction
    case menuRedCorner
    case menuRecordTitle
    case menuTotalWins
    case menuBestStreak
    case menuGymTitle
    case rivalAnalysisButton
    case rivalAnalysisSubtitle
    case rivalAnalysisKicker
    case rivalAnalysisTitle
    case rivalAnalysisReadLabel
    case rivalAnalysisReadNone
    case rivalAnalysisConfidenceLabel
    case rivalAnalysisFavoriteAttackLabel
    case rivalAnalysisAdaptationLabel
    case rivalAnalysisPlayerDodgeLabel
    case rivalAnalysisEnemyDodgeLabel
    case rivalAnalysisPlayerTopAttackLabel
    case rivalAnalysisEnemyTopAttackLabel
    case rivalAnalysisCoachLabel
    case rivalAnalysisTipNeutral
    case rivalAnalysisReadJab
    case rivalAnalysisReadBody
    case rivalAnalysisReadGuard
    case rivalAnalysisReadDuckLeft
    case rivalAnalysisReadDuckRight
    case rivalAnalysisReadRetreat
    case rivalAnalysisReadPressure
    case outfitPreviewLabel
    case outfitEquippedLabel
    case gymFreePractice
    case leaderboardRankLabel
    case leaderboardFighterLabel
    case previewCharacterAccessibility
    case styleTabLabel
    case boxingKicker, lockerKicker, settingsKicker, resetKicker, leaderboardKicker, trainingKicker
    case fightStarted, roundWon, exhausted, counterOpportunity, perfectCounter
    case knockoutWin, knockoutLoss, roundWin, roundLoss, roundDraw
    case rivalAccessibility, inputUnavailable, controlHeld, controlReleased, holdControlHint, comboAccessibilityHint
    case roundLabel, healthLabel, staminaLabel, scoreLabel

    static func pick(ko: String, en: String, ja: String, language: AppLanguage) -> String {
        switch language {
        case .korean: ko
        case .english: en
        case .japanese: ja
        }
    }

    func text(for language: AppLanguage) -> String {
        switch self {
        case .boxingKicker:
            L.pick(ko: "복싱", en: "BOXING", ja: "ボクシング", language: language)
        case .lockerKicker:
            L.pick(ko: "RIVAL / 대기실", en: "RIVAL / LOCKER ROOM", ja: "RIVAL / 控室", language: language)
        case .settingsKicker:
            L.pick(ko: "RIVAL / 환경 설정", en: "RIVAL / PREFERENCES", ja: "RIVAL / 環境設定", language: language)
        case .resetKicker:
            L.pick(ko: "RIVAL / 새로운 시작", en: "RIVAL / NEW GAME", ja: "RIVAL / 新たな挑戦", language: language)
        case .leaderboardKicker:
            "RIVAL / GAME CENTER"
        case .trainingKicker:
            L.pick(ko: "RIVAL / 트레이닝", en: "RIVAL / TRAINING", ja: "RIVAL / トレーニング", language: language)
        case .fightStarted:
            L.pick(ko: "경기 시작", en: "FIGHT", ja: "試合開始", language: language)
        case .roundWon:
            L.pick(ko: "라운드 승리", en: "ROUND WON", ja: "ラウンド勝利", language: language)
        case .exhausted:
            L.pick(ko: "탈진 · 잠시 회복하세요", en: "GASSED OUT · Recover for a moment", ja: "スタミナ切れ・回復を待とう", language: language)
        case .counterOpportunity:
            L.pick(ko: "카운터 기회", en: "COUNTER", ja: "反撃のチャンス", language: language)
        case .perfectCounter:
            L.pick(ko: "퍼펙트 카운터", en: "PERFECT COUNTER", ja: "パーフェクトカウンター", language: language)
        case .knockoutWin:
            L.pick(ko: "K.O. 승리", en: "K.O. WIN", ja: "K.O. 勝利", language: language)
        case .knockoutLoss:
            L.pick(ko: "K.O. 패배", en: "K.O. LOSS", ja: "K.O. 敗北", language: language)
        case .roundWin:
            L.pick(ko: "라운드 승리", en: "ROUND WIN", ja: "ラウンド勝利", language: language)
        case .roundLoss:
            L.pick(ko: "라운드 패배", en: "ROUND LOSS", ja: "ラウンド敗北", language: language)
        case .roundDraw:
            L.pick(ko: "무승부", en: "DRAW", ja: "引き分け", language: language)
        case .rivalAccessibility:
            L.pick(ko: "라이벌", en: "Rival", ja: "ライバル", language: language)
        case .inputUnavailable:
            L.pick(ko: "현재 입력 불가", en: "Currently unavailable", ja: "現在は操作できません", language: language)
        case .controlHeld:
            L.pick(ko: "누른 상태", en: "Held", ja: "押している状態", language: language)
        case .controlReleased:
            L.pick(ko: "해제됨", en: "Released", ja: "解除済み", language: language)
        case .holdControlHint:
            L.pick(ko: "이중 탭하여 누르거나 해제합니다.", en: "Double-tap to hold or release.", ja: "ダブルタップで押す・離すを切り替えます。", language: language)
        case .comboAccessibilityHint:
            L.pick(ko: "누르고 있는 가드와 더킹에 따라 공격이 바뀝니다.", en: "The punch changes with your held guard or duck.", ja: "ガードやダッキングの状態でパンチが変わります。", language: language)
        case .roundLabel:
            L.pick(ko: "라운드", en: "Round", ja: "ラウンド", language: language)
        case .healthLabel:
            L.pick(ko: "체력", en: "Health", ja: "体力", language: language)
        case .staminaLabel:
            L.pick(ko: "스태미나", en: "Stamina", ja: "スタミナ", language: language)
        case .scoreLabel:
            L.pick(ko: "스코어", en: "Score", ja: "スコア", language: language)
        case .styleTabLabel:
            L.pick(ko: "스타일", en: "Style", ja: "スタイル", language: language)
        case .outfitPreviewLabel:
            L.pick(ko: "미리보기", en: "Preview", ja: "プレビュー", language: language)
        case .outfitEquippedLabel:
            L.pick(ko: "착용 중", en: "Equipped", ja: "着用中", language: language)
        case .gymFreePractice:
            L.pick(ko: "스태미나 소모 없는 연습", en: "Practice without stamina cost", ja: "スタミナ消費なしの練習", language: language)
        case .leaderboardRankLabel:
            L.pick(ko: "순위", en: "Rank", ja: "順位", language: language)
        case .leaderboardFighterLabel:
            L.pick(ko: "선수", en: "Fighter", ja: "選手", language: language)
        case .previewCharacterAccessibility:
            L.pick(ko: "선택한 스타일과 복장의 복서 미리보기", en: "Boxer preview with the selected style and outfit", ja: "選択したスタイルと衣装のボクサープレビュー", language: language)
        case .menuFightAction:
            L.pick(ko: "링에 오르기", en: "Enter the ring", ja: "リングへ", language: language)
        case .menuRedCorner:
            L.pick(ko: "레드 코너", en: "RED CORNER", ja: "赤コーナー", language: language)
        case .menuRecordTitle:
            L.pick(ko: "나의 경기 기록", en: "YOUR RECORD", ja: "あなたの戦績", language: language)
        case .menuTotalWins:
            L.pick(ko: "통산 승리", en: "TOTAL WINS", ja: "通算勝利", language: language)
        case .menuBestStreak:
            L.pick(ko: "최고 연승", en: "BEST STREAK", ja: "最高連勝", language: language)
        case .menuGymTitle:
            L.pick(ko: "체육관", en: "Gym", ja: "ジム", language: language)
        case .rivalAnalysisButton:
            L.pick(ko: "라이벌 분석", en: "Rival Analysis", ja: "ライバル分析", language: language)
        case .rivalAnalysisSubtitle:
            L.pick(ko: "읽기 성향 · 대응 힌트", en: "Read tendency · counter tips", ja: "読み傾向・対策ヒント", language: language)
        case .rivalAnalysisKicker:
            L.pick(ko: "RIVAL / 분석", en: "RIVAL / ANALYSIS", ja: "RIVAL / 分析", language: language)
        case .rivalAnalysisTitle:
            L.pick(ko: "라이벌 리포트", en: "Rival Report", ja: "ライバルレポート", language: language)
        case .rivalAnalysisReadLabel:
            L.pick(ko: "현재 읽기", en: "Current read", ja: "現在の読み", language: language)
        case .rivalAnalysisReadNone:
            L.pick(ko: "아직 뚜렷한 패턴이 없습니다", en: "No clear pattern yet", ja: "まだ明確なパターンはありません", language: language)
        case .rivalAnalysisConfidenceLabel:
            L.pick(ko: "읽기 신뢰도", en: "Read confidence", ja: "読みの信頼度", language: language)
        case .rivalAnalysisFavoriteAttackLabel:
            L.pick(ko: "내 반복 공격", en: "Repeated attack", ja: "自分の反復攻撃", language: language)
        case .rivalAnalysisAdaptationLabel:
            L.pick(ko: "적응 강도", en: "Adaptation level", ja: "適応レベル", language: language)
        case .rivalAnalysisPlayerDodgeLabel:
            L.pick(ko: "내 회피 성공", en: "My dodges", ja: "自分の回避成功", language: language)
        case .rivalAnalysisEnemyDodgeLabel:
            L.pick(ko: "라이벌 회피 성공", en: "Rival dodges", ja: "ライバルの回避成功", language: language)
        case .rivalAnalysisPlayerTopAttackLabel:
            L.pick(ko: "내 주요 공격", en: "My top attack", ja: "自分の主な攻撃", language: language)
        case .rivalAnalysisEnemyTopAttackLabel:
            L.pick(ko: "라이벌 주요 공격", en: "Rival top attack", ja: "ライバルの主な攻撃", language: language)
        case .rivalAnalysisCoachLabel:
            L.pick(ko: "코너 코멘트", en: "Corner comment", ja: "コーナーコメント", language: language)
        case .rivalAnalysisTipNeutral:
            L.pick(ko: "같은 입력을 연속으로 반복하면 읽히기 쉬워집니다. 잽·바디·더킹 타이밍을 섞어보세요.", en: "Repeating the same input is easier to read. Mix your jab, body shots, and duck timing.", ja: "同じ入力を繰り返すと読まれやすくなります。ジャブ・ボディ・ダッキングのタイミングを混ぜましょう。", language: language)
        case .rivalAnalysisReadJab:
            L.pick(ko: "잽 패턴", en: "Jab pattern", ja: "ジャブ傾向", language: language)
        case .rivalAnalysisReadBody:
            L.pick(ko: "바디 패턴", en: "Body pattern", ja: "ボディ傾向", language: language)
        case .rivalAnalysisReadGuard:
            L.pick(ko: "가드 셸", en: "Guard shell", ja: "ガードシェル", language: language)
        case .rivalAnalysisReadDuckLeft:
            L.pick(ko: "왼쪽 더킹 패턴", en: "Left duck pattern", ja: "左ダッキング傾向", language: language)
        case .rivalAnalysisReadDuckRight:
            L.pick(ko: "오른쪽 더킹 패턴", en: "Right duck pattern", ja: "右ダッキング傾向", language: language)
        case .rivalAnalysisReadRetreat:
            L.pick(ko: "후퇴 패턴", en: "Retreat pattern", ja: "後退傾向", language: language)
        case .rivalAnalysisReadPressure:
            L.pick(ko: "압박 패턴", en: "Pressure pattern", ja: "圧力傾向", language: language)
        case .tagline:
            L.pick(ko: "상대는 당신을 기억한다", en: "Your opponent remembers you.", ja: "相手はあなたを覚えている。", language: language)
        case .waitingRoomButton:
            L.pick(ko: "대기실", en: "Waiting Room", ja: "待機室", language: language)
        case .pausedTitle:
            L.pick(ko: "일시정지", en: "PAUSED", ja: "一時停止", language: language)
        case .resumeButton:
            L.pick(ko: "계속하기", en: "RESUME", ja: "再開", language: language)
        case .outfitLabel:
            L.pick(ko: "복장", en: "Outfit", ja: "衣装", language: language)
        case .close:
            L.pick(ko: "닫기", en: "Close", ja: "閉じる", language: language)
        case .settingsTitle:
            L.pick(ko: "설정", en: "Settings", ja: "設定", language: language)
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
        case .practiceRoomSubtitle:
            L.pick(ko: "샌드백으로 조작 · 콤보 연습", en: "Practice controls and combos on the heavy bag", ja: "サンドバッグで操作・コンボ練習", language: language)
        case .exitButton:
            L.pick(ko: "나가기", en: "Exit", ja: "退出", language: language)
        case .learningResetMessage:
            L.pick(ko: "학습 메모리 초기화 · ROUND 1", en: "Learning memory reset · ROUND 1", ja: "学習メモリ初期化・ROUND 1", language: language)
        case .roundLostMessage:
            L.pick(ko: "라운드 패배 · 같은 라운드 재도전", en: "ROUND LOST · Retry this round", ja: "ラウンド敗北・同じラウンドで再挑戦", language: language)
        case .drawMessage:
            L.pick(ko: "무승부 · 남은 체력이 같습니다", en: "DRAW · Equal health", ja: "引き分け・残り体力が同じです", language: language)
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
        case .weaveLeftAccessibility:
            L.pick(ko: "왼쪽 위빙", en: "Weave Left", ja: "左ウィービング", language: language)
        case .weaveRightAccessibility:
            L.pick(ko: "오른쪽 위빙", en: "Weave Right", ja: "右ウィービング", language: language)
        case .weaveEvadeMessage:
            L.pick(ko: "위빙으로 공격을 피했습니다!", en: "Weave evasion!", ja: "ウィービングで回避！", language: language)
        case .weaveLeftControl:
            L.pick(ko: "L\n위빙", en: "L\nWEAVE", ja: "左\nウィーブ", language: language)
        case .weaveRightControl:
            L.pick(ko: "R\n위빙", en: "R\nWEAVE", ja: "右\nウィーブ", language: language)
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
        case .leaderboardNotConfigured:
            L.pick(ko: "이 앱의 Game Center 순위표가 아직 연결되지 않았습니다.", en: "The Game Center leaderboard isn't configured for this app.", ja: "このアプリのGame Centerランキングはまだ設定されていません。", language: language)
        case .leaderboardRefreshButton:
            L.pick(ko: "랭킹 새로고침", en: "Refresh rankings", ja: "ランキングを更新", language: language)
        case .leaderboardEmptyState:
            L.pick(ko: "아직 등록된 랭킹이 없어요. 첫 승리를 기록해 보세요!", en: "No rankings yet. Be the first to log a win!", ja: "まだランキングがありません。最初の勝利を記録しましょう!", language: language)
        case .leaderboardYouLabel:
            L.pick(ko: "나", en: "You", ja: "あなた", language: language)
        }
    }

    /// The coach's rotating speech-bubble tutorial tips shown in the practice room (see
    /// `PracticeScene.updateCoachTip`), fully translated per-language so switching languages mid-session
    /// replaces the coach's messages too, not just static UI chrome.
    static func coachTipMessages(for language: AppLanguage) -> [String] {
        switch language {
        case .korean:
            return [
                "더킹을 하면서 같은 방향의 주먹을 내지르면 바디샷을 날릴 수 있어",
                "왼 위빙 뒤 잽, 오른 위빙 뒤 크로스를 누르면 같은 쪽 훅으로 이어져",
                "위빙은 한 번 누르면 옆으로 조금 빠지는 동작이야. 계속 누르고 있어도 반복하지 않아",
                "위빙은 맞는 방향과 타이밍에 머리 공격을 피하지만 바디샷은 막아주지 않아",
                "바디샷은 낮게 준비한 주먹으로 복부를 아래에서 위로 파고들어봐",
                "잽은 가장 긴 사거리로 견제하고, 크로스는 조금 더 가까이서 맞혀봐",
                "훅을 던질 땐 발끝과 골반을 함께 돌려야 힘이 실려",
                "어퍼컷은 사거리가 짧아, 가까이 붙은 뒤 노려봐",
                "가드는 절대 내리지 마, 턱을 감싸고 팔꿈치로 몸통을 막아",
                "스텝은 항상 가볍게, 발이 땅에 오래 붙어있지 않게 해",
                "펀치를 낼 때마다 숨을 참지 말고 짧게 내쉬어봐",
                "백스텝으로 거리를 벌린 다음 바로 반격을 준비해",
                "카운터는 타이밍이 전부야, 상대 펀치가 끝나는 순간을 노려",
                "같은 펀치를 세 번 이상 연속으로 쓰면 위력이 줄어들어",
                "더킹 후 바로 몸을 세우지 말고 잠깐 낮은 자세를 유지해봐",
                "같은 패턴만 반복하면 상대가 읽어버려, 콤보를 섞어봐",
                "크로스는 반대쪽 발로 바닥을 밀어내면서 던져야 회전력이 붙어",
                "시야는 상대 눈이 아니라 가슴 쪽을 봐야 다음 동작이 먼저 보여",
                "원투 콤보 후엔 곧바로 가드로 돌아오는 습관을 들여",
                "가드에 막힌 펀치도 상대 스태미나를 깎아, 가드가 깨질 틈을 노려봐",
                "팔꿈치를 몸에 붙이고 있어야 옆구리가 뚫리지 않아",
                "상대가 전진할 땐 무리하게 맞서지 말고 각도를 바꿔 피해봐",
                "잽으로 거리를 재고 크로스로 마무리하는 게 기본 중의 기본이야",
                "시간이 끝나면 남은 체력이 더 많은 쪽이 승리해",
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
                "Press JAB after a left weave, or CROSS after a right weave, to link a same-side hook.",
                "One weave press makes one small side step. Holding it does not repeat the move.",
                "A weave avoids head punches with the right direction and timing, not body shots.",
                "Load a body shot low, then drive a short rising punch into the body.",
                "The jab has the longest reach. Step a little closer to land the cross.",
                "Rotate your hips and toes together when you throw a hook, or it loses power.",
                "Uppercuts have short reach. Close the distance before throwing one.",
                "Never drop your guard -- tuck your chin and block your body with your elbows.",
                "Keep your steps light -- don't let your feet stay planted too long.",
                "Don't hold your breath on every punch, exhale sharply instead.",
                "Backstep to create distance, then get ready to counter right away.",
                "Countering is all about timing -- strike the instant their punch ends.",
                "Repeating the same punch three or more times in a row reduces its power.",
                "After ducking, stay low for a beat instead of standing straight back up.",
                "Repeating the same pattern lets your opponent read you -- mix up your combos.",
                "Push off your back foot when throwing a cross for extra rotational power.",
                "Watch your opponent's chest, not their eyes -- you'll see the next move sooner.",
                "Get in the habit of returning to guard right after a one-two combo.",
                "Blocked punches drain the defender's stamina. Watch for a guard break.",
                "Keep your elbows tucked in, or your ribs stay wide open.",
                "When your opponent charges in, change your angle instead of meeting them head-on.",
                "Measure with the jab, finish with the cross -- that's boxing 101.",
                "When time runs out, the fighter with more health remaining wins.",
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
                "左ウィービング後にジャブ、右ウィービング後にクロスで同じ側のフックにつながるよ",
                "ウィービングは一押しで少し横へ動く。押し続けても繰り返さないよ",
                "ウィービングは方向とタイミングが合えば頭へのパンチを避ける。ボディには注意しよう",
                "ボディは拳を低く構えて、腹へ下から短く突き上げよう",
                "ジャブのリーチが一番長い。クロスはもう少し近づいて当てよう",
                "フックを打つときは足先と骨盤を一緒に回して",
                "アッパーはリーチが短い。距離を詰めてから狙おう",
                "ガードは絶対下げるな、あごを引いて肘で体を守れ",
                "ステップは常に軽く、足を長く地面につけないで",
                "パンチのたびに息を止めず、短く吐いてみて",
                "バックステップで距離を取ったらすぐ反撃の準備を",
                "カウンターはタイミングが全て、相手のパンチが終わる瞬間を狙え",
                "同じパンチを3回以上続けると威力が下がるよ",
                "ダッキングの後はすぐ立たず少し低い姿勢を保って",
                "同じパターンばかりだと読まれる、コンビネーションを混ぜよう",
                "クロスは逆足で地面を蹴ると回転力がつく",
                "相手の目じゃなく胸を見ると次の動きが早く分かる",
                "ワンツーの後はすぐガードに戻る癖をつけて",
                "ガードされたパンチも相手のスタミナを削る。ガードが崩れる隙を狙おう",
                "肘を体につけていないと脇腹が空いてしまう",
                "相手が突っ込んできたら無理せず角度を変えてかわして",
                "ジャブで距離を測りクロスで仕留めるのが基本中の基本",
                "時間切れのときは残り体力が多い方が勝つよ",
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
