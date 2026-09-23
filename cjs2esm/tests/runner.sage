gc_disable()
# -----------------------------------------
# tests/runner.sage - cjs2esm converter tests
# -----------------------------------------

import io
import sys
import std.testing
from cjs2esm.analyzer.cjs_usage import analyze_require_calls, classify_require_call
from cjs2esm.converter import convert_cjs_text
from cjs2esm.lexer.javascript_lexer import js_code_tokens, js_tokenize
from cjs2esm.lexer.js_scanner import js_scan_source
from cjs2esm.printer.codegen import cjs_emit_default_export, cjs_emit_json_import, cjs_emit_named_import
from cjs2esm.project.manifest import cjs_update_package_type_text
from cjs2esm.resolver.path_resolver import resolve_import_path
from cjs2esm.transform.context import cjs_validate_mode, cjs_validate_target
from cjs2esm.transform.pass_dynamic import cjs_dynamic_report
from cjs2esm.transform.pass_globals import cjs_entry_expression, cjs_global_prologue
from cjs2esm.transform.pass_imports import cjs_destructured_import_text, cjs_static_import_is_safe, cjs_static_import_text
from cjs2esm.transform.pass_json import cjs_json_require_names

proc cjs_find_token(tokens, kind, raw):
    var index = 0
    while index < len(tokens):
        if tokens[index].kind == kind and tokens[index].raw == raw:
            return tokens[index]
        index = index + 1
    return nil

proc test_scanner_spans():
    let source = "const value = require(\"mod\");" + chr(10)
    let scan = js_scan_source(source)
    testing.assert_equal(len(scan["errors"]), 0, "scanner errors")
    let token_value = cjs_find_token(scan["tokens"], "word", "require")
    testing.assert_not_nil(token_value, "require token")
    testing.assert_equal(slice(source, token_value.start, token_value.end), "require", "require span")
    let call = cjs_find_token(scan["tokens"], "string", chr(34) + "mod" + chr(34))
    testing.assert_not_nil(call, "module string")

proc test_scanner_template_and_regex():
    let source = "const text = `Hello ${name}!`;" + chr(10) + "const ratio = total / 2;" + chr(10) + "const pattern = /ab+c/g;" + chr(10)
    let scan = js_scan_source(source)
    testing.assert_equal(len(scan["errors"]), 0, "template scanner errors")
    testing.assert_not_nil(cjs_find_token(scan["tokens"], "template_start", chr(96)), "template start")
    testing.assert_not_nil(cjs_find_token(scan["tokens"], "template_end", chr(96)), "template end")
    testing.assert_not_nil(cjs_find_token(scan["tokens"], "regex", "/ab+c/g"), "regex token")
    testing.assert_not_nil(cjs_find_token(scan["tokens"], "word", "ratio"), "division context")

proc test_scanner_ignores_comments_and_strings():
    let source = "const kept = require(\"real\");" + chr(10) + "// require(\"fake\");" + chr(10)
    let scan = js_scan_source(source)
    testing.assert_equal(len(scan["errors"]), 0, "comment scanner errors")
    testing.assert_not_nil(cjs_find_token(scan["tokens"], "string", chr(34) + "real" + chr(34)), "real module")
    testing.assert_nil(cjs_find_token(scan["tokens"], "string", chr(34) + "fake" + chr(34)), "fake module is a comment")

proc test_bootstrap_wrapper():
    let path = "core/lib/transpiler/cjs2esm/tests/fixtures/discordjs/bot-bootstrap/bootstrap.cjs"
    let source = io.readfile(path)
    testing.assert_not_nil(source, "bootstrap fixture")
    let result = convert_cjs_text(source, "node20", "compat")
    testing.assert_true(result["ok"], "bootstrap conversion")
    testing.assert_contains(result["code"], "import { createRequire } from \"node:module\";", "require shim")
    testing.assert_contains(result["code"], "const { Client, GatewayIntentBits, Events } = require(\"discord.js\");", "bootstrap body")
    testing.assert_contains(result["code"], "client.login(process.env.DISCORD_TOKEN);", "bootstrap body end")

