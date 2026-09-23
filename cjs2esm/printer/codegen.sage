gc_disable()
# -----------------------------------------
# codegen.sage - Small ESM text emitters for cjs2esm
# -----------------------------------------

proc cjs_indent_text(text, level):
    if text == nil or text == "":
        return text
    let spaces = ""
    for i in range(level):
        spaces = spaces + "  "
    let output = ""
    var line_start = true
    var index = 0
    while index < len(text):
        let value = text[index]
        if line_start and value != chr(10):
            output = output + spaces
            line_start = false
        output = output + value
        if value == chr(10):
            line_start = true
        index = index + 1
    return output

proc cjs_join_names(names):
    let output = ""
    var index = 0
    while index < len(names):
        if index > 0:
            output = output + ", "
        output = output + names[index]
        index = index + 1
    return output

proc cjs_emit_named_import(names, source):
    return "import { " + cjs_join_names(names) + " } from " + chr(34) + source + chr(34) + ";"

proc cjs_emit_default_import(local_name, source):
    return "import " + local_name + " from " + chr(34) + source + chr(34) + ";"

proc cjs_emit_json_import(local_name, source):
    return "import " + local_name + " from " + chr(34) + source + chr(34) + " with { type: " + chr(34) + "json" + chr(34) + " };"

proc cjs_emit_default_export(expression):
    return "export default " + expression + ";"

proc cjs_emit_named_export(name):
    return "export const " + name + " = module.exports." + name + ";"
