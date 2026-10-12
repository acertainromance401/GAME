# RIVAL iOS

> 플레이어의 반복 습관을 학습해 점점 대응 방식을 바꾸는 `RIVAL`과 겨루는 iPhone 가로형 3D 복싱 게임입니다.

출시 중인 1.1 유료 앱과 구분되는 1.2 업데이트 작업 트리입니다. 기존 Bundle Identifier·저장 키·스타일 식별자는
업데이트에서도 유지합니다. 구현 기준은 [게임 의도와 설계 철학](../docs/product/RIVAL_GAME_INTENT_AND_DESIGN_PHILOSOPHY.md)이며,
과거 제출 PDF와 현재 소스의 변경 사항을 구분합니다.

## 현재 문서 기준

- **대상:** RIVAL 1.2(6) 작업 트리 · 마케팅 버전 `1.2`, 빌드 번호 `6`
- **기준일:** 2026-10-12 · 현재 소스·설정과 보존된 제출·홍보 기록 대조
- **플랫폼:** iPhone·iPad 가로 전용 · iOS 17 이상 · Swift 6 · SwiftUI/SceneKit
- **설정:** 실제 프로젝트 [RIVAL.xcodeproj/project.pbxproj](RIVAL.xcodeproj/project.pbxproj)와 [project.yml](project.yml) · 기존 Bundle Identifier `com.acertainromance401.pixelboxing` 유지
- **범위:** 현재 작업 트리의 구현 설명이며, 같은 버전의 기존 아카이브·스토어 배포본과 동일함을 보장하지 않습니다.
- **검증:** 날짜별 실행 기록은 당시 범위에 한정됩니다. 이번 문서 정리에서 빌드·테스트·실기기 실행이나 배포 조회를 새로 수행하지 않았습니다.

## 1.2 진행 상태

- 2026-10-11 `1.2(6)` 앱·Story 비소모성 상품·Total Wins 순위표를 함께 제출했고, 당시 상태는 `Waiting for Review`였습니다. 수동 출시를 유지합니다. [제출 기록](AppStoreMetadata/1.2-submission.json)과 [릴리스 체크리스트](../docs/release/RELEASE_READINESS_CHECKLIST.md)를 따르며 현재 승인 상태를 새로 조회한 것은 아닙니다.
- 무료 RIVAL·체육관과 선택적 유료 스토리를 분리하는 업데이트입니다. 10월 12일 확인한 공개 앱은 여전히 유료 `1.1`이며, 무료 가격 전환·1.2 출시는 완료로 기록하지 않습니다.
- 스토리는 압박형 → 견제형 → 카운터형 → 강타형 → RIVAL 순서입니다. 구매는 이용권·퍼스트 벨 시작 복장을 해금하고, 상대 외형·챔피언 복장·벨트에는 이용권과 해당 승리 기록이 모두 필요합니다.
- 기존 유료 구매자 권한은 검증된 Production 원본 빌드 `1...4`에 한정합니다. 무료 전환과 버전 배포 시차에 따른 경계, 실계정 구매·복원·권한 취소·Game Center 제출은 별도 확인 사항입니다.
- Debug 전체 스토리 체험은 별도 저장소를 사용하고 실제 통계·장비·랭킹 저장을 막습니다. Release에는 해금 우회가 없으며, 구매 검증에는 Debug 체험을 비활성화해야 합니다.
- Release UI 캡처 6개·첨부 30장 확인은 10월 11일의 제한된 로컬 StoreKitTest 결과입니다. 전체 회귀·실결제 검증이 아닙니다. 10월 12일에는 격리된 Debug 엔진으로 홍보 장면을 캡처했습니다.
- [홍보 영상·게시 기록](PromotionVideos/README.md)에 24초 가로·세로 영상, 음악 라이선스, Reddit·Instagram 게시와 광고 심사 요청을 구분해 보관합니다. 광고 게재·성과는 미확인입니다.

## 제출 문서

