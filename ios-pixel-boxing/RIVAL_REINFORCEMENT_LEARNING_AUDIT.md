# RIVAL 강화학습 구현 및 최종 적응형 AI 검증 기록

> 현재 iOS 기준: RIVAL 1.2(6) 작업 트리 · 2026-10-12 소스·기존 제출 기록 대조
> 최초 감사 기록: 2026-09-06 · 날짜별 실행 검증은 당시 기록으로 보존
> 범위: 현재 iOS 코드·문서와 기존 감사의 Git 이력·VS Code 로컬 작업 기록
> 원칙: 확인되지 않은 개발 동기, 성능 결과, 사용자 체감 결과는 사실로 단정하지 않는다.

`1.2(6)`는 실제 [RIVAL.xcodeproj/project.pbxproj](RIVAL.xcodeproj/project.pbxproj)의
마케팅 버전 `1.2`, 빌드 번호 `6`이며 [project.yml](project.yml)도 일치한다.
실제 프로젝트를 기준으로 하며 문서 갱신을 위해 함부로 재생성하지 않는다. iPhone·iPad 가로 전용, iOS 17 이상이다.
2026-10-12 확인 당시 공개 App Store는 유료 1.1(USD 1.99 / KRW 3,300)이며 무료 전환·1.2 출시는 미완료다.
2026-10-11 서명된 Release 1.2(6) 아카이브 업로드와 앱·Story IAP·Total Wins 순위표의
3항목 동반 심사 제출 기록은 `Waiting for Review`, 수동 출시(`MANUAL`)다.
[제출 영수증](AppStoreMetadata/1.2-submission.json)과
[출시 체크리스트](RELEASE_READINESS_CHECKLIST.md)를 따르며 오늘 새 조회·빌드 결과가 아니다.
당시 로컬 Release StoreKitTest UI 캡처 6개 통과·첨부 30개는 제한된 화면 검증이다.
실계정 구매·복원·권한 취소·기존 유료 고객 이행·Game Center는 미검증이다.
현재 작업 트리와 기존 아카이브·App Store·TestFlight 배포본이 동일하다고 가정하지 않는다.
이번 문서 정리에서는 과거 C++/Python/iOS 실행 검증을 재실행하거나 새 빌드·테스트·
실기기 확인·배포 조회를 수행하지 않았다. 과거 조사 결과는 그때의 범위에 한정한다.

## 결론

RIVAL의 강화학습은 한 단계의 단일 구현이 아니었다.

1. 초기 C++ TUI에는 실제 온라인 Q-learning 코드, Q-table 저장, 전투 루프 연결이 구현됐다.
2. 이후 Python Pixel Boxing 코어에는 17개 행동, 관측 상태, 보상 이벤트, 렌더링 없는 시뮬레이터가 구현됐지만 정책 학습기와 정책 저장/로드는 구현되지 않았다.
3. 현재 iOS RIVAL은 Q-table, 신경망, 보상 기반 정책 갱신을 사용하지 않는다. `HabitMemory`와 양측 `RivalAttackMemory`를 완료 라운드에서 확정하고 다음 라운드부터 사전에 작성된 규칙의 가중 확률에 반영한다. 라운드 중 난도·학습모델은 고정한다.

정확한 표현은 다음과 같다.

> 초기 C++ 프로토타입에는 온라인 Q-learning이 실제 구현됐고, Python 단계에서는 RL 훈련 환경을 준비했으나, 최종 iOS 앱은 설명 가능한 규칙·통계 기반 적응형 AI를 채택했다.

## 근거의 수준

| 구분 | 이 문서에서 뜻하는 것 |
| --- | --- |
| 직접 코드 근거 | 현재 작업 트리에 함수, 상태, 호출 경로가 존재한다. |
| 문서 근거 | 저장소 문서가 설계 또는 제품 범위를 명시한다. |
| 과거 작업 기록 | 로컬 VS Code 세션에 남은 사용자 요구와 당시 작업 보고다. 역사적 맥락의 근거이며 현재 코드 자체를 대체하지 않는다. |
| 미확인 | 코드, 문서, 세션 기록 어디에서도 직접 근거를 찾지 못했다. |

### 주요 근거

- 초기 C++ Q-learning: [../include/game/ai_agent.hpp](../include/game/ai_agent.hpp), [../src/game/ai_agent.cpp](../src/game/ai_agent.cpp), [../src/game/game_session.cpp](../src/game/game_session.cpp), [../src/game/save_game.cpp](../src/game/save_game.cpp)
- Python RL 준비 환경: [../desktop-pixel-boxing/pixel_boxing/boxing_core.py](../desktop-pixel-boxing/pixel_boxing/boxing_core.py), [../tests/test_pixel_boxing_core.py](../tests/test_pixel_boxing_core.py), [../docs/PIXEL_BOXING_GAME_DESIGN.md](../docs/PIXEL_BOXING_GAME_DESIGN.md)
- 현재 iOS AI: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift), [PixelBoxingIOS/RivalAI.swift](PixelBoxingIOS/RivalAI.swift), [PixelBoxingIOS/StoryMode.swift](PixelBoxingIOS/StoryMode.swift), [PixelBoxingIOSTests/PlaceholderTests.swift](PixelBoxingIOSTests/PlaceholderTests.swift), [AI_USAGE.md](AI_USAGE.md), [PixelBoxingIOS/GameView.swift](PixelBoxingIOS/GameView.swift)
- 과거 대화 기록: 로컬 VS Code 세션 `02474283-4175-4bb7-9854-ed8a560cc96f`, `47210cd2-1316-4043-8a54-a4d919d25571`

