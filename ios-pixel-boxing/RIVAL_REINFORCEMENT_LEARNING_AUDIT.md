# RIVAL 강화학습 구현 및 최종 적응형 AI 검증 기록

> 검증일: 2026-09-06
> 범위: 현재 작업 트리 코드·문서, Git 이력, VS Code 로컬 작업 기록
> 원칙: 확인되지 않은 개발 동기, 성능 결과, 사용자 체감 결과는 사실로 단정하지 않는다.

## 결론

RIVAL의 강화학습은 한 단계의 단일 구현이 아니었다.

1. 초기 C++ TUI에는 실제 온라인 Q-learning 코드, Q-table 저장, 전투 루프 연결이 구현됐다.
2. 이후 Python Pixel Boxing 코어에는 17개 행동, 관측 상태, 보상 이벤트, 렌더링 없는 시뮬레이터가 구현됐지만 정책 학습기와 정책 저장/로드는 구현되지 않았다.
3. 현재 iOS RIVAL은 Q-table, 신경망, 보상 기반 정책 갱신을 사용하지 않는다. 플레이어 행동 통계를 `HabitMemory`에 누적하고, 사전에 작성된 규칙으로 RIVAL 행동의 가중 확률을 바꾸는 적응형 AI다.

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
- 현재 iOS AI: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift), [PixelBoxingIOSTests/PlaceholderTests.swift](PixelBoxingIOSTests/PlaceholderTests.swift), [AI_USAGE.md](AI_USAGE.md), [PixelBoxingIOS/GameView.swift](PixelBoxingIOS/GameView.swift)
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

근거: [../docs/PIXEL_BOXING_GAME_DESIGN.md](../docs/PIXEL_BOXING_GAME_DESIGN.md)의 10.1~10.5절 및 18절 3단계, [../docs/PROJECT_OVERVIEW.md](../docs/PROJECT_OVERVIEW.md)의 `Current Constraints`.

### 1-4. 최종 iOS 앱: 강화학습이 아닌 규칙·통계 기반 적응

현재 iOS `CombatCore.swift`에는 Q-table, 보상 기반 정책 갱신, DQN, 신경망 모델 또는 학습된 정책 파일을 읽는 코드가 없다.

[AI_USAGE.md](AI_USAGE.md)는 이를 다음처럼 명시한다.

> 현재 iOS 빌드는 신경망을 학습하거나 보상으로 정책을 갱신하는 강화학습 모델이 아닙니다. 행동 규칙과 가중치가 소스 코드에 명시된 설명 가능한 적응형 시스템입니다.

따라서 iOS에서는 플레이 중 바뀌는 값이 Q값이나 모델 가중치가 아니라, 플레이어의 누적 행동 비율과 그 비율에 의해 계산되는 행동 선택 확률이다.

---

## 2. 최종 iOS에서 강화학습을 사용하지 않은 이유

### 사유에 대한 결론

코드와 동시대 작업 기록만으로 "강화학습을 쓰지 않게 된 단 하나의 가장 직접적인 이유"를 확정할 수는 없다.

다만 현재 문서에는 선택 기준과 온라인 학습의 위험이 명시돼 있다. [../docs/RIVAL_PORTFOLIO.typ](../docs/RIVAL_PORTFOLIO.typ)는 2026-09-02에 만든 현재 미추적 포트폴리오 원본이므로, 과거 결정 당시의 불변 기록이 아니라 사후에 문서화한 제품 선택 기준으로 취급한다.

