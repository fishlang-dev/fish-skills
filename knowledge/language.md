# Fish for TypeScript developers

The values and everyday syntax that go wrong when Fish is written as if it were TypeScript:
program shape, numbers, conditions, equality, absence, strings, bindings, collections, functions,
classes in brief, enums, `match`, pipes and generators. Moves and borrows are in `ownership.md`,
the type system in `types.md`, `throws` and `async` in `errors-async.md`, the std library in
`std.md`, and porting a TypeScript file step by step in `porting.md`. Checked against fishc 0.1.3.

In the blocks that show refusals, the compiler reports one error per function, so each function
holds one refused line with its message beside it.

## 1. What is the same

The syntax. Fish parses all of TypeScript: `const` and `let`, type annotations, `type` and
`interface`, classes, generics, arrows, template literals, destructuring, spread, `if`, `for`,
`for...of`, `while`, `do`, `switch` with fallthrough, labels, `?:`, `++`, `?.`, `??`, `import` and
`export`. Semicolons are optional. Most array, string, `Map`, `Set`, `Math` and `JSON` methods
have their JavaScript names and results (`std.md`).

What differs is what the values are. Everything below is a place where the TypeScript reading of
a line is wrong, or where the compiler refuses a line TypeScript takes.

## 2. Program shape

Execution starts at `main()`, which takes no parameters and returns no value; it may be `async`.
A file's top level holds declarations only: `import`, `function`, `class`, `type`, `interface`,
`enum` and `const`. `print` is a second spelling of `console.log`.

```fsh
const LIMIT = 3;
const NAMES = ["ada", "bo"];
const double = (n: i64): i64 => n * 2;
function main() {
  console.log("limit", double(LIMIT), NAMES); // expect: limit 6 [ 'ada', 'bo' ]
  print("same", 1.5, true);                   // expect: same 1.5 true
}
```

State that changes lives in `main` or in a `const` holding an `Atomic` or a `Lock`
(`errors-async.md`): a top-level `let` and a top-level statement are refused.

```fsh
let counter = 0;         // error: error[E0404]: a top-level 'let' would be a global that changes; use 'const'
console.log("starting"); // error: error[E0404]: only declarations are allowed at the top level; move this into main()
function main() {}
```

A top-level `const` is computed while compiling, so its initializer may call functions but can't
read a file, the clock or the environment: `const started = Date.now()` is E1101, `'now' can't run
while compiling: comptime code only computes values`, which `fishc build` and `fishc run` report
and `fishc check` does not. A file with no `main` is E0405, `no main() function; execution starts
there`.

A local file is imported by its `.fsh` name, as in `import { double, type Point } from
"./util.fsh"`. Named and default imports work; `import * as u` is E0801 (`namespace imports aren't
supported yet; import the names you use`), and importing a name the file declares without `export`
is E0902. More: `examples/modules_basic`, `examples/modules_forms`.

## 3. Numbers

**There is no one number type.** An integer literal is an `i64`. A literal with a point or an
exponent is a `number`, the 64-bit float; `f64` is another name for it, and messages always say
`number`. The sized types are `i8`, `i16`, `i32`, `i64`, `i128`, `isize`, `u8`, `u16`, `u32`,
`u64`, `u128`, `usize` and `f32`, and `123n` is a `bigint`.

A literal takes the type it is written for, so `const r: f64 = 5 / 2` is a float division. A
variable does not: once `n` is an `i64` it stays one, and two number types never mix. The habit
that fails is TypeScript's `total / count` on whatever the two happen to be. `as` converts the way
Rust's does: an integer narrows by dropping high bits, a float loses its fraction and stops at the
integer type's ends. Integer `/` and `%` truncate toward zero.

```fsh
function half(x: f64): f64 { return x / 2 }
function main() {
  const ratio: f64 = 5 / 2;
  const bytes: u8[] = [1, 2, 255];
  console.log(7 / 2, -7 / 2, -7 % 3, ratio, half(3), bytes); // expect: 3 -3 -1 2.5 1.5 [ 1, 2, 255 ]
  const n = 7, f = 2.5;
  console.log((n as f64) * f, f as i64, -2.9 as i64, 300 as u8, 1e30 as i64); // expect: 17.5 2 -2 44 9223372036854775807
  console.log(1.0, 0.1 + 0.2, 1_000, 0xff, 2 ** 10, 2.0 ** 0.5); // expect: 1 0.30000000000000004 1000 255 1024 1.4142135623730951
}
```

