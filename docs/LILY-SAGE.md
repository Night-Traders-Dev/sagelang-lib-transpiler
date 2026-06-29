# Lily Language Specification

Version 0.1.0-draft  
Status: Planning  
Maintainer: MilkmanAbi  

> "A kinder language for friendlier times."  
> "The developer has a choice in his tooling, an absolute freedom to his implementation."

Lily is a compiled and interpreted programming language. It does not try to be new or unique.
It tries to be good. Inspired by C++, Python, and Rust, it takes the best from each and gives
the developer genuine freedom in how they write, how they manage memory, and how they run their programs.

---

## Table of Contents

1. Lexical Structure
2. Type System
3. Variables and Declarations
4. Pointers
5. Functions
6. Control Flow
7. Classes and Enums
8. Memory Management
9. Ownership System
10. Annotations
11. Import System
12. Header Files
13. I/O
14. Error Handling
15. File Structure
16. Subsystems
17. LilyKnight Sandbox
18. FFI
19. Appendix: Firefly Error Codes

---

## 1. Lexical Structure

### 1.1 Keywords

```
var  let  const  final  void  bool  double  int  string  raw  ptr  addr
func  return  if  else
while  do  for  in  break  continue
switch  case  default  match
class  interface  enum  struct  public  private  static
extends  implements  override  open  sealed  self  super  protected
import  from  as  extern
try  catch  finally  raise
true  false  nil
and  or  not
```

### 1.2 Identifiers

- Any length, no limit
- Uppercase and lowercase letters allowed
- Digits allowed, but not as the first character
- `_` allowed as a word separator
- `-` is not allowed: it is the subtraction operator, so `a-b` must always mean `a minus b`
- No other symbols permitted
- No spaces

Valid: `age`, `age_of_max`, `myVariable123`, `MAX_SPEED`, `http_server_port`  
Invalid: `3age`, `my age`, `age@max`, `age-of-max` (parsed as `age - of - max`)

Both `snake_case` and `camelCase` are valid. The standard library uses `snake_case`.

### 1.3 Comments

```lily
// Single-line comment

/* Multi-line
   comment */
```

### 1.4 Literals

```lily
// Integers
42
0xFF        // hex
0b1010      // binary
0o77        // octal

// Doubles
3.14
1.0e10
-0.5

// Strings
"hello"
"interpolation: {expression}"
"escape: \n \t \\ \""

// Boolean
true
false

// Nil
nil

// Arrays
[1, 2, 3]
["hello", "world"]

// Dicts and tuples: see Section 2.9
```

### 1.5 Operators

Lily uses C++ operators with Python-compatible alternatives where applicable.

```
Arithmetic:    +   -   *   /   %   **
Comparison:    ==  !=  <   >   <=  >=
Logical:       and  or  not   (also: &&  ||  !)
Bitwise:       &   |   ^   ~              (bit-shift is the shl / shr methods, not an operator)
Assignment:    =   +=  -=  *=  /=  %=
Increment:     ++  --
Null coalesce: ??
Safe nav:      ?.
Outcome route: ->
Range:         ..  ..=
Variadic/pack: ...
Stream:        <<  >>                     (stream insert / extract, see Section 13)
```

### 1.6 Operator Precedence

Tightest binding first. Operators on the same line share precedence.

```
 1  postfix:    a()   a[i]   a.b   a?.b   a.0   a++   a--          (left)
 2  prefix:     not a   !a   ~a   -a   *p   addr a   ++a   --a      (right)
 3  power:      **                                                 (right)
 4  multiply:   *   /   %                                          (left)
 5  add:        +   -                                              (left)
 6  range:      ..   ..=                                           (left)
 7  bit-and:    &                                                  (left)
 8  bit-xor:    ^                                                  (left)
 9  bit-or:     |                                                  (left)
10  compare:    <   >   <=   >=                                    (left)
11  equality:   ==   !=                                            (left)
12  and:        and   &&                                           (left)
13  or:         or   ||                                            (left)
14  coalesce:   ??                                                 (left)
15  stream:     <<   >>                                            (left)
16  route:      ->                                                 (left)
17  assign:     =   +=   -=   *=   /=   %=                          (right)
```

So `a + b * c == d and not e` groups as `((a + (b * c)) == d) and (not e)`. Bitwise `&` `^` `|` bind
tighter than comparison, fixing the C wart where `a & b == c` surprises. Stream `<<` `>>` sit low,
below arithmetic, comparison, and logic, so `sout << a + b` is `sout << (a + b)` (Section 13.2). `->`
binds looser than everything but assignment and chains left to right, so
`let n = parse(s) -> retry(3) -> default(0)` routes the whole right-hand side (Section 14.3).

---

## 2. Type System

Lily uses gradual typing. Annotations are optional, but enforced wherever present. The
same type names mean the same thing whether Lily is interpreted or compiled.

### 2.1 Value Model

Lily follows the approach proven by C++, the JVM, and C#: **how a value is represented
depends on whether its type is known.**

- **When the type is statically known** (a typed binding like `int x`, a typed parameter,
  a typed class field, or anything inference has pinned down), the value is stored in its
  **native, untagged form**. An `int` is a raw 64-bit machine integer, a `double` is a raw
  64-bit IEEE-754 float, a `bool` is a raw byte. No type tag, no box, no runtime type check.
  Typed Lily code carries zero representation overhead, and the AOT backend emits the same
  machine code a C compiler would for the equivalent native type.

- **When the type is dynamic** (`var` whose type cannot be resolved, untyped parameters,
  or heterogeneous containers), the value is stored as a **tagged value**: a small
  discriminant plus storage wide enough to hold any single Lily value. This is the same
  design as C++'s `std::variant`. A tagged value is wider than a native value, because it
  must carry both the payload and the tag. That extra width is the price of runtime
  polymorphism, and it is paid only by dynamic values, never by typed ones.

Heap-allocated values (`string`, arrays, dicts, class instances, closures) are always
reached through a pointer whose target carries its own type header. Adding a new heap type
never changes the size of a value, and never forces a change anywhere a value is handled.

This split is what lets Lily offer both "write `var` and forget about types" and "annotate
everything and pay nothing for it" in one language. You choose where on that line you sit,
per binding. Annotate the hot path and it runs like C; leave the glue dynamic and it stays
convenient.

### 2.2 Primitive Types

| Type | Description |
|------|-------------|
| `int` | True 64-bit signed integer. Full range in every context, interpreted or compiled. Never backed by a float, never silently truncated. |
| `double` | 64-bit IEEE-754 floating point. |
| `bool` | Boolean. `true` or `false`. |
| `string` | UTF-8 string, heap-allocated, reached by pointer. |
| `raw` | Raw memory value. Always native and untagged. Poweruser feature, see Section 2.5. |
| `var` | Type inferred at compile or interpretation time. Resolves to a native or a tagged representation per Section 2.1. |

**On `int` specifically.** `int` is a genuine 64-bit signed integer everywhere, with the
full range `-2^63` to `2^63 - 1`. It is not a float in disguise. Code that depends on all
64 bits behaves correctly: 64-bit hashes (FNV-1a, xxHash, wyhash), 64-bit PRNG state
(xorshift64, splitmix64, PCG), nanosecond timestamps, and `uint64_t` / `size_t` / `off_t`
values returned across the C FFI all round-trip without precision loss.

This is a deliberate departure from languages that represent every number as a double and
quietly lose precision past 2^53. Lily does not do that. A nanosecond Unix timestamp today
is already about two hundred times larger than 2^53, so a double-backed integer would
silently corrupt it. Lying about an integer's range is exactly the class of silent failure
Lily exists to eliminate.

A dynamic (tagged) `int` reserves enough storage to hold a full 64-bit value alongside its
tag, so it is just as exact as a typed `int`. The cost of going dynamic is width, never
correctness.

### 2.3 Type Inference

`var` is inferred from the right-hand side of the assignment. The resolved type is fixed
after the first assignment.

```lily
var x = 42           // int
var name = "Lily"    // string
var ratio = 3.14     // double
var active = true    // bool
```

### 2.4 Type Promotion

When mixing `int` and `double` in arithmetic, the result is `double`.

```
int + int       -> int
int + double    -> double
double + double -> double
```

Integer division truncates: `10 / 3` produces `3`.  
Mixed division promotes: `10 / 3.0` produces `3.333...`.

### 2.5 The `raw` Type

`raw` stores a value directly at a memory address. It is always native and untagged. It is
a poweruser feature intended for scientific computation, low-level work, and cases where
direct memory control is needed. It bypasses type safety and can produce undefined behavior, so `raw`, and any operation on it, may appear only inside an `@unsafe` scope (Section 10).

```lily
@unsafe
raw data = 0xFF00FF
```

`raw` is not subject to ownership tracking and does not interact with the GC.
Use with intent.

### 2.6 String Interpolation

Strings support inline expression interpolation using `{}`.

```lily
string name = "Lily"
int version = 1
print("Welcome to {name} v{version}")   // Welcome to Lily v1
```

### 2.7 Integer Overflow

`int` arithmetic traps on overflow by default. When an operation would exceed the 64-bit range,
Lily raises a Firefly error (E032) at the point it happens, rather than silently wrapping around.
This is the honest default: an `int` that quietly reports `a + b` as a negative number after
overflow is lying, and silent wraparound is exactly the class of bug Lily exists not to hide.

Wraparound is a legitimate thing to want in specific places (hashes, PRNG state, ring counters,
and checksums all rely on modular arithmetic), so it is available explicitly, per operation,
rather than as a silent global default:

| Form | Behavior on overflow |
|------|----------------------|
| `a + b` (and the other operators) | Trap: raise E032 |
| `a.wrapping_add(b)` | Wrap, two's-complement modular arithmetic |
| `a.saturating_add(b)` | Clamp to the type's minimum or maximum |
| `a.checked_add(b)` | Return an `int!` (the result, or an overflow error), handled through `->`, `try`, or `match` (Section 14) |

The same `wrapping_`, `saturating_`, and `checked_` forms exist for the other arithmetic
operators. Choosing wraparound is therefore a visible, local decision a reader can see, not an
ambient surprise.

In a designated performance context (`@hotpath`, or a release build that opts in), the
per-operation overflow check may be elided, trading the guarantee for speed exactly where you
asked for it. This mirrors the rest of Lily's safety model: the safe, honest behavior is the
default, and shedding it is explicit.

### 2.8 Optional Types

A normal type can never hold `nil`. An `int` is always an integer and a `string` is always a string;
Firefly rejects assigning `nil` to either. This is deliberate: the billion-dollar mistake is letting
nil hide inside a type that claims it cannot be nil.

When a value genuinely may be absent, you say so with a trailing `?`:

```lily
int? maybe = nil          // an int, or nil
maybe = 42                // fine
```

`T?` parallels the fallible `T!` (Section 14): `?` is for absence, `!` is for failure. Both are
postfix on a type, and the `?` suffix never collides with the `??` operator.

A `T?` cannot be used as a plain `T` until the nil case is handled, three ways, smallest first:

