# Interop: C, TypeScript declarations, npm and Rust

Every way a Fish program reaches code that is not Fish: C functions through `declare function`
and `unsafe`, Fish exported to C with `fishc build --lib`, npm packages typed from their `.d.ts`
files and run in an embedded JavaScript engine, and Rust crates through a generated shim. Fish
packages, `fish.toml` and the registry are in `toolchain.md`; std's `node:` modules and the `Bun`
global are in `std.md`; handles follow the ownership rules of `ownership.md`. Checked against
fishc 0.1.3 on macOS arm64, with clang, cargo and Bun installed.

## 1. Which door to use

| You have | Write | Build needs | `unsafe` | A call costs |
| --- | --- | --- | --- | --- |
| a C function | `declare function f(x: i32): i32;` | `--link <lib>` outside libc and libm | each call | a direct call |
| a C program that wants Fish code | `export function`, `fishc build --lib` | nothing more | no | a direct call |
| an npm package of plain JavaScript | `import { f } from "pkg"` | `node_modules` with declarations, `bun` on PATH | no | an interpreter, values copied |
| a Rust crate | `import { f } from "rust:crate"`, a `declare module` block | `fish.toml`, cargo | no | a direct call through a shim |

npm is the slow door and the narrow one (section 9). Prefer std, then Rust or C, and keep npm for
logic that would be a rewrite, called at a program's edges and not in its loops.

## 2. Calling C

`declare function` with no body declares a C function, linked by its name. TypeScript habit:
there, `declare` is a type-only promise. In Fish it is a link-time symbol, called with exactly the
types written, which nothing checks against the C header. A call is allowed only in `unsafe { }`.

```fsh
declare function abs(n: i32): i32;
declare function strlen(s: Ptr<u8>): usize;
declare function getenv(name: Ptr<u8>): Ptr<u8>;

function envOr(name: string, fallback: string): string {
  const p = unsafe { getenv(cString(name)) };
  if (unsafe { p.isNull() }) return fallback;
  return unsafe { fromCString(p) };
}

function main() {
  const n: i32 = -7;
  console.log(unsafe { abs(n) }); // expect: 7
  console.log(unsafe { strlen(cString("héllo")) }); // expect: 6
  console.log(envOr("FISH_SURELY_NOT_SET", "unset")); // expect: unset
}
```

```fsh
declare function abs(n: i32): i32;

function main() {
  console.log(abs(-1));
}
// error: error[E1001]: calling the C function 'abs' can only happen inside 'unsafe { }'
```

What may cross: the sized integers and floats, `boolean`, and the raw pointers `Ptr<T>` and
`MutPtr<T>` (`Ptr<void>` for `void *`). Nothing else: no `string`, array, object, enum, union,
`Ref` or function type (E1002, listed in section 13). The return type must be written, `void`
included. Arguments are not converted: a literal takes the parameter's type, but an `i64` variable
given to an `i32` parameter is `error[E0101]` asking for `as i32`.

Not supported, each E0801: variadic functions (`variadic C functions are not supported yet`, so
no `printf`), a C function as a value (`C functions used as values are not supported yet`; wrap
it, as in `xs.map((c) => unsafe { toupper(c) })`), and every other ambient form, `declare const`,
`declare let`, `declare class`, `declare module "fs"` (`ambient declarations are not supported
yet`). So: no C globals, no `errno`, no structs by value, no C callbacks. More: `examples/ffi.fsh`.

## 3. `unsafe { }` and what needs it

`unsafe { }` is a block in statement position and an expression in expression position, where it
holds one expression and gives its value. Rust habit: there is no `unsafe fn`, and the expression
form takes no statements before its value.

```fsh
declare function abs(n: i32): i32;

function main() {
  const a = unsafe { abs(-2) + abs(-3) };
  const f = () => unsafe { abs(-9) };
  unsafe {
    const b = abs(-1);
    console.log(a, f(), b); // expect: 5 9 1
  }
}
```

E1001 is raised for exactly five things outside `unsafe`:

