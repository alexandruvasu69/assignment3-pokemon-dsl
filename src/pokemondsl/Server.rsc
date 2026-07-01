module pokemondsl::Server

import IO;
import Set;
import List;
import String;
import ParseTree;

import util::IDEServices;
import util::LanguageServer;

import pokemondsl::Syntax;

set[LanguageService] contributions() = {
  parsing(parser(#start[Program]), usesSpecialCaseHighlighting = false)
};
