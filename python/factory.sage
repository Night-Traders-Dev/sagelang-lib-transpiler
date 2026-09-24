from transpiler.python.ast_parser import PythonASTParser
from transpiler.python.native_parser import SageNativeParser

proc get_parser(backend):
    if backend == "ast":
        return PythonASTParser()
    elif backend == "native":
        return SageNativeParser()
    return "Unknown backend: " + backend