| Operation | Message starts |
| --- | --- |
| calling a declared C function | `calling the C function 'abs' can only happen inside 'unsafe { }'` |
| `p.read()`, `p.write(v)`, `p.offset(n)`, `p.isNull()` | `'read' on a raw pointer can only happen inside 'unsafe { }'` |
| `fromCString(p)` | `'fromCString' can only happen inside 'unsafe { }'` |
| `nullPtr<T>()` | `'nullPtr' can only happen inside 'unsafe { }'` |
| `as` to or from a raw pointer | `'as' with a raw pointer can only happen inside 'unsafe { }'` |

Safe everywhere: making a pointer with `ptrOf`, `mutPtrOf` or `cString`, passing and storing
pointers, comparing them with `===`, and calling Rust or npm functions.

## 4. Raw pointers

`Ptr<T>` reads, `MutPtr<T>` reads and writes; a `MutPtr<T>` passes where a `Ptr<T>` is wanted and
not the other way. There is no `*p` and no `&x`: `ptrOf(place)` and `mutPtrOf(place)` take a
variable, a field or an array element, and the methods are `read`, `write`, `offset` and `isNull`.
`offset` counts elements, not bytes.

```fsh
function sum(start: Ptr<i64>, count: i64): i64 {
  let total = 0;
  for (let i = 0; i < count; i++) total += unsafe { start.offset(i).read() };
  return total;
}

function main() {
  const xs = [10, 20, 30, 40];
  console.log(sum(ptrOf(xs[0]), 4), sum(ptrOf(xs[1]), 2)); // expect: 100 50
  let n: i32 = 1;
  const p = mutPtrOf(n);
  unsafe {
    p.write(p.read() + 41);
  }
  const q: Ptr<i32> = p;
  console.log(n, q === ptrOf(n)); // expect: 42 true
}
```

Writing through a `Ptr` is `error[E1006]: 'write' needs a 'MutPtr'; a 'Ptr' only reads what it
points at`. `ptrOf(xs[0])` indexes first, so it panics on an empty array, and a temporary has no
address (`ptrOf(make())` is E1006). `read` and `write` work on numbers, booleans and pointers
only (`raw reads and writes of 'string' are not supported yet`). A pointer can't be printed.

A pointer converts with `as`, inside `unsafe`, to another pointer type or to `usize` and back.
`nullPtr<T>()` gives a `MutPtr<T>`. C memory is managed by hand:

```fsh
declare function malloc(size: usize): MutPtr<void>;
declare function free(p: MutPtr<void>): void;

function main() {
  const raw = unsafe { malloc(16) };
  const p = unsafe { raw as MutPtr<i64> };
  unsafe {
    p.write(41);
    p.offset(1).write(1);
    console.log(p.read() + p.offset(1).read()); // expect: 42
    console.log((p as usize) !== 0, nullPtr<u8>().isNull()); // expect: true true
    free(raw);
  }
}
```

**Symptom**: C reading a Fish object through `Ptr<Point>` sees its fields in the wrong order.
**Why**: an object's fields are laid out sorted by name, not as written, and there is no C struct
layout. **Fix**: pass numbers and pointers to numbers, or lay the bytes out yourself. More:
`examples/unsafe.fsh`.

```fsh
type Pair = { b: f64; a: f64 };

function main() {
  const p: Pair = { b: 1.0, a: 2.0 };
  console.log(unsafe { (ptrOf(p) as Ptr<f64>).read() }); // expect: 2
}
```

## 5. Strings and buffers across the C boundary

A Fish `string` is not a `char *`. `cString(s)` gives a `Ptr<u8>` to a NUL-terminated UTF-8 copy
of `s`; `fromCString(p)` (unsafe) copies a C string into a new Fish string. C sees bytes, so
`strlen` of `"héllo"` is 6 where `.length` is 5. A buffer for C to fill is a `u8[]` and a
`mutPtrOf` its first element.

