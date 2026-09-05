# RIVAL Project Guidelines

## Canonical Product Intent

Before proposing or changing RIVAL's combat, AI, UI/UX, onboarding, rewards,
cinematics, progression, or player feedback, read
[docs/RIVAL_GAME_INTENT_AND_DESIGN_PHILOSOPHY.md](../docs/RIVAL_GAME_INTENT_AND_DESIGN_PHILOSOPHY.md).

- Preserve the core loop: RIVAL reads repeated player habits, and the player can
  respond by changing strategy.
- Treat reinforcement learning as a possible future implementation technique,
  not the product identity. The current iOS app is a rule-and-statistics-based
  adaptive AI, not a reinforcement-learning runtime.
- Do not solve difficulty by silently inflating enemy health, damage, or hidden
  player penalties. Favor readable tactical responses under shared combat rules.
- Keep technical AI language out of player-facing fight UI. Communicate the
  rival relationship through boxing behavior, short corner reports, feedback,
  and presentation.
- Preserve the approved boxer and arena/map designs unless the request explicitly
  asks to redesign them. Favor a simple but premium UI: matte solid surfaces,
  restrained contrast, and meaningful interaction feedback over decorative
  complexity. Do not add color gradients to real-time combat controls.

## Truthfulness And Scope

- Distinguish developer intent, implemented behavior, unverified player impact,
  and backlog work in code comments, documentation, and reports.
- When an existing implementation conflicts with the philosophy document, state
  the conflict clearly and either align the code or revise the document with a
  factual explanation.
- For RIVAL work, modify the iOS implementation by default. Do not change the
  web, desktop, C++, or Godot variants unless the request explicitly includes them.

## Validation And Approval

- For combat or AI changes, add focused regression tests for the changed
  behavior and run an iPhone SDK build.
- For touch, haptic, animation, camera, or visual changes, validate on a real
  iPhone when available and report what was and was not directly observed.
- Keep changes staged. Complete one approved experience slice, validate it, and
  obtain user play feedback before expanding into the next large slice.
