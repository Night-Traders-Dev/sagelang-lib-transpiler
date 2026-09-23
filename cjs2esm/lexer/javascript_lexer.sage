gc_disable()
# -----------------------------------------
# javascript_lexer.sage - Compatibility entry point for cjs2esm scanning
# -----------------------------------------

from js_scanner import js_scan_source
from js_token import js_is_code_token

proc js_tokenize(source):
    return js_scan_source(source)

proc js_code_tokens(scan):
    let code = []
    var index = 0
    while index < len(scan["tokens"]):
        if js_is_code_token(scan["tokens"][index]):
            push(code, scan["tokens"][index])
        index = index + 1
    return code
