# RIVAL 문서

**플레이 경험에서 구현 근거까지.** 현행 iOS 제품을 먼저 읽고, 제작 자료와 이전 구현은 별도로 살펴볼 수 있도록 구성했습니다.

> 기준: 2026-10-12, 현재 소스 **1.2(6)**. 공개 앱은 같은 날 마지막 확인한 유료 **1.1**입니다.
> App Store Connect의 마지막 확인 기록은 2026-10-11 **Waiting for Review**, 수동 출시입니다. 승인·출시 완료를 뜻하지 않습니다.

[저장소 홈](../README.md#L1) · [폴더 안내](REPOSITORY_LAYOUT.md#L1) · [iOS 구조](engineering/ARCHITECTURE.md#L1) · [보안 제보](../SECURITY.md#L1)

## 제품

게임이 무엇을 지향하고, 플레이어에게 어떤 선택을 제공하는지부터 시작합니다.

| 문서 | 읽을 내용 |
| --- | --- |
| [게임 가이드](product/GAME_GUIDE.md#L1) | 조작, 전투 규칙, 모드와 보상 |
| [제품 의도와 설계 철학](product/RIVAL_GAME_INTENT_AND_DESIGN_PHILOSOPHY.md#L1) | 습관을 읽는 상대, 전략 변화와 피드백의 기준 |

## 개발과 소스

| 문서 | 읽을 내용 |
| --- | --- |
| [아키텍처와 소스 탐색](engineering/ARCHITECTURE.md#L1) | 진입점, 전투 엔진, 스냅샷·이벤트, 화면과 서비스 |
| [AI 구현 안내](engineering/AI_USAGE.md#L1) | 현재 규칙·통계 기반 적응 AI의 동작과 범위 |
| [강화학습 점검](engineering/RIVAL_REINFORCEMENT_LEARNING_AUDIT.md#L1) | 현행 구현과 강화학습 개념의 차이, 향후 과제 |
| [개발 문제와 해결](engineering/DEVELOPMENT_ISSUES_AND_SOLUTIONS.md#L1) | 문제, 원인, 수정과 확인 한계를 남긴 기록 |
| [iOS 개발 안내](../ios-pixel-boxing/README.md#L1) | 현행 앱 프로젝트와 개발 경로 |

## 출시와 보안

| 문서 | 읽을 내용 |
| --- | --- |
| [출시 준비 체크리스트](release/RELEASE_READINESS_CHECKLIST.md#L1) | 확인한 제출 상태와 남은 구매·가격 전환·출시 점검 |
| [1.2 제출 기록](../ios-pixel-boxing/AppStoreMetadata/1.2-submission.json#L1) | 날짜가 있는 제출 근거, 실시간 상태 조회가 아닌 기록 |
| [보안 경계](engineering/SECURITY_BOUNDARIES.md#L1) | 공개 자료, 로컬 자료, 인증 비밀과 서비스 경계 |
| [보안 정책](../SECURITY.md#L1) | 취약점의 비공개 제보 경로 |

## 미디어와 포트폴리오

| 안내 | 읽을 내용 |
| --- | --- |
| [미디어 인덱스](media/README.md#L1) | 실제 화면, 완성 영상, 제작 원본과 초기 캡처 |
| [포트폴리오 안내](portfolio/README.md#L1) | 현행 Typst 원본과 과거 PDF의 구분, 선택적 출력 방법 |

영상·스크린샷은 촬영 조건과 버전을 함께 읽습니다. 오래된 PDF나 홍보 장면을 현재 출시 기능의 증거로 대신하지 않습니다.

## 레거시

이전 구현은 제품의 출발점과 실험 기록입니다. 현행 iOS 기능 명세와 분리합니다.

| 안내 | 범위 |
| --- | --- |
| [C++ 터미널 구현](../legacy/terminal-cpp/README.md#L1) | 초기 전투·세션 규칙과 기존 루트 CMake 실행 경로 |
| [Python 구현](../legacy/python/README.md#L1) | 데스크톱 프로토타입과 해당 테스트 |
| [../legacy/godot](../legacy/godot) | 이전 Godot 엔진 실험 |
| [legacy](legacy) | 초기 설계, 개요, 모션 메모와 이미지 |

## 읽는 순서

- **제품 이해:** 게임 가이드 → 설계 철학 → 실제 미디어.
- **구현 탐색:** 아키텍처 → 관심 소스 → AI 안내·개발 문제 기록.
- **출시 검토:** 체크리스트 → 제출 기록 → 보안 경계와 공개 정책.

## 기록 기준

- 의도, 구현된 동작, 직접 확인한 결과와 미검증 항목을 구분합니다.
- 경로 이동은 [폴더 안내](REPOSITORY_LAYOUT.md#L1)에 정리합니다. 앱·Pages·제작 도구의 현행 참조 경로는 유지합니다.
- 이 인덱스는 새 빌드·테스트·캡처·서비스 조회를 수행했다는 보고가 아닙니다.