proc test_exports_alias_wrapper():
    let path = "core/lib/transpiler/cjs2esm/tests/fixtures/exports/exports_patterns.cjs"
    let source = io.readfile(path)
    testing.assert_not_nil(source, "exports fixture")
    let result = convert_cjs_text(source, "node20", "compat")
    testing.assert_true(result["ok"], "exports conversion")
    testing.assert_contains(result["code"], "export default module.exports;", "default export")
    testing.assert_contains(result["code"], "module.exports = function main()", "reassignment order")

proc test_json_require_wrapper():
    let source = "const config = require(\"./config.json\");" + chr(10) + "module.exports = config;" + chr(10)
    let result = convert_cjs_text(source, "node20", "compat")
    testing.assert_true(result["ok"], "json conversion")
    testing.assert_contains(result["code"], "require(\"./config.json\")", "json require preserved")
    testing.assert_contains(result["code"], "export default module.exports;", "json default export")

proc test_runtime_global_replacement():
    let source = "const here = __dirname;" + chr(10) + "const there = thing.__dirname;" + chr(10)
    let result = convert_cjs_text(source, "node20", "compat")
    testing.assert_true(result["ok"], "global conversion")
    testing.assert_contains(result["code"], "const here = dirname(fileURLToPath(import.meta.url));", "dirname replacement")
    testing.assert_contains(result["code"], "const there = thing.__dirname;", "property preserved")

proc test_require_main_replacement():
    let source = "if (require.main === module) {" + chr(10) + "  main();" + chr(10) + "}" + chr(10)
    let result = convert_cjs_text(source, "node20", "compat")
    testing.assert_true(result["ok"], "entry conversion")
    testing.assert_contains(result["code"], "if (process.argv[1] === fileURLToPath(import.meta.url)) {", "entry replacement")
    testing.assert_contains(result["code"], "import process from \"node:process\";", "process import")

proc test_existing_esm_rejected():
    let result = convert_cjs_text("import value from \"./value.js\";" + chr(10), "node20", "compat")
    testing.assert_false(result["ok"], "existing ESM rejected")

proc test_shadowed_require_rejected():
    let result = convert_cjs_text("const require = 1;" + chr(10) + "print require;" + chr(10), "node20", "compat")
    testing.assert_false(result["ok"], "shadowed require rejected")

proc test_dynamic_cache_preserved():
    let source = "delete require.cache[require.resolve(id)];" + chr(10) + "const loaded = require(id);" + chr(10)
    let result = convert_cjs_text(source, "node20", "compat")
    testing.assert_true(result["ok"], "dynamic cache conversion")
    testing.assert_contains(result["code"], "delete require.cache[require.resolve(id)];", "cache preserved")
    testing.assert_contains(result["code"], "const require = createRequire(import.meta.url);", "dynamic shim")

proc test_compatibility_lexer_entry():
    let scan = js_tokenize("const value = 1;" + chr(10))
    let code = js_code_tokens(scan)
    testing.assert_equal(len(code), 5, "compatibility token count")
    testing.assert_equal(code[0].raw, "const", "compatibility keyword")
    testing.assert_equal(code[1].raw, "value", "compatibility identifier")

proc test_require_classifier():
    let analyzed = analyze_require_calls("const kept = require(\"real\");" + chr(10) + "const loaded = require(name);" + chr(10))
    testing.assert_equal(len(analyzed["errors"]), 0, "classifier scan")
    testing.assert_equal(len(analyzed["calls"]), 2, "require calls")
    testing.assert_equal(classify_require_call(analyzed["calls"][0]), "PURE_CJS", "static classification")
    testing.assert_equal(classify_require_call(analyzed["calls"][1]), "DYNAMIC", "dynamic classification")

proc test_codegen_snippets():
    testing.assert_equal(cjs_emit_named_import(["Client", "Events"], "discord.js"), "import { Client, Events } from \"discord.js\";", "named import")
    testing.assert_equal(cjs_emit_json_import("config", "./config.json"), "import config from \"./config.json\" with { type: \"json\" };", "json import")
    testing.assert_equal(cjs_emit_default_export("module.exports"), "export default module.exports;", "default export")

proc test_package_type_update():
    let updated = cjs_update_package_type_text("{" + chr(10) + "  " + chr(34) + "name" + chr(34) + ": " + chr(34) + "bot" + chr(34) + chr(10) + "}")
    testing.assert_true(updated["ok"], "package update")
    testing.assert_true(updated["changed"], "package changed")
    testing.assert_contains(updated["text"], chr(34) + "type" + chr(34) + ": " + chr(34) + "module" + chr(34), "module type")