```fsh
declare function getcwd(buf: MutPtr<u8>, size: usize): MutPtr<u8>;

function cwd(): string {
  let buf: u8[] = new Array<u8>(1024).fill(0);
  const got = unsafe { getcwd(mutPtrOf(buf[0]), 1024) };
  if (unsafe { got.isNull() }) return "";
  return unsafe { fromCString(got) };
}

async function main() {
  console.log(cwd().startsWith("/")); // expect: true
}
```

`cString` is refused inside async functions and generators (`error[E0801]: 'cString' inside
async functions are not supported yet`). Put the C call in a plain function, as `cwd` is, and
call that from async code. A string holding NUL can't cross: `cString("a\0bc")` panics with `a
string holding NUL can't cross to C`.

**Symptom**: garbage or a crash reading a `cString` pointer later. **Why**: the copy belongs to
the block `cString` is written in and is freed when that block ends, yet the compiler lets the
pointer leave (`function leak(): Ptr<u8> { return cString("gone"); }` compiles). **Fix**: call
`cString` in the same statement as the C call that uses it, and copy anything C hands back with
`fromCString` before the block ends.

## 6. Linking

A program links the C library and libm with no flag, which is why `abs`, `strlen` and `malloc`
above just work. Any other library is named once per library, as clang's `-l` takes it:
`fishc build main.fsh --link z` for zlib's `adler32`. `fishc run` takes the same `--link`, though
its usage line doesn't list it. `fish.toml` has no key for it.

**Symptom**: `clang failed:` followed by `Undefined symbols` naming your function. **Why**:
`fishc check` passes any declaration; the name is only looked up when clang links. **Fix**: add
`--link <library>`, or correct the name.

## 7. Exporting Fish to C

`fishc build api.fsh --lib -o out/api` builds a static library and a header, `out/libapi.a` and
`out/api.h`; `--lib=shared` gives `libapi.dylib` or `libapi.so` instead. Without `-o` they take
the file's name, in the current directory. The exports are the entry file's `export function`s,
each under its own name. Functions it imports, and exported classes and constants, stay inside.

```fsh
export function sumSquares(n: i64): i64 {
  let total = 0;
  for (let i = 1; i <= n; i++) total += i * i;
  return total;
}

export function fill(at: MutPtr<u8>, count: usize, value: u8) {
  for (let i = 0; i < (count as i64); i++) {
    unsafe {
      at.offset(i).write(value);
    }
  }
}
```

The header declares, inside an include guard and an `extern "C"` block for C++,
`int64_t sumSquares(int64_t n);` and `void fill(uint8_t *at, size_t count, uint8_t value);`.
This C program, built with `clang main.c libapi.a -lm -o prog`, printed `14 9 0`:

```c
#include <stdio.h>
#include "api.h"

int main(void) {
  unsigned char buf[4] = {0};
  fill(buf, 3, 9);
  printf("%lld %d %d\n", (long long)sumSquares(3), buf[2], buf[3]);
}
```

A static library needs `-lm` on the link line; a shared one links with `-L<dir> -lapi`. In the
header `i8` to `i64` are `int8_t` to `int64_t`, `u8` to `u64` are `uint8_t` to `uint64_t`, `usize`
is `size_t`, `isize` is `ptrdiff_t`, `f32` and `f64` are `float` and `double`, `boolean` is `bool`,
`Ptr<T>` is `const T *`, `MutPtr<T>` is `T *`, and a pointer to a Fish object is `const void *`.

An export takes and returns only what a C declaration can (section 2), and can't be generic, a
generator, throwing, defaulted, or named like a C keyword or a libc function: each is E1003
(section 13), raised only by a `--lib` build. Elsewhere `export function f(s: string)` is an
ordinary function. A Fish panic in an export never unwinds into C: it prints `panicked at` with
its place and reason, then aborts the process. More: the compiler's `tests/unit/library.fsh`.

## 8. TypeScript declarations: how a package is found and typed

A bare import name is, in this order: a `rust:` crate, a Fish package the importing package's
`fish.toml` lists, a std module (`node:fs`, `fs`, `bun`), and otherwise an npm package. An npm
package is typed only from its declaration files, found as TypeScript's `bundler` resolution
finds them. Fish never reads the JavaScript to type it.

