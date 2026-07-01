# PokéScript: Project Context & Specifications

> Living design doc for the 2IMP20 DSL Design assignment. Reflects decisions made after
> inspecting the real backend (`backend/pokemon-agent`, a git submodule) and choosing a
> Rust-flavored surface syntax.

## 1. Purpose & Thesis

**PokéScript** is a Domain-Specific Language for scripting Pokémon Red gameplay, designed
to be **written by an LLM agent in a closed loop**. Instead of emitting raw, error-prone
button presses, the agent expresses *bounded strategic plans* — `while (!has badge) { if
(hp low) { heal } else { fight } }` — in a language whose vocabulary is a fixed, typed set
of enumerations and macro actions. The compiler owns the hard part (pathfinding, dialogue,
battle turn-logic) and, crucially, **statically rejects malformed or hallucinated plans
before they ever touch the emulator**, feeding the error back to the agent to self-correct.

The DSL is therefore three things at once:
1. a **grounded action interface** — the agent can only name things that exist;
2. a **safety layer** — the type checker is the guardrail in the agent loop;
3. an **abstraction** — one line of strategy compiles to hundreds of frame-level inputs.

## 2. The LLM-in-the-Loop (the core of the proposal)

PokéScript is the *interface between the agent's reasoning and the emulator*. Each turn:

```
      ┌─────────────────────────────────────────────────────────────┐
      │                                                             ▼
┌───────────┐   grounded      ┌───────────┐   .pks plan   ┌──────────────────┐
│  LLM      │◀── observation ─│  Runtime  │◀───────────── │  LLM writes a    │
│  Agent    │   (in PokéScript│  (backend │               │  `goal { … }`    │
│           │    vocabulary)  │   state)  │               └────────┬─────────┘
└───────────┘                 └───────────┘                        │
      ▲                             ▲                              ▼
      │   compiler error messages   │                    ┌──────────────────┐
      └──── (self-correction) ──────┴──────── reject ────│ Rascal: parse +  │
                                    │                     │ STATIC CHECK     │
                                    │  accept → compile   └────────┬─────────┘
                                    │  → run walk_*/press_*         │
                                    └───────────────────────────────┘
```

Two properties make this work, and both fall directly out of the language design:

- **Observations are the evaluated sensor set — the dual of the action set.** Each turn
  the runtime hands the agent (a) a **sensor snapshot**: the current value of every §5.3
  query, rendered in PokéScript enums (`Location::PewterCity`, not `map_id=2`), plus
  (b) an **outcome trace** of what the last plan did (`navigate(Route2): ok`,
  `engage(Brock): lost — lead fainted`). Observation vocabulary = condition vocabulary,
  so nothing is visible that cannot also be tested in an `if`/`while`/`match`.
  Deliberately **no screenshot / tile grid** is fed back (the backend's own reference
  driver is multimodal and navigates visually; we raise the abstraction on *both* sides
  instead — high-level sensors ↔ high-level macros — so tile reasoning never re-enters).
- **The static checker is the agent's guardrail.** Enum grounding + type checking +
  `match` exhaustiveness reject a plan that names a non-existent location, battles a
  boulder, or forgets a case — *before* execution. The diagnostic (with "did you mean…?")
  is returned to the agent as a correction signal. This is the "DSLs prevent LLM
  hallucination" argument (PORTAL, van Rozen) made concrete and measurable.

A turn either **executes** (grounded, type-safe plan runs against the emulator, new
observation returned) or **bounces** (compiler error returned, agent rewrites). See §7.5
for a full transcript including a rejected-then-corrected plan.

## 3. Backend Reality (what we actually build on)

The runtime is `NousResearch/pokemon-agent` (vendored at `backend/pokemon-agent`, ROM at
`backend/pokemon_red.gb`). It wraps PyBoy headlessly and exposes a **low-level** HTTP API
on `localhost:8765`. There is **no** high-level navigation endpoint — that is the DSL's job.