```fsh
function mix(n: i64, f: f64): f64 { return n * f } // error: error[E0111]: operator '*' can't mix 'i64' and 'number'; convert one side with 'as', like 'x as i64'
function pass(n: i64): f64 { return Math.sqrt(n) } // error: error[E0111]: 'Math.sqrt' takes a 'number', an f64, not 'i64'; convert it with 'as', as in 'n as f64'
function fit(): u8 { return 300 }                  // error: error[E0110]: '300' doesn't fit in 'u8', which holds 0 to 255
function power(x: i64, y: i64): i64 { return x ** y } // error: error[E0110]: the exponent of '**' on an integer is a 'u32', as in Rust's 'pow', not 'i64'; convert it with 'as u32'
function pick(xs: Ref<i64[]>, i: i64): i64 { return xs[i] } // error: error[E0101]: an array's index is a 'usize', not 'i64'; convert it with 'as usize'
function bits(x: number) { console.log(x & 1) }    // error: error[E0103]: operator '&' works on integers, and 'number' is a float; convert it with 'as i64' first
function main() {}
```

`Math.floor`, `Math.round` and the rest of `Math` take and give floats, so `Math.floor(a / b)` on
integers is refused; integer `/` already truncates. The bit operators, `>>>` included, work on
integers of one type, and `&` on booleans is refused with `use '&&'`. A `bigint` doesn't mix with
the other integers either: `1n + 1` is E0111, `convert the number with 'BigInt(x)', or the bigint
with 'as i64'`. More: `examples/int.fsh`, `examples/float.fsh`, `examples/bitwise.fsh`,
`examples/bigint.fsh`, `examples/i128.fsh`, `examples/math.fsh`.

**Lengths and indexes are `usize`.** `xs.length` and `s.length` are `usize`, an array or string
index must be one, and a `let i = 0` compared with a length becomes one. Methods where a negative
position counts from the end (`slice`, `at`) take an `i64`, and `indexOf` gives an `i64`, so it
can be -1.

**Symptom**: `attempt to subtract with overflow` from a loop that counts down, or from
`xs.length - 1` on an empty array.
**Why**: a `usize` can't go below zero, so `i >= 0` is always true and the last `i--` overflows.
**Fix**: count down from the length and index with `i - 1`, or convert the length with `as i64`.

**Overflow panics.** In a debug build `+`, `-`, `*`, `**` and a shift past the type's width panic
on overflow; with `--release` they wrap. Division by zero panics in every build. Every integer
type has Rust's `checked`, `wrapping`, `saturating` and `overflowing` methods (`checkedAdd`,
`wrappingMul`, `saturatingSub`, `checkedPow` and so on), which mean the same in every build; the
checked ones give an Option. More: `examples/overflow.fsh`, `examples/integer_methods.fsh`,
`examples/power.fsh`, `examples/shift.fsh`, `examples/divide.fsh`.

**Parsing gives an Option, not NaN.** `parseInt(s)` is an `i64 | null`, and `parseFloat(s)` and
`Number(s)` are an `f64 | null`. `Number(n)` on a number is E0504 (`'Number' parses a string, not
'i64'; to convert a number, write 'x as f64'`). A number becomes a string with `String(n)`, a
template or `"" + n`; an integer has no `toString()` (E0502), and a float has `toFixed`.

```fsh
function main() {
  const xs = [10, 20, 30];
  let sum = 0;
  for (let i = 0; i < xs.length; i++) sum += xs[i];
  for (let i = xs.length; i > 0; i--) sum += xs[i - 1];
  const at = xs.indexOf(20);
  console.log(sum, (xs.length as i64) - 1, at, xs[at as usize], xs.slice(-2)); // expect: 120 2 1 20 [ 20, 30 ]
  const port = parseInt("8080") ?? 80;
  console.log(port + 1, parseInt("x"), Number("2.5"), parseInt("ff", 16)); // expect: 8081 null 2.5 255
  console.log(String(42) + "!", `${port}`, "" + 1.5, (2.5).toFixed(2));    // expect: 42! 8080 1.5 2.50
  const max = 9223372036854775807;
  let level: u8 = 250;
  level = level.saturatingAdd(10);
  console.log(max.checkedAdd(1), max.wrappingAdd(1), max.saturatingAdd(1), level); // expect: null -9223372036854775808 9223372036854775807 255
  console.log(max + 1);
}
// panic: attempt to add with overflow
```