---

## 1. 강화학습은 어디까지 구현 또는 설계됐는가

### 1-1. 최초 구상: 기획 단계

2026-08-03의 초기 작업 기록에는 다음이 기획으로 제시됐다.

- 상태 후보: 양측 HP, 거리, 양측 스태미나, 최근 플레이어/적 행동, 최근 피격/회피 성공, 콤보, 전투 시간, 쿨다운
- 행동 후보: 공격, 강공격, 방어, 회피, 패링, 후퇴, 접근
- 보상 예시: 플레이어에게 피해 `+10`, 플레이어 처치 `+100`, 피격 `-5`, 사망 `-100`, 쓸모없는 행동 `-1`

이 내용은 세션 `02474283-4175-4bb7-9854-ed8a560cc96f`, turn 0의 사용자 요구에 남은 초기 기획이다. 아래 C++ 구현 및 이후 Python 설계와 정확히 같은 사양은 아니므로 구현 사실과 혼동하면 안 된다.

### 1-2. 초기 C++ TUI: 실제 온라인 Q-learning 프로토타입

초기 C++ 구현에는 Q-table 기반 온라인 학습이 실제로 들어 있다.

#### 상태(state)

`AIAgent::encode_state()`는 상태를 다음 네 버킷의 문자열 키로 압축한다.

```cpp
distance_bucket(state) : hp_bucket(state.player) : hp_bucket(state.enemy) : round_bucket(state)
```

- 거리: `0...5`로 제한
- 양측 HP: 20% 단위 버킷
- 라운드: `1...3`, `4...6`, `7+`의 세 구간

근거: [../src/game/ai_agent.cpp](../src/game/ai_agent.cpp)의 `distance_bucket`, `hp_bucket`, `round_bucket`, `AIAgent::encode_state`.

플레이어 행동 패턴은 Q-table 상태 키에는 포함되지 않고, `PatternModel`이 별도로 행동 빈도와 행동 전이 횟수를 기록해 다음 행동을 예측한다. 즉 당시 구조는 순수 Q-learning 하나가 아니라 Q-table과 규칙 기반 패턴 예측을 결합한 하이브리드다.

근거: [../include/game/pattern_model.hpp](../include/game/pattern_model.hpp), [../src/game/pattern_model.cpp](../src/game/pattern_model.cpp), [../src/game/ai_agent.cpp](../src/game/ai_agent.cpp)의 `choose_exploratory_action`.

#### 행동(action)

`Action` 열거형에는 총 14개 선택지가 있다.

- 8종 공격: `Jab`, `Cross`, `LeftBody`, `RightHook`, `LeftHook`, `RightBody`, `LeftUppercut`, `RightUppercut`
- 방어: `Guard`, `DuckLeft`, `DuckRight`
- 풋워크: `StepBack`, `StepForward`
- 대기: `Wait`

근거: [../include/game/action.hpp](../include/game/action.hpp).

#### 보상(reward)

실제 C++ 보상은 초기 기획의 보상표를 그대로 사용하지 않았다. `GameSession::compute_enemy_reward()`는 다음을 계산한다.

```text
reward = 2.5 * playerDamage
       - 2.2 * enemyDamage
       + pressureBonus
       - 0.05 * staminaCost
       + knockoutBonus
```

- 플레이어에게 입힌 피해: 피해량당 `+2.5`
- 적이 받은 피해: 피해량당 `-2.2`
- 거리 보정: 근거리 `+1.0`, 중거리 `+0.4`, 그 외 `-0.2`
- 행동 스태미나 비용: 비용당 `-0.05`
- 플레이어 KO: `+18`, 적 KO: `-18`

근거: [../src/game/game_session.cpp](../src/game/game_session.cpp)의 `compute_enemy_reward`.

#### 실제 학습 코드와 실행 흔적

`AIAgent::apply_q_update()`에는 다음 Q-learning 갱신이 구현돼 있다.

```cpp
const auto target = reward + kDiscountFactor * next_value;
current_row[action_index] = current_value + kLearningRate * (target - current_value);
```

- 학습률 `kLearningRate = 0.18`
- 할인율 `kDiscountFactor = 0.82`
- 탐험률 `kExplorationRate = 0.14`

적이 행동할 때 이전 상태와 행동을 보관하고, 공격 결과가 정리된 뒤 `record_transition()`으로 보상을 전달한다. Q-table은 `AI_RL` 섹션으로 저장·복원된다.

근거: [../src/game/ai_agent.cpp](../src/game/ai_agent.cpp)의 `apply_q_update`, `record_transition`; [../src/game/game_session.cpp](../src/game/game_session.cpp)의 `apply_enemy_action`, `commit_enemy_learning_if_ready`; [../src/game/save_game.cpp](../src/game/save_game.cpp)의 `write_q_table`, `read_q_table`.

현재 로컬의 [../game_save.txt](../game_save.txt)에는 다음 헤더가 존재한다.

```text
AI_RL
343 149
```

직렬화 코드에 따르면 이는 `343`회의 학습 갱신과 `149`개의 Q-table 상태 행을 뜻한다. 이는 Q-table이 비어 있지 않은 저장 산출물이라는 직접 증거다.

