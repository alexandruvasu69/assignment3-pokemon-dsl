"""
PokéScript runtime library.

Hand-written support library imported by the Python programs that Compile.rsc
generates from .pks sources. It wraps the `pokemon-agent` backend HTTP API and
implements the DSL's queries (sensors) and actions (actuators).

Scope note: map *navigation* is intentionally NOT implemented yet — `navigate`,
`push`, `roam_grass`, `use_field_move` and the "walk to the target" preamble of
`interact`/`engage`/`heal_team` are TODO stubs that log and no-op so that a
generated program still runs end-to-end (minus movement). Everything else
(state queries, a basic battle loop, dialogue mashing) is functional.

Backend: set POKESCRIPT_URL to override http://localhost:8765
"""

from __future__ import annotations
import json
import os
import time
import urllib.request
from collections import deque

try:
    import world as _world  # runtime/world.py — navigation world model
except Exception:
    _world = None

BASE = os.environ.get("POKESCRIPT_URL", "http://localhost:8765")


# --------------------------------------------------------------------------
# HTTP client
# --------------------------------------------------------------------------
def _get(path: str):
    with urllib.request.urlopen(BASE + path, timeout=30) as r:
        return json.load(r)


def _post(path: str, body: dict):
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        BASE + path, data=data, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def state() -> dict:
    """Full game state (see backend /state)."""
    return _get("/state")


def act(actions):
    """Execute a list of primitive actions (walk_*/press_*/hold_*)."""
    return _post("/action", {"actions": list(actions)})


def narrate(text: str):
    """Push a reasoning event so it shows up on the dashboard stream."""
    try:
        _post("/event", {"type": "reasoning", "text": text})
    except Exception:
        pass


def press_a(n: int = 1):
    act(["press_a"] * n)


def _todo(what: str):
    msg = f"[TODO navigation] {what} — not implemented yet (no-op)"
    print(msg)
    narrate(msg)


def _stub(what: str):
    msg = f"[stub] {what} — menu automation out of scope (no-op)"
    print(msg)
    narrate(msg)


# --------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------
def _norm(s: str) -> str:
    return "".join(ch for ch in str(s).lower() if ch.isalnum())


def _party():
    return state().get("party", []) or []

# Location enum members (the DSL's vocabulary). current_location() matches the
# backend's map_name against these by normalized form, so "Pewter Pokecenter" ->
# "PewterPokeCenter", "Route 2" -> "Route2", "Viridian City" -> "ViridianCity".
LOCATIONS = {
    "PalletTown", "OaksLab", "Route1", "ViridianCity", "ViridianForest",
    "PewterCity", "PewterGym", "PewterPokeCenter", "Route2", "CeruleanCity",
    "CeruleanGym", "CeruleanPokeCenter", "Route24", "Route24_Grass",
    "VermilionCity", "VermilionGym", "SilphCo_Floor7", "CinnabarIsland",
}
_LOC_BY_NORM = {_norm(x): x for x in LOCATIONS}

# engage() strategy thresholds, as a percentage of max HP.
CATCH_HP_PCT = 25
STALL_HP_PCT = 30


# --------------------------------------------------------------------------
# Queries (sensors) — read-only
# --------------------------------------------------------------------------
def has_badge(badge: str) -> bool:
    badges = (state().get("player", {}) or {}).get("badges", []) or []
    return any(_norm(badge) in _norm(b) or _norm(b) in _norm(badge) for b in badges)


def money() -> int:
    return int((state().get("player", {}) or {}).get("money", 0) or 0)


def current_location() -> str:
    name = (state().get("map", {}) or {}).get("map_name", "") or ""
    # reverse-match the backend map_name to a Location member; fall back to its
    # normalized form so comparisons in the DSL still behave sensibly.
    return _LOC_BY_NORM.get(_norm(name), _norm(name))


def average_level() -> int:
    party = _party()
    if not party:
        return 0
    return sum(int(m.get("level", 0) or 0) for m in party) // len(party)


