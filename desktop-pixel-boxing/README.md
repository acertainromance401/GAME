# Pixel Boxing Top-Down

Python/Tkinter로 실행되는 독립형 탑다운 복싱 게임입니다. 현재 저장소의 주 개발 대상입니다.

## Current Progress

- 그래픽과 모션 4단계의 4-1~4-5 승인 범위가 완료되었습니다.
- 도형 기반 복서 실루엣, 공격·더킹·이동 모션, 링 구조물, 360도 관중석과 경기장 조명이 적용되어 있습니다.
- 펀치 종류와 가드 여부에 따른 피격 반응, 전신 KO 낙하와 다운 모션이 적용되어 있습니다.
- 선수의 전체 실루엣을 고려한 링 경계와 전경/후경 로프 분리로 링 이탈처럼 보이는 문제를 방지합니다.
- 자동 테스트 57개와 전투·KO 장면별 300프레임 렌더 성능 검증을 통과했습니다.
- 최종 비프로파일 렌더는 일반 전투 평균 6.48ms(P95 8.97ms), KO 장면 평균 5.42ms(P95 6.84ms)를 기록했습니다.

## Run

```bash
cd /path/to/GAME
.venv/bin/python desktop-pixel-boxing/pixel_boxing_topdown.py
```

## Test

```bash
.venv/bin/python -m unittest tests.test_pixel_boxing_core tests.test_pixel_boxing_phase2 -v
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
- 일시정지/재개: `P` 또는 `Esc`
- 조작 안내: `H`
- 설정: `O`

설정 화면에서는 숫자 키로 사운드, 해설 자막, 카메라 셰이크를 켜고 끌 수 있습니다. 설정은 사용자 홈의 `.pixel_boxing/settings.json`에 저장됩니다.

## Notes

- Python 표준 라이브러리의 `tkinter`를 사용합니다.
- 실제 메인 게임 구현은 `desktop-pixel-boxing/pixel_boxing/` 패키지 아래에 정리되어 있습니다.
- 루트의 `pixel_boxing_topdown.py`, `boxing_core.py`, `audio_feedback.py`, `game_settings.py`는 기존 실행/테스트 경로 호환용 진입점입니다.
- 상세 컨셉, 전투 규칙, 차별점과 단계별 계획은 [게임 설계 문서](../docs/PIXEL_BOXING_GAME_DESIGN.md)를 기준으로 합니다.
- `pixel_boxing_app.py`와 `pixel_boxing_desktop.py`는 이전 프로토타입입니다.
- `godot-pixel-boxing/`은 이식 검증용 실험이며 현재 개발은 보류합니다.