다만 이 저장 파일은 Git 추적 대상이 아닌 로컬 파일이다. 따라서 이 감사에서는 "현재 남아 있는 저장 산출물이 Q-learning 갱신값을 포함한다"까지만 확인하며, 해당 값이 어떤 사용자 플레이에서 언제 생성됐는지까지는 단정하지 않는다.

2026-08-06의 과거 세션 turn 38도 C++ 구조를 "전이마다 작은 Q-value를 갱신하는 온라인 Q-learning"으로 보고했고, 빌드와 스모크 테스트 통과를 기록했다. 이는 당시 작업 기록이지만, 이 문서에서는 현재 코드와 저장 산출물로 재확인 가능한 부분만 구현 사실로 사용한다.

### 1-3. Python Pixel Boxing: RL 훈련 환경과 인터페이스

Python 코어는 C++보다 넓은 RL 인터페이스를 실제로 구현했다.

#### Python 관측 상태(state)

`CombatObservation`은 다음을 포함한다.

- 거리 구간, 상대 각도 구간
- 양측 HP/스태미나 구간
- 양측 현재 행동
- 양측 노출·스태거 상태
- 로프/코너/중앙 구간
- 남은 시간 구간

근거: [../desktop-pixel-boxing/pixel_boxing/boxing_core.py](../desktop-pixel-boxing/pixel_boxing/boxing_core.py)의 `CombatObservation`, `HeadlessCombatSimulator.observe`.

#### Python 행동(action)

`RL_ACTIONS`는 총 17개다.

- 대기 1개: `wait`
- 풋워크 4개: `approach`, `retreat`, `circle_left`, `circle_right`
- 방어 4개: `guard`, `duck_left`, `duck_right`, `backstep`
- 공격 8개: 잽, 크로스, 좌우 바디, 좌우 훅, 좌우 어퍼컷

스태미나 부족, 경직, 탈진 등으로 실행할 수 없는 행동은 `valid_actions()`가 마스킹한다.

근거: [../desktop-pixel-boxing/pixel_boxing/boxing_core.py](../desktop-pixel-boxing/pixel_boxing/boxing_core.py)의 `RL_ACTIONS`, `HeadlessCombatSimulator.valid_actions`.

#### Python 보상(reward)

`REWARD_VALUES`와 `RewardEvent`가 구현돼 있다.

| 사건 | 값 |
| --- | ---: |
| 입힌 피해 1 | `+1.0` |
| 받은 피해 1 | `-1.2` |
| KO 승리 / 패배 | `+100` / `-100` |
| 판정 라운드 승리 / 패배 | `+40` / `-40` |
| 올바른 더킹 회피 | `+4` |
| 백스텝 회피 | `+3` |
| 가드 | `+1.5` |
| 카운터 | `+6` |
| 헛스윙 | `-3` |
| 스태거 | `-4` |
| 반복 공격 약화 단계 | `-1` |
| 불가능한 행동 | `-1` |
| 코너 고립 / 무의미한 대기 | `-0.1` / `-0.05` |

근거: [../desktop-pixel-boxing/pixel_boxing/boxing_core.py](../desktop-pixel-boxing/pixel_boxing/boxing_core.py)의 `REWARD_VALUES`, `RewardEvent`, `_attempt_hit`, `_finish_episode`.

#### 실제로 실행된 것과 실행되지 않은 것

`HeadlessCombatSimulator`는 렌더링 없이 `reset()`, `valid_actions()`, `observe()`, `step()`, `run_episode()`를 실행할 수 있다. 즉 RL 환경의 상태 전이, 행동 마스킹, 보상 이벤트, 에피소드 실행은 코드로 존재한다.

2026-09-06에 [../tests/test_pixel_boxing_core.py](../tests/test_pixel_boxing_core.py)를 실행해 35개 테스트가 통과했다. 이 중에는 17개 행동 마스킹, 보상 이벤트, 렌더링 없는 에피소드 실행 테스트가 포함된다.

반면 현재 `desktop-pixel-boxing/pixel_boxing/`과 해당 테스트에서 Q-table, DQN, 정책 훈련, 정책 저장/로드를 검색했을 때 구현은 발견되지 않았다. `run_episode()`는 학습을 수행하지 않고, 호출자가 전달한 `player_policy`와 `enemy_policy`를 실행할 뿐이다.

따라서 Python 단계는 학습 가능한 환경을 구현한 단계이지, 훈련된 RL 정책을 만든 단계는 아니다. 이 구분은 문서에도 남아 있다.

- "강화학습 정책 훈련, 저장, 로드, 평가"는 3단계의 남은 항목으로 열거돼 있다.
- "훈련된 강화학습 정책 저장·배포는 아직 보류 상태"라고 명시돼 있다.

근거: [../docs/PIXEL_BOXING_GAME_DESIGN.md](../docs/PIXEL_BOXING_GAME_DESIGN.md)의 10.1~10.5절 및 18절 3단계, [../docs/PROJECT_OVERVIEW.md](../docs/PROJECT_OVERVIEW.md)의 `Legacy Python Constraints`.

### 1-4. 최종 iOS 앱: 강화학습이 아닌 규칙·통계 기반 적응

현재 iOS `CombatCore.swift`에는 Q-table, 보상 기반 정책 갱신, DQN, 신경망 모델 또는 학습된 정책 파일을 읽는 코드가 없다.

