# Gameplay features & mechanics

> Read this when changing **gameplay**: forms, money, houses, NPCs, map content, kill rules, announcements. Organized by system, with the build history that shaped each. The authoritative design doc is `Multiplayer Alien Shapeshifting Prototype.pdf` in the repo root — read it before changing gameplay rules.

**Game:** multiplayer alien shapeshifting sandbox. Players spawn as aliens at a landfill (The Dump), shapeshift into Memphis world objects, and kill/counter each other. Deaths are funny; money is physical and stealable.

---

## Forms & shapeshifting (Slice 1)

- Stand near an interactive object → **Become** (1s hold) → your body becomes that object with its speed/collision/kill rules. **Pop Out** returns to alien; the object **stays where you parked it** (same tile AND rotation) and you step off beside it. Rooted forms (Pyramid, claimed safe house) stay put; the alien steps aside.
- Forms are defined centrally in `creature-godot/scripts/forms/form_defs.gd` (speed, radius, kind, visual, carry rules, kill matrix). Procedural meshes in `scripts/forms/object_mesh.gd` are shared by world props and shapeshifted players (1:1 scale).
- Current shapeshiftables: alien (worm), Rusty Altima, Dodge Charger, **Truck**, MATA bus, shopping cart, magnolia/tree, pothole, propane tank, BBQ grill, BBQ smoker, house, Pyramid, ATM (prop only), zoo tiger/bear, human.
- **Kill/collision matrix** (in `FormDefs.resolve_player_death`) — vehicles squish aliens; trees/potholes/buildings wreck vehicles; propane/grills explode. **Kills are CLIENT-LOCAL:** each client only decides whether *its own* player dies.
- **Vehicle crash ranking:** bus > truck > car. A player truck wrecks NPC/player cars; the MATA bus beats a truck; truck-vs-truck totals both. NPC-vs-NPC crashes use the same ranking. Only **moving** vehicles kill — parked/stopped ones (prop, player, or braking NPC) are harmless.
- **Owned-house immunity:** you never crash into a house you own.
- **Rotation feel:** player forms ease toward travel direction with a per-frame step cap and ~31° max trail (`MAX_TURN_LAG` in `creature.gd`) — intentional "slop" without looking sideways.
- Region label (bottom-left HUD) via `GameConfig.region_for_tile()` / `MemphisLayout.REGIONS`.

## Money economy (Slices 2–3)