## 4. Conditions: no truthiness

`if`, `while`, `?:`, `!`, `&&` and `||` take a `boolean` and nothing else. `0`, `""`, `null` and
an empty array are not false, and `||` does not supply a default. `typeof x` is only a test, as in
`typeof x === "string"`, where it narrows a union (`types.md`); as a value it is E0801, and every
number type answers `"number"`.

| TypeScript | Fish |
| --- | --- |
| `if (s)` on a string | `if (s !== "")` or `if (s.length > 0)` |
| `if (n)` on a number, `!!n` | `if (n !== 0)`, `n !== 0` |
| `if (!xs.length)` | `if (xs.length === 0)` |
| `if (x)` on a `T \| null` | `if (x !== null)` |
| `name \|\| "anon"` | `name ?? "anon"` |

```fsh
function a(s: string) { if (s) console.log(s) }         // error: error[E0102]: condition must be a boolean, not 'string'; compare explicitly, e.g. 'n !== 0'
function b(x: i64 | null) { if (x) console.log(x) }     // error: error[E0102]: condition must be a boolean, not the Option 'i64 | null'; check it with '!== null'
function c(xs: Ref<i64[]>): boolean { return !xs.length } // error: error[E0103]: operator '!' cannot be applied to type 'usize'
function d(name: string | null) { console.log(name || "anon") } // error: error[E0103]: operator '||' cannot be applied to types 'null | string' and '"anon"'
function main() {}
```

## 5. Equality

`===` compares values, not identities. Strings, numbers, booleans, arrays, tuples, object types,
unions and enum members compare by what they hold, so two separately built arrays with the same
elements are equal. For arrays and objects this is the opposite of JavaScript. There is no `==`
(section 16).

```fsh
type P = { x: i64; tags: string[] };
function main() {
  const a: P = { x: 1, tags: ["t"] };
  const b: P = { x: 1, tags: ["t"] };
  let xs = [1, 2]; xs.push(3);
  const nan = 0.0 / 0.0;
  console.log(a === b, xs === [1, 2, 3], xs !== [1, 2], "a" + "b" === "ab", nan === nan); // expect: true true true true false
}
```

What can't be compared is refused while compiling. A class is compared through its
`equals(other: Ref<this>): boolean` method, which `@derive(Eq)` writes (`meta.md`). A `Set` is
refused like a `Map`. More: `examples/eq.fsh`.

```fsh
class Pt { constructor(public x: i64) {} }
function widths(a: i32, b: i64): boolean { return a === b } // error: error[E0112]: this comparison appears to be unintentional because the types 'i32' and 'i64' have no overlap
function maps(a: Ref<Map<string, i64>>, b: Ref<Map<string, i64>>): boolean { return a === b } // error: error[E0112]: values of type 'Map<string, i64>' can't be compared with '===': a Map isn't compared by value; compare its entries
function points(): boolean { return new Pt(1) === new Pt(1) } // error: a class compares through 'equals(other: Ref<this>): boolean', which 'Pt' doesn't have; add one, or '@derive(Eq)'
function main() {}
```

## 6. Absence: null, undefined and Option

`null` and `undefined` are one empty value, and both print as `null`. `T | null`, `T | undefined`,
`Option<T>`, an optional field `x?: T` and an optional parameter are all the same thing: an Option
of `T`. It is checked with `=== null` or `=== undefined`, and either spelling works on any of
them. A check narrows it for the rest of the branch, after an early `return`, and across `&&` and
`?:`. `!` takes the value out and panics when there is none.

