gc_disable()
# -----------------------------------------
# pass_json.sage - JSON require detection
# -----------------------------------------

from lexer.js_scanner import js_scan_source
from lexer.js_token import js_is_code_token

proc cjs_json_require_names(source):
    let scan = js_scan_source(source)
    let names = []
    if len(scan["errors"]) > 0:
        return names
    let code = []
    var token_index = 0
    while token_index < len(scan["tokens"]):
        if js_is_code_token(scan["tokens"][token_index]):
            push(code, scan["tokens"][token_index])
        token_index = token_index + 1
    var index = 0
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "word" and token_value.raw == "require":
            let open = cjs_json_token_at(code, index + 1)
            if open != nil and open.kind == "punct" and open.raw == "(":
                let argument = cjs_json_token_at(code, index + 2)
                let close = cjs_json_token_at(code, index + 3)
                if argument != nil and argument.kind == "string" and close != nil and close.kind == "punct" and close.raw == ")":
                    let raw = argument.raw
                    if len(raw) > 6 and slice(raw, len(raw) - 6, len(raw) - 1) == ".json":
                        push(names, slice(raw, 1, len(raw) - 1))
                    index = index + 4
                else:
                    index = index + 1
            else:
                index = index + 1
        else:
            index = index + 1
    return names

proc cjs_json_token_at(code, index):
    if index < 0 or index >= len(code):
        return nil
    return code[index]
