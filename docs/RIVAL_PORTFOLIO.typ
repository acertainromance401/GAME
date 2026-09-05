#let navy = rgb("#111827")
#let ink = rgb("#202633")
#let muted = rgb("#687083")
#let paper = rgb("#f7f8fa")
#let border = rgb("#d9dee7")
#let blue = rgb("#1357c4")
#let red = rgb("#b6243f")
#let gold = rgb("#d4a62a")
#let pale-blue = rgb("#eaf1fc")
#let pale-red = rgb("#fbecef")

#set document(title: "RIVAL 프로젝트 포트폴리오", author: "acertainromance401")
#set page(paper: "a4", margin: (x: 18mm, y: 16mm), fill: paper)
#set text(font: "Apple SD Gothic Neo", size: 9.5pt, fill: ink)
#set par(leading: 0.72em, justify: false)
#set heading(numbering: none)
#show heading.where(level: 1): it => block(above: 0pt, below: 10pt)[
  #text(size: 22pt, weight: "bold", fill: navy)[#it.body]
]
#show heading.where(level: 2): it => block(above: 14pt, below: 6pt)[
  #text(size: 13pt, weight: "bold", fill: blue)[#it.body]
]
#show link: set text(fill: blue)
#show table.cell.where(y: 0): set text(weight: "bold", fill: navy)

#let section-label(label-text) = block(below: 5pt)[
  #text(size: 8pt, weight: "bold", fill: red)[#upper(label-text)]
]

#let panel(body, fill: white, stroke: border, inset: 10pt) = block(
  fill: fill,
  stroke: 0.7pt + stroke,
  radius: 4pt,
  inset: inset,
  width: 100%,
  body,
)

#let metric(value, label, accent: blue) = block[
  #text(size: 20pt, weight: "bold", fill: accent)[#value]
  #linebreak()
  #text(size: 8pt, fill: muted)[#label]
]

#let page-title(kicker, title, subtitle: none) = [
  #section-label(kicker)
  #heading(level: 1)[#title]
  #if subtitle != none [#text(size: 9pt, fill: muted)[#subtitle]]
  #v(5pt)
]

#let bullet-item(title, body) = block(below: 5pt)[
  #text(weight: "bold", fill: navy)[#title] #body
]

// 1. Cover
#set page(margin: 0mm, fill: rgb("#05070b"))
#block(width: 100%, height: 112mm, clip: true)[
  #image("../ios-pixel-boxing/PixelBoxingIOS/Assets.xcassets/LoadingScreenArt.imageset/LoadingScreenArt@3x.png", width: 100%, height: 112mm, fit: "cover")
]
#block(inset: (x: 20mm, y: 14mm), width: 100%)[
  #text(size: 9pt, weight: "bold", fill: rgb("#db3656"))[PROJECT PORTFOLIO · iOS GAME]
  #v(7pt)
  #text(size: 36pt, weight: "bold", fill: white)[RIVAL]
  #v(2pt)
  #text(size: 17pt, weight: "medium", fill: rgb("#cdd5e3"))[플레이어의 습관을 읽는 3D 복싱 게임]
  #v(12pt)
  #line(length: 38mm, stroke: 2pt + blue)
  #v(10pt)
  #text(size: 10pt, fill: rgb("#aeb8ca"))[
    개인 프로젝트 · 기획 / 게임 시스템 / iOS 개발 / 테스트 / App Store 출시
  ]
  #v(4pt)
  #text(size: 9pt, fill: rgb("#7f8ba0"))[Swift 6 · SwiftUI · SceneKit · GameKit · XCTest]
  #v(20pt)
  #text(size: 8pt, fill: rgb("#778196"))[acertainromance401 · 2026]
]

// 2. Project overview
#pagebreak()
#set page(margin: (x: 18mm, y: 16mm), fill: paper)
#page-title("01 · OVERVIEW", "단순히 강해지는 AI가 아니라, 나를 읽는 상대", subtitle: "App Store 정식 출시 · 2026-08-27 · iPhone · iOS 17+")

#panel(fill: navy, stroke: navy, inset: 13pt)[
  #text(size: 15pt, weight: "bold", fill: white)[핵심 질문]
  #v(5pt)
  #text(size: 11pt, fill: rgb("#dce3ee"))[
    “같은 패턴을 반복하면 상대가 그 습관을 기억하고 공략하는 복싱 게임을 만들 수 있을까?”
  ]
]