- `node_modules/<name>` is looked for in the importing file's directory, then each one above. A
  copy without declarations is passed over for one further up that has them.
- With `exports` in `package.json`: the subpath's target under the conditions `types`, `import`
  and `default`, in the file's own key order. `./features/*` patterns work, the longer pattern
  wins, `null` excludes a path, and a `.js` target stands for the `.d.ts` beside it.
- Without `exports`: `typings`, then `types`, then the `.d.ts` beside `main`, then `index.d.ts`.
  A subpath `pkg/sub` is `sub.d.ts`, then `sub/index.d.ts`.
- Then `node_modules/@types/<name>` (`@types/scope__name` for `@scope/name`), including its
  `declare module "name"` blocks.

```fsh
import { x } from "absent";
// error: error[E0902]: can't find the package 'absent': no 'node_modules/absent' in
```

The other misses are E0902 too: `'untyped' has no TypeScript declarations` (no `types`, no
`index.d.ts`, no `@types/untyped`), a subpath that `doesn't export './nope' in its package.json
'exports'`, a file that `declares globals, not a module`, and a missing name, which lists what
is there (`'tiny' has no export 'nope'; its declarations in 'node_modules/tiny/index.d.ts'
export 'Box', 'Point'` and so on). Named, default and namespace imports work, as do `export =`
and re-exports between declaration files. What a declared type becomes:

| Declared | In Fish |
| --- | --- |
| `number` | `f64`: an `i64` needs `as number` going in, a result needs `as i64` coming out |
| `string`, `boolean`, literal types, unions of them | themselves |
| `T \| undefined`, `T \| null`, an optional parameter or property | `T \| null` |
| `T[]`, `[A, B]` | an array or tuple, copied across on each call |
| `any`, `unknown`, `object` | `JsValue`, an opaque handle (section 10) |
| an `interface`, an object type alias, a `class` | a handle to the JS object, typed by its members |
| `(x: number) => void`, `Promise<T>` | a Fish closure, an awaitable (section 11) |
| a generic function | typed per call, as `chunk<T>(xs: T[], n: number): T[][]` |
| an `enum` or `namespace` export | refused at the import, E1005 |
| `Date`, `Map`, `Set`, `bigint`, `Record<K, V>` | refused where called |

A declaration Fish can't type is refused only when the program calls it, at the declaration
(`node_modules/shapes/index.d.ts:3:33: error[E1005]: 'when' from 'shapes' gives a 'Date', which
can't cross between Fish and JS yet: Fish has no JS form for it`), with a note at the call
(`note: 'when' is called here`).

A function its declaration file declares more than once (overloads) is imported with every
signature: with `twice(x: number): number` and `twice(x: string): string` declared, `twice(2)` and
`twice("ab")` both type and run. An overloaded method of an interface is typed by its first
signature. More: the compiler's `tests/unit/typings.fsh` and `tests/unit/npm.fsh`.

## 9. npm packages: what runs, and what it costs

`fishc check` stops at the declarations. `fishc build` and `fishc run` of a program whose code
reaches a package call do two more things:

1. Bundle the packages' JavaScript into one ES module with Bun's bundler, in a `bun` child
   process found on PATH. Without it: `error[E0901]: bundling a program's npm packages needs
   Bun; install it so 'bun' is on PATH`. A package with declarations and no JavaScript is
   `error[E0901]: 'nodets' has no JS Fish could bundle`.
2. Store that bundle in the binary as data, and compile QuickJS-ng 0.17.0, an interpreter kept
   unmodified in the compiler's `vendor/quickjs-ng`, into the binary with clang.

The binary then needs nothing at run time: no `node_modules`, no Bun, no Node. Here a hello
world was 516 KB and a small program calling a package 1.7 MB; the first call paid up to a
millisecond to start the engine, and each later call passing and returning a short string about
a microsecond. `fish.lock` does not list npm packages: what is bundled is whatever `node_modules`
held at build time, so pin it with the lockfile of the tool that installed it.

