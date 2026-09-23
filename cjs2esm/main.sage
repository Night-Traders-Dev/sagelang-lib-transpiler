gc_disable()
# -----------------------------------------
# main.sage - cjs2esm command-line entry point
# -----------------------------------------

import io
import sys
from converter import cjs_ends_with, cjs_starts_with, convert_cjs_file, convert_cjs_text
from parser.parser import parse_program
from project.manifest import cjs_update_package_file

proc cjs_print_usage():
    print "Usage:"
    print "  cjs2esm convert <input.cjs> [--out <file.mjs|dir>] [--target node18|node20|node22|node24] [--mode compat|discord] [--source-maps] [--update-package-json] [--rewrite-dynamic-imports] [--dry-run]"
    print "  cjs2esm inspect <input.cjs>"
    print "  cjs2esm check <path>"
    print "  cjs2esm report <path> [--out <report.md>]"
    return 0

proc cjs_cli_args():
    let argv = sys.args()
    let args = []
    var index = 2
    while index < len(argv):
        push(args, argv[index])
        index = index + 1
    return args

proc cjs_option_value(args, index, name):
    let token_value = args[index]
    let prefix = "--" + name + "="
    if cjs_starts_with(token_value, prefix):
        return slice(token_value, len(prefix), len(token_value))
    if token_value == "--" + name and index + 1 < len(args):
        return args[index + 1]
    return nil

proc cjs_option_takes_value(args, index, name):
    let token_value = args[index]
    if cjs_starts_with(token_value, "--" + name + "="):
        return 1
    if token_value == "--" + name:
        return 2
    return 0

proc cjs_default_output_path(input_path):
    let directory = path_dirname(input_path)
    let base = path_basename(input_path)
    if cjs_ends_with(base, ".cjs"):
        return path_join(directory, slice(base, 0, len(base) - 4) + ".mjs")
    return path_join(directory, base + ".mjs")

proc cjs_output_file_path(input_path, out_option):
    if out_option == nil or out_option == "":
        return cjs_default_output_path(input_path)
    if cjs_ends_with(out_option, ".mjs"):
        return out_option
    let base = path_basename(input_path)
    if cjs_ends_with(base, ".cjs"):
        return path_join(out_option, slice(base, 0, len(base) - 4) + ".mjs")
    return path_join(out_option, base + ".mjs")

proc cjs_print_diagnostics(diagnostics):
    var index = 0
    while index < len(diagnostics):
        let diagnostic = diagnostics[index]
        print "  [" + diagnostic["code"] + "/" + diagnostic["severity"] + "] " + diagnostic["message"]
        index = index + 1
    return 0

proc cjs_execute_convert(args):
    var input_path = ""
    var out_option = nil
    var target = "node20"
    var mode = "compat"
    var dry_run = false
    var want_map = false
    var update_package = false
    var rewrite_dynamic = false
    var index = 0
    while index < len(args):
        let token_value = args[index]
        if token_value == "--dry-run":
            dry_run = true
            index = index + 1
        elif token_value == "--source-maps":
            want_map = true
            index = index + 1
        elif token_value == "--update-package-json":
            update_package = true
            index = index + 1
        elif token_value == "--rewrite-dynamic-imports":
            rewrite_dynamic = true
            index = index + 1
        elif token_value == "--help" or token_value == "-h":
            cjs_print_usage()
            return 0
        elif cjs_option_takes_value(args, index, "out") > 0:
            out_option = cjs_option_value(args, index, "out")
            index = index + cjs_option_takes_value(args, index, "out")
        elif cjs_option_takes_value(args, index, "target") > 0:
            target = cjs_option_value(args, index, "target")
            index = index + cjs_option_takes_value(args, index, "target")
        elif cjs_option_takes_value(args, index, "mode") > 0:
            mode = cjs_option_value(args, index, "mode")
            index = index + cjs_option_takes_value(args, index, "mode")
        elif cjs_starts_with(token_value, "--"):
            print "Unknown option: " + token_value
            return 2
        elif input_path == "":
            input_path = token_value
            index = index + 1
        else:
            print "Unexpected argument: " + token_value
            return 2
    if input_path == "":
        print "Missing input file."
        cjs_print_usage()
        return 2
    if cjs_ends_with(input_path, ".mjs"):
        print "Input is already an ES module."
        return 1
    if dry_run:
        let source = io.readfile(input_path)
        if source == nil:
            print "Input file could not be read."
            return 1
        let converted = convert_cjs_text(source, target, mode)
        if not converted["ok"]:
            print converted["message"]
            cjs_print_diagnostics(converted["diagnostics"])
            return 1
        print "Dry run succeeded."
        cjs_print_diagnostics(converted["diagnostics"])
        return 0
    let output_path = cjs_output_file_path(input_path, out_option)
    let converted = convert_cjs_file(input_path, output_path, target, mode, want_map, rewrite_dynamic)
    if not converted["ok"]:
        print converted["message"]
        cjs_print_diagnostics(converted["diagnostics"])
        return 1
    if update_package:
        let package_path = path_join(path_dirname(input_path), "package.json")
        if io.exists(package_path):
            let updated = cjs_update_package_file(package_path)
            if not updated["ok"]:
                print updated["message"]
                return 1
            if updated["changed"]:
                print "Updated " + package_path
    print "Wrote " + output_path
    if want_map:
        print "Wrote " + output_path + ".map"
    cjs_print_diagnostics(converted["diagnostics"])
    return 0