[AI_USAGE.md](AI_USAGE.md)는 이를 다음처럼 명시한다.

> 현재 iOS 빌드는 신경망을 학습하거나 보상으로 정책을 갱신하는 강화학습 모델이 아닙니다. 행동 규칙과 가중치가 소스 코드에 명시된 설명 가능한 적응형 시스템입니다.

따라서 iOS에서는 Q값이나 신경망 파라미터를 훈련하지 않는다. 일반 RIVAL은 라운드 시작의
장기 습관·공격 결과·난도를 고정하고 `tacticalRead`도 확정 장기 습관으로 결정한다.
전투 중 `roundHabits`·`roundPlayerAttackResults`·`roundRivalAttackResults`는 수집만 한다.
`finishRound`에서 승패와 무관하게 병합·저장하며 다음 라운드·재도전부터 반영한다.
현재 거리·스태미나·보이는 공격·직전 공격 결과에 대한 고정 상황 반응은 실시간 학습이 아니다.

---

## 2. 최종 iOS에서 강화학습을 사용하지 않은 이유

### 사유에 대한 결론

코드와 동시대 작업 기록만으로 "강화학습을 쓰지 않게 된 단 하나의 가장 직접적인 이유"를 확정할 수는 없다.

다만 현재 문서에는 선택 기준과 온라인 학습의 위험이 명시돼 있다. [../docs/RIVAL_PORTFOLIO.typ](../docs/RIVAL_PORTFOLIO.typ)는 2026-09-02에 만든 뒤 갱신한 포트폴리오 원본이므로, 과거 결정 당시의 불변 기록이 아니라 사후에 문서화한 제품 선택 기준으로 취급한다.

| 후보 이유 | 판정 | 확인된 사실 | 근거 |
| --- | --- | --- | --- |
| 학습 데이터 부족 | 미확인 | 데이터가 부족했다는 직접 진술이나 측정 기록을 찾지 못했다. | 코드·문서·검색한 과거 기록 |
| 행동 결과의 예측 어려움 | 제한적으로 확인 | 설계 문서는 플레이 중 온라인 학습을 정책 붕괴와 난이도 불안정을 막기 위해 기본 비활성화한다고 명시한다. 이것만으로 iOS 미채택의 단일 원인이라고 단정할 수는 없다. | [../docs/PIXEL_BOXING_GAME_DESIGN.md](../docs/PIXEL_BOXING_GAME_DESIGN.md)의 10.5절 |
| 디버깅 어려움 | 부분 확인 | 포트폴리오 원본은 "디버깅 가능성"을 우선했다고 적는다. 실제로 "어려워서 포기했다"는 동시대 기록은 찾지 못했다. | [../docs/RIVAL_PORTFOLIO.typ](../docs/RIVAL_PORTFOLIO.typ) |
| 밸런스 조정 어려움 | 미확인 | "플레이 감각의 직접 조정"은 우선순위로 적혀 있으나, 밸런스 조정이 불가능하거나 어려웠다는 직접 근거는 없다. | [../docs/RIVAL_PORTFOLIO.typ](../docs/RIVAL_PORTFOLIO.typ) |
| iPhone 성능 | 미확인 | 성능 제약이 RL 미채택 원인이라는 코드·문서·세션 근거를 찾지 못했다. | 코드·문서·검색한 과거 기록 |
| 앱 크기 | 선택 기준으로 확인 | 작은 앱 크기를 초기 제품의 우선순위로 문서화했다. 그러나 이것만으로 결정적 원인이라고는 단정할 수 없다. | [../docs/RIVAL_PORTFOLIO.typ](../docs/RIVAL_PORTFOLIO.typ) |
| 오프라인 제약 | 선택 기준으로 확인 | 핵심 전투·습관 학습은 외부 AI API·서버 동기화 없이 동작한다. 선택적 Game Center 인증·랭킹 조회·기록 제출은 네트워크를 사용한다. | [../docs/RIVAL_PORTFOLIO.typ](../docs/RIVAL_PORTFOLIO.typ), [AI_USAGE.md](AI_USAGE.md), [GameCenterManager.swift](PixelBoxingIOS/GameCenterManager.swift) |
| 개발 일정 | 미확인 | 일정 때문에 전환했다는 직접 발언이나 일정 문서를 찾지 못했다. | 코드·문서·검색한 과거 기록 |
| 구현 복잡도 | 미확인 | 복잡도 때문에 포기했다는 직접 근거를 찾지 못했다. | 코드·문서·검색한 과거 기록 |

가장 조심스러운 사실 서술은 다음과 같다.

> 최종 앱은 오프라인 동작, 디버깅 가능성, 작은 앱 크기, 플레이 감각의 직접 조정을 우선한 설명 가능한 적응 시스템을 선택했다. 설계 문서는 온라인 RL이 정책 붕괴와 난이도 불안정을 일으킬 수 있음을 위험으로 기록한다. 그 외 데이터 부족, iPhone 성능, 일정, 구현 복잡도를 결정적 이유로 단정할 근거는 확인되지 않았다.

---

## 3. 규칙·통계 기반 적응형 AI를 선택하며 포기하고 얻은 것

### 포기한 것

아래 항목은 iOS 코드에 해당 기능이 없고, Python 설계에서 후속 항목으로 남아 있어 확인할 수 있다.

