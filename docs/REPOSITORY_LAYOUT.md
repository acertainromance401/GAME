# 저장소 구조와 경로 계약

현행 iOS 제품, 공개 웹, 이전 구현과 문서를 논리적으로 나눕니다. 폴더 정리는 앱 기능 변경이나 보안 감사 완료를 뜻하지 않습니다.

## 논리 구조

아래는 주요 경로만 표시한 지도입니다. 로컬 빌드·개인 설정·원본 녹화는 공개 파일 목록과 분리합니다.

```text
GAME/
├── README.md / SECURITY.md / CMakeLists.txt
├── .github/workflows/              Pages 등 저장소 자동화
├── ios-pixel-boxing/               현행 iOS 제품, 기존 경로 유지
│   ├── PixelBoxingIOS/             Swift 소스, Assets.xcassets, Resources
│   ├── PixelBoxingIOSTests/        단위 테스트 소스
│   ├── PixelBoxingIOSUITests/      UI 테스트와 StoreKit fixture
│   ├── RIVAL.xcodeproj/            기준 Xcode 프로젝트
│   ├── project.yml                별도 관리되는 생성 입력
│   ├── scripts/                   앱·제작·배포 도구
│   ├── art/                       Story 제작 원본
│   ├── PromotionAssets/           촬영·음원 자료와 권리 안내
│   ├── PromotionVideos/           완성 홍보물
│   ├── AppStoreScreenshots/       현행 제출 화면과 보존 자료
│   └── AppStoreMetadata/          버전별 메타데이터·제출 기록
├── pixel-boxing/                  웹 구현과 Pages 공개 파일
│   ├── support/                   기존 지원 URL의 원본
│   └── privacy/                   기존 개인정보 URL의 원본
├── legacy/
│   ├── terminal-cpp/              include, src, tests, CMakeLists.txt
│   ├── python/                    데스크톱 모듈과 tests
│   └── godot/                     이전 Godot 구현
├── docs/
│   ├── product/                   현행 가이드·설계 철학
│   ├── engineering/               구조·AI·개발 문제·보안 경계
│   ├── release/                   출시 준비와 확인 기록
│   ├── media/                     공개 미디어 인덱스·초기 캡처 archive
│   ├── portfolio/                 Typst 원본·과거 PDF archive
│   └── legacy/                    초기 설계·개요·모션 메모·이미지
└── scripts/                       루트 실행 도우미
```

## 공개·로컬·민감 자료

| 구분 | 예 | 취급 |
| --- | --- | --- |
| 공개 구현·문서 | 앱·웹·레거시 소스, 테스트, 프로젝트 설정, 문서 | 공개 소스와 실제 실행·배포 권한은 별개 |
| 공개 미디어·메타데이터 | 완성 영상, 제출 화면, 날짜가 있는 심사 기록, 앱·상품 ID | 버전·촬영 조건·외부 자산 라이선스 확인. ID는 인증 비밀이 아님 |
| 로컬 전용 | 빌드·아카이브, 원본 녹화, 제한된 음원 원본, 개인 IDE 설정, 로컬 저장 파일 | Git 제외 대상으로 유지. 정리를 위해 삭제하거나 공개 필수 링크로 만들지 않음 |
| 민감 자료 | 실제 환경 변수 파일, 개인 키, 서명 인증서, 프로비저닝 프로파일, 토큰 | 공개 저장소에 넣지 않음. 노출되었다면 폐기·회전과 영향 확인이 별도로 필요 |

