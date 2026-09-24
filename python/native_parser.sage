from transpiler.base import Transpiler

class SageNativeParser(Transpiler):
    proc parse(source):
        raise "Native Python transpiler backend is not implemented"
