module pokemondsl::Check

import pokemondsl::AST;
import pokemondsl::Parser;
import pokemondsl::CST2AST;

import IO;
import List;
import Set;
import Prelude;
import String;


/*
 * Implement a well-formedness checker for the pokemon language. For this you must use the AST.
 * - Hint: Map regular CST arguments (e.g., *, +, ?) to lists
 * - Hint: Map lexical nodes to Rascal primitive types (bool, int, str)
 * - Hint: Use switch to do case distinction with concrete patterns
 */

/*
 * Define a function per each verification defined in the PDF (Section 2.2.)
 * Some examples are provided below.
 */

bool checkBoulderWallConfiguration(BoulderingWall wall){
  bool numberOfHolds = checkNumberOfHolds(wall);

  bool startingLabelLimit = checkStartingHoldsTotalLimit(wall);
  bool unique_end_hold = checkUniqueEndHold(wall);

  return (numberOfHolds && startingLabelLimit && unique_end_hold);
}


// Check that there are at least two holds in the wall
bool checkNumberOfHolds(BoulderingWall wall) {
  return false;
}

// Check that routes have between zero and two hand start holds
bool checkStartingHoldsTotalLimit(BoulderingWall wall) {
  return false;
}

// This function will insure that there is only one hold assign to end hold
bool checkUniqueEndHold(BoulderingWall wall){
  return false;
}
