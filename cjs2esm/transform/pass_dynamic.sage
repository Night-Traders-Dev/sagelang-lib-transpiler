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
                let dot = cjs_code_token_at(code, index + 1)
                let cache = cjs_code_token_at(code, index + 2)
                if dot != nil and dot.kind == "punct" and dot.raw == "." and cache != nil and cache.kind == "word" and cache.raw == "cache":
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

proc cjs_dyn_is_opener(token_value):
    if token_value.kind != "punct":
        return false
    if token_value.raw == "(" or token_value.raw == "[" or token_value.raw == "{" or token_value.raw == "${":
        return true
    return false

proc cjs_dyn_is_closer(token_value):
    if token_value.kind == "template_end":
        return true
    if token_value.kind != "punct":
        return false
    if token_value.raw == ")" or token_value.raw == "]" or token_value.raw == "}":
        return true
    return false

proc cjs_dyn_match_opening(code, close_index):
    var depth = 1
    var position = close_index - 1
    while position >= 0:
        let token_value = code[position]
        if cjs_dyn_is_closer(token_value):
            depth = depth + 1
        elif cjs_dyn_is_opener(token_value):
            depth = depth - 1
            if depth == 0:
                return position
        position = position - 1
    return -1

proc cjs_dyn_skip_group(code, open_index, closing):
    var depth = 1
    var position = open_index + 1
    while position < len(code):
        let token_value = code[position]
        if cjs_dyn_is_opener(token_value):
            depth = depth + 1
        elif cjs_dyn_is_closer(token_value):
            depth = depth - 1
            if depth == 0 and token_value.raw == closing:
                return position + 1
            if depth < 0:
                return position
        position = position + 1
    return position

proc cjs_dyn_word_at(code, index):
    let token_value = cjs_code_token_at(code, index)
    if token_value == nil:
        return ""
    if token_value.kind == "word":
        return token_value.raw
    return ""

proc cjs_dyn_block_owner(code, open_index):
    let result = {}
    result["function"] = false
    result["async"] = false
    let previous = cjs_code_token_at(code, open_index - 1)
    if previous == nil:
        return result
    if previous.kind == "punct" and previous.raw == ")":
        let open_paren = cjs_dyn_match_opening(code, open_index - 1)
        if open_paren < 0:
            return result
        let before = cjs_code_token_at(code, open_paren - 1)
        if before != nil and before.kind == "keyword" and before.raw == "function":
            result["function"] = true
            let maybe_async = cjs_code_token_at(code, open_paren - 2)
            if maybe_async != nil and maybe_async.kind == "word" and maybe_async.raw == "async":
                result["async"] = true
            return result
        if before != nil and before.kind == "punct" and before.raw == "=>":
            result["function"] = true
            result["async"] = cjs_dyn_arrow_is_async(code, open_paren)
            return result
        if before != nil and before.kind == "keyword":
            if before.raw == "function":
                result["function"] = true
                let maybe_async = cjs_code_token_at(code, open_paren - 2)
                if maybe_async != nil and maybe_async.kind == "word" and maybe_async.raw == "async":
                    result["async"] = true
                return result
            return result
        if before != nil and before.kind == "word":
            let owner = cjs_code_token_at(code, open_paren - 2)
            if owner != nil and owner.kind == "keyword" and owner.raw == "function":
                result["function"] = true
                let maybe_async = cjs_code_token_at(code, open_paren - 3)
                if maybe_async != nil and maybe_async.kind == "word" and maybe_async.raw == "async":
                    result["async"] = true
                return result
            if owner != nil and owner.kind == "word" and owner.raw == "async":
                result["function"] = true
                result["async"] = true
                return result
            let owner2 = cjs_code_token_at(code, open_paren - 3)
            if owner2 != nil and owner2.kind == "punct" and owner2.raw == "*":
                let owner3 = cjs_code_token_at(code, open_paren - 4)
                if owner3 != nil and owner3.kind == "word" and owner3.raw == "async":
                    result["function"] = true
                    result["async"] = true
                    return result
            result["function"] = true
            result["async"] = false
            return result
        return result
    if previous.kind == "punct" and previous.raw == "=>":
        result["function"] = true
        result["async"] = cjs_dyn_arrow_is_async(code, open_index - 1)
        return result
    if previous.kind == "word" and previous.raw == "static":
        result["function"] = true
        result["async"] = false
        return result
    if previous.kind == "word":
        let owner = cjs_code_token_at(code, open_index - 2)
        if owner != nil and owner.kind == "keyword" and owner.raw == "class":
            return result
        let lookback = open_index - 2
        var found_class = false
        var steps = 0
        while lookback >= 0 and steps < 8:
            let probe = code[lookback]
            if probe.kind == "keyword" and probe.raw == "class":
                found_class = true
            if probe.kind == "punct" and (probe.raw == "{" or probe.raw == "}" or probe.raw == ";"):
                break
            lookback = lookback - 1
            steps = steps + 1
        if found_class:
            result["function"] = true
            result["async"] = false
            return result
        return result
    return result

