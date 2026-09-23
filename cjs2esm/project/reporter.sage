gc_disable()
# -----------------------------------------
# reporter.sage - Migration report builder for cjs2esm
# -----------------------------------------

proc cjs_markdown_report(project_path, results):
    let newline = chr(10)
    let report = "# cjs2esm migration report" + newline + newline + "Project: " + project_path + newline + newline
    var passed = 0
    var failed = 0
    var index = 0
    while index < len(results):
        if results[index]["ok"]:
            passed = passed + 1
        else:
            failed = failed + 1
        index = index + 1
    report = report + str(passed) + " supported, " + str(failed) + " unsupported." + newline + newline
    index = 0
    while index < len(results):
        let entry = results[index]
        if entry["ok"]:
            report = report + "- PASS " + entry["path"] + newline
        else:
            report = report + "- FAIL " + entry["path"] + ": " + entry["message"] + newline
        let diagnostics = entry["diagnostics"]
        var diagnostic_index = 0
        while diagnostic_index < len(diagnostics):
            report = report + "  - [" + diagnostics[diagnostic_index]["code"] + "/" + diagnostics[diagnostic_index]["severity"] + "] " + diagnostics[diagnostic_index]["message"] + newline
            diagnostic_index = diagnostic_index + 1
        index = index + 1
    return report

proc cjs_report_summary(results):
    var passed = 0
    var failed = 0
    var index = 0
    while index < len(results):
        if results[index]["ok"]:
            passed = passed + 1
        else:
            failed = failed + 1
        index = index + 1
    let summary = {}
    summary["passed"] = passed
    summary["failed"] = failed
    return summary
