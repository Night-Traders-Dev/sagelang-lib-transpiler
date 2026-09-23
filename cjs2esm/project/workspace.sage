gc_disable()
# -----------------------------------------
# workspace.sage - Multi-file project traversal for cjs2esm
# -----------------------------------------

import io
from cjs2esm.converter import convert_cjs_file, convert_cjs_text

proc cjs_is_input_file(entry):
    if len(entry) < 4:
        return false
    if slice(entry, len(entry) - 4, len(entry)) == ".cjs":
        return true
    if len(entry) < 3:
        return false
    return slice(entry, len(entry) - 3, len(entry)) == ".js"

proc cjs_list_inputs(directory):
    let entries = io.listdir(directory)
    let inputs = []
    if entries == nil:
        return inputs
    var index = 0
    while index < len(entries):
        if cjs_is_input_file(entries[index]):
            push(inputs, path_join(directory, entries[index]))
        index = index + 1
    return inputs

proc cjs_analyze_project(directory, target, mode):
    let results = []
    let inputs = cjs_list_inputs(directory)
    var index = 0
    while index < len(inputs):
        let source = io.readfile(inputs[index])
        let entry = {}
        entry["path"] = inputs[index]
        if source == nil:
            entry["ok"] = false
            entry["message"] = "Input file could not be read."
            entry["diagnostics"] = []
        else:
            let converted = convert_cjs_text(source, target, mode, inputs[index])
            entry["ok"] = converted["ok"]
            if converted["ok"]:
                entry["message"] = "Supported."
            else:
                entry["message"] = converted["message"]
            entry["diagnostics"] = converted["diagnostics"]
        push(results, entry)
        index = index + 1
    return results

proc cjs_convert_project(input_directory, output_directory, target, mode, want_map, rewrite_dynamic):
    let results = []
    let inputs = cjs_list_inputs(input_directory)
    var index = 0
    while index < len(inputs):
        let base = path_basename(inputs[index])
        let output_path = path_join(output_directory, base + ".mjs")
        let converted = convert_cjs_file(inputs[index], output_path, target, mode, want_map, rewrite_dynamic)
        let entry = {}
        entry["path"] = inputs[index]
        entry["output"] = output_path
        entry["ok"] = converted["ok"]
        if converted["ok"]:
            entry["message"] = "Wrote " + output_path
        else:
            entry["message"] = converted["message"]
        entry["diagnostics"] = converted["diagnostics"]
        push(results, entry)
        index = index + 1
    return results