```fsh
type User = { name: string; nick?: string; age: i64 | null };
function find(n: i64): User | null {
  if (n > 0) return { name: "Ada", age: n };
  return null;
}
function greet(u: Ref<User>, title?: string): string { return `${title ?? "friend"} ${u.nick ?? u.name}` }
function main() {
  const u: User = { name: "Bo", age: null };
  console.log(u.nick, u.age, u.age === undefined, greet(u), greet(u, "Dr")); // expect: null null true friend Bo Dr Bo
  console.log(find(0)?.name, find(1)?.name, find(1)?.nick?.length, find(2)!.age); // expect: null Ada null 2
  const hit = find(3);
  if (hit === null) return;
  console.log(hit.name, hit.age !== null && hit.age > 2); // expect: Ada true
  console.log(find(0)!.name);
}
// panic: called `Option::unwrap()` on a `None` value
```

Using an Option before it is checked, and treating a value that is never empty as one, are both
E0108. A `!` on a value that is never empty is accepted and does nothing.

```fsh
function unchecked(o: i64 | null): i64 { return o + 1 } // error: error[E0108]: operator '+' can't use the Option 'i64 | null' until it is checked; check it with '!== null' first, or give a default with '??'
function never(n: i64): i64 { return n ?? 0 }           // error: error[E0108]: the left side of '??' is a 'i64', which is never empty; '??' gives a default for an Option
function chain(p: Ref<{ x: i64 }>): i64 { return p?.x } // error: error[E0108]: '?.' reads through an Option, and this is a '{ x: i64 }', which is never empty; use '.'
function main() {}
```

**Indexing is not an Option.** `xs[i]` and `s[i]` give the element and panic when the index is out
of bounds, as in Rust, so `xs[i]!` is never needed and `xs[i] ?? d` is E0108. What may be missing
gives an Option: `xs.at(i)`, `xs.find(f)`, `xs.pop()`, `xs.shift()`, `map.get(k)`, and a read of a
dictionary, `d[k]`. More: `examples/option.fsh`, `examples/optional.fsh`, `examples/non_null.fsh`.

**Symptom**: a change made to what `map.get(k)` gave doesn't show in the map, or
`m.get(k)!.push(x)` fails with E0212, `'push' changes its array, so call it on a variable or a field`.
**Why**: `get` gives a copy of the value, and `!` and `??` give copies too.
**Fix**: take the value into a `let`, change it, and `set` it back.

**Symptom**: `type 'null | i64[]' is not assignable to type 'i64[]'` on `m.get(k) ?? []`, or
`'null | i64[]' has no method 'push'` on its result.
**Why**: an empty `[]` has no element type of its own, and here it is typed as the whole left
side, `null | i64[]`.
**Fix**: give the fallback a type of its own, as `none` has below.

```fsh
function main() {
  let groups = new Map<string, i64[]>();
  const none: i64[] = [];
  for (const n of [1, 2, 3]) {
    const key = n % 2 === 0 ? "even" : "odd";
    let list = groups.get(key) ?? none.clone();
    list.push(n);
    groups.set(key, list);
  }
  console.log(groups, groups.get("odd")!.length, groups.has("x")); // expect: Map(2) { 'odd' => [ 1, 3 ], 'even' => [ 2 ] } 2 false
  let xs = [1, 2, 3];
  console.log(xs[0] + 1, xs.at(-1), xs.at(9), xs.find((x) => x > 1), xs.pop()); // expect: 2 3 null 2 3
  console.log(xs[7]);
}
// panic: index out of bounds: the len is 2 but the index is 7
```

## 7. Strings

A string is an immutable value. Assigning one or passing it to a function copies it cheaply and
never moves it, unlike an array or an object, so the old name stays usable. `+=` builds a new
string. `length` and `s[i]` count UTF-16 code units, as in JavaScript: `s[i]` is a one-unit string
and panics past the end, and `for...of` walks whole code points.

A template, `String(x)` and `+` take strings, numbers and booleans only. An Option, an array or
an object there is E0510, not `"null"`, `"1,2"` or `"[object Object]"`. `console.log` prints any
value directly; to make a string, use `join`, `JSON.stringify`, or `inspect` from `node:util`,
which gives what `console.log` prints. More: `examples/string.fsh`.

