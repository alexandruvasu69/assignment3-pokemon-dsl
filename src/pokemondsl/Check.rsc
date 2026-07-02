module pokemondsl::Check

/*
 * Static semantics for PokéScript (works on the AST from CST2AST).
 * Deliberately modest: well-typedness only.
 *   1. enum literals/patterns name a real member of a real enum type (incl. Slot 1..6);
 *   2. action/query arguments have the right enum kind (e.g. navigate wants a Location,
 *      engage wants an NPC|WildPokemon then a Strategy);
 *   3. if/while conditions are Bool;
 *   4. match patterns match the scrutinee kind;
 *   5. goals are unique and every goal call refers to a defined goal.
 *
 * `check` returns diagnostics; `checkOk` (no errors) is the wrapper used by Plugin/tests.
 */

import Message;
import List;
import Set;
import String;

import pokemondsl::AST;

// --- reference data -------------------------------------------------------
map[str, set[str]] enums = (
  "Location":     {"PalletTown","OaksLab","Route1","ViridianCity","ViridianForest","PewterCity",
                   "PewterGym","PewterPokeCenter","Route2","CeruleanCity","CeruleanGym",
                   "CeruleanPokeCenter","Route24","Route24_Grass","VermilionCity","VermilionGym",
                   "SilphCo_Floor7","CinnabarIsland"},
  "Badge":        {"Boulder","Cascade","Thunder","Rainbow","Soul","Marsh","Volcano","Earth"},
  "Item":         {"PokeBall","GreatBall","Potion","SuperPotion","Antidote","SilphScope",
                   "PokeFlute","Bicycle","HM_Cut","HM_Surf","HM_Strength","HM_Flash"},
  "FieldMove":    {"Cut","Surf","Strength","Flash"},
  "Strategy":     {"Aggressive","TypeAdvantage","Catch","Stall"},
  "NPC":          {"Rival","NurseJoy","GymLeader_Brock","GymLeader_Misty","GymLeader_LtSurge",
                   "Snorlax","SilphEmployee"},
  "Interactable": {"Boulder","PC","CutTree"},
  "Species":      {"Pikachu","Charmander","Squirtle","Bulbasaur","Lapras","Snorlax"},
  "Slot":         {"1","2","3","4","5","6"},
  "Direction":    {"Up","Down","Left","Right"},
  "Entity":       {"WildPokemon"}
);

// --- entry points ---------------------------------------------------------
set[Message] check(Program p) {
  set[str] goalNames = { g.name | Goal g <- p.goals };
  set[Message] msgs = {};
  if (p.goals == []) msgs += {error("program has no goals", p.src)};

  set[str] seen = {};
  for (Goal g <- p.goals) {
    if (g.name in seen) msgs += {error("duplicate goal name \'<g.name>\'", g.src)};
    seen += {g.name};
  }

  visit (p) {
    case e:enumLit(str t, str m):       msgs += enumMember(t, m, e.src);
    case pt:enumPat(str t, str m):      msgs += enumMember(t, m, pt.src);
    case action(Action a):              msgs += checkAction(a);
    case query(Query q):                msgs += checkQuery(q);
    case c:callGoal(str n):             if (n notin goalNames) msgs += {error("call to undefined goal \'<n>\'", c.src)};
    case b:callBody(str n):             if (n notin goalNames) msgs += {error("call to undefined goal \'<n>\'", b.src)};
    case ifThen(Expr c, _):             msgs += condBool(c);
    case ifElse(Expr c, _, _):          msgs += condBool(c);
    case whileLoop(Expr c, _):          msgs += condBool(c);
    case elseIf(Expr c, _):             msgs += condBool(c);
    case elseIfElse(Expr c, _, _):      msgs += condBool(c);
    case matchStmt(Expr scrut, list[Arm] arms): msgs += checkMatch(scrut, arms);
  }
  return msgs;
}

bool checkOk(Program p) = !any(Message m <- check(p), m is error);

