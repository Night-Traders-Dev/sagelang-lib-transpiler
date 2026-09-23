gc_disable()
# -----------------------------------------
# converter.sage - Compatibility-first CommonJS to ESM converter
# -----------------------------------------

from lexer.js_scanner import js_scan_source
from lexer.js_token import js_is_code_token

proc cjs_text_in_list(text, values):
    var index = 0
    while index < len(values):
        if values[index] == text:
            return true
        index = index + 1
    return false

proc cjs_is_keyword_text(text):
    let keywords = ["await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "finally", "for", "function", "if", "import", "in", "instanceof", "let", "new", "return", "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield"]
    return cjs_text_in_list(text, keywords)

proc cjs_is_injection_name(text):
    return cjs_text_in_list(text, ["require", "module", "exports", "__filename", "__dirname", "process", "path", "fileURLToPath", "dirname", "createRequire"])

proc cjs_is_runtime_name(text):
    return cjs_text_in_list(text, ["require", "module", "exports", "__filename", "__dirname"])

proc cjs_is_valid_export_name(text):
    if text == nil or text == "":
        return false
    let first = text[0]
    if not (is_js_identifier_start_simple(first)):
        return false
    var index = 1
    while index < len(text):
        if not is_js_identifier_part_simple(text[index]):
            return false
        index = index + 1
    return true

proc is_js_identifier_start_simple(value):
    if value == nil or value == "":
        return false
    if value >= "a" and value <= "z":
        return true
    if value >= "A" and value <= "Z":
        return true
    if value == "_" or value == chr(36):
        return true
    if ord(value) >= 128:
        return true
    return false

proc is_js_identifier_part_simple(value):
    if is_js_identifier_start_simple(value):
        return true
    if value == nil or value == "":
        return false
    return value >= "0" and value <= "9"

proc cjs_starts_with(value, prefix):
    if value == nil or prefix == nil:
        return false
    if len(value) < len(prefix):
        return false
    return slice(value, 0, len(prefix)) == prefix

proc cjs_ends_with(value, suffix):
    if value == nil or suffix == nil:
        return false
    if len(value) < len(suffix):
        return false
    return slice(value, len(value) - len(suffix), len(value)) == suffix

proc cjs_code_token_at(code, index):
    if index < 0 or index >= len(code):
        return nil
    return code[index]

proc cjs_next_code(code, index):
    return cjs_code_token_at(code, index + 1)

proc cjs_previous_code(code, index):
    return cjs_code_token_at(code, index - 1)

proc cjs_unquote_module_name(raw):
    if raw == nil or len(raw) < 2:
        return ""
    let first = raw[0]
    let last = raw[len(raw) - 1]
    if (first == chr(34) or first == chr(39)) and first == last:
        return slice(raw, 1, len(raw) - 1)
    return ""

proc cjs_empty_analysis():
    let analysis = {}
    analysis["ok"] = true
    analysis["message"] = ""
    analysis["code"] = []
    analysis["declared_top"] = {}
    analysis["declared_anywhere"] = {}
    analysis["references"] = {}
    analysis["calls"] = []
    analysis["replacements"] = []
    analysis["diagnostics"] = []
    analysis["has_existing_esm"] = false
    analysis["needs_require"] = false
    analysis["needs_filename"] = false
    analysis["needs_dirname"] = false
    analysis["needs_process"] = false
    analysis["needs_module"] = false
    analysis["dynamic_require_count"] = 0
    analysis["static_require_count"] = 0
    analysis["has_cache_operation"] = false
    analysis["exports_final_names"] = []
    analysis["exports_object_names"] = []
    analysis["exports_shorthand_names"] = []
    analysis["exports_spec_names"] = []
    analysis["exports_has_default"] = false
    analysis["exports_wholesale"] = false
    return analysis

proc cjs_add_diagnostic(analysis, code, message, severity, line):
    let diagnostic = {}
    diagnostic["code"] = code
    diagnostic["message"] = message
    diagnostic["severity"] = severity
    diagnostic["line"] = line
    push(analysis["diagnostics"], diagnostic)
    return true

proc cjs_fail(analysis, code, message, line):
    analysis["ok"] = false
    analysis["message"] = message
    cjs_add_diagnostic(analysis, code, message, "ERROR", line)
    return analysis

proc cjs_mark_top_declaration(analysis, name, line):
    if name == nil or name == "":
        return false
    analysis["declared_top"][name] = true
    analysis["declared_anywhere"][name] = true
    return true

proc cjs_mark_anywhere_declaration(analysis, name, line):
    if name == nil or name == "":
        return false
    analysis["declared_anywhere"][name] = true
    return true

proc cjs_note_reference(analysis, name, token_value):
    if name == nil or name == "":
        return false
    if dict_has(analysis["references"], name):
        analysis["references"][name] = analysis["references"][name] + 1
    else:
        analysis["references"][name] = 1
    return true

proc cjs_remove_reference(analysis, name):
    if not dict_has(analysis["references"], name):
        return false
    if analysis["references"][name] > 0:
        analysis["references"][name] = analysis["references"][name] - 1
    return true

proc cjs_code_tokens(tokens):
    let code = []
    var index = 0
    while index < len(tokens):
        if js_is_code_token(tokens[index]):
            push(code, tokens[index])
        index = index + 1
    return code

proc cjs_skip_expression(code, start):
    var paren = 0
    var brace = 0
    var bracket = 0
    var index = start
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "punct":
            if token_value.raw == "(" or token_value.raw == "{" or token_value.raw == "[":
                if token_value.raw == "(":
                    paren = paren + 1
                elif token_value.raw == "{":
                    brace = brace + 1
                else:
                    bracket = bracket + 1
            elif token_value.raw == ")" or token_value.raw == "}" or token_value.raw == "]":
                if paren == 0 and brace == 0 and bracket == 0:
                    return index
                if token_value.raw == ")":
                    if paren > 0:
                        paren = paren - 1
                    else:
                        return index
                elif token_value.raw == "}":
                    if brace > 0:
                        brace = brace - 1
                    else:
                        return index
                else:
                    if bracket > 0:
                        bracket = bracket - 1
                    else:
                        return index
            elif (token_value.raw == "," or token_value.raw == ";") and paren == 0 and brace == 0 and bracket == 0:
                return index
        elif token_value.kind == "keyword" and paren == 0 and brace == 0 and bracket == 0:
            if cjs_text_in_list(token_value.raw, ["const", "let", "var", "class", "import", "export", "return", "if", "for", "while", "switch", "try", "catch", "throw"]):
                return index
        index = index + 1
    return index

proc cjs_skip_balanced_group(code, start, closing):
    var depth = 1
    var index = start + 1
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "punct":
            if token_value.raw == "(" or token_value.raw == "{" or token_value.raw == "[":
                depth = depth + 1
            elif token_value.raw == ")" or token_value.raw == "}" or token_value.raw == "]":
                depth = depth - 1
                if depth == 0 and token_value.raw == closing:
                    return index + 1
                if depth < 0:
                    return index
        index = index + 1
    return index

proc cjs_append_names(target, names):
    var index = 0
    while index < len(names):
        push(target, names[index])
        index = index + 1
    return true

proc cjs_collect_pattern(code, start, closing):
    let names = []
    var index = start
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "word":
            if cjs_is_keyword_text(token_value.raw):
                if token_value.raw == "function":
                    index = cjs_skip_function_value(code, index)
                elif token_value.raw == "class":
                    index = cjs_skip_class_value(code, index)
                else:
                    index = index + 1
            else:
                let next = cjs_code_token_at(code, index + 1)
                if next != nil and next.kind == "punct" and next.raw == ":":
                    let value = cjs_collect_pattern(code, index + 2, closing)
                    cjs_append_names(names, value["names"])
                    index = value["stop"]
                else:
                    push(names, token_value.raw)
                    index = index + 1
                    let after = cjs_code_token_at(code, index)
                    if after != nil and after.kind == "punct" and after.raw == "=":
                        index = cjs_skip_expression(code, index + 1)
        elif token_value.kind == "string" or token_value.kind == "number":
            let next = cjs_code_token_at(code, index + 1)
            if next != nil and next.kind == "punct" and next.raw == ":":
                let value = cjs_collect_pattern(code, index + 2, closing)
                cjs_append_names(names, value["names"])
                index = value["stop"]
            else:
                index = index + 1
        elif token_value.kind == "punct":
            if token_value.raw == "{":
                let inner = cjs_collect_pattern(code, index + 1, "}")
                cjs_append_names(names, inner["names"])
                index = inner["stop"]
            elif token_value.raw == "[":
                let inner = cjs_collect_pattern(code, index + 1, "]")
                cjs_append_names(names, inner["names"])
                index = inner["stop"]
            elif token_value.raw == "(":
                let inner = cjs_collect_pattern(code, index + 1, ")")
                cjs_append_names(names, inner["names"])
                index = inner["stop"]
            elif token_value.raw == "...":
                index = index + 1
            elif token_value.raw == ":":
                index = index + 1
                let value = cjs_collect_pattern(code, index, closing)
                cjs_append_names(names, value["names"])
                index = value["stop"]
            elif closing != "" and token_value.raw == closing:
                let result = {}
                result["names"] = names
                result["stop"] = index + 1
                return result
            elif closing == "" and (token_value.raw == "," or token_value.raw == ";" or token_value.raw == "="):
                let result = {}
                result["names"] = names
                result["stop"] = index
                return result
            else:
                index = index + 1
        else:
            index = index + 1
    let result = {}
    result["names"] = names
    result["stop"] = index
    return result

proc cjs_skip_function_value(code, start):
    var index = start + 1
    if index < len(code):
        let star = code[index]
        if star.kind == "punct" and star.raw == "*":
            index = index + 1
    if index < len(code):
        let name = code[index]
        if name.kind == "word" and not cjs_is_keyword_text(name.raw):
            index = index + 1
    if index < len(code):
        let params = code[index]
        if params.kind == "punct" and params.raw == "(":
            index = cjs_skip_balanced_group(code, index, ")")
    if index < len(code):
        let body = code[index]
        if body.kind == "punct" and body.raw == "{":
            index = cjs_skip_balanced_group(code, index, "}")
    return index

proc cjs_skip_class_value(code, start):
    var index = start + 1
    if index < len(code):
        let name = code[index]
        if name.kind == "word" and not cjs_is_keyword_text(name.raw):
            index = index + 1
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "punct" and token_value.raw == "{":
            return cjs_skip_balanced_group(code, index, "}")
        if token_value.kind == "punct" and (token_value.raw == ";" or token_value.raw == ","):
            return index
        if token_value.kind == "keyword" and cjs_text_in_list(token_value.raw, ["const", "let", "var", "class", "import", "export", "return"]):
            return index
        index = index + 1
    return index

proc cjs_parse_function_signature(code, start, analysis, is_top):
    var index = start + 1
    if index < len(code):
        let star = code[index]
        if star.kind == "punct" and star.raw == "*":
            index = index + 1
    if index < len(code):
        let name = code[index]
        if name.kind == "word" and not cjs_is_keyword_text(name.raw):
            if is_top:
                cjs_mark_top_declaration(analysis, name.raw, name.line)
            else:
                cjs_mark_anywhere_declaration(analysis, name.raw, name.line)
            index = index + 1
    if index < len(code):
        let params = code[index]
        if params.kind == "punct" and params.raw == "(":
            let parsed = cjs_collect_pattern(code, index + 1, ")")
            var name_index = 0
            while name_index < len(parsed["names"]):
                cjs_mark_anywhere_declaration(analysis, parsed["names"][name_index], params.line)
                name_index = name_index + 1
            index = parsed["stop"]
    let result = {}
    result["stop"] = index
    return result

proc cjs_parse_class_signature(code, start, analysis, is_top):
    var index = start + 1
    if index < len(code):
        let name = code[index]
        if name.kind == "word" and not cjs_is_keyword_text(name.raw):
            if is_top:
                cjs_mark_top_declaration(analysis, name.raw, name.line)
            else:
                cjs_mark_anywhere_declaration(analysis, name.raw, name.line)
            index = index + 1
    let result = {}
    result["stop"] = index
    return result

proc cjs_parse_catch_signature(code, start, analysis):
    var index = start + 1
    if index < len(code):
        let params = code[index]
        if params.kind == "punct" and params.raw == "(":
            let parsed = cjs_collect_pattern(code, index + 1, ")")
            var name_index = 0
            while name_index < len(parsed["names"]):
                cjs_mark_anywhere_declaration(analysis, parsed["names"][name_index], params.line)
                name_index = name_index + 1
            index = parsed["stop"]
    let result = {}
    result["stop"] = index
    return result

proc cjs_parse_variable_statement(code, start, analysis, is_top):
    var index = start + 1
    while index < len(code):
        let parsed = cjs_collect_pattern(code, index, "")
        var name_index = 0
        while name_index < len(parsed["names"]):
            if is_top:
                cjs_mark_top_declaration(analysis, parsed["names"][name_index], code[index].line)
            else:
                cjs_mark_anywhere_declaration(analysis, parsed["names"][name_index], code[index].line)
            name_index = name_index + 1
        index = parsed["stop"]
        if index < len(code):
            let separator = code[index]
            if separator.kind == "punct" and separator.raw == "=":
                index = cjs_skip_expression(code, index + 1)
            elif separator.kind == "punct" and separator.raw == ",":
                index = index + 1
            elif separator.kind == "punct" and separator.raw == ";":
                index = index + 1
                break
            else:
                break
        else:
            break
    let result = {}
    result["stop"] = index
    return result

proc cjs_note_arrow_parameters(code, analysis):
    var index = 0
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "word" and not cjs_is_keyword_text(token_value.raw):
            let next = cjs_code_token_at(code, index + 1)
            if next != nil and next.kind == "punct" and next.raw == "=>":
                cjs_mark_anywhere_declaration(analysis, token_value.raw, token_value.line)
        if token_value.kind == "punct" and token_value.raw == "(":
            let close = cjs_skip_balanced_group(code, index, ")")
            let after = cjs_code_token_at(code, close)
            if after != nil and after.kind == "punct" and after.raw == "=>":
                let parsed = cjs_collect_pattern(code, index + 1, ")")
                var name_index = 0
                while name_index < len(parsed["names"]):
                    cjs_mark_anywhere_declaration(analysis, parsed["names"][name_index], token_value.line)
                    name_index = name_index + 1
        index = index + 1
    return true

proc cjs_match_call(code, index):
    let open = cjs_code_token_at(code, index + 1)
    if open == nil or open.kind != "punct" or open.raw != "(":
        let result = {}
        result["found"] = false
        result["stop"] = index + 1
        result["arguments"] = []
        return result
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
    if depth == 0:
        result["found"] = true
        result["stop"] = position + 1
    else:
        result["found"] = false
        result["stop"] = position
    result["arguments"] = args
    return result

proc cjs_single_string_argument(args):
    if len(args) != 1:
        return ""
    if args[0].kind != "string":
        return ""
    return cjs_unquote_module_name(args[0].raw)

proc cjs_add_replacement(analysis, start, stop, text, line):
    if start < 0 or stop <= start:
        return cjs_fail(analysis, "CJS400", "Invalid replacement span.", line)
    var index = 0
    while index < len(analysis["replacements"]):
        let existing = analysis["replacements"][index]
        if not (stop <= existing["start"] or start >= existing["stop"]):
            return cjs_fail(analysis, "CJS400", "Overlapping replacements are unsupported.", line)
        index = index + 1
    let replacement = {}
    replacement["start"] = start
    replacement["stop"] = stop
    replacement["text"] = text
    push(analysis["replacements"], replacement)
    return true

proc cjs_analyze_declarations(code, analysis):
    var brace_depth = 0
    var index = 0
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "keyword":
            if token_value.raw == "import":
                cjs_fail(analysis, "CJS400", "Existing ECMAScript import syntax is unsupported in this converter version.", token_value.line)
                return index
            if token_value.raw == "export" and brace_depth == 0:
                cjs_fail(analysis, "CJS400", "Existing ECMAScript export syntax is unsupported in this converter version.", token_value.line)
                return index
            if (token_value.raw == "const" or token_value.raw == "let" or token_value.raw == "var") and brace_depth == 0:
                let parsed = cjs_parse_variable_statement(code, index, analysis, true)
                index = parsed["stop"]
            elif (token_value.raw == "const" or token_value.raw == "let" or token_value.raw == "var"):
                let parsed = cjs_parse_variable_statement(code, index, analysis, false)
                index = parsed["stop"]
            elif token_value.raw == "function":
                let parsed = cjs_parse_function_signature(code, index, analysis, brace_depth == 0)
                index = parsed["stop"]
            elif token_value.raw == "class":
                let parsed = cjs_parse_class_signature(code, index, analysis, brace_depth == 0)
                index = parsed["stop"]
            elif token_value.raw == "catch":
                let parsed = cjs_parse_catch_signature(code, index, analysis)
                index = parsed["stop"]
            elif token_value.raw == "return" and brace_depth == 0:
                cjs_fail(analysis, "CJS402", "Top-level return is unsupported in this converter version.", token_value.line)
                return index
            else:
                index = index + 1
        elif token_value.kind == "punct":
            if token_value.raw == "{":
                brace_depth = brace_depth + 1
            elif token_value.raw == "}":
                brace_depth = brace_depth - 1
                if brace_depth < 0:
                    cjs_fail(analysis, "CJS403", "Unbalanced closing brace.", token_value.line)
                    return index
            index = index + 1
        else:
            index = index + 1
    if brace_depth != 0:
        cjs_fail(analysis, "CJS403", "Unbalanced braces.", code[len(code) - 1].line)
        return index
    cjs_note_arrow_parameters(code, analysis)
    return index

proc cjs_require_call_details(code, index):
    let call = cjs_match_call(code, index + 1)
    let details = {}
    details["found"] = call["found"]
    details["stop"] = call["stop"]
    details["static_name"] = ""
    details["is_static"] = false
    if call["found"]:
        let args = call["arguments"]
        let values = []
        var arg_index = 0
        while arg_index < len(args):
            if js_is_code_token(args[arg_index]):
                push(values, args[arg_index])
            arg_index = arg_index + 1
        if len(values) == 1 and values[0].kind == "string":
            details["is_static"] = true
            details["static_name"] = cjs_unquote_module_name(values[0].raw)
    return details

proc cjs_analyze_references(code, analysis, path):
    var brace_depth = 0
    var index = 0
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "word":
            let previous = cjs_previous_code(code, index)
            let is_property = previous != nil and previous.kind == "punct" and previous.raw == "."
            if token_value.raw == "require" and not is_property and not dict_has(analysis["declared_anywhere"], "require"):
                cjs_note_reference(analysis, "require", token_value)
                analysis["needs_require"] = true
                let call = cjs_require_call_details(code, index)
                if call["found"]:
                    if call["is_static"]:
                        analysis["static_require_count"] = analysis["static_require_count"] + 1
                        cjs_add_diagnostic(analysis, "CJS102", "Static require preserved on createRequire at line " + str(token_value.line) + " [COMPAT_SHIM].", "NOTE", token_value.line)
                    else:
                        analysis["dynamic_require_count"] = analysis["dynamic_require_count"] + 1
                        cjs_add_diagnostic(analysis, "CJS102", "Dynamic require preserved on createRequire at line " + str(token_value.line) + " [COMPAT_SHIM].", "NOTE", token_value.line)
                    index = call["stop"]
                else:
                    index = index + 1
            elif token_value.raw == "module" and not is_property and not dict_has(analysis["declared_anywhere"], "module"):
                cjs_note_reference(analysis, "module", token_value)
                analysis["needs_module"] = true
                index = index + 1
            elif token_value.raw == "exports" and not is_property and not dict_has(analysis["declared_anywhere"], "exports"):
                cjs_note_reference(analysis, "exports", token_value)
                analysis["needs_module"] = true
                index = index + 1
            elif token_value.raw == "__filename" and not is_property and not dict_has(analysis["declared_anywhere"], "__filename"):
                cjs_note_reference(analysis, "__filename", token_value)
                analysis["needs_filename"] = true
                index = index + 1
            elif token_value.raw == "__dirname" and not is_property and not dict_has(analysis["declared_anywhere"], "__dirname"):
                cjs_note_reference(analysis, "__dirname", token_value)
                analysis["needs_dirname"] = true
                analysis["needs_filename"] = true
                index = index + 1
            elif token_value.raw == "this" and brace_depth == 0:
                cjs_fail(analysis, "CJS402", "Top-level this is unsupported in this converter version.", token_value.line)
                return index
            elif token_value.raw == "arguments" and brace_depth == 0:
                cjs_fail(analysis, "CJS402", "Top-level arguments is unsupported in this converter version.", token_value.line)
                return index
            else:
                index = index + 1
        elif token_value.kind == "keyword":
            if token_value.raw == "return" and brace_depth == 0:
                cjs_fail(analysis, "CJS402", "Top-level return is unsupported in this converter version.", token_value.line)
                return index
            index = index + 1
        elif token_value.kind == "punct":
            if token_value.raw == "{":
                brace_depth = brace_depth + 1
            elif token_value.raw == "}":
                brace_depth = brace_depth - 1
            index = index + 1
        else:
            index = index + 1
    return index

proc cjs_replace_runtime_names(code, analysis):
    var index = 0
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "word":
            let previous = cjs_previous_code(code, index)
            let is_property = previous != nil and previous.kind == "punct" and previous.raw == "."
            if token_value.raw == "__filename" and not is_property and not dict_has(analysis["declared_anywhere"], "__filename"):
                cjs_add_replacement(analysis, token_value.start, token_value.end, "fileURLToPath(import.meta.url)", token_value.line)
                cjs_add_diagnostic(analysis, "CJS103", "__filename converted to fileURLToPath at line " + str(token_value.line) + " [SAFE].", "NOTE", token_value.line)
            elif token_value.raw == "__dirname" and not is_property and not dict_has(analysis["declared_anywhere"], "__dirname"):
                cjs_add_replacement(analysis, token_value.start, token_value.end, "dirname(fileURLToPath(import.meta.url))", token_value.line)
                cjs_add_diagnostic(analysis, "CJS103", "__dirname converted to dirname at line " + str(token_value.line) + " [SAFE].", "NOTE", token_value.line)
            elif token_value.raw == "require" and not is_property and not dict_has(analysis["declared_anywhere"], "require"):
                let first_dot = cjs_code_token_at(code, index + 1)
                let member = cjs_code_token_at(code, index + 2)
                let operation = cjs_code_token_at(code, index + 3)
                let target = cjs_code_token_at(code, index + 4)
                if first_dot != nil and member != nil and operation != nil and target != nil and first_dot.kind == "punct" and first_dot.raw == "." and member.kind == "word" and member.raw == "main" and operation.kind == "punct" and operation.raw == "===" and target.kind == "word" and target.raw == "module" and not dict_has(analysis["declared_anywhere"], "module"):
                    cjs_add_replacement(analysis, token_value.start, target.end, "process.argv[1] === fileURLToPath(import.meta.url)", token_value.line)
                    analysis["needs_process"] = true
                    cjs_remove_reference(analysis, "require")
                    cjs_remove_reference(analysis, "module")
                    if not dict_has(analysis["references"], "require") or analysis["references"]["require"] == 0:
                        analysis["needs_require"] = false
                    if not dict_has(analysis["references"], "module") or analysis["references"]["module"] == 0:
                        analysis["needs_module"] = false
                    cjs_add_diagnostic(analysis, "CJS103", "require.main entry check converted to argv comparison at line " + str(token_value.line) + " [SAFE].", "NOTE", token_value.line)
                    index = index + 4
            elif token_value.raw == "module" and not is_property and not dict_has(analysis["declared_anywhere"], "module"):
                let operation = cjs_code_token_at(code, index + 1)
                let target = cjs_code_token_at(code, index + 2)
                let first_dot = cjs_code_token_at(code, index + 3)
                let member = cjs_code_token_at(code, index + 4)
                if operation != nil and target != nil and first_dot != nil and member != nil and operation.kind == "punct" and operation.raw == "===" and target.kind == "word" and target.raw == "require" and first_dot.kind == "punct" and first_dot.raw == "." and member.kind == "word" and member.raw == "main" and not dict_has(analysis["declared_anywhere"], "require"):
                    cjs_add_replacement(analysis, token_value.start, member.end, "process.argv[1] === fileURLToPath(import.meta.url)", token_value.line)
                    analysis["needs_process"] = true
                    cjs_remove_reference(analysis, "require")
                    cjs_remove_reference(analysis, "module")
                    if not dict_has(analysis["references"], "require") or analysis["references"]["require"] == 0:
                        analysis["needs_require"] = false
                    if not dict_has(analysis["references"], "module") or analysis["references"]["module"] == 0:
                        analysis["needs_module"] = false
                    cjs_add_diagnostic(analysis, "CJS103", "require.main entry check converted to argv comparison at line " + str(token_value.line) + " [SAFE].", "NOTE", token_value.line)
                    index = index + 4
        index = index + 1
    return true

proc cjs_analyze_cache_operations(code, analysis):
    var index = 0
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "keyword" and token_value.raw == "delete":
            let target = cjs_code_token_at(code, index + 1)
            let dot = cjs_code_token_at(code, index + 2)
            let cache = cjs_code_token_at(code, index + 3)
            if target != nil and target.kind == "word" and target.raw == "require" and dot != nil and dot.kind == "punct" and dot.raw == "." and cache != nil and cache.kind == "word" and cache.raw == "cache":
                analysis["has_cache_operation"] = true
                cjs_add_diagnostic(analysis, "CJS202", "require.cache manipulation preserved on createRequire at line " + str(token_value.line) + " [MANUAL_REVIEW].", "WARNING", token_value.line)
        index = index + 1
    return true

proc cjs_object_property_name(code, index):
    let token_value = cjs_code_token_at(code, index)
    if token_value == nil:
        return ""
    if token_value.kind == "word" and not cjs_is_keyword_text(token_value.raw):
        return token_value.raw
    if token_value.kind == "string":
        return cjs_unquote_module_name(token_value.raw)
    return ""

proc cjs_parse_object_key(code, index):
    let token_value = cjs_code_token_at(code, index)
    let result = {}
    result["name"] = ""
    result["stop"] = index
    if token_value == nil:
        return result
    if token_value.kind == "word" and (token_value.raw == "async" or token_value.raw == "get" or token_value.raw == "set"):
        let candidate = cjs_code_token_at(code, index + 1)
        let opener = cjs_code_token_at(code, index + 2)
        let star = cjs_code_token_at(code, index + 1)
        if candidate != nil and candidate.kind == "punct" and candidate.raw == "*":
            let actual = cjs_code_token_at(code, index + 2)
            if actual != nil:
                result["name"] = cjs_object_property_name(code, index + 2)
                result["stop"] = index + 3
                return result
        if candidate != nil and opener != nil and ((candidate.kind == "word" and not cjs_is_keyword_text(candidate.raw)) or candidate.kind == "string") and opener.kind == "punct" and opener.raw == "(":
            result["name"] = cjs_object_property_name(code, index + 1)
            result["stop"] = index + 2
            return result
        if token_value.kind == "word" and not cjs_is_keyword_text(token_value.raw):
            result["name"] = token_value.raw
            result["stop"] = index + 1
            return result
        return result
    if token_value.kind == "punct" and token_value.raw == "*":
        let actual = cjs_code_token_at(code, index + 1)
        if actual != nil:
            result["name"] = cjs_object_property_name(code, index + 1)
            result["stop"] = index + 2
            return result
        return result
    if token_value.kind == "punct" and token_value.raw == "[":
        let close = cjs_skip_balanced_group(code, index, "]")
        let inner = []
        var inner_index = index + 1
        while inner_index < close - 1:
            push(inner, code[inner_index])
            inner_index = inner_index + 1
        if len(inner) == 1 and inner[0].kind == "string":
            result["name"] = cjs_object_property_name(code, index + 1)
        result["stop"] = close
        return result
    result["name"] = cjs_object_property_name(code, index)
    result["stop"] = index + 1
    return result

proc cjs_skip_object_method(code, index):
    var position = index
    if position < len(code):
        let star = code[position]
        if star.kind == "punct" and star.raw == "*":
            position = position + 1
    if position < len(code):
        let params = code[position]
        if params.kind == "punct" and params.raw == "(":
            position = cjs_skip_balanced_group(code, position, ")")
    if position < len(code):
        let body = code[position]
        if body.kind == "punct" and body.raw == "{":
            position = cjs_skip_balanced_group(code, position, "}")
    return position

proc cjs_collect_object_property_names(code, open_index):
    let names = []
    let shorthands = []
    var index = open_index + 1
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "punct" and token_value.raw == "}":
            let result = {}
            result["names"] = names
            result["shorthands"] = shorthands
            result["stop"] = index + 1
            return result
        if token_value.kind == "punct" and token_value.raw == ",":
            index = index + 1
        elif token_value.kind == "punct" and token_value.raw == "...":
            index = cjs_skip_expression(code, index + 1)
        else:
            let parsed = cjs_parse_object_key(code, index)
            if parsed["name"] == "" or parsed["name"] == "__proto__":
                index = cjs_skip_expression(code, parsed["stop"])
            else:
                let separator = cjs_code_token_at(code, parsed["stop"])
                if separator != nil and separator.kind == "punct" and separator.raw == ":":
                    if cjs_is_valid_export_name(parsed["name"]):
                        push(names, parsed["name"])
                    index = cjs_skip_expression(code, parsed["stop"] + 1)
                elif separator != nil and separator.kind == "punct" and separator.raw == "(":
                    if cjs_is_valid_export_name(parsed["name"]):
                        push(names, parsed["name"])
                    index = cjs_skip_object_method(code, parsed["stop"])
                else:
                    let maybe = cjs_code_token_at(code, parsed["stop"])
                    if token_value.kind == "word" and not cjs_is_keyword_text(token_value.raw) and cjs_is_valid_export_name(parsed["name"]):
                        push(names, parsed["name"])
                        push(shorthands, parsed["name"])
                    if maybe != nil and maybe.kind == "punct" and maybe.raw == "=":
                        index = cjs_skip_expression(code, parsed["stop"] + 1)
                    else:
                        index = parsed["stop"]
    let result = {}
    result["names"] = names
    result["shorthands"] = shorthands
    result["stop"] = index
    return result

proc cjs_collect_wholesale_exports(code, analysis):
    var wholesale_index = -1
    var index = 0
    while index + 3 < len(code):
        let target = code[index]
        let dot = code[index + 1]
        let name = code[index + 2]
        let assign = code[index + 3]
        if target.kind == "word" and target.raw == "module" and dot.kind == "punct" and dot.raw == "." and name.kind == "word" and name.raw == "exports" and assign.kind == "punct" and assign.raw == "=":
            let after = cjs_code_token_at(code, index + 4)
            if after == nil or after.kind != "punct" or (after.raw != "=" and after.raw != "=>"):
                wholesale_index = index + 3
                analysis["exports_wholesale"] = true
                analysis["exports_object_names"] = []
                analysis["exports_shorthand_names"] = []
                analysis["exports_spec_names"] = []
                if after != nil and after.kind == "punct" and after.raw == "{":
                    let properties = cjs_collect_object_property_names(code, index + 4)
                    analysis["exports_object_names"] = properties["names"]
                    analysis["exports_shorthand_names"] = properties["shorthands"]
                cjs_add_diagnostic(analysis, "CJS301", "module.exports reassignment preserved through default export at line " + str(target.line) + " [COMPAT_SHIM].", "NOTE", target.line)
        index = index + 1
    return wholesale_index

proc cjs_record_assignment_exports(code, analysis, wholesale_index):
    let names = []
    var alias_targets = {}
    var index = 0
    while index < len(code):
        let token_value = code[index]
        if token_value.kind == "word" and not cjs_is_keyword_text(token_value.raw):
            let assign = cjs_code_token_at(code, index + 1)
            if assign != nil and assign.kind == "punct" and assign.raw == "=":
                let value = cjs_code_token_at(code, index + 2)
                if value != nil:
                    if value.kind == "word" and value.raw == "module":
                        let dot = cjs_code_token_at(code, index + 3)
                        let suffix = cjs_code_token_at(code, index + 4)
                        if dot != nil and dot.kind == "punct" and dot.raw == "." and suffix != nil and suffix.kind == "word" and suffix.raw == "exports":
                            alias_targets[token_value.raw] = wholesale_index
                    elif value.kind == "word" and value.raw == "exports":
                        alias_targets[token_value.raw] = wholesale_index
                    elif dict_has(alias_targets, token_value.raw):
                        alias_targets[token_value.raw] = -2
        if token_value.kind == "word" and token_value.raw == "module":
            let dot = cjs_code_token_at(code, index + 1)
            let name = cjs_code_token_at(code, index + 2)
            let assign = cjs_code_token_at(code, index + 3)
            if dot != nil and dot.kind == "punct" and dot.raw == "." and name != nil and name.kind == "word" and name.raw == "exports":
                if assign != nil and assign.kind == "punct" and assign.raw == ".":
                    let property_name = cjs_code_token_at(code, index + 4)
                    let property_assign = cjs_code_token_at(code, index + 5)
                    if property_name != nil and property_name.kind == "word" and property_assign != nil and property_assign.kind == "punct" and property_assign.raw == "=":
                        let after = cjs_code_token_at(code, index + 6)
                        if after == nil or after.kind != "punct" or (after.raw != "=" and after.raw != "=>"):
                            if index > wholesale_index and cjs_is_valid_export_name(property_name.raw):
                                push(names, property_name.raw)
                                if after.kind == "word" and after.raw == property_name.raw:
                                    push(analysis["exports_spec_names"], property_name.raw)
        if token_value.kind == "word" and (token_value.raw == "exports" or dict_has(alias_targets, token_value.raw)):
            let dot = cjs_code_token_at(code, index + 1)
            let property_name = cjs_code_token_at(code, index + 2)
            let assign = cjs_code_token_at(code, index + 3)
            if dot != nil and dot.kind == "punct" and dot.raw == "." and property_name != nil and property_name.kind == "word" and assign != nil and assign.kind == "punct" and assign.raw == "=":
                let after = cjs_code_token_at(code, index + 4)
                if after == nil or after.kind != "punct" or (after.raw != "=" and after.raw != "=>"):
                    if index > wholesale_index and cjs_is_valid_export_name(property_name.raw):
                        push(names, property_name.raw)
                        if after.kind == "word" and after.raw == property_name.raw:
                            push(analysis["exports_spec_names"], property_name.raw)
        index = index + 1
    let combined = []
    var object_index = 0
    while object_index < len(analysis["exports_object_names"]):
        push(combined, analysis["exports_object_names"][object_index])
        object_index = object_index + 1
    var name_index = 0
    while name_index < len(names):
        push(combined, names[name_index])
        name_index = name_index + 1
    let unique = []
    var unique_index = 0
    while unique_index < len(combined):
        if not cjs_text_in_list(combined[unique_index], unique):
            push(unique, combined[unique_index])
        unique_index = unique_index + 1
    analysis["exports_final_names"] = unique
    return true

proc cjs_apply_replacements(source, replacements):
    let output = ""
    var cursor = 0
    var index = 0
    while index < len(replacements):
        let replacement = replacements[index]
        if replacement["start"] < cursor:
            let failure = {}
            failure["ok"] = false
            failure["message"] = "Overlapping replacements are unsupported."
            return failure
        output = output + slice(source, cursor, replacement["start"]) + replacement["text"]
        cursor = replacement["stop"]
        index = index + 1
    output = output + slice(source, cursor, len(source))
    let result = {}
    result["ok"] = true
    result["code"] = output
    return result

proc cjs_build_output(source, body, analysis):
    let newline = chr(10)
    let prologue = ""
    if analysis["needs_require"]:
        prologue = prologue + "import { createRequire } from " + chr(34) + "node:module" + chr(34) + ";" + newline
    if analysis["needs_filename"] or analysis["needs_dirname"] or analysis["needs_process"]:
        prologue = prologue + "import { fileURLToPath } from " + chr(34) + "node:url" + chr(34) + ";" + newline
    if analysis["needs_dirname"]:
        prologue = prologue + "import { dirname } from " + chr(34) + "node:path" + chr(34) + ";" + newline
    if analysis["needs_process"]:
        prologue = prologue + "import process from " + chr(34) + "node:process" + chr(34) + ";" + newline
    if analysis["needs_require"]:
        prologue = prologue + "const require = createRequire(import.meta.url);" + newline
    if analysis["needs_filename"]:
        prologue = prologue + "const __filename = fileURLToPath(import.meta.url);" + newline
    if analysis["needs_dirname"]:
        prologue = prologue + "const __dirname = dirname(__filename);" + newline
    if analysis["needs_module"]:
        prologue = prologue + "const module = { exports: {} };" + newline
        prologue = prologue + "const exports = module.exports;" + newline
    if prologue != "":
        prologue = prologue + newline
    let footer = ""
    if analysis["needs_module"]:
        footer = footer + newline + ";" + newline + "export default module.exports;" + newline
        var name_index = 0
        while name_index < len(analysis["exports_final_names"]):
            let export_name = analysis["exports_final_names"][name_index]
            if (cjs_text_in_list(export_name, analysis["exports_shorthand_names"]) or cjs_text_in_list(export_name, analysis["exports_spec_names"])) and dict_has(analysis["declared_top"], export_name):
                footer = footer + "export { " + export_name + " };" + newline
            elif dict_has(analysis["declared_top"], export_name):
                return cjs_fail(analysis, "CJS401", "Export name collides with an existing top-level binding.", 1)
            else:
                footer = footer + "export const " + export_name + " = module.exports." + export_name + ";" + newline
            name_index = name_index + 1
    if cjs_starts_with(source, "#!"):
        var split = 0
        while split < len(source):
            if source[split] == chr(10):
                break
            split = split + 1
        let head = slice(source, 0, split + 1)
        let remainder = slice(source, split + 1, len(source))
        return head + prologue + body + footer
    return prologue + body + footer

proc convert_cjs_text(source, target, mode):
    if target != "node18" and target != "node20" and target != "node22" and target != "node24":
        let failure = {}
        failure["ok"] = false
        failure["message"] = "Unsupported target. Use node18, node20, node22, or node24."
        failure["code"] = ""
        failure["diagnostics"] = []
        return failure
    if mode != "compat" and mode != "discord":
        let failure = {}
        failure["ok"] = false
        failure["message"] = "Only compat and discord modes are implemented in this converter version."
        failure["code"] = ""
        failure["diagnostics"] = []
        return failure
    let scan = js_scan_source(source)
    if len(scan["errors"]) > 0:
        let failure = {}
        failure["ok"] = false
        failure["message"] = scan["errors"][0]["message"]
        failure["code"] = ""
        failure["diagnostics"] = []
        return failure
    let analysis = cjs_empty_analysis()
    let code = cjs_code_tokens(scan["tokens"])
    cjs_analyze_declarations(code, analysis)
    if not analysis["ok"]:
        let failure = {}
        failure["ok"] = false
        failure["message"] = analysis["message"]
        failure["code"] = ""
        failure["diagnostics"] = analysis["diagnostics"]
        return failure
    cjs_analyze_references(code, analysis, "")
    if not analysis["ok"]:
        let failure = {}
        failure["ok"] = false
        failure["message"] = analysis["message"]
        failure["code"] = ""
        failure["diagnostics"] = analysis["diagnostics"]
        return failure
    cjs_analyze_cache_operations(code, analysis)
    let wholesale_index = cjs_collect_wholesale_exports(code, analysis)
    cjs_record_assignment_exports(code, analysis, wholesale_index)
    let injection_names = ["require", "module", "exports", "__filename", "__dirname"]
    var injection_index = 0
    while injection_index < len(injection_names):
        let injection_name = injection_names[injection_index]
        if dict_has(analysis["declared_anywhere"], injection_name):
            let failure = {}
            failure["ok"] = false
            failure["message"] = "A local declaration shadows " + injection_name + "."
            failure["code"] = ""
            failure["diagnostics"] = analysis["diagnostics"]
            cjs_add_diagnostic(analysis, "CJS401", "Local declaration shadows " + injection_name + ".", "ERROR", 1)
            failure["diagnostics"] = analysis["diagnostics"]
            return failure
        injection_index = injection_index + 1
    cjs_replace_runtime_names(code, analysis)
    if not analysis["ok"]:
        let failure = {}
        failure["ok"] = false
        failure["message"] = analysis["message"]
        failure["code"] = ""
        failure["diagnostics"] = analysis["diagnostics"]
        return failure
    let replaced = cjs_apply_replacements(source, analysis["replacements"])
    if not replaced["ok"]:
        let failure = {}
        failure["ok"] = false
        failure["message"] = replaced["message"]
        failure["code"] = ""
        failure["diagnostics"] = analysis["diagnostics"]
        return failure
    let output = cjs_build_output(source, replaced["code"], analysis)
    if type(output) != "string":
        let failure = {}
        failure["ok"] = false
        failure["message"] = output["message"]
        failure["code"] = ""
        failure["diagnostics"] = analysis["diagnostics"]
        return failure
    let result = {}
    result["ok"] = true
    result["code"] = output
    result["diagnostics"] = analysis["diagnostics"]
    return result

proc convert_cjs_file(input_path, output_path, target, mode):
    import io
    let source = io.readfile(input_path)
    if source == nil:
        let failure = {}
        failure["ok"] = false
        failure["message"] = "Input file could not be read."
        failure["code"] = ""
        failure["diagnostics"] = []
        return failure
    let converted = convert_cjs_text(source, target, mode)
    if not converted["ok"]:
        return converted
    let parent = path_dirname(output_path)
    if parent != "" and parent != "." and not io.exists(parent):
        if not cjs_ensure_parent_directory(parent):
            let failure = {}
            failure["ok"] = false
            failure["message"] = "Output directory could not be created."
            failure["code"] = ""
            failure["diagnostics"] = converted["diagnostics"]
            return failure
    if not io.writefile(output_path, converted["code"]):
        let failure = {}
        failure["ok"] = false
        failure["message"] = "Output file could not be written."
        failure["code"] = ""
        failure["diagnostics"] = converted["diagnostics"]
        return failure
    let result = {}
    result["ok"] = true
    result["code"] = converted["code"]
    result["diagnostics"] = converted["diagnostics"]
    return result

proc cjs_ensure_parent_directory(parent):
    import io
    if parent == "" or parent == "." or parent == "/":
        return true
    if io.exists(parent):
        return true
    let grandparent = path_dirname(parent)
    if grandparent != parent:
        if not cjs_ensure_parent_directory(grandparent):
            return false
    return io.mkdir(parent)
