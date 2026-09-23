gc_disable()
# -----------------------------------------
# js_scanner.sage - JavaScript lexical scanner for cjs2esm
# -----------------------------------------

from js_token import js_make_error, js_make_token

class JsScanner:
    proc init(source):
        self.source = source
        self.length = len(source)
        self.pos = 0
        self.line = 1
        self.column = 1
        self.tokens = []
        self.errors = []
        self.modes = ["code"]
        self.template_braces = []
        self.last_code = nil

    proc current_mode():
        return self.modes[len(self.modes) - 1]

    proc peek_character():
        if self.pos >= self.length:
            return ""
        return self.source[self.pos]

    proc peek_character_at(offset):
        if self.pos + offset >= self.length:
            return ""
        return self.source[self.pos + offset]

    proc read_character():
        if self.pos >= self.length:
            return ""
        let value = self.source[self.pos]
        self.pos = self.pos + 1
        if value == chr(10):
            self.line = self.line + 1
            self.column = 1
        else:
            self.column = self.column + 1
        return value

    proc add_token(kind, start, stop, start_line, start_column):
        let raw = slice(self.source, start, stop)
        let token_value = js_make_token(kind, raw, start, stop, start_line, start_column)
        push(self.tokens, token_value)
        return token_value

    proc add_scan_error(message, line, column):
        push(self.errors, js_make_error(message, line, column))
        return false

    proc remember_code_token(token_value):
        self.last_code = token_value
        return true

    proc scan_all():
        while self.pos < self.length:
            if self.current_mode() == "template":
                if not self.scan_template_piece():
                    return self.scan_result()
            else:
                if not self.scan_code_piece():
                    return self.scan_result()
        self.add_token("eof", self.pos, self.pos, self.line, self.column)
        return self.scan_result()

    proc scan_result():
        let result = {}
        result["tokens"] = self.tokens
        result["errors"] = self.errors
        return result

    proc scan_code_piece():
        let start = self.pos
        let start_line = self.line
        let start_column = self.column
        let first = self.read_character()
        if first == " " or first == chr(9) or first == chr(13) or first == chr(11) or first == chr(12):
            return true
        if first == chr(10):
            self.add_token("newline", start, self.pos, start_line, start_column)
            return true
        if first == chr(47):
            return self.scan_slash(start, start_line, start_column)
        if first == chr(34) or first == chr(39):
            return self.scan_js_string(first, start, start_line, start_column)
        if first == chr(96):
            push(self.modes, "template")
            self.remember_code_token(nil)
            self.add_token("template_start", start, self.pos, start_line, start_column)
            return true
        if is_js_identifier_start(first):
            return self.scan_js_word(first, start, start_line, start_column)
        if is_js_digit(first):
            return self.scan_js_number(first, start, start_line, start_column)
        if first == "." and is_js_digit(self.peek_character()):
            return self.scan_js_number(first, start, start_line, start_column)
        return self.scan_js_punctuation(first, start, start_line, start_column)

    proc scan_slash(start, start_line, start_column):
        let second = self.peek_character()
        if second == chr(47):
            self.read_character()
            while self.pos < self.length:
                if self.peek_character() == chr(10):
                    break
                self.read_character()
            self.add_token("comment", start, self.pos, start_line, start_column)
            return true
        if second == chr(42):
            self.read_character()
            while self.pos < self.length:
                let value = self.read_character()
                if value == chr(42) and self.peek_character() == chr(47):
                    self.read_character()
                    self.add_token("comment", start, self.pos, start_line, start_column)
                    return true
            return self.add_scan_error("Unterminated block comment.", start_line, start_column)
        if second == "=":
            self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if self.regex_can_start():
            return self.scan_js_regex(start, start_line, start_column)
        let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
        self.remember_code_token(token_value)
        return true

    proc regex_can_start():
        if self.last_code == nil:
            return true
        if self.last_code.kind == "punct":
            if self.last_code.raw == ")":
                return false
            if self.last_code.raw == "]":
                return false
            if self.last_code.raw == "}":
                return false
            return true
        if self.last_code.kind == "word":
            return is_js_regex_keyword(self.last_code.raw)
        if self.last_code.kind == "number":
            return false
        if self.last_code.kind == "string":
            return false
        if self.last_code.kind == "regex":
            return false
        if self.last_code.kind == "template_end":
            return false
        return true

    proc scan_js_regex(start, start_line, start_column):
        var in_class = false
        var closed = false
        while self.pos < self.length:
            let value = self.read_character()
            if value == chr(92):
                if self.pos >= self.length:
                    return self.add_scan_error("Unterminated regular expression.", start_line, start_column)
                self.read_character()
            elif value == "[":
                in_class = true
            elif value == "]":
                in_class = false
            elif value == chr(10) or value == chr(13):
                return self.add_scan_error("Unterminated regular expression.", start_line, start_column)
            elif value == chr(47) and not in_class:
                closed = true
                break
        if not closed:
            return self.add_scan_error("Unterminated regular expression.", start_line, start_column)
        while self.pos < self.length:
            let flag = self.peek_character()
            if is_js_alpha(flag) or flag == chr(36) or flag == "_" or is_js_digit(flag):
                self.read_character()
            else:
                break
        let token_value = self.add_token("regex", start, self.pos, start_line, start_column)
        self.remember_code_token(token_value)
        return true

    proc scan_js_string(delimiter, start, start_line, start_column):
        while self.pos < self.length:
            let value = self.read_character()
            if value == chr(92):
                if self.pos >= self.length:
                    return self.add_scan_error("Unterminated string literal.", start_line, start_column)
                self.read_character()
            elif value == delimiter:
                let token_value = self.add_token("string", start, self.pos, start_line, start_column)
                self.remember_code_token(token_value)
                return true
            elif value == chr(10) or value == chr(13):
                return self.add_scan_error("Unterminated string literal.", start_line, start_column)
        return self.add_scan_error("Unterminated string literal.", start_line, start_column)

    proc scan_js_word(first, start, start_line, start_column):
        while self.pos < self.length:
            if is_js_identifier_part(self.peek_character()):
                self.read_character()
            else:
                break
        let text = slice(self.source, start, self.pos)
        let kind = "word"
        if is_js_keyword(text):
            kind = "keyword"
        let token_value = self.add_token(kind, start, self.pos, start_line, start_column)
        self.remember_code_token(token_value)
        return true

    proc scan_js_number(first, start, start_line, start_column):
        if first == "0":
            let second = self.peek_character()
            if second == "x" or second == "X":
                self.read_character()
                if not self.scan_hex_digits():
                    return self.add_scan_error("Invalid hexadecimal literal.", start_line, start_column)
                self.scan_number_suffix()
                let token_value = self.add_token("number", start, self.pos, start_line, start_column)
                self.remember_code_token(token_value)
                return true
            if second == "b" or second == "B":
                self.read_character()
                if not self.scan_binary_digits():
                    return self.add_scan_error("Invalid binary literal.", start_line, start_column)
                self.scan_number_suffix()
                let token_value = self.add_token("number", start, self.pos, start_line, start_column)
                self.remember_code_token(token_value)
                return true
            if second == "o" or second == "O":
                self.read_character()
                if not self.scan_octal_digits():
                    return self.add_scan_error("Invalid octal literal.", start_line, start_column)
                self.scan_number_suffix()
                let token_value = self.add_token("number", start, self.pos, start_line, start_column)
                self.remember_code_token(token_value)
                return true
        self.scan_decimal_digits()
        if self.peek_character() == "." and is_js_digit(self.peek_character_at(1)):
            self.read_character()
            self.scan_decimal_digits()
        self.scan_js_exponent()
        self.scan_number_suffix()
        let token_value = self.add_token("number", start, self.pos, start_line, start_column)
        self.remember_code_token(token_value)
        return true

    proc scan_decimal_digits():
        while self.pos < self.length:
            let value = self.peek_character()
            if is_js_digit(value):
                self.read_character()
            elif value == "_" and is_js_digit(self.peek_character_at(1)):
                self.read_character()
            else:
                break
        return true

    proc scan_hex_digits():
        var found = false
        while self.pos < self.length:
            let value = self.peek_character()
            if is_js_hex_digit(value):
                self.read_character()
                found = true
            elif value == "_" and is_js_hex_digit(self.peek_character_at(1)):
                self.read_character()
            else:
                break
        return found

    proc scan_binary_digits():
        var found = false
        while self.pos < self.length:
            let value = self.peek_character()
            if value == "0" or value == "1":
                self.read_character()
                found = true
            elif value == "_" and (self.peek_character_at(1) == "0" or self.peek_character_at(1) == "1"):
                self.read_character()
            else:
                break
        return found

    proc scan_octal_digits():
        var found = false
        while self.pos < self.length:
            let value = self.peek_character()
            if value >= "0" and value <= "7":
                self.read_character()
                found = true
            elif value == "_" and self.peek_character_at(1) >= "0" and self.peek_character_at(1) <= "7":
                self.read_character()
            else:
                break
        return found

    proc scan_js_exponent():
        let marker = self.peek_character()
        if marker != "e" and marker != "E":
            return true
        let first_extra = self.peek_character_at(1)
        if is_js_digit(first_extra):
            self.read_character()
            self.scan_decimal_digits()
            return true
        if (first_extra == "+" or first_extra == "-") and is_js_digit(self.peek_character_at(2)):
            self.read_character()
            self.read_character()
            self.scan_decimal_digits()
            return true
        return true

    proc scan_number_suffix():
        if self.peek_character() == "n" and not is_js_identifier_part(self.peek_character_at(1)):
            self.read_character()
        return true

    proc scan_js_punctuation(first, start, start_line, start_column):
        if first == ".":
            if self.peek_character() == "." and self.peek_character_at(1) == ".":
                self.read_character()
                self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "=":
            if self.peek_character() == "=":
                self.read_character()
                if self.peek_character() == "=":
                    self.read_character()
            elif self.peek_character() == ">":
                self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "!":
            if self.peek_character() == "=":
                self.read_character()
                if self.peek_character() == "=":
                    self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "<":
            if self.peek_character() == "<":
                self.read_character()
                if self.peek_character() == "=":
                    self.read_character()
            elif self.peek_character() == "=":
                self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == ">":
            if self.peek_character() == ">":
                self.read_character()
                if self.peek_character() == ">":
                    self.read_character()
                    if self.peek_character() == "=":
                        self.read_character()
                elif self.peek_character() == "=":
                    self.read_character()
            elif self.peek_character() == "=":
                self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "+":
            if self.peek_character() == "+":
                self.read_character()
            elif self.peek_character() == "=":
                self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "-":
            if self.peek_character() == "-":
                self.read_character()
            elif self.peek_character() == "=":
                self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "*":
            if self.peek_character() == "*":
                self.read_character()
                if self.peek_character() == "=":
                    self.read_character()
            elif self.peek_character() == "=":
                self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "%" and self.peek_character() == "=":
            self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "&":
            if self.peek_character() == "&":
                self.read_character()
                if self.peek_character() == "=":
                    self.read_character()
            elif self.peek_character() == "=":
                self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "|":
            if self.peek_character() == "|":
                self.read_character()
                if self.peek_character() == "=":
                    self.read_character()
            elif self.peek_character() == "=":
                self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "^" and self.peek_character() == "=":
            self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "?":
            if self.peek_character() == "?":
                self.read_character()
                if self.peek_character() == "=":
                    self.read_character()
            elif self.peek_character() == "." and not is_js_digit(self.peek_character_at(1)):
                self.read_character()
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "{":
            if len(self.template_braces) > 0:
                self.template_braces[len(self.template_braces) - 1] = self.template_braces[len(self.template_braces) - 1] + 1
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        if first == "}":
            if len(self.template_braces) > 0:
                let top = self.template_braces[len(self.template_braces) - 1]
                if top > 0:
                    self.template_braces[len(self.template_braces) - 1] = top - 1
                    let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
                    self.remember_code_token(token_value)
                    return true
                pop(self.template_braces)
                pop(self.modes)
                let token_value = self.add_token("template_interpolation_end", start, self.pos, start_line, start_column)
                self.remember_code_token(token_value)
                return true
            let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
            self.remember_code_token(token_value)
            return true
        let token_value = self.add_token("punct", start, self.pos, start_line, start_column)
        self.remember_code_token(token_value)
        return true

    proc scan_template_piece():
        let text_start = self.pos
        let text_line = self.line
        let text_column = self.column
        while self.pos < self.length:
            let value = self.peek_character()
            if value == chr(96):
                if text_start < self.pos:
                    self.add_token("template_text", text_start, self.pos, text_line, text_column)
                let delimiter_start = self.pos
                let delimiter_line = self.line
                let delimiter_column = self.column
                self.read_character()
                self.add_token("template_end", delimiter_start, self.pos, delimiter_line, delimiter_column)
                pop(self.modes)
                self.remember_code_token(nil)
                return true
            if value == chr(36) and self.peek_character_at(1) == "{":
                if text_start < self.pos:
                    self.add_token("template_text", text_start, self.pos, text_line, text_column)
                let piece_start = self.pos
                let piece_line = self.line
                let piece_column = self.column
                self.read_character()
                self.read_character()
                self.add_token("template_interpolation_start", piece_start, self.pos, piece_line, piece_column)
                push(self.template_braces, 0)
                push(self.modes, "code")
                self.remember_code_token(nil)
                return true
            if value == chr(92):
                self.read_character()
                if self.pos >= self.length:
                    return self.add_scan_error("Unterminated template literal.", text_line, text_column)
                self.read_character()
            else:
                self.read_character()
        return self.add_scan_error("Unterminated template literal.", text_line, text_column)