| 후보 이유 | 판정 | 확인된 사실 | 근거 |
| --- | --- | --- | --- |
| 학습 데이터 부족 | 미확인 | 데이터가 부족했다는 직접 진술이나 측정 기록을 찾지 못했다. | 코드·문서·검색한 과거 기록 |
| 행동 결과의 예측 어려움 | 제한적으로 확인 | 설계 문서는 플레이 중 온라인 학습을 정책 붕괴와 난이도 불안정을 막기 위해 기본 비활성화한다고 명시한다. 이것만으로 iOS 미채택의 단일 원인이라고 단정할 수는 없다. | [../docs/PIXEL_BOXING_GAME_DESIGN.md](../docs/PIXEL_BOXING_GAME_DESIGN.md)의 10.5절 |
| 디버깅 어려움 | 부분 확인 | 포트폴리오 원본은 "디버깅 가능성"을 우선했다고 적는다. 실제로 "어려워서 포기했다"는 동시대 기록은 찾지 못했다. | [../docs/RIVAL_PORTFOLIO.typ](../docs/RIVAL_PORTFOLIO.typ) |
| 밸런스 조정 어려움 | 미확인 | "플레이 감각의 직접 조정"은 우선순위로 적혀 있으나, 밸런스 조정이 불가능하거나 어려웠다는 직접 근거는 없다. | [../docs/RIVAL_PORTFOLIO.typ](../docs/RIVAL_PORTFOLIO.typ) |
| iPhone 성능 | 미확인 | 성능 제약이 RL 미채택 원인이라는 코드·문서·세션 근거를 찾지 못했다. | 코드·문서·검색한 과거 기록 |
| 앱 크기 | 선택 기준으로 확인 | 작은 앱 크기를 초기 제품의 우선순위로 문서화했다. 그러나 이것만으로 결정적 원인이라고는 단정할 수 없다. | [../docs/RIVAL_PORTFOLIO.typ](../docs/RIVAL_PORTFOLIO.typ) |
| 오프라인 제약 | 선택 기준으로 확인 | 오프라인 동작을 우선했고, 현재 앱은 서버·외부 AI API·클라우드 동기화 없이 동작한다. | [../docs/RIVAL_PORTFOLIO.typ](../docs/RIVAL_PORTFOLIO.typ), [AI_USAGE.md](AI_USAGE.md) |
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
- 온디바이스·오프라인 동작: 습관 데이터는 `UserDefaults` JSON으로 저장되며 외부 서버로 전송하지 않는다.
- 작은 런타임 의존성: iOS 앱에는 훈련된 외부 모델 파일이나 외부 AI API가 없다.
- 회귀 테스트 가능성: 가드 비율이 높으면 바디샷 가중치가 커지는지, 패배 라운드의 습관이 롤백되는지 테스트할 수 있다.

근거: [AI_USAGE.md](AI_USAGE.md), [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift), [PixelBoxingIOSTests/PlaceholderTests.swift](PixelBoxingIOSTests/PlaceholderTests.swift).

"얻은 것"은 기능과 문서화된 선택 기준을 뜻한다. 실제 사용자 만족도나 난이도 품질이 더 좋아졌다는 비교 실험 결과는 확인하지 못했다.

---

## 4. 최종 iOS AI가 기록하는 행동과 바꾸는 가중치

### 4-1. 기록하는 행동

`HabitMemory`는 다음 데이터를 누적한다.

| 기록 | 수집 방식 | 파생 값 |
| --- | --- | --- |
| 8종 공격별 횟수 | 실제 공격 시작이 성공했을 때 증가 | 최다 공격, 잽 비율, 바디 비율 |
| 최근 공격과 연속 횟수 | 공격 시작 시 갱신 | `repeatStreak` |
| 가드 유지 | 프레임 시간 표본 | `guardRatio` |
| 왼쪽·오른쪽 더킹 | 프레임 시간 표본 | `duckLeftRatio`, `duckRightRatio` |
| 백스텝 | 무적 시간 상태를 프레임 표본화 | `backstepRatio` |
| 전진·후퇴 | 플레이어의 전후 이동 축을 프레임 표본화 | `pressureRatio`, `retreatRatio` |
| 전체 표본량 | 모든 프레임 표본의 누적 | `sampleStrength` |

공격은 "명중했을 때"가 아니라 "실제로 공격 시작에 성공했을 때" 기록된다. 스태미나 부족이나 경직으로 시작하지 못한 입력은 기록되지 않는다.

근거: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `HabitMemory.noteAttack`, `HabitMemory.sample`, `CombatEngine.startAttack`, `CombatEngine.sampleHabits`; [AI_USAGE.md](AI_USAGE.md)의 "플레이 습관 수집".

### 4-2. 적응도

```text
adaptation = clamp(
    0.18 + 0.16 * (round - 1) + 0.58 * sampleStrength,
    0.18,
    1.0
)
```