- 보상으로 Q값 또는 모델 파라미터를 갱신하는 정책 학습
- 사전 규칙에 없는 대응을 학습 과정에서 스스로 발견하는 능력
- 정책 훈련, 저장, 로드, 버전 관리, 기존 정책·무작위 AI와의 승률 평가 파이프라인
- 여러 사용자의 데이터를 합쳐 서버에서 재훈련하는 구조

근거: [AI_USAGE.md](AI_USAGE.md)의 "현재 방식의 범위와 한계", [../docs/PIXEL_BOXING_GAME_DESIGN.md](../docs/PIXEL_BOXING_GAME_DESIGN.md)의 10.5절 및 3단계 잔여 항목.

### 얻은 것

- 설명 가능성: 어떤 습관에 어떤 공격 가중치가 늘어나는지 `HabitSnapshot.enemyWeights()`의 조건문으로 확인할 수 있다.
- 직접 조정 가능성: 임계값, 가중치, 적응도 상한이 Swift 소스에 명시돼 있다.
- 라운드 내 정책 안정성: 관측 버퍼와 확정 학습을 분리해 당해 라운드의 행동으로 학습모델을 바꾸지 않는다.
- 제한된 공격 결과 기억: 적중·가드·회피·헛침 증거로 미리 정의된 가중치 보정만 수행한다.
- 온디바이스·오프라인 동작: 습관 데이터는 `UserDefaults` JSON으로 저장되며 외부 서버로 전송하지 않는다.
- 작은 런타임 의존성: iOS 앱에는 훈련된 외부 모델 파일이나 외부 AI API가 없다.
- 회귀 테스트 가능성: 가드 비율에 따른 바디샷 가중치와 승패에 관계없는 완료 라운드 습관 병합을 테스트할 수 있다.

근거: [AI_USAGE.md](AI_USAGE.md), [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift), [PixelBoxingIOSTests/PlaceholderTests.swift](PixelBoxingIOSTests/PlaceholderTests.swift).

"얻은 것"은 기능과 문서화된 선택 기준을 뜻한다. 실제 사용자 만족도나 난이도 품질이 더 좋아졌다는 비교 실험 결과는 확인하지 못했다.

---

## 4. 최종 iOS AI가 기록하는 행동과 바꾸는 가중치

이 절의 iOS 구현 설명은 2026-10-12의 RIVAL 1.2(6) 작업 트리에 맞춰 대조했다.
과거 C++/Python/iOS 검증 기록을 다시 실행했다는 뜻이나, 이 작업 트리가 이미 App Store에
배포됐다는 뜻은 아니다.

### 4-1. 기록하는 행동

`HabitMemory`는 다음 데이터를 누적한다.

| 기록 | 수집 방식 | 파생 값 |
| --- | --- | --- |
| 8종 공격별 횟수 | 실제 공격 시작이 성공했을 때 증가 | 최다 공격, 잽 비율, 바디 비율 |
| 당해 라운드의 최근 공격과 연속 횟수 | 공격 시작 시 갱신, 장기 병합 시 연속 상태 초기화 | `repeatStreak` |
| 가드 유지 | 프레임 시간 표본 | `guardRatio` |
| 왼쪽·오른쪽 더킹 | 프레임 시간 표본 | `duckLeftRatio`, `duckRightRatio` |
| 백스텝 | 실제 백스텝 동작 상태를 프레임 표본화 | `backstepRatio` |
| 스토리의 좌우 위빙 | 실행 중인 방향을 기존 좌우 회피 표본에 합산 | `duckLeftRatio`, `duckRightRatio` · 독립 위빙 카운터 없음 |
| 전진·후퇴 | 플레이어의 전후 이동 축을 프레임 표본화 | `pressureRatio`, `retreatRatio` |
| 전체 표본량 | 모든 프레임 표본의 누적 | `sampleStrength` |

공격은 "명중했을 때"가 아니라 "실제로 공격 시작에 성공했을 때" 기록된다. 스태미나 부족이나 경직으로 시작하지 못한 입력은 기록되지 않는다.

공격 결과는 별도 양측 `RivalAttackMemory`에 적중·가드·더킹/위빙·백스텝 회피·거리/각도/접촉 헛침으로 기록한다.
실행 불가 결과는 제외한다. 일반 모드 저장 키는 습관 `pixelBoxingHabitMemory`, 양측 결과 프로필
`pixelBoxingRivalResults`의 두 개다. 학습 초기화는 두 키를 모두 삭제하며 최고 라운드·누적 승수·보상은 보존한다.
스토리는 별도 `StoryLearningState`와 진행 저장을 사용한다.

근거: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `HabitMemory.noteAttack`, `HabitMemory.sample`, `CombatEngine.startAttack`, `CombatEngine.sampleHabits`; [AI_USAGE.md](AI_USAGE.md)의 "플레이 습관 수집".

### 4-2. 적응도

```text
adaptation = clamp(
    0.18 + 0.57 * sampleStrength,
    0.18,
    0.75
)
```

- `sampleStrength = min(1, max(totalSamples, 0) / 900)`, 표본은 경과시간의 8배다.
- 관측 적응도는 `0.18...0.75`이며 이 식에는 라운드 번호 항이 없다. 별도 `RivalDifficulty`의
    `experience = 1 - exp(-(max(1, round) - 1) / 55)`가 습관 대응 배율·판단 간격·이동·연계를 조절한다.
