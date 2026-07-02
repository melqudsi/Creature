import {
  TILE,
  drawCreature,
  drawGrassTile,
  drawTree,
  drawNameLabel,
  drawSpawnBurst,
  drawSleepZzz,
} from './renderer.js';
import { createEyeState, updateEyes } from './eyes.js';
import * as api from './api.js';

export const MAP_W = 20;
export const MAP_H = 15;
const MOVE_TILES_PER_SEC = 1;
const STAMINA_PER_TILE = 1;
const AFK_SLEEP_SEC = 45;
const SYNC_INTERVAL_MS = 400;
const POLL_OTHERS_MS = 1500;
const FIGHT_RANGE = 1.2;
const EAT_RANGE = 1.1;
const FIGHT_DAMAGE = 15;
const FIGHT_STAMINA = 2;
const STAMINA_MAX = 10;
const STAMINA_REGEN_PER_SEC = 1;
const VIEW_TILES_W = 9;
const VIEW_TILES_H = 7;

export class Game {
  constructor(canvas, hud, toast, session, clickMarker = null) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.hud = hud;
    this.toast = toast;
    this.clickMarker = clickMarker;
    this.session = session;
    this.userId = session.user.id;

    this.creatures = new Map();
    this.mapObjects = [];
    this.eyeStates = new Map();

    this.me = null;
    this.keys = {};
    this.spawnAnim = null;
    this.lastInput = Date.now();
    this.syncTimer = 0;
    this.pollTimer = null;
    this.raf = 0;
    this.lastT = 0;

