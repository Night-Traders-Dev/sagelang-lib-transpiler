gc_disable()
# -----------------------------------------
# parser.sage - Program-level parse coordinator for cjs2esm
# -----------------------------------------

from lexer.js_scanner import js_scan_source
from lexer.js_token import js_is_code_token
from parser.expression import js_parse_expression_tokens
from parser.statements import parse_statements

proc parse_program(source):
    let scan = js_scan_source(source)
    let result = {}
    result["errors"] = scan["errors"]
    result["statements"] = []
    result["ok"] = len(scan["errors"]) == 0
    if not result["ok"]:
        return result
    let parsed = parse_statements(scan)
    result["statements"] = parsed["statements"]
    result["errors"] = parsed["errors"]
    result["ok"] = len(parsed["errors"]) == 0
    return result

proc parse_expression_text(source):
    let scan = js_scan_source(source)
    let result = {}
    result["errors"] = scan["errors"]
    result["node"] = nil
    result["consumed"] = 0
    if len(scan["errors"]) > 0:
        result["ok"] = false
        return result
    let code = []
    var index = 0
    while index < len(scan["tokens"]):
        if js_is_code_token(scan["tokens"][index]):
            push(code, scan["tokens"][index])
        index = index + 1
    let parsed = js_parse_expression_tokens(code)
    result["node"] = parsed["node"]
    result["consumed"] = parsed["consumed"]
    result["errors"] = parsed["errors"]
    result["ok"] = len(parsed["errors"]) == 0 and parsed["node"] != nil and parsed["consumed"] == len(code)
    return result