- 전술 읽기는 확정 장기 습관으로 라운드 시작에 결정한다. 최근 몇 초의 입력으로
    만료·감쇠·주기적 재평가하는 실시간 학습 경로는 현재 없다.
- 각 `RivalAttackMemory`는 최대 32개 결과를 보존하고 역순 증거 가중치를 기록마다 `0.94`배로 낮춘다.
    `confidence = min(1, max(0, (samples - 2) / 6))`이며 공격별 곱셈 보정은 `0.50...1.20`이다.
    이 감쇠는 기록 순서에 대한 증거 가중치이지 실시간 표본의 반감기가 아니다.
- 내부 적응 계수나 규칙 기반 confidence를 ‘학습 정확도 %’로 해석하지 않는다.

근거: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `HabitSnapshot.adaptation`, `CombatEngine.updateEnemy`.

### 4-3. RIVAL이 선택하는 행동

가중치 추첨 후보는 아래 17개이며, 보이는 준비 동작에 반응하는 별도 방어 경로에는 가드도
있다. 위빙과 후속 훅도 별도 실행 경로에서 가능하다. 아래 기본 추첨 목록을 전체 런타임 행동 수라고
해석하지 않으며 Python RL 계획과 같은 상태 전이 계약이라고도 보지 않는다.

- 8종 펀치
- `dodge_left`, `dodge_right`, `dodge_back`
- `advance`, `retreat`, `circle_left`, `circle_right`, `cut_off`
- `wait`

별도 풋워크 상태가 없어도 목표 거리 조절·서클링을 지속한다. 선택된 풋워크는
0.40–0.75초 동안 유지하며, 읽기·거리·스태미나와 후속 공격에 맞춰 움직인다. 공격·경직·
탈진·방어 동작 중 일반 풋워크는 제한된다. 스토리 견제형은 공격 중에도 횡이동하는 별도 경로다.
반응형 가드는 기존 피해 경감·스태미나 비용을 따른다. 백스텝은 순간 이동이 아니라
0.22초 동작 중 0.18초에 걸친 최대 34 게임 단위 이동이며 회피 구간은 0.035–0.18초다.
위빙은 비용 9·동작 0.36초·훅 시작 0.23초·입력 유예 0.12초·재시작 대기 0.48초다.
방향 회피 시작은 `DuckMotion.entryDuration × minimumEvadeAmount`(약 0.063초), 끝은 0.27초다.
플레이어 위빙 성공도 더킹과 같은 등급·카운터 창을 사용하며 상위 등급은 RIVAL MOMENT로 이어질 수 있다. 위빙 전용 피해 배율은 없다.

근거: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `HabitSnapshot.enemyWeights`, `CombatEngine.updateEnemy`, `CombatEngine.performEnemyDecision`.

### 4-4. 거리와 습관이 바꾸는 가중치

기본 가중치에 거리 규칙과 습관 대응 규칙을 더한 뒤, `weightedChoice()`가 가중 무작위로 하나를 선택한다.

| 관찰 조건 | RIVAL의 가중치 변화 |
| --- | --- |
| 거리 `> hitRange(jab, enemy.style) + 12` | 잽 `+1.55`, 크로스 `+0.45` |
| 원거리 조건이 아니고 거리 `> hitRange(cross, enemy.style) - 4` | 잽·크로스·훅·좌우 더킹 증가 |
| 위 두 조건에 해당하지 않는 근거리 | 좌우 바디·훅·어퍼컷·백스텝 증가 |
| 가드 비율 `> 0.22` | 좌·우 바디샷에 각각 `0.95a`, `1.20a` 추가 |
| 오른쪽 더킹 비율 `> 0.16` | 크로스·오른쪽 훅·오른쪽 어퍼컷 증가 |
| 왼쪽 더킹 비율 `> 0.16` | 잽·왼쪽 훅·왼쪽 어퍼컷 증가 |
| 잽 비율 `> 0.34` 또는 공격 표본이 있고 최다 공격이 잽 | 크로스·오른쪽 훅·오른쪽 더킹 증가 |
| 바디 비율 `> 0.30` | 좌·우 어퍼컷 증가 |
| 전진 압박 비율 `> 0.20` | 백스텝·후퇴·좌우 서클링·훅 증가 |
| 백스텝 비율 `> 0.14` 또는 후퇴 비율 `> 0.18` | 거리 차단·전진·잽·크로스 증가, 대기 가중치 `0.8`배 |
| 같은 공격을 3회 이상 반복 · 정의된 분기 | 좌·우 더킹에 각각 `0.35a` 추가하도록 정의됐으나 현재 장기 프로필 입력에서는 미적용 |
| 플레이어 노출 상태 | 크로스 `+1.8`, 오른쪽 어퍼컷 `+1.4`, 오른쪽 훅 `+0.9`, 대기 `0.05` |

여기서 `a`는 관측 적응도에 라운드별 `learningWeight`를 곱한 값이다. 플레이어 노출 상태에
대한 마지막 행은 기본 고정 보정이다. 최종 실행 경로는 실제 사거리·스태미나로 불가능한
공격을 제외하고 저장된 공격 결과·숙련도·대기·반복 공격 약화 회피 보정을 적용한 뒤 추첨한다.

