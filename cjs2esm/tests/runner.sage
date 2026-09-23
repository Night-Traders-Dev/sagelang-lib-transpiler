gc_disable()
# -----------------------------------------
# tests/runner.sage - cjs2esm converter tests
# -----------------------------------------

import io
import sys
import std.testing
from cjs2esm.analyzer.cjs_usage import analyze_require_calls, classify_require_call
from cjs2esm.converter import cjs_redact_secrets, convert_cjs_file, convert_cjs_text
from cjs2esm.lexer.javascript_lexer import js_code_tokens, js_tokenize
from cjs2esm.lexer.js_scanner import js_scan_source
from cjs2esm.printer.codegen import cjs_emit_default_export, cjs_emit_json_import, cjs_emit_named_import
from cjs2esm.parser.parser import parse_expression_text, parse_program
from cjs2esm.project.manifest import cjs_update_package_file, cjs_update_package_type_text
from cjs2esm.resolver.path_resolver import resolve_import_path
from cjs2esm.transform.context import cjs_validate_mode, cjs_validate_target
from cjs2esm.transform.pass_dynamic import cjs_dynamic_report
from cjs2esm.transform.pass_globals import cjs_entry_expression, cjs_global_prologue
from cjs2esm.transform.pass_imports import cjs_destructured_import_text, cjs_static_import_is_safe, cjs_static_import_text
from cjs2esm.transform.pass_json import cjs_json_require_names
from cjs2esm.resolver.node_builtins import cjs_is_node_builtin
from cjs2esm.resolver.package_json import cjs_package_main_entry, cjs_package_top_level_string
from cjs2esm.analyzer.scope import cjs_scope_bind, cjs_scope_enter, cjs_scope_exit, cjs_scope_lookup, cjs_scope_tracker
from cjs2esm.analyzer.classifier import cjs_classification_confidence, cjs_classify_calls
from cjs2esm.ast.declarations import js_export_default, js_export_named, js_function_declaration, js_import_declaration, js_import_pair, js_program_node, js_variable_declaration, js_variable_declarator
from cjs2esm.ast.visitor import js_visit_kinds
from cjs2esm.printer.comments import cjs_is_line_comment
from cjs2esm.project.reporter import cjs_markdown_report, cjs_report_summary
from cjs2esm.project.workspace import cjs_analyze_project, cjs_list_inputs

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
    testing.assert_contains(result["code"], "import { Client, GatewayIntentBits, Events } from \"discord.js\";", "static import")
    testing.assert_contains(result["code"], "client.login(process.env.DISCORD_TOKEN);", "bootstrap body end")

proc test_exports_alias_wrapper():
    let path = "core/lib/transpiler/cjs2esm/tests/fixtures/exports/exports_patterns.cjs"
    let source = io.readfile(path)
    testing.assert_not_nil(source, "exports fixture")
    let result = convert_cjs_text(source, "node20", "compat")
    testing.assert_true(result["ok"], "exports conversion")
    testing.assert_contains(result["code"], "export default module.exports;", "default export")
    testing.assert_contains(result["code"], "module.exports = function main()", "reassignment order")

proc test_object_export_names():
    let basic = io.readfile("core/lib/transpiler/cjs2esm/tests/fixtures/basic/basic_cjs.cjs")
    testing.assert_not_nil(basic, "basic fixture")
    let basic_result = convert_cjs_text(basic, "node20", "compat")
    testing.assert_true(basic_result["ok"], "basic conversion")
    testing.assert_contains(basic_result["code"], "export { handler };", "handler export")
    let slash = io.readfile("core/lib/transpiler/cjs2esm/tests/fixtures/discordjs/slash-builders/slash_cmd.cjs")
    testing.assert_not_nil(slash, "slash fixture")
    let slash_result = convert_cjs_text(slash, "node20", "compat")
    testing.assert_true(slash_result["ok"], "slash conversion")
    testing.assert_contains(slash_result["code"], "export const data = module.exports.data;", "data export")
    testing.assert_contains(slash_result["code"], "export const execute = module.exports.execute;", "execute export")

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

proc test_source_map_output():
    let converted = convert_cjs_file("core/lib/transpiler/cjs2esm/tests/fixtures/runtime/order.cjs", "/tmp/opencode/cjs2esm-map-test.mjs", "node20", "compat", true)
    testing.assert_true(converted["ok"], "mapped conversion")
    let map_text = io.readfile("/tmp/opencode/cjs2esm-map-test.mjs.map")
    testing.assert_not_nil(map_text, "map file")
    testing.assert_contains(map_text, chr(34) + "version" + chr(34) + ":3", "map version")
    testing.assert_contains(map_text, chr(34) + "mappings" + chr(34), "map mappings")
    testing.assert_contains(converted["code"], "//# sourceMappingURL=cjs2esm-map-test.mjs.map", "map comment")

