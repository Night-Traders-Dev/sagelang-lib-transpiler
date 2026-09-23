gc_disable()
# -----------------------------------------
# pass_dynamic.sage - Dynamic require and cache diagnostics
# -----------------------------------------

from lexer.js_scanner import js_scan_source
from lexer.js_token import js_is_code_token

proc cjs_dynamic_report(source):
    let scan = js_scan_source(source)
    let report = {}
    report["errors"] = scan["errors"]
    report["static"] = 0
    report["dynamic"] = 0
    report["cache"] = 0
    if len(scan["errors"]) > 0:
        return report
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
            let open = cjs_code_token_at(code, index + 1)
            if open != nil and open.kind == "punct" and open.raw == "(":
                let call = cjs_match_call(code, index)
                if call["balanced"]:
                    if cjs_call_has_single_string(call["arguments"]):
                        report["static"] = report["static"] + 1
                    else:
                        report["dynamic"] = report["dynamic"] + 1
                    index = call["stop"]
                else:
                    report["dynamic"] = report["dynamic"] + 1
                    index = index + 1
            else:
                index = index + 1
        elif token_value.kind == "keyword" and token_value.raw == "delete":
            let target = cjs_code_token_at(code, index + 1)
            let dot = cjs_code_token_at(code, index + 2)
            let cache = cjs_code_token_at(code, index + 3)
            if target != nil and target.kind == "word" and target.raw == "require" and dot != nil and dot.kind == "punct" and dot.raw == "." and cache != nil and cache.kind == "word" and cache.raw == "cache":
                report["cache"] = report["cache"] + 1
            index = index + 1
        else:
            index = index + 1
    return report

proc cjs_code_token_at(code, index):
    if index < 0 or index >= len(code):
        return nil
    return code[index]

proc cjs_match_call(code, index):
    var depth = 1
    var position = index + 2
    let args = []
    while position < len(code):
        let token_value = code[position]
        if token_value.kind == "punct":
            if token_value.raw == "(":
                depth = depth + 1
            elif token_value.raw == ")":
                depth = depth - 1
                if depth == 0:
                    break
        push(args, token_value)
        position = position + 1
    let result = {}
    result["stop"] = position + 1
    result["balanced"] = depth == 0
    result["arguments"] = args
    return result

proc cjs_call_has_single_string(args):
    let values = []
    var index = 0
    while index < len(args):
        if js_is_code_token(args[index]):
            push(values, args[index])
        index = index + 1
    if len(values) != 1:
        return false
    return values[0].kind == "string"
