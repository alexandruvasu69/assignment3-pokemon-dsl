module pokemondsl::Parser

import ParseTree;
import IO;
import pokemondsl::Syntax;

start[Program] parsePokemon(loc filePath) {
    return parse(#start[Program], readFile(filePath), filePath);
}