#v(8pt)
#panel(fill: pale-red, stroke: red, inset: 9pt)[
  #text(weight: "bold", fill: red)[App Store 출시 완료]
  #h(6pt)
  한국 App Store에 유료 앱으로 정식 출시했습니다. · 출시 버전 1.0 · 게임/스포츠/액션 · ₩4,400
]

#v(8pt)
#grid(columns: (1fr, 1fr), gutter: 8pt,
  panel[
    #text(weight: "bold", fill: blue)[문제]
    #v(4pt)
    일반적인 난이도 상승은 체력·공격력 증가에 머물러 플레이어에게 “학습당하고 있다”는 감각을 주기 어렵습니다.
  ],
  panel[
    #text(weight: "bold", fill: red)[해결]
    #v(4pt)
    공격, 가드, 더킹, 전후 이동 비율을 기기 안에서 누적하고 라운드와 표본 신뢰도에 따라 RIVAL의 행동 가중치를 조정했습니다.
  ],
)

#heading(level: 2)[프로젝트 한눈에 보기]
#grid(columns: (1fr, 1fr, 1fr, 1fr), gutter: 7pt,
  panel(metric("8", "서로 다른 공격", accent: red), inset: 8pt),
  panel(metric("3", "전투 스타일", accent: blue), inset: 8pt),
  panel(metric("10", "해금 의상", accent: gold), inset: 8pt),
  panel(metric("3", "지원 언어", accent: navy), inset: 8pt),
)

#heading(level: 2)[담당 범위]
#table(
  columns: (28mm, 1fr),
  inset: 6pt,
  stroke: 0.6pt + border,
  [영역], [구현 내용],
  [기획], [핵심 루프, 공격 체계, 방향 더킹, 난이도 곡선, 보상 구조],
  [게임 로직], [프레임 기반 전투 엔진, 적중·가드·카운터·탈진·라운드 판정],
  [클라이언트], [SwiftUI 터치 HUD, SceneKit 3D 링·복서·카메라·연출],
  [AI], [행동 통계, 적응도, 상황별 가중치, 로컬 영속화와 패배 롤백],
  [품질], [XCTest/UI 테스트, 다국어, VoiceOver, 햅틱, 실기기·App Store 배포],
)

#v(9pt)
#panel(fill: pale-blue, stroke: blue)[
  #text(weight: "bold", fill: blue)[결과]
  #h(5pt)
  C++ TUI에서 시작한 규칙 실험을 웹·Python 프로토타입으로 검증한 뒤, 네이티브 iOS 3D 게임으로 완성해 App Store에 출시했습니다.
]

// 3. Gameplay
#pagebreak()
#page-title("02 · GAMEPLAY", "두 개의 공격 버튼으로 만드는 8가지 선택", subtitle: "버튼 수는 줄이고, 방향·타이밍·거리의 판단은 늘렸습니다.")

#grid(columns: (0.86fr, 1.14fr), gutter: 10pt,
  [
    #heading(level: 2)[조합 입력]
    #table(
      columns: (1.15fr, 0.8fr, 0.9fr),
      inset: 5pt,
      stroke: 0.55pt + border,
      [홀드], [JAB], [CROSS],
      [없음], [잽], [크로스],
      [가드], [L 어퍼], [R 어퍼],
      [L 더킹], [L 바디], [R 훅],
      [R 더킹], [L 훅], [R 바디],
    )
    #v(9pt)
    #panel(fill: pale-red, stroke: red)[
      #text(weight: "bold", fill: red)[설계 의도]
      #v(4pt)
      모바일 화면을 버튼으로 가득 채우지 않으면서도, 방어 자세와 펀치의 조합을 익히는 손맛을 남겼습니다.
    ]
  ],
  [
    #block(height: 88mm, clip: true, radius: 4pt)[
      #image("../ios-pixel-boxing/PixelBoxingIOS/Assets.xcassets/LoadingScreenArt.imageset/LoadingScreenArt@3x.png", width: 100%, height: 88mm, fit: "cover")
    ]
    #text(size: 7.5pt, fill: muted)[SceneKit으로 생성한 실제 인게임 복서와 링]
  ],
)