def lead_hp_percent() -> int:
    party = _party()
    if not party:
        return 0
    hp = int(party[0].get("hp", 0) or 0)
    mx = int(party[0].get("max_hp", 1) or 1)
    return (hp * 100) // max(mx, 1)


def is_full() -> bool:
    return len(_party()) >= 6


def has_fainted(slot: str) -> bool:
    party = _party()
    i = int(slot) - 1
    return 0 <= i < len(party) and int(party[i].get("hp", 0) or 0) == 0


def has_item(item: str) -> bool:
    return count(item) > 0


def count(item: str) -> int:
    for it in (state().get("bag", []) or []):
        if _norm(it.get("item", "")) == _norm(item):
            return int(it.get("quantity", 0) or 0)
    return 0


# --------------------------------------------------------------------------
# Actions (actuators)
# --------------------------------------------------------------------------
# ---- battle helpers (driven blind: /state has no menu-cursor/turn info) ----
def _in_battle() -> bool:
    return bool((state().get("battle", {}) or {}).get("in_battle", False))


def _enemy_hp_pct() -> int:
    enemy = (state().get("battle", {}) or {}).get("enemy", {}) or {}
    hp = int(enemy.get("hp", 0) or 0)
    mx = int(enemy.get("max_hp", 1) or 1)
    return (hp * 100) // max(mx, 1)


def _attack():
    # Slow and deliberate. The Game Boy samples the joypad slowly and buffers
    # inputs during animations, so mashing mis-selects (it typed "AAAA" at name
    # entry!). From the battle menu (cursor defaults to FIGHT): A opens the move
    # list, A selects move 1, then we WAIT out the attack + enemy-turn animation.
    act(["press_a"])      # FIGHT -> move list
    act(["wait_40"])      # ~0.7s for the move menu to settle
    act(["press_a"])      # select move 1 (default cursor)
    act(["wait_150"])     # ~2.5s: move animation + damage + enemy turn -> back to menu


def _open_battle_bag():
    # From the battle menu (FIGHT top-left): Down -> ITEM (bottom-left), A opens the bag.
    # Slow pacing (same reason as _attack). NOTE: in-battle bag selection is still
    # best-effort/unverified — needs a wild battle to tune (see plan).
    act(["press_down"])
    act(["wait_40"])
    act(["press_a"])
    act(["wait_60"])


def _throw_ball():
    # Best-effort blind: open the bag and select/confirm the first entry. Fragile —
    # assumes a ball is the first in-battle bag item. TODO: locate the ball by name.
    narrate("Catch: throwing a ball")
    _open_battle_bag()
    act(["press_a", "press_a", "press_a"])


def _use_potion():
    # Best-effort blind: open the bag, pick an item, target the lead. Fragile.
    narrate("Stall: using a Potion")
    _open_battle_bag()
    act(["press_a", "press_a", "press_a"])


def engage(entity: str, strategy: str):
    """Battle turn loop. Aggressive/TypeAdvantage attack with move 1; Catch throws
    a ball when the enemy is weak; Stall heals when the lead is low. Reaching /
    triggering the encounter is navigation (out of scope) — if no battle is active
    this logs the navigation TODO. No type engine (see plan)."""
    narrate(f"engage({entity}, {strategy})")
    if not _in_battle():
        _todo(f"engage: reaching {entity} to start the battle")
        return
    act(["wait_180"])  # let the send-out intro animation play; the menu then appears
    for _ in range(40):
        if not _in_battle():
            break
        if strategy == "Catch" and _enemy_hp_pct() <= CATCH_HP_PCT:
            _throw_ball()
        elif strategy == "Stall" and lead_hp_percent() <= STALL_HP_PCT and count("Potion") > 0:
            _use_potion()
        else:
            _attack()
    narrate("engage: battle ended" if not _in_battle() else "engage: turn cap reached")


