# cjs2esm - CommonJS to ECMAScript Modules Transpiler

## Overview

`cjs2esm` is a CommonJS → ECMAScript Modules transpiler written in **SageLang**. It converts CommonJS codebases into clean, runnable ESM projects while strictly preserving runtime execution order, export/import semantics, object identity, and Node.js-specific conveniences (`__dirname`, `__filename`, `require.resolve()`, `require.main`).

## Project Structure

```
cjs2esm/
├── Makefile / build.sage          # SageLang build and LLVM compilation script
├── README.md                      # This file
├── plan.md                        # This specification document
│
├── src/
│   ├── main.sage                 # CLI Entry point, command routing, exit codes
│   │
│   ├── lexer/
│   │   ├── token.sage            # Token definitions, spans, TokenType enums
│   │   ├── scanner.sage          # Lexical scanner engine with streaming buffer
│   │   └── asi.sage              # Automatic Semicolon Insertion logic
│   │
│   ├── ast/
│   │   ├── nodes.sage            # Base AST Node, Expression, Statement classes
│   │   ├── declarations.sage     # Import, Export, Variable, Function AST nodes
│   │   └── visitor.sage          # AST Visitor and Node Mutator interfaces
│   │
│   ├── parser/
│   │   ├── parser.sage           # Recursive descent parsing coordinator
│   │   ├── expression.sage       # Pratt precedence expression parser
│   │   └── statements.sage       # Statement, block, and declaration parser
│   │
│   ├── analyzer/
│   │   ├── scope.sage            # Lexical Scope Tree & Identifier bindings
│   │   ├── classifier.sage       # Module classifier (PURE_CJS, DYNAMIC, etc.)
│   │   └── cjs_usage.sage        # Detects requires, exports, globals, and hoisting
│   │
│   ├── resolver/
│   │   ├── path_resolver.sage    # Relative path, extension, and directory index resolution
│   │   ├── package_json.sage     # Conditional exports & package resolution
│   │   └── node_builtins.sage    # Built-in modules list (node:fs, path, etc.)
│   │
│   ├── transform/
│   │   ├── context.sage          # Transform pass state and active configuration
│   │   ├── pass_imports.sage     # Static/destructured require to import
│   │   ├── pass_exports.sage     # module.exports / exports.* to export declarations
│   │   ├── pass_globals.sage     # __dirname, __filename, require.resolve, require.main
│   │   ├── pass_dynamic.sage     # createRequire injection or async dynamic import shims
│   │   └── pass_json.sage        # JSON import attributes and destructuring synthesis
│   │
│   ├── printer/
│   │   ├── codegen.sage          # Formatted JavaScript source code emitter
│   │   ├── sourcemap.sage        # Base64 VLQ source map generator (.map)
│   │   └── comments.sage         # Trivia attachment and comment preservation
│   │
│   └── project/
│       ├── workspace.sage        # Multi-file graph orchestrator and file I/O
│       ├── manifest.sage         # package.json updates ("type": "module")
│       └── reporter.sage         # JSON/Markdown migration report generator
│
└── tests/
    ├── runner.sage               # Native SageLang integration test runner
    ├── fixtures/
    │   ├── basic/                # Primitives, functions, control flow
    │   ├── exports/              # Object exports, aliasing, reassignments
    │   ├── json/                 # JSON attribute imports and destructuring
    │   └── discordjs/            # Headless Discord.js mock test suites
    │       ├── bot-bootstrap/
    │       ├── command-handler/
    │       ├── event-handler/
    │       └── slash-builders/
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

* `--out=<dir>`: Output directory for transpiled files (defaults to in-place or `./dist`).
* `--target=<node18|node20|node22|node24>`: Target Node.js baseline (default: `node20`).
* `--mode=<strict|compat|discord>`:
  - `strict`: Avoid compatibility shims; fail on unresolved dynamic requires.
  - `compat`: Automatically inject `createRequire` and fallback shims where needed.
  - `discord`: Optimized for Discord.js bot architectures; handles dynamic command loaders.
* `--rewrite-dynamic-imports`: Converts filesystem dynamic `require()` calls into `await import()`.
* `--source-maps`: Generates `.map` files alongside converted `.js` files.
* `--update-package-json`: Updates or injects `"type": "module"` in `package.json`.
* `--dry-run`: Runs analysis, prints diagnostics, and generates report without writing to disk.

## Diagnostic Codes

Every transformed construct is evaluated against confidence levels:

* `[SAFE]`: Mechanically exact conversion (e.g., static named require).
* `[LIKELY_SAFE]`: Extension or directory resolution backed by filesystem lookup.
* `[COMPAT_SHIM]`: Preserved via `createRequire` or URL shim.
* `[SEMANTIC_CHANGE]`: Asynchronous or order-dependent transformation.
* `[MANUAL_REVIEW]`: Dynamic runtime mutation of exports that cannot be safely determined.

### Diagnostic Registry

* `CJS101` — **Destructured require converted to named ESM import** (`[SAFE]`).
* `CJS102` — **Dynamic require preserved via `createRequire`** (`[COMPAT_SHIM]`).
* `CJS103` — **`__dirname` / `__filename` converted to target specifier** (`[SAFE]`).
* `CJS104` — **JSON require rewritten with import attributes & synthesized bindings** (`[SAFE]`).
* `CJS201` — **Hoisting conflict detected: executable statement precedes require** (`[SEMANTIC_CHANGE]`).
* `CJS202` — **`require.cache` invalidation detected: module unloading unsupported in native ESM** (`[MANUAL_REVIEW]`).
* `CJS301` — **Dynamic export structure preserved via default export object** (`[COMPAT_SHIM]`).

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

* **Token Redaction**: Any token matching regex patterns for Discord Bot tokens (`[MNO][A-Za-z\d]{23,}\.[\w-]{6}\.[\w-]{27,}`) is stripped from diagnostic outputs and reports.
* **Non-Execution**: The transpiler parses ASTs statically and never evaluates or executes project source code at transform time.
* **Credential Isolation**: `.env` and secret configuration files are excluded from diagnostic output.

## Verification & Differential Testing Strategy

### Headless Discord.js Fixture Suite

To ensure deterministic CI runs without network dependencies or live gateway tokens, testing is conducted offline:

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