- **`??`** supplies a fallback: `maybe ?? 0` is the int, or `0` if it was nil.
- **`?.`** navigates safely: `user?.name` is `nil` when `user` is nil, instead of faulting.
- **`match`** handles both cases explicitly, with a `case nil:` and a `case value:`.

```lily
int count = maybe ?? 0                 // never nil from here on
string? city = user?.address?.city     // nil if any link in the chain is nil
```

Because absence lives in the type, a function that returns "maybe a value" returns `T?`, and the
caller cannot forget the nil case. `T?` is the built-in optional enum (Section 7.7) with this sugar
layered on top.

### 2.9 Composite Literals: Arrays, Dicts, Tuples

Arrays are the ordered, homogeneous collection from Section 1.4: `[1, 2, 3]`, indexed `arr[i]`.

A **dict** is a key-value map. The literal uses braces with `key: value` pairs, and the type mirrors
the literal:

```lily
{string: int} ages = {"ana": 30, "ben": 25}
var score = ages["ana"]                // 30
ages["cleo"] = 41
var empty = {:}                        // the empty dict; bare {} is an empty block
```

`{:}` spells the empty dict so it is never confused with an empty brace block. Indexing a missing key
is a fault; the safe lookup form returns `int?` (Section 2.8) instead, for when absence is expected.

A **tuple** is a fixed-size, ordered group of values of possibly different types. The literal and the
type are both parenthesized comma lists:

```lily
(int, string, double) row = (1, "ana", 30.0)
var who = row.1                        // "ana", fields are accessed by position
var (id, name, _) = row                // destructuring; _ discards a field
```

A one-element tuple is written `(x,)` with a trailing comma, so it is not read as a parenthesized
expression `(x)`. Tuples are the lightweight way to return several values from a function without
declaring a class for them.

### 2.10 Conversions

Widening from `int` to `double` is implicit (Section 2.4). Every other conversion is explicit, an
ordinary method call, so a lossy or fallible change of type is always visible where it happens.
`int x = some_double` is a type error; you write `int x = some_double.to_int()`.

| Conversion | Method | Result | Notes |
|------------|--------|--------|-------|
| `double` to `int` | `.to_int()` | `int` | truncates toward zero; a value outside `int`'s range is an overflow fault (E032, Section 2.7) |
| `int` to `double` | `.to_double()` | `double` | already implicit; the method is for when you want it spelled out |
| number to `string` | `.to_string()` | `string` | always safe |
| `bool` to `string` | `.to_string()` | `string` | `"true"` or `"false"` |
| `string` to `int` | `.to_int()` | `int!` | parsing can fail, so the result is fallible (Section 2.8) |
| `string` to `double` | `.to_double()` | `double!` | likewise fallible |

A parse returns the fallible type rather than trapping, because bad input is a recoverable error,
not a bug, so it is handled the same way as any other error (Section 14):

```lily
int port = read_config().to_int() -> default(8080)
```

There is no implicit conversion between `int` and `bool` in either direction: a condition must be a
`bool` and a count must be an `int`. Keeping them apart removes the `if (x)` ambiguity C inherits.

## 3. Variables and Declarations

### 3.1 Mutable Variables

```lily
int age = 25
double ratio = 3.14
string name = "Lily"
bool active = true
var x = 42
```

Type annotations are enforced at runtime (interpreted) and compile time (AOT).
Assigning the wrong type is a Firefly error.

### 3.2 Immutable Variables

Variables declared with `let` are immutable. They cannot be reassigned after declaration.
`let` also enables ownership tracking (see Section 9).

```lily
let int max_speed = 200
let string label = "hello"
let var data = [1, 2, 3]
```

Attempting to reassign a `let` variable is a Firefly error.

### 3.3 Constants

A `const` is an immutable binding whose value is fixed at compile time. It must be
initialized at its declaration with a constant expression, and it can never be reassigned.
Where the value is foldable, the compiler inlines it.

```lily
const double PI = 3.14159265358979
const int MAX_CONNECTIONS = 1024
```

ALL_CAPS is the convention for constants, not a requirement. `const pi = 3.14159` is equally
valid; the capitals are a signal to human readers, nothing more.

`const` differs from `let`. A `let` binding is immutable but its value may be computed at
runtime, and it participates in ownership tracking (Section 9). A `const` is a value known
ahead of time, with no ownership semantics. If you need "immutable, but computed when the
program runs," use `let`. If you need "a fixed number or string baked in," use `const`.

### 3.4 final (Write-Once)

`final` is a write-once binding. It may be assigned exactly once. That assignment can happen
at the declaration, or later, anywhere in scope. Until it is assigned, reading it is a
Firefly error. After its single assignment it is immutable, behaving exactly like a `let`
from that point on.

`final` infers its type the same way `var` does, from the assigned value.

```lily
final greeting = "hello"     // assigned at declaration, now immutable

final result                 // declared without a value
if ok:
    result = compute()       // assigned here on this path
else:
    result = fallback()      // or here on the other - still one assignment at runtime
print(result)
result = "no"                // Firefly error: final already assigned
```

`final` exists mostly as a kindness to people arriving from other languages. It lets you say
"I will set this once, then leave it alone" without deciding up front whether you want `let`'s
ownership behavior. It is the gentle on-ramp; `let` is the destination.

### 3.5 Nil

`nil` is the null value. Typed variables reject `nil` by default.

```lily
var x = nil           // ok, inferred as nil-typed
int y = nil           // Firefly error: cannot assign nil to int
```

Optional types: `int? y = nil` is valid (Section 2.8); a plain `int` can never be nil.

### 3.6 Scope

A variable is visible from its declaration to the end of the block that encloses it, and no further.
A block is any indentation- or brace-delimited body: a function body, an `if` or `else` arm, a
`while`, `do`, or `for` body, a `switch` or `match` case, or a bare nested block. When the block
ends the variable leaves scope, and in `@manual` mode that exit is exactly when its destructor runs
(Section 8.2).

Scopes nest. An inner block sees the variables of the blocks around it, and a name declared inside a
block shadows an outer variable of the same name for the rest of that block. The C-style for loop's
counter is just this rule applied to the loop header: scoped to the loop, invisible after it
(Section 6.4).

---

## 4. Pointers

Lily gives you a named pointer to a memory address without C's sigil soup. The target variable
stays clean (you never write `&age`), and the pointer is an ordinary named variable. Three pieces,
each with one job: the type `ptr T`, the address-of operator `addr`, and the dereference operator
`*`.

### 4.1 Declaring and Binding

A pointer's type is `ptr T`, read left to right as "pointer to T". You bind it to a target with
`addr`, the address-of operator. There is no `&`; the target is named plainly.

```lily
int age = 25
ptr int p = addr age        // p is a pointer to int, aimed at age's address
```

`addr` is a word, not a sigil, and it is the one place address-of happens. Making it explicit is
deliberate: "the address of x" and "the value of x" are different things, and naming the operation
is what keeps `p = ...` from ever being ambiguous (Section 4.3).

### 4.2 Reading, Dereferencing, and Writing Through

The bare name is the address. `*p` is the dereference: the value at that address, usable for both
reading and writing.

```lily
sout << p                   // the address itself, e.g. 0x7ffee3bf8a8c
sout << *p                  // 25, the value at that address

*p = 30                     // write through the pointer
sout << age                 // 30, age was changed via p
```

`*` is prefix-dereference here and infix-multiplication elsewhere, disambiguated by position the
same way `-` is negation or subtraction. In prefix position against a pointer it dereferences;
between two values it multiplies. That is the only ambiguity `*` carries, where C overloaded it
three ways.

### 4.3 Rebinding, Copying, and Pointers to Pointers

Because `addr` is explicit, every assignment has exactly one meaning.

```lily
int other = 99
p = addr other              // rebind: p now aims at other
sout << *p                  // 99

ptr int q = p               // copy: q holds the same address as p
ptr ptr int pp = addr p     // pointer to a pointer: pp aims at p itself
```

`p = addr other` rebinds the pointer, `*p = v` writes through it, `q = p` copies the address, and
`q = addr p` points one level deeper. None can be mistaken for another, which was the ambiguity
that sank the earlier implicit-binding design. The type checker rejects crossing them (assigning a
`ptr int` where a `ptr ptr int` is expected, and so on).

### 4.4 Nil and Safety

A pointer may be `nil`, meaning it aims at nothing.

```lily
p = nil
sout << *p                  // Firefly E083: dereference of nil pointer
```

In safe and GC modes, dereferencing a nil pointer traps with E083 rather than crashing. Under
`@unsafe`, the check is dropped and the dereference is on you.

### 4.5 Pointer Arithmetic

A pointer moves in units of `sizeof(T)`. This is most useful over arrays and raw buffers.

```lily
var arr = [10, 20, 30, 40, 50]
ptr int cursor = addr arr[0]

cursor++                    // advances by sizeof(int) bytes
sout << *cursor             // 20

cursor += 2
sout << *cursor             // 40
```

Arithmetic that walks off the end of a known allocation is caught in safe mode and is your
responsibility under `@unsafe`.

### 4.6 Pointers from Allocation

`mem_alloc` (Section 8.2) returns a pointer directly, so manual buffers use the same `ptr T` type.

```lily
@manual
@unsafe
ptr int buf = mem_alloc(sizeof(int) * 16)
*buf = 7
mem_free(buf)               // buf is dangling afterward; do not dereference it
```

### 4.7 Pointers and Memory Modes

Pointers are available in all memory modes. In GC mode, the GC knows a pointer's target and will
not collect it while a live pointer holds it. In manual mode, the pointer's lifetime is yours. In
hybrid mode, the rules follow whichever mode was active where the target was allocated.

### 4.8 Raw Pointers

`ptr raw` is an untyped pointer that bypasses Lily's pointer safety. It can hold an arbitrary
address, including a literal one for memory-mapped I/O, and it requires `@unsafe` (Section 10).

```lily
@unsafe
ptr raw reg = 0xFF00        // a raw pointer to a fixed address
```

Raw pointers are not tracked by the GC and are not bounds- or nil-checked. They exist for the
lowest-level work, and nothing about them is guarded; that is the point.

---

## 5. Functions

### 5.1 Syntax

Return type first, then `func`, then name and parameters. Method modifiers come before the return
type in the fixed order `static? override? final?`, so `override final void func id()` is valid.
`static` and `override` are mutually exclusive, since a static method is not dispatched and nothing
overrides it; `override final` is valid and means "override this parent method, then forbid any
further override below it." `open` and `sealed` attach to a class, not a method (Section 7.4).

```lily
void func greet():
    print("Hello, Lily!")

int func add(int a, int b):
    return a + b

string func name_of(int id):
    return lookup(id)

double func average(int a, int b):
    return (a + b) / 2.0
```

With braces (GC mode allows either, manual mode requires braces):

```lily
int func add(int a, int b) {
    return a + b;
}
```

### 5.2 No Function Prototypes

Lily does not require function prototypes. MossVM and KieruVM both perform a two-pass init:
all `func` declarations in the current file are registered before any code executes.
Functions are accessible regardless of their position in the file.

```lily
void func main():
    greet()           // works fine, even though greet is defined below

void func greet():
    print("Hello!")
```