#heading(level: 2)[전투를 읽게 만드는 규칙]
#grid(columns: (1fr, 1fr), gutter: 8pt,
  panel[
    #bullet-item("방향 더킹", [공격 손에 맞는 방향으로 피해야 성공하며, 바디 공격에는 통하지 않습니다.])
    #bullet-item("헛스윙 노출", [사거리 밖 공격은 빈틈을 만들고 다음 피격 피해를 키웁니다.])
    #bullet-item("반복 기술 약화", [동일 기술을 세 번째부터 반복하면 피해가 단계적으로 감소합니다.])
  ],
  panel[
    #bullet-item("가드 파괴", [체력 피해를 줄이는 대신 스태미나를 소모하고, 0이 되면 탈진합니다.])
    #bullet-item("카운터", [정확한 회피 뒤 제한 시간 안에 바디·훅을 연결하면 추가 피해가 발생합니다.])
    #bullet-item("승리 기반 진행", [플레이어가 이긴 경우에만 라운드와 AI 적응 단계가 올라갑니다.])
  ],
)

#heading(level: 2)[플레이 스타일]
#table(
  columns: (25mm, 35mm, 1fr),
  inset: 6pt,
  stroke: 0.55pt + border,
  [스타일], [강점], [트레이드오프],
  [인파이터], [균형·연타], [낮은 공격 스태미나 비용으로 빠른 연계에 유리],
  [아웃복싱], [리치·풋워크], [빠르고 길지만 공격력이 낮음],
  [슬러거], [한 방·가드], [강한 공격력과 가드 효율 대신 짧은 리치와 느린 이동],
)

// 4. Adaptive AI
#pagebreak()
#page-title("03 · ADAPTIVE AI", "설명 가능한 온디바이스 적응형 AI", subtitle: "외부 API와 플레이 데이터 전송 없이, 현재 기기에서만 동작합니다.")

#grid(columns: (1fr, 9mm, 1fr, 9mm, 1fr), gutter: 3pt,
  panel[
    #text(weight: "bold", fill: blue)[01 · 관찰]
    #v(3pt)
    8종 공격, 가드, 좌우 더킹, 백스텝, 압박·후퇴를 누적
  ],
  align(center + horizon)[#text(size: 18pt, fill: muted)[→]],
  panel[
    #text(weight: "bold", fill: blue)[02 · 해석]
    #v(3pt)
    행동 비율과 표본 강도, 현재 라운드로 적응도 계산
  ],
  align(center + horizon)[#text(size: 18pt, fill: muted)[→]],
  panel[
    #text(weight: "bold", fill: red)[03 · 대응]
    #v(3pt)
    거리·상태·습관을 반영한 가중 확률로 다음 행동 선택
  ],
)

#heading(level: 2)[적응도 모델]
#panel(fill: navy, stroke: navy)[
  #align(center)[
    #text(size: 12pt, fill: white)[adaptation = clamp(0.18 + 0.16 × (round - 1) + 0.58 × sampleStrength, 0.18, 1.0)]
  ]
]

#v(9pt)
#grid(columns: (1fr, 1fr), gutter: 8pt,
  [
    #heading(level: 2)[관찰 → 대응 예시]
    #table(
      columns: (0.9fr, 1.15fr),
      inset: 5pt,
      stroke: 0.55pt + border,
      [플레이어 습관], [RIVAL의 가중치 변화],
      [가드 유지], [바디샷 증가],
      [오른쪽 더킹 반복], [오른손 공격 증가],
      [잽 반복], [크로스·훅·회피 증가],
      [후퇴·백스텝], [잽·크로스 추격 증가],
      [같은 공격 3회+], [좌우 더킹 증가],
    )
  ],
  [
    #heading(level: 2)[데이터 원칙]
    #panel[
      #bullet-item("Local-first", [`UserDefaults`에 `Codable` JSON으로 저장])
      #bullet-item("Privacy", [이름·연락처·위치·광고 식별자 수집 없음])
      #bullet-item("Resilience", [저장값이 없거나 손상되면 빈 메모리로 시작])
      #bullet-item("Fairness", [패배 라운드의 신규 습관은 시작 시점으로 롤백])
      #bullet-item("Explainability", [신경망이 아닌 명시적 규칙과 임계값으로 동작])
    ]
  ],
)

#v(10pt)
#panel(fill: pale-blue, stroke: blue)[
  #text(weight: "bold", fill: blue)[왜 강화학습 모델을 쓰지 않았나]
  #v(4pt)
  초기 제품에서는 오프라인 동작, 디버깅 가능성, 작은 앱 크기, 플레이 감각의 직접 조정을 우선했습니다. 런타임 AI와 개발 과정의 생성형 AI 사용도 명확히 분리했습니다.
]

