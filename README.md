# terminal

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
- 잽: `a`
- 스트레이트: `s`
- 가드: `d`
- 슬립: `space`
- 블록/패링: `f`
- 스텝 아웃: `u`
- 스텝 인: `o`
- 대시: `z`
- 더킹: `x`
- 회복: `h`
- 저장: `v`
- 불러오기: `b`
- 새 경기: `n`
- 통계: `t`
- 종료: `q`

## 문서

- [프로젝트 개요](docs/PROJECT_OVERVIEW.md)

## 현재 목표

- 링 크기와 거리감을 복싱답게 유지
- 잽/스트레이트/가드/슬립 판정을 명확하게 분리
- 모션과 외형을 더 읽기 쉽게 개선