```ts
// node_modules/tiny/index.d.ts
export declare function camel(s: string, upper?: boolean): string;
export declare function count(xs: string[]): number;
export declare class Box {
  constructor(size: number, label?: string);
  size: number;
  grow(by: number): void;
}
export default function slug(s: string): string;
```

```fsh fragment
import slug, { camel, count, Box } from "tiny";

function main() {
  const n: f64 = count(["a", camel("foo bar_baz", true)]);
  console.log(n, slug("Hello World")); // 2 hello-world
  const b = new Box(3, "crate");
  b.grow(2);
  b.size = b.size + 1;
  console.log(b.size); // 6
}
```

The engine is a bare ECMAScript interpreter, not Node. Inside package code these were
`undefined` when run: `console`, `setTimeout`, `fetch`, `Buffer`, `TextEncoder`, `URL`, `Intl`,
`crypto`, `structuredClone`, `require`. Present: the language's own built-ins, `queueMicrotask`,
`performance`, and a `process` with `argv`, `env`, `platform` and `exit`. Of Node's modules a
package may import `path`, `os`, `process` and `fs/promises` (`readFile`, `writeFile`), which
call Fish's runtime. Any other stops the build: `error[E1005]: 'usesfs' needs Node's 'fs' module,
which a package's JS can't use in Fish yet`.

A JS exception from a synchronous call is a panic, not something to catch: the program prints
`uncaught exception in JS: TypeError: boom` and exits with 101, and a `try` around the call is
refused with E0603 because nothing in it throws. A declaration that lies is caught when the value
crosses, also as a panic: `'bytes' from 'shapes' gave an object, where its declaration says
'u8[]'`. JSDoc `@throws` tags in a package's declarations are ignored.

## 10. `JsValue` and handles

A package's object (an interface, object type or class instance) is a handle: reading `b.size`
or calling `b.grow(2)` goes to JS each time. Handles are owned values like any other (moved by
assignment, lent with `Ref`, movable into a spawned task), but `.clone()` copies the handle, not
the object, and Fish's `const` says nothing about the JS object behind it: a method called
through a `Ref<Box>` may change it, and so may `b.size = 9` on a `const b`.

A Fish object literal passes where a declared object type of plain data is wanted, converted at
the call (`norm({ x: 3.0, y: 4.0 })`), but not where the type has methods, and not outside a call:

```fsh
function main() {
  const o: JsValue = 5;
}
// error: error[E1005]: turning a Fish value into a JS value isn't supported yet, outside a call or a write that gives it to JS; a 'JsValue' or a package's object comes only from JS
```

`JsValue` is what `any`, `unknown` and `object` become. It has three methods, `get(key)`,
`at(index)` and `has(key)`, and is read by narrowing with `typeof` against `"string"`,
`"number"`, `"boolean"`, `"object"`, `"function"`, `"undefined"`, `"bigint"` or `"symbol"`, or by
comparing with `null` or `undefined`:

```fsh
function size(v: Ref<JsValue>): f64 {
  const n = v.get("length");
  return typeof n === "number" ? n : 0.0;
}

