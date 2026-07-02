module pokemondsl::Plugin

import IO;
import util::Reflective;
import util::IDEServices;
import util::LanguageServer;

import pokemondsl::Server;
import pokemondsl::Parser;
import pokemondsl::CST2AST;
import pokemondsl::Check;

/*
 * Parse -> CST2AST -> static check. Returns true iff the program is well-formed.
 */
bool checkWellformedness(loc fil) {
  return checkOk(cst2ast(parsePokemon(fil)));
}

/*
 * Registers PokéScript with the Rascal LSP multiplexer (syntax highlighting for .pks).
 */
int main() {
  registerLanguage(
    language(
      pathConfig(srcs=[|project://pokemondsl/src|]),
      "PokeScript",
      {"pks"},
      "pokemondsl::Server",
      "contributions"
    )
  );
  return 0;
}

void clearPokeScript() {
  unregisterLanguage("PokeScript", {"pks"});
}

/*
 * Runs the test suite: valid programs should pass the checker, invalid ones should fail.
 */
void runTests() {
  int fails = 0;
  validFiles   = |project://pokemondsl/test/valid|.ls;
  invalidFiles = |project://pokemondsl/test/invalid|.ls;

  println("\nValid tests");
  for (loc file <- validFiles) {
    if (checkWellformedness(file)) println("SUCCESS: <file.file> returns true");
    else { println("FAILURE: <file.file> returns false"); fails += 1; }
  }

  println("\nInvalid tests");
  for (loc file <- invalidFiles) {
    if (checkWellformedness(file)) { println("FAILURE: <file.file> returns true"); fails += 1; }
    else println("SUCCESS: <file.file> returns false");
  }

  println("\n<fails> failed tests");
}