- **게임 소개 및 설명:** [현재 Markdown 원본](../docs/product/GAME_GUIDE.md)
- **AI 활용 기술:** [현재 Markdown 원본](../docs/engineering/AI_USAGE.md)
- **강화학습 이력과 현재 AI 구분:** [감사 문서](../docs/engineering/RIVAL_REINFORCEMENT_LEARNING_AUDIT.md)
- **개발 고민과 문제 해결:** [상세 기록](../docs/engineering/DEVELOPMENT_ISSUES_AND_SOLUTIONS.md) · 2026-10-12, 당시 해결 이력과 현재 코드·검증 수준 구분

과거 제출 PDF는 현재 Markdown과 별도 산출물입니다. 이번 정리에서는 PDF를 재생성하지 않았습니다.

## 개발 설명

`legacy/python/pixel_boxing/pixel_boxing_topdown.py`와 `boxing_core.py`를 기준으로 만든 네이티브 iPhone 가로 화면 버전입니다. iOS는 Tkinter와 Python `.py` 창을 직접 앱 번들로 실행할 수 없으므로, 동일 저장소 안에서 전투 규칙과 행동 패턴 AI를 Swift로 이식하고 화면은 SceneKit 기반 실제 3D 씬으로 재구성했습니다.

## 포함 기능

- 8종 공격의 피해·타이밍·기본 비용과 방향 더킹 매핑, 현재 iOS 사거리·스타일 보정
- JAB/CROSS 두 공격 버튼과 가드·L 더킹·R 더킹 홀드 조합
- 이동 패드 위쪽 좌우의 1회 위빙, 작은 측면 이동과 같은 쪽 훅 연계
- 가드, 백스텝, 헛스윙 노출, 카운터, 반복 기술 약화와 탈진
- 45초 일반 경기와 승리 때만 증가하는 라운드, 완료 라운드의 습관·공격 결과 기반 적응형 AI
- 한 라운드 안에서는 학습 정책을 고정하고 관측만 수집하며, 종료 시 병합·저장해 다음 라운드부터 반영
- 5명 상대의 스토리, 관장 공략·인트로·승리 컷씬·엔딩, 체크포인트 이어하기와 획득 보상 다시 보기
- `UserDefaults`에 유지되는 플레이어 행동 패턴 메모리
- 높이와 깊이를 가진 링, 3단 로프, 코너 포스트, 객석과 4점 조명
- 승인된 복서 실루엣과 주먹·엄지·커프·손목 스트랩으로 구성된 글러브
- 전완이 커프 입구에 연결되고 팔 방향을 따라 회전하는 글러브 접합
- 카메라를 향해 회전하는 머리 위 `ME`·`RIVAL` 식별 라벨
- 캡슐·구·박스 관절로 구성한 8종 공격·피격·KO 모션
- 상대를 바라보는 전후·좌우 이동축, 전진·횡이동의 기본 속도 210과 스타일 배율, 스타일 보너스 없는 후퇴 0.5배
- 복서 중심 간 최소 거리 34를 유지하는 충돌 제약과 목표 표면 반경을 포함한 공격 판정
- 공격별 체중 이동, 타격 손 강조와 모션 트레일, 보간형 좌우 더킹
- 조합 공격 도중 버튼을 놓으면 공격 종료 후 가드·더킹 자세가 자동 해제되는 홀드 입력 동기화
- 판정 이벤트 기반 소리·햅틱·시그니처 표시와 타격 중요도별 카메라 임펄스
- 4단계 플레이어 더킹 등급, 0.18/0.28/0.60/0.80초 카운터 입력 창
- Accurate/Perfect 회피 순간의 슬로모션·줌, KO 낙하를 가리지 않는 결과 공개
- 실전 카메라·플래시·잔상·버튼의 동작 줄이기 지원과 무광 공용 패널
- 성공 더킹 뒤 바디샷·훅 카운터 보너스 피해량을 숫자로 보여주는 해설
- 플레이어 공격 성향에 따라 좌우 더킹과 백스텝을 실제로 실행하는 RIVAL
- 공격 기술, 적중, 가드, 더킹, 헛스윙, 카운터와 KO를 설명하는 경기 해설 HUD
- 선수 간 거리에 따라 초점과 줌이 변하는 플레이어 어깨너머 카메라
- 월드 업축, 최단 회전, 회전 속도 제한과 근접 반전 방지를 적용한 탑다운 카메라
- iPhone 가로 화면 전용 SwiftUI 터치 조작
- 가로 safe area에 추가 여백을 둔 56×50 이동 버튼과 불투명 조작부 표면
- 메인 메뉴 → 건너뛸 수 있는 VS 연출 → 실전, 체육관에서 조합 연습
- 메뉴 전용 라이벌 근접 초상·독립 대기 모션, 응축형 타이포와 아이보리 경기 버튼, 실제 승수·연승 기록
- 같은 차콜 디자인의 전체 화면 대기실·랭킹, 작은 설정·초기화 패널과 공용 조작부
- 기존 판정 시간에 맞춘 잽·크로스의 하체/상체 모션, 머리·바디·가드별 피격 반응과 짧은 비발광 접촉 표시
- 학습 메모리와 점수를 삭제하고 ROUND 1부터 재시작함을 알리는 초기화 확인 팝업
- VoiceOver 레이블과 햅틱 피드백

