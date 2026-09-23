gc_disable()
# -----------------------------------------
# pass_imports.sage - Safe static import planning helpers
# -----------------------------------------

proc cjs_static_import_text(module_name, local_name):
    return "import " + local_name + " from " + chr(34) + module_name + chr(34) + ";"

proc cjs_destructured_import_text(names, source):
    let joined = ""
    var index = 0
    while index < len(names):
        if index > 0:
            joined = joined + ", "
        joined = joined + names[index]
        index = index + 1
    return "import { " + joined + " } from " + chr(34) + source + chr(34) + ";"

proc cjs_json_import_text(local_name, source):
    return "import " + local_name + " from " + chr(34) + source + chr(34) + " with { type: " + chr(34) + "json" + chr(34) + " };"

proc cjs_static_import_is_safe(has_side_effect_before, is_dynamic, has_existing_esm):
    if has_existing_esm:
        return false
    if is_dynamic:
        return false
    if has_side_effect_before:
        return false
    return true
