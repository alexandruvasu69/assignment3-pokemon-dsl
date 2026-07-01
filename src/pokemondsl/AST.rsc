module pokemondsl::AST

data Program(loc src = |unknown:///|)
  = program(list[Goal] goals);

data Goal(loc src = |unknown:///|)
  = goal(str name, Block body);

data Block(loc src = |unknown:///|)
  = block(list[Stmt] statements);

data Stmt(loc src = |unknown:///|)
  = action(Action action)
  | callGoal(str name)
  | ifThen(Expr condition, Block thenBranch)
  | ifElse(Expr condition, Block thenBranch, ElseBranch elseBranch)
  | whileLoop(Expr condition, Block body)
  | matchStmt(Expr expression, list[Arm] arms);

data ElseBranch(loc src = |unknown:///|)
  = elseIf(Expr condition, Block body)
  | elseIfElse(Expr condition, Block body, ElseBranch elseBranch)
  | elseBlock(Block body);

data Arm(loc src = |unknown:///|)
  = arm(Pat pattern, ArmBody body);

data ArmBody(loc src = |unknown:///|)
  = blockBody(Block body)
  | actionBody(Action action)
  | callBody(str name);

data Pat(loc src = |unknown:///|)
  = enumPat(str enumType, str member)
  | rangePat(int lower, int upper)
  | intPat(int number)
  | wildcard();

data Expr(loc src = |unknown:///|)
  = query(Query query)
  | intLit(int number)
  | enumLit(str enumType, str member)
  | not(Expr operand)
  | binOp(Expr left, str operator, Expr right)
  | and(Expr left, Expr right)
  | or(Expr left, Expr right);

data Query(loc src = |unknown:///|)
  = hasBadge(Expr badge)
  | money()
  | currentLocation()
  | averageLevel()
  | leadHpPercent()
  | isFull()
  | hasFainted(Expr slot)
  | hasItem(Expr item)
  | itemCount(Expr item);

data Action(loc src = |unknown:///|)
  = navigate(Expr location)
  | interact(Expr entity)
  | push(Expr entity, Expr direction)
  | roamGrass()
  | engage(Expr entity, Expr strategy)
  | flee()
  | healTeam()
  | buy(Expr item, Expr amount)
  | useKeyItem(Expr item)
  | useFieldMove(Expr move)
  | swapLead(Expr slot)
  | deposit(Expr slot)
  | withdraw(Expr species);