proc cjs_dyn_arrow_is_async(code, arrow_index):
    let previous = cjs_code_token_at(code, arrow_index - 1)
    if previous == nil:
        return false
    if previous.kind == "punct" and previous.raw == ")":
        let open_paren = cjs_dyn_match_opening(code, arrow_index - 1)
        if open_paren >= 0:
            let before = cjs_code_token_at(code, open_paren - 1)
            if before != nil and before.kind == "word" and before.raw == "async":
                return true
        return false
    if previous.kind == "word" and previous.raw == "async":
        return true
    if previous.kind == "word":
        let before = cjs_code_token_at(code, arrow_index - 2)
        if before != nil and before.kind == "word" and before.raw == "async":
            return true
    return false

proc cjs_dyn_await_valid(code, index):
    let contexts = []
    let delimiters = []
    var position = 0
    while position < index:
        let token_value = code[position]
        if cjs_dyn_is_opener(token_value):
            if token_value.raw == "{":
                let owner = cjs_dyn_block_owner(code, position)
                if owner["function"]:
                    let context = {}
                    context["kind"] = "function"
                    context["async"] = owner["async"]
                    context["stack_len"] = len(delimiters)
                    push(contexts, context)
            push(delimiters, token_value)
        elif cjs_dyn_is_closer(token_value):
            if len(delimiters) > 0:
                pop(delimiters)
            let stack_len = len(delimiters)
            while len(contexts) > 0:
                let context = contexts[len(contexts) - 1]
                if context["kind"] == "arrow" and context["stack_len"] > stack_len:
                    pop(contexts)
                elif context["kind"] == "function" and context["stack_len"] >= stack_len:
                    pop(contexts)
                else:
                    break
        elif token_value.kind == "punct" and token_value.raw == "=>":
            let context = {}
            context["kind"] = "arrow"
            context["async"] = cjs_dyn_arrow_is_async(code, position)
            context["stack_len"] = len(delimiters)
            push(contexts, context)
        elif token_value.kind == "punct" and (token_value.raw == ";" or token_value.raw == ","):
            let stack_len = len(delimiters)
            while len(contexts) > 0:
                let context = contexts[len(contexts) - 1]
                if context["kind"] == "arrow" and context["stack_len"] == stack_len:
                    pop(contexts)
                else:
                    break
        position = position + 1
    var context_index = len(contexts) - 1
    while context_index >= 0:
        if contexts[context_index]["kind"] == "arrow" or contexts[context_index]["kind"] == "function":
            return contexts[context_index]["async"]
        context_index = context_index - 1
    return true

proc cjs_dyn_range_has_path_call(code, start, stop):
    var index = start
    while index + 2 < stop:
        let token_value = code[index]
        let dot = code[index + 1]
        let member = code[index + 2]
        if token_value.kind == "word" and token_value.raw == "path" and dot.kind == "punct" and dot.raw == "." and member.kind == "word" and (member.raw == "join" or member.raw == "resolve"):
            return true
        index = index + 1
    return false

proc cjs_dyn_argument_may_be_path(code, require_index, call_stop, args):
    if cjs_dyn_range_has_path_call(code, require_index + 2, call_stop):
        return true
    if len(args) != 1 or args[0].kind != "word":
        return false
    let name = args[0].raw
    var index = 0
    while index < require_index:
        let token_value = code[index]
        if token_value.kind == "word" and token_value.raw == name:
            let assign = cjs_code_token_at(code, index + 1)
            let declaration = cjs_code_token_at(code, index - 1)
            if assign != nil and assign.kind == "punct" and assign.raw == "=" and declaration != nil and declaration.kind == "keyword" and (declaration.raw == "const" or declaration.raw == "let" or declaration.raw == "var"):
                if cjs_dyn_range_has_path_call(code, index + 2, require_index):
                    return true
        index = index + 1
    return false

proc cjs_dyn_rewritable_calls(code):
    let calls = []
    var index = 0
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "word" and token_value.raw == "require":
            let previous = cjs_code_token_at(code, index - 1)
            if previous == nil or previous.kind != "punct" or previous.raw != ".":
                let open = cjs_code_token_at(code, index + 1)
                if open != nil and open.kind == "punct" and open.raw == "(":
                    let call = cjs_match_call(code, index)
                    if call["balanced"] and not cjs_call_has_single_string(call["arguments"]):
                        let args = []
                        var arg_index = 0
                        while arg_index < len(call["arguments"]):
                            if js_is_code_token(call["arguments"][arg_index]):
                                push(args, call["arguments"][arg_index])
                            arg_index = arg_index + 1
                        if len(args) > 0 and cjs_dyn_await_valid(code, index):
                            let entry = {}
                            entry["start"] = token_value.start
                            entry["stop"] = code[call["stop"] - 1].end
                            entry["arg_start"] = args[0].start
                            entry["arg_stop"] = args[len(args) - 1].end
                            entry["arguments"] = args
                            entry["require_index"] = index
                            entry["stop_index"] = call["stop"]
                            entry["line"] = token_value.line
                            push(calls, entry)
                    index = call["stop"]
                else:
                    index = index + 1
            else:
                index = index + 1
        else:
            index = index + 1
    return calls