function describe(v: Ref<JsValue>): string {
  if (typeof v === "string") return v;
  if (typeof v === "number") return `${v + 0.5}`;
  if (v === null || v === undefined) return "nothing";
  return v.has("length") ? `${size(v)} long` : "an object";
}
```

TypeScript habit: `v.n` on an `any`. Refused, with the fix in the message:

```fsh
function show(v: Ref<JsValue>) {
  console.log(v.n);
}
// error: error[E1005]: a 'JsValue' could be anything, as an 'unknown' could, so it has no property 'n' to use; read one with 'v.get("n")'
```

Also refused: `v[0]` (use `v.at(0)`), writing `v.x = 1` or `v[0] = 1`, `v as string` (E0111),
`v.get("n") === 2.0` before narrowing (E0801), `typeof v` as a value outside a comparison
(E0801), `console.log(v)` (E0510) and `JSON.stringify(v)` (E0509). Reading through `undefined`
panics with JS's own `TypeError`.

## 11. Callbacks and promises

A Fish closure passes where a declaration takes a function, if its parameters and result cross
and it doesn't throw. JS may keep it, so it owns what it captures: captures move in, a captured
`Ref` is refused, and changing a captured `let` is `error[E0210]: this closure changes 'total',
which it captures, but a stored callable can't change what it captures; keep that state in an
'Atomic' or a 'Lock'`. What worked here for state the caller reads afterwards: a `shared<{ sum:
f64 }>`, its `.clone()` moved into the callback and changed there with `update`.

A declared `Promise<T>` result is awaited like a Fish one, and the `await` can throw `JsError`
(`name`, `message`, and the thrown `value` as a `JsValue`), so the caller declares or catches it:
`error[E0602]: 'main' must declare 'throws JsError' after its return type since this Promise can
throw 'JsError', or catch it with try/catch`. A rejection arrives there. A Fish future passes
where a `Promise<number>` parameter is declared, but only inside an `async` function, because
giving it starts it as a task. A callback that returns a `Promise`, or a function or `Promise`
inside another value, is E1005. The engine has no timers: a package that waits with `setTimeout`
rejects with `setTimeout is not defined`.

## 12. Rust crates

Three pieces: the crate listed in the manifest of the package being built, one `declare module
"rust:<crate>"` block somewhere in that package's files, and an ordinary import. No `unsafe`.

The manifest entry goes under `[rust-dependencies]`, as `demo = { path = "rust/demo" }`, `demo =
"1.2"`, or a table with `version`, `features`, `default-features`, and `path` or `git` with one
of `rev`, `tag`, `branch`, as Cargo takes them. The block declares the crate's public items as
Fish sees them, without bodies; `@rust("path::in::crate")` gives the Rust path when the Fish
name differs or the item is in a module:

```fsh
declare module "rust:demo" {
  export function add(a: i64, b: i64): i64;
  export function shout(s: string): string;
  export function halve(n: i64 | null): i64 | null;
  export function sum(xs: Ref<i64[]>): i64;
  export function parse(s: string): i64 throws Error;
  @rust("util::mul") export function mul(a: i32, b: i32): i32;
  export class Counter {
    constructor(start: i64);
    @rust("zero") static empty(): Counter;
    get(): i64;
    add(this: Mut<this>, n: i64): void;
    finish(this: Own<this>): i64;
  }
}
```

After `import { shout, parse, Counter } from "rust:demo"` the calls are plain Fish. Against a
crate written to match, `shout("héllo")` gave `HÉLLO`, `parse("x")` threw an `Error` whose
`message` was `invalid digit found in string`, and `let c = new Counter(5); c.add(2);
c.finish()` gave 70. How each declared type must be written in the crate:

| Fish | Rust |
| --- | --- |
| sized integers, floats, `boolean`, `void` | the same type, `bool`, `()` |
| `string` | `&str` or `String`, whichever the function takes or gives |
| `T[]`, `Ref<T[]>` | `Vec<T>` (moved), `&[T]`; elements are numbers, booleans, strings or Rust types |
| `T \| null` | `Option<T>` |
| `throws Error` | `Result<T, E>`: the `Err` becomes an `Error` with its `Display` text |
| `throws Oops`, a declared Rust class | `Result<T, Oops>`, caught as the Rust value |
| a declared `class` | a boxed Rust value Fish owns and drops once; `constructor` is `new` |
| a method, `this: Mut<this>`, `this: Own<this>` | `&self`, `&mut self`, `self` |
| `Ref<Counter>`, `Mut<Counter>`, `Counter` parameters | `&Counter`, `&mut Counter`, `Counter` |

Refused with E1004 at the declaration: tuples, maps, objects, function types, unions other than
`T | null`, arrays of arrays, `Mut<T[]>`, a returned `Ref`, fields in a Rust class, `async`,
generics, `extends`. A Rust value can't be printed, spread, extended or made a `Dyn`, and
`.clone()` needs `clone(): Counter` declared in its class (E0213), which calls its `Clone`.

fishc writes a shim crate into its cache directory, one `extern "C"` function per declared item,
depending on the crates as `fish.toml` lists them. cargo builds it as a static library on each
build that calls Rust, doing nothing when nothing changed, and the program links it. So:

- `fishc check` never runs cargo and never sees the crate. A declaration that doesn't match it
  fails at `fishc build` with `cargo failed building the Rust shim in` and rustc's own error
  (`cannot find function`, `mismatched types`). Without cargo the build says `this program
  calls Rust, which needs cargo to build, and cargo isn't on PATH`.
