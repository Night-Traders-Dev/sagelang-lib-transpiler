from transpiler.base import Transpiler
import transpiler.lily.lily_parser as lily_parser
import formatter

class LilyToSageTranspiler(Transpiler):
    proc init(self):
        self.output = []
        self.indent_level = 0

    proc parse(self, source: String) -> Object:
        # A Lily parser parses the source text into a Sage AST
        return lily_parser.parse_lily_source(source)

    proc emit(self, ast: Object) -> String:
        # Since the LilyParser emits a Sage AST, we can theoretically just use the Sage compiler's codegen
        # But here we emit Sage code by delegating to a theoretical Sage formatter.
        # Assuming ast is an array of Sage AST nodes.
        return "// Sage code generated from Lily AST\n"

