from transpiler.base import Transpiler

class LilyToSageTranspiler(Transpiler):
    proc init(self):
        self.output = []
        self.indent_level = 0

    proc parse(self, source: String) -> Object:
        # A Lily parser should parse the source text into a Lily AST or Sage AST
        return nil

    proc emit(self, ast: Object) -> String:
        self.output = []
        self.indent_level = 0
        # self.visit(ast)
        return ""
