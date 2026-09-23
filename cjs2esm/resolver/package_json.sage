gc_disable()
# -----------------------------------------
# package_json.sage - package.json field lookup for cjs2esm
# -----------------------------------------

import io

proc cjs_package_top_level_string(text, field):
    var depth = 0
    var index = 0
    while index < len(text):
        let value = text[index]
        if value == chr(34):
            let key = cjs_package_scan_string(text, index)
            if not key["ok"]:
                return nil
            index = key["stop"]
            index = cjs_package_skip_space(text, index)
            if depth == 1 and key["value"] == field and index < len(text) and text[index] == ":":
                index = cjs_package_skip_space(text, index + 1)
                if index < len(text) and text[index] == chr(34):
                    let parsed = cjs_package_scan_string(text, index)
                    if parsed["ok"]:
                        return parsed["value"]
                return ""
        elif value == "{":
            depth = depth + 1
            index = index + 1
        elif value == "}":
            depth = depth - 1
            index = index + 1
        else:
            index = index + 1
    return nil

proc cjs_package_scan_string(text, start):
    let result = {}
    result["ok"] = false
    result["stop"] = start
    result["value"] = ""
    var index = start + 1
    while index < len(text):
        let value = text[index]
        if value == chr(92):
            if index + 1 >= len(text):
                return result
            result["value"] = result["value"] + text[index] + text[index + 1]
            index = index + 2
        elif value == chr(34):
            result["ok"] = true
            result["stop"] = index + 1
            return result
        elif value == chr(10) or value == chr(13):
            return result
        else:
            result["value"] = result["value"] + value
            index = index + 1
    return result

proc cjs_package_skip_space(text, start):
    var index = start
    while index < len(text):
        let value = text[index]
        if value != " " and value != chr(9) and value != chr(10) and value != chr(13):
            break
        index = index + 1
    return index

proc cjs_package_main_entry(package_directory):
    let package_path = path_join(package_directory, "package.json")
    if not io.exists(package_path):
        return "index.js"
    let text = io.readfile(package_path)
    if text == nil:
        return "index.js"
    let main = cjs_package_top_level_string(text, "main")
    if main == nil or main == "":
        return "index.js"
    return main
