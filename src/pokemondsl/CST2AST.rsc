module pokemondsl::CST2AST

import ParseTree;
import pokemondsl::AST;
import pokemondsl::Syntax;

public pokemondsl::AST::Program cst2ast(Tree cst)
  = implode(#pokemondsl::AST::Program, cst);
