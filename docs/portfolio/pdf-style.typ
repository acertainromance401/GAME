#let rival-navy = rgb("#172033")
#let rival-teal = rgb("#007c78")
#let rival-red = rgb("#b33a3a")
#let rival-line = rgb("#cfd6df")
#let rival-soft = rgb("#f3f6f8")

#set text(fill: rival-navy)
#set par(justify: true, leading: 0.72em)
#set table(inset: 5pt, stroke: 0.45pt + rival-line)

#show heading.where(level: 1): set text(size: 24pt, weight: "bold", fill: rival-navy)
#show heading.where(level: 2): set text(size: 16pt, weight: "bold", fill: rival-teal)
#show heading.where(level: 3): set text(size: 12.5pt, weight: "semibold", fill: rival-navy)
#show heading.where(level: 4): set text(size: 10.5pt, weight: "semibold", fill: rival-red)

#show table.cell.where(y: 0): set text(weight: "semibold", fill: rival-navy)
#show link: set text(fill: rival-teal)
#show raw.where(block: true): set block(fill: rival-soft, inset: 8pt, radius: 3pt)