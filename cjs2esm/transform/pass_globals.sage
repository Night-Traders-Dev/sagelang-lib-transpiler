gc_disable()
# -----------------------------------------
# pass_globals.sage - Runtime-global replacement expressions
# -----------------------------------------

proc cjs_filename_expression():
    return "fileURLToPath(import.meta.url)"

proc cjs_dirname_expression():
    return "dirname(fileURLToPath(import.meta.url))"

proc cjs_entry_expression():
    return "process.argv[1] === fileURLToPath(import.meta.url)"

proc cjs_global_prologue(needs_require, needs_filename, needs_dirname, needs_process, needs_module):
    let newline = chr(10)
    let prologue = ""
    if needs_require:
        prologue = prologue + "import { createRequire } from " + chr(34) + "node:module" + chr(34) + ";" + newline
    if needs_filename or needs_dirname or needs_process:
        prologue = prologue + "import { fileURLToPath } from " + chr(34) + "node:url" + chr(34) + ";" + newline
    if needs_dirname:
        prologue = prologue + "import { dirname } from " + chr(34) + "node:path" + chr(34) + ";" + newline
    if needs_process:
        prologue = prologue + "import process from " + chr(34) + "node:process" + chr(34) + ";" + newline
    if needs_require:
        prologue = prologue + "const require = createRequire(import.meta.url);" + newline
    if needs_filename:
        prologue = prologue + "const __filename = fileURLToPath(import.meta.url);" + newline
    if needs_dirname:
        prologue = prologue + "const __dirname = dirname(__filename);" + newline
    if needs_module:
        prologue = prologue + "const module = { exports: {} };" + newline
        prologue = prologue + "const exports = module.exports;" + newline
    if prologue != "":
        prologue = prologue + newline
    return prologue