| Capability | Endpoint | Notes |
|---|---|---|
| Read state | `GET /state` | `player.position{x,y}`, `player.facing`, `player.badges[]`, `player.money`, `map.map_id`/`map_name`, `party[]`(`hp`,`max_hp`,`level`,`species`), `bag`, `battle`, `flags` |
| Walkability | `GET /map/ascii`, `state.collision` | Ground-truth `@`/`.`/`#` tile grid, **current map only** |
| Act | `POST /action` | Primitives only: `walk_up\|down\|left\|right`, `press_a\|b\|start\|select`, `hold_X_N` |
| Save/Load | `POST /save`, `/load` | Named snapshots (used to make the demo deterministic) |

Consequence: `navigate(Location::CeruleanCity)` is **not** one API call — it is warp-graph
routing across maps, then A\* to each warp tile on each map's dynamically-fetched collision
grid, then a stream of `walk_*` primitives.

## 4. Architecture (committed)

**Code generation to pure, self-contained Python.** Rascal is the compiler; the generated
`player.py` is the only runtime artifact and contains *everything* (HTTP client, warp
graph, A\*, battle/dialogue routines, goal control-flow).

```
PokéScript (.pks)  ──parse──►  CST  ──CST2AST──►  AST
                                                   ├──► Check.rsc  → error/warning set
                                                   └──► Compile.rsc → player.py ──HTTP──► backend
```

- **Pathfinding is authored in Rascal templates** and emitted into `player.py`; it runs
  against **dynamically-fetched** collision grids (maps are never baked in — a live agent
  plays a live game).
- The **world model** (maps as nodes; connections + warps as edges, capability-gated) is
  static game knowledge held by the compiler, used for both routing and Tier-2 static
  analysis. It is distinct from the per-tile collision grid fetched at runtime.

### Navigation = hierarchical pathfinding (the DSL's substantial transformation)
The backend provides **only** local-window tile-A\* ([`pathfinding.py`], `(x,y)` start+goal
on the current 9×10 collision screen). It has *no* warp graph, named destinations, or
waypoints — its reference agent navigates by looking at screenshots. So `navigate(Location)`
is where PokéScript does real work, as **two-level pathfinding** emitted by Rascal:

1. **Macro (graph) search** over the authored world model: A\*/BFS across maps via
   *connection edges* (route↔city, crossed by a compass direction) and *warp tiles*
   (doors/caves, exact coordinates) → an ordered plan of `(map, exit)` hops, honoring
   capability gates (Surf/Cut/Strength/badges).
2. **Micro (tile) A\*** within each map: reach the next exit tile using the dynamically
   fetched collision window, re-planning window-by-window as new screens load
   (the grid is local, so this is incremental, not one-shot).
3. **Executor**: emit `walk_*` streams, detect `map_id` transitions, advance the macro plan.

The algorithm is general; the authored data is scoped to the demo corridor
(Pallet→Viridian→Pewter→Cerulean) and extensible. This hierarchical stitch (graph search
+ dynamic tile A\* + windowed re-planning) is the non-trivial transformation the assignment
rewards — not a wrapper over a backend call.

### Assignment fit
Real transformation (type system, routing, A\* generation, control-flow + `match`
lowering); no HTML/XML/JSON; C/Rust-style procedural syntax; covers concrete+abstract
syntax, static semantics, codegen to an executable GPL, non-trivial inputs+outputs, and a
live compile→run demo. Fits the approved "toy-robot / state-machine" category.

### Academic backing (verify each before citing!)
1. Mernik et al. (2005), *When and how to develop DSLs* — **general**.
2. Klint et al. (2009), *Rascal: A metaprogramming language* — the LWB.
3. van Rozen (2020), *Languages of Games and Play* — **domain**; DSLs for rules of play.
4. Wang et al. (2025), *PORTAL: Agents Play Thousands of 3D Video Games* — DSLs to structure
   agent behaviour / reduce hallucination. **⚠ confirm this paper exists.**
> Paper rule is per-student: each partner reads 1 general + 1 domain paper, no overlap.

---

## 5. Language Specification (Rust-flavored)

Conventions: `::` for enum paths (`Location::Route2`); `.` for method-style queries on
subsystems (`player.has_badge(…)`); `snake_case` actions/queries; `PascalCase` enum types
and variants; mandatory `{ }` blocks; **conditions are parenthesized** (`if (…) { }`).

