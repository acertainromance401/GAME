(() => {
  "use strict";

  const canvas = document.getElementById("gameCanvas");
  const ctx = canvas.getContext("2d", { alpha: false });
  const WIDTH = canvas.width;
  const HEIGHT = canvas.height;
  const ROUND_SECONDS = 45;
  const RING = { left: 118, right: 842, top: 150, bottom: 520 };
  const PLAYER_COLOR = "#57c8dc";
  const ENEMY_COLOR = "#ef5b62";
  const ATTACK_NAMES = [
    "jab", "cross", "left_body", "right_body",
    "left_hook", "right_hook", "left_uppercut", "right_uppercut",
  ];

  const ATTACKS = {
    jab:            { dur: 0.24, activeA: 0.08, activeB: 0.15, damage: 6,  range: 78, angle: 26, cost: 13, zone: "head", family: "straight", hand: "lead" },
    cross:          { dur: 0.34, activeA: 0.14, activeB: 0.24, damage: 11, range: 60, angle: 20, cost: 18, zone: "head", family: "straight", hand: "rear" },
    left_body:      { dur: 0.32, activeA: 0.12, activeB: 0.22, damage: 9,  range: 54, angle: 40, cost: 16, zone: "body", family: "body", hand: "lead" },
    right_body:     { dur: 0.35, activeA: 0.14, activeB: 0.24, damage: 10, range: 56, angle: 38, cost: 17, zone: "body", family: "body", hand: "rear" },
    left_hook:      { dur: 0.36, activeA: 0.16, activeB: 0.26, damage: 11, range: 50, angle: 56, cost: 18, zone: "head", family: "hook", hand: "lead" },
    right_hook:     { dur: 0.38, activeA: 0.17, activeB: 0.28, damage: 12, range: 52, angle: 50, cost: 19, zone: "head", family: "hook", hand: "rear" },
    left_uppercut:  { dur: 0.40, activeA: 0.18, activeB: 0.30, damage: 13, range: 44, angle: 26, cost: 20, zone: "head", family: "uppercut", hand: "lead" },
    right_uppercut: { dur: 0.42, activeA: 0.19, activeB: 0.31, damage: 14, range: 46, angle: 24, cost: 21, zone: "head", family: "uppercut", hand: "rear" },
  };

  const DUCK_EVADE = {
    jab: "right",
    left_hook: "right",
    left_uppercut: "right",
    cross: "left",
    right_hook: "left",
    right_uppercut: "left",
  };

  const LABELS = {
    jab: "JAB",
    cross: "CROSS",
    left_body: "LEFT BODY",
    right_body: "RIGHT BODY",
    left_hook: "LEFT HOOK",
    right_hook: "RIGHT HOOK",
    left_uppercut: "LEFT UPPERCUT",
    right_uppercut: "RIGHT UPPERCUT",
  };

  const ui = Object.fromEntries([
    "roundLabel", "timerLabel", "aiReadLabel", "playerHpText", "enemyHpText",
    "playerHpBar", "enemyHpBar", "playerStaminaBar", "enemyStaminaBar",
    "playerScore", "enemyScore", "fightOverlay", "overlayKicker", "overlayTitle",
    "overlayText", "overlayButton", "impactMessage", "modelLabel", "exchangeLabel",
    "statusLabel", "soundButton", "pauseButton", "resetLearningButton",
  ].map((id) => [id, document.getElementById(id)]));

  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
  const length = (x, y) => Math.hypot(x, y);
  const normalize = (x, y) => {
    const magnitude = length(x, y) || 1;
    return { x: x / magnitude, y: y / magnitude };
  };
  const lerp = (start, end, amount) => start + (end - start) * amount;

  function makeHabitMemory() {
    return {
      attacks: Object.fromEntries(ATTACK_NAMES.map((name) => [name, 0])),
      guard: 0,
      duckLeft: 0,
      duckRight: 0,
      backstep: 0,
      pressure: 0,
      retreat: 0,
      samples: 0,
      recentAttack: "",
      repeatStreak: 0,
    };
  }

  function loadHabitMemory() {
    try {
      const stored = JSON.parse(localStorage.getItem("pixelBoxingHabitMemory") || "null");
      const fresh = makeHabitMemory();
      if (!stored || typeof stored !== "object") return fresh;
      for (const name of ATTACK_NAMES) fresh.attacks[name] = Number(stored.attacks?.[name]) || 0;
      for (const key of ["guard", "duckLeft", "duckRight", "backstep", "pressure", "retreat", "samples"]) {
        fresh[key] = Number(stored[key]) || 0;
      }
      fresh.recentAttack = ATTACK_NAMES.includes(stored.recentAttack) ? stored.recentAttack : "";
      fresh.repeatStreak = Number(stored.repeatStreak) || 0;
      return fresh;
    } catch {
      return makeHabitMemory();
    }
  }

  function saveHabitMemory() {
    try {
      localStorage.setItem("pixelBoxingHabitMemory", JSON.stringify(game.habits));
    } catch {
      // Storage can be disabled in private browsing; the current session still learns.
    }
  }

  function makeFighter(name, x, y, color) {
    return {
      name,
      x,
      y,
      vx: 0,
      vy: 0,
      facingX: name === "player" ? 1 : -1,
      facingY: 0,
      color,
      hp: 100,
      stamina: 100,
      action: "idle",
      actionTime: 0,
      actionSpec: null,
      acted: false,
      whiffed: false,
      exposed: 0,
      stagger: 0,
      invuln: 0,
      exhausted: 0,
      defense: "none",
      defenseTime: 0,
      aiTimer: 0,
      hitReaction: 0,
      hitKind: "",
      knockedOut: false,
      knockdown: 0,
      streakAction: "",
      streakCount: 0,
      animTime: 0,
    };
  }

  const game = {
    state: "intro",
    round: 1,
    time: ROUND_SECONDS,
    playerScore: 0,
    enemyScore: 0,
    player: makeFighter("player", 330, 350, PLAYER_COLOR),
    enemy: makeFighter("enemy", 630, 310, ENEMY_COLOR),
    habits: loadHabitMemory(),
    held: new Set(),
    keyDown: new Set(),
    particles: [],
    shake: 0,
    hitstop: 0,
    lastTimestamp: 0,
    soundEnabled: true,
    audioContext: null,
    overlayAction: "start",
    status: "READY",
    exchange: "거리를 만들고 첫 선택을 보여주세요",
  };

  function snapshotHabits() {
    const attackTotal = Math.max(1, Object.values(game.habits.attacks).reduce((sum, value) => sum + value, 0));
    const sampleTotal = Math.max(1, game.habits.samples);
    const favoriteAttack = ATTACK_NAMES.reduce((best, name) => (
      game.habits.attacks[name] > game.habits.attacks[best] ? name : best
    ), "jab");
    return {
      favoriteAttack,
      jabRatio: game.habits.attacks.jab / attackTotal,
      bodyRatio: (game.habits.attacks.left_body + game.habits.attacks.right_body) / attackTotal,
      hookRatio: (game.habits.attacks.left_hook + game.habits.attacks.right_hook) / attackTotal,
      guardRatio: game.habits.guard / sampleTotal,
      duckLeftRatio: game.habits.duckLeft / sampleTotal,
      duckRightRatio: game.habits.duckRight / sampleTotal,
      backstepRatio: game.habits.backstep / sampleTotal,
      pressureRatio: game.habits.pressure / sampleTotal,
      retreatRatio: game.habits.retreat / sampleTotal,
      repeatStreak: game.habits.repeatStreak,
      sampleStrength: Math.min(1, sampleTotal / 18),
    };
  }

  function adaptationLevel() {
    const snapshot = snapshotHabits();
    return clamp(0.18 + 0.16 * Math.max(0, game.round - 1) + 0.58 * snapshot.sampleStrength, 0.18, 1);
  }

  function notePlayerAttack(action) {
    game.habits.attacks[action] += 1;
    if (game.habits.recentAttack === action) {
      game.habits.repeatStreak += 1;
    } else {
      game.habits.recentAttack = action;
      game.habits.repeatStreak = 1;
    }
    saveHabitMemory();
  }

  function samplePlayerHabits(dt, forwardAxis) {
    const sample = Math.max(0, dt * 8);
    game.habits.samples += sample;
    if (game.player.defense === "guard") game.habits.guard += sample;
    if (game.player.defense === "duck_left") game.habits.duckLeft += sample;
    if (game.player.defense === "duck_right") game.habits.duckRight += sample;
    if (game.player.defense === "backstep") game.habits.backstep += sample;
    if (forwardAxis > 0) game.habits.pressure += sample * forwardAxis;
    if (forwardAxis < 0) game.habits.retreat += sample * -forwardAxis;
  }

  function describeModel() {
    const snapshot = snapshotHabits();
    if (snapshot.sampleStrength < 0.12) return "행동 표본 수집 중";
    const traits = [
      [snapshot.guardRatio, "가드 의존"],
      [snapshot.duckLeftRatio, "왼쪽 더킹"],
      [snapshot.duckRightRatio, "오른쪽 더킹"],
      [snapshot.backstepRatio, "백스텝"],
      [snapshot.pressureRatio, "전진 압박"],
      [snapshot.retreatRatio, "후퇴 성향"],
    ].sort((a, b) => b[0] - a[0]);
    if (traits[0][0] > 0.14) return `${traits[0][1]} 분석 · ${LABELS[snapshot.favoriteAttack]} 추적`;
    return `${LABELS[snapshot.favoriteAttack]} 반복 패턴 추적`;
  }

  function resetFighters() {
    game.player = makeFighter("player", 340, 360, PLAYER_COLOR);
    game.enemy = makeFighter("enemy", 620, 300, ENEMY_COLOR);
    game.time = ROUND_SECONDS;
    game.particles.length = 0;
    game.shake = 0;
    game.hitstop = 0;
  }

  function showOverlay(kicker, title, text, button, action) {
    ui.overlayKicker.textContent = kicker;
    ui.overlayTitle.textContent = title;
    ui.overlayText.textContent = text;
    ui.overlayButton.textContent = button;
    ui.fightOverlay.classList.add("is-visible");
    game.overlayAction = action;
  }

  function hideOverlay() {
    ui.fightOverlay.classList.remove("is-visible");
    canvas.focus();
  }

  function startRound() {
    resetFighters();
    game.state = "fight";
    game.status = "FIGHT";
    game.exchange = `라운드 ${game.round}. AI 적응도 ${Math.round(adaptationLevel() * 100)}%`;
    hideOverlay();
    playTone("bell");
  }

  function newSession() {
    game.round = 1;
    game.playerScore = 0;
    game.enemyScore = 0;
    startRound();
  }

  function finishRound(winner, reason) {
    if (game.state !== "fight") return;
    game.state = "round_break";
    game.status = reason;
    if (winner === "player") game.playerScore += 1;
    if (winner === "enemy") game.enemyScore += 1;
    saveHabitMemory();
    playTone(reason === "KO" ? "ko" : "bell");

    const completedRound = game.round;
    const result = winner === "player" ? "PLAYER WINS" : winner === "enemy" ? "RIVAL WINS" : "DRAW";
    game.exchange = `${result} · ${reason}`;
    window.setTimeout(() => {
      if (game.state !== "round_break") return;
      game.round += 1;
      showOverlay(
        `ROUND ${completedRound} · ${reason}`,
        result,
        `AI는 이전 라운드의 행동을 유지합니다. 다음 적응도 ${Math.round(adaptationLevel() * 100)}%. 같은 습관은 더 강하게 공략당합니다.`,
        "NEXT ROUND",
        "next",
      );
    }, reason === "KO" ? 1050 : 350);
  }

  function triggerImpact(text) {
    ui.impactMessage.textContent = text;
    ui.impactMessage.classList.remove("is-visible");
    void ui.impactMessage.offsetWidth;
    ui.impactMessage.classList.add("is-visible");
  }

  function playTone(kind) {
    if (!game.soundEnabled) return;
    try {
      game.audioContext ||= new (window.AudioContext || window.webkitAudioContext)();
      const oscillator = game.audioContext.createOscillator();
      const gain = game.audioContext.createGain();
      const now = game.audioContext.currentTime;
      const settings = {
        light: [180, 0.045, 0.05],
        heavy: [105, 0.085, 0.08],
        block: [260, 0.035, 0.035],
        evade: [520, 0.05, 0.03],
        bell: [760, 0.18, 0.045],
        ko: [78, 0.34, 0.1],
      }[kind] || [180, 0.05, 0.04];
      oscillator.type = kind === "bell" ? "sine" : "triangle";
      oscillator.frequency.setValueAtTime(settings[0], now);
      gain.gain.setValueAtTime(settings[2], now);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + settings[1]);
      oscillator.connect(gain).connect(game.audioContext.destination);
      oscillator.start(now);
      oscillator.stop(now + settings[1]);
    } catch {
      game.soundEnabled = false;
    }
  }

  function canAct(fighter) {
    return game.state === "fight"
      && !fighter.knockedOut
      && fighter.action === "idle"
      && fighter.stagger <= 0
      && fighter.exhausted <= 0;
  }

  function startAttack(fighter, action) {
    const spec = ATTACKS[action];
    if (!spec || !canAct(fighter) || fighter.stamina < spec.cost) return false;
    fighter.action = action;
    fighter.actionTime = 0;
    fighter.actionSpec = spec;
    fighter.acted = false;
    fighter.whiffed = false;
    fighter.defense = "none";
    fighter.stamina = clamp(fighter.stamina - spec.cost, 0, 100);
    if (fighter.stamina === 0) {
      fighter.exhausted = 1.1;
      fighter.exposed = Math.max(fighter.exposed, 0.28);
    }
    if (fighter.streakAction === action) fighter.streakCount += 1;
    else {
      fighter.streakAction = action;
      fighter.streakCount = 1;
    }
    if (fighter.name === "player") notePlayerAttack(action);
    return true;
  }

  function startDefense(fighter, defense) {
    if (!canAct(fighter)) return false;
    const cost = defense === "backstep" ? 31 : 17;
    if (defense !== "guard" && fighter.stamina < cost) return false;
    fighter.defense = defense;
    fighter.defenseTime = defense === "backstep" ? 0.28 : 0.34;
    if (defense !== "guard") fighter.stamina = clamp(fighter.stamina - cost, 0, 100);
    if (defense === "backstep") fighter.invuln = 0.2;
    return true;
  }

  function performPlayerAction(action) {
    if (ATTACKS[action]) startAttack(game.player, action);
    else startDefense(game.player, action);
    canvas.focus();
  }

  function updateFacing(fighter, target) {
    const direction = normalize(target.x - fighter.x, target.y - fighter.y);
    fighter.facingX = direction.x;
    fighter.facingY = direction.y;
  }

  function hitGeometry(attacker, defender, spec) {
    const dx = defender.x - attacker.x;
    const dy = defender.y - attacker.y;
    const distance = length(dx, dy);
    if (distance > spec.range + 24) return false;
    const direction = normalize(dx, dy);
    const dot = clamp(attacker.facingX * direction.x + attacker.facingY * direction.y, -1, 1);
    return Math.acos(dot) * 180 / Math.PI <= spec.angle;
  }

  function spawnHitParticles(defender, color, count) {
    for (let index = 0; index < count; index += 1) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 35 + Math.random() * 80;
      game.particles.push({
        x: defender.x,
        y: defender.y - 38,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed - 25,
        life: 0.3 + Math.random() * 0.22,
        maxLife: 0.52,
        color,
      });
    }
  }

  function resolveHit(attacker, defender) {
    const action = attacker.action;
    const spec = attacker.actionSpec;
    if (!spec || !hitGeometry(attacker, defender, spec)) return false;

    if (defender.invuln > 0) {
      attacker.acted = true;
      attacker.exposed = Math.max(attacker.exposed, 0.27);
      game.exchange = `${defender.name === "player" ? "PLAYER" : "RIVAL"} BACKSTEP EVADE`;
      triggerImpact("EVADE");
      playTone("evade");
      return true;
    }

    const duckNeeded = DUCK_EVADE[action];
    const duckSide = defender.defense === "duck_left" ? "left" : defender.defense === "duck_right" ? "right" : "";
    if (spec.zone === "head" && duckNeeded && duckSide === duckNeeded) {
      attacker.acted = true;
      attacker.exposed = Math.max(attacker.exposed, 0.27);
      game.exchange = `${defender.name === "player" ? "PLAYER" : "RIVAL"} ${duckSide.toUpperCase()} DUCK`;
      triggerImpact("CLEAN DUCK");
      playTone("evade");
      return true;
    }

    const guarding = defender.defense === "guard";
    const counter = defender.exposed > 0;
    const staleCount = Math.max(0, attacker.streakCount - 2);
    const staleMultiplier = Math.max(0.5, Math.pow(0.85, staleCount));
    let damage = spec.damage * staleMultiplier;
    if (counter) damage *= spec.family === "body" || spec.family === "hook" ? 1.68 : 1.4;
    if (guarding) damage *= 0.4;
    damage = Math.max(1, Math.round(damage));

    defender.hp = clamp(defender.hp - damage, 0, 100);
    defender.hitReaction = guarding ? 0.15 : 0.28;
    defender.hitKind = spec.family;
    defender.stagger = guarding ? 0.06 : 0.16;
    defender.action = "idle";
    defender.actionSpec = null;
    attacker.acted = true;
    game.hitstop = guarding ? 0.035 : 0.065 + damage * 0.002;
    game.shake = Math.max(game.shake, guarding ? 3 : 4 + damage * 0.28);
    spawnHitParticles(defender, guarding ? "#e7bd57" : attacker.color, guarding ? 4 : 7);

    const result = guarding ? "BLOCK" : counter ? "COUNTER" : LABELS[action];
    triggerImpact(`${result}  ${damage}`);
    game.exchange = `${attacker.name === "player" ? "PLAYER" : "RIVAL"} · ${result} · ${damage} DAMAGE`;
    playTone(guarding ? "block" : damage >= 12 ? "heavy" : "light");

    if (defender.hp <= 0) {
      defender.knockedOut = true;
      defender.knockdown = 0;
      finishRound(attacker.name, "KO");
    }
    return true;
  }

  function updateFighterTimers(fighter, target, dt) {
    fighter.animTime += dt;
    fighter.stamina = clamp(fighter.stamina + dt * 8.5, 0, 100);
    fighter.invuln = Math.max(0, fighter.invuln - dt);
    fighter.exhausted = Math.max(0, fighter.exhausted - dt);
    fighter.exposed = Math.max(0, fighter.exposed - dt);
    fighter.stagger = Math.max(0, fighter.stagger - dt);
    fighter.hitReaction = Math.max(0, fighter.hitReaction - dt);
    fighter.defenseTime = Math.max(0, fighter.defenseTime - dt);

    if (fighter.knockedOut) {
      fighter.knockdown = clamp(fighter.knockdown + dt / 0.9, 0, 1);
      return;
    }

    if (fighter.actionSpec) {
      fighter.actionTime += dt;
      if (!fighter.acted && !fighter.whiffed && fighter.actionTime >= fighter.actionSpec.activeA && fighter.actionTime <= fighter.actionSpec.activeB) {
        resolveHit(fighter, target);
      }
      if (fighter.actionTime >= fighter.actionSpec.dur) {
        if (!fighter.acted && !fighter.whiffed) {
          fighter.whiffed = true;
          fighter.exposed = Math.max(fighter.exposed, 0.27);
          if (fighter.name === "player") triggerImpact("OFF BALANCE");
        } else if (!fighter.whiffed || fighter.actionTime >= fighter.actionSpec.dur + 0.22) {
          fighter.action = "idle";
          fighter.actionTime = 0;
          fighter.actionSpec = null;
          fighter.acted = false;
        }
      }
    }

    if (fighter.defense !== "guard" && fighter.defenseTime <= 0) fighter.defense = "none";
    updateFacing(fighter, target);
  }

  function clampToRing(fighter) {
    fighter.x = clamp(fighter.x, RING.left + 38, RING.right - 38);
    fighter.y = clamp(fighter.y, RING.top + 54, RING.bottom - 28);
  }

  function updatePlayerMovement(dt) {
    const player = game.player;
    const target = game.enemy;
    let forwardAxis = 0;
    let sideAxis = 0;
    if (game.keyDown.has("arrowup") || game.held.has("up")) forwardAxis += 1;
    if (game.keyDown.has("arrowdown") || game.held.has("down")) forwardAxis -= 1;
    if (game.keyDown.has("arrowleft") || game.held.has("left")) sideAxis -= 1;
    if (game.keyDown.has("arrowright") || game.held.has("right")) sideAxis += 1;

    const facing = normalize(target.x - player.x, target.y - player.y);
    const side = { x: -facing.y, y: facing.x };
    let moveX = facing.x * forwardAxis + side.x * sideAxis;
    let moveY = facing.y * forwardAxis + side.y * sideAxis;
    const moveLength = length(moveX, moveY);
    if (moveLength > 1) {
      moveX /= moveLength;
      moveY /= moveLength;
    }

    if (player.defense === "backstep") {
      moveX = -facing.x * 1.6;
      moveY = -facing.y * 1.6;
    }
    if (player.defense === "duck_left") {
      moveX += -side.x * 0.65;
      moveY += -side.y * 0.65;
    }
    if (player.defense === "duck_right") {
      moveX += side.x * 0.65;
      moveY += side.y * 0.65;
    }

    const canMove = !player.knockedOut && player.stagger <= 0 && player.exhausted <= 0 && !player.actionSpec;
    if (canMove) {
      const speed = player.defense === "guard" ? 62 : 145;
      player.x += moveX * speed * dt;
      player.y += moveY * speed * dt;
      clampToRing(player);
    }
    samplePlayerHabits(dt, forwardAxis);
    return forwardAxis;
  }

  function weightedChoice(weights) {
    const entries = Object.entries(weights).filter(([, weight]) => weight > 0);
    let pick = Math.random() * entries.reduce((sum, [, weight]) => sum + weight, 0);
    for (const [name, weight] of entries) {
      pick -= weight;
      if (pick <= 0) return name;
    }
    return entries.at(-1)?.[0] || "wait";
  }

  function enemyWeights(distance) {
    const snapshot = snapshotHabits();
    const adapt = adaptationLevel();
    const weights = {
      jab: 0.1, cross: 0.1, left_body: 0.08, right_body: 0.08,
      left_hook: 0.08, right_hook: 0.08, left_uppercut: 0.06, right_uppercut: 0.06,
      dodge_left: 0.04, dodge_right: 0.04, dodge_back: 0.04,
      wait: Math.max(0.05, 0.34 - 0.16 * adapt),
    };
    if (distance > 115) {
      weights.jab += 1.55;
      weights.cross += 0.45;
    } else if (distance > 78) {
      weights.jab += 1;
      weights.cross += 0.95;
      weights.left_hook += 0.35;
      weights.right_hook += 0.55;
      weights.dodge_left += 0.22;
      weights.dodge_right += 0.22;
    } else {
      weights.left_body += 0.95;
      weights.right_body += 1.15;
      weights.left_hook += 0.8;
      weights.right_hook += 0.95;
      weights.left_uppercut += 0.45;
      weights.right_uppercut += 0.65;
      weights.dodge_back += 0.28;
    }
    if (snapshot.guardRatio > 0.22) {
      weights.left_body += 0.95 * adapt;
      weights.right_body += 1.2 * adapt;
    }
    if (snapshot.duckRightRatio > 0.16) {
      weights.cross += 1.05 * adapt;
      weights.right_hook += 0.95 * adapt;
      weights.right_uppercut += 0.7 * adapt;
    }
    if (snapshot.duckLeftRatio > 0.16) {
      weights.jab += 0.85 * adapt;
      weights.left_hook += 0.8 * adapt;
      weights.left_uppercut += 0.6 * adapt;
    }
    if (snapshot.jabRatio > 0.34 || snapshot.favoriteAttack === "jab") {
      weights.cross += 0.9 * adapt;
      weights.right_hook += 0.55 * adapt;
      weights.dodge_right += 0.35 * adapt;
    }
    if (snapshot.bodyRatio > 0.3) {
      weights.left_uppercut += 0.45 * adapt;
      weights.right_uppercut += 0.7 * adapt;
    }
    if (snapshot.pressureRatio > 0.2) {
      weights.dodge_back += 0.75 * adapt;
      weights.right_hook += 0.55 * adapt;
      weights.left_hook += 0.45 * adapt;
    }
    if (snapshot.backstepRatio > 0.14 || snapshot.retreatRatio > 0.18) {
      weights.jab += 0.7 * adapt;
      weights.cross += 0.45 * adapt;
      weights.wait *= 0.8;
    }
    if (snapshot.repeatStreak >= 3) {
      weights.dodge_left += 0.35 * adapt;
      weights.dodge_right += 0.35 * adapt;
    }
    if (game.player.exposed > 0) {
      weights.cross += 1.8;
      weights.right_uppercut += 1.4;
      weights.right_hook += 0.9;
      weights.wait = 0.05;
    }
    return weights;
  }

  function updateEnemy(dt) {
    const enemy = game.enemy;
    const player = game.player;
    if (enemy.knockedOut || enemy.stagger > 0 || enemy.exhausted > 0) return;
    enemy.aiTimer = Math.max(0, enemy.aiTimer - dt);
    const dx = player.x - enemy.x;
    const dy = player.y - enemy.y;
    const distance = length(dx, dy);
    const facing = normalize(dx, dy);
    const side = { x: -facing.y, y: facing.x };

    if (!enemy.actionSpec && enemy.defense === "none" && distance > 105) {
      const weave = Math.sin(enemy.animTime * 1.7) * 0.28;
      enemy.x += (facing.x + side.x * weave) * 126 * dt;
      enemy.y += (facing.y + side.y * weave) * 126 * dt;
      clampToRing(enemy);
    }

    if (!canAct(enemy) || enemy.aiTimer > 0) return;
    const cooldownScale = 1 + 0.16 * (game.round - 1) + 0.32 * adaptationLevel();
    enemy.aiTimer = (0.13 + Math.random() * 0.18) / cooldownScale;
    if (distance > 148 && game.player.exposed <= 0) return;

    const option = weightedChoice(enemyWeights(distance));
    if (option === "dodge_left") startDefense(enemy, "duck_left");
    else if (option === "dodge_right") startDefense(enemy, "duck_right");
    else if (option === "dodge_back") startDefense(enemy, "backstep");
    else if (option !== "wait") startAttack(enemy, option);
  }

  function updateDefenseFromKeys() {
    const player = game.player;
    if (player.actionSpec || player.stagger > 0 || player.exhausted > 0 || player.knockedOut) return;
    if (game.keyDown.has("w") || game.held.has("guard")) {
      player.defense = "guard";
      player.defenseTime = 0.1;
      return;
    }
    if (game.keyDown.has("q")) {
      player.defense = "duck_left";
      player.defenseTime = 0.1;
      return;
    }
    if (game.keyDown.has("e")) {
      player.defense = "duck_right";
      player.defenseTime = 0.1;
      return;
    }
    if (player.defense === "guard" || player.defense === "duck_left" || player.defense === "duck_right") {
      if (player.defenseTime <= 0) player.defense = "none";
    }
  }

  function updateParticles(dt) {
    for (const particle of game.particles) {
      particle.x += particle.vx * dt;
      particle.y += particle.vy * dt;
      particle.vy += 150 * dt;
      particle.life -= dt;
    }
    game.particles = game.particles.filter((particle) => particle.life > 0);
  }

  function update(dt) {
    if (game.state !== "fight") {
      updateFighterTimers(game.player, game.enemy, dt);
      updateFighterTimers(game.enemy, game.player, dt);
      updateParticles(dt);
      return;
    }
    if (game.hitstop > 0) {
      game.hitstop = Math.max(0, game.hitstop - dt);
      dt *= 0.12;
    }

    updateDefenseFromKeys();
    updatePlayerMovement(dt);
    updateEnemy(dt);
    updateFighterTimers(game.player, game.enemy, dt);
    updateFighterTimers(game.enemy, game.player, dt);
    updateParticles(dt);
    game.shake = Math.max(0, game.shake - dt * 30);
    game.time = Math.max(0, game.time - dt);

    if (game.time <= 0) {
      const winner = game.player.hp === game.enemy.hp ? "draw" : game.player.hp > game.enemy.hp ? "player" : "enemy";
      finishRound(winner, "TIME");
    }
  }

  function drawAudience() {
    ctx.fillStyle = "#07090d";
    ctx.fillRect(0, 0, WIDTH, HEIGHT);
    ctx.fillStyle = "#111721";
    ctx.fillRect(0, 64, WIDTH, 150);
    for (let row = 0; row < 4; row += 1) {
      for (let column = 0; column < 34; column += 1) {
        const x = 12 + column * 29 + (row % 2) * 8;
        const y = 82 + row * 29 + ((column * 7) % 9);
        const colors = ["#27323e", "#4a3440", "#2d4140", "#4b4530"];
        ctx.strokeStyle = colors[(column + row) % colors.length];
        ctx.lineWidth = 7;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.moveTo(x, y);
        ctx.lineTo(x, y + 12);
        ctx.stroke();
      }
    }
    ctx.fillStyle = "#d7b754";
    for (let index = 0; index < 8; index += 1) ctx.fillRect(64 + index * 119, 36 + (index % 2) * 5, 7, 7);
  }

  function drawArena() {
    drawAudience();
    const gradient = ctx.createLinearGradient(0, RING.top, 0, RING.bottom + 60);
    gradient.addColorStop(0, "#273443");
    gradient.addColorStop(0.55, "#53636d");
    gradient.addColorStop(1, "#303c48");
    ctx.fillStyle = "#0e141c";
    ctx.beginPath();
    ctx.moveTo(RING.left - 26, RING.top + 12);
    ctx.lineTo(RING.right + 26, RING.top + 12);
    ctx.lineTo(RING.right + 54, RING.bottom + 34);
    ctx.lineTo(RING.left - 54, RING.bottom + 34);
    ctx.closePath();
    ctx.fill();
    ctx.strokeStyle = "#607080";
    ctx.lineWidth = 3;
    ctx.fillStyle = gradient;
    ctx.fillRect(RING.left, RING.top, RING.right - RING.left, RING.bottom - RING.top);
    ctx.strokeRect(RING.left, RING.top, RING.right - RING.left, RING.bottom - RING.top);

    ctx.strokeStyle = "rgba(239, 240, 233, 0.09)";
    ctx.lineWidth = 1;
    for (let x = RING.left + 60; x < RING.right; x += 60) {
      ctx.beginPath();
      ctx.moveTo(x, RING.top);
      ctx.lineTo(x, RING.bottom);
      ctx.stroke();
    }
    for (let y = RING.top + 50; y < RING.bottom; y += 50) {
      ctx.beginPath();
      ctx.moveTo(RING.left, y);
      ctx.lineTo(RING.right, y);
      ctx.stroke();
    }

    ctx.strokeStyle = "rgba(231, 189, 87, 0.42)";
    ctx.lineWidth = 5;
    ctx.beginPath();
    ctx.arc(WIDTH / 2, 345, 72, 0, Math.PI * 2);
    ctx.stroke();
    ctx.fillStyle = "rgba(11, 15, 20, 0.34)";
    ctx.font = "900 28px 'Avenir Next Condensed', sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("ADAPT", WIDTH / 2, 354);

    const ropeColors = ["#ece9df", "#e7bd57", "#9f2f3f"];
    for (let index = 0; index < 3; index += 1) {
      const offset = 20 + index * 14;
      ctx.strokeStyle = ropeColors[index];
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.moveTo(RING.left, RING.top - offset);
      ctx.lineTo(RING.right, RING.top - offset);
      ctx.stroke();
    }
    ctx.fillStyle = "#d2b253";
    ctx.fillRect(RING.left - 7, RING.top - 54, 14, 76);
    ctx.fillStyle = "#9f2f3f";
    ctx.fillRect(RING.right - 7, RING.top - 54, 14, 76);
  }

  function attackPose(fighter) {
    const spec = fighter.actionSpec;
    if (!spec) return { extension: 0, side: 0, lift: 0, crouch: 0 };
    const phase = clamp(fighter.actionTime / spec.dur, 0, 1);
    const peak = spec.activeA / spec.dur + 0.12;
    const extension = phase < peak ? clamp(phase / peak, 0, 1) : clamp(1 - (phase - peak) / Math.max(0.12, 1 - peak), 0, 1);
    const sideSign = spec.hand === "lead" ? -1 : 1;
    if (spec.family === "hook") return { extension: extension * 0.72, side: sideSign * (1 - extension) * 22 - sideSign * extension * 11, lift: -4, crouch: 0 };
    if (spec.family === "uppercut") return { extension: extension * 0.6, side: sideSign * 7, lift: -extension * 28, crouch: (1 - extension) * 10 };
    if (spec.family === "body") return { extension: extension * 0.75, side: sideSign * 6, lift: 12, crouch: 10 };
    return { extension, side: sideSign * 4, lift: 0, crouch: 0 };
  }

  function drawLimb(from, to, width, color, outline = "#11141a") {
    ctx.lineCap = "round";
    ctx.strokeStyle = outline;
    ctx.lineWidth = width + 5;
    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    ctx.stroke();
    ctx.strokeStyle = color;
    ctx.lineWidth = width;
    ctx.stroke();
  }

  function drawFighter(fighter) {
    const scale = lerp(0.88, 1.12, (fighter.y - RING.top) / (RING.bottom - RING.top));
    const facing = normalize(fighter.facingX, fighter.facingY);
    const side = { x: -facing.y, y: facing.x };
    const pose = attackPose(fighter);
    const hit = fighter.hitReaction > 0 ? fighter.hitReaction / 0.28 : 0;
    const duck = fighter.defense === "duck_left" || fighter.defense === "duck_right" ? 12 : 0;
    const guard = fighter.defense === "guard" ? 1 : 0;
    const crouch = pose.crouch + duck;
    const bob = Math.sin(fighter.animTime * 5.5) * 1.6;

    ctx.save();
    if (game.shake > 0) ctx.translate((Math.random() - 0.5) * game.shake, (Math.random() - 0.5) * game.shake * 0.6);

    ctx.fillStyle = "rgba(0, 0, 0, 0.34)";
    ctx.beginPath();
    ctx.ellipse(fighter.x, fighter.y + 18 * scale, 25 * scale, 8 * scale, 0, 0, Math.PI * 2);
    ctx.fill();

    if (fighter.knockedOut) {
      const fall = fighter.knockdown * fighter.knockdown * (3 - 2 * fighter.knockdown);
      ctx.translate(fighter.x, fighter.y - 8 * scale);
      ctx.rotate((fighter.name === "player" ? 1 : -1) * fall * 1.42);
      ctx.translate(-fighter.x, -fighter.y + 8 * scale);
    }

    const hip = { x: fighter.x - facing.x * hit * 7, y: fighter.y - (13 - crouch * 0.35) * scale + bob };
    const chest = { x: hip.x + facing.x * (2 - hit * 8), y: hip.y - (31 - crouch * 0.45) * scale };
    const head = { x: chest.x + facing.x * (3 - hit * 7), y: chest.y - 27 * scale };
    const leadShoulder = { x: chest.x - side.x * 10 * scale, y: chest.y - side.y * 5 * scale };
    const rearShoulder = { x: chest.x + side.x * 10 * scale, y: chest.y + side.y * 5 * scale };
    const leadHip = { x: hip.x - side.x * 7 * scale, y: hip.y - side.y * 4 * scale };
    const rearHip = { x: hip.x + side.x * 7 * scale, y: hip.y + side.y * 4 * scale };

    const leadFoot = { x: hip.x - facing.x * 6 * scale - side.x * 13 * scale, y: fighter.y + 13 * scale - side.y * 4 * scale };
    const rearFoot = { x: hip.x + facing.x * 8 * scale + side.x * 13 * scale, y: fighter.y + 15 * scale + side.y * 4 * scale };
    const leadKnee = { x: (leadHip.x + leadFoot.x) / 2 - facing.x * crouch * 0.25, y: (leadHip.y + leadFoot.y) / 2 + crouch * 0.2 };
    const rearKnee = { x: (rearHip.x + rearFoot.x) / 2 + facing.x * crouch * 0.2, y: (rearHip.y + rearFoot.y) / 2 + crouch * 0.22 };
    drawLimb(leadHip, leadKnee, 10 * scale, "#d1a582");
    drawLimb(leadKnee, leadFoot, 8 * scale, "#d1a582");
    drawLimb(rearHip, rearKnee, 10 * scale, "#bc8e70");
    drawLimb(rearKnee, rearFoot, 8 * scale, "#bc8e70");
    drawLimb({ x: leadFoot.x - facing.x * 4, y: leadFoot.y }, { x: leadFoot.x + facing.x * 9, y: leadFoot.y }, 8 * scale, fighter.color);
    drawLimb({ x: rearFoot.x - facing.x * 4, y: rearFoot.y }, { x: rearFoot.x + facing.x * 9, y: rearFoot.y }, 8 * scale, fighter.color);

    ctx.fillStyle = "#ece9df";
    ctx.strokeStyle = "#11141a";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.moveTo(hip.x - side.x * 12 * scale, hip.y - side.y * 7 * scale - 7 * scale);
    ctx.lineTo(hip.x + side.x * 12 * scale, hip.y + side.y * 7 * scale - 7 * scale);
    ctx.lineTo(hip.x + side.x * 10 * scale, hip.y + side.y * 6 * scale + 9 * scale);
    ctx.lineTo(hip.x - side.x * 10 * scale, hip.y - side.y * 6 * scale + 9 * scale);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.strokeStyle = fighter.color;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.moveTo(hip.x - side.x * 11 * scale, hip.y - side.y * 6 * scale - 5 * scale);
    ctx.lineTo(hip.x + side.x * 11 * scale, hip.y + side.y * 6 * scale - 5 * scale);
    ctx.stroke();

    drawLimb(hip, chest, 24 * scale, "#d1a582");

    const guardLead = { x: head.x + facing.x * 9 * scale - side.x * 8 * scale, y: head.y + 7 * scale };
    const guardRear = { x: head.x + facing.x * 5 * scale + side.x * 9 * scale, y: head.y + 10 * scale };
    let leadHand = guardLead;
    let rearHand = guardRear;
    if (fighter.actionSpec) {
      const hand = fighter.actionSpec.hand;
      const shoulder = hand === "lead" ? leadShoulder : rearShoulder;
      const reach = fighter.actionSpec.range * 0.62 * pose.extension * scale;
      const strikeHand = {
        x: shoulder.x + facing.x * reach + side.x * pose.side * scale,
        y: shoulder.y + facing.y * reach + side.y * pose.side * scale + pose.lift * scale,
      };
      if (hand === "lead") leadHand = strikeHand;
      else rearHand = strikeHand;
    } else if (guard) {
      leadHand = { x: head.x + facing.x * 7 - side.x * 7, y: head.y + 2 };
      rearHand = { x: head.x + facing.x * 7 + side.x * 7, y: head.y + 4 };
    }

    const leadElbow = { x: (leadShoulder.x + leadHand.x) / 2 - side.x * 7 * scale, y: (leadShoulder.y + leadHand.y) / 2 - side.y * 7 * scale };
    const rearElbow = { x: (rearShoulder.x + rearHand.x) / 2 + side.x * 7 * scale, y: (rearShoulder.y + rearHand.y) / 2 + side.y * 7 * scale };
    drawLimb(leadShoulder, leadElbow, 10 * scale, "#d1a582");
    drawLimb(leadElbow, leadHand, 8 * scale, "#d1a582");
    drawLimb(rearShoulder, rearElbow, 10 * scale, "#bc8e70");
    drawLimb(rearElbow, rearHand, 8 * scale, "#bc8e70");

    for (const hand of [leadHand, rearHand]) {
      ctx.fillStyle = fighter.color;
      ctx.strokeStyle = "#11141a";
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.ellipse(hand.x, hand.y, 9 * scale, 7 * scale, Math.atan2(facing.y, facing.x), 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    }

    ctx.fillStyle = fighter.hitReaction > 0 ? "#f5e4d5" : "#d7ad8b";
    ctx.strokeStyle = "#11141a";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(head.x, head.y, 14 * scale, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = "#18191d";
    ctx.beginPath();
    ctx.arc(head.x - facing.x * 4 * scale, head.y - 8 * scale, 10 * scale, Math.PI, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = fighter.color;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.moveTo(head.x - side.x * 11 * scale, head.y - side.y * 6 * scale - 1);
    ctx.lineTo(head.x + side.x * 11 * scale, head.y + side.y * 6 * scale - 1);
    ctx.stroke();

    if (fighter.exposed > 0) {
      ctx.fillStyle = "#e7bd57";
      ctx.font = "900 13px 'Avenir Next Condensed', sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("OPEN", fighter.x, head.y - 27 * scale);
    }
    ctx.restore();
  }

  function drawForegroundRopes() {
    const colors = ["#ece9df", "#e7bd57", "#9f2f3f"];
    for (let index = 0; index < 3; index += 1) {
      const y = RING.bottom + 14 + index * 15;
      ctx.strokeStyle = "#080a0d";
      ctx.lineWidth = 7;
      ctx.beginPath();
      ctx.moveTo(RING.left - 24, y);
      ctx.lineTo(RING.right + 24, y);
      ctx.stroke();
      ctx.strokeStyle = colors[index];
      ctx.lineWidth = 3;
      ctx.stroke();
    }
    ctx.fillStyle = "#d2b253";
    ctx.fillRect(RING.left - 9, RING.bottom - 12, 16, 73);
    ctx.fillStyle = "#9f2f3f";
    ctx.fillRect(RING.right - 7, RING.bottom - 12, 16, 73);
  }

  function drawParticles() {
    for (const particle of game.particles) {
      ctx.globalAlpha = clamp(particle.life / particle.maxLife, 0, 1);
      ctx.fillStyle = particle.color;
      ctx.fillRect(particle.x - 2, particle.y - 2, 4, 4);
    }
    ctx.globalAlpha = 1;
  }

  function render() {
    drawArena();
    const fighters = [game.player, game.enemy].sort((first, second) => first.y - second.y);
    for (const fighter of fighters) drawFighter(fighter);
    drawParticles();
    drawForegroundRopes();
    updateHud();
  }

  function updateHud() {
    const player = game.player;
    const enemy = game.enemy;
    const adapt = Math.round(adaptationLevel() * 100);
    ui.roundLabel.textContent = `ROUND ${game.round}`;
    ui.timerLabel.textContent = String(Math.ceil(game.time)).padStart(2, "0");
    ui.aiReadLabel.textContent = `AI READ ${String(adapt).padStart(3, "0")}%`;
    ui.playerHpText.textContent = Math.ceil(player.hp);
    ui.enemyHpText.textContent = Math.ceil(enemy.hp);
    ui.playerHpBar.style.transform = `scaleX(${player.hp / 100})`;
    ui.enemyHpBar.style.transform = `scaleX(${enemy.hp / 100})`;
    ui.playerStaminaBar.style.transform = `scaleX(${player.stamina / 100})`;
    ui.enemyStaminaBar.style.transform = `scaleX(${enemy.stamina / 100})`;
    ui.playerScore.textContent = game.playerScore;
    ui.enemyScore.textContent = game.enemyScore;
    ui.modelLabel.textContent = describeModel();
    ui.exchangeLabel.textContent = game.exchange;
    ui.statusLabel.textContent = game.state === "paused" ? "PAUSED" : player.exhausted > 0 ? "GASSED" : game.status;
  }

  function frame(timestamp) {
    if (!game.lastTimestamp) game.lastTimestamp = timestamp;
    const dt = Math.min(0.05, Math.max(0, (timestamp - game.lastTimestamp) / 1000));
    game.lastTimestamp = timestamp;
    if (game.state !== "paused") update(dt);
    render();
    window.requestAnimationFrame(frame);
  }

  function selectKeyboardAttack(key) {
    if (key === "a") {
      if (game.keyDown.has("q")) return "left_body";
      if (game.keyDown.has("e")) return "left_hook";
      if (game.keyDown.has("w")) return "left_uppercut";
      return "jab";
    }
    if (key === "d") {
      if (game.keyDown.has("q")) return "right_hook";
      if (game.keyDown.has("e")) return "right_body";
      if (game.keyDown.has("w")) return "right_uppercut";
      return "cross";
    }
    return "";
  }

  function togglePause() {
    if (game.state === "fight") {
      game.state = "paused";
      game.status = "PAUSED";
      showOverlay("BREAK", "일시정지", "AI 학습과 라운드 타이머가 멈췄습니다.", "RESUME", "resume");
    } else if (game.state === "paused") {
      game.state = "fight";
      game.status = "FIGHT";
      hideOverlay();
    }
  }

  window.addEventListener("keydown", (event) => {
    const key = event.key.toLowerCase();
    const controlled = ["arrowup", "arrowdown", "arrowleft", "arrowright", "a", "d", "q", "w", "e", "s", "p", "escape"];
    if (controlled.includes(key)) event.preventDefault();
    if (event.repeat && ["a", "d", "s", "p", "escape"].includes(key)) return;
    game.keyDown.add(key);
    if (key === "a" || key === "d") performPlayerAction(selectKeyboardAttack(key));
    if (key === "s") performPlayerAction("backstep");
    if (key === "p" || key === "escape") togglePause();
  }, { passive: false });

  window.addEventListener("keyup", (event) => {
    game.keyDown.delete(event.key.toLowerCase());
  });

  document.querySelectorAll("[data-action]").forEach((button) => {
    button.addEventListener("click", () => performPlayerAction(button.dataset.action));
  });

  document.querySelectorAll("[data-hold]").forEach((button) => {
    const hold = button.dataset.hold;
    const activate = (event) => {
      event.preventDefault();
      game.held.add(hold);
      button.classList.add("is-active");
      if (hold === "guard") game.player.defense = "guard";
    };
    const release = (event) => {
      event.preventDefault();
      game.held.delete(hold);
      button.classList.remove("is-active");
      if (hold === "guard" && game.player.defense === "guard") game.player.defense = "none";
    };
    button.addEventListener("pointerdown", activate);
    button.addEventListener("pointerup", release);
    button.addEventListener("pointercancel", release);
    button.addEventListener("pointerleave", release);
  });

  ui.overlayButton.addEventListener("click", () => {
    if (game.overlayAction === "start") newSession();
    else if (game.overlayAction === "next") startRound();
    else if (game.overlayAction === "resume") togglePause();
  });

  ui.pauseButton.addEventListener("click", togglePause);
  ui.soundButton.addEventListener("click", () => {
    game.soundEnabled = !game.soundEnabled;
    ui.soundButton.textContent = game.soundEnabled ? "SFX" : "MUTE";
    ui.soundButton.setAttribute("aria-label", game.soundEnabled ? "사운드 끄기" : "사운드 켜기");
  });

  ui.resetLearningButton.addEventListener("click", () => {
    game.habits = makeHabitMemory();
    saveHabitMemory();
    game.exchange = "AI 학습 메모리를 초기화했습니다";
    triggerImpact("MEMORY RESET");
  });

  canvas.addEventListener("pointerdown", () => canvas.focus());
  window.addEventListener("blur", () => {
    game.keyDown.clear();
    game.held.clear();
    if (game.state === "fight") togglePause();
  });

  window.__PIXEL_BOXING__ = {
    start: newSession,
    nextRound: () => finishRound("player", "TEST"),
    state: () => ({
      state: game.state,
      round: game.round,
      time: game.time,
      playerHp: game.player.hp,
      enemyHp: game.enemy.hp,
      playerAction: game.player.action,
      adaptation: adaptationLevel(),
      favoriteAttack: snapshotHabits().favoriteAttack,
    }),
  };

  render();
  window.requestAnimationFrame(frame);
})();