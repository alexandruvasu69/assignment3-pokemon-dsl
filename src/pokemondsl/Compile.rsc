module pokemondsl::Compile

/*
 * Code generation: PokéScript AST -> Python.
 *
 * Each program becomes a `player.py` that imports the hand-written runtime
 * (runtime/pokescript_rt.py) and drives the pokemon-agent backend. Goals become
 * functions, control flow / match lower to native Python, queries and actions
 * become runtime calls. Map navigation is emitted but marked "# TODO: navigation"
 * (the runtime stubs it) — see the plan.
 */

import IO;
import List;
import String;

import pokemondsl::AST;
import pokemondsl::Parser;
import pokemondsl::CST2AST;

// --- entry points ---------------------------------------------------------
str compile(Program p) {
  str header = "# Generated from PokeScript by pokemondsl::Compile. Do not edit.\n"
             + "from pokescript_rt import *\n\n\n";
  str goalsSrc = intercalate("\n\n\n", [genGoal(g) | Goal g <- p.goals]);
  str entry = "";
  if (p.goals != []) {
    // entry point: a goal named `main` if present, else the first goal
    str first = p.goals[0].name;
    if ("main" in { g.name | Goal g <- p.goals }) first = "main";
    entry = "\n\n\nif __name__ == \"__main__\":\n    <first>()\n";
  }
  return header + goalsSrc + entry;
}

str compileSrc(loc f) = compile(cst2ast(parsePokemon(f)));

void compileExamples(loc srcDir, loc outDir) {
  for (loc f <- srcDir.ls, f.extension == "pks") {
    str nm = f[extension="py"].file;
    writeFile(outDir + nm, compileSrc(f));
    println("generated <nm>");
  }
}

// --- goals & statements ---------------------------------------------------
str genGoal(Goal g) = "def <g.name>():\n" + genStmts(g.body.statements, 1);

str genStmts(list[Stmt] ss, int lvl) {
  if (ss == []) return indent(lvl) + "pass";
  return intercalate("\n", [genStmt(s, lvl) | Stmt s <- ss]);
}

str genStmt(Stmt s, int lvl) {
  switch (s) {
    case action(Action a): return indent(lvl) + genAction(a);
    case callGoal(str n):  return indent(lvl) + "<n>()";
    case ifThen(Expr c, block(list[Stmt] b)):
      return indent(lvl) + "if <genExpr(c)>:\n" + genStmts(b, lvl + 1);
    case ifElse(Expr c, block(list[Stmt] b), ElseBranch eb):
      return indent(lvl) + "if <genExpr(c)>:\n" + genStmts(b, lvl + 1) + "\n" + genElse(eb, lvl);
    case whileLoop(Expr c, block(list[Stmt] b)):
      return indent(lvl) + "while <genExpr(c)>:\n" + genStmts(b, lvl + 1);
    case ms:matchStmt(Expr scrut, list[Arm] arms):
      return genMatch(ms.src.offset, scrut, arms, lvl);
  }
  return indent(lvl) + "pass";
}

str genElse(ElseBranch eb, int lvl) {
  switch (eb) {
    case elseIf(Expr c, block(list[Stmt] b)):
      return indent(lvl) + "elif <genExpr(c)>:\n" + genStmts(b, lvl + 1);
    case elseIfElse(Expr c, block(list[Stmt] b), ElseBranch eb2):
      return indent(lvl) + "elif <genExpr(c)>:\n" + genStmts(b, lvl + 1) + "\n" + genElse(eb2, lvl);
    case elseBlock(block(list[Stmt] b)):
      return indent(lvl) + "else:\n" + genStmts(b, lvl + 1);
  }
  return "";
}

// --- match lowering (if/elif/else over the scrutinee) ---------------------
str genMatch(int off, Expr scrut, list[Arm] arms, int lvl) {
  str var = "_m<off>";
  list[str] lines = [indent(lvl) + "<var> = <genExpr(scrut)>"];
  bool first = true;
  for (arm(Pat pat, ArmBody body) <- arms) {
    str kw = first ? "if" : "elif";
    str head = "";
    switch (pat) {
      case wildcard():               head = indent(lvl) + "else:";
      case enumPat(_, str m):       { head = indent(lvl) + "<kw> <var> == \"<m>\":"; first = false; }
      case intPat(int n):           { head = indent(lvl) + "<kw> <var> == <n>:"; first = false; }
      case rangePat(int lo, int hi):{ head = indent(lvl) + "<kw> <lo> \<= <var> \<= <hi>:"; first = false; }
    }
    lines += [head + "\n" + genArmBody(body, lvl + 1)];
  }
  return intercalate("\n", lines);
}

str genArmBody(ArmBody b, int lvl) {
  switch (b) {
    case blockBody(block(list[Stmt] ss)): return genStmts(ss, lvl);
    case actionBody(Action a):            return indent(lvl) + genAction(a);
    case callBody(str n):                 return indent(lvl) + "<n>()";
  }
  return indent(lvl) + "pass";
}

// --- expressions ----------------------------------------------------------
str genExpr(Expr e) {
  switch (e) {
    case query(Query q):                return genQuery(q);
    case intLit(int n):                 return "<n>";
    case enumLit(_, str m):             return "\"<m>\"";
    case not(Expr x):                   return "not (<genExpr(x)>)";
    case binOp(Expr l, str op, Expr r): return "(<genExpr(l)> <op> <genExpr(r)>)";
    case and(Expr l, Expr r):           return "(<genExpr(l)> and <genExpr(r)>)";
    case or(Expr l, Expr r):            return "(<genExpr(l)> or <genExpr(r)>)";
  }
  return "None";
}

str genQuery(Query q) {
  switch (q) {
    case hasBadge(Expr b):   return "has_badge(<genExpr(b)>)";
    case money():            return "money()";
    case currentLocation():  return "current_location()";
    case averageLevel():     return "average_level()";
    case leadHpPercent():    return "lead_hp_percent()";
    case isFull():           return "is_full()";
    case hasFainted(Expr s): return "has_fainted(<genExpr(s)>)";
    case hasItem(Expr i):    return "has_item(<genExpr(i)>)";
    case itemCount(Expr i):  return "count(<genExpr(i)>)";
  }
  return "None";
}

// --- actions (navigation ones flagged as TODO) ----------------------------
str genAction(Action a) {
  switch (a) {
    case navigate(Expr e):       return "navigate(<genExpr(e)>)  # TODO: navigation";
    case interact(Expr e):       return "interact(<genExpr(e)>)";
    case push(Expr e, Expr d):   return "push(<genExpr(e)>, <genExpr(d)>)  # TODO: navigation";
    case roamGrass():            return "roam_grass()  # TODO: navigation";
    case engage(Expr e, Expr s): return "engage(<genExpr(e)>, <genExpr(s)>)";
    case flee():                 return "flee()";
    case healTeam():             return "heal_team()";
    case buy(Expr i, Expr n):    return "buy(<genExpr(i)>, <genExpr(n)>)";
    case useKeyItem(Expr i):     return "use_key_item(<genExpr(i)>)";
    case useFieldMove(Expr m):   return "use_field_move(<genExpr(m)>)  # TODO: navigation";
    case swapLead(Expr s):       return "swap_lead(<genExpr(s)>)";
    case deposit(Expr s):        return "pc_deposit(<genExpr(s)>)";
    case withdraw(Expr sp):      return "pc_withdraw(<genExpr(sp)>)";
  }
  return "pass";
}

// --- util -----------------------------------------------------------------
str indent(int n) = ("" | it + "    " | _ <- [0..n]);