Cross-file declarations are handled via `.lilyh` headers (see Section 12).

### 5.3 Parameters

Parameters use the same type-first syntax as variable declarations.

```lily
void func log(string message, int level):
    print("[{level}] {message}")
```

Untyped parameters are valid. Type is inferred at call time.

```lily
void func print_it(var value):
    print(value)
```

### 5.4 Return Types

`void` for functions that return nothing. Any type for functions that return a value.
The return type is enforced: returning the wrong type is a Firefly error.

### 5.5 First-Class Functions

Functions are values. They can be stored in variables, passed as arguments, and returned
from other functions.

```lily
var action = greet
action()

void func run(var callback):
    callback()

run(greet)
```

**Capture.** A function that refers to a variable from an enclosing scope captures it, by reference:
the closure sees later changes to that variable, not a frozen copy. In GC mode the collector keeps a
captured binding alive for as long as the closure is reachable. A captured `var` is shared mutably,
so the closure and the surrounding code see each other's writes; a captured `let` is captured as an
immutable owned reference, readable but not movable out from under the closure. In `@manual` mode a
closure may not outlive the scope of anything it captures, and under `@Strict` a captured `let` is
borrowed for the closure's lifetime; Firefly checks both, the same way it checks any other borrow.

### 5.6 Default Parameters

A parameter may declare a default value with `=`. Parameters with defaults must come after all
required parameters (trailing only).

```lily
void func log(string message, int level = 1):
    print("[{level}] {message}")

log("starting")        // level = 1
log("disk full", 3)    // level = 3
```

**Defaults are evaluated at call time, not definition time.** Each call that omits an argument
re-evaluates that parameter's default expression fresh. This is deliberate. Definition-time
evaluation is the source of one of the most common bugs in other languages, where a mutable
default (an empty array, say) is created once and silently shared across every call. Lily does
not do that: a default of `[]` gives every call its own new array.

Because defaults are evaluated at call time, a default expression may reference any parameter
to its left, which is already bound:

```lily
void func slice(string text, int start = 0, int end = text.length):
    ...
```

A default may not reference a parameter to its right, or itself (not yet bound); doing so is a
Firefly error. The default's type must satisfy the parameter's annotation, checked at compile
time where the type is known, otherwise at runtime.

One thing to keep in mind: because the default re-runs every call, do not put something in a
default expecting it to be computed once. If you want a single shared value, bind it to a `let`
or `const` outside the function and reference that.

### 5.7 Variadic Functions

A function may accept a variable number of trailing arguments by declaring a variadic parameter
with `...` after its element type. Inside the function the parameter is an ordinary array of
that element type.

```lily
int func sum(int... nums):        // homogeneous: every arg must be int
    var total = 0
    for n in nums:
        total += n
    return total

sum(1, 2, 3)        // nums = [1, 2, 3]
sum()               // nums = []

void func log_all(string tag, var... values):   // heterogeneous: any types
    for v in values:
        print("{tag}: {v}")
```

Rules:

- The variadic parameter must be last, and a function may have at most one.
- `int... nums` is homogeneous: each argument is checked against `int`. `var... values` is
  heterogeneous: each argument keeps its own type as a dynamic value.
- A variadic may follow required and defaulted parameters. Positional arguments fill
  left-to-right; every non-variadic parameter is satisfied first (using its default if it has
  one), and the variadic captures whatever remains. So in
  `void func f(int a, int b = 1, int... rest)`, the call `f(10, 20, 30)` gives `a = 10`,
  `b = 20`, `rest = [30]`: `b` greedily takes the first trailing argument before `rest` begins.

**The `...` pack operator.** `...` is Lily's one operator for variadic packing, and it works in
two dual positions:

- In a parameter declaration, `T... name` *collects* trailing arguments into an array.
- At a call site, or inside an array literal, `...expr` *expands* an array back into individual elements.

```lily
var xs = [1, 2, 3]
var copy   = [...xs]        // spread into a literal: a fresh [1, 2, 3]
var joined = [0, ...xs, 4]  // -> [0, 1, 2, 3, 4]
sum(...xs)                  // spread into a call: sum(1, 2, 3)
sum(10, ...xs, 20)          // -> sum(10, 1, 2, 3, 20)
```

This keeps `..` and `..=` meaning exactly one thing (ranges) and `...` meaning exactly one thing
(variadic pack and unpack). To preserve that clean split, **ranges always require both bounds**:
there is no `..hi` or `lo..` open-ended range. That guarantees a leading `...` is always a spread
and never an ambiguous half-range. If open-ended ranges are ever wanted, they will get their own
spelling rather than overloading `..`.

Calling C variadic functions across the FFI (`printf` and friends) is a separate and more
dangerous problem, handled under Section 18.3, not here.

---

## 6. Control Flow

Lily's control flow is C-style in structure and Lily-clean in spelling. Both indentation (the GC
default) and braces (always accepted, required in `@manual`) work for every construct; examples use
indentation unless braces clarify something.

### 6.1 If / Else If / Else

```lily
if x > 10:
    print("big")
else if x > 0:
    print("small")
else:
    print("zero or negative")
```

Brace style:

```lily
if (x > 10) {
    print("big");
} else if (x > 0) {
    print("small");
} else {
    print("zero or negative");
}
```

Lily uses `else if`, the C-family spelling, rather than a separate `elif` keyword: `else` and `if`
already exist, so the combination needs nothing new.

### 6.2 While

Tests before each iteration; the body may run zero times.

```lily
while x < 10:
    x = x + 1
```

### 6.3 Do-While

Runs the body once, then repeats while the condition holds. The test is at the bottom, so the body
always executes at least once.

```lily
do:
    x = x + 1
while x < 10

// brace style
do {
    x = x + 1;
} while (x < 10);
```

In indented form the trailing condition is `while <cond>` with no colon and no body. That absent
colon is the disambiguator: `while cond` (no colon) closes a `do`, whereas `while cond:` (with a
colon, opening a block) is a fresh loop. The two never collide, even at the same indentation.

### 6.4 For

Lily has two for loops. The C-style counting loop separates its header clauses with commas, not
semicolons, and declares its counter in the header like any other variable:

```lily
for(var i = 0, i < arr.length, i++):
    print(arr[i])
```

The counter is scoped to the loop: `i` is not visible after it ends (the C++ rule, not C's older
leak into the enclosing scope). The comma separators are deliberate, for consistency with argument
and collection syntax; they are not C's semicolons, and that difference is intended.

The range-based loop iterates a collection or a range:

```lily
for item in arr:
    print(item)

for i in 0..10:       // exclusive: 0 to 9
    print(i)

for i in 0..=10:      // inclusive: 0 to 10
    print(i)
```

### 6.5 Break and Continue

In a loop, `break` exits the loop and `continue` skips to the next iteration.

```lily
for(var i = 0, i < 100, i++):
    if i == 5:
        break
    if i % 2 == 0:
        continue
    print(i)
```

Inside a `switch`, `continue` has a second, case-local meaning (fallthrough); see 6.6.

### 6.6 Switch / Case

`switch` dispatches on the value of an expression. Cases do not fall through by default, which is
the sane default: a case runs its body and the switch ends, with no `break` required. This removes
C's most notorious footgun, the accidental fallthrough.

```lily
switch status:
    case 200, 201, 204:          // a case may list several values
        println("success")
    case 301, 302:
        println("redirect")
    case 404:
        println("not found")
        continue                 // explicit fallthrough into the next case
    default:
        log(status)
```

Three rules:

- **No implicit fallthrough.** A case ends when its body finishes.
- **`continue` falls through** to the next case, on purpose, when you want it. Inside a `case`,
  `continue` means fallthrough, which is its case-local meaning, distinct from its loop meaning.
- **`break` is optional.** You never need it, since cases do not fall through, but you may write it
  to end a case early or simply because C and C++ habits run deep. It does nothing that running off
  the end of a case would not.

Several values share a body with a comma list (`case 301, 302:`), so stacking empty labels is never
needed. `switch` compares by value and suits ints, strings, bools, and enum values. For structural
matching with binding and destructuring, use `match` (6.7).

### 6.7 Match

`match` is the structural cousin of `switch`. Where `switch` branches on a value, `match`
pattern-matches on shape: enum variants, their associated data, and types, binding parts of the
matched value as it goes. When the subject is a fallible `T!` (Section 14), `match` is its explicit
value form: one case for success, one for the error. Enum variants and their patterns are defined
in Section 7.7, and a `match` over an enum is checked for exhaustiveness.

```lily
match result:
    case Ok(v):
        print("got {v}")
    case Err(e):
        print("error: {e}")
```

A `case _:` matches anything not handled above. It is the wildcard that satisfies exhaustiveness
when you would rather not spell out every variant, the same `_` that discards a field in tuple
destructuring (Section 2.9).

---

## 7. Classes and Enums

Lily uses C++ style classes adapted to Lily syntax, plus enums (Section 7.7) for sum types and ADTs.

### 7.1 Declaration

```lily
class Car:
    public:
        string brand
        int year

        void func drive():
            sout << "The " << brand << " is driving!"

    private:
        double fuel_level

        void func refuel(double amount):
            fuel_level += amount
```

### 7.2 Instantiation

```lily
var my_car = Car()
my_car.brand = "Toyota"
my_car.year = 2024
my_car.drive()
```

### 7.3 Construction

A class is constructed by an `init` method, called implicitly when the class is instantiated.
`init` is optional: a class without one is default-constructed and you assign its public fields
directly (Section 7.2). When you need construction logic, `init` provides it, and its parameters
use the same default and variadic rules as any function (Sections 5.6 and 5.7), so a single `init`
covers what other languages reach for overloaded constructors to do.

`self` refers to the instance. Field access is bare when unambiguous; use `self.field` when a
parameter shares the field's name.

```lily
class Vehicle:
    public:
        string brand
        int year

        void func init(string brand, int year = 2025):
            self.brand = brand
            self.year = year

var my_vehicle = Vehicle("Toyota")     // year defaults to 2025
var older       = Vehicle("Mazda", 2008)
```

For alternative ways to build a value, use named static factories instead of overloading `init`.
A factory says what it does, where a second `init` could not:

```lily
class Point:
    public:
        double x
        double y

        void func init(double x, double y):
            self.x = x
            self.y = y

        static Point func polar(double r, double theta):
            return Point(r * math.cos(theta), r * math.sin(theta))

var p = Point.polar(1.0, 1.5708)
```

Construction that can fail should not leave a half-built object behind. Express it as a factory
that routes failure through the `->` operator (Section 14.3), so the caller decides:

```lily
var cfg = Config.from_file("settings.toml") -> default(Config.empty())
```

### 7.4 Inheritance and Interfaces

A class may extend at most one parent class and implement any number of interfaces.

```lily
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
            println("{name}: woof")
```

Inheritance and overriding are open by default: you extend `Animal` and override `speak` without
the base author marking anything first. The `override` keyword is mandatory wherever a method
replaces a parent or interface method, and the compiler checks it both directions. `override` with
no matching parent method is an error (a mistyped signature), and a method that silently shadows a
parent method without `override` is also an error. That one rule catches the typo class of bug
with certainty, and it is the only annotation the model asks of you.