```fsh
import { inspect } from "node:util";
function shout(s: string): string { return s.toUpperCase() + "!" }
function main() {
  let a = "fish";
  const b = a;
  a += "es";
  console.log(a, b, shout(b), b < a); // expect: fishes fish FISH! true
  const s = "a😀é";
  let points: string[] = [];
  for (const c of s) points.push(c);
  console.log(s.length, points.length, s[0], s.slice(-1), s.indexOf("é")); // expect: 4 3 a é 3
  const xs = [1, 2];
  const p = { x: 1, tags: ["a"] };
  const o: i64 | null = null;
  console.log(`${xs.join(",")} ${o ?? 0}`, JSON.stringify(p), inspect(p)); // expect: 1,2 0 {"tags":["a"],"x":1} { tags: [ 'a' ], x: 1 }
}
```

```fsh
function arr(xs: Ref<i64[]>): string { return `xs: ${xs}` } // error: error[E0510]: a template works with strings, numbers and booleans, not 'i64[]'
function opt(o: i64 | null): string { return "o: " + o }    // error: error[E0510]: '+' works with strings, numbers and booleans, not 'i64 | null'
function main() {}
```

## 8. Bindings

`const` is deeply immutable: no reassignment, no field write, no `push`, no `set`, and no call of
a method that changes its object. Anything that will change is a `let`. This is the habit that
fails most often, since TypeScript declares nearly every array and object `const`. A binding also
needs a type the compiler can see where it is declared. An unused binding is warning W0001; name
it `_x` when that is on purpose.

A third keyword, `using x = value;`, binds a value whose class has a `[Symbol.dispose]()` method
and keeps it in its block: the binding can't be reassigned or moved, only lent, and the method
runs where the block ends. `await using` is its async form. Both are in `ownership.md`, section
18, and `errors-async.md`, section 18.

```fsh
class Counter { n = 0; bump(this: Mut<this>) { this.n += 1 } }
function a() { const xs = [1, 2]; xs.push(3) }               // error: error[E0207]: cannot push to 'xs' because it is a constant
function b() { const p = { x: 1 }; p.x = 2 }                 // error: error[E0207]: cannot assign to 'p.x' because 'p' is a constant
function c() { const m = new Map<string, i64>(); m.set("a", 1) } // error: error[E0207]: cannot add to 'm' because it is a constant
function d() { const k = new Counter(); k.bump() }           // error: error[E0207]: cannot call 'bump' on 'k' because it is a constant
function e() { const xs = []; console.log(xs.length) }       // error: error[E0104]: an empty array needs a type to say what it will hold, like 'let xs: string[] = []'
function f() { let x; x = 1; console.log(x) }                // error: error[E0406]: 'x' needs a type to be declared without a value, like 'let x: string'
function main() {}
```

## 9. Arrays, Map, Set and objects

Literals, spread, destructuring and the array methods read as in TypeScript. Three things don't:
assigning an array, an object, a `Map` or a class instance to another name moves it
(`ownership.md`); `sort()` with no comparator sorts numbers as numbers; and an object type is a
record with a fixed set of fields, printed and listed by `Object.keys` in name order, not
insertion order.

```fsh
type P = { x: i64; name: string };
function main() {
  let nums = [10, 9, 1];
  nums.sort();
  nums[0] = 0;
  const [first, ...rest] = nums;
  const more = [...nums, 11].map((n) => n * 2).filter((n) => n > 0);
  console.log(nums, first, rest, more); // expect: [ 0, 9, 10 ] 0 [ 9, 10 ] [ 18, 20, 22 ]
  const p: P = { x: 1, name: "a" };
  const q = { ...p, x: 2 };
  const { x, name: label } = q;
  console.log(q, x, label, Object.keys(p)); // expect: { name: 'a', x: 2 } 2 a [ 'name', 'x' ]
  let seen = new Set<string>();
  seen.add("a"); seen.add("a");
  const table = new Map<string, i64>([["a", 1], ["b", 2]]);
  for (const [k, v] of table) console.log(k, v, seen.has(k), seen.size);
  // expect: a 1 true 1
  // expect: b 2 false 1
  let counts: { [k: string]: i64 } = {};
  for (const w of ["a", "b", "a"]) counts[w] = (counts[w] ?? 0) + 1;
  const key = "x";
  console.log(counts, counts["zz"], p[key], p["name"]); // expect: { a: 2, b: 1 } null 1 a
}
```

