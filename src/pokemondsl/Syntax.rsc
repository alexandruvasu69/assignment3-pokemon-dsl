module pokemondsl::Syntax

layout Layout = WhitespaceOrComment*;

lexical WhitespaceOrComment
  = [\t-\n\r\ ]
  | "//" ![\n\r]* $
  ;

lexical GoalId
  = ([a-z][a-zA-Z0-9_]* !>> [a-zA-Z0-9_]) \ Reserved;
lexical TypeName = [A-Z][a-zA-Z0-9_]*;
lexical EnumMember = [A-Z0-9][a-zA-Z0-9_]*;
lexical IntLiteral = "-"? [0-9]+;

keyword Reserved
  = "goal"
  | "if"
  | "else"
  | "while"
  | "match"
  | "navigate"
  | "interact"
  | "push"
  | "roam_grass"
  | "engage"
  | "flee"
  | "heal_team"
  | "buy"
  | "use_key_item"
  | "use_field_move"
  | "player"
  | "party"
  | "inventory"
  | "pc";

start syntax Program
  = program: Goal+ goals;

syntax Goal
  = goal: "goal" GoalId name Block body;

syntax Block
  = block: "{" Stmt* statements "}";

syntax Stmt
  = action: Action action ";"
  | callGoal: GoalId name "(" ")" ";"
  | ifThen: "if" "(" Expr condition ")" Block thenBranch
  | ifElse: "if" "(" Expr condition ")" Block thenBranch
      ElseBranch elseBranch
  | whileLoop: "while" "(" Expr condition ")" Block body
  | matchStmt: "match" "(" Expr expression ")" "{" Arm+ arms "}";

syntax ElseBranch
  = elseIf: "else" "if" "(" Expr condition ")" Block body
  | elseIfElse: "else" "if" "(" Expr condition ")" Block body
      ElseBranch elseBranch
  | elseBlock: "else" Block body;

syntax Arm
  = arm: Pat pattern "=\>" ArmBody body;

syntax ArmBody
  = blockBody: Block body
  | actionBody: Action action ","
  | callBody: GoalId name "(" ")" ",";

syntax Pat
  = enumPat: TypeName enumType "::" EnumMember member
  | rangePat: IntLiteral lower ".." IntLiteral upper
  | intPat: IntLiteral value
  | wildcard: "_";

syntax Action
  = navigate: "navigate" "(" Expr location ")"
  | interact: "interact" "(" Expr entity ")"
  | push: "push" "(" Expr entity "," Expr direction ")"
  | roamGrass: "roam_grass" "(" ")"
  | engage: "engage" "(" Expr entity "," Expr strategy ")"
  | flee: "flee" "(" ")"
  | healTeam: "heal_team" "(" ")"
  | buy: "buy" "(" Expr item "," Expr amount ")"
  | useKeyItem: "use_key_item" "(" Expr item ")"
  | useFieldMove: "use_field_move" "(" Expr move ")"
  | swapLead: "party" "." "swap_lead" "(" Expr slot ")"
  | deposit: "pc" "." "deposit" "(" Expr slot ")"
  | withdraw: "pc" "." "withdraw" "(" Expr species ")";

syntax Query
  = hasBadge: "player" "." "has_badge" "(" Expr badge ")"
  | money: "player" "." "money" "(" ")"
  | currentLocation: "player" "." "current_location" "(" ")"
  | averageLevel: "party" "." "average_level" "(" ")"
  | leadHpPercent: "party" "." "lead_hp_percent" "(" ")"
  | isFull: "party" "." "is_full" "(" ")"
  | hasFainted: "party" "." "has_fainted" "(" Expr slot ")"
  | hasItem: "inventory" "." "has_item" "(" Expr item ")"
  | itemCount: "inventory" "." "count" "(" Expr item ")";

syntax Expr
  = query: Query query
  | intLit: IntLiteral value
  | enumLit: TypeName enumType "::" EnumMember member
  | bracket "(" Expr ")"
  > not: "!" Expr operand
  > non-assoc binOp: Expr left Comparator operator Expr right
  > left and: Expr left "&&" Expr right
  > left or: Expr left "||" Expr right;

syntax Comparator
  = "=="
  | "!="
  | "\<"
  | "\<="
  | "\>"
  | "\>=";