proc is_js_alpha(value):
    if value == nil:
        return false
    if value == "":
        return false
    if value >= "a" and value <= "z":
        return true
    if value >= "A" and value <= "Z":
        return true
    return false

proc is_js_digit(value):
    if value == nil:
        return false
    if value == "":
        return false
    return value >= "0" and value <= "9"

proc is_js_hex_digit(value):
    if value == nil:
        return false
    if value == "":
        return false
    if value >= "0" and value <= "9":
        return true
    if value >= "a" and value <= "f":
        return true
    if value >= "A" and value <= "F":
        return true
    return false

proc is_js_identifier_start(value):
    if is_js_alpha(value):
        return true
    if value == "_" or value == chr(36):
        return true
    if value == nil or value == "":
        return false
    if ord(value) >= 128:
        return true
    return false

proc is_js_identifier_part(value):
    if is_js_identifier_start(value):
        return true
    if is_js_digit(value):
        return true
    return false

proc is_js_keyword(text):
    let keywords = ["await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "finally", "for", "function", "if", "import", "in", "instanceof", "let", "new", "return", "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield"]
    var index = 0
    while index < len(keywords):
        if keywords[index] == text:
            return true
        index = index + 1
    return false

proc is_js_regex_keyword(text):
    let keywords = ["await", "case", "delete", "do", "else", "in", "instanceof", "new", "of", "return", "throw", "typeof", "void", "yield"]
    var index = 0
    while index < len(keywords):
        if keywords[index] == text:
            return true
        index = index + 1
    return false

proc js_scan_source(source):
    let scanner = JsScanner(source)
    return scanner.scan_all()