**An object is not a dictionary.** A field can't be added or removed, and a computed key must be
known while compiling, as `key` is above. Keys known only at run time go in a `Map`, or in a
dictionary type `{ [k: string]: T }` (also written `Record<string, T>`), whose reads are Options.
More: `examples/array.fsh`, `examples/map.fsh`, `examples/destructure.fsh`, `examples/spread.fsh`,
`examples/index_signatures.fsh`, `examples/object_keys.fsh`.

```fsh
function get(p: Ref<{ x: i64 }>, key: string): i64 { return p[key] } // error: error[E0120]: a computed key has to be known while compiling, and this is a 'string'
function add() { let p = { x: 1 }; p.y = 2 }            // error: error[E0502]: property 'y' does not exist on type '{ x: i64 }'
function remove() { let p = { x: 1, y: 2 }; delete p.y } // error: error[E0801]: operator 'delete' is not supported yet
function keys(p: Ref<{ x: i64 }>) { for (const k in p) console.log(k) } // error: error[E0801]: 'for...in' loops are not supported yet
function main() {}
```

## 10. Functions and closures

Every parameter needs a type. A return type is inferred, except for a function that calls itself.
Default values, optional and rest parameters, and arrows are TypeScript's. A function type is
written `(n: i64) => i64`, and a top-level function is passed by name.

```fsh
function greet(name: string, greeting = "hello", ...rest: string[]): string { return `${greeting} ${name} ${rest.length}` }
function apply(f: (n: i64) => i64, x: i64): i64 { return f(x) }
function adder(k: i64): (n: i64) => i64 { return (n) => n + k }
function twice(n: i64): i64 { return n * 2 }
function main() {
  console.log(greet("ada"), greet("bo", "yo", "x", "y")); // expect: hello ada 0 yo bo 2
  console.log(apply(twice, 4), apply(adder(5), 1), [1, 2].map(twice)); // expect: 8 6 [ 2, 4 ]
  let count = 0;
  const bump = () => { count += 1 };
  bump(); bump();
  console.log(count); // expect: 2
}
```

A closure borrows what it captures, and one that changes a captured variable holds it mutably
until the closure's own last use. Above, `count` is read after the last `bump()`. Reading it
between two calls is refused, as in `between` below; the rules are in `ownership.md`. There is no
`any`, no `object` type and no `arguments`; `unknown` exists and must be narrowed (`types.md`).
More: `examples/closure.fsh`, `examples/default.fsh`, `examples/rest.fsh`,
`examples/function_value.fsh`.

```fsh
function between() { let total = 0; const add = (n: i64) => { total += n }; add(1); console.log(total); add(2) } // error: error[E0203]: cannot use 'total' while 'add' borrows 'total' mutably and is used later
function inc(n) { return n + 1 } // error: error[E0104]: parameter 'n' implicitly has an 'any' type; add a type annotation
function fact(n: i64) { return n <= 1 ? 1 : n * fact(n - 1) } // error: error[E0104]: 'fact' needs a return type annotation because it calls itself
function loose(x: any) {}        // error: error[E0105]: cannot find type 'any'
function expr(): i64 { const f = function (x: i64): i64 { return x }; return f(1) } // error: error[E0801]: function expressions are not supported yet
function local(): i64[] { const double = (n: i64) => n * 2; return [1, 2].map(double) } // error: error[E0801]: a local function passed by name isn't supported yet; write an arrow calling it, as in '(x) => double(x)'
function main() {}
```

## 11. Classes in brief

Class syntax is TypeScript's: fields, initializers, parameter properties, `readonly`, `static`,
`#private`, getters and setters, `extends`, `instanceof`. The differences: every field must be
assigned by its initializer or the constructor, `this` is read-only in a method unless the method
declares `this: Mut<this>`, a method that changes its object can only be called on a `let`
(section 8), and classes are nominal. Depth, interfaces and generics: `types.md`. More:
`examples/class.fsh`, `examples/classes.fsh`, `examples/accessors.fsh`, `examples/extends.fsh`.