proc test_package_file_update():
    io.writefile("/tmp/opencode/cjs2esm-package.json", "{" + chr(10) + "  " + chr(34) + "name" + chr(34) + ": " + chr(34) + "bot" + chr(34) + chr(10) + "}")
    let updated = cjs_update_package_file("/tmp/opencode/cjs2esm-package.json")
    testing.assert_true(updated["ok"], "package file update")
    testing.assert_true(updated["changed"], "package file changed")
    testing.assert_contains(io.readfile("/tmp/opencode/cjs2esm-package.json"), chr(34) + "type" + chr(34) + ": " + chr(34) + "module" + chr(34), "package module type")

proc test_expression_precedence():
    let parsed = parse_expression_text("1 + 2 * 3")
    testing.assert_true(parsed["ok"], "precedence parse")
    testing.assert_equal(parsed["node"]["kind"], "Binary", "root binary")
    testing.assert_equal(parsed["node"]["operator"], "+", "root operator")
    testing.assert_equal(parsed["node"]["right"]["kind"], "Binary", "right binary")
    testing.assert_equal(parsed["node"]["right"]["operator"], "*", "right operator")

proc test_require_call_expression():
    let parsed = parse_expression_text("require(\"discord.js\")")
    testing.assert_true(parsed["ok"], "require parse")
    testing.assert_equal(parsed["node"]["kind"], "Call", "call node")
    testing.assert_equal(parsed["node"]["callee"]["name"], "require", "callee name")
    testing.assert_equal(len(parsed["node"]["args"]), 1, "one argument")

proc test_member_call_expression():
    let parsed = parse_expression_text("client.once(Events.ClientReady, handler)")
    testing.assert_true(parsed["ok"], "member call parse")
    testing.assert_equal(parsed["node"]["kind"], "Call", "call node")
    testing.assert_equal(parsed["node"]["callee"]["kind"], "Member", "member callee")

proc test_arrow_expression():
    let parsed = parse_expression_text("c => c + 1")
    testing.assert_true(parsed["ok"], "arrow parse")
    testing.assert_equal(parsed["node"]["kind"], "Arrow", "arrow node")

proc test_statement_splitting():
    let source = io.readfile("core/lib/transpiler/cjs2esm/tests/fixtures/discordjs/bot-bootstrap/bootstrap.cjs")
    testing.assert_not_nil(source, "bootstrap fixture")
    let parsed = parse_program(source)
    testing.assert_true(parsed["ok"], "program parse")
    testing.assert_equal(len(parsed["statements"]), 4, "statement count")
    testing.assert_equal(parsed["statements"][0]["kind"], "variable_declaration", "first statement")
    testing.assert_equal(parsed["statements"][3]["kind"], "expression", "last statement")

proc test_node_builtins():
    testing.assert_true(cjs_is_node_builtin("node:fs"), "node prefix builtin")
    testing.assert_true(cjs_is_node_builtin("path"), "bare builtin")
    testing.assert_false(cjs_is_node_builtin("discord.js"), "package not builtin")

proc test_package_main_entry():
    testing.assert_equal(cjs_package_main_entry("core/lib/transpiler/cjs2esm/tests/fixtures/json"), "index.js", "missing package default")
    io.writefile("/tmp/opencode/cjs2esm-pkg.json", "{" + chr(10) + "  " + chr(34) + "main" + chr(34) + ": " + chr(34) + "bot.js" + chr(34) + chr(10) + "}")
    testing.assert_equal(cjs_package_top_level_string(io.readfile("/tmp/opencode/cjs2esm-pkg.json"), "main"), "bot.js", "package main field")

proc test_scope_tracker():
    let tracker = cjs_scope_tracker()
    cjs_scope_bind(tracker, "top")
    cjs_scope_enter(tracker, "function")
    cjs_scope_bind(tracker, "local")
    testing.assert_true(cjs_scope_lookup(tracker, "top"), "outer lookup")
    testing.assert_true(cjs_scope_lookup(tracker, "local"), "inner lookup")
    cjs_scope_exit(tracker)
    testing.assert_true(cjs_scope_lookup(tracker, "top"), "outer after exit")
    testing.assert_false(cjs_scope_lookup(tracker, "local"), "inner after exit")

proc test_classifier():
    let static_call = {}
    static_call["static"] = true
    let dynamic_call = {}
    dynamic_call["static"] = false
    let pure = cjs_classify_calls([static_call], false)
    testing.assert_equal(pure["classification"], "PURE_CJS", "pure classification")
    testing.assert_equal(cjs_classification_confidence("PURE_CJS"), "SAFE", "pure confidence")
    let mixed = cjs_classify_calls([static_call, dynamic_call], false)
    testing.assert_equal(mixed["classification"], "DYNAMIC", "dynamic classification")
    testing.assert_equal(mixed["dynamic"], 1, "dynamic count")

proc test_ast_declarations_visitor():
    let declarator = js_variable_declarator("value", nil)
    let declaration = js_variable_declaration("const", [declarator])
    let program = js_program_node([declaration, js_import_declaration("fs", [js_import_pair("readFile", "readFile")]), js_export_default("value"), js_export_named(["value"]), js_function_declaration("main", false)])
    let kinds = []
    js_visit_kinds(program, kinds)
    testing.assert_equal(len(kinds), 7, "visited kinds")
    testing.assert_equal(kinds[0], "Program", "program kind")
    testing.assert_equal(kinds[1], "VariableDeclaration", "declaration kind")