- `sampleStrength = min(1, totalSamples / 18)`
- 적응도는 `0.18` 아래로 내려가지 않고 `1.0`을 넘지 않는다.
- 이 값은 습관 대응 가중치, 적의 접근 속도, 적의 판단 간격에 사용된다.

근거: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `HabitSnapshot.adaptation`, `CombatEngine.updateEnemy`.

### 4-3. RIVAL이 선택하는 행동

현재 가중치 선택 후보는 계획된 17개 행동과 다르다.

- 8종 펀치
- `dodge_left`, `dodge_right`, `dodge_back`
- `wait`

`approach`은 가중치 후보가 아니라, 플레이어와의 거리가 `86`보다 멀 때 별도 이동 로직으로 실행된다. 적은 가드 행동을 이 가중치 목록에서 선택하지 않는다.

근거: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `HabitSnapshot.enemyWeights`, `CombatEngine.updateEnemy`, `CombatEngine.performEnemyDecision`.

### 4-4. 거리와 습관이 바꾸는 가중치

기본 가중치에 거리 규칙과 습관 대응 규칙을 더한 뒤, `weightedChoice()`가 가중 무작위로 하나를 선택한다.

| 관찰 조건 | RIVAL의 가중치 변화 |
| --- | --- |
| 거리 `> 115` | 잽 `+1.55`, 크로스 `+0.45` |
| 거리 `78...115` | 잽·크로스·훅·좌우 더킹 증가 |
| 거리 `<= 78` | 좌우 바디·훅·어퍼컷·백스텝 증가 |
| 가드 비율 `> 0.22` | 좌·우 바디샷에 각각 `0.95a`, `1.20a` 추가 |
| 오른쪽 더킹 비율 `> 0.16` | 크로스·오른쪽 훅·오른쪽 어퍼컷 증가 |
| 왼쪽 더킹 비율 `> 0.16` | 잽·왼쪽 훅·왼쪽 어퍼컷 증가 |
| 잽 비율 `> 0.34` 또는 최다 공격이 잽 | 크로스·오른쪽 훅·오른쪽 더킹 증가 |
| 바디 비율 `> 0.30` | 좌·우 어퍼컷 증가 |
| 전진 압박 비율 `> 0.20` | 백스텝·좌우 훅 증가 |
| 백스텝 비율 `> 0.14` 또는 후퇴 비율 `> 0.18` | 잽·크로스 증가, 대기 가중치 `0.8`배 |
| 같은 공격을 3회 이상 반복 | 좌·우 더킹에 각각 `0.35a` 추가 |
| 플레이어 노출 상태 | 크로스 `+1.8`, 오른쪽 어퍼컷 `+1.4`, 오른쪽 훅 `+0.9`, 대기 `0.05` |

여기서 `a`는 위 적응도다. 플레이어 노출 상태에 대한 마지막 행은 적응도를 곱하지 않는 고정 보정이다.

근거: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `HabitSnapshot.enemyWeights`.

### 4-5. 가중치 외에 실제로 달라지는 적 행동

```text
enemySpeed = 46 + 22 * adaptation
decisionInterval = max(0.18, 0.68 - 0.28 * adaptation) + random(0...0.18)
```

즉 현재 iOS의 적응은 단순히 공격 종류만 바꾸는 것이 아니다. 멀리 있을 때의 접근 속도와 다음 행동을 결정하는 간격도 적응도에 따라 바뀐다.

