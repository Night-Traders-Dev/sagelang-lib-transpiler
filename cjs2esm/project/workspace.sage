gc_disable()
# -----------------------------------------
# workspace.sage - Multi-file project traversal for cjs2esm
# -----------------------------------------

import io
from cjs2esm.converter import convert_cjs_file, convert_cjs_text

proc cjs_workspace_path_starts_with(value, prefix):
    if value == nil or prefix == nil or len(value) < len(prefix):
        return false
    return slice(value, 0, len(prefix)) == prefix

proc cjs_workspace_path_ends_with(value, suffix):
    if value == nil or suffix == nil or len(value) < len(suffix):
        return false
    return slice(value, len(value) - len(suffix), len(value)) == suffix

proc cjs_is_input_file(entry):
    if len(entry) < 4:
        return false
    if slice(entry, len(entry) - 4, len(entry)) == ".cjs":
        return true
    if len(entry) < 3:
        return false
    return slice(entry, len(entry) - 3, len(entry)) == ".js"

proc cjs_collect_inputs(directory, inputs):
    let entries = io.listdir(directory)
    if entries == nil:
        return inputs
    var index = 0
    while index < len(entries):
        let entry = entries[index]
        let full_path = path_join(directory, entry)
        if io.isdir(full_path):
            if entry != "node_modules" and entry != ".git" and entry != "dist" and entry != "build":
                cjs_collect_inputs(full_path, inputs)
        elif cjs_is_input_file(entry):
            push(inputs, full_path)
        index = index + 1
    return inputs

proc cjs_list_inputs(directory):
    return cjs_collect_inputs(directory, [])

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

proc cjs_project_output_path(input_path, input_directory, output_directory):
    let relative = input_path
    let prefix = input_directory
    if prefix != "." and cjs_workspace_path_starts_with(input_path, prefix + "/"):
        relative = slice(input_path, len(prefix) + 1, len(input_path))
    elif prefix == "." and cjs_workspace_path_starts_with(input_path, "./"):
        relative = slice(input_path, 2, len(input_path))
    let base = path_basename(relative)
    var output_name = base
    if cjs_workspace_path_ends_with(base, ".cjs"):
        output_name = slice(base, 0, len(base) - 4) + ".mjs"
    elif cjs_workspace_path_ends_with(base, ".js"):
        output_name = slice(base, 0, len(base) - 3) + ".mjs"
    else:
        output_name = base + ".mjs"
    let parent = path_dirname(relative)
    if parent == "." or parent == "":
        return path_join(output_directory, output_name)
    return path_join(path_join(output_directory, parent), output_name)

proc cjs_convert_project(input_directory, output_directory, target, mode, want_map, rewrite_dynamic):
    let results = []
    let inputs = cjs_list_inputs(input_directory)
    var index = 0
    while index < len(inputs):
        let output_path = cjs_project_output_path(inputs[index], input_directory, output_directory)
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
