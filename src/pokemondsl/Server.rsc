module pokemondsl::Server

import IO;
import Set;
import List;
import String;
import ParseTree;

import util::IDEServices;
import util::LanguageServer;

import pokemondsl::Syntax;

/*
 * A minimal implementation of a DSL in rascal
 * users can add support for more advanced features
 * More information about language servers can be found here:
 * - https://www.rascal-mpl.org/docs/Packages/RascalLsp/API/util/LanguageServer/#util-LanguageServer-Summary
 * - https://www.rascal-mpl.org/docs/Packages/RascalLsp/API/demo/lang/pico/LanguageServer/#demo-lang-pico-LanguageServer-picoExecutionService
 */
set[LanguageService] contributions() = {
  parsing(parser(#start[Program]), usesSpecialCaseHighlighting = false)
};
