# Lily to Sage Transpiler Documentation

## What is Lily?

Lily is a compiled and interpreted systems programming language that aims to be simple, predictable, and highly controllable. Inspired by C++, Python, and Rust, Lily embraces gradual typing, allowing developers to smoothly transition between dynamic prototyping (using `var`) and highly optimized static typing (using exact primitives like `int` and `double`).

Some of Lily's standout features include:
- A transparent value model: dynamic values are tagged unions, while statically typed values are stored natively.
- Predictable and precise primitives: `int` is always a 64-bit integer, eliminating the "float in disguise" issues.
- Explicit but clean pointer syntax (`ptr T` and `addr` without C's confusing sigils).
- Versatile variable semantics with `var` (dynamic/inferred), `let` (immutable and owned), `const` (compile-time), and `final` (write-once).

## How Lily Compares and Differs from Sage

Lily and Sage share a deeply similar philosophy. Both languages support indentation-based syntax and focus on providing C-like performance with Python-like readability. They can both be run through an interpreter or compiled ahead-of-time (AOT) to native binaries.

However, they diverge in several key syntactic and semantic design choices:

1. **Variables & Mutability:**
   - **Sage:** Uses `let` for immutable bindings. Mutability is often restricted or handled via specific structures.
   - **Lily:** Uses a broader suite. `var` for mutable/inferred variables, `let` for strict immutability/ownership, `final` for write-once mutability, and `const` for compile-time constants.

2. **Function Declarations:**
   - **Sage:** Uses the `proc` keyword for procedures/functions (e.g., `proc main():`).
   - **Lily:** Uses the `func` keyword (e.g., `void func main():`).

3. **Pointers & Memory:**
   - **Sage:** Handles low-level memory via `unsafe` blocks and built-in FFI/memory functions (`mem_alloc`, `mem_read`, etc.).
   - **Lily:** Has first-class named pointer types (`ptr int`) and an explicit `addr` keyword for referencing memory, making manual memory management cleaner while keeping pointer ambiguity to a minimum.

4. **Types and Error Handling:**
   - **Sage:** Relies heavily on `try / catch / raise` for exception handling.
   - **Lily:** Uses `try / catch`, but also includes optional types (`T?`) for nil-safety and fallible types (`T!`) to enforce error checking locally.

## How the Transpiler Works

The transpiler project resides in `core/lib/transpiler/lily/` and offers bidirectional compilation between Lily and Sage.

### Sage to Lily (`SageToLilyTranspiler`)
Since the transpiler is written in Sage itself, the `SageToLilyTranspiler` takes advantage of the self-hosted Sage compiler toolchain.
1. The Sage code is parsed using the standard `parser.sage` module, which yields a Sage Abstract Syntax Tree (AST).
2. The `SageToLilyTranspiler` implements a visitor pattern over the Sage AST.
3. As it traverses the tree, it emits corresponding Lily syntax—for instance, replacing `proc` with `func`, mapping `let` assignments accurately, and converting expression constructs.

### Lily to Sage (`LilyToSageTranspiler`)
Translating Lily back into Sage requires accommodating Lily's unique syntax (`var`, `ptr`, `addr`, etc.). 
1. The `LilyToSageTranspiler` relies on a custom front-end parser that understands Lily's lexical and grammar rules.
2. It parses the Lily source text and constructs an equivalent Sage AST.
3. Once the AST is formed, the standard Sage formatters (or an AST-to-text emitter) are used to output valid Sage source code.

By bridging the ASTs of both languages, the transpiler acts as a seamless interoperability layer, allowing developers to write in Lily and leverage the expansive Sage backend ecosystem (LLVM, C, ASM, VM), or vice versa.
