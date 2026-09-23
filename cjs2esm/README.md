# cjs2esm - CommonJS to ECMAScript Modules Transpiler

## Overview

`cjs2esm` is a CommonJS → ECMAScript Modules transpiler written in **SageLang**. It converts CommonJS codebases into clean, runnable ESM projects while strictly preserving runtime execution order, export/import semantics, object identity, and Node.js-specific conveniences (`__dirname`, `__filename`, `require.resolve()`, `require.main`).

## Current Implementation Status

The checked-in converter is compatibility-first:

- JavaScript sources are scanned with byte-accurate token spans.
- A Pratt expression parser and top-level statement splitter produce statement records consumed by `inspect`.
- Supported CommonJS bodies are preserved byte-for-byte.
- Compatibility shims are injected only when the corresponding global is used.
- `__dirname`, `__filename`, and complete `require.main === module` checks are rewritten.
- Dynamic `require()` and `require.cache` manipulation remain on `createRequire` by default.
- With `--rewrite-dynamic-imports`, dynamic requires in `await`-valid positions (module top level or `async` function bodies) are rewritten to `(await import(...)).default ?? (await import(...))`. Requires inside synchronous functions and files using `require.cache` eviction are never rewritten.
- Leading safe static requires are rewritten to ESM imports, including JSON import attributes with destructuring synthesis.
- `--source-maps` emits Base64 VLQ `.map` files with line-level mappings; `--update-package-json` injects `"type": "module"`.
- Diagnostic messages redact Discord-style bot token patterns.
- Existing ESM syntax, shadowed runtime globals, top-level `return`/`this`/`arguments`, and unbalanced input are rejected.
- Full ESTree AST construction with scope resolution, package updates beyond `"type": "module"`, and the full Discord.js verification harness remain planned work.

Run the current tests with:

```bash
SAGE_PATH="$PWD/core/lib/transpiler:$PWD/core/lib" ./core/sage core/lib/transpiler/cjs2esm/tests/runner.sage
```

## Project Structure

```
cjs2esm/
├── README.md
├── plan.md
├── main.sage
├── converter.sage
├── lexer/
│   ├── js_token.sage
│   ├── js_scanner.sage
│   └── javascript_lexer.sage
├── analyzer/
│   └── cjs_usage.sage
├── ast/
│   └── astnodes.sage
├── parser/
│   ├── parser.sage
│   ├── expression.sage
│   └── statements.sage
├── transform/
│   ├── context.sage
│   ├── pass_imports.sage
│   ├── pass_exports.sage
│   ├── pass_globals.sage
│   ├── pass_dynamic.sage
│   └── pass_json.sage
├── printer/
│   └── codegen.sage
├── resolver/
│   └── path_resolver.sage
├── project/
│   └── manifest.sage
└── tests/
    ├── runner.sage
    └── fixtures/
        ├── basic/
        ├── exports/
        ├── json/
        ├── runtime/
        └── discordjs/
            ├── bot-bootstrap/
            ├── command-handler/
            └── slash-builders/
```

## CLI Specification

The compiled SageLang binary provides the following command-line interface:

```bash
cjs2esm convert <input-path> [options]
cjs2esm inspect <file-path>
cjs2esm check <project-path>
cjs2esm report <project-path>
```

### Options & Flags

* `--out=<file.mjs|dir>`: Output file or directory. Without `--out`, the converter writes a same-directory `.mjs` file.
* `--target=<node18|node20|node22|node24>`: Target Node.js baseline (default: `node20`). All current targets use the conservative `fileURLToPath` compatibility shims.
* `--mode=<compat|discord>`: Compatibility conversion. Both modes currently preserve inline execution order with `createRequire`.
* `--dry-run`: Runs analysis, prints diagnostics, and generates report without writing to disk.
* `--rewrite-dynamic-imports`: Rewrites dynamic `require()` calls in `await`-valid positions to `await import()` with default interop.
* `--mode strict` is not implemented yet and returns an explicit error.

## Diagnostic Codes

Every transformed construct is evaluated against confidence levels:

* `[SAFE]`: Mechanically exact conversion (e.g., static named require).
* `[LIKELY_SAFE]`: Extension or directory resolution backed by filesystem lookup.
* `[COMPAT_SHIM]`: Preserved via `createRequire` or URL shim.
* `[SEMANTIC_CHANGE]`: Asynchronous or order-dependent transformation.
* `[MANUAL_REVIEW]`: Dynamic runtime mutation of exports that cannot be safely determined.

### Diagnostic Registry

The current converter emits:

* `CJS102` — **Require preserved via `createRequire`** (`[COMPAT_SHIM]`).
* `CJS103` — **`__dirname`, `__filename`, or `require.main` converted to a conservative target expression** (`[SAFE]`).
* `CJS202` — **`require.cache` manipulation preserved on `createRequire`** (`[MANUAL_REVIEW]`).
* `CJS203` — **Dynamic require rewritten to `await import`** (`[SEMANTIC_CHANGE]`).
* `CJS301` — **`module.exports` reassignment preserved through the default export object** (`[COMPAT_SHIM]`).
* `CJS400`–`CJS403` — **Unsupported, shadowed, malformed, or unbalanced input.**