To prevent extension or overriding, opt in explicitly. `sealed` on a class stops it being
extended; `final` on a method stops it being overridden.

```lily
sealed class Currency:          // cannot be extended
    ...

class Account:
    public:
        final string func id():   // cannot be overridden
            return self.account_id
```

#### Interfaces

An interface declares a contract and may carry default implementations, so it ships behavior and
not just signatures. Implementation is nominal: a class states which interfaces it implements, so
every implementer is discoverable and the compiler reports the moment one breaks.

```lily
interface Drawable:
    void func draw()                  // required, no body

    void func draw_twice():           // default implementation
        self.draw()
        self.draw()

class Circle extends Shape implements Drawable:
    public:
        override void func draw():
            println("circle")
```

A class implements many interfaces but extends one parent. If two implemented interfaces supply
conflicting default methods, the class must override the method to resolve the ambiguity. There is
no multiple inheritance of classes: interfaces provide the multiple-capability benefit without the
diamond.

#### Strict mode

By default Lily is open, and relies on mandatory `override` plus explicit `sealed`/`final` for
control. Under `@Strict` (Section 10) the defaults flip to the Effective-Java discipline: classes
become final by default and must be marked `open` to be extended. `override` stays mandatory in
both modes; the only thing `@Strict` changes is the default direction of the lock.

### 7.5 Operator Overloading

Operator overloading in Lily is implementing a built-in interface. The set of overloadable
operators is fixed and closed, each backed by a standard interface with a named method. You cannot
invent new operators, and you cannot overload assignment or identity. An implementation is expected
to respect the operator's ordinary meaning: `+` should add, not surprise the next reader.

```lily
class Vec2 implements Add:
    public:
        double x
        double y

        void func init(double x, double y):
            self.x = x
            self.y = y

        override Vec2 func add(Vec2 other):      // backs the + operator
            return Vec2(self.x + other.x, self.y + other.y)

var total = Vec2(1.0, 2.0) + Vec2(3.0, 4.0)      // calls add, gives Vec2(4.0, 6.0)
```

The overloadable operators and the interface that backs each:

| Operators | Interface (method) |
|-----------|--------------------|
| `+` `-` `*` `/` `%` | `Add`, `Sub`, `Mul`, `Div`, `Mod` (`add`, `sub`, `mul`, `div`, `mod`) |
| `**` | `Pow` (`pow`) |
| unary `-` | `Negate` (`negate`) |
| `==` `!=` | `Equals` (`equals`) |
| `<` `>` `<=` `>=` | `Compare` (`compare`, returning an ordering) |
| `[]` | `Index` (`get`, `set`) |
| `<<` `>>` | `Stream` (`insert`, `extract`) |

`<<` and `>>` sit in this table, which is exactly what makes `sout << value` work and what a custom
type implements to become streamable (Section 13.2). Because the set is closed and each entry maps
to one named method, an overload can never quietly reassign an operator to an unrelated job, which
is the trap unrestricted overloading let C++ fall into.

### 7.6 Access Control

`public:`, `protected:`, and `private:` are block-level access specifiers, C++ style.

- `public:` is visible everywhere.
- `protected:` is visible to the declaring class and its subclasses, but not from outside.
- `private:` is visible only within the declaring class.

Default access is `private` when not specified. `protected` exists because Lily has classical
inheritance (Section 7.4): a subclass that could see nothing of its parent but the public surface
would be inheritance in name only.

---

### 7.7 Enums

An enum is a type with a fixed set of named variants. Lily's enum is one construct covering both the
plain C-style enum (named constants) and the full algebraic data type (variants that carry data),
the way Rust and Swift unify them. It replaces hand-rolled tagged unions and the class hierarchy you
would otherwise reach for, with the compiler tracking which variant is active.

**Plain variants.** The simplest enum is a set of names. Access is scoped through the type, so the
names never leak into the surrounding namespace, and an enum value never implicitly becomes an int
(the C++ `enum class` lesson):

```lily
enum Color:
    Red
    Green
    Blue

var c = Color.Green
```

**Variants with data.** A variant may carry fields, and different variants may carry completely
different data:

```lily
enum Shape:
    Circle(double radius)
    Rect(double width, double height)
    Empty                              // a bare variant is fine alongside data-carrying ones

var s = Shape.Rect(3.0, 4.0)
```

The data inside a variant is reached only by matching, so you can never read a `Circle`'s radius off
a value that is actually a `Rect`. `match` (Section 6.7) destructures and binds it, and the match
must be exhaustive: Firefly rejects one that forgets a variant (E017), so you handle every variant
or add a catch-all. That enforcement is the safety that makes enums worth having.

```lily
double func area(Shape s):
    match s:
        case Circle(r):
            return 3.14159 * r * r
        case Rect(w, h):
            return w * h
        case Empty:
            return 0.0
```

**Backing values.** For interop and serialization, plain variants may be given explicit values of a
single primitive type, the way you pin HTTP status codes or wire constants:

```lily
enum Status:
    Ok       = 200
    NotFound = 404
    Teapot   = 418
```

The mapping is explicit in both directions: you convert with named methods, never by silently
treating the enum as its backing type.

**Methods and interfaces.** An enum may carry methods and implement interfaces, exactly like a class
(Sections 7.4, 7.5), so behavior lives with the type:

```lily
enum Direction:
    North
    East
    South
    West

    Direction func opposite():
        match self:
            case North: return Direction.South
            case East:  return Direction.West
            case South: return Direction.North
            case West:  return Direction.East
```

**Built-in enums.** Two enums are built in and underlie syntax you have already seen. `T?`
(Section 2.8) is the optional, "a `T` or `nil`". `T!` (Section 14) is the fallible result, "a `T` or
an error". Both are ordinary enums with a little sugar: `match` works on them directly, which is why
the error chapter's `Ok(v)` and `Err(e)` cases are exactly enum-variant patterns.

---

## 8. Memory Management

Lily offers three memory management modes. Modes can be mixed in a single program.
The default is GC mode.

### 8.1 GC Mode (Default)

