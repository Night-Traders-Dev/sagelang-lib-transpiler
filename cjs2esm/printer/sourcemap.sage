gc_disable()
# -----------------------------------------
# sourcemap.sage - Base64 VLQ source map generator for cjs2esm
# -----------------------------------------

proc cjs_base64_digit(value):
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    return alphabet[value]

proc cjs_vlq_encode(value):
    var unsigned = 0
    if value < 0:
        unsigned = (0 - value) * 2 + 1
    else:
        unsigned = value * 2
    let output = ""
    while true:
        let shifted = int(unsigned / 32)
        let digit = unsigned - shifted * 32
        unsigned = shifted
        if unsigned > 0:
            output = output + cjs_base64_digit(digit + 32)
        else:
            output = output + cjs_base64_digit(digit)
            break
    return output

proc cjs_count_lines(text):
    var count = 1
    var index = 0
    while index < len(text):
        if text[index] == chr(10):
            count = count + 1
        index = index + 1
    return count

proc cjs_build_source_map(output_path, source_path, prologue_line_count, body_line_count, output_line_count):
    let mappings = ""
    var line = 0
    var previous_source = 0
    var previous_line = 0
    var previous_column = 0
    while line < output_line_count:
        if line > 0:
            mappings = mappings + ";"
        if line >= prologue_line_count and line < prologue_line_count + body_line_count:
            let original = line - prologue_line_count
            mappings = mappings + cjs_vlq_encode(0) + cjs_vlq_encode(0 - previous_source) + cjs_vlq_encode(original - previous_line) + cjs_vlq_encode(0 - previous_column)
            previous_source = 0
            previous_line = original
            previous_column = 0
        line = line + 1
    let map_text = "{\"version\":3,\"file\":" + chr(34) + path_basename(output_path) + chr(34) + ",\"sources\":[" + chr(34) + source_path + chr(34) + "],\"names\":[],\"mappings\":" + chr(34) + mappings + chr(34) + "}"
    let result = {}
    result["text"] = map_text
    result["mappings"] = mappings
    return result
