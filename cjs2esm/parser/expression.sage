gc_disable()
# -----------------------------------------
# expression.sage - Pratt expression parser for cjs2esm
# -----------------------------------------

from lexer.js_token import js_is_code_token

proc js_expr_node(kind, start, stop):
    let node = {}
    node["kind"] = kind
    node["start"] = start
    node["stop"] = stop
    return node

proc js_binary_power(raw):
    if raw == "||" or raw == "??":
        return 40
    if raw == "&&":
        return 50
    if raw == "|":
        return 60
    if raw == "^":
        return 70
    if raw == "&":
        return 80
    if raw == "==" or raw == "!=" or raw == "===" or raw == "!==":
        return 90
    if raw == "<" or raw == ">" or raw == "<=" or raw == ">=" or raw == "in" or raw == "instanceof":
        return 100
    if raw == "<<" or raw == ">>" or raw == ">>>":
        return 110
    if raw == "+" or raw == "-":
        return 120
    if raw == "*" or raw == "/" or raw == "%":
        return 130
    if raw == "**":
        return 140
    return 0

proc js_is_assign_operator(raw):
    if raw == "=" or raw == "+=" or raw == "-=" or raw == "*=" or raw == "/=" or raw == "%=":
        return true
    if raw == "**=" or raw == "<<=" or raw == ">>=" or raw == ">>>=" or raw == "&=" or raw == "|=" or raw == "^=" or raw == "&&=" or raw == "||=" or raw == "??=":
        return true
    return false