- A Rust panic is caught in the shim and raised as a Fish panic at the call, with its message.
- Only the package being built may list Rust crates; a dependency that does is `error[E0906]`.

Threading: Fish moves values between worker threads, so every declared Rust type must be `Send`.
One that isn't fails in cargo, naming `Send` (here, `Rc<i64>` cannot be sent between threads
safely). A Rust value may move into a spawned task. It need not be `Sync`: inside a `shared<T>`
it is reached only within `update`, one task at a time, and reading it outside is E1004. More:
the compiler's `tests/unit/rust.fsh` and `tests/fixtures/rust/demo`.

```fsh
import { add } from "rust:demo";
// error: error[E1004]: 'demo' isn't a Rust dependency of this package; list it under [rust-dependencies] in fish.toml, as in demo = "1.0"
```

## 13. Error codes E1001 to E1006

`fishc explain` has no longer text for these: the message is the whole explanation, and the fix
is what it says. Names in quotes stand for whatever the program wrote.

**E1001, an operation that needs 'unsafe'.** The five in section 3, each ending `so you vouch
for it there`. Fix: wrap that expression in `unsafe { }`.

**E1002, invalid C function declaration.**

- `a C function can't be a generator; drop the '*'`, `a C function can't be async; C calls return when they finish`
- `'main' can't be a C function; it is where the program starts`, `a C function can't throw; C reports failures in its result`
- `a C function needs its return type written, 'void' if it returns nothing`, `a C function can't take a comptime parameter: C takes every argument at run time`
- `a C function's parameter can't be a 'string'; C takes numbers, booleans and raw pointers like 'Ptr<u8>'`
- `a C function can't return a '{ x: i64 }'; C gives numbers, booleans and raw pointers`
- `the C function 'labs' is declared in 'a.fsh' with other types; declare it in one file and import it from there`
- `a library's C functions are its entry file's exported functions, each under its own name; write 'export function' on the function itself` (a `--lib` entry re-exporting from another file)

**E1003, a function a library can't export to C.** Only from `fishc build --lib`.

- `a library has nothing for C to call; mark functions with 'export'`, `a library can't export a generator to C, which has no generators`
- `a library can't export a generic function to C, which has no generics; export one for each type`
- `a library can't export a function that throws to C, which has no exceptions; return a status instead`
- `a library can't export 'int' to C, which needs a name of ASCII letters, digits and underscores that isn't a C or C++ keyword`
- `a library can't export 'free' to C, since C's library or the Fish runtime already uses that name`
- `an exported function's parameter can't have a default in a library, since C callers pass every argument`, `an exported function can't take a comptime parameter, since C calls it with run-time values`
- `an exported function's parameter can't be a 'string' in a library; C takes numbers, booleans and raw pointers like 'Ptr<u8>'`
- `an exported function can't return a 'string' in a library; C gives numbers, booleans and raw pointers` (an `async` export fails here, on its `Promise`)

**E1004, invalid Rust crate declaration or use.**

- Finding the crate: `'demo' isn't a Rust dependency of this package` (section 12); `no file of
  this package declares the functions of 'demo'; declare them in one, as in 'declare module
  "rust:demo" { export function f(x: i64): i64; }'`; `'rust:demo' is declared twice in this
  package; declare its functions in one place`.
- A declaration's shape: `a Rust function is declared without a body; the crate has its body`;
  `the Rust function 's' needs its return type written, 'void' if it returns nothing`; `the Rust
  function 's' can't be async; it returns when the Rust function does`; `'demo::add' is declared
  elsewhere as (i64, i64): i64; declare it with the same types`; `@rust takes the item's path in
  the crate as a string literal, as in @rust("util::mul")`; `this isn't a Rust path; write one
  from the crate's root, as in "util::mul"`.
