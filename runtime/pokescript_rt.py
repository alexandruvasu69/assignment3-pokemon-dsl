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


# ---- pure navigation: TODO stubs -----------------------------------------
def navigate(location: str):
    narrate(f"navigate({location})")
    _todo(f"navigate to {location}")


def push(entity: str, direction: str):
    narrate(f"push({entity}, {direction})")
    _todo(f"push {entity} {direction}")


def roam_grass():
    narrate("roam_grass()")
    _todo("roam_grass: wander in grass to trigger encounters")


def use_field_move(move: str):
    narrate(f"use_field_move({move})")
    _todo(f"use_field_move {move}")