A tracing garbage collector handles all allocation and deallocation (the collector's internals are an implementation detail, not yet locked). You write code.
The GC cleans up. No annotations required. Python-style indentation is sufficient.

```lily
int x = 42
string name = "Lily"
var data = [1, 2, 3, 4, 5]
// GC handles cleanup when these go out of scope
```

### 8.2 Manual Mode (RAII)

Declared with `@manual`. Braces and semicolons are required in manual blocks. This applies to
executable blocks: function and method bodies, and the bodies of loops and conditionals. A class is
declared the same way in either memory mode (Section 7), with its `public` and `private` sections
and field declarations unchanged; under `@manual` only its method bodies take braces.

RAII (Resource Acquisition Is Initialization) is the default ideology in manual mode. Resources are
tied to scope. A class's destructor is a method named `deinit`, the symmetric partner to `init`; it
runs automatically when the scope exits, even when the exit is an early return or an error unwind,
and is where a `@manual` class releases what it owns. No boilerplate `free()` or `close()` calls are
needed, the scope boundary handles it.

```lily
@manual
@unsafe                           // reinterpreting a raw allocation as a typed pointer
void func process_data() {
    ptr int buf = mem_alloc(sizeof(int));   // bind the allocation to a typed pointer
    *buf = 42;                              // typed write through the pointer (Section 4)
    // buf is freed automatically when this scope exits
}
```

Explicit control is also available:

```lily
@manual
@unsafe
void func explicit_control() {
    ptr int buf = mem_alloc(sizeof(int) * 256);
    // ... work ...
    mem_free(buf);    // manual free before scope exit
}
```

`@manual` governs *lifetime*: you decide when memory is released, and RAII releases it at scope
exit. It does not by itself switch off safety. The low-level primitives that touch raw memory
directly also require `@unsafe` (Section 10), because they can violate memory safety. The table
marks which tier each needs.

| Function | Requires | Description |
|----------|----------|-------------|
| `mem_alloc(size)` | `@manual` | Allocate `size` bytes |
| `mem_free(ptr)` | `@manual` | Free allocated memory |
| `mem_read(ptr, offset, type)` | `@unsafe` | Read value at offset (unchecked) |
| `mem_write(ptr, offset, type, value)` | `@unsafe` | Write value at offset (unchecked) |
| `ptr_add(ptr, offset)` | `@unsafe` | Pointer arithmetic |
| `sizeof(type)` | safe | Size of type in bytes |

The normal way to use allocated memory is the typed pointer: bind the allocation to a `ptr T` and
read or write it with `*p` and `p[i]` (Section 4). The `mem_read` / `mem_write` primitives are the
untyped, byte-level alternative, for a `ptr raw` buffer where you are packing mixed data at explicit
offsets; they take the type as an argument because the pointer itself carries none.

`sizeof(type)` is a compile-time constant, not a runtime call. It takes a type rather than a value,
and the compiler folds it to an integer literal for that type's native size in bytes: `sizeof(int)`
is `8`, `sizeof(double)` is `8`, `sizeof(ptr T)` is the pointer width. It is defined for the types
whose size is fixed, the primitives, pointers, and `extern struct` (Section 18.4). In the IR it is
always a constant, never an operation, which is how it can size an allocation at no runtime cost.

**Destruction order.** RAII objects are destroyed in the reverse of their construction order, last
constructed is first destroyed, the deterministic LIFO rule C++ and Rust both use. Because you build
dependencies before the things that use them, reverse order tears users down before their
dependencies, which is what you want. A scope's locals and a class's fields both follow it, so
acquiring locks in a consistent order releases them in the safe reverse order for free, the standard
defense against the two-lock deadlock. Where a destructor reaches for an object the LIFO order has
already destroyed, Firefly catches the hazard statically (a use-after-free in a destructor, E081) and
points at it instead of leaving it to crash. That is the protection: an order you can predict, plus a
compiler that flags the case where the predictable order is still wrong.

### 8.3 Hybrid Mode

`@manual` and `@gc` annotations switch modes at the function or block level. The rest
of the program unaffected.

```lily
// Default GC - no annotation needed
void func normal_work():
    var data = [1, 2, 3]
    print(data)

// Manual for timing-critical section
@manual
void func hot_path() {
    var pool = mem_alloc(4096);
    // critical loop
}

// GC section inside a predominantly manual program
@gc
void func background_task():
    var temp = [1, 2, 3]
    print(temp)
```

### 8.4 Memory Safety Detection

Firefly detects:
- Double free (E080)
- Use after free (E081)
- Memory leak in `@manual` block (E082)

### 8.5 Emergency Recovery

Lily provides three escape hatches for when a program hits a memory fault or other fatal
condition it was not written to handle. They run on a spectrum from "keep going, save what
you can" to "snapshot everything, then die cleanly." All three are damage-limitation tools,
not correctness mechanisms. None of them can undo undefined behavior; once UB has occurred
the program state is, by definition, already suspect. They exist to salvage work, not to
pretend the fault did not happen.

| Mechanism | Scope | On fault | Survives? | Use when |
|-----------|-------|----------|-----------|----------|
| `-> nullcollect` | Function | Drop the frame's locals, cache critical data in memory, limp on | Yes (barely) | Last-ditch attempt to keep a non-strict program alive |
| `@Catch` | Program | Kill program and all children, free memory immediately | No | Dev/debug, to surface fatals loudly (Section 10) |
| `frogpond.on_fatal(lily.backup_kill)` | Program | Pause, snapshot all state to a file, then kill cleanly | No | Long runs you cannot afford to lose (Section 17.4) |

#### `-> nullcollect`

`-> nullcollect` is the `->` outcome operator (Section 14.3) in function-declaration position.

```lily
void func risky_parse() -> nullcollect:
    // non-strict code that touches raw memory
    ...
```

When a memory fault or UB-class error occurs inside a function marked `-> nullcollect`, Lily
does not crash. Instead it:

1. Throws away every local in the current frame. All locals, temporaries, and inferred types
   are discarded into the void; the frame is treated as unrecoverable.
2. From that point on, copies critical program data (data the program marked critical, plus
   reachable non-local state) into an in-memory salvage cache.
3. Unwinds out of the faulting function and lets the program continue.

This is a very bad practice and is heavily discouraged. It applies only in non-strict code;
it is meaningless under `@Strict`, where the offending operations are rejected before they
run. It cannot guarantee the surviving program is correct, because a memory fault may already
have corrupted state outside the dropped frame. Treat it as a way to barely save a program
from itself, not as error handling. If you find yourself relying on it, the real fix is
`@Strict`, or `let`/safe mode on the offending code. Firefly still reports the underlying
fault (it is never silenced) and emits W011 wherever `-> nullcollect` appears.

---

## 9. Ownership System

`let` enables Rust-style ownership and memory safety. Using normal type keywords (`int`,
`string`, etc.) without `let` opts out of ownership tracking entirely.

This is an explicit choice, not a forced one. Ownership tracking is available when you
want it, invisible when you don't.

### 9.1 let

```lily
let string name = "Lily"      // owned, immutable
let int max = 200
let var data = [1, 2, 3]
```

- Cannot be reassigned after declaration
- Ownership is tracked
- Moving transfers ownership; the original binding becomes invalid
- Borrowing is checked

### 9.2 Opting Out

```lily
int counter = 0          // mutable, no ownership tracking
string label = "hello"   // mutable, no ownership tracking
```

### 9.3 @Strict

`@Strict` forces ownership enforcement. Headed at the top of a file, it treats every variable in
that file as ownership-tracked, regardless of whether `let` is used.

```lily
@Strict

int x = 42         // ownership tracked, even without let
```

At runtime (MossVM/KieruVM), `@Strict` produces Firefly errors when ownership rules
are violated. Under AOT, violations are compile-time errors.

`@Strict` also makes classes final by default, requiring `open` to extend them (Section 7.4).
Ownership enforcement and inheritance lockdown together are Lily's maximum-rigor mode.

`@Strict` is per file. At the top of a file it governs the code written in that file, and it does
not propagate across imports: a non-strict module called from a strict one runs under its own rules,
because ownership checking has to be designed into code, not imposed from outside. A whole project
opts in by enabling strict mode in the build configuration, which is equivalent to heading every
file with it.

---

## 10. Annotations

Annotations appear at the top of a function, block, or program. They are not decorators -
they are directives to the compiler and interpreter about behavior and optimization strategy.

| Annotation | Scope | Effect |
|------------|-------|--------|
| `@manual` | Function / block | Switch to manual memory management (RAII, braces required) |
| `@gc` | Function / block | Switch to GC mode (inside a predominantly manual program) |
| `@unsafe` | Function / block | Disable Lily's safety checks (bounds, null, ownership) for this scope, and unlock the `raw` type, pointer arithmetic, raw memory access, and unchecked/variadic FFI. Orthogonal to `@manual`; the two combine. |
| `@inline` | Program / function | Inline all functions. AOT and MossVM apply it (MossVM pre-processes at load time and caches the inlined form); KieruVM ignores it, as it does no pre-optimization. |
| `@hotpath` | Function / block | Aggressively optimize the critical execution path. AOT uses profile-guided optimization where a profile is available and annotation-directed optimization otherwise; MossVM does a simplified inlining and fast-path pass; KieruVM ignores it (no pre-optimization). |
| `@Strict` | Program / file | Force Rust-style ownership and safety enforcement (per file, or project-wide via build config), and make classes final-by-default (Section 7.4). Interpreted: runtime errors. AOT: compile-time errors. |
| `@Catch` | Program | Catch catastrophic memory leaks and fatal errors mid-run. Kills the program and all child processes, frees memory immediately. For dev/debug use only, not recommended in production. |

**Safety tiers.** Lily separates two axes that are easy to confuse:

- *Lifetime* is who frees memory. The default is GC; `@manual` hands that job to you, via RAII. A `@manual` block is still memory-checked.
- *Enforcement* is whether Lily's safety checks run at all. `@Strict` turns them to the maximum (ownership enforced throughout its scope), the default leaves them on, and `@unsafe` turns them off for a scope and unlocks the raw primitives.

The two are orthogonal. You can allocate manually and stay fully checked (`@manual` alone), reach for raw pointers inside otherwise-GC code (`@unsafe` alone), or do both (`@manual @unsafe`). Nothing dangerous is reachable without naming `@unsafe`, so a grep for `@unsafe` is a complete inventory of where a program sheds its guarantees.

`@Catch` is the program-wide member of a small family of emergency-recovery tools. Its
function-level cousin `-> nullcollect` (Section 8.5) keeps a non-strict program limping after
a memory fault, and its snapshot-to-disk cousin `frogpond.on_fatal(lily.backup_kill)`
(Section 17.4) preserves state before a clean kill. None of the three are error handling;
Section 8.5 carries the honest caveats.

---

## 11. Import System

Lily uses a uniform, prefix-based import syntax. The prefix tells you exactly where a
module comes from. No ambiguity.

```lily
import lily.http          // Lily standard library or installed Lily package
import py.numpy           // Python package via Python FFI
import c.time             // C library via C FFI
```

Selective imports:

```lily
from py.numpy import array, mean
from lily.math import sqrt, pow
from c.string import memcpy
```

Aliases:

```lily
import py.pandas as pd
import lily.http as http
```

### 11.1 Resolution Rules

- `lily.*` resolves to Lily stdlib first, then installed Myst packages
- `py.*` resolves via Python FFI (CPython embedding)
- `c.*` resolves via C FFI (libffi or direct linking)
- No implicit resolution without a prefix. Always use a prefix.

### 11.2 Import by Path

For local files, import by relative or absolute path:

```lily
import "path/to/mymodule"
import "./utils"
```

The interpreter reads the corresponding `.lilyh` header for cross-file declarations.

---

## 12. Header Files (.lilyh)

`.lilyh` files declare the public API of a Lily module. They are read during the init
pass for imported modules, giving the interpreter and compiler full knowledge of exported
functions and types without executing the implementation file.

### 12.1 Syntax

Declarations only, no function bodies.

```lilyh
// math.lilyh
double func sqrt(double x)
double func pow(double base, double exp)
int func abs(int x)
double func floor(double x)
double func ceil(double x)
```

```lilyh
// server.lilyh
void func listen(int port)
void func stop()
string func get_host()
```

### 12.2 Rules

- A declaration must match its `.lily` implementation in signature: the same function name, the
  same return type, the same parameter types in the same order, the same arity, the same variadic
  (`...`) marker, and the same default values where a parameter has one. Parameter names are the one
  exception, they are documentation in a header and need not match. A mismatch is a Firefly error, at
  compile time under AOT and at load time when interpreted. `--emit-header` derives the header from
  source, so a generated header matches by construction; the rule bites only for hand-authored headers
- Programmer authors `.lilyh` files for modules they write
- The AOT compiler reads `.lilyh` to generate C forward declarations automatically
- The compiler can emit a module's `.lilyh` from its `.lily` source by extracting the public
  declarations (an `--emit-header` mode), so authoring a header by hand is optional and reserved
  for when you want to curate or document a public API deliberately
- C FFI bindings expose their headers as `.lilyh` files

---

## 13. I/O

### 13.1 Print Functions

```lily
print("hello")              // print without newline
println("hello")            // print with newline
printserial(data)           // print serial / internal / debug data streams
                            // for visualizing data streams, internal debugging,
                            // hidden data that isn't normally user-visible
```

### 13.2 Stream Operators

`<<` and `>>` are Lily's stream operators, and they mean only that: `<<` inserts into an output
stream, `>>` extracts from an input stream. They are deliberately not bit-shift. Lily learned
from C++ here, where one glyph meaning both insertion and shifting inherits shift's precedence,
which is wrong for streaming and is the source of the classic `out << a & b` misparse. Bit
shifting is done with the `shl` and `shr` methods instead (Section 1.5), which frees `<<` and
`>>` to mean exactly one thing and to carry their own sensible precedence.

`sout`, `sin`, and `serr` are built-in global stream values, always in scope without an import:
`sout` is standard output, `sin` is standard input, `serr` is standard error. They are values of the
built-in stream type whose interface (Section 7.5) backs `<<` and `>>`, which is how any type can be
made streamable to them.

```lily
sout << "The " << brand << " is driving!"     // output to stdout
sin  >> user_input                             // read from stdin
```

The operators are left-associative and each returns its stream, so they chain. They sit at a
low precedence, below arithmetic, comparison, and logical operators, so the surrounding
expression groups the way it reads:

```lily
sout << a + b        // parses as  sout << (a + b)
sout << x == y       // parses as  sout << (x == y)
```

**Formatting is done with interpolation, not stream state.** Lily has no `hex` or `setw` style
manipulators that silently change a stream's mode for everything written after them, which was
the other half of the C++ regret. You format the value where you write it, using string
interpolation (Section 2.6); any width, base, or precision options belong to the interpolation
syntax, not to persistent stream state.

```lily
sout << "total: {total}, rate: {rate}\n"
```

`endl` is available as a plain newline value (`sout << endl`) that also flushes, but it carries
no hidden mode state.

A type becomes streamable by implementing the standard output-stream interface (Section 7.5),
which is why `sout << my_point` works exactly when `Point` opts in. There is no implicit
fallback that prints something surprising for a type that did not implement it; Firefly tells
you the type is not streamable and how to make it so.

`print()` and `sout <<` overlap in purpose; both exist for convenience. Use whichever reads
better for the line you are writing.

### 13.3 printserial

`printserial` writes **plain text**: it dumps the raw representation of whatever it is given,
straight from whatever interface or stream the programmer hands it, with no formatting, framing, or
user-facing niceties. It is a test, log, and debug tool built into the language, not a general
output function. Use it for:
- Visualizing internal data streams
- Debugging data that is normally hidden from the user
- Serial or trace logging pipelines
- Seeing what is flowing through a system without touching stdout

It is deliberately dumb: it does not pretty-print, structure, or interpret. For formatting, use
`print` with interpolation, or `sout`.

Concretely, it differs from `print` in three ways. It bypasses the `Stream` interface and
interpolation, so a type's custom formatting is ignored and you get its raw internal representation.
It writes to standard error, not stdout, so debug output never pollutes a program's real output. And
it does not buffer. `print(x)` asks `x` how it wishes to be shown; `printserial(x)` shows what `x`
actually is.

---

## 14. Error Handling

Lily separates two kinds of failure and keeps them in different channels. Conflating them is what
makes error handling miserable in most languages, so Lily does not.

**Faults** are bugs and broken contracts: dereferencing a nil pointer (E083), integer overflow
(E032), an out-of-bounds index (E020), division by zero (E030), a use-after-free (E081). A fault
means the program did something it was never supposed to do. Faults are not part of a function's
type, they are not meant to be caught and recovered in ordinary control flow, and they raise a
Firefly error that unwinds the program. The only things that catch a fault are the emergency tools
(`@Catch`, `-> nullcollect`, `frogpond.on_fatal`, Section 8.5), and even those are damage control,
not recovery. The rule of thumb: if a failure can happen in correct code, it is not a fault, it is
an error.

**Errors** are expected, recoverable conditions: a file that is not there, a parse that fails, a
network timeout, a withdrawal larger than the balance. An error is a value, and a function's ability
to produce one is written in its type. A function that can fail returns a fallible type, spelled
`T!` ("a T, or an error"):

```lily
int! func parse_int(string s):     // returns an int, or an error
    ...
```

`T!` parallels the optional `T?` ("a T, or nil"): `?` is for absence, `!` is for failure. The `!`
is postfix on a type and never collides with the `not` operator, which is prefix on a value, the
same positional rule that disambiguates `*` and `-`.

The error channel has one underlying concept, the fallible result, and three ways to handle it that
all consume the same `T!`:

- **`->`** (Section 14.3) handles a failure inline: `parse_int(s) -> default(0)`.
- **`try` / `catch`** (Section 14.1) handles it as a block, when you want to inspect and branch.
- **`match`** (Section 6.7) handles it as an explicit value, matching the success and error cases.

`raise` (Section 14.2) is how a function produces an error, and it is legal only inside a function
whose return type is fallible. That is the honesty rule: if a function can fail, its signature says
so, and a failure path can never hide behind a clean-looking type. A function with no `!` in its
return type cannot raise, and calling it needs no error handling. Calling a fallible function, by
contrast, must either handle the error with one of the three forms above or re-raise it with
`-> raise` (which is legal only if the calling function is itself fallible).

An error value is an enum (Section 7.7), so one fallible function can offer several distinct,
inspectable failure modes that `match` tells apart. The two-tier split and the `T!` channel are the
fixed core.

### 14.1 Try / Catch / Finally

```lily
try:
    var result = risky_operation()
    print(result)
catch e:
    print("Error: {e}")
finally:
    print("cleanup")
```

With braces:

```lily
try {
    var result = risky_operation();
} catch (e) {
    print("Error: {e}");
} finally {
    print("cleanup");
}
```

### 14.2 Raise

`raise` produces an error. It is legal only inside a function whose return type is fallible (`T!`),
so a function that can raise always says so in its signature.

```lily
int! func withdraw(int balance, int amount):
    if amount > balance:
        raise InsufficientFunds
    return balance - amount
```

(Division by zero is a fault, not an error: it traps with E030 on its own. You raise errors for
expected conditions, not for bugs.)

### 14.3 The `->` Handler Operator

`->` is the outcome-routing operator. It is postfix: the left side is something that may fail or
fault, the right side is a handler that decides what happens when it does. `try`/`catch` is the
block form for when you want to inspect an error and branch on it; `->` is the inline form for
handling a single failure right where it happens, the way Rust pairs `match` with `.unwrap_or(...)`.

It works in two positions, with the same meaning at different scope:

- On an expression, the handler catches a failure of that one expression.
- On a function declaration, the handler catches any failure in the whole body.

**Everyday handlers** (ordinary, recoverable failures):

```lily
let config = read_file("config.toml") -> default("{}")   // missing file? use an empty config
let n      = parse_int(input) -> retry(3) -> default(0)   // try, retry 3x, then fall back
let data   = fetch(url) -> raise                          // propagate the failure upward
fetch(url) -> warn                                        // log a Firefly warning, continue with nil
```

| Handler | On failure |
|---------|-----------|
| `default(v)` | The expression evaluates to `v`. Makes a fallible expression total. |
| `retry(n)` | Re-run up to `n` times, then propagate if it still fails. |
| `raise` | Re-raise the failure to the caller. The explicit "not handling it here." |
| `warn` | Emit a Firefly warning and continue with `nil`. |
| `<function>` | A user-defined handler that receives the failure descriptor and decides. |

Handlers chain left to right: `parse_int(input) -> retry(3) -> default(0)` runs the parse,
retries three times on failure, and only then falls back to `0`. Each `->` hands its
predecessor's failure to the next handler.

**Memory-fault handler** (best-effort, not recoverable):

```lily
void func risky_parse() -> nullcollect:
    ...
```

`nullcollect` is the one handler that engages memory faults and UB rather than ordinary errors,
and as Section 8.5 spells out, it is salvage, not recovery. The everyday handlers above assume a
sane, inspectable failure; do not point `default(0)` at a segfault and expect a meaningful zero.

`->` is a single token; it never means subtraction followed by greater-than.

### 14.4 Firefly

Firefly is Lily's error diagnosis and guidance subsystem. All runtime and compile-time
errors pass through Firefly. The goal is errors that help, not errors that scold.

Every Firefly message includes:
- Source file, line, and column
- Caret underlining of the exact token
- A plain-English explanation of what went wrong
- "Did you mean?" suggestions using edit distance when relevant
- Type-specific help (lists available methods on the relevant type)
- Call stack traces
- Cross-file analysis (Firefly can trace errors across imported modules)
- Smart suggestions based on context

Error format:

```
-- error[E001]: undefined variable 'nme' -- script.lily:2:9 --
    |
  2 | print(nme)
    |       ^^^
    |
  Firefly: 'nme' is not defined in this scope.
           Did you mean 'name'? (1 character off)

  Call stack:
    0. greet   at script.lily:5
    1. main    at script.lily:10
----------------------------------------------------------------------
```

Verbosity levels:
- `--firefly=full` (default): full explanation, suggestions, call stack
- `--firefly=minimal`: error code, location, one-line message
- `--firefly=off`: raw error output only

### 14.5 Firefly Error Codes

See Appendix for the full error code registry.  
Core categories: Names (E001-E009), Types (E010-E019), Bounds (E020-E029),
Arithmetic (E030-E039), Mutability (E040-E049), Members (E050-E059),
Calls (E060-E069), Modules (E070-E079), Memory (E080-E089), Sandbox (E090-E099),
Operators (E100-E109).

---

## 15. File Structure

| Extension | Purpose |
|-----------|---------|
| `.lily` | Source files |
| `.lilyh` | Header files. Declare public API of a module. |
| `.lilyobj` | Object files produced by the AOT compiler |
| `.lilyknight` | LilyKnight sandbox configuration file |

### 15.1 Import Resolution

Files are not folder-dependent. Import by module name or path:

```lily
import lily.utils           // resolved by Lily's module resolver
import "./utils"            // relative path, interpreter finds utils.lily + utils.lilyh
import "src/server"         // explicit path
```

### 15.2 Multi-file Projects

The interpreter natively supports multi-file Lily projects. When a file is imported:
1. Interpreter reads the `.lilyh` header to register exported declarations
2. Implementation file is loaded on demand
3. Init pass registers all functions before execution

The AOT compiler uses all file types and handles linking via generated C.

---

## 16. Subsystems

| Name | What it does |
|------|-------------|
| **Firefly** | Error diagnosis, guidance, cross-file analysis, smart suggestions. The heart of Lily's developer experience. |
| **MossVM** | Main interpreter. Two-pass init, in-memory caching of optimizations, smart pre-interpretation at load time. LilyKnight available. |
| **KieruVM** | Embedded / resource-limited interpreter. No caching, no LilyKnight, no pre-optimization. Slower than MossVM but far less resource-intensive. For constrained environments. |
| **LilyKnight** | Capability-based sandbox. Deny-all by default. Controls filesystem, network, process execution, FFI, memory limits, device access. MossVM only. |
| **FrogPond** | LilyKnight's runtime API. Request permissions, query sandbox state, configure limits, handle safe shutdowns and error recovery from inside a program. |
| **AOT** | Ahead-of-time compiler. Lowers the typed IR to C, then invokes the system C compiler. Produces native binaries. |
| **IR** | Typed intermediate representation. The AST is lowered to the typed IR, which is the single source of truth consumed by MossVM, KieruVM, and the AOT backend alike. Backends never read the AST directly, so they cannot diverge. |
| **AST** | Abstract syntax tree produced by the parser. Lowered to the typed IR. Foundation for tooling. |
| **Myst** | Package manager. Separate toolchain component. |

---

## 17. LilyKnight Sandbox

LilyKnight is the Lily runtime's permission enforcement layer. It is available under MossVM only;
KieruVM runs without any sandbox, since constrained and embedded targets cannot afford the
enforcement overhead and are assumed to run trusted code.

LilyKnight exists for one job: running code you do not fully trust (plugins, downloaded
scripts, student submissions, third-party Lily packages) without handing it the keys to the
machine. If you are running your own trusted code, you do not need it, and turning it on buys
you nothing but overhead.

### 17.1 Permission Model

Three rules define the model:

1. **Deny by default.** A fresh sandbox grants nothing. Every capability a program needs must
   be granted explicitly, either statically in a `.lilyknight` file or at runtime via FrogPond.
2. **Capabilities are additive and non-transitive.** Holding one capability never implies
   another. `fs.read` on `/data` does not grant `fs.read` on `/etc`, and no filesystem grant
   ever implies a network grant. Filters narrow a capability; they never widen it.
3. **No escalation without explicit permission.** A program cannot grant itself anything the
   static manifest did not pre-authorize. Runtime requests through FrogPond are themselves
   gated by a meta-capability, `cap.grant` (see 17.2). Without `cap.grant`, every
   `frogpond.request(...)` is denied. This is what stops untrusted code from simply asking for
   `fs.write` and getting it.

A capability token, once granted, is unforgeable: LilyKnight hands it to the program at
sandbox init, and program code cannot construct one.

Rules 2 and 3 govern *capabilities*, the powers a program holds. A separate dial, *strictness*
(17.4), governs *resource budgets*, how much CPU, memory, and so on a program may use. Strictness
can let a program borrow extra budget at runtime, but it never grants a capability the manifest
withheld. The two axes do not cross.

### 17.2 Controllable Capabilities

Capabilities are grouped by the resource they gate, not by incidental device names. The
guiding principle: ordinary output (printing, writing a file you were granted) is not a
capability; only genuinely dangerous or privacy-sensitive actions are. That is why there is no
`device.sound` here. Emitting audio to a speaker is ordinary output and lives under normal
I/O. Recording from a microphone, by contrast, is surveillance, and is gated.

**Filesystem (`fs`)**

| Capability | Gates |
|------------|-------|
| `fs.read <paths>` | Reading files and directories within the listed path prefixes |
| `fs.write <paths>` | Writing file contents within the listed path prefixes |
| `fs.create <paths>` | Creating or deleting entries (mutating the tree, distinct from writing contents) |

Symlinks are not followed out of a granted prefix.

**Network (`net`)**

| Capability | Gates |
|------------|-------|
| `net.connect <host:port>` | Outbound connections to the listed hosts and ports |
| `net.listen <port>` | Binding and listening on the listed ports (inbound) |
| `net.dns` | Name resolution |

**Process and concurrency (`proc`, `thread`)**

| Capability | Gates |
|------------|-------|
| `proc.spawn <binaries>` | Launching subprocesses, optionally restricted to an allowlist |
| `proc.signal` | Sending signals to other processes |
| `proc.max <n>` | Hard cap on concurrent child processes (fork-bomb guard) |
| `thread.max <n>` | Hard cap on live threads |

**Foreign code (`ffi`)**

| Capability | Gates |
|------------|-------|
| `ffi.c` | Loading and calling C libraries |
| `ffi.python` | Embedding and calling CPython |

Granting any `ffi.*` capability would, on its own, void the sandbox: foreign code runs as native
machine code outside LilyKnight's in-process enforcement, so a single `import py.os` then
`os.system(...)` could do anything the host process can. LilyKnight does not paper over this with a
warning. When an `ffi.*` grant coexists with any in-process restriction (a narrowed `fs.*`, `net.*`,
or `proc.*`, or a `mem.limit`), LilyKnight escalates enforcement to the operating system before any
foreign code runs: it translates the capability set into an OS-level sandbox policy (seccomp-bpf and
Landlock on Linux, `pledge`/`unveil` on OpenBSD, the platform equivalent elsewhere) and applies it
to the whole process, native code included. The OS then enforces the boundary that LilyKnight, in
process, cannot. If the host platform offers no such mechanism, LilyKnight refuses the combination
at startup rather than pretend to enforce it: a manifest asking for both `ffi.*` and real
containment fails closed. An `ffi.*` grant in an otherwise-permissive sandbox, with no restrictions
to enforce, needs no escalation and runs as before.

**Memory (`mem`)**

| Capability | Gates |
|------------|-------|
| `mem.limit <bytes>` | Maximum heap the program may allocate |
| `mem.raw` | Use of `raw`, `@unsafe`, pointer arithmetic, and raw memory access |

Without `mem.raw`, sandboxed code is confined to safe mode and the unsafe memory features are
rejected before they run. This is the capability that stops untrusted code from corrupting memory
to escape the sandbox in the first place. `@manual` is deliberately not gated here: it changes only
memory lifetime (RAII) and stays fully memory-checked (Section 10), so manual allocation is no more
dangerous to the sandbox than GC mode, and unbounded allocation is bounded by `mem.limit`, not
`mem.raw`. When no `mem.limit` is set, LilyKnight allocates per program need and assumes developer
best practice.

**Compute (`cpu`)**

| Capability | Gates |
|------------|-------|
| `cpu.time <seconds>` | CPU/wall budget. On exceed, LilyKnight fires E096 and stops the program |

**Devices (`device`)**, only the dangerous interactions, never ordinary output

| Capability | Gates |
|------------|-------|
| `device.capture.audio` | Microphone capture |
| `device.capture.video` | Camera capture |
| `device.capture.screen` | Screen capture and recording |
| `device.input` | Reading raw input events (keylogging risk) |
| `device.raw` | Direct access to device files, GPU, and other raw hardware |

Ordinary buffered input is not gated: reading a line from `sin` is normal I/O, the counterpart to
writing to `sout`. `device.input` gates the dangerous forms, raw or unbuffered terminal input that
sees individual keystrokes as they happen (raw or cbreak terminal mode, ncurses raw input), reads
from OS input-event devices (`/dev/input/*` and equivalents), and any API positioned to observe
input the user did not intend for this program. The line is intent: a program reading the input
meant for it needs nothing; a program positioned to watch input more broadly needs `device.input`.

**System and ambient authority (`sys`)**

| Capability | Gates |
|------------|-------|
| `sys.env` | Reading environment variables |
| `sys.info` | Host/OS/user/machine details (fingerprinting and info leak) |
| `sys.clock` | Reading the real wall clock |
| `sys.random` | Access to real OS entropy |

`sys.clock` and `sys.random` are gated because Lily cares about reproducibility. Denying them
lets a sandbox run untrusted code deterministically: time and randomness become virtualized
and seeded, so the same input produces the same run every time.

**Escalation control (`cap`)**

| Capability | Gates |
|------------|-------|
| `cap.grant` | Whether the program may request *new* capabilities at runtime via FrogPond at all |

Without `cap.grant`, the static manifest is the complete and final set of permissions. With
it, runtime requests are still limited to capabilities the manifest marked `requestable`,
never anything outside that set. There is no path by which a program raises its own privilege
beyond what the manifest pre-approved.

### 17.3 Configuration

Static, via a `.lilyknight` file read at startup. Grants are explicit; filters follow the
capability.

```lilyknight
allow fs.read     "/data", "/tmp/lily"
allow fs.write    "/tmp/lily"
allow net.connect "api.example.com:443"
deny  net.listen
allow cpu.time    30s
allow mem.limit   512mb
deny  mem.raw                  # force safe mode
deny  ffi.c
deny  ffi.python
deny  cap.grant                # manifest is final, no runtime escalation
strictness  10                 # 10 = locked default; lower = more runtime resource escalation (17.4)

requestable fs.write "/var/out"  # may be requested at runtime IF cap.grant is allowed
```

Anything not mentioned is denied. `requestable` pre-approves a capability for a later runtime
request without granting it up front; it has no effect unless `cap.grant` is also allowed.

### 17.4 FrogPond (Runtime API)

FrogPond is LilyKnight's runtime face: the API a program uses to interact with its own sandbox
from the inside. It does not let a program exceed its manifest. It lets a program work within
it, query it, and react to failure.

```lily
import lily.frogpond
```

**Querying state**

```lily
frogpond.has("net.connect")               // true/false: do we hold this capability?
frogpond.list()                            // all currently held capabilities
frogpond.mem_used()                        // current heap usage in bytes
frogpond.cpu_used()                        // CPU/wall consumed against cpu.time
```

**Requesting capabilities** (only if `cap.grant` is held)

```lily
frogpond.request("fs.write")               // succeeds only if the manifest marked it
                                           // requestable, otherwise denied with E098
```

**Setting limits** (within the manifest ceiling)

```lily
frogpond.set_mem_limit(512 * 1024 * 1024)  // may lower, never raise above the manifest cap
```

**Fatal handlers**

A program registers what should happen if it hits a fatal or UB-class condition.

```lily
frogpond.on_fatal(lily.shutdown_safe)      // orderly shutdown: run defers, flush, exit
frogpond.on_fatal(lily.backup_kill)        // snapshot everything, then hard-kill
```

`lily.backup_kill` is for long-running work you cannot afford to lose: a five-day research run
that hits UB at hour 100. On a fatal condition it:

1. Pauses the program at the point of failure.
2. Serializes all reachable program state to a file on disk: every live variable binding at
   the fault site, all stored data, accumulated modifications, and progress markers.
3. Terminates the program violently and cleans up all child and orphaned processes, so nothing
   is left running.

Honesty caveat: the snapshot is fully reliable for non-memory fatals (a logic panic, a denied
capability, a limit exceeded). For a memory-corruption fault the snapshot is best-effort,
because the state being saved may itself be the corrupted state. It maximizes what you can
recover; it does not guarantee the recovery is clean. For the in-memory, keep-running cousin,
see `-> nullcollect` in Section 8.5.

**Strictness**

Strictness is a single dial, `strictness 0-10`, set in the manifest and queryable at runtime. It
governs how readily LilyKnight grants *runtime resource escalation*: requests for more CPU time,
more memory, more threads or processes than the manifest baseline. It governs budgets only. It
never loosens capabilities, so a program can never gain `fs.write` or `net.connect` it was not
granted, whatever the strictness, because capabilities stay bound by `cap.grant` and `requestable`
(17.1). Strictness flexes how much resource LilyKnight will float, not what powers a program holds.

- **10 (default, recommended):** maximum strictness. Manifest budgets are final, with no runtime
  resource escalation. This is the behavior assumed everywhere else in this section.
- **Moderate (4-7):** LilyKnight grants reasonable budget bumps on request, in exchange for a
  cleanup obligation. The extra budget is a loan: the program must return to its baseline within a
  window, or LilyKnight reclaims the surplus and fires the relevant resource error (E095 for memory,
  E096 for CPU).
- **Low (1-3):** permissive. Most resource requests are granted with little friction.
- **0:** no strictness. Resource requests are granted freely, effectively unbounded escalation, for
  trusted prototyping only.

On a memory loan, "reclaim" does not mean LilyKnight yanks live memory out from under a running
program, which cannot be done safely. At the deadline it requests a GC cycle; whatever the collector
frees counts toward returning to baseline. If the program is still over baseline after that
collection, it is genuinely holding the memory live, the loan is called, and the program stops with
E095. The loan is "free it or be killed," never a silent rug-pull. In `@manual` mode the allocator
enforces the ceiling directly, so the deadline does not arise.

```lily
frogpond.strictness()                            // query the current level, 0-10
frogpond.request_more("mem.limit", 256 * 1024 * 1024)  // ask for a temporary budget bump;
                                                 // granted per strictness, carries a cleanup deadline
frogpond.release("mem.limit")                    // return borrowed budget early, fulfilling the promise
```

Lowering strictness is not recommended for code you ship. It earns its place in two situations:
sandboxed prototyping, where you want a program to run before its real resource envelope is worked
out, and crash diagnostics, where a low-strictness run lets a program limp all the way to its
failure point and log why and where it died instead of being cut off at the first limit. Treat it
like `@unsafe`: a deliberate, visible loosening, fine in the lab and suspect in production.

### 17.5 Violations

When a sandboxed program attempts a denied operation, LilyKnight:

1. Blocks the operation before it touches the resource.
2. Logs the violation (the capability requested and the source location).
3. Fires a Firefly sandbox error (E090-E099) that names the missing capability and shows how
   to grant it in the manifest.
4. Optionally pauses or kills the program, per the registered FrogPond fatal handler.

### 17.6 Establishing a Sandbox (Host Side)

Sections 17.1 to 17.5 describe life inside a sandbox, the "imposed from outside" case. The other
half is the host: a trusted program (a plugin host, a game engine loading mods, a grader running
student code) that creates a sandbox for guest code and decides its permissions. That is arguably
the most compelling use of the whole system, and it has its own API.

A host builds a capability set from the same vocabulary as the manifest, then runs guest code under
it:

```lily
import lily.sandbox

var caps = sandbox.capabilities()
caps.allow("fs.read", "/mods/coolmod/assets")
caps.allow("mem.limit", 64 * 1024 * 1024)
caps.set_strictness(10)

var guest  = sandbox.create(caps)
var result = guest.run("mods/coolmod/main.lily")   // runs under exactly those capabilities
```

The guest sees `caps` as its complete, deny-all-by-default manifest: it cannot exceed it, and
`cap.grant` and `requestable` behave exactly as in a file manifest. A host may create many guests
with different capability sets in one process, and guests can reach neither each other nor the host
beyond what they were handed. When a guest's capability set bears `ffi.*` alongside restrictions, the
OS-level escalation of 17.2 applies to that guest's execution.

A guest carries its own fatal policy, so a host can isolate a faulting guest without going down with
it:

```lily
guest.on_fatal(sandbox.kill_guest)        // a guest fault kills only the guest; the host runs on
guest.on_fatal(lily.backup_kill)          // or snapshot the guest's state, then kill the guest

var outcome = guest.run("mods/coolmod/main.lily")
if outcome.faulted:
    log("mod {guest.name} crashed: {outcome.fault}")
```

This is the scoped counterpart to the program-wide `frogpond.on_fatal` (17.4). `frogpond.on_fatal`
sets the policy for the current program; `guest.on_fatal` sets it for a guest the current program is
hosting. `sandbox.kill_guest` is the option the program-wide form cannot express: it tears down one
guest's sandbox (its threads, memory, and open resources) and returns control to the host, leaving
the host process alive.

---

## 18. FFI

### 18.1 Python FFI

Lily embeds CPython. Python packages are imported via the `py.` prefix and called directly.
Type marshaling between Lily and Python is automatic for common types.

```lily
import py.numpy as np
import py.pandas as pd

var arr = np.array([1, 2, 3, 4, 5])
print(np.mean(arr))

var df = pd.read_csv("data.csv")
print(df.head())
```

Automatic type conversion:

| Lily | Python |
|------|--------|
| `int` | `int` |
| `double` | `float` |
| `string` | `str` |
| `bool` | `bool` |
| `nil` | `None` |
| `[...]` (array) | `list` |
| `{...}` (dict) | `dict` |
| `(...)` (tuple) | `tuple` |
| class instance | object (attributes mapped) |

A Python object with no Lily equivalent (a numpy `ndarray`, a pandas `DataFrame`) is not converted
element by element; it is held by reference as a Python object handle and operated on through its
own library, crossing the boundary by reference rather than by copy. So `np.array([1,2,3])` yields a
handle to a numpy array, not a Lily array, which is what makes chained numpy calls cheap.

### 18.2 C FFI

C libraries are imported via the `c.` prefix. The C FFI binding layer exposes C functions
to Lily. C header bindings are exposed as `.lilyh` files.

```lily
import c.string
import c.math

var result = c.math.sqrt(144.0)
print(result)   // 12.0
```

Direct FFI call for a symbol with no declaration, gated by `ffi.c` and `@unsafe`:

```lily
@unsafe
var n = ffi_call("c", "write", int, [1, buf, count])
// ffi_call(library, symbol, return_type, [args]); marshaling follows the table in 18.4
```

### 18.3 C Variadic Functions

Calling a C function that uses C's own `...` varargs (`printf`, `snprintf`, `execl`, `ioctl`,
and so on) is fundamentally more dangerous than Lily's variadics, and Lily treats it that way.