### 5.1 Type universe & subtyping
```
Scalars:  Bool, Int
Enums:    Location, Item, FieldMove, Strategy, Badge, Slot, Direction, Species
Entity hierarchy (enables real subtyping checks):
          Entity ├── NPC (Rival, NurseJoy, GymLeader_Brock, …)
                 ├── WildPokemon (Entity::WildPokemon)
                 └── Interactable (Boulder, PC, CutTree)
```
`engage` accepts `NPC | WildPokemon` (you cannot battle a Boulder); `interact` accepts
`NPC | Interactable`; `push` accepts only `Interactable`.

### 5.2 Enumerations (grounding — the only identifiers the agent may name)
* **Location:** `PalletTown, OaksLab, Route1, ViridianCity, ViridianForest, PewterCity,
  PewterGym, PewterPokeCenter, Route2, CeruleanCity, CeruleanGym, CeruleanPokeCenter,
  Route24, Route24_Grass, VermilionCity, VermilionGym, SilphCo_Floor7, CinnabarIsland, …`
* **Badge:** `Boulder, Cascade, Thunder, Rainbow, Soul, Marsh, Volcano, Earth`
* **Item:** `PokeBall, GreatBall, Potion, SuperPotion, Antidote, SilphScope, PokeFlute,
  Bicycle, HM_Cut, HM_Surf, HM_Strength, HM_Flash`
* **FieldMove:** `Cut, Surf, Strength, Flash`
* **Strategy:** `Aggressive, TypeAdvantage, Catch, Stall`
* **NPC:** `Rival, NurseJoy, GymLeader_Brock, GymLeader_Misty, GymLeader_LtSurge, Snorlax,
  SilphEmployee`
* **Interactable:** `Boulder, PC, CutTree` &nbsp; **Species:** `Pikachu, Charmander,
  Squirtle, Bulbasaur, Lapras, Snorlax, …`
* **Slot:** `Slot::1 … Slot::6` &nbsp; **Direction:** `Up, Down, Left, Right`
* **WildPokemon:** `Entity::WildPokemon`

### 5.3 State queries (read-only "sensors") — expressions
| Query | Return |
|---|---|
| `player.has_badge(Badge)` | `Bool` |
| `player.money()` | `Int` |
| `player.current_location()` | `Location` |
| `party.average_level()` | `Int` |
| `party.lead_hp_percent()` | `Int` (0–100) |
| `party.is_full()` | `Bool` |
| `party.has_fainted(Slot)` | `Bool` |
| `inventory.has_item(Item)` | `Bool` |
| `inventory.count(Item)` | `Int` |

### 5.4 Macro actions ("actuators") — statements
| Action | Signature | Lowers to |
|---|---|---|
| `navigate(Location)` | `(Location)` | hierarchical pathfinding (§4): macro graph search + micro tile-A\* → `walk_*` |
| `interact(e)` | `(NPC \| Interactable)` | pathfind adjacent, face, `press_a` |
| `push(Interactable, Direction)` | `(Interactable, Direction)` | Strength puzzle |
| `roam_grass()` | `()` | walk grass until encounter |
| `engage(e, Strategy)` | `(NPC \| WildPokemon, Strategy)` | battle turn-logic from `state.battle` |
| `flee()` | `()` | run from wild encounter |
| `heal_team()` | `()` | walk to nurse, `press_a` dialogue loop |
| `buy(Item, Int)` | `(Item, Int)` | PokeMart menu |
| `use_key_item(Item)` | `(Item)` | use progression item |
| `use_field_move(FieldMove)` | `(FieldMove)` | use HM overworld |
| `party.swap_lead(Slot)` | `(Slot)` | move to front |
| `pc.deposit(Slot)` / `pc.withdraw(Species)` | `(Slot)` / `(Species)` | box management |