```fsh
class Counter {
  count = 0;
  #step: i64;
  constructor(public readonly label: string, step: i64) { this.#step = step }
  bump(this: Mut<this>): i64 { this.count += this.#step; return this.count }
  get doubled(): i64 { return this.count * 2 }
  set doubled(v: i64) { this.count = v / 2 }
}
class Loud extends Counter { constructor() { super("loud", 10) } }
function main() {
  let c = new Counter("a", 2);
  c.bump(); c.doubled = 10;
  let l = new Loud();
  console.log(c.count, c.doubled, l.bump(), l instanceof Counter, c); // expect: 5 10 10 true Counter { count: 5, label: 'a' }
}
```

```fsh
class P { x: i64; y: i64; constructor(x: i64) { this.x = x } } // error: error[E0703]: property 'y' has no initializer and is not definitely assigned in the constructor
class C { n = 0; bump() { this.n += 1 } } // error: error[E0206]: cannot assign to 'this.n' because 'this' is read-only here; declare 'this: Mut<this>'
function main() {}
```

## 12. Enums and switch

Numeric and string enums are TypeScript's, and a numeric member reads as an `i64`. An `i64` is not
an enum value (E0101), and the reverse mapping `Color[0]` is refused. Fish adds enums whose members
hold data, built by calling the member and taken apart with `match`; one enum can't mix the two
kinds.

`switch` falls through as in JavaScript. A `switch` that names every member still doesn't count as
returning on every path (E0601, shown under section 13): add a `default`, or use `match`, which is
checked for coverage. More: `examples/enum.fsh`, `examples/enums.fsh`, `examples/switch.fsh`.

```fsh
enum Color { Red, Green, Blue }
enum Level { Low = "low", High = "high" }
enum Shape { Circle(f64), Rect(f64, f64), Empty }
function name(c: Color): string {
  switch (c) { case Color.Red: return "red"; case Color.Green: return "green"; default: return "blue" }
}
function main() {
  const n: i64 = Color.Blue;
  const shapes = [Shape.Circle(2.0), Shape.Rect(1.0, 2.0), Shape.Empty];
  console.log(name(Color.Blue), n, Level.High, shapes.length, shapes[0]); // expect: blue 2 high 3 Circle(2)
}
```

## 13. match