`hitRange`는 `기본 사거리 × 스타일 리치 배율 + 14 + 0.34 / 0.025`이며,
인파이터(`standard`)의 원거리 경계는 83.6, 중거리 하한은 61.6 게임 단위다.
거리 경계는 스타일에 따라 달라지므로 이전의 고정 115·78을 현재 조건으로 사용하지 않는다.

현재 습관 가중치 입력은 확정된 장기 프로필이다. 장기 병합 때 `repeatStreak`를 0으로
초기화하므로 정상 수집·병합 경로에서 위 연속 3회 분기는 적용되지 않는다. 현재 공격에
대한 방어와 직전 결과의 후속 행동은 고정 상황 규칙이다. 반복 공격의 피해 감쇠는
이 AI 가중치 분기와 별개의 전투 규칙이다.

근거: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `HabitSnapshot.enemyWeights`.

### 4-5. 가중치 외에 실제로 달라지는 적 행동

```text
experience = 1 - exp(-(max(1, round) - 1) / 55)
movementBudget = 210 * (0.36 + 0.57 * experience)
decisionInterval = 1.0 - 0.80 * experience + random(0 ... (0.16 - 0.10 * experience))
learningWeight = 0.45 + 1.85 * experience
```

이동 예산은 전진·횡이동에 스타일 배율을, 후퇴 성분에는 스타일 보너스 없는 공통 0.5배를
적용한다. 공격 회수나 경직을 건너뛰지 않으며
일반 RIVAL의 기본 HP·피해·사거리도 바꾸지 않는다. 일반 반응형 회피/가드는 보이는 공격 준비
동작과 고정된 지연·확률을 사용해 펀치당 한 번 시도한다. 후반일수록 두 공격의 짧은 연계를
자주 시도한다. 이는 규칙 기반 실행 숙련도이며 보상 기반 정책 학습은 아니다.

실제 타격은 공유 `BoxingMotion.Contact`의 `activeStart...activeEnd` swept 접촉을 사용한다.
방향·조준은 공격 시작에 고정하며 매 프레임 추적하지 않는다. 양측 후보를 먼저 계산한 뒤
각 공격의 절대 actionTime이 아닌 공통 프레임 시작 대비 접촉 시간순으로 처리하고
접촉 시점의 가드·더킹·위빙·무적을 적용한다.

스토리는 압박형→견제형→카운터형→강타형→RIVAL의 별도 정책이며 60초, 최대 4·6·8·10·12라운드다.
일반 모드는 45초·최종 엔딩 없음인 반면 스토리는 한 선수의 한 라운드 3다운 TKO·그 전 4–9초
카운트 후 HP 60/스태미나 50 기상·최종 점수 판정·마지막 승리 엔딩을 사용한다.
강타형만 HP 120·추가 리치 4·공격력 1.15배이며 비용을 감당하는 동안 연타하고 회복 목표 45를 사용한다.
회복 진입에만 최대 2초 가드, 가드 회복 6/초·종료 후 비가드 16.5/초이며 같은 회복기 재가드는 없다.
공통 기본 회복은 11/초다. 마지막 RIVAL의 championship 실행 기준(판단 최대 0.28초·반응 지연 0.025초·
확률 최소 66%·이동 effort 최소 0.84)도 라운드 안에서는 고정하며 중간 학습 적응이 아니다.

스토리 이용권 `com.acertainromance401.pixelboxing.story`는 선택적 비소모성 상품이다.
퍼스트 벨(`First Bell`)은 검증된 이용권, 상대 복장·챔피언 보상은 검증된 이용권과 해당 승리가 필요하다.
기존 유료 권한은 번들 ID가 일치하는 검증된 Production `AppTransaction`의 최초 빌드 `1...4`만 인정한다.
무료 전환의 날짜 경계·배포 시차는 미확정이다. DEBUG 전체 프리뷰 `true`/Release `false`는
`rival.story.preview.v1` 별도 defaults suite를 사용하며 실제 통계·장비·Game Center 저장을 비활성화한다.
프리뷰·로컬 StoreKitTest 캡처를 실계정 구매·복원·권한 취소·기존 유료 권한 검증으로 해석하지 않는다.
세부 전투·권한 규칙은 [GAME_GUIDE.md](GAME_GUIDE.md), 개발 사례의 날짜별 기록은
[DEVELOPMENT_ISSUES_AND_SOLUTIONS.md](DEVELOPMENT_ISSUES_AND_SOLUTIONS.md)를 따른다.

근거: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `CombatEngine.updateEnemy`,
[PixelBoxingIOS/RivalAI.swift](PixelBoxingIOS/RivalAI.swift).

---

## 5. "불공정하게 강해졌다"보다 "반복 습관이 읽혔다"는 느낌을 위한 장치

### 실제 구현된 장치

