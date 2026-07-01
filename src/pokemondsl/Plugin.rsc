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
 * This function is defined to test the functionality of the whole assignment. It receives a file path as a parameter and returns true if the program satisfies the specification or false otherwise.
 * First, it calls the parser (Parser.rsc). Then, it transforms the resulting parse tree of the previous program and calls the function cst2ast (CST2AST.rsc), responsible for transforming a parse tree into an abstract syntax tree.
 * Finally, the resulting AST is used to evaluate the well-formedness of the labour program using the check function (Check.rsc).
 */
bool checkWellformedness(loc fil) {
  // Parsing
  &T resource = parsePokemon(fil);
  // Transform the parse tree into an abstract syntax tree
  &T ast = cst2ast(resource);
  // Check the well-formedness of the program
  return checkBoulderWallConfiguration(ast);
}

/*
 * This is the main function of the project. This function enables the editor's syntax highlighting.
 * After calling this function from the terminal, all files with extension .labour will be parsed using the parser defined in module labour::Parser.
 * If there are syntactic errors in the program, no highlighting will be shown in the editor.
 */

int main() {
  // we register a new language to Rascal's LSP multiplexer
  // the multiplexer starts a new evaluator and loads this module and function
  registerLanguage(
    language(
      pathConfig(srcs=[|project://labour/src|]),
      "BoulderingWall",      // name of the language
      {"labour"},            // extension, e.g., example.lbr
      "labour::Server",      // module to import, this one
      "contributions"
    )
  );
  return 0;
}

/*
 * Use this function to clear all traces of your language from VS code.
 */
void clearLaBouR() {
  unregisterLanguage("BoulderingWall", {"labour"});
}

/*
 * Use this function to run your tests. It will show how many tests succeeded.
 * Note that an invalid test "succeeds" when the check fails
 */
void runTests() {
  fails = 0;
  validFiles = |project://labour/test/valid|.ls;
  invalidFiles = |project://labour/test/invalid|.ls;

  println("\nValid tests");
  for (file <- validFiles) {
    if (checkWellformedness(file)) {
      println("SUCCESS: <file.path> returns true");
    } else {
      println("FAILURE: <file.path> returns false");
      fails += 1;
    }
  }

  println("\nInvalid tests");

  for (file <- invalidFiles) {
    if (checkWellformedness(file)) {
      println("FAILURE: <file.path> returns true");
      fails +=1;
    } else {
      println("SUCCESS: <file.path> returns false");
    }
  }

  println("<fails> failed tests");
}