3D 지오메트리는 외부 유료 에셋 없이 소스에서 생성합니다. 매 프레임 노드를 다시 만들지 않고 생성한 링·관중·복서 노드를 유지한 채 관절 자세와 카메라만 갱신합니다.

## 터치 공격 조합

| 홀드 입력 | JAB | CROSS |
| --- | --- | --- |
| 없음 | 잽 | 크로스 |
| 중앙 가드 | 왼쪽 어퍼컷 | 오른쪽 어퍼컷 |
| L 더킹 | 왼쪽 바디 | 오른쪽 훅 |
| R 더킹 | 왼쪽 훅 | 오른쪽 바디 |

이 조합은 데스크톱 버전의 `W/Q/E + A/D` 입력 규칙과 같습니다. 가드는 이동 패드 중앙,
더킹은 양옆 아래에 유지하며 공격 버튼에는 선택된 조합명이 표시됩니다. 공격은 터치
시작에 한 번 입력됩니다. 겹쳐 누른 더킹을 놓으면 아직 누르고 있는 방향으로 복귀합니다.

JAB/CROSS 버튼 위의 `BACKSTEP`은 기본 비용 31에 스타일 배율을 적용해 상대 반대 방향으로
0.22초 동작 중 0.18초에 걸쳐 최대 34만큼 이동하며, 0.035–0.18초에 회피가 적용됩니다. 인파이터·슬러거의 비용은 31,
아웃복싱은 18.6입니다. 필요한 비용보다 스태미나가 적거나 공격·피격 경직·탈진 중이면 사용할 수 없습니다.

### 위빙과 훅

- 이동 패드 왼쪽 위의 **L 위빙 → JAB**은 왼훅, 오른쪽 위의 **R 위빙 → CROSS**는 오른훅입니다.
  기존 더킹 조합과 버튼 크기·배치는 유지합니다. 위빙은 한 번 누르면 한 번만 실행되며 홀드 자동반복은 없습니다.
- 실전 비용 9, 동작 0.36초, 재시작 대기 총 0.48초입니다. 회피 진입부터 0.23초까지 최대 12 게임 단위
  측면 이동하며 링·상대 충돌 경계를 따릅니다. 체육관은 위빙·연계 훅도 무료입니다.
- 머리 공격을 맞는 방향에서 충분히 숙인 뒤 0.27초 전까지 피합니다. 바디·잘못된 방향·공격 중에는
  위빙 회피가 적용되지 않습니다. 별도 무적이나 위빙 전용 피해 보너스는 없으며,
  실제 회피 성공은 더킹과 같은 등급·카운터·상위 등급 RIVAL MOMENT 경로를 사용합니다.
- 같은 쪽 공격을 미리 누르면 0.23초 이후 훅으로 이어지고, 종료 후 0.12초까지 입력 유예가 있습니다.
  피격·탈진·일시정지·화면 이탈·라운드 종료는 예약을 취소합니다. 훅 자체는 기존 비용·피해·판정 시간을 씁니다.
- 더킹은 무릎·고관절 하강과 방향성 몸통 회전, 전방 숙임을 연결하며 장갑은 실제 턱을 따라갑니다.
  위빙 훅은 낮은 진입 자세를 접촉까지 유지하고, 바디샷은 낮게 준비해 복부로 상승하는 짧은 어퍼컷 궤적입니다.

## 공격 데미지와 가드 비용