근거: [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `CombatEngine.updateEnemy`.

---

## 5. "불공정하게 강해졌다"보다 "반복 습관이 읽혔다"는 느낌을 위한 장치

### 실제 구현된 장치

| 장치 | 실제 동작 | 근거 |
| --- | --- | --- |
| 낮은 초기 적응도와 상한 | ROUND 1과 적은 표본에서 적응도는 최소 `0.18`; 최대 `1.0`으로 제한 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `adaptation` |
| 가중 무작위 선택 | 가장 높은 행동만 고정 실행하지 않고 가중치 합에서 난수를 뽑아 선택 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `weightedChoice` |
| 동일 전투 제약 | RIVAL의 펀치는 `startAttack`을 사용하며 스태미나, 경직, 탈진 규칙을 적용; 회피도 스태미나를 소비 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `startAttack`, `performEnemyDecision` |
| 패배 라운드 롤백 | 플레이어 패배 시 해당 라운드에서 새로 쌓인 `habits`를 라운드 시작 스냅샷으로 되돌림 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `roundStartHabits`, `finishRound` |
| 패배 시 진행 정지 | 라운드는 플레이어 승리일 때만 증가하며, 패배·무승부 후에는 현재 라운드를 다시 시작 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `advancesRoundAfterBreak`, `requestNextRound` |
| 학습도 표시 | 라운드 결과 화면에 `RIVAL 학습도 n%`를 표시 | [PixelBoxingIOS/GameView.swift](PixelBoxingIOS/GameView.swift)의 `roundResultOverlay` |
| 라운드 통계 표시 | 양측의 회피 성공 횟수와 주요 공격을 표시 | [PixelBoxingIOS/GameView.swift](PixelBoxingIOS/GameView.swift)의 `roundStatColumn` 호출 |
| 학습 초기화 | 확인 후 습관·현재 점수를 지우고 ROUND 1부터 시작 | [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift)의 `resetLearning`, [PixelBoxingIOS/GameView.swift](PixelBoxingIOS/GameView.swift)의 `LearningResetConfirmView` |
| 롤백 메시지 | 플레이어 패배 문구는 `ROUND LOST - RIVAL 학습 롤백`으로 현지화돼 있음 | [PixelBoxingIOS/Localization.swift](PixelBoxingIOS/Localization.swift)의 `roundLostMessage` |

패배 라운드 롤백은 XCTest로도 확인된다. 테스트는 공격 습관을 기록한 뒤 패배 처리하면 해당 공격 횟수가 라운드 시작 값으로 돌아가는지 검증한다.

근거: [PixelBoxingIOSTests/PlaceholderTests.swift](PixelBoxingIOSTests/PlaceholderTests.swift)의 `testPlayerLossRollsBackRoundHabitLearning`, `testLearningResetBecomesLossRollbackBaseline`.

### 확인되지 않은 효과와 현재의 한계

다음은 코드에서 확인되지 않았으므로 주장하지 않는다.

- 위 장치가 실제 모든 플레이어에게 공정하다고 느껴졌다는 사용자 연구 또는 플레이테스트 결과
- 플레이어가 매번 정확히 어떤 습관 때문에 RIVAL의 특정 행동이 나왔는지 이해한다는 증거
- 규칙·통계 방식이 강화학습 방식보다 난이도 밸런스가 우수하다는 비교 실험 결과

특히 현재 UI에는 "잽 반복을 감지해 크로스를 선택했다"처럼 개별 습관과 대응 규칙의 인과관계를 실시간으로 설명하는 기능은 확인되지 않는다. 화면이 보여 주는 것은 RIVAL 학습도 비율과 라운드 결과 통계다.

따라서 실제 구현이 뒷받침하는 가장 정확한 표현은 다음과 같다.

> RIVAL은 공격력이나 체력을 임의로 올리는 대신, 플레이어의 반복 공격·방어·이동 습관을 기록해 대응 행동의 출현 확률과 판단 빈도를 점차 조정한다. 패배 라운드의 신규 습관은 롤백되고, 학습도와 전투 통계는 화면에 표시되지만, 개별 대응의 이유를 직접 해설하는 기능은 현재 없다.

---

## 검증 결과 요약

- 2026-09-06 실행: `.venv/bin/python -m unittest tests.test_pixel_boxing_core -q`
- 결과: `Ran 35 tests ... OK`
- 확인 범위: Python의 17개 행동 마스킹, 보상 이벤트, 렌더링 없는 에피소드 실행을 포함한 전투 코어 회귀 테스트
- 제한: 현재 VS Code CMake Tools의 테스트 검색에서는 실행 가능한 CTest 이름이 발견되지 않았다. 이 감사는 초기 C++ Q-learning에 대해 현재 코드, Git 이력, 로컬 `game_save.txt` 산출물, 과거 세션 기록을 근거로 삼으며, 역사적 커밋을 새로 빌드해 당시 런타임을 재현하지는 않았다.