### 5.5 Grammar & control flow
```rust
Program ::= Goal+
Goal    ::= "goal" Id Block
Block   ::= "{" Stmt* "}"
Stmt    ::= Action ";"                                  // macro action
          | Id "(" ")" ";"                              // goal call (composition)
          | "if" "(" Expr ")" Block ("else" "if" "(" Expr ")" Block)* ("else" Block)?
          | "while" "(" Expr ")" Block
          | "match" "(" Expr ")" "{" Arm+ "}"
Arm     ::= Pat "=>" (Block | Stmt ",")
Pat     ::= EnumLit | Int | Int ".." Int | "_"
Expr    ::= Query | Int | EnumLit
          | Expr Cmp Expr | Expr "&&" Expr | Expr "||" Expr | "!" Expr | "(" Expr ")"
EnumLit ::= Id "::" Id                                  // e.g. Location::Route2, Slot::3
```
The first `goal` is the entry point. There is no `until`; use `while (!cond)`.

---

## 6. Static Semantics (Check.rsc) — also the agent guardrail

### Tier 1 — well-typedness (sound)
Enum resolution (+ Levenshtein "did you mean…?"); arity; argument conformance with
`Entity` subtyping and `Slot ∈ 1..6`; condition/expression typing (`Bool` conditions;
relational `Int×Int`; equality same-enum or `Int`; `&& || !` over `Bool`); statement-vs-
expression position; goal scope (unique names, ≥1 goal, goal-call targets exist, no cyclic
calls).

### `match` analysis (sound)
Scrutinee type drives arm patterns (enum patterns must belong to the scrutinee's enum;
`Int`/range patterns only for `Int`); **exhaustiveness** (all enum variants covered, or a
`_`; `Int` requires `_`); duplicate-arm and unreachable-arm-after-`_` warnings.

### Tier 2 — light capability analysis (warning-level, deliberately)
Capability *acquisition* is dynamic, so we track capabilities **established by enclosing
guards** (`K`) flow-sensitively: `if (player.has_badge(Cascade))` adds `Cascade` in the
then-branch; `if (inventory.has_item(Item::HM_Surf))` adds `Surf`. Checks: navigation
feasibility vs. the warp graph (warn if a route needs a capability ∉ `K`); unknown
`navigate` target (error, sound); dead-guard (`if (has_badge(X))` inside
`while (!has_badge(X))` is always true → the flagship analysis for the video).

### Decidability boundary (→ runtime)
Live HP, wild-encounter spawns, battle outcomes, money, NPC positions. Naming this boundary
is part of the report.

---

## 7. Concrete Examples

### 7.1 Beat Brock — nav + grind + heal + gym (`while`, `match`, subtyping)
```rust
goal defeat_brock {
    while (!player.has_badge(Badge::Boulder)) {
        if (party.average_level() < 12) {
            navigate(Location::Route2);
            match (party.lead_hp_percent()) {
                0..25 => { navigate(Location::PewterPokeCenter); heal_team(); }
                _     => engage(Entity::WildPokemon, Strategy::Aggressive),
            }
        } else {
            navigate(Location::PewterGym);
            engage(NPC::GymLeader_Brock, Strategy::TypeAdvantage);
        }
    }
}
```

### 7.2 Goal composition (routines called by name)
```rust
goal grind {
    navigate(Location::Route24_Grass);
    while (party.lead_hp_percent() > 20) {
        roam_grass();
        engage(Entity::WildPokemon, Strategy::Aggressive);
    }
    navigate(Location::CeruleanPokeCenter);
    heal_team();
}

goal challenge_misty {
    navigate(Location::CeruleanGym);
    engage(NPC::GymLeader_Misty, Strategy::TypeAdvantage);
}

goal main {
    while (!player.has_badge(Badge::Cascade)) {
        if (party.average_level() < 18) { grind(); }
        else { challenge_misty(); }
    }
}
```

### 7.3 Party/PC management + shopping (`interact` subtyping, `pc.*`, `buy`)
```rust
goal prepare_for_lapras {
    if (inventory.count(Item::GreatBall) < 10) {
        navigate(Location::CeruleanCity);
        buy(Item::GreatBall, 10);
    }
    if (party.is_full()) {
        navigate(Location::CeruleanPokeCenter);
        interact(Interactable::PC);
        pc.deposit(Slot::6);
    }
    navigate(Location::SilphCo_Floor7);
    interact(NPC::SilphEmployee);
}
```

