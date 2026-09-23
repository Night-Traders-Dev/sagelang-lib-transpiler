gc_disable()
# -----------------------------------------
# cjs_usage.sage - Scope and require/export analysis for cjs2esm
# -----------------------------------------

from lexer.js_scanner import js_scan_source
from lexer.js_token import js_is_code_token

class ScopeLevel:
    proc init(level_type, parent):
        self.level_type = level_type
        self.parent = parent
        self.bindings = {}

class ScopeTracker:
    proc init():
        self.global_scope = ScopeLevel("global", nil)
        self.current_scope = self.global_scope
        self.scope_stack = [self.global_scope]
        self.hoisting_conflicts = []
        self.diagnostics = []

    proc enter_scope(level_type):
        let child = ScopeLevel(level_type, self.current_scope)
        push(self.scope_stack, child)
        self.current_scope = child
        return child

    proc exit_scope():
        if len(self.scope_stack) > 1:
            pop(self.scope_stack)
            self.current_scope = self.scope_stack[len(self.scope_stack) - 1]
        return self.current_scope

    proc bind_identifier(name):
        if name == nil or name == "":
            return false
        self.current_scope.bindings[name] = true
        return true

    proc lookup_identifier(name):
        var index = len(self.scope_stack) - 1
        while index >= 0:
            if dict_has(self.scope_stack[index].bindings, name):
                return true
            index = index - 1
        return false

proc cjs_code_tokens(scan):
    let code = []
    var index = 0
    while index < len(scan["tokens"]):
        if js_is_code_token(scan["tokens"][index]):
            push(code, scan["tokens"][index])
        index = index + 1
    return code

proc cjs_unquote_module_name(raw):
    if raw == nil or len(raw) < 2:
        return ""
    let first = raw[0]
    let last = raw[len(raw) - 1]
    if (first == chr(34) or first == chr(39)) and first == last:
        return slice(raw, 1, len(raw) - 1)
    return ""

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

proc cjs_static_call_name(code, index):
    let open = cjs_code_token_at(code, index + 1)
    if open == nil or open.kind != "punct" or open.raw != "(":
        let result = {}
        result["found"] = false
        result["stop"] = index + 1
        result["name"] = ""
        return result
    let call = cjs_match_call(code, index)
    let values = []
    var arg_index = 0
    while arg_index < len(call["arguments"]):
        if js_is_code_token(call["arguments"][arg_index]):
            push(values, call["arguments"][arg_index])
        arg_index = arg_index + 1
    let result = {}
    result["stop"] = call["stop"]
    if call["balanced"] and len(values) == 1 and values[0].kind == "string":
        result["found"] = true
        result["name"] = cjs_unquote_module_name(values[0].raw)
    else:
        result["found"] = false
        result["name"] = ""
    return result

proc cjs_code_token_at(code, index):
    if index < 0 or index >= len(code):
        return nil
    return code[index]

proc analyze_require_calls(source):
    let scan = js_scan_source(source)
    let result = {}
    result["errors"] = scan["errors"]
    result["calls"] = []
    if len(scan["errors"]) > 0:
        return result
    let code = cjs_code_tokens(scan)
    var index = 0
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "word" and token_value.raw == "require":
            let call = cjs_static_call_name(code, index)
            if call["found"]:
                let entry = {}
                entry["static"] = true
                entry["name"] = call["name"]
                entry["line"] = token_value.line
                push(result["calls"], entry)
                index = call["stop"]
            else:
                let entry = {}
                entry["static"] = false
                entry["name"] = ""
                entry["line"] = token_value.line
                push(result["calls"], entry)
                index = index + 1
        else:
            index = index + 1
    return result

proc classify_require_call(call):
    if call["static"]:
        return "PURE_CJS"
    return "DYNAMIC"