| 기술 | 기본 체력 데미지 | 가드 체력 데미지 | 가드 스태미나 소모 | 기본 사거리 |
| --- | ---: | ---: | ---: | ---: |
| 잽 | 6 | 2 | 5.4 | 44 |
| 크로스 | 11 | 4 | 9.9 | 38 |
| 왼쪽 바디 | 9 | 4 | 8.1 | 29 |
| 오른쪽 바디 | 10 | 4 | 9.0 | 30 |
| 왼쪽 훅 | 11 | 4 | 9.9 | 26 |
| 오른쪽 훅 | 12 | 5 | 10.8 | 27 |
| 왼쪽 어퍼컷 | 13 | 5 | 11.7 | 25 |
| 오른쪽 어퍼컷 | 14 | 6 | 12.6 | 26 |

표의 피해와 가드 비용은 스타일·카운터·반복 공격 보정 전 기준값입니다. 가드 체력
데미지는 기본 데미지의 40%를 반올림하며 최소 1입니다. 가드 스태미나 소모는 기본
데미지의 90%에 방어자 가드 스태미나 배율을 곱하고 최소 5를 적용합니다. 가드 HP 피해에는
공격자 피해·반복·노출 보정과 방어자 가드 HP 배율이 적용되지만, 가드 스태미나 피해에는
공격자 피해·반복·노출 보정이 적용되지 않습니다.
일반 가드 중에는 스태미나가 회복되지 않고, 스태미나가 0이 되면 가드가 깨지면서 탈진과 노출이
발생합니다. 헛스윙 노출 상태에서 맞으면 피해가 1.4배가 되며 바디와 훅은 추가로 1.2배가
적용됩니다. 같은 기술을 세 번째부터 반복하면 피해에 0.85배를 누적 적용하고 최저 50%까지 내려갑니다.
스토리 강타형의 회복 단계만 최대 2초 가드·초당 6 회복을 사용하며, 이후 가드 없이
초당 16.5로 목표 45까지 회복합니다. 플레이어·다른 상대의 일반 가드 규칙과 구분합니다.

