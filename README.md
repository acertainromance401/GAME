# GAME

복싱 게임 실험을 함께 관리하는 저장소입니다.

## 현재 본선

현재 집중 개발 대상은 Python/Tkinter 기반의 독립형 탑다운 복싱 게임입니다.

```bash
.venv/bin/python desktop-pixel-boxing/pixel_boxing_topdown.py
```

전투 규칙, 8종 펀치, 방향 더킹, 라운드/매치 진행, 카메라, 캐릭터 모션과 경기장 연출은 이 버전을 기준으로 발전시킵니다. `godot-pixel-boxing/`은 이식 가능성을 검증한 실험 스캐폴드이며 현재 개발은 보류합니다.

## C++ TUI

Realtime boxing TUI written in C++20.

플레이어는 링 위에서 계속 부활하며, 라운드가 올라갈수록 적 AI가 학습하고 압박을 강화합니다. 최종 10라운드를 돌파하면 KO 승리입니다.

## 빠른 시작

```bash
cmake -S . -B build -DGAME_USE_FTXUI=ON
cmake --build build
./build/game_tui
```

macOS에서 새 Terminal 창으로 실행하려면:

```bash
bash scripts/open_game_terminal.sh
```

## 조작

- 이동: 방향키 또는 `i/j/k/l`
- 위/`i`: 상대에게서 멀어짐
- 아래/`k`: 상대에게 다가감
- 왼쪽/`j`: 상대 기준 반시계 회전
- 오른쪽/`l`: 상대 기준 시계 회전
- 잽: `a`
- 스트레이트: `d`
- 가드: `w`
- 왼쪽 덕킹: `q`
- 오른쪽 덕킹: `e`
- `q + a`: 레프트 바디
- `q + d`: 라이트 훅
- `e + a`: 레프트 훅
- `e + d`: 라이트 바디
- `w + a`: 레프트 어퍼컷
- `w + d`: 라이트 어퍼컷
- 회복: `h`
- 저장: `v`
- 불러오기: `b`
- 새 경기: `n`
- 통계: `t`
- 종료: `Escape`

## 문서

- [프로젝트 개요](docs/PROJECT_OVERVIEW.md)
- [Pixel Boxing Top-Down 게임 설계](docs/PIXEL_BOXING_GAME_DESIGN.md)

## 현재 목표

- 링 안을 360도 돌며 싸우는 회전형 이동을 더 자연스럽게 만들기
- 잽/스트레이트/가드/슬립 판정을 명확하게 분리
- 모션과 외형을 더 읽기 쉽게 개선
