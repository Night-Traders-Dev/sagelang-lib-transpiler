# Sage ↔ Lily Transpiler Specification

> **Sage version:** 3.9.4 / Spec 2.0  
> **Lily version:** 0.1.0-draft  
> **Spec version:** 1.0.0  
> **Authors:** Night-Traders-Dev / MilkmanAbi collaboration

Bidirectional transpilation rules between SageLang and Lily. Both directions are covered in
full, with explicit callouts for semantic gaps, lossy translations, and features that have
no counterpart on the target side.

---

## Table of Contents

1. [Design Goals](#1-design-goals)
2. [Operator Conflicts](#2-operator-conflicts)
3. [Feature Compatibility Matrix](#3-feature-compatibility-matrix)
4. [Sage → Lily](#4-sage--lily)
   - 4.1 Variables and Bindings
   - 4.2 Types and Annotations
   - 4.3 Functions (proc → func)
   - 4.4 Classes and Inheritance
   - 4.5 Structs, Enums, Traits
   - 4.6 Control Flow
   - 4.7 Operators
   - 4.8 Pattern Matching
   - 4.9 Exception Handling
   - 4.10 I/O
   - 4.11 Imports
   - 4.12 Memory and FFI
   - 4.13 Concurrency
   - 4.14 Metaprogramming
   - 4.15 Unsupported Sage Features
5. [Lily → Sage](#5-lily--sage)
   - 5.1 Variables and Declarations
   - 5.2 Types and Annotations
   - 5.3 Functions (func → proc)
   - 5.4 Classes and Inheritance
   - 5.5 Interfaces and Enums
   - 5.6 Control Flow
   - 5.7 Operators
   - 5.8 Pattern Matching
   - 5.9 Error Handling
   - 5.10 I/O
   - 5.11 Imports
   - 5.12 Memory, Pointers, FFI
   - 5.13 Annotations
   - 5.14 Unsupported Lily Features
6. [Semantic Gap Reference](#6-semantic-gap-reference)
7. [Implementation Notes](#7-implementation-notes)
8. [Quick Reference Tables](#8-quick-reference-tables)

---

## 1. Design Goals

- **Correctness over elegance.** When a clean mapping exists, use it. When it doesn't,
  emit a working equivalent even if it is verbose.
- **Explicit over implicit.** Where the target language has an optional feature (type
  annotation, `override`, ownership), emit it. Don't strip information.
- **Flag semantic loss.** Emit a `// TRANSPILER: ...` comment whenever a translation is
  lossy — missing semantics, runtime-only enforcement, or a required manual review.
- **No silent breakage.** Features with no target equivalent must either be stubbed with
  a clear comment or cause a transpiler error. Never silently drop code.

---

## 2. Operator Conflicts

Three operators change meaning between languages. The transpiler must resolve these before
processing any other rule.

### 2.1 The `->` Operator

| Language | Meaning | Example |
|----------|---------|---------|
| Sage | Alias for `.` (property/method access) | `dog->speak()` ≡ `dog.speak()` |
| Lily | Outcome-routing / error handler | `parse(s) -> default(0)` |

**Sage → Lily:** Rewrite all `a->b` as `a.b`. The Lily `->` error router has no syntactic
equivalent in Sage; see §4.9.

**Lily → Sage:** `->` as outcome router has no single-expression equivalent in Sage; see §5.9.
`->` as property access does not exist in Lily, so this direction has no conflict.

### 2.2 The `<<` / `>>` Operators

| Language | Meaning |
|----------|---------|
| Sage | Bitwise left-shift / right-shift |
| Lily | Stream insert (`sout <<`) / stream extract (`sin >>`) |

**Sage → Lily:** Sage `a << b` (bitshift) → Lily `a.shl(b)`. Sage `a >> b` → `a.shr(b)`.  
**Lily → Sage:** Lily `sout << expr` → Sage `print expr`. Lily `sin >> var` → Sage `let var = input()`.

### 2.3 The `in` Keyword

| Language | Meaning |
|----------|---------|
| Sage | `for x in arr` iteration AND `array_contains` membership test (`3 in arr`) |
| Lily | `for item in arr` iteration only |

**Sage → Lily:** `val in arr` (membership) → `arr.contains(val)` (call on the Lily array's
method, or manual loop). `for x in arr` → `for x in arr` (direct).

---

## 3. Feature Compatibility Matrix

`✓` = direct translation  `~` = lossy or approximate  `✗` = no target equivalent

| Feature | Sage → Lily | Lily → Sage |
|---------|------------|------------|
| Immutable binding | `✓` `let` → `let` | `✓` `let` → `let` |
| Mutable binding | `~` (Sage has no `var`; use Lily `var`) | `✓` `var` → `let` (Sage only has `let`) |
| `const` | `✗` (Sage has no const; use `let`) | `~` `const` → `let` |
| `final` (write-once) | N/A | `~` `final` → `let` |
| Type annotations | `~` (syntax inversion) | `~` (syntax inversion) |
| Optional type `T?` | `~` → nil check convention | `✓` → direct |
| Fallible type `T!` | `✗` → `try`/`catch` | N/A |
| Generics `[T]` | `~` → `var` (type-erased) | N/A |
| `proc` / `func` | `✓` | `✓` |
| Default parameters | `✓` | `✓` |
| Variadic params | `~` (different spread syntax) | `~` |
| Classes | `✓` | `✓` |
| Single inheritance | `✓` | `✓` |
| `trait` / `interface` | `~` (nominal vs structural) | `~` |
| Multiple interface impl | `✗` (Sage class syntax has none) | `✗` |
| Access modifiers | `✗` (Sage has none) | `✗` (stripped) |
| `override` keyword | `✗` | `✗` |
| `sealed` / `open` | `✗` | `✗` |
| Operator overloading | `~` (dunders vs interfaces) | `~` |
| `if`/`else` | `✓` | `✓` |
| `while` | `✓` | `✓` |
| `do-while` | `✗` | `~` → `while true` + `break` |
| C-style `for` | `✗` | `~` → `while` |
| Range-based `for` | `✓` | `✓` |
| `range()` | `✓` | `~` → `..` range literal |
| `break` / `continue` | `✓` | `✓` |
| `switch`/`case` | N/A | `~` → `match`/`case` |
| `match`/`case` | `✓` | `✓` |
| `try`/`catch`/`finally` | `✓` | `✓` |
| `raise` | `~` (Lily restricts to `T!`) | `✓` |
| `defer` | `✗` | N/A |
| `yield` / generators | `✗` | N/A |
| `async`/`await` | `✗` | N/A |
| `unsafe` block | `~` → `@unsafe` | `~` → `unsafe:`/`end` |
| `comptime` | `✗` | N/A |
| `macro`/`quote` | `✗` | N/A |
| Pointer type | `~` → `mem_alloc` style | `~` → `mem_alloc` |
| `@manual` RAII | N/A | `~` → manual `mem_alloc`/`mem_free` |
| `@Strict` | N/A | `✗` |
| `@inline` pragma | `✓` | `✓` |
| String interpolation | `~` (Sage uses concat) | `~` (Lily uses `{}`) |
| Bitshift | `✓` `<<`/`>>` | `~` `.shl()`/`.shr()` |
| `??` null coalesce | N/A | `~` → `if nil` check |
| `?.` safe navigation | N/A | `~` → `if nil` check |
| `..` / `..=` ranges | N/A | `~` → `range()` |
| `**` power operator | N/A | `~` → `math.pow()` |
| `++` / `--` | N/A | `~` → `x = x + 1` |
| `import` | `~` (prefix required in Lily) | `~` (prefix stripped) |
| FFI (C libs) | `~` | `~` |
| Python FFI | `✗` | N/A |
| LilyKnight sandbox | N/A | `✗` |

---

## 4. Sage → Lily

### 4.1 Variables and Bindings

Sage has only `let` (all bindings immutable). Lily has `var` (mutable), `let` (immutable +
ownership), `const` (compile-time), and `final` (write-once). Since Sage's `let` is immutable
but carries no ownership semantics by default, the safe mapping is Lily `let` — which adds
ownership tracking. Annotate with a comment if this changes runtime behaviour under `@Strict`.

```sage
# Sage
let x = 42
let name: String = "Alice"
let items: Array[Int] = [1, 2, 3]
```

```lily
// Lily
let var x = 42
let string name = "Alice"
let var items = [1, 2, 3]   // Array[Int] → untyped; no generic array annotation in Lily
```

> **Rule:** `let x = expr` → `let var x = expr`  
> **Rule:** `let x: T = expr` → `let <lily_type> x = expr` (see §4.2 for type mapping)  
> **Note:** Lily's `let` enforces ownership tracking. If the Sage source freely copies
> the binding, the transpiled code may need `var` instead. When in doubt, prefer `let` and
> let Firefly catch violations.

### 4.2 Types and Annotations

Sage annotations use `name: Type` (name first). Lily uses `type name` (type first). Syntax
is inverted at every site: variable declarations, parameters, and struct fields.

| Sage Type | Lily Type | Notes |
|-----------|-----------|-------|
| `Int` / `Number` | `int` | Sage stores numbers as double internally; Lily `int` is true 64-bit |
| `Float` / `Number` | `double` | |
| `String` | `string` | |
| `Bool` | `bool` | |
| `Nil` | `nil` (literal), type is `T?` | Sage nil-able by default; use `T?` in Lily |
| `Array` / `Array[T]` | `var` or `[T]` literal | Lily has no typed generic array annotation |
| `Dict[K, V]` | `{K: V}` | |
| `Tuple` | `(T1, T2, ...)` | |
| `T?` (optional) | `T?` | Direct mapping |

**Return type syntax:**

```sage
# Sage
proc multiply(a: Int, b: Int) -> Int:
    return a * b
```

```lily
// Lily
int func multiply(int a, int b):
    return a * b
```

**Generics — lossy:**

```sage
# Sage
proc identity[T](x: T) -> T:
    return x
```

```lily
// Lily
// TRANSPILER: generic [T] erased to dynamic var; type safety lost
var func identity(var x):
    return x
```

**Optional types:**

```sage
# Sage
let maybe: String? = nil
```

```lily
// Lily
let string? maybe = nil
```

### 4.3 Functions (proc → func)

The keyword changes and return type moves from trailing `-> T` to leading `T func name()`.
`void func` for no explicit return. `self` is an implicit receiver in Lily methods (not a
named parameter); strip it from the parameter list when inside a class.

```sage
# Sage — free function
proc greet(name):
    print "Hello, " + name

proc add(x: Int, y: Int) -> Int:
    return x + y
```

```lily
// Lily — free function
void func greet(var name):
    print("Hello, " + name)

int func add(int x, int y):
    return x + y
```

**Self parameter:** Strip `self` from the parameter list. Lily methods have an implicit `self`.

```sage
# Sage
proc speak(self):
    print self.name + " says Woof!"
```

```lily
// Lily
void func speak():
    println("{self.name} says Woof!")
```

**Default parameters:** Direct mapping, syntax adjusted.

```sage
# Sage
proc connect(host, port=8080):
    print "Connecting to " + host + ":" + str(port)
```

```lily
// Lily
void func connect(var host, int port = 8080):
    print("Connecting to {host}:{port}")
```

**Variadic:**

```sage
# Sage
proc log_all(tag, ...args):   # Sage variadic (if supported)
    for a in args:
        print tag + ": " + str(a)
```

```lily
// Lily
void func log_all(var tag, var... args):
    for a in args:
        print("{tag}: {a}")
```

### 4.4 Classes and Inheritance

Class declaration syntax is mostly compatible. Key differences:
- Access modifiers don't exist in Sage — default everything to `public:` in Lily.
- `override` keyword: Sage has none. In Lily, overriding a parent method requires `override`; the
  transpiler must emit it whenever a method name matches a parent's method name. Requires parent
  class analysis.
- `proc init(self, ...)` → `void func init(...)` (self stripped).
- `super.init(name)` → `super.init(name)` (direct).

```sage
# Sage
class Animal:
    proc init(self, name):
        self.name = name

    proc speak(self):
        print self.name + " makes a sound"

class Dog(Animal):
    proc init(self, name, breed):
        super.init(name)
        self.breed = breed

    proc speak(self):
        print self.name + " says Woof!"
```

```lily
// Lily
class Animal:
    public:
        string name

        void func init(string name):
            self.name = name

        void func speak():
            println("{self.name} makes a sound")

class Dog extends Animal:
    public:
        string breed

        void func init(string name, string breed):
            super.init(name)
            self.breed = breed

        // TRANSPILER: 'override' inferred from parent method match
        override void func speak():
            println("{self.name} says Woof!")
```

**The `->` arrow accessor:** Replace all `obj->field` and `obj->method()` with `obj.field` and
`obj.method()`.

```sage
# Sage
dog->speak()        # arrow accessor
dog.speak()         # dot accessor (equivalent)
```

```lily
// Lily — both become:
dog.speak()
// (Lily's -> means outcome routing, never property access)
```

**Dunders → Operator interfaces:**

| Sage dunder | Lily interface + method |
|-------------|------------------------|
| `__str__` | Implement `Stream` → `insert` (makes type streamable) |
| `__eq__` | Implement `Equals` → `equals` |

No other Sage dunders have a standard Lily interface mapping. Flag with a comment.

### 4.5 Structs, Enums, Traits

**Struct:**

Lily's `struct` is `extern struct` — FFI/C-layout only. Sage's `struct` is a value type with
named fields. Map Sage `struct` to a Lily `class` with all fields `public:`.

```sage
# Sage
struct Point:
    x: Int
    y: Int
```

```lily
// Lily
// TRANSPILER: Sage struct → Lily class (no value-type guarantee)
class Point:
    public:
        int x
        int y
```

**Enum:**

```sage
# Sage
enum Color:
    Red
    Green
    Blue
```

```lily
// Lily
enum Color:
    Red
    Green
    Blue
```

Direct mapping for plain variants. Data-carrying variants also map directly:

```sage
# Sage — data variant (if supported)
enum Shape:
    Circle(r)
    Rect(w, h)
```

```lily
// Lily
enum Shape:
    Circle(double r)
    Rect(double w, double h)
```

> **Note:** Lily `match` over an enum is exhaustiveness-checked (Firefly E017). Ensure all Sage
> `match` blocks have a `default:` or cover all variants, or add `case _:` in Lily output.

**Trait → Interface:**

```sage
# Sage
trait Drawable:
    proc draw(self)
```

```lily
// Lily
interface Drawable:
    void func draw()
```

Sage's trait system does not have a syntax for classes to declare `implements Trait`. Lily
requires `class Foo implements Drawable`. The transpiler cannot automatically infer which
classes implement which traits from Sage code; this requires manual annotation or a separate
config file.

```
// TRANSPILER: trait implementation is not declared in Sage class syntax.
// Add 'implements Drawable' to class declarations manually.
```

### 4.6 Control Flow

**if/else:** Direct. No changes needed (both use `else if`-style chaining).

**while:** Direct.

**for with range():**

```sage
# Sage
for i in range(10):
    print i

for i in range(2, 8):
    print i

for i in range(0, 10, 2):
    print i
```

```lily
// Lily
for i in 0..10:
    print(i)

for i in 2..8:
    print(i)

// TRANSPILER: range with step has no Lily range literal; use C-style for
for(var i = 0, i < 10, i += 2):
    print(i)
```

**for over collection:** Direct.

```sage
for fruit in fruits:
    print fruit
```

```lily
for fruit in fruits:
    print(fruit)
```

**break / continue:** Direct.

**Membership test (`in`):**

```sage
# Sage — 'in' as membership test
if 3 in arr:
    print "found"
```

```lily
// Lily — no 'in' for membership; use method
if arr.contains(3):
    print("found")
```

> Lily arrays are expected to have a `contains` method; if the runtime doesn't provide one,
> emit a linear search helper.

**Defer:** Sage `defer` has no Lily equivalent. Emit a comment and wrap the deferred call in
a `@manual` block's `deinit` if inside a class, otherwise flag for manual review.

```sage
# Sage
proc process_file(name):
    let f = open(name)
    defer close(f)
    # ... work ...
```

```lily
// Lily
// TRANSPILER: 'defer' has no Lily equivalent.
// Use @manual RAII with deinit, or restructure with try/finally.
void func process_file(var name):
    var f = open(name)
    try:
        // ... work ...
    finally:
        close(f)
```

### 4.7 Operators

| Sage | Lily | Notes |
|------|------|-------|
| `and` | `and` | Direct |
| `or` | `or` | Direct |
| `not` | `not` | Direct |
| `&` | `&` | Direct (bitwise AND) |
| `\|` | `\|` | Direct (bitwise OR) |
| `^` | `^` | Direct (bitwise XOR) |
| `~` | `~` | Direct (bitwise NOT) |
| `<<` | `.shl(n)` | **Conflict** — Lily `<<` is stream insert |
| `>>` | `.shr(n)` | **Conflict** — Lily `>>` is stream extract |
| `+` `-` `*` `/` `%` | same | Direct |
| `==` `!=` `<` `>` `<=` `>=` | same | Direct |
| `-` (unary) | `-` | Direct |

```sage
# Sage bitshift
let flags = mask << 4
let val = flags >> 2
```

```lily
// Lily
let var flags = mask.shl(4)
let var val = flags.shr(2)
```

**String concatenation:** Sage uses `+`. Lily supports both `+` and string interpolation.
Where interpolation reads more cleanly, prefer it.

```sage
# Sage
print "Hello, " + name + "! You are " + str(age) + " years old."
```

```lily
// Lily
print("Hello, {name}! You are {age} years old.")
```

### 4.8 Pattern Matching

```sage
# Sage
match value:
    case 1:
        print "one"
    case 2:
        print "two"
    case X if condition:
        print "guarded"
    default:
        print "other"
```

```lily
// Lily
match value:
    case 1:
        print("one")
    case 2:
        print("two")
    case _ if condition:   // TRANSPILER: guard variable X → wildcard _ in Lily
        print("guarded")
    case _:
        print("other")
```

> Lily's `match` wildcard is `_`, not `default`. Sage's `default:` → `case _:`.  
> Sage guard syntax `case X if cond` — the bound variable `X` becomes `_`; the guard expression
> references `value` directly instead of `X`.

### 4.9 Exception Handling

The `try`/`catch`/`finally`/`raise` block structure is identical. Key differences:

- Lily's `raise` is legal only inside a function returning `T!`. The transpiler must change the
  return type of any function that contains `raise`.
- Lily's `catch e:` binds a typed error enum. Sage's `catch e:` catches any value.

```sage
# Sage
proc divide(a, b):
    if b == 0:
        raise "Division by zero"
    return a / b
```

```lily
// Lily
// TRANSPILER: function contains raise → return type promoted to T!
var! func divide(var a, var b):
    if b == 0:
        raise DivisionByZero    // define an error enum variant
    return a / b
```

**Sage `->` (dot alias) vs Lily `->` (error routing):**

The `->` error router is a Lily-specific idiom. There is no one-liner equivalent in Sage.
Map Lily `-> default(v)` to a try/catch pattern when going the other direction (see §5.9).
Going Sage → Lily, if the Sage code has manual nil checks or error checks after a call, the
transpiler may suggest `->` patterns but must not emit them automatically without analysis.

### 4.10 I/O

**Print statement → function call:**

```sage
# Sage
print "Hello"
print x
print str(x) + " items"
```

```lily
// Lily
println("Hello")
println(str(x))                // or print("{x}")
println("{x} items")
```

> Sage `print` is a statement. Lily `print()` / `println()` are function calls. Always wrap
> in parens. Prefer `println` (newline) unless the Sage code chains prints on the same line.

**Input:**

```sage
# Sage
let line = input()
```

```lily
// Lily
var line = ""
sin >> line
// or: let var line = read_line()   // depends on Lily stdlib API
```

### 4.11 Imports

Lily requires a source prefix (`lily.`, `py.`, `c.`). Map Sage stdlib modules to `lily.`
prefix. Sage OS modules, ML modules, and graphics modules have no Lily equivalent; flag them.

| Sage import | Lily import | Notes |
|-------------|-------------|-------|
| `import math` | `import lily.math` | |
| `from math import sqrt` | `from lily.math import sqrt` | |
| `import math as m` | `import lily.math as m` | |
| `import io` | `import lily.io` | If Lily stdlib has equivalent |
| `import sys` | `import lily.sys` | If Lily stdlib has equivalent |
| `import os.fat` | `// TRANSPILER: no Lily equivalent` | OS dev modules are Sage-specific |
| `import ml.tensor` | `// TRANSPILER: no Lily equivalent` | ML modules are Sage-specific |
| `import graphics.renderer` | `// TRANSPILER: no Lily equivalent` | Graphics modules are Sage-specific |
| `import thread` | `import lily.thread` | |

### 4.12 Memory and FFI

**Raw memory functions:** Sage's `mem_alloc`, `mem_free`, `mem_read`, `mem_write` map to
Lily's equivalents inside `@manual @unsafe`.

```sage
# Sage
unsafe:
    let ptr = mem_alloc(1024)
    mem_write(ptr, 0, "int", 42)
    let val = mem_read(ptr, 0)
    mem_free(ptr)
end
```

```lily
// Lily
@manual
@unsafe
void func _mem_example() {
    ptr raw buf = mem_alloc(1024);
    mem_write(buf, 0, int, 42);
    var val = mem_read(buf, 0, int);
    mem_free(buf);
}
```

**FFI:**

```sage
# Sage
let lib = ffi_open("libm.so")
let result = ffi_call(lib, "sqrt", 16.0)
ffi_close(lib)
```

```lily
// Lily
// TRANSPILER: Sage FFI → Lily C FFI; declare in .lilyh header
// libm.lilyh: double sqrt(double x)
import c.libm
@unsafe
var result = c.libm.sqrt(16.0)
```

### 4.13 Concurrency

**Threads:** Sage thread module → Lily thread module. Mostly compatible.

```sage
# Sage
import thread
let t = thread.spawn(my_proc, args)
thread.join(t)
```

```lily
// Lily
import lily.thread
var t = lily.thread.spawn(my_proc, args)
lily.thread.join(t)
```

**Async/Await:** Lily 0.1 has no async/await. Sage's `async proc` / `await` cannot be
transpiled. Use threads as an approximation.

```sage
# Sage
async proc compute(x):
    return x * x

let future = compute(42)
print await future
```

```lily
// Lily
// TRANSPILER: async/await not available in Lily 0.1.
// Approximated with threads — semantics differ (no future value return).
import lily.thread

void func compute(var x):
    // TRANSPILER: return value from async proc not directly expressible
    var result = x * x
    print(result)

var t = lily.thread.spawn(compute, [42])
lily.thread.join(t)
```

### 4.14 Metaprogramming

Sage's `comptime`, `macro`, `quote`, and `unquote` have no equivalents in Lily. Emit a
transpiler error and a placeholder comment. Do not attempt to simulate them.

```sage
# Sage
comptime:
    let result = factorial(10)

macro unless(cond, body):
    quote:
        if not unquote(cond):
            unquote(body)
```

```
// TRANSPILER ERROR: comptime and macro constructs have no Lily equivalent.
// These blocks require manual rewrite.
```

### 4.15 Unsupported Sage Features

The following Sage features cannot be transpiled to Lily 0.1 and require manual rewrite
or are out of scope:

| Feature | Reason |
|---------|--------|
| `yield` / generators | Lily 0.1 has no generators by design |
| `async proc` / `await` | Lily 0.1 has no async/await by design |
| `defer` | No RAII sugar in Lily outside of `@manual deinit` |
| `comptime` | No compile-time execution in Lily |
| `macro`/`quote`/`unquote` | No macro system in Lily |
| Blockchain library (`lib/blockchain/`) | Sage-specific |
| ML library (`lib/ml/`) | Sage-specific |
| GPU graphics library (`lib/graphics/`) | Sage-specific |
| LLM library (`lib/llm/`) | Sage-specific |
| Agent AI framework (`lib/agent/`) | Sage-specific |
| OS development library (`lib/os/`) | Sage-specific |
| CUDA library (`lib/cuda/`) | Sage-specific |
| Android library (`lib/android/`) | Sage-specific |
| Discord library (`lib/discord/`) | Sage-specific |
| Inline assembly (`asm_exec`, `asm_compile`) | No Lily equivalent |
| Multiple GC modes (`gc_set_arc`, `gc_set_orc`) | Lily GC internals not exposed |
| Bytecode VM / JIT / AOT backends | Compiler-level, not transpilable |
| `trait` implementations on classes | Sage has no class-level `implements` syntax |

---

## 5. Lily → Sage

### 5.1 Variables and Declarations

Sage only has `let`. Every Lily declaration kind maps to `let`, with a comment noting lost
semantics (mutability, ownership enforcement, compile-time constness).

| Lily | Sage | Notes |
|------|------|-------|
| `var x = 42` | `let x = 42` | Mutable → immutable. **LOSSY**: Sage `let` can't be reassigned. If the variable is reassigned later, restructure with new `let` bindings or flag. |
| `int x = 25` | `let x: Int = 25` | |
| `let int x = 42` | `let x: Int = 42` | Direct |
| `const PI = 3.14` | `let PI = 3.14` | LOSSY: no compile-time guarantee |
| `final result` | `let result = ...` | LOSSY: write-once → immutable |
| `string? maybe = nil` | `let maybe = nil` | Optional type → unenforced nil |

> **Critical:** Lily `var` is mutable and may be reassigned. Sage `let` is immutable. When
> a Lily `var` is reassigned in the original code, the transpiler must restructure using new
> `let` bindings (shadowing in the same scope) or use a workaround. Sage has no mutable
> variable primitive.
>
> **Workaround pattern for mutable accumulation:**
> ```lily
> // Lily
> var total = 0
> for n in nums:
>     total += n
> ```
> ```sage
> # Sage — accumulate via mutable workaround using class or array
> # TRANSPILER: mutable var has no Sage equivalent; use array cell
> let acc = [0]
> for n in nums:
>     acc[0] = acc[0] + n
> let total = acc[0]
> ```

### 5.2 Types and Annotations

Type annotation syntax is inverted: Lily puts type before name, Sage puts name before type
with a colon.

| Lily | Sage annotation |
|------|----------------|
| `int x` | `x: Int` |
| `double ratio` | `ratio: Float` (or `Number`) |
| `string name` | `name: String` |
| `bool flag` | `flag: Bool` |
| `int? maybe` | `maybe` (no optional enforcement) |
| `{string: int} ages` | `ages: Dict[String, Int]` |
| `(int, string) row` | `row: Tuple` (no typed tuple in Sage) |

**Fallible type `T!`:** Sage has no `T!`. Functions returning `T!` become Sage procs that
use `try`/`catch`. See §5.9.

**Optional type `T?`:** Sage has no enforced optionals. `T?` fields become untyped Sage
bindings; nil checks from `??` and `?.` are rewritten to explicit if-nil guards.

### 5.3 Functions (func → proc)

Return type moves from leading position to trailing `-> T`. `void` is dropped.

```lily
// Lily
void func greet(string name):
    println("Hello, {name}")

int func add(int a, int b):
    return a + b

var func identity(var x):
    return x
```

```sage
# Sage
proc greet(name: String):
    print "Hello, " + name

proc add(a: Int, b: Int) -> Int:
    return a + b

proc identity(x):
    return x
```

**Static methods:** Lily `static T func name()` → Sage top-level `proc` (outside class).
Sage has no static method concept; restructure as module-level procs.

```lily
// Lily
static Point func polar(double r, double theta):
    return Point(r * math.cos(theta), r * math.sin(theta))
```

```sage
# Sage
# TRANSPILER: static method → module-level proc (loses class namespace)
proc Point_polar(r, theta):
    return Point(r * math.cos(theta), r * math.sin(theta))
```

**Method modifiers (`override`, `final func`, etc.):** Stripped in Sage — no equivalents.

### 5.4 Classes and Inheritance

```lily
// Lily
class Animal:
    public:
        string name

        void func init(string name):
            self.name = name

        void func speak():
            println("...")

class Dog extends Animal:
    public:
        void func init(string name):
            super.init(name)

        override void func speak():
            println("{self.name}: woof")
```

```sage
# Sage
class Animal:
    proc init(self, name: String):
        self.name = name

    proc speak(self):
        print "..."

class Dog(Animal):
    proc init(self, name: String):
        super.init(name)

    # TRANSPILER: 'override' stripped — not a Sage keyword
    proc speak(self):
        print self.name + ": woof"
```

**Access modifiers:** Sage has none. Strip `public:` / `private:` / `protected:` blocks and
emit all methods/fields as-is. Flag `private:` members with a comment.

```
# TRANSPILER: private members have no access restriction in Sage.
# The following fields/methods are public by default.
```

**`sealed class` / `open class` / `final func`:** All Lily inheritance control keywords are
dropped. Sage has no equivalent enforcement.

**`deinit`:** Lily's destructor method. Sage has no destructor. If the `deinit` contains
critical cleanup (memory, file handles), map it to a `defer` call at the call site, or flag
for manual review.

```lily
// Lily @manual
void func deinit():
    mem_free(self.buf)
```

```sage
# Sage
# TRANSPILER: deinit has no Sage equivalent.
# If self.buf was mem_alloc'd, emit mem_free at each use site or use defer.
proc cleanup(self):
    mem_free(self.buf)
```

### 5.5 Interfaces and Enums

**Interface → Trait:**

```lily
// Lily
interface Drawable:
    void func draw()

    void func draw_twice():
        self.draw()
        self.draw()
```

```sage
# Sage
trait Drawable:
    proc draw(self)

    proc draw_twice(self):
        self.draw()
        self.draw()
```

> Lily's `class Foo implements Drawable` → Sage has no implements syntax. Strip the
> declaration. Sage uses structural duck typing, so the trait is satisfied implicitly.

**Enum — plain variants:** Direct.

**Enum with data:** Direct (Sage enums support data variants).

**Enum with methods:** Sage enums don't officially specify method support in the spec.
Emit methods as a note for manual handling.

**Enum with backing values:**

```lily
// Lily
enum Status:
    Ok       = 200
    NotFound = 404
```

```sage
# Sage
enum Status:
    Ok
    NotFound
# TRANSPILER: backing values (200, 404) not supported in Sage enum. Strip them.
# Use a dict for the value mapping:
let STATUS_VALUES = {"Ok": 200, "NotFound": 404}
```

**Operator overloading via interfaces:**

```lily
// Lily
class Vec2 implements Add:
    override Vec2 func add(Vec2 other):
        return Vec2(self.x + other.x, self.y + other.y)
```

```sage
# Sage
class Vec2:
    # TRANSPILER: Lily 'Add' interface → Sage __add__ dunder (if supported)
    proc __add__(self, other):
        return Vec2(self.x + other.x, self.y + other.y)
```

> Sage only documents `__str__` and `__eq__` dunders. Operator overloading dunders
> beyond those are undocumented and may not work. Flag accordingly.

### 5.6 Control Flow

**if / else if / else:** Direct.

**while:** Direct.

**do-while:** No Sage equivalent. Rewrite as `while true` with a break.

```lily
// Lily
do:
    x = x + 1
while x < 10
```

```sage
# Sage
# TRANSPILER: do-while → while-true + break
while true:
    x = x + 1
    if not (x < 10):
        break
```

**C-style for:** Rewrite as `while`.

```lily
// Lily
for(var i = 0, i < arr.length, i++):
    print(arr[i])
```

```sage
# Sage
# TRANSPILER: C-style for → while loop
let i = [0]    # mutable counter via array cell
while i[0] < len(arr):
    print arr[i[0]]
    i[0] = i[0] + 1
```

**Range-based for:**

```lily
// Lily
for item in arr:
    print(item)

for i in 0..10:    // exclusive
    print(i)

for i in 0..=10:   // inclusive
    print(i)
```

```sage
# Sage
for item in arr:
    print item

for i in range(10):
    print i

for i in range(0, 11):   # inclusive → range(start, end+1)
    print i
```

**Increment / Decrement:**

```lily
// Lily
i++
i--
i += 2
```

```sage
# Sage
i = i + 1
i = i - 1
i = i + 2
```

**switch/case → match/case:**

```lily
// Lily
switch status:
    case 200, 201:
        println("success")
    case 404:
        println("not found")
    default:
        log(status)
```

```sage
# Sage
# TRANSPILER: switch → match; no fallthrough in either; default → 'default'
match status:
    case 200:
        print "success"
    case 201:
        print "success"
    # TRANSPILER: multi-value case split into separate cases
    case 404:
        print "not found"
    default:
        # log() — map to equivalent Sage call
        print str(status)
```

> Lily allows `case 200, 201:` multi-value cases. Sage match does not. Split into
> individual cases that share the same body.

> Lily `continue` inside switch = fallthrough. Sage has no fallthrough in match; flag it.

### 5.7 Operators

| Lily | Sage | Notes |
|------|------|-------|
| `**` (power) | `math.pow(a, b)` | Sage has no `**` operator |
| `++a` / `a++` | `a = a + 1` | Sage has no increment |
| `--a` / `a--` | `a = a - 1` | Sage has no decrement |
| `??` | `if x == nil: fallback else: x` | No null coalesce in Sage |
| `?.` | `if x == nil: nil else: x.field` | No safe nav in Sage |
| `..` (exclusive range) | `range(start, end)` | |
| `..=` (inclusive range) | `range(start, end + 1)` | |
| `...` (spread) | No equivalent | Sage has no spread |
| `<<` (stream insert) | `print` / `str()` + concat | **Conflict** — see §2.2 |
| `>>` (stream extract) | `input()` | **Conflict** — see §2.2 |
| `.shl(n)` | `<< n` | Sage `<<` is bitshift |
| `.shr(n)` | `>> n` | Sage `>>` is bitshift |
| `and` / `or` / `not` | `and` / `or` / `not` | Direct |
| `&&` / `\|\|` / `!` | `and` / `or` / `not` | Normalize to keyword form |

**`??` null coalesce:**

```lily
// Lily
let count = maybe ?? 0
```

```sage
# Sage
# TRANSPILER: ?? null coalesce → explicit nil check
let count = 0
if maybe != nil:
    count = maybe
```

**`?.` safe navigation:**

```lily
// Lily
string? city = user?.address?.city
```

```sage
# Sage
# TRANSPILER: ?. safe nav → chained nil checks
let city = nil
if user != nil:
    if user.address != nil:
        city = user.address.city
```

**Power operator:**

```lily
// Lily
var result = a ** 3
```

```sage
# Sage
import math
let result = math.pow(a, 3)
```

### 5.8 Pattern Matching

```lily
// Lily
match result:
    case Ok(v):
        print("got {v}")
    case Err(e):
        print("error: {e}")
    case _:
        print("unknown")
```

```sage
# Sage
match result:
    case Ok(v):
        print "got " + str(v)
    case Err(e):
        print "error: " + str(e)
    default:
        print "unknown"
```

> Lily `case _:` wildcard → Sage `default:`.

### 5.9 Error Handling

**try/catch/finally/raise:** Structurally identical. Adjust syntax (indentation, parens).

```lily
// Lily
try:
    var result = risky_operation()
    print(result)
catch e:
    print("Error: {e}")
finally:
    print("cleanup")
```

```sage
# Sage
try:
    let result = risky_operation()
    print result
catch e:
    print "Error: " + str(e)
finally:
    print "cleanup"
```

**Lily `T!` fallible type:**

```lily
// Lily
int! func withdraw(int balance, int amount):
    if amount > balance:
        raise InsufficientFunds
    return balance - amount
```

```sage
# Sage
# TRANSPILER: T! return type → proc with raise; callers must use try/catch
proc withdraw(balance: Int, amount: Int) -> Int:
    if amount > balance:
        raise "InsufficientFunds"
    return balance - amount
```

**`->` outcome routing:**

```lily
// Lily
let config = read_file("config.toml") -> default("{}")
let n = parse_int(input) -> retry(3) -> default(0)
let data = fetch(url) -> raise
```

```sage
# Sage
# TRANSPILER: -> default(v) → try/catch with fallback
let config = "{}"
try:
    config = read_file("config.toml")
catch e:
    config = "{}"    # default

# -> retry(3) -> default(0)
let n = 0
let success = false
let attempts = 0
while not success and attempts < 3:
    try:
        n = parse_int(input())
        success = true
    catch e:
        attempts = attempts + 1

# -> raise
# (re-raise is already natural in Sage — just don't catch it)
let data = fetch(url)
```

**Specific handler mapping:**

| Lily `->` handler | Sage equivalent |
|-------------------|----------------|
| `-> default(v)` | `try: result = expr catch e: result = v` |
| `-> retry(n)` | While loop with counter + try/catch |
| `-> raise` | Don't catch (let exception propagate) |
| `-> warn` | `try: expr catch e: print "Warning: " + str(e)` |
| `-> nullcollect` | No Sage equivalent; flag |

### 5.10 I/O

**Print functions:**

```lily
// Lily
print("hello")          // no newline
println("hello")        // with newline
sout << "value: " << x << endl
serr << "error message"
sin >> user_input
```

```sage
# Sage
print "hello"              # Sage print behavior (newline TBD per impl)
print "hello"
print "value: " + str(x)
# TRANSPILER: serr has no Sage stderr equivalent; use print
print "error message"
let user_input = input()
```

**`printserial`:** No Sage equivalent. Map to `print` with a debug comment.

### 5.11 Imports

Lily prefixes: `lily.*`, `py.*`, `c.*`. Strip the prefix for Sage, adding a note.

| Lily import | Sage import | Notes |
|-------------|-------------|-------|
| `import lily.math` | `import math` | |
| `from lily.math import sqrt` | `from math import sqrt` | |
| `import lily.http as http` | `import http as http` | |
| `import py.numpy as np` | `# TRANSPILER: Python FFI not available in Sage` | |
| `import c.math` | `let libm = ffi_open("libm.so")` | Sage uses explicit FFI |
| `import lily.frogpond` | `# TRANSPILER: LilyKnight not available in Sage` | |
| `import lily.sandbox` | `# TRANSPILER: LilyKnight not available in Sage` | |
| `import "path/to/file"` | `import path.to.file` | Path import — normalize |

### 5.12 Memory, Pointers, FFI

**Lily pointer types → Sage raw memory:**

```lily
// Lily
int age = 25
ptr int p = addr age
*p = 30
sout << age      // 30
```

```sage
# Sage
let age = 25
# TRANSPILER: Lily ptr T / addr / * → Sage raw pointer via mem_alloc or addressof
# Sage pointers are read via mem_read/mem_write; addressof gives the address.
# Direct stack-variable pointer binding is not idiomatic in Sage.
let p = addressof(age)
# No Sage equivalent for *p = 30 on a stack variable.
# TRANSPILER: requires manual rewrite or use of a single-element array as a cell.
let age_cell = [25]
# age_cell[0] acts as mutable cell
age_cell[0] = 30
```

**`@manual` RAII → manual Sage memory:**

```lily
// Lily
@manual
@unsafe
void func process_data() {
    ptr int buf = mem_alloc(sizeof(int));
    *buf = 42;
}   // buf freed at scope exit (RAII)
```

```sage
# Sage
# TRANSPILER: @manual RAII → explicit mem_free; no automatic scope cleanup
unsafe:
    let buf = mem_alloc(sizeof("int"))
    mem_write(buf, 0, "int", 42)
    mem_free(buf)    # TRANSPILER: must be placed manually; no deinit in Sage
end
```

**C FFI:**

```lily
// Lily — C FFI via header
import c.libm
var r = c.libm.sqrt(16.0)
```

```sage
# Sage — explicit FFI
let libm = ffi_open("libm.so")
let r = ffi_call(libm, "sqrt", 16.0)
ffi_close(libm)
```

**`extern struct` → `struct_def`:**

```lily
// Lily
extern struct Timespec:
    int seconds
    int nanos
```

```sage
# Sage
let Timespec = struct_def({"seconds": "i64", "nanos": "i64"})
```

### 5.13 Annotations

| Lily annotation | Sage equivalent |
|----------------|----------------|
| `@manual` | No direct equivalent; restructure with `mem_alloc`/`mem_free` |
| `@gc` | Default in Sage; no annotation needed |
| `@unsafe` | `unsafe: ... end` block |
| `@inline` | `@inline` pragma (Sage supports this) |
| `@hotpath` | No Sage equivalent; strip |
| `@Strict` | No Sage equivalent; strip + comment |
| `@Catch` | No Sage equivalent; strip + comment |

```lily
// Lily
@inline
int func fast_add(int a, int b):
    return a + b
```

```sage
# Sage
@inline
proc fast_add(a: Int, b: Int) -> Int:
    return a + b
```

### 5.14 Unsupported Lily Features

| Feature | Reason |
|---------|--------|
| `var` (mutable reassignable) | Sage has no mutable variable; workaround with array cells |
| `const` (compile-time) | Sage has no compile-time constants |
| `final` (write-once) | Sage has no write-once enforcement |
| `T!` fallible type | Sage uses exception-based error handling only |
| `T?` optional type | No enforced optionals in Sage |
| `??` null coalesce | No operator; manual nil check |
| `?.` safe navigation | No operator; manual nil check |
| `..` / `..=` range literals | Use `range()` |
| `**` power | Use `math.pow()` |
| `++` / `--` | Use `x = x + 1` / `x = x - 1` |
| `...` spread | No Sage spread operator |
| `do-while` | Rewrite as `while true` + `break` |
| C-style `for` | Rewrite as `while` |
| `ptr T` / `addr` / `*` dereference | Use `addressof` + `mem_read`/`mem_write` |
| `@manual` RAII / `deinit` | No automatic destructor in Sage |
| `@Strict` | No Sage equivalent |
| `@Catch` | No Sage equivalent |
| `@hotpath` | No Sage equivalent |
| `->` outcome routing | Rewrite with `try`/`catch` |
| `switch`/`case` (with multi-value case) | Rewrite as multiple `match` cases |
| `sout` / `sin` / `serr` | `print` / `input()` |
| Access modifiers (`public`, `private`, `protected`) | Stripped; all members public |
| `override`, `sealed`, `open`, `final func` | Stripped; no equivalent |
| `interface` with `implements` | Sage `trait`; class impl is structural (implicit) |
| Operator overloading interfaces (`Add`, `Eq`, etc.) | Limited to `__str__`, `__eq__` dunders |
| LilyKnight sandbox / FrogPond | Sage-specific sandbox does not exist in Lily or vice versa |
| Python FFI (`py.*`) | Sage has no embedded CPython |
| `.lilyh` header files | Sage uses module system; no header concept |
| `printserial` | Map to `print` with debug note |
| `@manual` `sizeof(type)` | Sage `sizeof(type_name)` (string argument) |

---

## 6. Semantic Gap Reference

The following table consolidates the hardest gaps — cases where the translation is
non-trivial or produces code with different runtime behaviour.

| Gap | Sage side | Lily side | Impact |
|-----|-----------|-----------|--------|
| Mutability model | All bindings immutable (`let`) | `var` mutable, `let` owned immutable | Lily code with reassigned `var` cannot cleanly map to Sage |
| Integer precision | Numbers stored as double internally (loses integers > 2^53) | `int` is true 64-bit signed integer | Lily code relying on 64-bit int precision may break on Sage |
| Overflow behavior | Unchecked wrap (double semantics) | Trap by default; wrapping explicit | Sage will silently wrap where Lily would trap E032 |
| `nil` semantics | Nil-able by default | Non-optional types reject nil; `T?` for nullable | Sage nil-anywhere vs Lily `int? maybe` enforcement |
| `->` operator | Property alias | Outcome router | Must be distinguished at parse time |
| `<<` / `>>` | Bitshift | Stream I/O | Must be distinguished by context |
| Ownership | No ownership system | `let` tracks ownership, `@Strict` enforces everywhere | Lily code may move values in ways Sage cannot express |
| Generator `yield` | Supported | Not available in Lily 0.1 | Hard gap |
| `async`/`await` | Supported | Not available in Lily 0.1 | Hard gap |
| `defer` | Supported | Not available in Lily | Hard gap |
| `comptime` / macros | Supported | Not available in Lily | Hard gap |
| Access control | None | `public`/`private`/`protected` | Sage output has no access enforcement |
| `override` enforcement | None | Mandatory in Lily | Sage-generated code may silently shadow parent methods |
| Trait `implements` | No class-level syntax | Explicit and checked | Implicit structural satisfaction in Sage; Lily requires explicit decl |
| Operator overloading | `__str__`, `__eq__` only | Full interface set (`Add`, `Compare`, `Index`, etc.) | Many Lily operator overloads cannot be expressed in Sage |
| Python FFI | Not available | `import py.*` | Lily Python interop cannot be transpiled to Sage |
| `ptr T` / pointer arithmetic | Via `mem_*` functions | First-class `ptr T` type | Lily pointer idioms are awkward in Sage |
| `@manual` RAII / `deinit` | No destructor | Deterministic scope-based cleanup | Lily RAII cleanup must be manually placed in Sage |
| String interpolation | String concatenation | `{expr}` in string literals | Style difference; semantically equivalent |

---

## 7. Implementation Notes

### 7.1 AST-Level Transpilation

Both languages have a recursive-descent parser producing an AST. The transpiler should
operate at AST level, not text level. Doing text-level substitution will misfire on edge
cases (e.g. `->` inside a string literal, `in` inside an identifier).

### 7.2 Symbol Table Requirements

The transpiler needs a symbol table to:
- Identify whether a `->` in Sage is a dot alias (always) vs potentially an issue.
- Determine parent class methods to emit `override` correctly in Lily output.
- Infer return types of `proc`s that contain `raise`, to emit `T!` in Lily.
- Identify which `var` bindings in Lily are reassigned later (to decide `let` vs array-cell
  workaround in Sage).

### 7.3 Print Newline Behavior

Sage `print` may or may not add a newline depending on the implementation backend. Treat
Sage `print` as equivalent to Lily `println()` (with newline). If trailing-no-newline
behavior is required, emit a comment.

### 7.4 Type Inference Direction

When Sage has no type annotation, infer a Lily type from the literal:

| Sage literal | Inferred Lily type |
|--------------|-------------------|
| `42` | `int` |
| `3.14` | `double` |
| `"hello"` | `string` |
| `true` / `false` | `bool` |
| `nil` | type is `T?` (unknown T; use `var?` or drop annotation) |
| `[1, 2, 3]` | `var` (no generic array type in Lily) |
| `{"a": 1}` | `{string: int}` |
| `(1, "x")` | `(int, string)` |

### 7.5 Multi-Value `case` Splitting (Lily → Sage)

Lily allows `case 200, 201, 204:` in a `switch`. Sage `match` does not. Duplicate the body
for each value:

```lily
case 200, 201, 204:
    println("success")
```

```sage
case 200:
    print "success"
case 201:
    print "success"
case 204:
    print "success"
```

### 7.6 Mutable Variable Workaround

When Lily `var x` is reassigned in a loop or branch, and the transpiler cannot restructure
with shadow `let` bindings, use a single-element array as a mutable cell:

```sage
let x = [initial_value]    # cell
# ... later ...
x[0] = new_value           # mutation via index
# ... read as ...
print x[0]
```

This is ugly but correct. Emit a `# TRANSPILER: mutable cell` comment.

### 7.7 Firefly Error Types → Sage Exception Values

Lily's structured Firefly error codes (E001–E109) become Sage string or dictionary
exceptions. When a Lily function raises a named error enum, use the enum variant name as
a string in Sage:

```lily
// Lily
raise InsufficientFunds
```

```sage
# Sage
raise "InsufficientFunds"
```

---

## 8. Quick Reference Tables

### 8.1 Keyword Map

| Sage | Lily | Direction |
|------|------|-----------|
| `let` | `let` (with type) / `var` | ↔ |
| `proc` | `func` (with return type) | ↔ |
| `class Foo(Bar)` | `class Foo extends Bar` | ↔ |
| `self` (explicit first param) | `self` (implicit, no param) | ↔ |
| `init` | `init` | ↔ |
| `super.init(...)` | `super.init(...)` | ↔ |
| `match` / `case` / `default` | `match` / `case` / `case _` | ↔ |
| `try` / `catch` / `finally` / `raise` | same | ↔ |
| `import X` | `import lily.X` | ↔ |
| `from X import Y` | `from lily.X import Y` | ↔ |
| `print expr` | `print(expr)` / `println(expr)` | ↔ |
| `and` / `or` / `not` | `and` / `or` / `not` | ↔ |
| `nil` | `nil` | ↔ |
| `true` / `false` | `true` / `false` | ↔ |
| `struct Foo` | `class Foo` (public fields) | ↔ |
| `trait Foo` | `interface Foo` | ↔ |
| `enum Foo` | `enum Foo` | ↔ |
| `async proc` | *(no equivalent)* | Sage → Lily only |
| `yield` | *(no equivalent)* | Sage → Lily only |
| `defer` | *(no equivalent, use try/finally)* | Sage → Lily only |
| `unsafe: end` | `@unsafe` block | ↔ |
| `@inline` | `@inline` | ↔ |
| *(none)* | `var` (mutable) | Lily → Sage |
| *(none)* | `const` | Lily → Sage |
| *(none)* | `final` | Lily → Sage |
| *(none)* | `override` / `sealed` / `open` | Lily → Sage |
| *(none)* | `public:` / `private:` / `protected:` | Lily → Sage |
| *(none)* | `@Strict` / `@manual` / `@Catch` | Lily → Sage |
| *(none)* | `do ... while` | Lily → Sage |
| *(none)* | `T!` fallible type | Lily → Sage |
| *(none)* | `??` / `?.` | Lily → Sage |
| *(none)* | `..` / `..=` ranges | Lily → Sage |
| *(none)* | `**` power | Lily → Sage |
| *(none)* | `++` / `--` | Lily → Sage |

### 8.2 Type Map

| Sage | Lily |
|------|------|
| `Int` / `Number` | `int` |
| `Float` / `Number` | `double` |
| `String` | `string` |
| `Bool` | `bool` |
| `Nil` | (nil literal, type is `T?`) |
| `Array` | `var` / `[T]` literal |
| `Dict` | `{K: V}` |
| `Tuple` | `(T1, T2, ...)` |
| `T?` | `T?` |
| *(none)* | `T!` |
| `Pointer` | `ptr T` / `ptr raw` |
| `CLib` | (via `import c.*`) |
| `Bytes` | `ptr raw` + `mem_*` |

### 8.3 Operator Map

| Sage | Lily | Notes |
|------|------|-------|
| `<<` (bitshift) | `.shl(n)` | Conflict |
| `>>` (bitshift) | `.shr(n)` | Conflict |
| `->` (dot alias) | `.` | Conflict |
| `in` (membership) | `.contains()` | Method call |
| `+` `-` `*` `/` `%` | same | Direct |
| `==` `!=` `<` `>` `<=` `>=` | same | Direct |
| `&` `\|` `^` `~` | same | Direct |
| `and` `or` `not` | same | Direct |
| *(none)* | `**` | power |
| *(none)* | `??` | null coalesce |
| *(none)* | `?.` | safe nav |
| *(none)* | `..` / `..=` | ranges |
| *(none)* | `++` / `--` | increment |
| *(none)* | `<<` (stream) | I/O |
| *(none)* | `>>` (stream) | I/O |
| *(none)* | `->` (route) | error handler |
