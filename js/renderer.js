export const TILE = 32;
export const COLORS = ['#f48fb1', '#81d4fa', '#a5d6a7', '#fff176', '#ce93d8', '#ffab91'];

const EYE_WHITE = '#fafafa';
const EYE_PUPIL = '#1a1a1a';

function hexToRgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function darken(hex, amount) {
  const [r, g, b] = hexToRgb(hex);
  return `rgb(${Math.max(0, r - amount)},${Math.max(0, g - amount)},${Math.max(0, b - amount)})`;
}

/** @param {CanvasRenderingContext2D} ctx */
export function drawTree(ctx, px, py) {
  const x = px * TILE;
  const y = py * TILE;
  ctx.fillStyle = '#5d4037';
  ctx.fillRect(x + 12, y + 20, 8, 12);
  ctx.fillStyle = '#2e7d32';
  ctx.fillRect(x + 4, y + 4, 24, 18);
  ctx.fillStyle = '#388e3c';
  ctx.fillRect(x + 8, y + 8, 16, 10);
}

/** @param {CanvasRenderingContext2D} ctx */
export function drawGrassTile(ctx, px, py) {
  const x = px * TILE;
  const y = py * TILE;
  const alt = (px + py) % 2;
  ctx.fillStyle = alt ? '#6b9b4f' : '#5d8a4a';
  ctx.fillRect(x, y, TILE, TILE);
  if (alt) {
    ctx.fillStyle = '#7cad5a';
    ctx.fillRect(x + 4, y + 20, 2, 2);
    ctx.fillRect(x + 20, y + 8, 2, 2);
  }
}

/**
 * @param {object} opts
 * @param {number} opts.lookX - normalized look direction -1..1
 * @param {number} opts.lookY
 * @param {number} opts.blink - 0 open, 1 closed
 * @param {number} opts.walkPhase - for leg wobble
 * @param {number} opts.facingAngle - radians, body rotation when moving
 * @param {boolean} opts.isAsleep
 * @param {number} opts.sleepPhase - breathing / rock cycle when asleep
 */