def flee():
    """Run from a wild battle. Battle menu 2x2 (FIGHT | PkMn / ITEM | RUN):
    RUN is bottom-right, so from FIGHT go down+right then A, and clear the text."""
    narrate("flee()")
    if not _in_battle():
        return
    act(["wait_150"])  # let any wild-encounter intro settle -> battle menu
    # battle menu 2x2 (FIGHT | PkMn / ITEM | RUN): Down -> ITEM, Right -> RUN.
    act(["press_down", "wait_40", "press_right", "wait_40", "press_a"])
    act(["wait_120"])  # "got away safely!"


def heal_team():
    """Mash A through the PokéCenter nurse dialogue. TODO: walk to the nurse."""
    narrate("heal_team()")
    _todo("heal_team: walking to the PokéCenter nurse")
    press_a(12)


def interact(entity: str):
    """Press A on the facing tile. TODO: pathfind adjacent to the entity."""
    narrate(f"interact({entity})")
    _todo(f"interact: walking up to {entity}")
    press_a(2)


def buy(item: str, amount: int):
    narrate(f"buy({item}, {amount})")
    _stub(f"buy {amount}x {item} (PokéMart menu)")


def use_key_item(item: str):
    narrate(f"use_key_item({item})")
    _stub(f"use_key_item {item} (bag menu)")


def swap_lead(slot: str):
    narrate(f"swap_lead({slot})")
    _stub(f"swap_lead {slot} (party menu)")


def pc_deposit(slot: str):
    narrate(f"pc_deposit({slot})")
    _stub(f"pc_deposit {slot} (PC box)")


def pc_withdraw(species: str):
    narrate(f"pc_withdraw({species})")
    _stub(f"pc_withdraw {species} (PC box)")


# ==========================================================================
# Navigation engine (see world.py). Stitches the local 9x10 collision window
# into a per-map map, A*/BFS to authored warp/waypoint tiles, and steps across
# warps (discrete tiles, may read non-walkable -> force-step) and connections
# (walk off a map edge). Cross-map routing is BFS over the WORLD graph.
# ==========================================================================
_DIRS = {"walk_up": (0, -1), "walk_down": (0, 1), "walk_left": (-1, 0), "walk_right": (1, 0)}
_EDGE_DIR = {"north": "walk_up", "south": "walk_down", "east": "walk_right", "west": "walk_left"}
_STITCH: dict = {}  # map_name -> {(x,y): walkable_bool}


def _pos():
    p = (state().get("player", {}) or {}).get("position", {}) or {}
    return int(p.get("x", 0)), int(p.get("y", 0))


def _mapname() -> str:
    return (state().get("map", {}) or {}).get("map_name", "")


def _collision():
    return state().get("collision", {}) or {}


def _stitch():
    """Merge the current 9x10 window into the per-map stitched collision map."""
    w = _collision().get("walkable")
    if not w:
        return
    x, y = _pos()
    d = _STITCH.setdefault(_mapname(), {})
    for r in range(len(w)):
        for c in range(len(w[r])):
            d[(x + (c - 4), y + (r - 4))] = bool(w[r][c])


def _bfs(known, start, goal):
    """Shortest walk_* path over known-walkable cells; None if unreachable."""
    prev = {start: None}
    q = deque([start])
    while q:
        cur = q.popleft()
        if cur == goal:
            path = []
            c = cur
            while prev[c] is not None:
                pc, a = prev[c]
                path.append(a)
                c = pc
            return path[::-1]
        for a, (dx, dy) in _DIRS.items():
            nb = (cur[0] + dx, cur[1] + dy)
            if known.get(nb) and nb not in prev:
                prev[nb] = (cur, a)
                q.append(nb)
    return None