The danger is not the mechanism. libffi can make the call through its variadic interface
(`ffi_prep_cif_var`, which takes the number of fixed arguments, the total number of arguments,
and a C type for every argument). The danger is the contract. A C variadic function decides how
to read its arguments from information Lily cannot see: `printf` reads its stack according to a
runtime format string, and C applies default argument promotions (a narrow integer becomes
`int`, a `float` becomes `double`) that the caller must get exactly right or the call corrupts
the stack. A Lily dynamic value carries a Lily tag, not a C type, so there is no safe automatic
mapping. This is the same reason Go's cgo refuses to call variadic C functions at all, and Rust
only allows it through explicit `unsafe` per-call signatures.

Lily's policy, in order of preference:

1. **Wrap, do not call.** The overwhelmingly common need (formatted output) is served by Lily's
   own string interpolation and `format`, not by C's `printf`. The standard library exposes
   safe, fixed-arity wrappers around the C variadic functions that matter, written on the C/Zig
   side where the types are known. This is the default, and it keeps generic-varargs machinery
   out of the core entirely.

2. **Explicit typed call, quarantined.** For the rare case with no wrapper (a driver `ioctl`,
   say), Lily provides an explicit variadic FFI call in which the programmer states the C type
   of every variadic argument by hand, so the ABI is correct. It is gated behind both the
   `ffi.c` capability and an `@unsafe` block, and Firefly marks it loudly. It exists so the
   language is never a dead end, not because you should reach for it.