[제외 규칙](../.gitignore#L1)은 이미 추적된 파일이나 과거 이력을 자동으로 지우지 않습니다. 자세한 경계는 [보안 문서](engineering/SECURITY_BOUNDARIES.md#L1), 제보는 [보안 정책](../SECURITY.md#L1)을 따릅니다. 이번 정리는 로컬 제외 파일의 삭제 작업이 아닙니다.

## 실제 이동과 C++ 호환 경로

루트의 C++ 헤더·구현은 `legacy/terminal-cpp/` 아래로, Python 모듈·해당 테스트는 `legacy/python/`으로, Godot 구현은 `legacy/godot/`으로 이동했습니다. 현행 앱이나 웹을 레거시로 이동한 것이 아닙니다.

루트 [CMake 진입점](../CMakeLists.txt#L1)은 C++ 하위 프로젝트를 연결하고 실행 파일 출력 위치를 유지합니다. 저장소 루트의 기존 명령은 계속 사용할 수 있습니다.

```bash
cmake -S . -B build -DGAME_USE_FTXUI=OFF
cmake --build build
./build/game_tui
```

이번 정리에서는 별도 임시 폴더에 CMake 구성·생성만 확인했습니다. 게임 대상 빌드·실행·테스트는 하지 않았습니다. 세부 옵션은 [C++ 안내](../legacy/terminal-cpp/README.md#L1)에 있습니다.

## 이동하지 않는 계약

- **iOS:** 소스·테스트·Xcode 프로젝트·앱 리소스는 기존 `ios-pixel-boxing/` 경로를 유지합니다. 기준 [프로젝트](../ios-pixel-boxing/RIVAL.xcodeproj/project.pbxproj#L1)를 보존하며 문서 정리에서 XcodeGen을 실행하지 않습니다.
- **제작·제출:** iOS 아래 스크립트, art, PromotionAssets, PromotionVideos, AppStoreScreenshots, AppStoreMetadata 경로를 유지합니다. 제작 도구나 리소스 등록의 참조를 임의로 바꾸지 않습니다.
- **Pages:** `pixel-boxing/`과 [배포 workflow](../.github/workflows/deploy-pages.yml#L1)를 유지합니다. [지원 URL](https://acertainromance401.github.io/GAME/support/)과 [개인정보 URL](https://acertainromance401.github.io/GAME/privacy/)을 바꾸지 않습니다. 로컬 원본 보존과 실제 공개 사이트 반영 확인은 별개입니다.
- **자료 이력:** 초기 캡처는 [미디어 인덱스](media/README.md#L1)의 archive로, 과거 PDF는 [포트폴리오 안내](portfolio/README.md#L1)의 archive로 구분합니다. 기존 출력물을 최신 결과로 재명명하지 않습니다.

## 이전 참조명 찾기

과거 문서·메모의 파일명은 아래 현행 경로에서 찾습니다. 파일명 기준 대응표이며, 이동으로 옛 GitHub 파일 링크에 자동 리디렉션이 생기지는 않습니다.

```text
GAME_GUIDE.md                             → docs/product/GAME_GUIDE.md
RIVAL_GAME_INTENT_AND_DESIGN_PHILOSOPHY.md → docs/product/RIVAL_GAME_INTENT_AND_DESIGN_PHILOSOPHY.md
AI_USAGE.md                              → docs/engineering/AI_USAGE.md
RIVAL_REINFORCEMENT_LEARNING_AUDIT.md      → docs/engineering/RIVAL_REINFORCEMENT_LEARNING_AUDIT.md
DEVELOPMENT_ISSUES_AND_SOLUTIONS.md        → docs/engineering/DEVELOPMENT_ISSUES_AND_SOLUTIONS.md
SECURITY_BOUNDARIES.md                    → docs/engineering/SECURITY_BOUNDARIES.md
RELEASE_READINESS_CHECKLIST.md            → docs/release/RELEASE_READINESS_CHECKLIST.md
PIXEL_BOXING_GAME_DESIGN.md               → docs/legacy/PIXEL_BOXING_GAME_DESIGN.md
PROJECT_OVERVIEW.md / motion.md / images.jpeg → docs/legacy/
RIVAL_PORTFOLIO.typ / pdf-style.typ        → docs/portfolio/
RIVAL_GAME_GUIDE.pdf / RIVAL_AI_USAGE.pdf  → docs/portfolio/archive/
루트 include/ · src/                      → legacy/terminal-cpp/include/ · src/
루트 Python 모듈 · Python 테스트         → legacy/python/ · legacy/python/tests/
Godot 프로토타입                         → legacy/godot/
```

문서에서 구현으로 들어갈 때는 [iOS 구조](engineering/ARCHITECTURE.md#L1), 전체 자료를 고를 때는 [문서 홈](README.md#L1)을 이용합니다.