class JsExprParser:
    proc init(code):
        self.code = code
        self.pos = 0
        self.errors = []
        self.failed = false

    proc peek():
        if self.pos >= len(self.code):
            return nil
        return self.code[self.pos]

    proc advance():
        let token_value = self.peek()
        if token_value != nil:
            self.pos = self.pos + 1
        return token_value

    proc fail(message, token_value):
        self.failed = true
        let failure = {}
        failure["message"] = message
        if token_value == nil:
            failure["line"] = 0
        else:
            failure["line"] = token_value.line
        push(self.errors, failure)
        return nil

    proc at_end():
        return self.pos >= len(self.code)

    proc skip_balanced(open_raw, close_raw):
        var depth = 1
        while self.pos < len(self.code):
            let token_value = self.code[self.pos]
            self.pos = self.pos + 1
            if token_value.kind == "punct":
                if token_value.raw == open_raw:
                    depth = depth + 1
                elif token_value.raw == close_raw:
                    depth = depth - 1
                    if depth == 0:
                        return true
            elif token_value.kind == "template_start":
                depth = depth + 1
            elif token_value.kind == "template_end":
                depth = depth - 1
                if depth == 0 and close_raw == "template_end":
                    return true
                if depth < 0:
                    return false
        return false

    proc parse_expression_list(closing):
        let elements = []
        while not self.at_end():
            let token_value = self.peek()
            if token_value.kind == "punct" and token_value.raw == closing:
                self.advance()
                break
            if token_value.kind == "punct" and token_value.raw == ",":
                self.advance()
            else:
                let element = self.parse_expression(0)
                if element == nil:
                    return nil
                push(elements, element)
        return elements

    proc parse_expression(minimum):
        let left = self.parse_prefix()
        if left == nil:
            return nil
        var result = left
        while not self.at_end() and not self.failed:
            let token_value = self.peek()
            if token_value.kind == "punct" and token_value.raw == "(":
                self.advance()
                let args = self.parse_expression_list(")")
                if args == nil:
                    return nil
                let node = js_expr_node("Call", result["start"], self.pos)
                node["callee"] = result
                node["args"] = args
                result = node
            elif token_value.kind == "punct" and token_value.raw == ".":
                self.advance()
                let name = self.advance()
                if name == nil or (name.kind != "word" and name.kind != "keyword"):
                    return self.fail("Expected property name after '.'.", token_value)
                let node = js_expr_node("Member", result["start"], self.pos)
                node["object"] = result
                node["property"] = name.raw
                node["computed"] = false
                result = node
            elif token_value.kind == "punct" and token_value.raw == "?.":
                self.advance()
                let name = self.peek()
                if name != nil and name.kind == "punct" and name.raw == "[":
                    self.advance()
                    let key = self.parse_expression(0)
                    if key == nil:
                        return nil
                    let close = self.advance()
                    if close == nil or close.kind != "punct" or close.raw != "]":
                        return self.fail("Expected ']' in optional computed access.", token_value)
                    let node = js_expr_node("OptionalMember", result["start"], self.pos)
                    node["object"] = result
                    node["key"] = key
                    result = node
                else:
                    self.advance()
                    if name == nil or (name.kind != "word" and name.kind != "keyword"):
                        return self.fail("Expected property name after '?.'.", token_value)
                    let node = js_expr_node("OptionalMember", result["start"], self.pos)
                    node["object"] = result
                    node["property"] = name.raw
                    result = node
            elif token_value.kind == "punct" and token_value.raw == "[":
                self.advance()
                let key = self.parse_expression(0)
                if key == nil:
                    return nil
                let close = self.advance()
                if close == nil or close.kind != "punct" or close.raw != "]":
                    return self.fail("Expected ']' in computed access.", token_value)
                let node = js_expr_node("Member", result["start"], self.pos)
                node["object"] = result
                node["key"] = key
                node["computed"] = true
                result = node
            elif token_value.kind == "punct" and token_value.raw == "?":
                if 30 < minimum:
                    break
                self.advance()
                let consequent = self.parse_expression(0)
                if consequent == nil:
                    return nil
                let colon = self.advance()
                if colon == nil or colon.kind != "punct" or colon.raw != ":":
                    return self.fail("Expected ':' in conditional expression.", token_value)
                let alternate = self.parse_expression(30)
                if alternate == nil:
                    return nil
                let node = js_expr_node("Conditional", result["start"], self.pos)
                node["test"] = result
                node["consequent"] = consequent
                node["alternate"] = alternate
                result = node
            elif token_value.kind == "punct" and token_value.raw == "=>":
                self.advance()
                let body = self.parse_arrow_body()
                if body == nil:
                    return nil
                let node = js_expr_node("Arrow", result["start"], self.pos)
                node["params"] = result
                node["body"] = body
                result = node
            elif token_value.kind == "punct" and token_value.raw == ",":
                if 10 < minimum:
                    break
                self.advance()
                let right = self.parse_expression(10)
                if right == nil:
                    return nil
                let node = js_expr_node("Sequence", result["start"], self.pos)
                node["left"] = result
                node["right"] = right
                result = node
            elif token_value.kind == "punct" and js_is_assign_operator(token_value.raw):
                if 20 < minimum:
                    break
                self.advance()
                let right = self.parse_expression(20)
                if right == nil:
                    return nil
                let node = js_expr_node("Assign", result["start"], self.pos)
                node["operator"] = token_value.raw
                node["left"] = result
                node["right"] = right
                result = node
            elif (token_value.kind == "punct" or token_value.kind == "keyword") and js_binary_power(token_value.raw) > 0:
                let power = js_binary_power(token_value.raw)
                if power < minimum:
                    break
                self.advance()
                var right_power = power + 1
                if token_value.raw == "**":
                    right_power = power
                let right = self.parse_expression(right_power)
                if right == nil:
                    return nil
                let node = js_expr_node("Binary", result["start"], self.pos)
                node["operator"] = token_value.raw
                node["left"] = result
                node["right"] = right
                result = node
            else:
                break
        return result

    proc parse_prefix():
        let token_value = self.advance()
        if token_value == nil:
            return self.fail("Unexpected end of expression.", nil)
        if token_value.kind == "number" or token_value.kind == "string" or token_value.kind == "regex":
            let node = js_expr_node("Literal", token_value.start, token_value.end)
            node["value"] = token_value.raw
            return node
        if token_value.kind == "template_start":
            return self.parse_template(token_value)
        if token_value.kind == "word":
            if token_value.raw == "true" or token_value.raw == "false":
                let node = js_expr_node("Literal", token_value.start, token_value.end)
                node["value"] = token_value.raw
                return node
            if token_value.raw == "null":
                let node = js_expr_node("Literal", token_value.start, token_value.end)
                node["value"] = "null"
                return node
            if token_value.raw == "this" or token_value.raw == "super":
                let node = js_expr_node("Identifier", token_value.start, token_value.end)
                node["name"] = token_value.raw
                return node
            let node = js_expr_node("Identifier", token_value.start, token_value.end)
            node["name"] = token_value.raw
            return node
        if token_value.kind == "keyword":
            if token_value.raw == "new":
                return self.parse_new(token_value)
            if token_value.raw == "typeof" or token_value.raw == "void" or token_value.raw == "delete":
                let argument = self.parse_expression(150)
                if argument == nil:
                    return nil
                let node = js_expr_node("Unary", token_value.start, self.pos)
                node["operator"] = token_value.raw
                node["argument"] = argument
                return node
            if token_value.raw == "await":
                let argument = self.parse_expression(150)
                if argument == nil:
                    return nil
                let node = js_expr_node("Await", token_value.start, self.pos)
                node["argument"] = argument
                return node
            if token_value.raw == "function":
                return self.parse_function_value(token_value, false)
            if token_value.raw == "class":
                return self.parse_class_value(token_value)
            if token_value.raw == "import":
                return self.parse_import_expression(token_value)
            return self.fail("Unexpected keyword in expression: " + token_value.raw, token_value)
        if token_value.kind == "punct":
            if token_value.raw == "(":
                return self.parse_group_or_arrow(token_value)
            if token_value.raw == "[":
                let elements = self.parse_expression_list("]")
                if elements == nil:
                    return nil
                let node = js_expr_node("Array", token_value.start, self.pos)
                node["elements"] = elements
                return node
            if token_value.raw == "{":
                return self.parse_object(token_value)
            if token_value.raw == "-" or token_value.raw == "+" or token_value.raw == "!" or token_value.raw == "~":
                let argument = self.parse_expression(150)
                if argument == nil:
                    return nil
                let node = js_expr_node("Unary", token_value.start, self.pos)
                node["operator"] = token_value.raw
                node["argument"] = argument
                return node
            if token_value.raw == "...":
                let argument = self.parse_expression(150)
                if argument == nil:
                    return nil
                let node = js_expr_node("Spread", token_value.start, self.pos)
                node["argument"] = argument
                return node
            return self.fail("Unexpected token in expression: " + token_value.raw, token_value)
        return self.fail("Unexpected token in expression.", token_value)

    proc parse_template(start_token):
        var depth = 1
        while self.pos < len(self.code):
            let token_value = self.code[self.pos]
            self.pos = self.pos + 1
            if token_value.kind == "template_start":
                depth = depth + 1
            elif token_value.kind == "template_end":
                depth = depth - 1
                if depth == 0:
                    let node = js_expr_node("Template", start_token.start, token_value.end)
                    return node
        return self.fail("Unterminated template literal.", start_token)

    proc parse_new(start_token):
        let next = self.peek()
        if next != nil and next.kind == "punct" and next.raw == ".":
            self.advance()
            let name = self.advance()
            let node = js_expr_node("Member", start_token.start, self.pos)
            node["object"] = "new"
            if name == nil:
                node["property"] = ""
            else:
                node["property"] = name.raw
            node["computed"] = false
            return node
        let callee = self.parse_expression(160)
        if callee == nil:
            return nil
        let node = js_expr_node("New", start_token.start, self.pos)
        node["callee"] = callee
        let args = []
        node["args"] = args
        let open = self.peek()
        if open != nil and open.kind == "punct" and open.raw == "(":
            self.advance()
            let parsed = self.parse_expression_list(")")
            if parsed == nil:
                return nil
            node["args"] = parsed
            node["stop"] = self.pos
        return node

    proc parse_function_value(start_token, is_async):
        var position = self.pos
        let star = cjs_expr_token_at(self.code, position)
        if star != nil and star.kind == "punct" and star.raw == "*":
            position = position + 1
        let name = cjs_expr_token_at(self.code, position)
        if name != nil and name.kind == "word":
            position = position + 1
        let params = cjs_expr_token_at(self.code, position)
        if params == nil or params.kind != "punct" or params.raw != "(":
            return self.fail("Expected function parameter list.", start_token)
        self.pos = position
        self.advance()
        var depth = 1
        while self.pos < len(self.code) and depth > 0:
            let token_value = self.code[self.pos]
            self.pos = self.pos + 1
            if token_value.kind == "punct":
                if token_value.raw == "(":
                    depth = depth + 1
                elif token_value.raw == ")":
                    depth = depth - 1
        let body = self.peek()
        if body == nil or body.kind != "punct" or body.raw != "{":
            return self.fail("Expected function body.", start_token)
        self.advance()
        var brace_depth = 1
        while self.pos < len(self.code) and brace_depth > 0:
            let token_value = self.code[self.pos]
            self.pos = self.pos + 1
            if token_value.kind == "punct":
                if token_value.raw == "{":
                    brace_depth = brace_depth + 1
                elif token_value.raw == "}":
                    brace_depth = brace_depth - 1
        let node = js_expr_node("Function", start_token.start, self.pos)
        node["async"] = is_async
        return node

    proc parse_class_value(start_token):
        var position = self.pos
        let name = cjs_expr_token_at(self.code, position)
        if name != nil and name.kind == "word":
            position = position + 1
        while position < len(self.code):
            let token_value = self.code[position]
            if token_value.kind == "punct" and token_value.raw == "{":
                break
            position = position + 1
        if position >= len(self.code):
            return self.fail("Expected class body.", start_token)
        self.pos = position
        self.advance()
        var depth = 1
        while self.pos < len(self.code) and depth > 0:
            let token_value = self.code[self.pos]
            self.pos = self.pos + 1
            if token_value.kind == "punct":
                if token_value.raw == "{":
                    depth = depth + 1
                elif token_value.raw == "}":
                    depth = depth - 1
        let node = js_expr_node("Class", start_token.start, self.pos)
        return node

    proc parse_import_expression(start_token):
        let next = self.peek()
        if next != nil and next.kind == "punct" and next.raw == "(":
            self.advance()
            let args = self.parse_expression_list(")")
            if args == nil:
                return nil
            let node = js_expr_node("Import", start_token.start, self.pos)
            node["args"] = args
            return node
        if next != nil and next.kind == "punct" and next.raw == ".":
            self.advance()
            let name = self.advance()
            let node = js_expr_node("Member", start_token.start, self.pos)
            node["object"] = "import"
            if name == nil:
                node["property"] = ""
            else:
                node["property"] = name.raw
            node["computed"] = false
            return node
        return self.fail("Unexpected import expression.", start_token)

    proc parse_group_or_arrow(start_token):
        var depth = 1
        var position = self.pos
        while position < len(self.code):
            let token_value = self.code[position]
            if token_value.kind == "punct":
                if token_value.raw == "(":
                    depth = depth + 1
                elif token_value.raw == ")":
                    depth = depth - 1
                    if depth == 0:
                        break
            position = position + 1
        if depth != 0:
            return self.fail("Unbalanced parentheses.", start_token)
        let after = cjs_expr_token_at(self.code, position + 1)
        if after != nil and after.kind == "punct" and after.raw == "=>":
            let node = js_expr_node("Params", start_token.start, self.code[position].end)
            self.pos = position + 2
            let body = self.parse_arrow_body()
            if body == nil:
                return nil
            let arrow = js_expr_node("Arrow", start_token.start, self.pos)
            arrow["params"] = node
            arrow["body"] = body
            return arrow
        let inner = self.parse_expression(0)
        if inner == nil:
            return nil
        let close = self.advance()
        if close == nil or close.kind != "punct" or close.raw != ")":
            return self.fail("Expected ')' in grouped expression.", start_token)
        return inner

    proc parse_arrow_body():
        let token_value = self.peek()
        if token_value != nil and token_value.kind == "punct" and token_value.raw == "{":
            self.advance()
            var depth = 1
            while self.pos < len(self.code) and depth > 0:
                let current = self.code[self.pos]
                self.pos = self.pos + 1
                if current.kind == "punct":
                    if current.raw == "{":
                        depth = depth + 1
                    elif current.raw == "}":
                        depth = depth - 1
            let node = js_expr_node("Block", token_value.start, self.pos)
            return node
        return self.parse_expression(0)

    proc parse_object(start_token):
        var depth = 1
        while self.pos < len(self.code) and depth > 0:
            let token_value = self.code[self.pos]
            self.pos = self.pos + 1
            if token_value.kind == "punct":
                if token_value.raw == "{":
                    depth = depth + 1
                elif token_value.raw == "}":
                    depth = depth - 1
            elif token_value.kind == "template_start":
                depth = depth + 1
            elif token_value.kind == "template_end":
                depth = depth - 1
                if depth < 0:
                    depth = 0
        let node = js_expr_node("Object", start_token.start, self.pos)
        return node

proc cjs_expr_token_at(code, index):
    if index < 0 or index >= len(code):
        return nil
    return code[index]

proc js_parse_expression_tokens(code):
    let parser = JsExprParser(code)
    let node = parser.parse_expression(0)
    let result = {}
    result["node"] = node
    result["errors"] = parser.errors
    result["consumed"] = parser.pos
    return result
