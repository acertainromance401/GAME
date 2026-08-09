# Pixel Boxing Top-Down

Python/Tkinter로 실행되는 독립형 탑다운 복싱 게임입니다. 현재 저장소의 주 개발 대상입니다.

## Run

```bash
cd /path/to/GAME
.venv/bin/python desktop-pixel-boxing/pixel_boxing_topdown.py
```

## Test

```bash
.venv/bin/python -m unittest tests.test_pixel_boxing_core -v
```

## Controls

- 이동: 방향키
- 잽: `A`
- 크로스: `D`
- 왼쪽 더킹: `Q`
- 오른쪽 더킹: `E`
- 백스텝: `S`
- 가드: `W`
- 레프트 바디: `Q + A`
- 라이트 훅: `Q + D`
- 레프트 훅: `E + A`
- 라이트 바디: `E + D`
- 레프트 어퍼컷: `W + A`
- 라이트 어퍼컷: `W + D`
- 라운드 시작/다음 라운드: `Space`
- 경기 재시작: `R`

## Notes

- Python 표준 라이브러리의 `tkinter`를 사용합니다.
- 전투 밸런스와 화면/캐릭터 고도화는 `pixel_boxing_topdown.py`를 기준으로 진행합니다.
- 상세 컨셉, 전투 규칙, 차별점과 단계별 계획은 [게임 설계 문서](../docs/PIXEL_BOXING_GAME_DESIGN.md)를 기준으로 합니다.
- `pixel_boxing_app.py`와 `pixel_boxing_desktop.py`는 이전 프로토타입입니다.
- `godot-pixel-boxing/`은 이식 검증용 실험이며 현재 개발은 보류합니다.