### 7.4 Intentionally ill-typed (the checker / guardrail demo)
Each line yields a distinct diagnostic — ideal for the video and for showing what the agent
loop rejects.
```rust
goal broken {
    engage(Interactable::Boulder, Strategy::Aggressive);  // ✗ type: Boulder is not NPC|WildPokemon
    navigate(Location::Ceruleon);                         // ✗ enum: did you mean CeruleanCity?
    if (party.lead_hp_percent()) { flee(); }              // ✗ condition: Int used as Bool
    pc.deposit(Slot::9);                                  // ✗ range: Slot ∈ 1..6
    match (player.current_location()) {                   // ✗ match: non-exhaustive (no _ / missing variants)
        Location::PewterCity => heal_team(),
    }
    no_such_goal();                                       // ✗ scope: undefined goal
}
```

### 7.5 One agent turn (the loop in action)
**Runtime → agent** — observation auto-generated from `/state`, in PokéScript vocabulary:
```rust
// OBSERVATION (evaluated sensor set)
// location        = Location::PewterCity
// badges          = []          // objective: earn Badge::Boulder
// party.lead      = Species::Charmander  level 9  hp 22/26
// party.avg_level = 9
// inventory       = { PokeBall:5, Potion:3 }
// LAST RESULT     = navigate(Location::PewterCity): ok
```
**Agent → runtime** — first attempt (contains a hallucinated identifier):
```rust
goal step {
    navigate(Location::PewterCty);                       // typo
    engage(NPC::GymLeader_Rock, Strategy::TypeAdvantage); // wrong name
}
```
**Runtime → agent** — static check *bounces* it before any emulator input:
```
error: unknown Location 'PewterCty' — did you mean 'PewterCity'?   [step:2]
error: unknown NPC 'GymLeader_Rock' — did you mean 'GymLeader_Brock'? [step:3]
```
**Agent → runtime** — corrected, type-safe plan that now **executes**:
```rust
goal step {
    if (party.average_level() < 12) {
        navigate(Location::Route2);
        engage(Entity::WildPokemon, Strategy::Aggressive);
    } else {
        navigate(Location::PewterGym);
        engage(NPC::GymLeader_Brock, Strategy::TypeAdvantage);
    }
}
```
The compiler lowers `navigate`/`engage` to `walk_*`/`press_*`, drives the emulator, and
returns a fresh observation — closing the loop.

---

## 8. Implementation Plan

Status: repo holds only the LaBouR/BoulderingWall Rascal skeleton (placeholders) + the
`backend/pokemon-agent` submodule + ROM (`backend/pokemon_red.gb`). The language does not
exist yet. Project name is `pokemondsl`; **TypePal is excluded in `pom.xml`** → the checker
is hand-rolled. Grading: syntax (1) · static semantics (1) · implementation (1) ·
inputs+outputs (1) · video (1) · docs (1) · reflection/papers/lectures (4).

### 8.1 File map & work order (dependency order)
1. **`src/pokemondsl/Syntax.rsc`** — replace `PLACEHOLDER`. `start syntax Program = Goal+;`
   per §5.5 grammar: `goal Id Block`; stmts (action `;`, goal-call `id();`, `if/else if/
   else`, `while`, `match`); `Arm = Pat "=>" (Block | Stmt ",")`; `Pat = EnumLit | Int |
   Int".."Int | "_"`; `Expr` with explicit priority (`!` > relational > `&&` > `||`); enum
   literals `Type::Member` (incl. `Slot::1..6`, `Entity::WildPokemon`); `.`-method queries;
   lexical `Id`(snake)/`Int`, layout + `//` comments, reserved keywords. *Resolve
   expression ambiguity with priorities early — the main risk.*
2. **`src/pokemondsl/AST.rsc`** — 1:1 with grammar: `Program`, `Goal`, `Stmt` (`action`,
   `callGoal`, `ifElse`, `whileLoop`, `matchStmt`), `Arm`, `Pat` (`enumPat`/`intPat`/
   `rangePat`/`wildcard`), `Expr` (`query`/`intLit`/`enumLit`/`binOp`/`not`/`and`/`or`),
   `Action`; all carry `loc src`.