proc test_relative_path_resolution():
    let base = "core/lib/transpiler/cjs2esm/tests/fixtures/json"
    testing.assert_equal(resolve_import_path("./config.json", base), "./config.json", "json path")
    testing.assert_equal(resolve_import_path("discord.js", base), "discord.js", "package path")

proc test_transform_context():
    testing.assert_true(cjs_validate_target("node20"), "supported target")
    testing.assert_false(cjs_validate_target("node16"), "unsupported target")
    testing.assert_true(cjs_validate_mode("compat"), "supported mode")
    testing.assert_false(cjs_validate_mode("strict"), "unsupported mode")

proc test_import_plan_helpers():
    testing.assert_equal(cjs_static_import_text("discord.js", "discord"), "import discord from \"discord.js\";", "default import")
    testing.assert_equal(cjs_destructured_import_text(["Client", "Events"], "discord.js"), "import { Client, Events } from \"discord.js\";", "named import")
    testing.assert_true(cjs_static_import_is_safe(false, false, false), "safe import")
    testing.assert_false(cjs_static_import_is_safe(true, false, false), "unsafe hoisted import")

proc test_global_prologue():
    testing.assert_equal(cjs_entry_expression(), "process.argv[1] === fileURLToPath(import.meta.url)", "entry expression")
    testing.assert_contains(cjs_global_prologue(true, true, false, false, false), "const require = createRequire(import.meta.url);", "require prologue")
    testing.assert_contains(cjs_global_prologue(false, false, false, false, true), "const module = { exports: {} };", "module prologue")

proc test_dynamic_report():
    let report = cjs_dynamic_report("delete require.cache[require.resolve(id)];" + chr(10) + "const kept = require(\"real\");" + chr(10) + "const loaded = require(id);" + chr(10))
    testing.assert_equal(len(report["errors"]), 0, "dynamic scan")
    testing.assert_equal(report["static"], 1, "static count")
    testing.assert_equal(report["dynamic"], 1, "dynamic count")
    testing.assert_equal(report["cache"], 1, "cache count")

proc test_json_detection():
    let names = cjs_json_require_names("const config = require(\"./config.json\");" + chr(10))
    testing.assert_equal(len(names), 1, "json count")
    testing.assert_equal(names[0], "./config.json", "json name")

proc main():
    let suite = testing.create_suite("cjs2esm")
    testing.add_test(suite, "scanner spans", test_scanner_spans)
    testing.add_test(suite, "scanner template and regex", test_scanner_template_and_regex)
    testing.add_test(suite, "scanner ignores comments and strings", test_scanner_ignores_comments_and_strings)
    testing.add_test(suite, "bootstrap wrapper", test_bootstrap_wrapper)
    testing.add_test(suite, "exports alias wrapper", test_exports_alias_wrapper)
    testing.add_test(suite, "json require wrapper", test_json_require_wrapper)
    testing.add_test(suite, "runtime global replacement", test_runtime_global_replacement)
    testing.add_test(suite, "require main replacement", test_require_main_replacement)
    testing.add_test(suite, "existing ESM rejected", test_existing_esm_rejected)
    testing.add_test(suite, "shadowed require rejected", test_shadowed_require_rejected)
    testing.add_test(suite, "dynamic cache preserved", test_dynamic_cache_preserved)
    testing.add_test(suite, "compatibility lexer entry", test_compatibility_lexer_entry)
    testing.add_test(suite, "require classifier", test_require_classifier)
    testing.add_test(suite, "codegen snippets", test_codegen_snippets)
    testing.add_test(suite, "package type update", test_package_type_update)
    testing.add_test(suite, "relative path resolution", test_relative_path_resolution)
    testing.add_test(suite, "transform context", test_transform_context)
    testing.add_test(suite, "import plan helpers", test_import_plan_helpers)
    testing.add_test(suite, "global prologue", test_global_prologue)
    testing.add_test(suite, "dynamic report", test_dynamic_report)
    testing.add_test(suite, "json detection", test_json_detection)
    testing.run(suite)
    testing.report(suite)
    if suite["failed"] > 0:
        sys.exit(1)
    return 0

sys.exit(main())
