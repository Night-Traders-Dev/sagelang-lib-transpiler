gc_disable()
# -----------------------------------------
# manifest.sage - package.json handling for cjs2esm
# -----------------------------------------

import io

proc cjs_find_non_whitespace(text, start):
    var index = start
    while index < len(text):
        let value = text[index]
        if value != " " and value != chr(9) and value != chr(10) and value != chr(13):
            return index
        index = index + 1
    return index

proc cjs_scan_json_string(text, start):
    var index = start + 1
    let result = {}
    result["ok"] = false
    result["stop"] = index
    result["value"] = ""
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

proc cjs_find_final_object_close(text):
    var depth = 0
    var index = 0
    var final_close = -1
    while index < len(text):
        let value = text[index]
        if value == chr(34):
            let scanned = cjs_scan_json_string(text, index)
            if not scanned["ok"]:
                return -1
            index = scanned["stop"]
        elif value == "{":
            depth = depth + 1
            index = index + 1
        elif value == "}":
            depth = depth - 1
            if depth < 0:
                return -1
            if depth == 0:
                final_close = index
            index = index + 1
        else:
            index = index + 1
    if depth != 0:
        return -1
    return final_close

proc cjs_top_level_type_value(text):
    var depth = 0
    var index = 0
    while index < len(text):
        let value = text[index]
        if value == chr(34):
            let key = cjs_scan_json_string(text, index)
            if not key["ok"]:
                return nil
            index = key["stop"]
            index = cjs_find_non_whitespace(text, index)
            if depth == 1 and key["value"] == "type" and index < len(text) and text[index] == ":":
                index = cjs_find_non_whitespace(text, index + 1)
                if index < len(text) and text[index] == chr(34):
                    let parsed = cjs_scan_json_string(text, index)
                    if not parsed["ok"]:
                        return nil
                    let result = {}
                    result["found"] = true
                    result["value"] = parsed["value"]
                    result["start"] = index
                    result["stop"] = parsed["stop"]
                    return result
                let result = {}
                result["found"] = true
                result["value"] = ""
                result["start"] = index
                result["stop"] = index
                return result
        elif value == "{":
            depth = depth + 1
            index = index + 1
        elif value == "}":
            depth = depth - 1
            index = index + 1
        else:
            index = index + 1
    return nil

proc cjs_update_package_type_text(text):
    let start = cjs_find_non_whitespace(text, 0)
    if start >= len(text) or text[start] != "{":
        let failure = {}
        failure["ok"] = false
        failure["message"] = "package.json does not contain a top-level object."
        failure["text"] = text
        return failure
    let existing = cjs_top_level_type_value(text)
    if existing != nil and existing["found"] and existing["value"] == "module":
        let result = {}
        result["ok"] = true
        result["changed"] = false
        result["text"] = text
        return result
    if existing != nil and existing["found"] and existing["value"] != "":
        let result = {}
        result["ok"] = true
        result["changed"] = true
        result["text"] = slice(text, 0, existing["start"]) + chr(34) + "module" + chr(34) + slice(text, existing["stop"], len(text))
        return result
    let final_close = cjs_find_final_object_close(text)
    if final_close < 0:
        let failure = {}
        failure["ok"] = false
        failure["message"] = "package.json is not balanced JSON."
        failure["text"] = text
        return failure
    var before = final_close - 1
    while before >= 0:
        let value = text[before]
        if value != " " and value != chr(9) and value != chr(10) and value != chr(13):
            break
        before = before - 1
    let result = {}
    result["ok"] = true
    result["changed"] = true
    if before >= 0 and text[before] == "{":
        result["text"] = slice(text, 0, final_close) + chr(34) + "type" + chr(34) + ": " + chr(34) + "module" + chr(34) + slice(text, final_close, len(text))
    else:
        result["text"] = slice(text, 0, final_close) + "," + chr(10) + "  " + chr(34) + "type" + chr(34) + ": " + chr(34) + "module" + chr(34) + slice(text, final_close, len(text))
    return result

proc cjs_update_package_file(package_path):
    let text = io.readfile(package_path)
    if text == nil:
        let failure = {}
        failure["ok"] = false
        failure["message"] = "package.json could not be read."
        return failure
    let updated = cjs_update_package_type_text(text)
    if not updated["ok"]:
        return updated
    if updated["changed"]:
        if not io.writefile(package_path, updated["text"]):
            let failure = {}
            failure["ok"] = false
            failure["message"] = "package.json could not be written."
            return failure
    return updated

proc cjs_write_migration_report(report_path, markdown):
    if not io.writefile(report_path, markdown):
        let failure = {}
        failure["ok"] = false
        failure["message"] = "Migration report could not be written."
        return failure
    let result = {}
    result["ok"] = true
    return result