3. **`src/pokemondsl/CST2AST.rsc`** — `cst2ast` via `switch`/concrete patterns; `*`/`+`
   → lists; lexicals → `str`/`int`.
4. **`src/pokemondsl/Tables.rsc`** (NEW) — static reference data: enum members, query
   signatures, action signatures, `Entity` subtyping relation.
5. **`src/pokemondsl/World.rsc`** (NEW, critical-path data) — the authored world model:
   map graph (connection edges w/ compass + warp tiles w/ coords), per-map named waypoints
   (gym door, PC, nurse, mart), capability gates. Scoped to the Pallet→Cerulean corridor.
   *Validate against the live game early (see 8.3).*
6. **`src/pokemondsl/Check.rsc`** — rewrite. Return `set[Message]`; add `bool check(Program)`
   wrapper (no errors) for `Plugin.runTests`. Implement §6: Tier 1 (sound), `match`
   analysis (sound), Tier 2 (guard-sensitive warnings vs. `World.rsc`).
7. **`src/pokemondsl/Compile.rsc`** (NEW) — `str compile(Program)` → self-contained
   `player.py` templates: embedded `urllib` HTTP client; emitted world-model constant;
   **hierarchical `navigate()`** (macro graph search + micro tile-A\* ported from
   `pathfinding.py` + windowed re-planning); observation renderer (sensor snapshot +
   outcome trace); per-action helpers (`engage` battle turn-logic from `state.battle`,
   `heal_team`/`buy` dialogue loops, `interact`, `push`, PC/party ops); `goal`→function,
   goal-call→call, `if/while`→native, `match`→`if/elif/else` chain, queries→`/state` reads.
8. **Wiring/config** — `Parser.rsc`+`Server.rsc`: `#start[Program]`. `Plugin.rsc` `main()`:
   `srcs=[|project://pokemondsl/src|]`, name `"PokeScript"`, ext `{"pks"}`, module
   `"pokemondsl::Server"`; point `checkWellformedness` at new `check`; keep `runTests`.
   `META-INF/RASCAL.MF`: `Language-Name: PokeScript`, `Language-Extensions: pks`.
   `pom.xml`: `mainModule` → `pokemondsl::Plugin`.
9. **`examples/*.pks` + generated `*.py`** — the §7 valid programs + a `match`-driven one.
   **`test/valid/`** and **`test/invalid/`** — one invalid file per diagnostic class
   (subtyping, enum typo, Int-as-Bool, `Slot` range, non-exhaustive/duplicate/unreachable
   `match`, dead-guard, undefined/cyclic goal call).

### 8.2 Verification
**Offline (no ROM — carries 4/5 code points):** in `rascal`, `runTests()` passes all
`test/valid` and fails all `test/invalid`, each surfacing the expected `Message`;
`compile(...)` output passes `python -m py_compile`; `main()` gives IDE highlighting +
inline diagnostics (incl. a Tier-2 dead-guard warning).
**Live (video):** `pokemon-agent serve --rom backend/pokemon_red.gb`; run a generated
`player.py`; watch fetch `/state` → navigate → battle → heal. Use save-states for
deterministic, short on-camera runs.

### 8.3 Sequencing & risk
Land items 1→8 in order; wire the IDE loop (8) as soon as the grammar compiles. Two top
risks, both mitigated early: (a) **grammar ambiguity** — fix with explicit priorities in
step 1; (b) **world-model correctness** (`World.rsc`) — build a throwaway `navigate`
prototype against the running backend to validate warp coords / compass edges *before*
wiring the full compiler. Static-semantics + codegen + generated outputs are fully offline
and carry most of the grade — finish those before the live emulator demo.

### 8.4 Submission checklist
Individual reports (papers ×2/person, LWB reflection, lectures); ~10p language doc; the
`.pks` examples + generated outputs; 5–10 min video; single Canvas zip. **Do not
redistribute `pokemon_red.gb`** (copyright) — keep it local, note substitution in the doc.
