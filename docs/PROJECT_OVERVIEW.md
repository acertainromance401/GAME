# Project Overview

## Summary

이 저장소는 하나의 복싱 게임을 C++ 터미널 TUI, 브라우저 및 Tkinter 횡 액션, Python/Tkinter 의사 3D 탑다운으로 발전시킨 기록을 함께 보관합니다. 현재 제품 본선은 `desktop-pixel-boxing/pixel_boxing/pixel_boxing_topdown.py`이며, 나머지 구현은 아이디어와 기술 선택을 검증한 이전 단계 또는 이식 실험입니다.

## Development Line

1. **C++20 TUI**: 실시간 전투 루프, 라운드, 저장·불러오기, 패턴 추적과 학습 AI를 먼저 검증했습니다.
2. **Browser prototype**: 의존성 없는 단일 웹 페이지에서 캐릭터, 공격, 가드와 회피를 시각화했습니다.
3. **Tkinter side-view**: 횡 액션 형태로 8종 공격, 캐릭터 모션과 타격 반응을 확장했습니다.
4. **Pixel Boxing Top-Down**: 360도 링 이동, 의사 3D 카메라, 방향 더킹과 거리·각도 중심 전투를 본선으로 확립했습니다.
5. **Stabilization and polish**: 전투 코어 분리, 자동 테스트, 적응형 AI, 설정·오디오·HUD, 링·관중·피격·KO 연출과 렌더 최적화를 진행했습니다.

자세한 의사결정 배경과 단계별 개선 내용은 저장소 [메인 README](../README.md)의 프로젝트 발전 과정에 정리되어 있습니다.

## Current Mainline

### Runtime flow

1. 호환 진입점 `desktop-pixel-boxing/pixel_boxing_topdown.py`가 canonical 패키지를 불러옵니다.
2. `pixel_boxing/pixel_boxing_topdown.py`의 `TopDownPrototype`이 입력, 라운드 상태, AI, 카메라와 Canvas 렌더를 조정합니다.
3. `pixel_boxing/boxing_core.py`가 공격 명세, 전투 규칙, 플레이 습관 모델, 적응 가중치와 헤드리스 시뮬레이터를 제공합니다.
4. `pixel_boxing/game_settings.py`와 `pixel_boxing/audio_feedback.py`가 영구 설정과 오디오 피드백을 담당합니다.
5. `tests/test_pixel_boxing_core.py`와 `tests/test_pixel_boxing_phase2.py`가 전투 및 라이브 연결을 회귀 검증합니다.

### Current capabilities

- 역할과 생체역학이 구분된 8종 펀치
- 좌우 방향 더킹, 가드, 백스텝과 카운터
- 헛스윙 노출, 반복 기술 약화, 스태미나와 탈진
- 플레이 습관을 읽고 라운드가 진행될수록 대응하는 적응형 AI
- 제한 없이 이어지는 45초 라운드와 세션 점수
- 정사각형 링, 360도 관중, 의사 3D 카메라와 관절형 복서
- 공격별 피격 반응, 전신 KO 다운, 사운드와 해설 자막
- 설정 저장, 일시정지, 조작 안내와 안전한 Tk 종료
- 57개 Python 회귀 테스트와 렌더 성능 검증

## Repository Map

### Current Python game

- `desktop-pixel-boxing/pixel_boxing/`: canonical Python 패키지
- `desktop-pixel-boxing/pixel_boxing_topdown.py`: 기존 실행 경로를 유지하는 호환 진입점
- `tests/`: 전투 코어와 Tk 게임 연결 회귀 테스트
- `docs/PIXEL_BOXING_GAME_DESIGN.md`: 현재 게임의 규칙과 단계별 개발 기준
- `docs/motion.md`: 오소독스 스탠스와 8종 펀치 모션 기준

### Official browser build

- `pixel-boxing/index.html`: GitHub Pages 실행 진입점과 접근 가능한 게임 UI
- `pixel-boxing/styles.css`: 데스크톱·모바일 반응형 경기 화면과 터치 조작 레이아웃
- `pixel-boxing/game.js`: 8종 공격, 방향 방어, 행동 패턴 학습 AI와 Canvas 렌더링
- `.github/workflows/deploy-pages.yml`: `pixel-boxing/`만 Pages 아티팩트로 자동 배포
- Play URL: [Pixel Boxing on GitHub Pages](https://acertainromance401.github.io/GAME/)

### Earlier visual prototypes

- `desktop-pixel-boxing/pixel_boxing_app.py`: Tkinter 횡 액션 프로토타입
- `desktop-pixel-boxing/pixel_boxing_desktop.py`: 이전 데스크톱 실험

### Original C++ TUI

- `include/game/`, `src/game/`: 전투 상태, 세션, AI, 패턴 모델, 저장과 렌더러
- `CMakeLists.txt`: `game_core`, `game_tui`, `game_tests`와 선택적 FTXUI 구성
- `tests/smoke_tests.cpp`: C++ 스모크 테스트
- `scripts/open_game_terminal.sh`: macOS Terminal 실행 도우미

### Portability experiments

- `godot-pixel-boxing/`: Godot 4 이식 가능성을 검증한 실험이며 현재 본 개발은 보류
- `desktop-pixel-boxing/`: PyInstaller 기반 macOS 애플리케이션 패키징이 가능한 현재 데스크톱 소스

## Verification

Python 본선:

```bash
.venv/bin/python -m unittest tests.test_pixel_boxing_core tests.test_pixel_boxing_phase2 -v
```

C++ TUI:

```bash
cmake -S . -B build -DGAME_USE_FTXUI=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

## Current Constraints

- 배포용 `.app` 또는 Steam 패키지는 아직 생성·서명되지 않았습니다.
- 실제 주먹 스윕과 머리·몸통 허트박스 인터페이스는 코어에 있지만, 라이브 표시와 판정의 완전한 통합은 후속 작업입니다.
- 학습형 AI의 현재 구현은 플레이 습관 기반 적응 로직이며, 훈련된 강화학습 정책 저장·배포는 아직 보류 상태입니다.
- 도형 기반 Tk Canvas 렌더러는 현재 스타일을 완성하는 데 적합하지만, 최종 상용 아트 파이프라인은 확정되지 않았습니다.
- 일반 사용자 배포 전에는 실제 플레이 검증과 macOS 서명·공증 절차가 필요합니다.