proc cjs_inspect_path(path):
    let source = io.readfile(path)
    if source == nil:
        print "Input file could not be read."
        return 1
    let converted = convert_cjs_text(source, "node20", "compat")
    print "Input: " + path
    print "Supported: " + str(converted["ok"])
    if not converted["ok"]:
        print converted["message"]
    cjs_print_diagnostics(converted["diagnostics"])
    let parsed = parse_program(source)
    if parsed["ok"]:
        print "Statements: " + str(len(parsed["statements"]))
        var statement_index = 0
        while statement_index < len(parsed["statements"]):
            let statement = parsed["statements"][statement_index]
            print "  line " + str(statement["line"]) + ": " + statement["kind"]
            statement_index = statement_index + 1
    else:
        print "Parse failed."
    if converted["ok"]:
        return 0
    return 1

proc cjs_check_path(path):
    if io.isdir(path):
        let entries = io.listdir(path)
        if entries == nil:
            print "Directory could not be read."
            return 1
        var checked = 0
        var failed = 0
        var index = 0
        while index < len(entries):
            let entry = entries[index]
            if cjs_ends_with(entry, ".cjs") or cjs_ends_with(entry, ".js"):
                let full = path_join(path, entry)
                let source = io.readfile(full)
                if source == nil:
                    print "Could not read " + full
                    failed = failed + 1
                else:
                    let converted = convert_cjs_text(source, "node20", "compat")
                    checked = checked + 1
                    if converted["ok"]:
                        print "PASS " + full
                    else:
                        print "FAIL " + full + ": " + converted["message"]
                        failed = failed + 1
            index = index + 1
        print str(checked - failed) + " passed, " + str(failed) + " failed."
        if failed > 0:
            return 1
        return 0
    return cjs_inspect_path(path)

proc cjs_report_path(path, out_option):
    let source = io.readfile(path)
    if source == nil and not io.isdir(path):
        print "Input path could not be read."
        return 1
    let report = "# cjs2esm report" + chr(10) + chr(10) + "Input: " + path + chr(10)
    if out_option == nil or out_option == "":
        print report
        return cjs_check_path(path)
    if not io.writefile(out_option, report):
        print "Report could not be written."
        return 1
    print "Wrote " + out_option
    return cjs_check_path(path)

proc main():
    let args = cjs_cli_args()
    if len(args) == 0:
        cjs_print_usage()
        return 2
    let command = args[0]
    let rest = slice(args, 1, len(args))
    if command == "convert":
        return cjs_execute_convert(rest)
    if command == "inspect":
        if len(rest) != 1:
            cjs_print_usage()
            return 2
        return cjs_inspect_path(rest[0])
    if command == "check":
        if len(rest) != 1:
            cjs_print_usage()
            return 2
        return cjs_check_path(rest[0])
    if command == "report":
        if len(rest) < 1 or len(rest) > 3:
            cjs_print_usage()
            return 2
        var out_option = nil
        var path = rest[0]
        var index = 1
        while index < len(rest):
            if cjs_option_takes_value(rest, index, "out") > 0:
                out_option = cjs_option_value(rest, index, "out")
                index = index + cjs_option_takes_value(rest, index, "out")
            else:
                print "Unexpected argument: " + rest[index]
                return 2
        return cjs_report_path(path, out_option)
    if command == "--help" or command == "-h" or command == "help":
        cjs_print_usage()
        return 0
    print "Unknown command: " + command
    cjs_print_usage()
    return 2

sys.exit(main())
