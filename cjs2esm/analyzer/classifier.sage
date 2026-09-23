gc_disable()
# -----------------------------------------
# classifier.sage - Module classification for cjs2esm
# -----------------------------------------

proc cjs_classify_calls(calls, has_reassignment):
    let result = {}
    result["classification"] = "PURE_CJS"
    result["dynamic"] = 0
    result["static"] = 0
    var index = 0
    while index < len(calls):
        if calls[index]["static"]:
            result["static"] = result["static"] + 1
        else:
            result["dynamic"] = result["dynamic"] + 1
        index = index + 1
    if has_reassignment or result["dynamic"] > 0:
        result["classification"] = "DYNAMIC"
    return result

proc cjs_classification_confidence(classification):
    if classification == "PURE_CJS":
        return "SAFE"
    if classification == "DYNAMIC":
        return "COMPAT_SHIM"
    return "MANUAL_REVIEW"