기본 사거리는 게임 단위의 선수 중심→장갑 중심 거리입니다. 실제 선수 중심 간 적중 한계는
`기본 사거리 × 스타일 리치 배율 + 14 + 0.34 / 0.025`입니다. 추가 14는 모든 공격에 공통인
리치 확장이며, 표면 반경 0.34는 렌더링 단위에서 게임 단위 13.6으로 환산합니다.
이 값은 거리 후보 한계이며, 활성 구간의 실제 공유 포즈·장갑 궤적 접촉도 필요합니다.
공격 방향·조준점은 시작 때 고정하고 접촉 시각의 방어 상태를 적용합니다.
스타일별 배율과 체육관 샌드백 판정은 [게임 가이드](../docs/product/GAME_GUIDE.md#26-8종-공격의-실제-전투-수치)를 따릅니다.

## 라운드 판정과 AI 난이도

- 제한시간 종료 시 플레이어 HP가 더 높으면 승리, 더 낮으면 패배입니다.
- 양쪽 HP가 정확히 같으면 무승부입니다.
- 플레이어가 승리했을 때만 라운드 숫자가 증가합니다. 관측 표본 기반 적응 계수와 별도로
  라운드별 숙련도가 판단 간격·습관 대응·풋워크·짧은 연계에 반영됩니다. 체력·피해·사거리는 유지합니다.
- 무승부와 패배 후에는 같은 라운드 숫자로 재경기합니다.
- 승패와 무관하게 모든 완료 라운드의 습관을 장기 프로필에 병합합니다.
- 전술 읽기는 이전 완료 라운드의 확정 습관에서 정하고 결과에서 코너 리포트를 제공합니다.
- 사거리·스태미나 조건으로 행동 후보를 걸러내고 읽기에 맞는 목표 거리로 계속 이동합니다.
  현재 거리·스태미나·보이는 공격에는 고정 규칙으로 반응하지만 경기 중 수집한 통계로 학습 정책을 재평가하지 않습니다.

## 구조

- [PixelBoxingIOS/CombatCore.swift](PixelBoxingIOS/CombatCore.swift): 전투 규칙, 습관 수집과 적응형 행동 선택
- [PixelBoxingIOS/RivalAI.swift](PixelBoxingIOS/RivalAI.swift): 라운드별 실행 숙련도, 연계와 시드 난수
- [PixelBoxingIOS/CombatInput.swift](PixelBoxingIOS/CombatInput.swift): 홀드 조합 입력 상태
- [PixelBoxingIOS/Weaving.swift](PixelBoxingIOS/Weaving.swift): 위빙 시간·이동·회피와 훅 예약
- [PixelBoxingIOS/FighterPose.swift](PixelBoxingIOS/FighterPose.swift), [PixelBoxingIOS/BoxingMotion.swift](PixelBoxingIOS/BoxingMotion.swift): 관절 자세, 공격 궤적과 고정 길이 IK
- [PixelBoxingIOS/Arena3DScene.swift](PixelBoxingIOS/Arena3DScene.swift): SceneKit 경기장, 관절형 복서, 조명과 카메라
- [PixelBoxingIOS/GameView.swift](PixelBoxingIOS/GameView.swift): 가로형 터치 HUD
- [PixelBoxingIOS/GameController.swift](PixelBoxingIOS/GameController.swift): 화면·전투 모델 연결, 설정과 누적 통계
- [PixelBoxingIOS/CombatPresentation.swift](PixelBoxingIOS/CombatPresentation.swift): 판정 이벤트·시그니처·카메라 강도와 줌 곡선
- `PixelBoxingIOSTests/`: 전투 수치와 AI 회귀 테스트
- `PixelBoxingIOSUITests/`: 가로 조작부 10개, 메뉴→경기, KO→다음 라운드와 동작 줄이기 검사
- [PixelBoxingIOS/StoryMode.swift](PixelBoxingIOS/StoryMode.swift): 스토리 진행·라운드·체크포인트·학습
- [PixelBoxingIOS/StoryPurchaseStore.swift](PixelBoxingIOS/StoryPurchaseStore.swift): StoreKit 권한·복원·기존 구매자 판정
- [PixelBoxingIOS/StoryViews.swift](PixelBoxingIOS/StoryViews.swift): 상대 선택·인트로·컷씬·스토리 HUD
- [project.yml](project.yml): XcodeGen 프로젝트 명세 · RIVAL 1.2(6)

## 과거 실행 검증 기록

아래 결과는 명시된 날짜의 소스와 실행 범위에 대한 기록입니다. 현재 1.2(6) 작업 트리의
모든 변경이 통과했다는 의미는 아닙니다. 현재 사거리·선수 간격·위빙 수치는 위 설명을
따르며, 과거 기록의 수치 검사 통과를 해당 변경의 새 검증으로 해석하지 않습니다.

**2026-09-10 위빙·더킹·바디샷·맵:** 실제 코어의 위빙 XCTest 21개를 macOS에서 실행해
통과했고, 모션 수치 assertion 128,842개와 기존 AI 봇 회귀도 통과했습니다. 재현은
`bash scripts/check_weaving.sh`, `bash scripts/check_motion.sh`, `bash scripts/check_ai_behavior.sh`입니다.
이는 실기기 모션·오입력·프레임 성능 검증을 대신하지 않습니다. 경기장 조명·카메라는 그대로이며,
맵은 캔버스·중앙 마크·코너 디테일·정적 관중석, 체육관 바닥·저상 장비·지지 구조·벽 장식과
체육관 조명/접지 그림자를 개선했습니다. 사우스포는 포함하지 않았습니다.
iPhone SDK `build-for-testing`도 통과했습니다. 원본 경로의 Xcode 프로젝트 읽기 대기는
동일 소스의 임시 로컬 복사본으로 우회했습니다. 이번 버전의 전체 iOS XCTest 실행·
실기기 설치·플레이 확인은 하지 않았습니다.

**2026-09-09 자세·모션 전반:** 준비 자세·골반 선행 로딩·월드 좌표 지지발·방어 전환·
방향성 피격 복귀·접촉 후 강타 시각 펄스를 적용했습니다. 전투 수치와 엔진 시간은
유지합니다. `bash scripts/check_motion.sh`로 실제 모션 소스의 수치 assertion 44,189개를
통과했고 iPhone SDK `build-for-testing`에 성공했습니다. 전체 XCTest 실행과 실기기
설치·플레이는 하지 않았습니다. [구현 범위와 검증 한계](../docs/product/RIVAL_GAME_INTENT_AND_DESIGN_PHILOSOPHY.md#13-2026-09-ios-고도화-현황)를 따릅니다.

**2026-09-09 후반 AI·조작·모션:** 실제 코어의 고정 난수 봇 대전 72개와 관측·입력·방어
모션 수학 검사를 실행했습니다. iPhone SDK 테스트 코드 컴파일을 확인했으며, 이번 변경의
전체 XCTest 실행·실기기 설치·조작감 확인은 하지 않았습니다. 봇 상대 차이는 사람 상대
난이도 검증이 아닙니다. 재현 명령은 `bash scripts/check_ai_behavior.sh`이며 앱 저장소를
사용하지 않습니다. [정본의 상세 결과](../docs/product/RIVAL_GAME_INTENT_AND_DESIGN_PHILOSOPHY.md)를 따릅니다.

2026-09-07 내부 메뉴·잽/크로스·피격까지: iPhone 12 mini 단위 테스트 82개와 UI 테스트 11개 통과. 테스트용 경기와
승수 기록은 실사용 저장소에서 격리됩니다. 시뮬레이터는 이번 검증에 사용하지 않았습니다.
메인 메뉴의 한국어·영어·일본어, 내부 메뉴의 큰 글씨·동작 줄이기·미리보기·모달 차단,
기존 카운터/KO를 포함합니다. 준비/적중/회수 프레임은 진단용 측면 카메라로 실기기에서
렌더링해 확인했습니다. 다른 기종의 실제 화면, 남은 공격 모션과 장시간 성능·손맛은 별도 검증이 필요합니다.

## 빌드 및 배포 안내

시뮬레이터를 실행하지 않고 generic iOS 대상으로 무서명 컴파일할 수 있습니다.
아래는 재현 명령이며 이번 문서 정리에서 실행하지 않았습니다.

```bash
cd ios-pixel-boxing
xcodebuild \
  -project RIVAL.xcodeproj \
  -scheme RIVAL \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

심사에 사용한 실제 Xcode 프로젝트를 함께 보존합니다. `project.yml`은 유지된 명세이며,
XcodeGen 재생성 전 Story JSON 11개·개인정보 매니페스트·UI-test-only StoreKit fixture의
등록과 스킴을 확인해야 합니다. 문서 정리를 위해 프로젝트를 재생성하지 않습니다.

## 배포 직전 원클릭 점검

배포 직전 스크립트는 XcodeGen 재생성과 무서명 generic iOS `build-for-testing`·Release
컴파일을 실행하고, `--device-id`를 지정하면 실기기 `test-without-building`을 시도합니다.
무서명 컴파일만으로 실기기 설치·테스트나 배포가 보장되지는 않으며, 실기기 테스트에는
해당 기기에서 실행 가능한 서명된 테스트 산출물이 별도로 필요합니다.

```bash
cd ios-pixel-boxing
chmod +x scripts/pre_release_check.sh
./scripts/pre_release_check.sh --device-id <UDID>
```

체크 항목 상세는 [RELEASE_READINESS_CHECKLIST.md](../docs/release/RELEASE_READINESS_CHECKLIST.md)를 사용합니다.

## 실제 iPhone 및 TestFlight 배포

실기기용 `.app` 또는 `.ipa`는 Apple 서명이 필요하므로 저장소에서 공용 파일로 미리 생성할 수 없습니다.

1. 정식 앱 업데이트는 기존 `com.acertainromance401.pixelboxing` 식별자와 Team을 유지합니다. 별도 포크에만 다른 식별자를 사용합니다.
2. Xcode의 Signing & Capabilities에서 Team과 자동 서명을 선택합니다.
3. Product > Archive를 실행합니다.
4. Organizer에서 Distribute App > App Store Connect > Upload를 선택합니다.
5. App Store Connect에서 TestFlight 빌드를 심사 계정에 배포합니다.

App Store 제출 전에는 앱 이름, 아이콘, 개인정보 처리방침, 연령 등급, 스크린샷과 Apple Developer 계정 설정을 최종 확인해야 합니다.