def _greedy_step(x, y, tx, ty, known):
    opts = []
    if tx > x: opts.append("walk_right")
    if tx < x: opts.append("walk_left")
    if ty > y: opts.append("walk_down")
    if ty < y: opts.append("walk_up")
    for a in opts:
        dx, dy = _DIRS[a]
        if known.get((x + dx, y + dy), True):  # unknown -> worth trying
            return a
    return opts[0] if opts else "walk_up"


def _walk_to(tx, ty, force_last=False, max_steps=300) -> bool:
    """Walk to (tx,ty) on the current map. force_last steps onto a target tile that
    reads non-walkable (a warp) by pathing to a walkable neighbour then forcing it."""
    for _ in range(max_steps):
        _stitch()
        x, y = _pos()
        if (x, y) == (tx, ty):
            return True
        known = _STITCH.get(_mapname(), {})
        path = _bfs(known, (x, y), (tx, ty))
        if path:
            act([path[0]])
            continue
        if force_last:
            # reach a known-walkable neighbour of the target, then force the last step
            for a, (dx, dy) in _DIRS.items():
                nb = (tx - dx, ty - dy)
                if known.get(nb):
                    p2 = _bfs(known, (x, y), nb)
                    if p2 is not None:
                        for st in p2:
                            act([st])
                        act([a])
                        return True
        act([_greedy_step(x, y, tx, ty, known)])
    return False


def _route(src, dst):
    """BFS over the WORLD graph (edges = warps + connections) -> list of hops."""
    if _world is None:
        return None
    prev = {src: None}
    q = deque([src])
    while q:
        cur = q.popleft()
        if cur == dst:
            hops = []
            c = cur
            while prev[c] is not None:
                pc, info = prev[c]
                hops.append(info)
                c = pc
            return hops[::-1]
        node = _world.WORLD.get(cur, {})
        edges = [(dm, ("warp", (wx, wy))) for (wx, wy, dm) in node.get("warps", [])]
        edges += [(dm, ("conn", e)) for e, dm in node.get("connections", {}).items()]
        for dm, info in edges:
            if dm not in prev:
                prev[dm] = (cur, info)
                q.append(dm)
    return None


def _cross(before, kind, arg):
    """Execute one hop; wait for the map to change."""
    if kind == "warp":
        _walk_to(arg[0], arg[1], force_last=True)
    else:  # connection edge
        node = _world.WORLD.get(before, {})
        gap = node.get("waypoints", {}).get(arg + "_exit")
        if gap:
            _walk_to(gap[0], gap[1])
        for _ in range(4):
            if _mapname() != before:
                break
            act([_EDGE_DIR[arg]])
    for _ in range(6):  # let the new map load
        if _mapname() != before:
            break
        act(["wait_20"])


def navigate(location: str):
    narrate(f"navigate({location})")
    if _world is None:
        _todo(f"navigate {location}: world model unavailable")
        return
    tgt = _world.LOCATION_MAP.get(location)
    if not tgt:
        _todo(f"navigate: no world-model entry for {location}")
        return
    target_map, waypoint = tgt
    hops = _route(_mapname(), target_map)
    if hops is None:
        _todo(f"navigate: no route from {_mapname()} to {target_map}")
        return
    for kind, arg in hops:
        _cross(_mapname(), kind, arg)
    if waypoint:
        wxy = _world.WORLD.get(target_map, {}).get("waypoints", {}).get(waypoint)
        if wxy:
            _walk_to(wxy[0], wxy[1])
    narrate(f"navigate: arrived at {_mapname()}")


def roam_grass():
    """Wander in tall grass until a wild encounter starts."""
    narrate("roam_grass()")
    for _ in range(40):
        if _in_battle():
            return
        act(["walk_up"])
        if _in_battle():
            return
        act(["walk_down"])
    narrate("roam_grass: no encounter (cap reached)")


def push(entity: str, direction: str):
    narrate(f"push({entity}, {direction})")
    _todo(f"push {entity} {direction}")


def use_field_move(move: str):
    narrate(f"use_field_move({move})")
    _todo(f"use_field_move {move}")