proc test_comments_helper():
    testing.assert_true(cjs_is_line_comment("// hello"), "line comment")
    testing.assert_false(cjs_is_line_comment("/* hello */"), "block comment")

proc test_workspace_reporter():
    let inputs = cjs_list_inputs("core/lib/transpiler/cjs2esm/tests/fixtures/runtime")
    testing.assert_true(len(inputs) >= 5, "workspace inputs")
    let results = cjs_analyze_project("core/lib/transpiler/cjs2esm/tests/fixtures/runtime", "node20", "compat")
    testing.assert_true(len(results) >= 5, "workspace results")
    let report = cjs_markdown_report("runtime", results)
    testing.assert_contains(report, "# cjs2esm migration report", "report header")
    let summary = cjs_report_summary(results)
    testing.assert_equal(summary["passed"] + summary["failed"], len(results), "summary total")

proc test_secret_redaction():
    let token = "Maaaaaaaaaaaaaaaaaaaaaaa.abcdef.abcdefghijklmnopqrstuvwxyz0"
    testing.assert_equal(cjs_redact_secrets("saw " + token + " here"), "saw [REDACTED] here", "token redacted")
    testing.assert_equal(cjs_redact_secrets("plain message"), "plain message", "plain message kept")

proc test_async_rewrite():
    let source = "async function load(name) {" + chr(10) + "  const helper = require(name);" + chr(10) + "  return helper;" + chr(10) + "}" + chr(10)
    let result = convert_cjs_text(source, "node20", "compat", "", true)
    testing.assert_true(result["ok"], "async rewrite conversion")
    testing.assert_contains(result["code"], "(await import(name)).default ?? (await import(name))", "await import rewrite")

proc test_sync_require_preserved_with_rewrite_flag():
    let source = "function load(name) {" + chr(10) + "  return require(name);" + chr(10) + "}" + chr(10) + "module.exports = { load };" + chr(10)
    let result = convert_cjs_text(source, "node20", "compat", "", true)
    testing.assert_true(result["ok"], "sync rewrite conversion")
    testing.assert_contains(result["code"], "return require(name);", "sync require preserved")
    testing.assert_contains(result["code"], "const require = createRequire(import.meta.url);", "sync shim kept")

proc test_top_level_rewrite():
    let source = "const name = \"./helper3.cjs\";" + chr(10) + "const helper = require(name);" + chr(10) + "console.log(helper(\"ann\"));" + chr(10)
    let result = convert_cjs_text(source, "node20", "compat", "", true)
    testing.assert_true(result["ok"], "top-level rewrite conversion")
    testing.assert_contains(result["code"], "(await import(name)).default ?? (await import(name))", "top-level rewrite")

proc main():
    let suite = testing.create_suite("cjs2esm")
    testing.add_test(suite, "scanner spans", test_scanner_spans)
    testing.add_test(suite, "scanner template and regex", test_scanner_template_and_regex)
    testing.add_test(suite, "scanner ignores comments and strings", test_scanner_ignores_comments_and_strings)
    testing.add_test(suite, "bootstrap wrapper", test_bootstrap_wrapper)
    testing.add_test(suite, "exports alias wrapper", test_exports_alias_wrapper)
    testing.add_test(suite, "object export names", test_object_export_names)
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
    testing.add_test(suite, "source map output", test_source_map_output)
    testing.add_test(suite, "package file update", test_package_file_update)
    testing.add_test(suite, "secret redaction", test_secret_redaction)
    testing.add_test(suite, "node builtins", test_node_builtins)
    testing.add_test(suite, "package main entry", test_package_main_entry)
    testing.add_test(suite, "scope tracker", test_scope_tracker)
    testing.add_test(suite, "classifier", test_classifier)
    testing.add_test(suite, "ast declarations visitor", test_ast_declarations_visitor)
    testing.add_test(suite, "comments helper", test_comments_helper)
    testing.add_test(suite, "workspace reporter", test_workspace_reporter)
    testing.add_test(suite, "expression precedence", test_expression_precedence)
    testing.add_test(suite, "require call expression", test_require_call_expression)
    testing.add_test(suite, "member call expression", test_member_call_expression)
    testing.add_test(suite, "arrow expression", test_arrow_expression)
    testing.add_test(suite, "statement splitting", test_statement_splitting)
    testing.add_test(suite, "async rewrite", test_async_rewrite)
    testing.add_test(suite, "sync require preserved with rewrite flag", test_sync_require_preserved_with_rewrite_flag)
    testing.add_test(suite, "top-level rewrite", test_top_level_rewrite)
    testing.run(suite)
    testing.report(suite)
    if suite["failed"] > 0:
        sys.exit(1)
    return 0

sys.exit(main())
