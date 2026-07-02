import * as api from './api.js';
import { Game, MAP_W, MAP_H } from './game.js';
import { COLORS, drawCreature } from './renderer.js';

const screens = {
  loading: document.getElementById('loading-screen'),
  welcome: document.getElementById('welcome-screen'),
  create: document.getElementById('create-screen'),
  game: document.getElementById('game-screen'),
};

function showScreen(name) {
  Object.values(screens).forEach((el) => el.classList.remove('active'));
  screens[name].classList.add('active');
}

function setupColorPicker(onChange) {
  const row = document.getElementById('color-picker');
  let selected = COLORS[0];
  COLORS.forEach((hex, i) => {
    const sw = document.createElement('button');
    sw.type = 'button';
    sw.className = 'color-swatch' + (i === 0 ? ' selected' : '');
    sw.style.background = hex;
    sw.dataset.color = hex;
    sw.addEventListener('click', () => {
      row.querySelectorAll('.color-swatch').forEach((s) => s.classList.remove('selected'));
      sw.classList.add('selected');
      selected = hex;
      onChange();
    });
    row.appendChild(sw);
  });
  return () => selected;
}

function getFormCreature() {
  const name = document.getElementById('creature-name').value.trim().slice(0, 10);
  const appearance = document.querySelector('input[name="appearance"]:checked')?.value ?? 'cute';
  const color = document.querySelector('.color-swatch.selected')?.dataset.color ?? COLORS[0];
  return { name, appearance, color };
}

function drawPreview() {
  const canvas = document.getElementById('preview-canvas');
  const ctx = canvas.getContext('2d');
  const { appearance, color } = getFormCreature();
  ctx.fillStyle = '#5d8a4a';
  ctx.fillRect(0, 0, 96, 96);
  drawCreature(ctx, 48, 52, 28, color, appearance, {
    lookX: 0.2,
    lookY: -0.3,
    blink: 0,
    walkPhase: 0,
  });
}

let session = null;
let game = null;

async function boot() {
  try {
    session = await api.ensureAnonymousAuth();
    const creature = await api.fetchMyCreature(session.user.id);
    const events = await api.fetchUnreadEvents(session.user.id);

    if (creature) {
      await startGame(creature, events);
    } else {
      if (events.length) {
        const names = [...new Set(events.map((e) => e.attacker_name))];
        const el = document.getElementById('welcome-alert');
        el.textContent = `Your creature was eaten by ${names.join(', ')}. Spawn a new one!`;
        el.hidden = false;
        await api.markEventsRead(events.map((e) => e.id));
      }
      showScreen('welcome');
    }
  } catch (err) {
    const el = document.getElementById('loading');
    const code = err?.code ?? err?.error_code ?? '';
    const msg = err?.message ?? err?.msg ?? String(err);

    if (code === 'anonymous_provider_disabled') {
      el.innerHTML =
        'Anonymous sign-in is off.<br><br>In Supabase Dashboard → Authentication → Sign In / Providers → Anonymous sign-ins → <b>Enable</b>. Then refresh.';
    } else if (msg.includes('relation') || msg.includes('does not exist') || code === '42P01') {
      el.innerHTML =
        'Database tables missing.<br><br>Run <code>supabase/schema.sql</code> in Supabase SQL Editor, then refresh.';
    } else {
      el.innerHTML = `Could not connect: ${msg}<br><br>Check config.js, anonymous sign-in, and schema.sql.`;
    }
    console.error(err);
  }
}

async function startGame(creature, prefetchedEvents) {
  showScreen('game');
  const mapObjects = await api.fetchMapObjects();
  const all = await api.fetchAllCreatures();

  if (prefetchedEvents?.length) {
    /* handled in Game.checkEatenMessage */
  }

  game = new Game(
    document.getElementById('game-canvas'),
    {
      hp: document.getElementById('hp-bar'),
      st: document.getElementById('st-bar'),
      name: document.getElementById('hud-name'),
    },
    document.getElementById('toast'),
    session,
    document.getElementById('click-marker'),
  );
  await game.init(creature, mapObjects, all);
}

document.getElementById('btn-play').addEventListener('click', () => {
  showScreen('create');
  drawPreview();
});

const getColor = setupColorPicker(drawPreview);
document.getElementById('creature-name').addEventListener('input', (e) => {
  document.getElementById('name-len').textContent = String(e.target.value.length);
  drawPreview();
});
document.querySelectorAll('input[name="appearance"]').forEach((r) =>
  r.addEventListener('change', drawPreview),
);

document.getElementById('create-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const { name, appearance, color } = getFormCreature();
  if (!name) return;

  const btn = document.getElementById('btn-create');
  btn.disabled = true;

  try {
    const row = await api.createCreature({
      user_id: session.user.id,
      name,
      color,
      appearance,
      x: Math.floor(MAP_W / 2),
      y: Math.floor(MAP_H / 2),
      health: 100,
      stamina: 10,
      size_level: 1,
      is_asleep: false,
    });
    await startGame(row, []);
  } catch (err) {
    btn.disabled = false;
    alert(err.message || 'Failed to create creature');
    console.error(err);
  }
});

boot();
