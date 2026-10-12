# RIVAL 포트폴리오

현행 포트폴리오 원본과 과거 출력물을 구분해 보관합니다. PDF가 있다는 이유만으로 최신 Markdown 문서나 현재 앱 버전과 내용이 같다고 보지 않습니다.

## 현행 원본

| 파일 | 용도 |
| --- | --- |
| [RIVAL_PORTFOLIO.typ](RIVAL_PORTFOLIO.typ#L1) | 2026-10-12 기준, 현재 소스 1.2(6)과 개인 프로젝트의 설계·구현·확인 범위를 설명하는 Typst 원본 |
| [pdf-style.typ](pdf-style.typ#L1) | 문서 출력용 스타일 자료. 포트폴리오 원본과 별도로 보관 |

소스 버전, 공개 앱 버전, 심사 상태는 서로 다른 정보입니다. 현재 소스 1.2(6)은 공개 앱 1.1과 같지 않으며, 마지막 심사 확인 기록은 2026-10-11 Waiting for Review·수동 출시입니다.

### 선택적 PDF 출력

Typst CLI와 원본에서 지정한 글꼴이 설치되어 있어야 합니다. 저장소 루트에서 다음 명령을 사용할 수 있습니다. `--root .`은 원본이 참조하는 iOS 이미지 경로를 포함합니다.

```bash
typst compile --root . docs/portfolio/RIVAL_PORTFOLIO.typ /tmp/RIVAL_PORTFOLIO.pdf
```

출력은 `/tmp`에 두어 보존 PDF를 덮어쓰지 않습니다. 이 문서 작업에서는 명령을 실행하거나 새 PDF를 생성하지 않습니다. 컴파일 성공만으로 문서 내용의 최신성이나 실제 앱 동작이 검증되지는 않습니다.

## 과거 PDF

| 보존 파일 | 읽는 기준 |
| --- | --- |
| [archive/RIVAL_GAME_GUIDE.pdf](archive/RIVAL_GAME_GUIDE.pdf) | 과거 게임 가이드 출력물. 현행 1.2 Markdown의 재출력본이 아님 |
| [archive/RIVAL_AI_USAGE.pdf](archive/RIVAL_AI_USAGE.pdf) | 과거 AI 안내 출력물. 현행 구현 설명·강화학습 점검과 동일한 문서가 아님 |

기존 출력물을 이력으로 보존하며, 새 버전으로 간주하거나 덮어쓰지 않습니다. 보존 경로 이동 자체가 내용 갱신을 뜻하지 않습니다.

## 최신 설명 읽기

- [게임 가이드](../product/GAME_GUIDE.md#L1)와 [제품 의도](../product/RIVAL_GAME_INTENT_AND_DESIGN_PHILOSOPHY.md#L1): 플레이 경험과 설계 기준.
- [AI 구현 안내](../engineering/AI_USAGE.md#L1)와 [강화학습 점검](../engineering/RIVAL_REINFORCEMENT_LEARNING_AUDIT.md#L1): 현재 구현과 기술적 한계.
- [개발 문제 기록](../engineering/DEVELOPMENT_ISSUES_AND_SOLUTIONS.md#L1)와 [출시 체크리스트](../release/RELEASE_READINESS_CHECKLIST.md#L1): 확인 근거와 남은 과제.
- [미디어 안내](../media/README.md#L1): 실제 화면·영상의 버전과 촬영 조건.

[문서 홈](../README.md#L1) · [저장소 구조](../REPOSITORY_LAYOUT.md#L1)