- **Three tiers:** Stack (T1) → Bag (T2) → Vault (T3); same `world_objects` table, types `money_stack`/`money_bag`/`vault`.
- **Carrying** (`FormDefs.carry_check()`): Alien 1 stack/bag · Cart 4 stacks or 1 bag · Altima 3 stacks or 1 bag · Bus 3 bags or **4 vaults in a row on the roof** · **Truck 2 vaults in the bed** (or 3 bags / 4 stacks; one vault + one bag OR stack may mix). At capacity the Pick Up button stays visible and pressing it toasts the reason.
- **Combining:** two matching tiers dropped close merge upward (Stack+Stack=Bag, Bag+Bag=Vault); combiner becomes owner (drop PATCHes are awaited first so labels don't lag).
- **Ownership + stealing:** bags/vaults show "NAME's Money Bag/Vault" labels; pick-up/steal re-brands immediately. **Steal** button works on remote carriers. Dying scatters carried money at the death spot (labels preserved).
- **Money enters via:** BBQ smoker (a stack every ~18s while player-possessed AND parked near houses — `SMOKER_GEN_INTERVAL_SEC`), and **ATMs** (a moving vehicle ramming one bursts 3 money bags; ATM goes dark and reseeds 24h later at a new random tile in its region via a `reseed:<due_unix>` marker in `owner_name`).
- **Money floor:** clients keep ≥36 idle stacks world-wide + 2 per playable region, re-seeded every ~60s jittered (`network_service.gd::_maybe_topup_money_stacks`). No world-wide cap.
- **Explosions & money:** blasts fling loose money 1.5–3 tiles (never destroyed); combined money demotes one tier (vault → 2 bags, bag → 2 stacks, owners kept) — `world_map.gd::_demote_money/_fling_money`.
- Safe placement: every drop/scatter goes through `GameState.free_drop_tile()` (spiral search avoiding blocked tiles, water, solid objects).

## Safe houses & Big Houses (Slice 7 + builds 2026-07-07a–2026-07-11a)

- Shapeshift into a house → **Claim** roots it (only the owner may wear it); **Unclaim** frees it. Tracked in `world_map.gd::safe_house_for()`. Respawn choice (Safe House vs The Dump) after death.
- **Big House upgrade:** near your claimed safe house an **Upgrade House** button always shows; costs **2 vaults** (dropped nearby and/or carried). Insufficient funds → toast "You need 2 vaults for this mane". On purchase: vaults consumed, synced smoke puff, house rebuilds as a Big House (two stories, gable roof, front door, 4 dark windows).
- **Vault storage:** vaults dropped near your own Big House **auto-deposit** (up to 4); one window glows gold with a light beam per stored vault — visible to all players. **Take Vault** withdraws (only while in a vault-capable form). Full house ignores extra drops.
- **Robbery:** near another player's loaded Big House → **Rob**: removes one vault, scatters **4 money stacks** outside. Once per day per house (`robbed:<unix>:<name>` marker). Owner gets a toast when the robbery syncs; everyone gets a broadcast toast.
- **Unclaim guard:** a loaded Big House refuses to unclaim. An empty unclaimed Big House keeps its upgrade and is claimable by anyone.
- **Data model:** everything rides `world_objects.owner_name` pipe segments — `home:x,y|safe:NAME|big|vaults:N|robbed:<unix>:<NAME>` (parse/set helpers in `world_object.gd`, e.g. `set_owner_segment()`). No schema change.
- **House facing:** ALL houses snap to face **south or east** (tile-hashed — `WorldMap.house_yaw()`/`snap_house_yaw()`) so doors/windows face the camera; pop-out snaps to the nearest allowed facing.

## Map & world content (Slices 4, 6)

- **Memphis, 160×112 tiles.** All layout in `scripts/world/memphis_layout.gd`: regions (Downtown, Midtown, Mud Island, Bartlett, Germantown, Collierville, …), two-lane roads with painted names, sidewalks, the sunken Mississippi + M Bridge (dead-ends west), landmarks (U of M campus halls, Shelby Farms, Memphis Zoo, Airport/FedEx, Krogers with parked carts/Altimas, The Pyramid).
- Scatter (houses/trees/towers) uses fixed seed `MemphisLayout.SCATTER_SEED` so all clients build identical worlds (blocked tiles must agree).
- The original 32×24 world (Dump, BBQ Corner, Bus Stop) is embedded at `GameConfig.OLD_WORLD_OFFSET` inside South Memphis.
- **The Pyramid:** shapeshiftable, speed 0; special = abduction (sky beam + saucer, NPC beam-up, nearby player kill), synced via transient `abduction` rows.
- **Occlusion fade:** buildings between camera and player fade to ~30% alpha (`world_map.gd::_update_occlusion_fades()`). Window panes/light beams carry a `no_fade` meta so fade doesn't stomp their materials.
- **Seeding rules:** parked vehicles/ATMs avoid road tiles; seed POSTs run a spreading pass (no two seeds share a tile / no seeds inside solid objects); parked vehicles get stable tile-hashed rotations. Regional rules: trucks parked only in Bartlett + East Memphis; Chargers South Memphis; no Altimas/Chargers in Germantown/Collierville; propane North Memphis + Midtown.
- **Respawn rules:** destroyed propane/grills reseed ~30s later at randomized tiles; zoo animals respawn in their enclosures; claimed houses reseed a replacement elsewhere; carts respawn at their Kroger; ATMs reseed daily.

## NPCs

- **Traffic** (`npc_traffic.gd`, client-local): Altimas, Chargers, buses, trucks drive every road (right-hand, counter-clockwise U-turns at dead ends). They brake for players (~4s patience, then drive through), brake for each other, and crash by ranking (bus > truck > car). A fully-stopped NPC vehicle is claimable (Become) — claiming creates a shared possessed `world_objects` row. NPCs never brake for pothole-players (driving over one wrecks the vehicle); ramming propane/grill players kills the vehicle in the blast.
- **Humans** (`npc_humans.gd`, client-local, target 64): randomized outfits, sidewalk pathing with crossings/roaming, **panic** when an alien-form player enters their forward vision cone; fully mortal (traffic, vehicles, predators, explosions). Become Human (wear that outfit) or **Eat Human** as an alien. Replacements step out of building doors. PERF: `_check_kills()` must run once per frame, NOT per human (past bug).
- **Zoo animals** (`zoo_animals.gd`): tiger + grizzly wander open pens; claimable in-pen. Tiger is the fastest form and eats aliens/humans/carts while moving; bear is slower with a Climb Tree special. Animals respawn at the zoo when killed.
- **Remote player name tags** show only in alien form — disguises hide the tag.

## Announcements & menu (builds 2026-07-07a–2026-07-11a)

- **Top-left menu** (hamburger icon, drawn in code): Sign Out + Admin (MOE only). No top-right X anymore; the loudspeaker (megaphone icon) button top-right re-opens the latest announcement.
- **Announcements:** `public.announcements` table; clients poll the newest row ~30s (`NetworkService._poll_announcements`). Unseen id → auto-popup with OK (mid-session too); OK persists the seen id locally (web localStorage key `creature_announcement_seen`, desktop `user://announcement_seen.txt`). The popup is a `PanelContainer` that auto-sizes to the message (~500px wrap width) and re-centers after layout.
- Admin panel has a broadcast composer. REST broadcast/clear commands: see `docs/supabase-backend.md`.

## Death, explosions & FX

- Death: camera zooms the corpse, red 3-2-1 countdown, respawn at The Dump (or safe house). Kill feed broadcast via transient `kill_event` rows.
- Explosions are synced via transient `explosion` rows — same lethal radius on every client (players, NPCs, zoo animals). Propane/grills chain-detonate (cap 32 blasts/wave). Non-vehicle contact does NOT detonate explosives; only moving vehicles, chain blasts, or manual Detonate.
- Squish deaths leave blood splats; vehicle deaths scatter wreck chunks; smoke clouds (smoker special) hide players/money inside ~3 tiles from everyone else, synced via transient `smoke_cloud` rows.

## Admin tools (MOE only)

In the menu → Admin: test-mode tap-to-teleport, pain test, remove all money / spawn 20 stacks, **reset ALL world objects** (wipe + reseed — the fix-everything button), profile list with last-login timestamps + delete, broadcast announcement composer, logs panel, clear session/reload, close (X) button.

## Shared gameplay constants

| Rule | Value |
|------|-------|
| Map | 160×112 tiles (~2:40 walk east-west) |
| Move speed | 1 tile/sec base; vehicles +35% on roads (`ROAD_SPEED_MULT`) |
| Name | Max 10 chars, forced UPPERCASE |
| Poll interval | 1.5s (`GameConfig.POLL_OTHERS_SEC`) |
| Idle logout | 40 min (`main.gd::IDLE_LOGOUT_SEC`) |