// 5. Architecture
#pagebreak()
#page-title("04 · ARCHITECTURE", "판정과 표현을 분리한 테스트 가능한 구조", subtitle: "렌더링 없이도 전투 규칙과 AI를 검증할 수 있도록 책임을 나눴습니다.")

#align(center)[
  #grid(columns: (36mm, 8mm, 36mm, 8mm, 36mm), gutter: 3pt,
    panel(fill: pale-blue, stroke: blue)[#align(center)[#text(weight: "bold")[SwiftUI Views]\입력 · HUD · 메뉴]],
    align(center + horizon)[→],
    panel(fill: white, stroke: navy)[#align(center)[#text(weight: "bold")[GameController]\상태 연결 · 저장]],
    align(center + horizon)[→],
    panel(fill: pale-red, stroke: red)[#align(center)[#text(weight: "bold")[CombatEngine]\전투 · AI · 라운드]],
  )
  #v(8pt)
  #text(size: 18pt, fill: muted)[↓]
  #v(5pt)
  #grid(columns: (1fr, 1fr, 1fr), gutter: 8pt,
    panel[#align(center)[#text(weight: "bold")[CombatSnapshot]\읽기 전용 화면 상태]],
    panel[#align(center)[#text(weight: "bold")[Arena3DScene]\SceneKit 표현]],
    panel[#align(center)[#text(weight: "bold")[HabitMemory]\행동 통계 · 영속화]],
  )
]

#heading(level: 2)[기술 선택]
#table(
  columns: (31mm, 1fr, 1.1fr),
  inset: 6pt,
  stroke: 0.55pt + border,
  [기술], [역할], [선택 이유],
  [Swift 6], [전투 코어·상태 모델], [타입 안정성과 엄격한 동시성 검증],
  [SwiftUI], [가로형 HUD·메뉴·접근성], [상태 기반 UI와 빠른 반복 개발],
  [SceneKit], [3D 링·복서·조명·카메라], [외부 모델 없이 코드 기반 지오메트리 생성],
  [GameKit], [리더보드], [별도 서버 없이 Apple 플랫폼 기능 연동],
  [XCTest], [전투·AI·회귀 테스트], [렌더러와 분리된 결정 로직 직접 검증],
  [XcodeGen], [프로젝트 정의], [생성 프로젝트 대신 `project.yml`을 단일 원본으로 유지],
)

#heading(level: 2)[제품 기능으로 확장된 구조]
#grid(columns: (1fr, 1fr), gutter: 8pt,
  panel[
    #bullet-item("체육관", [고정 샌드백, 타격 반응, 코치 팁, 무제한 콤보 연습])
    #bullet-item("보상", [승수·연승·무피격·스타일 숙련·체육관 시간으로 10개 의상 해금])
  ],
  panel[
    #bullet-item("랭킹", [Game Center 총 승수와 최고 라운드 표시])
    #bullet-item("현지화", [한국어·영어·일본어 UI와 코치 메시지])
  ],
)

#v(9pt)
#panel(fill: navy, stroke: navy)[
  #text(weight: "bold", fill: white)[앱 크기]
  #h(8pt)
  #text(size: 16pt, weight: "bold", fill: rgb("#79a9ff"))[약 5.2 MB]
  #h(8pt)
  #text(fill: rgb("#cdd5e3"))[Release 기준 · 외부 3D 모델/텍스처/오디오 파일 없이 지오메트리와 효과음을 코드로 생성]
]

// 6. Problem solving
#pagebreak()
#page-title("05 · PROBLEM SOLVING", "느낌의 문제를 구조와 수치의 문제로 바꾸기", subtitle: "플레이 피드백을 재현 가능한 조건으로 바꾸고, 가장 가까운 원인을 수정했습니다.")