// --- helpers --------------------------------------------------------------
set[Message] enumMember(str t, str m, loc src) {
  if (t notin enums)     return {error("unknown enum type \'<t>\'", src)};
  if (m notin enums[t])  return {error("\'<m>\' is not a valid <t>", src)};
  return {};
}

str typeOf(Expr e) {
  switch (e) {
    case intLit(_):        return "Int";
    case enumLit(str t, _):return t;
    case not(_):           return "Bool";
    case and(_, _):        return "Bool";
    case or(_, _):         return "Bool";
    case binOp(_, _, _):   return "Bool";
    case query(Query q):   return queryType(q);
  }
  return "?";
}

str queryType(Query q) {
  switch (q) {
    case hasBadge(_):       return "Bool";
    case isFull():          return "Bool";
    case hasItem(_):        return "Bool";
    case hasFainted(_):     return "Bool";
    case money():           return "Int";
    case averageLevel():    return "Int";
    case leadHpPercent():   return "Int";
    case itemCount(_):      return "Int";
    case currentLocation(): return "Location";
  }
  return "?";
}

set[Message] expect(Expr e, set[str] kinds, str what) {
  str t = typeOf(e);
  if (t != "?" && t notin kinds) {
    str ks = intercalate(" or ", sort(toList(kinds)));
    return {error("<what> expects <ks>, got <t>", e.src)};
  }
  return {};
}

set[Message] condBool(Expr c) {
  str t = typeOf(c);
  if (t != "?" && t != "Bool") return {error("condition must be Bool, got <t>", c.src)};
  return {};
}

set[Message] checkAction(Action a) {
  switch (a) {
    case navigate(Expr e):        return expect(e, {"Location"}, "navigate");
    case interact(Expr e):        return expect(e, {"NPC","Interactable"}, "interact");
    case push(Expr e, Expr d):    return expect(e, {"Interactable"}, "push") + expect(d, {"Direction"}, "push");
    case engage(Expr e, Expr s):  return expect(e, {"NPC","Entity"}, "engage") + expect(s, {"Strategy"}, "engage");
    case buy(Expr i, Expr n):     return expect(i, {"Item"}, "buy") + expectInt(n, "buy");
    case useKeyItem(Expr i):      return expect(i, {"Item"}, "use_key_item");
    case useFieldMove(Expr m):    return expect(m, {"FieldMove"}, "use_field_move");
    case swapLead(Expr s):        return expect(s, {"Slot"}, "swap_lead");
    case deposit(Expr s):         return expect(s, {"Slot"}, "deposit");
    case withdraw(Expr sp):       return expect(sp, {"Species"}, "withdraw");
  }
  return {};
}

set[Message] checkQuery(Query q) {
  switch (q) {
    case hasBadge(Expr b):   return expect(b, {"Badge"}, "has_badge");
    case hasFainted(Expr s): return expect(s, {"Slot"}, "has_fainted");
    case hasItem(Expr i):    return expect(i, {"Item"}, "has_item");
    case itemCount(Expr i):  return expect(i, {"Item"}, "count");
  }
  return {};
}

set[Message] expectInt(Expr e, str what) {
  str t = typeOf(e);
  if (t != "?" && t != "Int") return {error("<what> expects Int, got <t>", e.src)};
  return {};
}

set[Message] checkMatch(Expr scrut, list[Arm] arms) {
  str st = typeOf(scrut);
  set[Message] ms = {};
  for (arm(Pat pat, _) <- arms) {
    switch (pat) {
      case enumPat(str t, str m):
        if (st != "?" && t != st) ms += {error("pattern <t>::<m> does not match scrutinee type <st>", pat.src)};
      case intPat(_):
        if (st != "?" && st != "Int") ms += {error("integer pattern but scrutinee is <st>", pat.src)};
      case rangePat(int lo, int hi): {
        if (st != "?" && st != "Int") ms += {error("range pattern but scrutinee is <st>", pat.src)};
        if (lo > hi) ms += {error("empty range <lo>..<hi>", pat.src)};
      }
    }
  }
  return ms;
}