- Types, after `a Rust function can't take a 'T':` or `the Rust function 's' can't give a 'T':`
  come `maps can't cross the Rust boundary yet`; `tuples can't cross the Rust boundary yet`;
  `'Mut<T[]>' would be '&mut [T]', which can't cross yet; pass the array, which moves it`; `a
  borrow's lifetime can't cross from Rust yet; give the value itself`; `unions other than 'T |
  null' can't cross the Rust boundary yet; Rust enums other than Option and Result aren't
  supported`; `arrays of arrays can't cross the Rust boundary yet`; or `it can't cross the Rust
  boundary yet; Rust functions take and give numbers, booleans, strings, arrays, Options of
  those and Rust types`. A wrong `throws`: `the Rust function 's' throws a Rust 'Err' as Fish's
  'Error', made from its Display text, or as a Rust type declared in a 'rust:' block, not as a
  'string'`.
- Classes: `a Rust type's class declares a constructor, static functions and methods, without
  bodies; Rust fields aren't read from Fish`; `a Rust type's class can't extend another`;
  `generic Rust types can't cross to Fish yet`; `Rust types that aren't Send aren't supported
  yet: Fish moves values between threads, so a Rust type must be Send` (on `@rust.local`); `the
  Rust type 'Bare' declares no constructor; declare one, as in 'constructor(x: i64);', or make
  it with a static function`.
- Use: `a class can't extend the Rust type 'Counter'; hold one in a field instead`; `'c' holds
  a Rust 'Counter', which a shared value gives only inside 'update'`; `a Rust 'Counter' can't
  become a 'Dyn<Getter>' yet; call its methods on it, or take it as a generic parameter`.

**E1005, a value that can't cross between Fish and JS.**

- At a declaration, with a note at the call (section 8). After its colon comes `Fish has no JS
  form for it`, `functions crossing between Fish and JS aren't supported yet`, `Promises
  crossing between Fish and JS aren't supported yet`, `a callback that throws isn't supported
  yet; catch inside it` or `a callback or a Promise inside an object isn't supported yet; give
  it on its own`. Fix: call something else, or wrap the package.
- Imports and bundling: `'Kind' from 'shapes' is an enum, which can't be imported from a
  package yet` (also `a namespace`); `'usesfs' needs Node's 'fs' module, which a package's JS
  can't use in Fish yet` (also `Bun's own` modules).
- Fish values going to JS: `turning a Fish value into a JS value isn't supported yet` (section
  10); `a Promise given to JS starts running as a task when it is given, so it is given only
  inside an 'async' function`; `a callback given to JS must own everything it uses, as JS may
  keep it and call it from another task; it holds a 'Ref<string[]>'`; `JS keeps a callback or a
  Promise given to it, so it is given owned, not borrowed; give it a clone, or take it owned`;
  `spreading arguments into a package's functions isn't supported yet`.
- Reading a `JsValue`: the message of section 10, and `a 'JsValue' has no method 'push': its
  own are 'get', 'at' and 'has', and it is narrowed with 'typeof' to read it`; `'typeof' can't
  tell what a 'JsValue' in a union holds yet; test the 'JsValue' on its own`; `writing a JS
  value's properties isn't supported yet; a 'JsValue' is read with 'get'`.

**E1006, invalid use of a raw pointer.**

- `'ptrOf' needs a variable or a field to point at; a temporary is gone once its statement ends`
- `'mutPtrOf' needs a 'Mut' reference, or a place that may change`, `'write' needs a 'MutPtr'; a 'Ptr' only reads what it points at`
- `raw pointers have no method 'bump'; they have 'read', 'write', 'offset' and 'isNull'`, `a raw pointer converts only to another raw pointer or a 'usize', not 'string'`
- `'nullPtr' takes the type it points to, like 'nullPtr<u8>()'`, `'cString' takes 1 argument`, `'fromCString' takes 1 argument`
