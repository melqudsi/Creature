/** Per-creature eye state for idle randomness, blink, look-at. */
export function createEyeState() {
  return {
    lookX: 0,
    lookY: 0,
    blink: 0,
    nextBlink: 2 + Math.random() * 4,
    idleTimer: 0,
    idleTarget: { x: 0, y: 0 },
    screenLookTimer: 8 + Math.random() * 12,
    sleepPhase: 0,
  };
}

export function updateEyes(state, dt, creature, others, camera, isLocal) {
  if (creature.is_asleep) {
    state.blink = 1;
    state.sleepPhase += dt;
    return state;
  }

  state.nextBlink -= dt;
  if (state.nextBlink <= 0) {
    state.blink = 1;
    if (state.nextBlink <= -0.12) {
      state.blink = 0;
      state.nextBlink = 2 + Math.random() * 5;
    }
  } else if (state.blink > 0 && state.nextBlink > -0.12) {
    state.blink = Math.min(1, state.blink + dt * 8);
  }

  let targetX = 0;
  let targetY = 0;

  const moving = creature.vx !== 0 || creature.vy !== 0;
  if (moving) {
    const len = Math.hypot(creature.vx, creature.vy) || 1;
    targetX = creature.vx / len;
    targetY = creature.vy / len;
  } else if (!creature.is_asleep) {
    let nearest = null;
    let nearestDist = 4;
    for (const o of others) {
      if (o.user_id === creature.user_id) continue;
      const d = Math.hypot(o.x - creature.x, o.y - creature.y);
      if (d < nearestDist) {
        nearestDist = d;
        nearest = o;
      }
    }
    if (nearest) {
      const dx = nearest.x - creature.x;
      const dy = nearest.y - creature.y;
      const len = Math.hypot(dx, dy) || 1;
      targetX = dx / len;
      targetY = dy / len;
    } else {
      state.idleTimer -= dt;
      if (state.idleTimer <= 0) {
        state.idleTimer = 1.5 + Math.random() * 2;
        state.idleTarget = {
          x: (Math.random() - 0.5) * 2,
          y: (Math.random() - 0.5) * 2,
        };
      }
      targetX = state.idleTarget.x;
      targetY = state.idleTarget.y;

      if (isLocal) {
        state.screenLookTimer -= dt;
        if (state.screenLookTimer <= 0) {
          state.screenLookTimer = 10 + Math.random() * 15;
          targetY = -0.85;
          targetX = 0;
        }
      }
    }
  }

  const smooth = moving ? 12 : 4;
  state.lookX += (targetX - state.lookX) * dt * smooth;
  state.lookY += (targetY - state.lookY) * dt * smooth;

  return state;
}
