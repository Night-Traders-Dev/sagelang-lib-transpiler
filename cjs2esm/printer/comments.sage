gc_disable()
# -----------------------------------------
# comments.sage - Trivia helpers for cjs2esm
# -----------------------------------------

proc cjs_leading_comment(scan, token_index):
    var index = token_index - 1
    while index >= 0:
        let token_value = scan["tokens"][index]
        if token_value.kind == "comment":
            return token_value.raw
        if token_value.kind == "newline":
            index = index - 1
        else:
            return ""
    return ""

proc cjs_trailing_comment(scan, token_index):
    var index = token_index + 1
    while index < len(scan["tokens"]):
        let token_value = scan["tokens"][index]
        if token_value.kind == "comment":
            return token_value.raw
        if token_value.kind == "newline" or token_value.kind == "eof":
            return ""
        index = index + 1
    return ""

proc cjs_is_line_comment(raw):
    if raw == nil or len(raw) < 2:
        return false
    return raw[0] == chr(47) and raw[1] == chr(47)
