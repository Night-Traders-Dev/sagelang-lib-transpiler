gc_disable()
# -----------------------------------------
# statements.sage - Top-level statement splitter for cjs2esm
# -----------------------------------------

from transpiler.cjs2esm.lexer.js_token import js_is_code_token

proc cjs_statement_items(scan):
    let items = []
    var pending_break = false
    var index = 0
    while index < len(scan["tokens"]):
        let token_value = scan["tokens"][index]
        if token_value.kind == "newline":
            pending_break = true
        elif token_value.kind == "comment":
            if js_comment_has_newline(token_value.raw):
                pending_break = true
        elif js_is_code_token(token_value):
            let item = {}
            item["token"] = token_value
            item["hard_break"] = pending_break
            push(items, item)
            pending_break = false
        index = index + 1
    return items

proc js_comment_has_newline(raw):
    var index = 0
    while index < len(raw):
        if raw[index] == chr(10):
            return true
        index = index + 1
    return false

proc cjs_can_end_statement(token_value):
    if token_value.kind == "word" or token_value.kind == "keyword":
        return true
    if token_value.kind == "number" or token_value.kind == "string" or token_value.kind == "regex":
        return true
    if token_value.kind == "template_end":
        return true
    if token_value.kind == "punct":
        if token_value.raw == ")" or token_value.raw == "]" or token_value.raw == "}":
            return true
        if token_value.raw == "++" or token_value.raw == "--":
            return true
    return false

proc cjs_can_start_statement(token_value):
    if token_value.kind == "punct":
        if token_value.raw == "." or token_value.raw == "(" or token_value.raw == "[" or token_value.raw == ",":
            return false
        if token_value.raw == "+" or token_value.raw == "-" or token_value.raw == "*" or token_value.raw == "/" or token_value.raw == "%":
            return false
        if token_value.raw == "?" or token_value.raw == ":" or token_value.raw == "=>":
            return false
        if token_value.raw == "==" or token_value.raw == "!=" or token_value.raw == "===" or token_value.raw == "!==":
            return false
        if token_value.raw == "<" or token_value.raw == ">" or token_value.raw == "<=" or token_value.raw == ">=":
            return false
        if token_value.raw == "&&" or token_value.raw == "||" or token_value.raw == "??":
            return false
        if token_value.raw == "else" or token_value.raw == "catch" or token_value.raw == "finally" or token_value.raw == "while":
            return false
    return true

proc cjs_skip_balanced_items(items, start, closing):
    var depth = 1
    var index = start + 1
    while index < len(items):
        let raw = items[index]["token"].raw
        let kind = items[index]["token"].kind
        if kind == "punct":
            if raw == "(" or raw == "[" or raw == "{":
                depth = depth + 1
            elif raw == ")" or raw == "]" or raw == "}":
                depth = depth - 1
                if depth == 0 and raw == closing:
                    return index + 1
                if depth < 0:
                    return index
        elif kind == "template_start":
            depth = depth + 1
        elif kind == "template_end":
            depth = depth - 1
            if depth == 0 and closing == "template_end":
                return index + 1
            if depth < 0:
                return index
        index = index + 1
    return index

proc cjs_parse_declarators(items, start):
    let declarators = []
    var index = start
    while index < len(items):
        let pattern_start = index
        var depth = 0
        while index < len(items):
            let token_value = items[index]["token"]
            if token_value.kind == "punct":
                if token_value.raw == "(" or token_value.raw == "[" or token_value.raw == "{":
                    depth = depth + 1
                elif token_value.raw == ")" or token_value.raw == "]" or token_value.raw == "}":
                    if depth == 0:
                        break
                    depth = depth - 1
                elif (token_value.raw == "," or token_value.raw == ";" or token_value.raw == "=") and depth == 0:
                    break
            elif token_value.kind == "template_start":
                depth = depth + 1
            elif token_value.kind == "template_end":
                depth = depth - 1
            index = index + 1
        let declarator = {}
        declarator["pattern_start"] = pattern_start
        declarator["pattern_stop"] = index
        declarator["init_start"] = -1
        declarator["init_stop"] = index
        let assign = cjs_item_at(items, index)
        if assign != nil and assign["token"].kind == "punct" and assign["token"].raw == "=":
            index = index + 1
            declarator["init_start"] = index
            var idepth = 0
            while index < len(items):
                let token_value = items[index]["token"]
                if token_value.kind == "punct":
                    if token_value.raw == "(" or token_value.raw == "[" or token_value.raw == "{":
                        idepth = idepth + 1
                    elif token_value.raw == ")" or token_value.raw == "]" or token_value.raw == "}":
                        if idepth == 0:
                            break
                        idepth = idepth - 1
                    elif (token_value.raw == "," or token_value.raw == ";") and idepth == 0:
                        break
                elif token_value.kind == "template_start":
                    idepth = idepth + 1
                elif token_value.kind == "template_end":
                    idepth = idepth - 1
                elif token_value.hard_break and idepth == 0:
                    break
                index = index + 1
            declarator["init_stop"] = index
        push(declarators, declarator)
        let separator = cjs_item_at(items, index)
        if separator != nil and separator["token"].kind == "punct" and separator["token"].raw == ",":
            index = index + 1
        elif separator != nil and separator["token"].kind == "punct" and separator["token"].raw == ";":
            index = index + 1
            break
        else:
            break
    let result = {}
    result["declarators"] = declarators
    result["stop"] = index
    return result

proc cjs_item_at(items, index):
    if index < 0 or index >= len(items):
        return nil
    return items[index]