| 장치 | 실제 동작 | 근거 |
| --- | --- | --- |
| 표본 기반 적응도와 상한 | 확정된 표본량에 따라 `0.18...0.75`로 제한, 라운드 번호만으로 증가하지 않음 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `adaptation` |
| 분리된 라운드 숙련도 | 관측 사실은 유지하고 라운드별 판단·이동·습관 대응·연계 활용을 점진적으로 증가 | [PixelBoxingIOS/RivalAI.swift](PixelBoxingIOS/RivalAI.swift)의 `RivalDifficulty` |
| 가중 무작위 선택 | 가장 높은 행동만 고정 실행하지 않고 가중치 합에서 난수를 뽑아 선택 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `weightedChoice` |
| 동일 전투 제약 | RIVAL의 펀치는 `startAttack`을 사용하며 스태미나, 경직, 탈진 규칙을 적용; 회피도 스태미나를 소비 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `startAttack`, `performEnemyDecision` |
| 완료 라운드 습관 확정 | 승패와 무관하게 기존 표본의 82%와 완료 라운드 표본을 병합 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `incorporateRound`, `finishRound` |
| 패배 시 진행 정지 | 라운드는 플레이어 승리일 때만 증가하며, 패배·무승부 후에는 현재 라운드를 다시 시작 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `advancesRoundAfterBreak`, `requestNextRound` |
| 코너 리포트 | 확정 습관의 전술 읽기를 짧은 복싱 언어로 표시하며 학습도 %는 표시하지 않음 | [PixelBoxingIOS/GameView.swift](PixelBoxingIOS/GameView.swift)의 `roundResultOverlay` |
| 라운드 통계 표시 | 양측의 회피 성공 횟수와 주요 공격을 표시 | [PixelBoxingIOS/GameView.swift](PixelBoxingIOS/GameView.swift)의 `roundStatColumn` 호출 |
| 학습 초기화 | 확인 후 습관·양측 공격 결과의 두 저장 키와 현재 점수를 지우고 ROUND 1부터 시작; 최고 라운드·승수·보상은 유지 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `resetLearning`, [PixelBoxingIOS/GameView.swift](PixelBoxingIOS/GameView.swift)의 `LearningResetConfirmView` |

완료 라운드 확정의 회귀 테스트가 소스에 존재한다. 이번 문서 대조에서 이를 새로 실행한
것은 아니다. 과거의 패배 롤백 설명과 해당 테스트 이름은
현재 구현에서 유효하지 않으므로 현행 근거로 사용하지 않는다.

근거: [PixelBoxingIOSTests/PlaceholderTests.swift](PixelBoxingIOSTests/PlaceholderTests.swift)의
`testPlayerLossPromotesRoundHabitLearning`, `testEveryCompletedRoundPromotesPersistentHabits`,
기존 테스트의 이름만으로 현재 라운드 시작의 전술 읽기가 비워진다고 주장하지 않는다.

### 확인되지 않은 효과와 현재의 한계

다음은 코드에서 확인되지 않았으므로 주장하지 않는다.

- 위 장치가 실제 모든 플레이어에게 공정하다고 느껴졌다는 사용자 연구 또는 플레이테스트 결과
- 플레이어가 매번 정확히 어떤 습관 때문에 RIVAL의 특정 행동이 나왔는지 이해한다는 증거
- 규칙·통계 방식이 강화학습 방식보다 난이도 밸런스가 우수하다는 비교 실험 결과

현재 코너 리포트는 감지된 습관과 대응 방향을 설명하지만, 방금 선택된 특정 행동의
원인을 증명하는 실행 로그는 아니다. 실전에서는 AI 수치·분석 알림 대신 복싱 행동을
보여주고, 결과 화면에서 전술 읽기와 라운드 통계를 확인한다.

따라서 실제 구현이 뒷받침하는 가장 정확한 표현은 다음과 같다.

> 일반 RIVAL은 기본 공격력·체력 대신 확정된 반복 습관·공격 결과와 라운드별 숙련도로 대응한다.
> 라운드 중 난도·학습모델은 고정하고 승패와 무관하게 종료 후 기억해 다음 대결부터 반영한다.
> 코너 리포트는 확정 습관의 전술 방향을 확인하며, 스토리 상대의 별도 수치·정책은 구분한다.

---

## 과거 실행 검증 결과 요약

아래는 기존 감사에 기록된 날짜별 결과이며 2026-10-12의 새 실행 결과가 아니다.
현재 1.2(6)의 모든 변경에 대한 테스트·실기기 검증 완료를 의미하지 않는다.

- 2026-09-07 iOS: iPhone 12 mini 단위 테스트 61개 및 메뉴·조작부·KO·동작 줄이기 UI 테스트 4개 통과.
- 2026-09-07 검증에는 판정 이벤트, KO 결과 공개 순서, 기존 기록 디코딩과 화면 전환 시 입력 해제를 포함한다.
- 아래 Python/C++ 항목은 기존 날짜의 기록이다. 이번 iOS 연출 변경의 성능 근거로 전용하지 않는다.
- 2026-09-06 실행: `.venv/bin/python -m unittest tests.test_pixel_boxing_core -q`
- 결과: `Ran 35 tests ... OK`
- 이후 2026-09-09·2026-09-10 iOS AI 봇·모션·위빙 수치 검사와 iPhone SDK 컴파일 기록은 [README](README.md#과거-실행-검증-기록)를 따른다. 해당 기록을 현재 사거리·선수 간격·위빙 변경의 새 검증 근거로 사용하지 않는다.
- 확인 범위: Python의 17개 행동 마스킹, 보상 이벤트, 렌더링 없는 에피소드 실행을 포함한 전투 코어 회귀 테스트
- 2026-09-06 감사의 제한: 당시 VS Code CMake Tools의 테스트 검색에서는 실행 가능한 CTest 이름이 발견되지 않았다. 초기 C++ Q-learning은 당시 코드, Git 이력, 로컬 `game_save.txt` 산출물, 과거 세션 기록을 근거로 삼았으며, 역사적 커밋을 새로 빌드해 당시 런타임을 재현하지는 않았다.