#grid(columns: (1fr, 1fr), gutter: 8pt,
  panel[
    #text(size: 8pt, weight: "bold", fill: red)[CASE 01]
    #v(3pt)
    #text(size: 12pt, weight: "bold", fill: navy)[최단 사거리 공격이 맞지 않음]
    #v(6pt)
    체육관 이동 최소 반경 `58`이 인파이팅 보정이 적용된 왼쪽 어퍼컷 최대 적중 거리 `56.6`보다 컸습니다.
    #v(6pt)
    #text(weight: "bold", fill: blue)[해결]
    #h(4pt)
    전투 수치를 왜곡하지 않고 연습 공간의 최소 반경을 `54`로 조정해 모든 스타일·공격 조합의 적중을 보장했습니다.
  ],
  panel[
    #text(size: 8pt, weight: "bold", fill: red)[CASE 02]
    #v(3pt)
    #text(size: 12pt, weight: "bold", fill: navy)[샌드백이 펀치 쪽으로 흔들림]
    #v(6pt)
    회전축 부호를 직감으로 정한 결과 펀치 반대가 아닌 공격자 방향으로 기울었습니다.
    #v(6pt)
    #text(weight: "bold", fill: blue)[해결]
    #h(4pt)
    Rodrigues 회전식으로 매달린 점의 이동 방향을 계산해 축을 `(z, -x)`에서 `(-z, x)`로 교정했습니다.
  ],
)

#v(8pt)
#grid(columns: (1fr, 1fr), gutter: 8pt,
  panel[
    #text(size: 8pt, weight: "bold", fill: red)[CASE 03]
    #v(3pt)
    #text(size: 12pt, weight: "bold", fill: navy)[팔이 몸통에 묻혀 보임]
    #v(6pt)
    스타일별 몸통 스케일이 달라졌지만 관절 좌표는 동일해, 슬러거의 어깨와 전완이 몸통 표면 안에 들어갔습니다.
    #v(6pt)
    #text(weight: "bold", fill: blue)[해결]
    #h(4pt)
    타원 경계식 `(x/rx)^2 + (z/rz)^2 > 1`로 관절이 몸 밖에 있는지 검증하고, 벡터 내적으로 팔꿈치 각도를 수치화했습니다.
  ],
  panel[
    #text(size: 8pt, weight: "bold", fill: red)[CASE 04]
    #v(3pt)
    #text(size: 12pt, weight: "bold", fill: navy)[AI 메시지가 판정과 반대로 안내]
    #v(6pt)
    더킹·헛스윙 해설이 플레이어와 RIVAL의 역할을 구분하지 않아 카운터 권한을 반대로 전달했습니다.
    #v(6pt)
    #text(weight: "bold", fill: blue)[해결]
    #h(4pt)
    공격자·방어자 주체를 해설 함수에 전달해 “기회”와 “위험” 메시지를 분리하고 실제 판정과 일치시켰습니다.
  ],
)

#heading(level: 2)[반복 개선 방식]
#grid(columns: (1fr, 9mm, 1fr, 9mm, 1fr, 9mm, 1fr), gutter: 2pt,
  panel[#align(center)[#text(weight: "bold")[관찰]\실기기 피드백]],
  align(center + horizon)[→],
  panel[#align(center)[#text(weight: "bold")[가설]\코드 경로 특정]],
  align(center + horizon)[→],
  panel[#align(center)[#text(weight: "bold")[검증]\수치·테스트 재현]],
  align(center + horizon)[→],
  panel[#align(center)[#text(weight: "bold")[수정]\빌드·실기기 확인]],
)

#v(10pt)
#panel(fill: pale-red, stroke: red)[
  #text(weight: "bold", fill: red)[배운 점]
  #h(5pt)
  “모션이 이상하다”는 피드백도 카메라 투영, 관절 경계, 회전축, 입력 상태처럼 검증 가능한 하위 문제로 나누면 안정적으로 개선할 수 있습니다.
]

// 7. Verification and evolution
#pagebreak()
#page-title("06 · DELIVERY", "프로토타입에서 App Store 정식 출시까지", subtitle: "각 단계의 한계를 다음 기술 선택의 근거로 사용했습니다.")

#table(
  columns: (16mm, 32mm, 1fr),
  inset: 6pt,
  stroke: 0.55pt + border,
  [단계], [구현], [검증한 질문],
  [01], [C++20 TUI], [전투 루프, 저장, 플레이 패턴 기록이 게임으로 성립하는가],
  [02], [Web / Tkinter], [8종 공격과 방향 방어가 화면과 입력으로 읽히는가],
  [03], [Python Top-Down], [360도 이동, 의사 3D 카메라, 적응형 AI가 플레이 감각을 만드는가],
  [04], [Swift iOS], [터치·3D·햅틱·접근성·배포까지 네이티브 제품으로 완성할 수 있는가],
  [05], [App Store], [심사·가격 설정·스토어 메타데이터를 거쳐 실제 사용자에게 배포할 수 있는가],
)

#heading(level: 2)[검증 결과]
#grid(columns: (1fr, 1fr, 1fr), gutter: 8pt,
  panel(metric("30", "iOS 단위 회귀 테스트", accent: blue), inset: 9pt),
  panel(metric("1", "가로형 UI 시나리오", accent: red), inset: 9pt),
  panel(metric("57", "Python 회귀 테스트", accent: gold), inset: 9pt),
)

