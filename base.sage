class Transpiler:
    proc parse(self, source):
        # To be implemented by specific language parsers
        raise "Not implemented"

    proc emit(self, ast):
        # To be implemented by SageLang emitters
        raise "Not implemented"

    proc transpile(self, source):
        return self.emit(self.parse(source))
