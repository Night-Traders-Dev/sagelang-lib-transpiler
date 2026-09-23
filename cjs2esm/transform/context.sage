gc_disable()
# -----------------------------------------
# context.sage - Shared transform configuration and results
# -----------------------------------------

proc cjs_supported_targets():
    return ["node18", "node20", "node22", "node24"]

proc cjs_supported_modes():
    return ["compat", "discord"]

proc cjs_empty_diagnostics():
    return []

proc cjs_add_context_diagnostic(diagnostics, code, message, severity, line):
    let diagnostic = {}
    diagnostic["code"] = code
    diagnostic["message"] = message
    diagnostic["severity"] = severity
    diagnostic["line"] = line
    push(diagnostics, diagnostic)
    return true

proc cjs_empty_result():
    let result = {}
    result["ok"] = true
    result["message"] = ""
    result["code"] = ""
    result["diagnostics"] = []
    return result

proc cjs_failed_result(message, diagnostics):
    let result = {}
    result["ok"] = false
    result["message"] = message
    result["code"] = ""
    result["diagnostics"] = diagnostics
    return result

proc cjs_validate_target(target):
    let supported = cjs_supported_targets()
    var index = 0
    while index < len(supported):
        if supported[index] == target:
            return true
        index = index + 1
    return false

proc cjs_validate_mode(mode):
    let supported = cjs_supported_modes()
    var index = 0
    while index < len(supported):
        if supported[index] == mode:
            return true
        index = index + 1
    return false