The exact surface for option 2, the per-argument C-type marshalling helpers and the call form,
is reserved and will be locked together with the rest of the FFI interface (Section 18.4). It is
deliberately not finalized here, because getting the C-to-Lily boundary
right once is worth more than getting it fast.

### 18.4 FFI Design Principle

The C-to-Lily and Lily-to-C interface is the most important decision in the FFI system, because
Lily's standard library is implemented in C (and Zig) and exposed through it. The governing
requirement is that adding a binding is a single declaration: no glue file, no registration step, no
specific edit order across files.

**Bindings are declarations.** A C function becomes callable by declaring its signature once, in a
`.lilyh` header (Section 12), the same header format Lily modules already use. The declaration states
the C function in Lily's own type syntax; there is no separate binding language and no generated
glue:

```lilyh
// libm.lilyh
double sqrt(double x)
double pow(double base, double exp)
```

```lily
import c.math
var r = c.math.sqrt(144.0)             // 12.0
```

This is LuaJIT's "declare the signature, call it directly" model, adapted to Lily's typed header.
The standard library is bound this way: implement the function in C or Zig, declare it in the
module's `.lilyh`, and it is callable. Nothing else, which is exactly what this section demanded.

**Marshaling** is automatic where it is unambiguous and explicit where it is not:

