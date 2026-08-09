# Pixel Boxing: Adaptive Rival

GitHub Pages에서 설치 없이 실행하는 Pixel Boxing 공식 심사용 웹 빌드입니다.

이 빌드의 기준 구현은 `../desktop-pixel-boxing/pixel_boxing/pixel_boxing_topdown.py`입니다. GitHub Pages에서 Tkinter를 직접 실행할 수 없기 때문에 Python 파일을 그대로 패키징한 것이 아니라, 본선과 `boxing_core.py`의 전투 규칙과 적응형 AI를 `game.js`로 이식한 브라우저 실행판입니다. Python 본선, 공유 전투 코어, 웹 빌드와 테스트는 모두 같은 공개 저장소와 커밋 이력에 포함됩니다.

## Play

[Play Pixel Boxing](https://acertainromance401.github.io/GAME/)

이 빌드는 별도 계정, 유료 라이선스, 플러그인 또는 다운로드를 요구하지 않습니다. 데스크톱 키보드와 모바일 터치 조작을 모두 지원합니다.

## Core Concept

상대 AI는 플레이어의 공격 반복, 가드, 좌우 더킹, 백스텝, 압박과 후퇴 성향을 라운드 동안 기록합니다. 수집한 표본과 라운드 수를 바탕으로 다음 행동의 가중치와 판단 속도를 조정하므로, 같은 습관을 계속 사용하면 점차 더 정확하게 공략당합니다.

현재 웹 빌드는 훈련된 강화학습 정책 대신 데스크톱 본선과 같은 행동 패턴 모델과 적응 가중치를 사용합니다. 저장소의 Python 전투 코어에는 향후 정책 훈련을 위한 17개 행동과 헤드리스 시뮬레이터 인터페이스가 포함되어 있습니다.

## Controls

| Input | Action |
| --- | --- |
| Arrow keys / screen D-pad | Approach, retreat, circle left/right |
| `A` | Jab |
| `D` | Cross |
| `Q` | Left duck |
| `E` | Right duck |
| `W` | Guard |
| `S` | Backstep |
| `Q + A` | Left body shot |
| `E + D` | Right body shot |
| `E + A` | Left hook |
| `Q + D` | Right hook |
| `W + A` | Left uppercut |
| `W + D` | Right uppercut |
| `P` / `Esc` | Pause / resume |

화면 아래에는 이동, 방어와 8종 펀치 버튼이 모두 제공됩니다. 터치 환경에서는 조합 키를 동시에 누르지 않고 각 기술 버튼을 직접 사용할 수 있습니다.

## Combat Rules

- 라운드는 45초이며 횟수 제한 없이 이어집니다.
- AI 학습 메모리와 세션 점수는 다음 라운드에도 유지됩니다.
- 머리 공격은 주먹이 들어오는 방향에 맞는 좌우 더킹으로 피합니다.
- 가드는 피해를 줄이지만 완전히 막지는 못합니다.
- 백스텝은 짧은 회피 판정과 큰 스태미나 비용을 가집니다.
- 헛스윙하면 노출 상태가 되어 카운터 피해를 더 받습니다.
- 같은 기술을 반복하면 피해량이 점차 감소합니다.
- 스태미나를 모두 사용하면 일시적으로 행동할 수 없습니다.

## Source Layout

- `index.html`: 접근 가능한 HUD, Canvas와 키보드·터치 조작
- `styles.css`: 반응형 게임 화면
- `game.js`: 전투 규칙, 행동 모델 AI, 오디오와 Canvas 렌더링
- `../desktop-pixel-boxing/pixel_boxing/`: Python/Tkinter canonical 데스크톱 본선
- `../tests/`: Python 전투 및 UI 회귀 테스트

## Run Locally

저장소 루트에서 다음 명령을 실행합니다.

```bash
python3 -m http.server 4173 --directory pixel-boxing
```

그다음 [http://localhost:4173/](http://localhost:4173/) 을 엽니다. 외부 CDN이나 패키지 설치는 필요하지 않습니다.

## Deployment

`.github/workflows/deploy-pages.yml`이 `main` 브랜치의 `pixel-boxing/` 변경을 감지해 GitHub Pages에 자동 배포합니다. 배포 아티팩트에는 이 폴더의 정적 파일만 포함되며 전체 소스와 커밋 기록은 상위 공개 저장소에서 확인할 수 있습니다.

## License

MIT License. 자세한 내용은 공개 저장소의 [LICENSE](https://github.com/acertainromance401/GAME/blob/main/LICENSE)를 확인하세요.