Leading safe static requires now emit `CJS101`, and JSON destructuring synthesis emits `CJS104`. Explicit hoisting diagnostics (`CJS201`) remain future work; order-sensitive requires are preserved inline on `createRequire` instead.

## Phased Implementation Roadmap

### Phase 1: Lexer, Parser & AST Foundation (in SageLang)
- [ ] Implement `scanner.sage` with ECMAScript 2026 lexical grammar.
- [ ] Implement Pratt expression parser and recursive descent statement parser in SageLang.
- [ ] Implement AST node hierarchy and visitor/mutator interfaces.
- [ ] Verify parser on Discord.js bot code samples.

### Phase 2: Scope Analysis & CommonJS Classifier
- [ ] Implement lexical scope stack tracking `var`, `let`, `const`, `function`, and parameters.
- [ ] Build identifier binding resolver to identify shadowed `require`/`module`/`exports`.
- [ ] Implement `cjs_usage.sage` to tag module classifications (`PURE_CJS`, `DYNAMIC`, etc.).

### Phase 3: Core Import & Export Transformations
- [ ] Implement static require conversion (`const x = require("x")`, destructured, aliased).
- [ ] Implement export passes (`module.exports = ...`, `exports.key = ...`, object literals).
- [ ] Implement JSON module handling (default import + import attributes + destructuring synthesis).
- [ ] Implement Node runtime global replacements (`__dirname`, `__filename`, `require.resolve`).

### Phase 4: Dynamic Requires, Shims & Hoisting Guards
- [ ] Detect statement-preceded requires (hoisting guard) and inject `createRequire` where order matters.
- [ ] Implement dynamic require fallback using `createRequire(import.meta.url)`.
- [ ] Implement entry-point detection (`require.main === module`) matching `--target`.
- [ ] Implement path resolver appending `.js` extensions and resolving directory indexes.

### Phase 5: Code Generator & Source Map Emitter
- [ ] Implement `codegen.sage` formatting output AST back to JavaScript.
- [ ] Implement Base64 VLQ source map encoder generating spec-compliant `.map` files.
- [ ] Ensure comments and formatting trivia are preserved on untouched code sections.

### Phase 6: Project Orchestrator & CLI
- [ ] Implement CLI argument parser and filesystem workspace traversal in SageLang.
- [ ] Implement `package.json` updater (`"type": "module"`).
- [ ] Implement diagnostic engine with secret redaction.
- [ ] Implement JSON and Markdown migration summary reports (`cjs2esm-report.md`).

### Phase 7: Discord.js Integration & Differential Testing
- [ ] Set up offline test harness running Node against converted fixtures.
- [ ] Verify `SlashCommandBuilder`, `EmbedBuilder`, `Routes`, and event handlers.
- [ ] Run end-to-end migration on a full, multi-command real-world CommonJS Discord bot.

## Security & Secret Redaction

Bot repositories frequently store tokens and keys in local configuration files or scripts. The transpiler guarantees:

* **Token Redaction**: Discord Bot token patterns (`[MNO]...`) are replaced with `[REDACTED]` in diagnostic outputs and reports.
* **Non-Execution**: The transpiler scans input statically and never evaluates or executes project source code at transform time.
* **Credential Isolation**: Planned. `.env` and secret configuration files are not yet specially excluded from diagnostic output.

## Verification & Differential Testing Strategy

### Headless Discord.js Fixture Suite

The current converter has passing Sage scanner/converter tests and manually verified Node `.mjs` output for dependency-free runtime fixtures. A deterministic offline CI harness is still planned. Its intended checks are:

1. **Builder Serialization Verification**:
   - Construct `SlashCommandBuilder` and `EmbedBuilder` instances in CJS.
   - Convert the fixtures to ESM using `cjs2esm`.
   - Run both in Node.js and assert that `.toJSON()` serialized outputs match byte-for-byte.

2. **Routes & REST Formatters**:
   - Compare strings generated by `Routes.applicationCommands(clientId)` and permissions bitfield calculations between CJS and generated ESM.

3. **Collection Behavior**:
   - Confirm that instances of `Collection` instantiated within converted event/command loaders preserve custom utility methods (`filter`, `map`, `first`).

4. **Circular Reference Graphs**:
   - Stress-test circular dependency chains (e.g., `Client` references `Command`, `Command` references `Client`) to verify that ESM live bindings resolve without temporal dead zone (`ReferenceError`) failures.

## Confidence Engine

Every transformed construct is evaluated against confidence levels:

* `[SAFE]`: Mechanically exact conversion (e.g., static named require).
* `[LIKELY_SAFE]`: Extension or directory resolution backed by filesystem lookup.
* `[COMPAT_SHIM]`: Preserved via `createRequire` or URL shim.
* `[SEMANTIC_CHANGE]`: Asynchronous or order-dependent transformation.
* `[MANUAL_REVIEW]`: Dynamic runtime mutation of exports that cannot be safely determined.