#v(8pt)
#grid(columns: (1fr, 1fr), gutter: 8pt,
  panel[
    #text(weight: "bold", fill: navy)[테스트 범위]
    #v(5pt)
    · 8종 공격 수치와 조합 입력\
    · 방향 더킹과 카운터 보너스\
    · 가드·스태미나·탈진·백스텝\
    · 적응도와 습관별 행동 가중치\
    · 라운드 승패·학습 롤백·초기화\
    · 카메라 회전 안정성과 복서 구조
  ],
  panel[
    #text(weight: "bold", fill: navy)[출시·운영]
    #v(5pt)
    · Generic iOS / 실기기 빌드 검증\
    · XcodeGen 기반 재현 가능한 프로젝트\
    · TestFlight 외부 테스트와 심사 대응\
    · App Store 유료 앱 정식 출시\
    · 개인정보 비수집·오프라인 우선\
    · Game Center 리더보드 연동
  ],
)

#heading(level: 2)[성능과 운영 판단]
#panel(fill: pale-blue, stroke: blue)[
  외부 유료 에셋과 서버를 사용하지 않아 배포 복잡도와 유지 비용을 낮췄습니다. SceneKit 노드는 최초 생성 후 재사용하고 매 프레임 자세와 카메라만 갱신합니다. 앱은 네트워크 없이 핵심 게임 전체를 실행하며, Game Center만 선택적 온라인 기능으로 분리했습니다.
]

#v(10pt)
#text(size: 8pt, fill: muted)[테스트 수는 저장소 현재 소스 기준입니다. RIVAL 1.0은 2026년 8월 27일 한국 App Store에 정식 출시됐습니다.]

// 8. Links
#pagebreak()
#page-title("07 · LINKS", "직접 확인하기", subtitle: "코드, 플레이 영상, 실행 가능한 웹 빌드와 상세 기술 문서를 함께 제공합니다.")

#grid(columns: (38mm, 1fr), gutter: 10pt,
  [#image("../ios-pixel-boxing/PixelBoxingIOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png", width: 38mm)],
  [
    #text(size: 24pt, weight: "bold", fill: navy)[RIVAL]
    #v(4pt)
    #text(size: 11pt, fill: muted)[적응형 AI와 맞서는 iPhone 3D 복싱 게임]
    #v(10pt)
    #text(weight: "bold")[App Store 1.0 · Current source 1.1 (Build 3) · iOS 17+]
  ],
)

#v(12pt)
#table(
  columns: (35mm, 1fr),
  inset: 8pt,
  stroke: 0.6pt + border,
  [항목], [링크],
  [App Store], [#link("https://apps.apple.com/kr/app/rival/id6799909429")[App Store에서 RIVAL 보기]],
  [GitHub], [#link("https://github.com/acertainromance401/GAME")[github.com/acertainromance401/GAME]],
  [플레이 영상], [#link("https://youtu.be/01h8Lo5UIJc")[YouTube에서 RIVAL 플레이 보기]],
  [웹 버전], [#link("https://acertainromance401.github.io/GAME/")[GitHub Pages에서 바로 실행]],
  [TestFlight], [#link("https://testflight.apple.com/join/btSgA8uT")[RIVAL 베타 테스트]],
  [게임 설명서], [`ios-pixel-boxing/GAME_GUIDE.md`],
  [AI 기술 문서], [`ios-pixel-boxing/AI_USAGE.md`],
)

#v(14pt)
#panel(fill: navy, stroke: navy, inset: 14pt)[
  #text(size: 15pt, weight: "bold", fill: white)[프로젝트 요약]
  #v(7pt)
  #text(size: 10.5pt, fill: rgb("#dce3ee"))[
    RIVAL은 게임 규칙을 작은 프로토타입으로 검증하고, 플레이 피드백을 수치와 테스트로 전환하며, 네이티브 3D·접근성·현지화를 거쳐 App Store 정식 출시까지 완수한 개인 프로젝트입니다.
  ]
]

#v(15pt)
#line(length: 100%, stroke: 0.8pt + border)
#v(8pt)
#text(size: 8pt, fill: muted)[
  Portfolio generated from the repository source and documentation · 2026-09-02
]