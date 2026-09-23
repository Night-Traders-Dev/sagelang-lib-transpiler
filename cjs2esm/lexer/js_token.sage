gc_disable()
# -----------------------------------------
# js_token.sage - JavaScript token objects for cjs2esm
# -----------------------------------------

class JsToken:
    proc init():
        self.kind = ""
        self.raw = ""
        self.start = 0
        self.end = 0
        self.line = 1
        self.column = 1

proc js_make_token(kind, raw, start, stop, line, column):
    let token_value = JsToken()
    token_value.kind = kind
    token_value.raw = raw
    token_value.start = start
    token_value.end = stop
    token_value.line = line
    token_value.column = column
    return token_value

proc js_make_error(message, line, column):
    let failure = {}
    failure["ok"] = false
    failure["message"] = message
    failure["line"] = line
    failure["column"] = column
    return failure

proc js_is_code_token(token_value):
    if token_value == nil:
        return false
    if token_value.kind == "comment":
        return false
    if token_value.kind == "newline":
        return false
    if token_value.kind == "eof":
        return false
    if token_value.kind == "error":
        return false
    return true

proc js_token_text(token_value):
    if token_value == nil:
        return ""
    return token_value.raw