`match (value) { case pattern => result, ... }` is an expression. Arms are separated by commas,
and an arm's result is an expression or a block that `return`s its value. Patterns: literals,
alternatives with `|`, a name (binds the value), `_` (matches anything), `null`, a guard with
`if`, an enum member with its data (the enum's name may be left off), an object shape, and an
array of fixed length. The arms must cover every value, or the match is E0607.

```fsh
enum Shape { Circle(f64), Rect(f64, f64), Empty }
type Event = { kind: "click"; x: i64 } | { kind: "key"; code: string };
function area(s: Ref<Shape>): f64 {
  return match (s) {
    case Circle(r) if r < 0.0 => 0.0,
    case Circle(r) => 3.0 * r * r,
    case Shape.Rect(w, h) => w * h,
    case Empty => 0.0,
  };
}
function size(n: i64): string {
  return match (n) {
    case 0 => "none",
    case 1 | 2 => "few",
    case k if k < 0 => { return "negative " + k },
    case _ => "many",
  };
}
function show(e: Ref<Event>): string {
  return match (e) { case { kind: "click", x } => `click at ${x}`, case { kind: "key", code } => "key " + code };
}
function main() {
  console.log(area(Shape.Circle(1.0)), area(Shape.Rect(2.0, 3.0)), size(2), size(-5), size(9)); // expect: 3 6 few negative -5 many
  console.log(show({ kind: "click", x: 3 }), show({ kind: "key", code: "a" })); // expect: click at 3 key a
  const maybe: i64 | null = null;
  const n = match (maybe) { case null => -1, case v => v };
  match ([n, 2]) {
    case [-1, second] => console.log("pair", second), // expect: pair 2
    case _ => console.log("other"),
  }
}
```

```fsh
enum Color { Red, Green, Blue }
function name(c: Color): string { return match (c) { case Color.Red => "red", case Color.Green => "green" } } // error: error[E0607]: this match doesn't cover Color.Blue; add 'case Color.Blue =>', or 'case _ =>' for the rest
function size(n: i64): string { return match (n) { case 0 => "none", case k if k > 0 => "some" } } // error: error[E0607]: this match doesn't cover every 'i64'; add 'case _ =>' for the rest
function viaSwitch(c: Color): string { switch (c) { case Color.Red: return "r"; case Color.Green: return "g"; case Color.Blue: return "b" } } // error: error[E0601]: not all code paths return a value
function main() {}
```

An arm is a body of its own, like an arrow's: `break` and `continue` can't leave it (E0604), and
`return` gives the arm's value, not the function's. A rest element in an array pattern,
`case [first, ...rest]`, is E0801, `rest patterns are not supported yet`. More: `examples/match.fsh`.

## 14. The pipe operator

`value |> expression` evaluates the right side with `%` standing for the left side's value. The
right side must use `%`: a bare function name is refused, unlike F# or Elixir. More:
`examples/pipe.fsh`.

```fsh
function double(n: i64): i64 { return n * 2 }
function add(a: i64, b: i64): i64 { return a + b }
function main() {
  console.log(5 |> double(%) |> add(%, 1) |> % * %); // expect: 121
  console.log(" hi " |> %.trim() |> %.toUpperCase() |> `<${%}>`, 10 |> % % 3); // expect: <HI> 1
}
```

```fsh
function double(n: i64): i64 { return n * 2 }
function main() { console.log(5 |> double) } // error: error[E0004]: the right side of '|>' must use the topic '%'
```

## 15. Generators

`function*` and `yield` work as in TypeScript, and the return type is `Generator<T>` or inferred
from the yields. A generator is lazy, has the iterator helpers (`map`, `filter`, `take`,
`toArray`), spreads, and feeds `for...of`. Calling `next()` changes the generator, so it is held
in a `let`, and its result is narrowed with `r.done === false`: `!r.done` doesn't narrow it
(`property 'value' does not exist on type '{ done: false; value: i64 } | { done: true }'`). A
generator can't `return` a value yet. More: `examples/generator.fsh`, `examples/iterator.fsh`.

```fsh
function* count(n: i64): Generator<i64> { for (let i = 0; i < n; i++) yield i }
function* evens() { for (let n = 0; ; n += 2) yield n }
function main() {
  let g = evens();
  g.next();
  const r = g.next();
  if (r.done === false) console.log(r.value); // expect: 2
  console.log([...count(3)], count(5).map((x) => x * x).filter((x) => x > 1).toArray()); // expect: [ 0, 1, 2 ] [ 4, 9, 16 ]
  for (const k of evens().take(2)) console.log(k);
  // expect: 0
  // expect: 2
}
```

## 16. Forms Fish leaves out on purpose

E0802 marks a TypeScript form that is left out by design, where E0801 marks one not built yet. The
checker raises it for exactly these, each message saying what to write instead:

```fsh
class C { #x = 1; static is(o: Ref<C>): boolean { return #x in o } } // error: error[E0802]: '#x in' can't be used: Fish has no run-time reflection, and a value's class is known while compiling
function a() { var n = 1; console.log(n) }           // error: error[E0802]: 'var' is not supported; use 'let' or 'const'
function b(n: i64): boolean { return n == 2 }        // error: error[E0802]: '==' is not supported; use '==='
function c(n: i64): boolean { return n != 2 }        // error: error[E0802]: '!=' is not supported; use '!=='
function d() { let s = "abc"; s[0] = "x" }           // error: error[E0802]: strings can't be changed; build a new one instead, joining parts with '+'
function e() { let s = "abc"; s.length = 1 }         // error: error[E0802]: a string's 'length' can't be changed; strings can't be changed, so build a new one instead
function main() {}
```

`fishc lint` reports what it finds in a TypeScript file under the same code, including forms with
no Fish spelling at all: `eval` and `new Function`, prototype edits and `Object.defineProperty`,
`delete`, the `arguments` object, `Symbol` beyond a `[Symbol.iterator]` method, and declaration
merging (`porting.md`). Left out the same way, under the codes of their own areas: truthiness
(E0102, section 4), `any` (E0105, section 10), a top-level `let` (E0404, section 2), and identity
comparison (section 5).