    this.moveQueue = [];
    this.moving = false;
    this.moveFrom = { x: 0, y: 0 };
    this.moveTo = { x: 0, y: 0 };
    this.moveT = 0;
    this.facingAngle = 0;
    this.walkPhase = 0;
    this.actionCooldown = 0;
    this.staminaRegenAcc = 0;
    this.clickTarget = null;
    this.camX = 0;
    this.camY = 0;
  }

  async init(me, mapObjects, allCreatures) {
    this.me = me;
    this.mapObjects = mapObjects;
    for (const c of allCreatures) {
      this.creatures.set(c.user_id, { ...c, vx: 0, vy: 0 });
      this.eyeStates.set(c.user_id, createEyeState());
    }
    this.spawnAnim = { progress: 0, done: false };
    window.addEventListener('keydown', (e) => this.onKey(e, true));
    window.addEventListener('keyup', (e) => this.onKey(e, false));
    window.addEventListener('beforeunload', () => this.setAsleep(true));
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) this.setAsleep(true);
    });

    this.pollTimer = setInterval(() => this.pullCreatures(), POLL_OTHERS_MS);
    this.canvas.addEventListener('pointerdown', (e) => this.onPointerDown(e));
    await this.checkEatenMessage();
    this.resize();
    window.addEventListener('resize', () => this.resize());
    this.lastT = performance.now();
    this.loop(this.lastT);
  }

  resize() {
    this.canvas.width = window.innerWidth;
    this.canvas.height = window.innerHeight;
    this.scale = Math.min(
      this.canvas.width / (VIEW_TILES_W * TILE),
      this.canvas.height / (VIEW_TILES_H * TILE),
    );
    this.updateCamera(1);
  }

  updateCamera(dtOrInstant) {
    if (!this.me) return;
    const mapPxW = MAP_W * TILE;
    const mapPxH = MAP_H * TILE;
    const halfViewW = (this.canvas.width / this.scale) / 2;
    const halfViewH = (this.canvas.height / this.scale) / 2;

    const targetX = Math.max(
      halfViewW,
      Math.min(this.me.x * TILE + TILE / 2, mapPxW - halfViewW),
    );
    const targetY = Math.max(
      halfViewH,
      Math.min(this.me.y * TILE + TILE / 2, mapPxH - halfViewH),
    );

    const snap = dtOrInstant === 1;
    const lerp = snap ? 1 : Math.min(1, dtOrInstant * 10);
    this.camX += (targetX - this.camX) * lerp;
    this.camY += (targetY - this.camY) * lerp;

    this.offsetX = this.canvas.width / 2 - this.camX * this.scale;
    this.offsetY = this.canvas.height / 2 - this.camY * this.scale;
  }

  canvasToWorld(clientX, clientY) {
    const rect = this.canvas.getBoundingClientRect();
    const sx = ((clientX - rect.left) / rect.width) * this.canvas.width;
    const sy = ((clientY - rect.top) / rect.height) * this.canvas.height;
    const wx = (sx - this.offsetX) / this.scale;
    const wy = (sy - this.offsetY) / this.scale;
    return {
      x: Math.max(0, Math.min(MAP_W - 0.01, wx / TILE)),
      y: Math.max(0, Math.min(MAP_H - 0.01, wy / TILE)),
    };
  }

  onPointerDown(e) {
    if (e.button !== 0 || !this.me || (this.spawnAnim && !this.spawnAnim.done)) return;
    e.preventDefault();
    this.lastInput = Date.now();
    this.clickTarget = this.canvasToWorld(e.clientX, e.clientY);
    if (this.clickMarker) {
      const rect = this.canvas.getBoundingClientRect();
      const sx = ((e.clientX - rect.left) / rect.width) * 100;
      const sy = ((e.clientY - rect.top) / rect.height) * 100;
      this.clickMarker.style.left = `${sx}%`;
      this.clickMarker.style.top = `${sy}%`;
      this.clickMarker.hidden = false;
      this.clickMarker.classList.add('visible');
      clearTimeout(this.markerTimer);
      this.markerTimer = setTimeout(() => {
        this.clickMarker.classList.remove('visible');
        this.clickMarker.hidden = true;
      }, 600);
    }
  }

  stepTowardClickTarget() {
    if (!this.clickTarget || !this.me || this.moving) return;
    const tx = Math.round(this.clickTarget.x);
    const ty = Math.round(this.clickTarget.y);
    const cx = Math.round(this.me.x);
    const cy = Math.round(this.me.y);
    if (cx === tx && cy === ty) {
      this.clickTarget = null;
      return;
    }

    let dx = 0;
    let dy = 0;
    if (cx !== tx) dx = tx > cx ? 1 : -1;
    else if (cy !== ty) dy = ty > cy ? 1 : -1;

    const before = this.moving;
    this.tryQueueMove(dx, dy);
    if (!this.moving && !before) this.clickTarget = null;
  }

  async pullCreatures() {
    const list = await api.fetchAllCreatures();
    for (const c of list) {
      const existing = this.creatures.get(c.user_id);
      if (c.user_id === this.userId) {
        if (!this.moving) {
          this.me = { ...this.me, ...c, vx: existing?.vx ?? 0, vy: existing?.vy ?? 0 };
        } else {
          Object.assign(this.me, c, { x: existing?.x ?? c.x, y: existing?.y ?? c.y });
        }
        this.creatures.set(c.user_id, this.me);
      } else {
        this.creatures.set(c.user_id, {
          ...c,
          vx: existing?.vx ?? 0,
          vy: existing?.vy ?? 0,
          renderX: existing?.renderX ?? c.x,
          renderY: existing?.renderY ?? c.y,
        });
      }
      if (!this.eyeStates.has(c.user_id)) this.eyeStates.set(c.user_id, createEyeState());
    }
    for (const uid of [...this.creatures.keys()]) {
      if (!list.find((c) => c.user_id === uid)) this.creatures.delete(uid);
    }
  }

  async checkEatenMessage() {
    const events = await api.fetchUnreadEvents(this.userId);
    if (!events.length) return;
    const names = [...new Set(events.map((e) => e.attacker_name))];
    this.showToast(`Your creature was eaten by ${names.join(', ')}!`);
    await api.markEventsRead(events.map((e) => e.id));
  }

  showToast(msg) {
    this.toast.textContent = msg;
    this.toast.classList.add('visible');
    setTimeout(() => this.toast.classList.remove('visible'), 5000);
  }

  onKey(e, down) {
    this.keys[e.code] = down;
    if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(e.code)) {
      e.preventDefault();
    }
    if (down) {
      this.lastInput = Date.now();
      this.clickTarget = null;
    }
  }

  isBlocked(tx, ty) {
    if (tx < 0 || ty < 0 || tx >= MAP_W || ty >= MAP_H) return true;
    return this.mapObjects.some((o) => o.x === Math.floor(tx) && o.y === Math.floor(ty));
  }

  tryQueueMove(dx, dy) {
    if (!this.me || this.moving || this.spawnAnim && !this.spawnAnim.done) return;
    if (this.me.is_asleep) return;
    if (this.me.stamina < STAMINA_PER_TILE) return;

    const nx = Math.round(this.me.x) + dx;
    const ny = Math.round(this.me.y) + dy;
    if (this.isBlocked(nx, ny)) return;

    for (const c of this.creatures.values()) {
      if (c.user_id === this.userId) continue;
      if (Math.round(c.x) === nx && Math.round(c.y) === ny) return;
    }

    this.moveFrom = { x: this.me.x, y: this.me.y };
    this.moveTo = { x: nx, y: ny };
    this.me.vx = dx;
    this.me.vy = dy;
    this.facingAngle = Math.atan2(dy, dx);
    this.moving = true;
    this.moveT = 0;
    this.lastInput = Date.now();
  }

  async setAsleep(asleep) {
    if (!this.me) return;
    this.me.is_asleep = asleep;
    if (asleep && this.me.size_level > 1) {
      this.me.size_level = Math.max(1, this.me.size_level - 1);
    }
    await api.updateCreature(this.me.id, {
      is_asleep: asleep,
      size_level: this.me.size_level,
      last_active: new Date().toISOString(),
    });
  }

  async persistMe(patch) {
    if (!this.me) return;
    Object.assign(this.me, patch);
    await api.updateCreature(this.me.id, {
      ...patch,
      last_active: new Date().toISOString(),
      is_asleep: false,
    });
  }

  async doFight() {
    if (!this.me || this.me.is_asleep || this.me.stamina < FIGHT_STAMINA) return;
    let target = null;
    let best = FIGHT_RANGE;
    for (const c of this.creatures.values()) {
      if (c.user_id === this.userId) continue;
      const d = Math.hypot(c.x - this.me.x, c.y - this.me.y);
      if (d < best) {
        best = d;
        target = c;
      }
    }
    if (!target) return;

    const newHp = Math.max(0, target.health - FIGHT_DAMAGE);
    await api.updateCreature(target.id, { health: newHp });
    await this.persistMe({ stamina: this.me.stamina - FIGHT_STAMINA });
    if (newHp === 0) this.showToast(`${target.name} is down!`);
  }

  async doEat() {
    if (!this.me || this.me.is_asleep || this.me.stamina < 3) return;
    let target = null;
    let best = EAT_RANGE;
    for (const c of this.creatures.values()) {
      if (c.user_id === this.userId) continue;
      if (c.size_level >= this.me.size_level) continue;
      const d = Math.hypot(c.x - this.me.x, c.y - this.me.y);
      if (d < best) {
        best = d;
        target = c;
      }
    }
    if (!target) return;

    await api.recordEatenEvent(target.user_id, this.me.name);
    await api.deleteCreature(target.id);
    this.creatures.delete(target.user_id);

    const newSize = this.me.size_level + 1;
    await this.persistMe({
      size_level: newSize,
      stamina: Math.max(0, this.me.stamina - 3),
      health: Math.min(100, this.me.health + 10),
    });
    this.showToast(`You ate ${target.name}!`);
  }

  update(dt) {
    if (this.spawnAnim && !this.spawnAnim.done) {
      this.spawnAnim.progress = Math.min(1, this.spawnAnim.progress + dt * 0.8);
      if (this.spawnAnim.progress >= 1) this.spawnAnim.done = true;
      return;
    }

    const afk = (Date.now() - this.lastInput) / 1000 > AFK_SLEEP_SEC;
    if (afk && this.me && !this.me.is_asleep) this.setAsleep(true);
    else if (!afk && this.me?.is_asleep) this.setAsleep(false);

    if (!this.moving && this.me && !this.me.is_asleep) {
      let dx = 0;
      let dy = 0;
      if (this.keys.KeyW || this.keys.ArrowUp) dy = -1;
      if (this.keys.KeyS || this.keys.ArrowDown) dy = 1;
      if (this.keys.KeyA || this.keys.ArrowLeft) dx = -1;
      if (this.keys.KeyD || this.keys.ArrowRight) dx = 1;
      if (dx || dy) {
        if (Math.abs(dx) > Math.abs(dy)) dy = 0;
        else dx = 0;
        this.clickTarget = null;
        this.tryQueueMove(dx, dy);
      } else {
        this.stepTowardClickTarget();
      }
      if (this.actionCooldown <= 0) {
        if (this.keys.KeyF) {
          this.actionCooldown = 0.6;
          this.doFight();
        } else if (this.keys.KeyE) {
          this.actionCooldown = 1;
          this.doEat();
        }
      }
    }
    if (this.actionCooldown > 0) this.actionCooldown -= dt;

    if (this.moving && this.me) {
      this.moveT += dt * MOVE_TILES_PER_SEC;
      const t = Math.min(1, this.moveT);
      const ease = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
      this.me.x = this.moveFrom.x + (this.moveTo.x - this.moveFrom.x) * ease;
      this.me.y = this.moveFrom.y + (this.moveTo.y - this.moveFrom.y) * ease;
      this.walkPhase += dt * 10;

      if (t >= 1) {
        this.me.x = this.moveTo.x;
        this.me.y = this.moveTo.y;
        this.me.vx = 0;
        this.me.vy = 0;
        this.moving = false;
        const st = Math.max(0, this.me.stamina - STAMINA_PER_TILE);
        this.persistMe({ x: this.me.x, y: this.me.y, stamina: st });
        if (this.clickTarget && this.me.stamina < STAMINA_PER_TILE) {
          this.clickTarget = null;
        }
      }
    } else if (this.me) {
      this.me.vx = 0;
      this.me.vy = 0;
      if (!this.me.is_asleep && this.me.stamina < STAMINA_MAX) {
        this.staminaRegenAcc += dt * STAMINA_REGEN_PER_SEC;
        if (this.staminaRegenAcc >= 1) {
          const gain = Math.floor(this.staminaRegenAcc);
          this.staminaRegenAcc -= gain;
          this.me.stamina = Math.min(STAMINA_MAX, this.me.stamina + gain);
        }
      } else {
        this.staminaRegenAcc = 0;
      }
    }

    for (const c of this.creatures.values()) {
      if (c.user_id !== this.userId) {
        c.renderX = c.renderX ?? c.x;
        c.renderY = c.renderY ?? c.y;
        c.renderX += (c.x - c.renderX) * dt * 8;
        c.renderY += (c.y - c.renderY) * dt * 8;
      }
      const eye = this.eyeStates.get(c.user_id);
      const others = [...this.creatures.values()];
      updateEyes(eye, dt, c, others, null, c.user_id === this.userId);
    }

    this.syncTimer += dt * 1000;
    if (this.syncTimer >= SYNC_INTERVAL_MS && this.me && !this.moving) {
      this.syncTimer = 0;
      api.updateCreature(this.me.id, {
        x: this.me.x,
        y: this.me.y,
        health: this.me.health,
        stamina: this.me.stamina,
        size_level: this.me.size_level,
        is_asleep: this.me.is_asleep,
        last_active: new Date().toISOString(),
      });
    }

    if (this.me) {
      this.hud.hp.style.width = `${this.me.health}%`;
      this.hud.st.style.width = `${(this.me.stamina / 10) * 100}%`;
      this.hud.name.textContent = this.me.name;
      this.updateCamera(dt);
    }
  }

  draw() {
    const ctx = this.ctx;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#1a2f1c';
    ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    ctx.save();
    ctx.translate(this.offsetX, this.offsetY);
    ctx.scale(this.scale, this.scale);

    for (let py = 0; py < MAP_H; py++) {
      for (let px = 0; px < MAP_W; px++) {
        drawGrassTile(ctx, px, py);
      }
    }
    for (const o of this.mapObjects) drawTree(ctx, o.x, o.y);

    const sorted = [...this.creatures.values()].sort((a, b) => a.y - b.y);
    for (const c of sorted) {
      const rx = c.user_id === this.userId ? c.x : (c.renderX ?? c.x);
      const ry = c.user_id === this.userId ? c.y : (c.renderY ?? c.y);
      const sx = rx * TILE + TILE / 2;
      const sy = ry * TILE + TILE / 2;
      const size = TILE * (0.7 + (c.size_level - 1) * 0.08);
      const eye = this.eyeStates.get(c.user_id);

      if (c.user_id === this.userId && this.spawnAnim && !this.spawnAnim.done) {
        drawSpawnBurst(ctx, this.spawnAnim.progress, sx, sy + TILE * 0.2, c.color);
        if (this.spawnAnim.progress > 0.35) {
          const emerge = (this.spawnAnim.progress - 0.35) / 0.65;
          drawCreature(ctx, sx, sy + TILE * 0.3 * (1 - emerge), size, c.color, c.appearance, {
            lookX: eye.lookX,
            lookY: eye.lookY,
            blink: eye.blink,
            walkPhase: 0,
            facingAngle: 0,
            scale: emerge,
          });
        }
      } else {
        const angle = c.user_id === this.userId && this.moving ? this.facingAngle : 0;
        const walk = this.moving && c.user_id === this.userId ? this.walkPhase : 0;
        const asleep = c.is_asleep;
        if (asleep) ctx.globalAlpha = 0.85;
        drawCreature(ctx, sx, sy, size, c.color, c.appearance, {
          lookX: eye.lookX,
          lookY: eye.lookY,
          blink: eye.blink,
          walkPhase: walk,
          facingAngle: angle * 0.15,
          isAsleep: asleep,
          sleepPhase: eye.sleepPhase ?? 0,
        });
        ctx.globalAlpha = 1;
        if (asleep) {
          drawSleepZzz(ctx, sx, sy - size * 0.55, eye.sleepPhase ?? 0);
        }
      }

      if (c.user_id !== this.userId) {
        drawNameLabel(ctx, sx, sy - size * 0.5, c.name, c.is_asleep);
      }
    }

    ctx.restore();
  }

  loop(t) {
    const dt = Math.min(0.05, (t - this.lastT) / 1000);
    this.lastT = t;
    this.update(dt);
    this.draw();
    this.raf = requestAnimationFrame((nt) => this.loop(nt));
  }

  destroy() {
    cancelAnimationFrame(this.raf);
    if (this.pollTimer) clearInterval(this.pollTimer);
    this.setAsleep(true);
  }
}