proc parse_statements(scan):
    let items = cjs_statement_items(scan)
    let statements = []
    let errors = []
    var index = 0
    while index < len(items):
        let token_value = items[index]["token"]
        if token_value.kind == "keyword" and (token_value.raw == "const" or token_value.raw == "let" or token_value.raw == "var"):
            let parsed = cjs_parse_declarators(items, index + 1)
            let statement = {}
            statement["kind"] = "variable_declaration"
            statement["start"] = index
            statement["stop"] = parsed["stop"]
            statement["line"] = token_value.line
            statement["declarators"] = parsed["declarators"]
            push(statements, statement)
            index = parsed["stop"]
        elif token_value.kind == "keyword" and token_value.raw == "function":
            let stop = cjs_skip_statement_function(items, index)
            let statement = {}
            statement["kind"] = "function_declaration"
            statement["start"] = index
            statement["stop"] = stop
            statement["line"] = token_value.line
            push(statements, statement)
            index = stop
        elif token_value.kind == "keyword" and token_value.raw == "class":
            let stop = cjs_skip_statement_class(items, index)
            let statement = {}
            statement["kind"] = "class_declaration"
            statement["start"] = index
            statement["stop"] = stop
            statement["line"] = token_value.line
            push(statements, statement)
            index = stop
        elif token_value.kind == "keyword" and (token_value.raw == "import" or token_value.raw == "export"):
            let stop = cjs_skip_to_terminator(items, index)
            let statement = {}
            statement["kind"] = "esm"
            statement["start"] = index
            statement["stop"] = stop
            statement["line"] = token_value.line
            push(statements, statement)
            index = stop
        elif token_value.kind == "punct" and token_value.raw == ";":
            let statement = {}
            statement["kind"] = "empty"
            statement["start"] = index
            statement["stop"] = index + 1
            statement["line"] = token_value.line
            push(statements, statement)
            index = index + 1
        elif token_value.kind == "punct" and token_value.raw == "{":
            let stop = cjs_skip_balanced_items(items, index, "}")
            let statement = {}
            statement["kind"] = "block"
            statement["start"] = index
            statement["stop"] = stop
            statement["line"] = token_value.line
            push(statements, statement)
            index = stop
        else:
            let stop = cjs_skip_expression_statement(items, index)
            let statement = {}
            statement["kind"] = "expression"
            statement["start"] = index
            statement["stop"] = stop
            statement["line"] = token_value.line
            push(statements, statement)
            index = stop
    let result = {}
    result["statements"] = statements
    result["errors"] = errors
    return result

proc cjs_skip_to_terminator(items, index):
    var depth = 0
    var position = index
    while position < len(items):
        let token_value = items[position]["token"]
        if token_value.kind == "punct":
            if token_value.raw == "(" or token_value.raw == "[" or token_value.raw == "{":
                depth = depth + 1
            elif token_value.raw == ")" or token_value.raw == "]" or token_value.raw == "}":
                if depth == 0:
                    return position
                depth = depth - 1
            elif token_value.raw == ";" and depth == 0:
                return position + 1
        elif token_value.kind == "template_start":
            depth = depth + 1
        elif token_value.kind == "template_end":
            depth = depth - 1
        elif items[position]["hard_break"] and depth == 0 and position > index:
            let previous = items[position - 1]["token"]
            if cjs_can_end_statement(previous) and cjs_can_start_statement(token_value):
                return position
        position = position + 1
    return position

proc cjs_skip_expression_statement(items, index):
    var depth = 0
    var position = index
    while position < len(items):
        let token_value = items[position]["token"]
        if token_value.kind == "punct":
            if token_value.raw == "(" or token_value.raw == "[" or token_value.raw == "{":
                depth = depth + 1
            elif token_value.raw == ")" or token_value.raw == "]" or token_value.raw == "}":
                if depth == 0:
                    return position
                depth = depth - 1
            elif token_value.raw == ";" and depth == 0:
                return position + 1
        elif token_value.kind == "template_start":
            depth = depth + 1
        elif token_value.kind == "template_end":
            depth = depth - 1
        elif items[position]["hard_break"] and depth == 0 and position > index:
            let previous = items[position - 1]["token"]
            if cjs_can_end_statement(previous) and cjs_can_start_statement(token_value):
                return position
        position = position + 1
    return position

proc cjs_skip_statement_function(items, index):
    var position = index + 1
    let star = cjs_item_at(items, position)
    if star != nil and star["token"].kind == "punct" and star["token"].raw == "*":
        position = position + 1
    let name = cjs_item_at(items, position)
    if name != nil and name["token"].kind == "word":
        position = position + 1
    let params = cjs_item_at(items, position)
    if params != nil and params["token"].kind == "punct" and params["token"].raw == "(":
        position = cjs_skip_balanced_items(items, position, ")")
    let body = cjs_item_at(items, position)
    if body != nil and body["token"].kind == "punct" and body["token"].raw == "{":
        return cjs_skip_balanced_items(items, position, "}")
    return position

proc cjs_skip_statement_class(items, index):
    var position = index + 1
    let name = cjs_item_at(items, position)
    if name != nil and name["token"].kind == "word":
        position = position + 1
    while position < len(items):
        let token_value = items[position]["token"]
        if token_value.kind == "punct" and token_value.raw == "{":
            return cjs_skip_balanced_items(items, position, "}")
        if token_value.kind == "punct" and token_value.raw == ";":
            return position
        if items[position]["hard_break"] and position > index + 1:
            return position
        position = position + 1
    return position
