module pokemondsl::Cli

/*
 * Headless entry points for the `pokescript` CLI (the agent loop).
 * Kept free of LSP imports so it loads in a plain Rascal shell.
 */

import ParseTree;
import Message;
import IO;
import List;
import Set;

import pokemondsl::AST;
import pokemondsl::Parser;
import pokemondsl::CST2AST;
import pokemondsl::Check;
import pokemondsl::Compile;

str fmt(Message m) {
  str sev = m is error ? "error" : "warning";
  return "<sev> [line <m.at.begin.line>]: <m.msg>";
}

// Static-check a .pks file: "OK" or newline-separated diagnostics.
str checkStr(loc f) {
  try {
    Program ast = cst2ast(parsePokemon(f));
    set[Message] ms = check(ast);
    if (ms == {}) return "OK";
    return intercalate("\n", sort([fmt(m) | Message m <- ms]));
  } catch ParseError(loc l): {
    return "error [line <l.begin.line>]: syntax error";
  }
}

// Check and, if there are no errors, generate `out`. Returns a text report;
// the line "COMPILED" is appended on success.
str checkAndCompile(loc src, loc out) {
  try {
    Program ast = cst2ast(parsePokemon(src));
    set[Message] ms = check(ast);
    str report = (ms == {}) ? "OK" : intercalate("\n", sort([fmt(m) | Message m <- ms]));
    if (!any(Message m <- ms, m is error)) {
      writeFile(out, compile(ast));
      report = report + "\nCOMPILED";
    }
    return report;
  } catch ParseError(loc l): {
    return "error [line <l.begin.line>]: syntax error";
  }
}