| Lily | C |
|------|---|
| `int` | 64-bit integer (`int64_t`); a narrower C int widens, range-checked coming back |
| `double` | `double` |
| `bool` | `bool` |
| `string` | `const char*`, UTF-8 and NUL-terminated; ownership stated per binding |
| `ptr T` | `T*` |
| `ptr raw` | `void*` |
| `nil` | `NULL` |
| `extern struct` | a C struct, in declared field order |

**Structs across the boundary** use `extern struct`, which fixes field layout to C order with no
reordering or hidden padding, so a Lily value can be passed by pointer to C and back:

```lily
extern struct Timespec:
    int seconds
    int nanos
```

A plain `class` has no guaranteed layout: the compiler may reorder or pad its fields for alignment,
so a class cannot be handed to C by pointer. `extern struct` exists precisely to give up that
freedom. Lily has no general-purpose `struct`; ordinary data types are classes, and `extern struct`
is the FFI-only, C-layout record.

**Linking.** A binding resolves against the default C namespace or a named library. The AOT backend
emits a direct C call from the declaration; the interpreter makes the same call through libffi. One
declaration serves both execution paths.

**The trust boundary.** Everything crossing from C is unverified, so the FFI is gated by the `ffi.c`
capability (Section 17.2), and any binding whose safety Lily cannot guarantee (raw pointers, manual
ownership, variadic C calls, the dynamic `ffi_call`) additionally requires `@unsafe`. Lily's safety
stops at the boundary, and the boundary is marked.

---

## 19. Appendix: Firefly Error Codes

### Errors

| Code | Category | Description |
|------|----------|-------------|
| E001 | Names | Undefined variable |
| E002 | Names | Undefined function |
| E003 | Names | Undefined module |
| E004 | Names | Undefined type |
| E010 | Types | Type mismatch (general) |
| E011 | Types | Parameter type mismatch |
| E012 | Types | Return type mismatch |
| E013 | Types | Assignment type mismatch |
| E016 | Types | Nil assigned to non-optional type |
| E017 | Types | Non-exhaustive match (enum variant unhandled) |
| E020 | Bounds | Array index out of bounds |
| E021 | Bounds | String index out of bounds |
| E025 | Bounds | Dict key not found |
| E030 | Arithmetic | Division by zero |
| E031 | Arithmetic | Modulo by zero |
| E032 | Arithmetic | Integer overflow (default trap; see Section 2.7) |
| E040 | Mutability | Cannot reassign let variable |
| E050 | Members | No such method on type |
| E051 | Members | No such property on type |
| E052 | Members | Value is not callable |
| E060 | Calls | Wrong number of arguments |
| E070 | Modules | Module not found |
| E071 | Modules | Header mismatch (.lilyh does not match .lily) |
| E072 | Modules | Maximum recursion depth exceeded |
| E074 | Modules | Import failed |
| E080 | Memory | Double free detected |
| E081 | Memory | Use after free |
| E082 | Memory | Memory leak in @manual block |
| E083 | Memory | Dereference of nil pointer |
| E085 | Memory | Use after move |
| E090 | Sandbox | Permission denied (filesystem read) |
| E091 | Sandbox | Permission denied (filesystem write/create) |
| E092 | Sandbox | Permission denied (network) |
| E093 | Sandbox | Permission denied (process exec / signal) |
| E094 | Sandbox | Permission denied (FFI / foreign code) |
| E095 | Sandbox | Memory limit exceeded |
| E096 | Sandbox | CPU / time budget exceeded |
| E097 | Sandbox | Permission denied (device capture / raw / input) |
| E098 | Sandbox | Capability escalation denied (no cap.grant, or not requestable) |
| E099 | Sandbox | Thread / process count limit exceeded |
| E100 | Operators | Unsupported operand types for + |
| E101 | Operators | Unsupported operand types for - |
| E103 | Operators | Unsupported operand types for / |
| E105 | Operators | Cannot compare types |

### Warnings

| Code | Description |
|------|-------------|
| W001 | Unused variable |
| W002 | Non-exhaustive switch (no default case) |
| W003 | String concatenation in loop (suggest builder pattern) |
| W004 | Shadowed variable |
| W005 | Missing return in typed function |
| W006 | Unreachable code after return |
| W007 | Comparison always true or always false |
| W008 | Integer division truncation (result may surprise) |
| W009 | Pointer arithmetic in GC mode |
| W010 | @Catch used outside dev/debug context |
| W011 | `-> nullcollect` used (emergency recovery is not error handling) |

---

## Design Status

Every open question from earlier drafts is now resolved and folded into the sections above: the
enum/ADT model (7.7), the FFI boundary (18.4), RAII destruction order (8.2), optional types (2.8),
dict and tuple literals (2.9), `.lilyh` auto-generation (12.2), and printserial's format (13.3),
alongside the integer-overflow (2.7), pointer (4), and error-model (14) decisions made earlier.

What remains is implementation, not design. A few surfaces are left for the implementation to pin
down, because they are details of the toolchain rather than the language: the exact per-argument
marshalling helpers for the quarantined variadic-C call (18.3), and the internals of the garbage
collector (8.1).

Two features are intentionally absent in this version rather than overlooked: there is no
async/await, and there are no generators. Concurrency is thread-based (Section 17.2). If either
arrives later it will be a deliberate addition, not a retrofit.

The language itself is fully specified.
