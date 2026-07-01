module pokemondsl::Parser

import ParseTree;
import IO;
import pokemondsl::Syntax;

/*
 * We already provided the parser for the pokemon language. The name of the function must be parseLaBouR.
 * This function receives as a parameter the path of the file to parse represented as a loc, and returns a parse tree
 * that represents the parsed program.
 */

start[Program] parsePokemon(loc filePath) {
    return parse(#start[Program], readFile(filePath), filePath);
}