export function drawCreature(ctx, cx, cy, sizePx, color, appearance, opts = {}) {
  const {
    lookX = 0,
    lookY = 0,
    blink = 0,
    walkPhase = 0,
    facingAngle = 0,
    scale = 1,
    isAsleep = false,
    sleepPhase = 0,
  } = opts;

  const breath = isAsleep ? Math.sin(sleepPhase * 2.2) : 0;
  const s = sizePx * scale * (isAsleep ? 1 + breath * 0.06 : 1);
  const sleepTilt = isAsleep ? Math.sin(sleepPhase * 1.4) * 0.12 : 0;
  const sleepBob = isAsleep ? Math.sin(sleepPhase * 2.2) * 3 : 0;

  ctx.save();
  ctx.translate(cx, cy + sleepBob);
  ctx.rotate(facingAngle + sleepTilt);

  const bodyColor = color;
  const shadow = darken(color, 40);

  if (appearance === 'cute') {
    ctx.fillStyle = bodyColor;
    ctx.beginPath();
    ctx.ellipse(0, s * 0.05, s * 0.42, s * 0.38, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = shadow;
    ctx.fillRect(-s * 0.08, s * 0.32, s * 0.16, s * 0.08);
    ctx.fillStyle = '#ffcdd2';
    ctx.globalAlpha = 0.5;
    ctx.beginPath();
    ctx.arc(-s * 0.22, s * 0.08, s * 0.08, 0, Math.PI * 2);
    ctx.arc(s * 0.22, s * 0.08, s * 0.08, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#f8bbd0';
    ctx.fillRect(-s * 0.12, s * 0.18, s * 0.24, s * 0.04);
  } else {
    ctx.fillStyle = bodyColor;
    ctx.fillRect(-s * 0.38, -s * 0.2, s * 0.76, s * 0.55);
    ctx.fillStyle = shadow;
    ctx.fillRect(-s * 0.3, s * 0.28, s * 0.6, s * 0.12);
    ctx.fillStyle = '#eceff1';
    for (let i = -1; i <= 1; i += 2) {
      ctx.beginPath();
      ctx.moveTo(i * s * 0.15, s * 0.1);
      ctx.lineTo(i * s * 0.35, s * 0.35);
      ctx.lineTo(i * s * 0.05, s * 0.25);
      ctx.fill();
    }
    ctx.strokeStyle = '#37474f';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(-s * 0.2, s * 0.2);
    ctx.lineTo(0, s * 0.32);
    ctx.lineTo(s * 0.2, s * 0.2);
    ctx.stroke();
  }

  const legOffset = isAsleep
    ? Math.sin(sleepPhase * 2.2) * s * 0.03
    : Math.sin(walkPhase) * s * 0.06;
  ctx.fillStyle = shadow;
  ctx.fillRect(-s * 0.2, s * 0.35 + legOffset, s * 0.12, s * 0.1);
  ctx.fillRect(s * 0.08, s * 0.35 - legOffset, s * 0.12, s * 0.1);

  const eyeY = appearance === 'cute' ? -s * 0.08 : -s * 0.05;
  const eyeSpacing = appearance === 'cute' ? s * 0.18 : s * 0.2;
  const eyeR = s * 0.11;
  const pupilMax = s * 0.04;
  const pupilOffX = lookX * pupilMax;
  const pupilOffY = lookY * pupilMax;
  const eyeClosed = isAsleep || blink >= 0.95;
  const lidH = eyeClosed ? eyeR * 1.15 : blink * eyeR * 1.2;

  for (const side of [-1, 1]) {
    const ex = side * eyeSpacing;
    ctx.fillStyle = EYE_WHITE;
    ctx.beginPath();
    ctx.arc(ex, eyeY, eyeR, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = '#333';
    ctx.lineWidth = 1;
    ctx.stroke();
    if (!eyeClosed) {
      ctx.fillStyle = EYE_PUPIL;
      ctx.beginPath();
      ctx.arc(ex + pupilOffX, eyeY + pupilOffY, s * 0.045, 0, Math.PI * 2);
      ctx.fill();
    }
    if (lidH > 0) {
      ctx.fillStyle = bodyColor;
      ctx.fillRect(ex - eyeR, eyeY - eyeR, eyeR * 2, lidH);
      if (isAsleep) {
        ctx.strokeStyle = darken(color, 60);
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(ex - eyeR * 0.9, eyeY);
        ctx.lineTo(ex + eyeR * 0.9, eyeY);
        ctx.stroke();
      }
    }
  }

  ctx.restore();
}

export function drawNameLabel(ctx, x, y, name, asleep) {
  ctx.font = '8px "Press Start 2P", monospace';
  ctx.textAlign = 'center';
  ctx.fillStyle = 'rgba(0,0,0,0.6)';
  ctx.fillRect(x - 40, y - 22, 80, 12);
  ctx.fillStyle = asleep ? '#90a4ae' : '#fff';
  ctx.fillText(name.slice(0, 10), x, y - 12);
}

/** Floating zzz above a sleeping creature */
export function drawSleepZzz(ctx, cx, cy, sleepPhase) {
  const bob = Math.sin(sleepPhase * 2) * 4;
  ctx.font = '7px "Press Start 2P", monospace';
  ctx.textAlign = 'center';
  const chars = ['z', 'Z', 'z'];
  chars.forEach((ch, i) => {
    const t = sleepPhase * 1.5 + i * 0.9;
    const x = cx - 10 + i * 10 + Math.sin(t) * 3;
    const y = cy - 18 - i * 8 - bob + ((t * 3) % 12);
    ctx.globalAlpha = 0.5 + 0.5 * Math.sin(t * 2);
    ctx.fillStyle = '#b3e5fc';
    ctx.fillText(ch, x, y);
  });
  ctx.globalAlpha = 1;
}

export function drawSpawnBurst(ctx, progress, cx, cy, color) {
  const h = progress * TILE * 1.5;
  ctx.fillStyle = darken(color, 20);
  ctx.fillRect(cx - 14, cy + 8 - h, 28, h);
  ctx.fillStyle = '#4e342e';
  ctx.fillRect(cx - 18, cy + 10, 36, 6);
}
