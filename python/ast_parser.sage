from transpiler.base import Transpiler
from transpiler.json_parser import parse_json
import sys
import io

let _python_ast_temp_counter = 0

proc _python_ast_candidates():
    let candidates = []
    let sage_path = sys.getenv("SAGE_PATH")
    if sage_path != nil and sage_path != "":
        for entry in split(sage_path, ":"):
            if entry != "":
                push(candidates, path_join(entry, "transpiler/python/python_ast.py"))
    push(candidates, "core/lib/transpiler/python/python_ast.py")
    push(candidates, "lib/transpiler/python/python_ast.py")
    push(candidates, "/usr/local/share/sage/lib/transpiler/python/python_ast.py")
    return candidates

proc _find_python_ast_helper():
    for candidate in _python_ast_candidates():
        if io.exists(candidate) and not io.isdir(candidate):
            return candidate
    return nil

proc _shell_quote(path):
    if contains(path, "'"):
        raise "Python AST helper path contains an unsupported quote"
    return "'" + path + "'"

class PythonASTParser(Transpiler):
    proc parse(self, source):
        if type(source) != "string":
            raise "Python AST parser expects source text"
        let helper = _find_python_ast_helper()
        if helper == nil:
            raise "Python AST helper was not found in the configured Sage library paths"
        _python_ast_temp_counter = _python_ast_temp_counter + 1
        let tmp_name = "/tmp/sage_python_ast_" + str(int(clock() * 1000000.0))
        let tmp_file = tmp_name + "_" + str(_python_ast_temp_counter) + ".py"
        if not io.writefile(tmp_file, source):
            raise "Python AST temporary source could not be written"
        defer io.remove(tmp_file)
        let json_output = sys.shell_exec("python3 " + _shell_quote(helper) + " " + _shell_quote(tmp_file))
        if json_output == nil or json_output == "":
            raise "Python AST helper failed to produce JSON"
        let parsed = parse_json(json_output)
        if parsed == nil:
            raise "Python AST helper produced invalid JSON"
        return parsed
