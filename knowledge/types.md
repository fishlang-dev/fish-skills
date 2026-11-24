# Types

How Fish's type system differs from TypeScript's while keeping its syntax. Every value is laid out
in memory while compiling, so a type that TypeScript only checks, Fish also has to size: that is
why there is no `any`, why an interface can't sit in a field, and why a union is a tagged value.
Sized numbers, `Option` and value equality are in `language.md`; `Ref`, `Mut`, moves and `.clone()`
in `ownership.md`; `throws` in `errors-async.md`; `@derive` in `meta.md`. Checked against fishc 0.1.1.

## 1. Object types are structural, classes are nominal

A `type` object type is its set of fields: two aliases with the same fields are one type, a value
with extra fields fits, and so does a class instance through its public fields. A class is its
declaration: nothing else is that class, not a look-alike class and not its own subclass.

```fsh
type Point = { x: i64; y: i64 };
class P3 { x: i64 = 1; y: i64 = 2; z: i64 = 3; }
class User { constructor(public id: i64, public name: string) {} }
function sum(p: Ref<Point>): i64 { return p.x + p.y; }
function main() {
  const wide = { x: 1, y: 2, z: 3 };
  console.log(sum(wide), sum(new P3())); // expect: 3 3
  const p: Point = wide; // x and y are copied down, z is dropped
  const q: Point = new P3(); // no longer a P3
  console.log(p, q); // expect: { x: 1, y: 2 } { x: 1, y: 2 }
  const u: User = { id: 1, name: "ann" }; // a literal where a class is wanted builds one
  console.log(u, u instanceof User); // expect: User { id: 1, name: 'ann' } true
}
```

```fsh
class Animal { legs: i64 = 4; }
class Dog extends Animal { name: string = "rex"; }
function count(a: Animal): i64 { return a.legs; }
function main() { console.log(count(new Dog())); }
// error: error[E0704]: 'Dog' extends 'Animal' by embedding one, so it can't be used as 'Animal'; extract an interface both classes implement
```

- Two classes with the same fields don't fit each other: `error[E0101]: argument of type 'B' is
  not assignable to parameter of type 'A'`.
- An object held in a variable doesn't fit a class; only a literal builds one, and only when every
  field is public and given (`an object literal can't build 'P' because '#y' is private; use 'new'`).
- A private field isn't part of an instance's shape, a field's type must match exactly (`{ x: i64 }`
  doesn't fit `{ x: f64 }`), and a fresh literal with an unknown field is refused as in TypeScript.
  Objects print with their fields sorted by name, whatever order they were written in.

## 2. What fitting costs

Fitting is never a pointer cast. What happens instead is invisible in the source.

- **Copy down.** Storing a wider value as a narrower object type (a typed `const`, an assignment, a
  `return`) builds a new object from the fields the type names, nested fields included.
- **One function per shape.** A parameter typed with an object type or an interface is an implicit
  type parameter. `sum` above is compiled three times, once each for `Point`, the wide object and
  `P3` (`fishc build --emit-llvm` shows three `fsh.sum#...` definitions), each reading `x` where
  that shape keeps it. Code size grows with the number of shapes passed, not with calls.
- **Containers don't convert**, since each element would need copying: an array of
  `{ x: 1, y: 2, z: 3 }` given to a `Point[]` is `error[E0101]: type '{ x: i64; y: i64; z: i64 }[]'
  is not assignable to type '{ x: i64; y: i64 }[]'`. Type the literal where it is written, or
  build the narrow array with `map`.

## 3. Interfaces are satisfied by shape, and are not value types

A class, an object or an instance satisfies an interface by having its members. `implements` is
optional; written, it is checked (`error[E0702]: class 'Sq' incorrectly implements 'Shape': method
'area' is missing in type 'Sq' but required in type 'Shape'`). Interfaces extend interfaces only,
and a second `interface A` doesn't merge: `error[E0402]: duplicate type name 'A'`.

```fsh
interface Shape { area(): i64 }
class Sq { constructor(public side: i64) {} area(): i64 { return this.side * this.side; } }
class Rect implements Shape { constructor(public w: i64, public h: i64) {} area(): i64 { return this.w * this.h; } }
function twice(s: Shape): i64 { return s.area() * 2; } // compiled once per class passed
function main() {
  console.log(twice(new Sq(2)), twice(new Rect(2, 3))); // expect: 8 12
  const s: Shape = new Sq(3); // s is a Sq, checked against Shape
  console.log(s.area()); // expect: 9
}
```

An interface describes values without being one, so it is allowed only where the compiler can
see the one concrete type behind it: a parameter (one compiled copy per type), a local, and a
return type when every `return` gives the same type. Everywhere else it is refused:

| Written | Refusal |
| --- | --- |
| `class H { s: Shape }`, `type T = { s: Shape }` | `error[E0115]: a field can't have the interface type 'Shape'; use a type parameter instead` |
| `Shape[]` (a `Map` of them likewise) | `error[E0115]: an array can't hold the interface type 'Shape' directly, since its values may each be a different type; use 'Dyn<Shape>[]' to hold any of them` |
| `Shape \| null` | `error[E0115]: an interface can't be a union member; 'Shape' describes values without being one` |
| `id<Shape>(x)` | `error[E0115]: an interface can't be a type argument, since it describes values without being one` |
| `(s: Shape) => s.area()` | `error[E0801]: closure parameters of interface types are not supported yet` |
| `f(): Shape` returning `new Sq()` on one path and `new Ci()` on another | `error[E0101]: type 'Ci' is not assignable to return type 'Sq'` |
| `let s: Shape = new Sq(); s = new Ci()` | `error[E0101]: type 'Ci' is not assignable to type 'Sq'` |

**Fix**: one type per holder is a type parameter, `class Holder<S extends Shape> { constructor(public
s: S) {} }`; several types in one place is `Dyn<Shape>`.

## 4. `Dyn<I>` holds any value that implements an interface

`Dyn<Shape>` is the one type that means "some Shape, decided at run time". Making one moves the
value into a heap block and pairs it with a table of its methods; each call goes through the table.
It is an ordinary value type, so it can be a field, an element, a union member or a return type.

```fsh
interface Shape { name: string; area(): i64 }
class Sq { name: string = "sq"; constructor(public side: i64) {} area(): i64 { return this.side * this.side; } }
class Ci { name: string = "ci"; constructor(public r: i64) {} area(): i64 { return 3 * this.r * this.r; } }
function pick(big: boolean): Dyn<Shape> { if (big) return new Ci(10); return new Sq(1); }
function main() {
  const shapes: Dyn<Shape>[] = [new Sq(2), new Ci(1), pick(true)];
  let total = 0;
  for (const s of shapes) total += s.area();
  console.log(total, shapes[0].name); // expect: 307 sq
}
```

What a Dyn gives up, each one a wrong guess from TypeScript:

- It doesn't fit an interface-typed parameter. Passing a `Dyn<Shape>` to `twice(s: Shape)` is
  `error[E0101]: argument of type 'Dyn<Shape>' is not assignable to parameter of type 'Shape'`.
  Declare the parameter `Dyn<Shape>` or `Ref<Dyn<Shape>>`.
- No `instanceof`: `error[E0109]: a 'Dyn<Shape>' keeps no record of its value's class, so
  'instanceof' can't test it; add a method to the interface that says`.
- Fields are read through it, not written (`error[E0211]: writing a field through a Dyn isn't
  supported yet; change it through a method`), and `console.log(d)` is E0510.
- A method that changes its object must say so in the interface, as `bump(this: Mut<this>): void`,
  or the class is refused: `'C' can't be a 'Dyn<Counter>': its method 'bump' changes its object,
  which 'Counter' doesn't declare`.
- A method that is generic, or takes an interface or a function, has a version per argument type
  and so no table entry (E0211). Give it concrete parameter types or `Dyn` ones.
- `Dyn<T>` takes an interface only (`error[E0116]: 'Dyn' takes the interface its values implement,
  like 'Dyn<Handler>'`), and a `Dyn<A>` doesn't become a `Dyn<B>`. More: `examples/dyn.fsh`.

## 5. Object types with methods, optional methods, index signatures

**A `type` with a method member is an interface**, with every rule of section 3: it can't be a
field's type, `keyof` refuses it, and only a class can supply the method. For `{ area(): f64 }`
the literal `{ area: () => 4.0 }` is refused (`an object can't supply a method yet, so use a
class`), and a literal can't declare one (`error[E0801]: methods in object literals are not
supported yet`). A function-valued field, `{ area: () => f64 }`, is what a literal can fill.

**Optional methods** are called with `?.()`. A plain `h.onClose()` is `error[E0108]: 'onClose' may
be missing, since 'Handler' declares it optional; call it as 'h.onClose?.()', or check 'h.onClose
!== undefined' first`.

```fsh
type Area = { area: () => f64 };
interface Handler { name(): string; onClose?(): void }
class A { name(): string { return "a"; } onClose(): void { console.log("closed"); } }
class B { name(): string { return "b"; } }
function stop(h: Handler): string { h.onClose?.(); return h.name(); }
function show(s: Area): f64 { return s.area(); }
type Scores = { [name: string]: i64 };
function main() {
  console.log(stop(new B()), show({ area: () => 4.0 })); // expect: b 4
  console.log(stop(new A()));
  // expect: closed
  // expect: a
  let s: Scores = { ann: 3 };
  s.bo = 4;
  s["cy"] = 5;
  s.ann = (s.ann ?? 0) + 1; // 's.ann += 1' is refused: an entry is read as an Option
  console.log(s.ann, s.zz, "bo" in s, Object.keys(s)); // expect: 4 null true [ 'ann', 'bo', 'cy' ]
}
```

**Index signatures** (`Scores` above) make a dictionary: string keys only, no other members beside
the signature, and every read is an Option, as with `noUncheckedIndexedAccess`. `Record<string, V>`
is the same type; `Record<"a" | "b", V>` is a plain object with those two fields. A dictionary is
not a `Map`: no methods, no `for...of`; use `Object.keys`, `Object.values`, `Object.entries`.
More: `examples/index_signatures.fsh`, `examples/optionalmethods.fsh`.

## 6. Generics

Functions, classes, methods, arrows and aliases take type parameters, and each set of type
arguments is compiled as its own instance. Arguments are inferred from the call's arguments,
callbacks included, and from nothing else.

```fsh
class Box<T> {
  constructor(public value: T) {}
  get(): T { return this.value.clone(); } // 'return this.value' would move out of 'this' (E0202)
  map<U>(f: (x: Ref<T>) => U): Box<U> { return new Box(f(this.value)); }
  static of<U>(v: U): Box<U> { return new Box(v); } // a static can't use the class's T (E0706)
}
class Counter extends Box<i64> { constructor() { super(0); } }
function make<T>(): T[] { return []; }
const pair = <A, B>(a: A, b: B): [A, B] => [a, b];
function main() {
  const b = Box.of("ab").map((s) => s.length);
  console.log(b.get(), make<string>(), pair(1, "x"), new Counter().get()); // expect: 2 [] [ 1, 'x' ] 0
}
```

**Symptom**: `error[E0104]: can't infer a type for 'T'; pass the type arguments explicitly` on
`const xs: i64[] = make()`, or on `open(new IntBox())` for `open<T>(b: Box<T>)`.
**Why**: the type a result is assigned to is not used for inference, and neither is a generic
interface a class satisfies only by shape. **Fix**: `make<i64>()`, `open<i64>(new IntBox())`.

A bound is an interface, an object type, or a union, primitive, literal or brand type. A class is
not a bound (E0107), and built-ins don't satisfy object bounds: `string` does not satisfy
`{ length: usize }`. A union-bounded parameter narrows with `typeof`.

```fsh
interface Sized { size(): i64 }
function big<T extends Sized>(x: Ref<T>): boolean { return x.size() > 1; }
function label<T extends i64 | string>(x: T): string { return typeof x === "string" ? x : "#" + String(x); }
function main() {
  console.log(label(7), label("a")); // expect: #7 a
  console.log(big(5));
}
// error: error[E0107]: type 'i64' does not satisfy the constraint 'Sized': method 'size' is missing in type 'i64' but required in type 'Sized'
```

Refused, with the message to expect:

- An unbounded `T` has no members and no operators: `error[E0502]: property 'size' does not exist
  on type 'T'`, `error[E0103]: operator '+' cannot be applied to types 'T' and 'T'`.
- Conflicting inference: `error[E0104]: the type argument for 'T' can't be both 'i64' and 'boolean'`.
- An instance that needs a larger one of itself, as `grow([x], n - 1)` inside `grow<T>`:
  `error[E0113]: instantiating 'grow' never ends: each instance needs another with larger type arguments`.
- `<T = string>` is `error[E0801]: default type arguments are not supported yet`, and generic
  abstract classes are E0801 too. A generic function nested in another can't use the outer one's
  locals (E0409). More: `examples/generic.fsh`, `examples/generic_extends.fsh`, `examples/union_bounds.fsh`.

## 7. Unions and literal types

A union is a tagged value: a 32-bit tag saying which member it holds, then 64-bit words sized for
its largest member. Members can be primitives, literals, objects, classes, arrays, tuples, enums,
functions and `Dyn`s; not interfaces and not `Promise` (E0115). `undefined` is another spelling of
`null`, and `T | null` is the Option that `language.md` covers.

A string, number or boolean literal is a type; a `const` keeps its literal type and a `let` or an
object field widens, so a discriminant is written in the literal, not passed in from a `let`.

```fsh
type Dir = "up" | "down";
function flip(d: Dir): Dir { return d === "up" ? "down" : "up"; }
function main() {
  const d = "up";
  console.log(flip(d)); // expect: down
  let e = "up";
  console.log(flip(e));
}
// error: error[E0101]: argument of type 'string' is not assignable to parameter of type '"down" | "up"'
```

- A variable whose shape fits two members is refused: `error[E0109]: type '{ x: i64; y: i64 }'
  fits more than one member of '{ x: i64 } | { y: i64 }'`.
- A field every member has can be read without narrowing (its type is the union of the members'
  types), but not written until it is narrowed (E0109, `narrow it to one member first`).
- Members of other kinds share nothing: `x.length` on `string | i64[]` is `error[E0502]: property
  'length' does not exist on type 'string | i64[]'`.

## 8. Narrowing: what does and doesn't

These narrow a parameter, a `const`, a `let` (until its next assignment, and an assignment narrows
it too), and a field path such as `n.next` or `this.v`:

```fsh
type Shape = { kind: "circle"; r: i64 } | { kind: "square"; side: i64 };
type Node = { value: i64; next: Node | null };
class Dog { name: string = "rex"; }
class Cat { lives: i64 = 9; }
function area(s: Shape): i64 {
  if (s.kind === "circle") return 3 * s.r * s.r; // discriminant
  return s.side * s.side; // what is left after an early exit
}
function pet(p: Dog | Cat | null): string {
  if (p === null) return "none"; // equality with a literal or null
  return p instanceof Dog ? p.name : String(p.lives); // instanceof
}
function either(x: { a: i64 } | { b: string } | i64[]): string {
  return Array.isArray(x) ? "array" : "a" in x ? String(x.a) : x.b; // Array.isArray, 'in'
}
function second(n: Ref<Node>): i64 {
  if (n.next !== null) return n.next.value; // a field
  return -1;
}
function main() {
  let v: i64 | string = 1;
  if (typeof v === "number") v = "now a string"; // typeof, then an assignment
  console.log(v.length, area({ kind: "square", side: 2 }), pet(new Cat())); // expect: 12 4 9
  console.log(either({ b: "b" }), second({ value: 1, next: null })); // expect: b -1
}
```

`typeof` is only a comparison (`typeof x` as a value is `error[E0801]: operator 'typeof' is not
supported yet`) and only against `"number"` (every number type), `"boolean"`, `"string"`,
`"bigint"`, `"object"` and `"undefined"`. `typeof null` is `"undefined"`, not `"object"`.

What TypeScript narrows and Fish does not. Each leaves the value its whole union, so the error
is E0502 or E0101 at the use, as in `property 'value' does not exist on type '{ error: string; ok:
false } | { ok: true; value: i64 }'`:

| Written | Instead |
| --- | --- |
| `if (r.ok)`, `if (!r.ok)` on a boolean discriminant | `if (r.ok === true)` |
| `if (s)` on `string \| null` (E0102, no truthiness) | `if (s !== null)` |
| `const k = s.kind; if (k === "circle") s.r` | test `s.kind` itself |
| `const isNum = typeof x === "number"; if (isNum) x` | test in the `if` |
| `if (typeof xs[0] === "number") xs[0]` | `const x = xs[0];` then test `x` |
| `if (a === b)` with `b: i64`, to narrow `a: i64 \| string` | `typeof a === "number"` |
| `switch (s.kind)`: the `default:` branch and the code after the `switch` | `if`/`else if`/`else`, or `match` |
| a narrowed field after a call that could change it, `this.reset(); this.v.length` | test it again after the call |

## 9. Exhaustiveness

A `switch` narrows inside each `case` and proves nothing else: one that covers every member still
doesn't count as returning, and the `const n: never = s` trick fails because `default` isn't
narrowed.

```fsh
type Shape = { kind: "circle"; r: i64 } | { kind: "square"; side: i64 };
function area(s: Shape): i64 {
  switch (s.kind) { case "circle": return 3 * s.r * s.r; case "square": return s.side * s.side; }
}
// error: error[E0601]: not all code paths return a value
```

`match` is the exhaustive form: an expression whose missing member is an error that names it, as
in `error[E0607]: this match doesn't cover { kind: "square" }; add 'case { kind: "square" } =>', or
'case _ =>' for the rest`. An `if`/`else if`/`else` chain also works: its last branch is narrowed.
More: `examples/match.fsh`, `examples/discriminants.fsh`, `examples/narrowing_fields.fsh`.

## 10. `unknown`, no `any`, type predicates

There is no `any`, `object`, `Function`, `symbol` or `Object`: each is `error[E0105]: cannot find
type 'any'`. `unknown` exists and holds numbers, strings, booleans, null, objects, arrays and
instances (not functions); it is used only after `typeof`, `instanceof`, `=== null` or a
predicate, and `as` can't open it.

```fsh
class Dog { name: string = "rex"; }
function isText(x: Ref<unknown>): x is string { return typeof x === "string"; }
function show(x: Ref<unknown>): string {
  if (isText(x)) return "s:" + x;
  if (typeof x === "number") return "number";
  if (x instanceof Dog) return x.name;
  return "other";
}
function main() {
  const xs: unknown[] = ["a", 1.5, new Dog(), [1]];
  console.log(xs.map((x) => show(x)).join(" ")); // expect: s:a number rex other
}
```

A predicate narrows at the call, in both branches. Its parameter is a `Ref` unless the type
copies, or the call moves the value it tests. It doesn't change what `filter` returns
(`xs.filter(isText)` is still the array's own type), and `asserts x is T` is E0801 (`assertion
signatures are not supported yet`). More: `examples/unknown_type.fsh`, `examples/predicates.fsh`.

## 11. `as`, `satisfies`, `as const`, `!`

`as` never asserts something unchecked. It converts between number types, widens, makes a brand,
and takes one member out of a union with a run-time check. Everything else is `error[E0111]: 'as'
can't narrow '{ x: i64 }' to '{ x: i64; y: i64 }', since nothing would check it while the program
runs`: `s as "up" | "down"` on a `string`, `1 as Color` on an enum, the `as unknown as T` escape.
`<T>expr` is `error[E0801]: type assertions are not supported yet`.

`satisfies` checks without changing the type (`does not satisfy the expected type`). `as const`
gives literal and `readonly` types to a literal, and `(typeof NAMES)[number]` reads them back.
`x!` on an Option panics on `null` with ``called `Option::unwrap()` on a `None` value``; on a value
that is never null it is a silent no-op.

```fsh
const DIRS = ["up", "down"] as const;
type Dir = (typeof DIRS)[number];
type Cfg = { port: i64; host: string };
const cfg = { port: 80, host: "h" } satisfies Cfg;
function pick(n: i64): i64 | string { return n > 0 ? n : "none"; }
function main() {
  const d: Dir = "down";
  let m = new Map<string, i64>();
  m.set("a", 1);
  console.log(d, cfg.port, m.get("a")! + 1); // expect: down 80 2
  console.log(3.7 as i64, 300 as u8, pick(5) as i64); // expect: 3 44 5
  console.log(pick(0) as i64);
}
// panic: 'as i64' failed: union held another member
```

## 12. Tuples and `FixedArray`

A tuple is an object with fields named `0`, `1` and so on, not an array: no `push`, no array
methods, and an element is named by a number written in place. Optional elements read as an
Option; a rest element is allowed last, and not together with optional ones. An array literal is
a tuple only where a tuple type is expected: `const t = [1, "a"]` is an `(i64 | string)[]`, and an
`i64[]` never fits `[i64, i64]`.

```fsh
function minmax(xs: Ref<i64[]>): [i64, i64] { return [xs[0], xs[xs.length - 1]]; }
function main() {
  const t: [i64, string, boolean?] = [1, "a"];
  const r: [string, ...i64[]] = ["s", 1, 2];
  const [lo, hi] = minmax([1, 5]);
  console.log(t[1], t[2], t.length, r.length, lo, hi); // expect: a null 2 3 1 5
  let a: FixedArray<i64, 3> = [1, 2, 3];
  a[0] = 9;
  const zeros: FixedArray<i64, 4> = FixedArray.filled(0);
  let sum = 0;
  for (const x of a) sum += x;
  console.log(sum, a.length, zeros[3]); // expect: 14 3 0
}
```

With `const i = 0`, `t[i]` is `error[E0117]: a tuple's element is named by a number written in
place, like '[0]'; '[i64, string, boolean?]' has no element for a computed index`.
`FixedArray<T, N>`, in the same example, stores `N` elements inline (no heap block, at most 64
KiB), with `N` a number written in place. It indexes, loops and has `length`, has no array
methods, and doesn't fit `T[]`. More: `examples/tuple.fsh`, `examples/fixed.fsh`.

## 13. Brands, intersections, enums, `this`, recursive types

**Brands** are built in: `Brand<Base, "Tag">` over a number, boolean, string or bigint type. A
brand is made only with `as`, reads as its base, and never mixes with another brand. The
TypeScript idiom `i64 & { __brand: "Id" }` is read as the same thing, and `Unit<f64, "m/s">` does
the same for units (`examples/units.fsh`).

```fsh
type UserId = Brand<i64, "UserId">;
type OrderId = Brand<i64, "OrderId">;
function load(id: UserId): i64 { return id + 1; }
function main() {
  console.log(load(5 as UserId)); // expect: 6
  load(3 as OrderId); // a bare 'load(5)' is refused too: make one with 'as Brand<i64, "UserId">'
}
// error: error[E0101]: argument of type 'Brand<i64, "OrderId">' is not assignable to parameter of type 'Brand<i64, "UserId">'
```

**Intersections** join object types into one object type and interfaces into one interface.
With a class, a primitive (outside the brand idiom), a type parameter, or an interface with a
union, `&` is E0801; a field typed differently on each side is an error (E0114), not `never`.

**Enums** are nominal. A numeric member reads as an `i64` (`const n: i64 = Color.Green`) and a
string member prints as its string, but neither a number nor the literal `"low"` becomes the enum:
`error[E0101]: type '"low"' is not assignable to type 'Level'`. `Color[0]` is E0801, and `Mode.On`
is a type of its own. Members can also hold data, as Rust's do, read with `match` (`language.md`).

**`this` as a type** is allowed only in a class's instance methods. A chaining method says how it
holds the object: `add(this: Mut<this>, x: i64): Mut<this>` changes in place and lends it on,
`add(this: Own<this>, x: i64): this` takes the object and hands it back (`examples/this_type.fsh`).

**Recursive types** work through anything that can end: `T | null`, an array, a dictionary, a
union. `type List = { head: i64; tail: List | null }` and `type J = string | J[] | { [k: string]: J }`
both compile and need no `Box`. More: `examples/recursive.fsh`.

## 14. Type-level functions

They are computed while compiling, from concrete types. That is the one rule TypeScript habits
break: applied to a type parameter inside a generic function they are refused, `Partial<T>` and a
conditional type of `T` with the same message as `keyof T` below. A generic alias is fine, since
it is computed when it is given a concrete type: `type P<T> = Partial<T>`.

```fsh
function get<T, K extends keyof T>(o: Ref<T>, k: K): T[K] { return o[k]; }
// error: error[E0114]: 'keyof' of the type parameter 'T' isn't supported yet: it is computed while compiling, from a type known then
```

| Exists | Refused |
| --- | --- |
| `Partial`, `Required`, `Readonly`, `Pick`, `Omit`, `Record` | `Parameters`, `ThisType`, `NoInfer`, `ReadonlyMap` (E0105) |
| `Exclude`, `Extract`, `NonNullable`, `ReturnType`, `Awaited` | `InstanceType<typeof C>`, `ConstructorParameters<typeof C>`: a class isn't a value |
| `Uppercase`, `Lowercase`, `Capitalize`, `Uncapitalize` | `ReadonlyArray` (E0801) |
| `keyof T`, `T["k"]`, `T[number]`, `typeof topLevelConstOrFunction` | `typeof local`, `keyof` an interface, `typeof genericFn` |
| conditional types, `infer`, mapped types with `+?`/`-?`/`readonly`/`as` | conditional types of a type parameter, `infer` in a union |
| template literal types, finite (`` `${"a" \| "b"}-${1 \| 2}` ``) or patterns (`` `${number}px` ``) | pattern types in class fields and function types |

```fsh
type User = { id: i64; name: string; email?: string };
type Getters<T> = { [K in keyof T as `get${Capitalize<K>}`]: () => T[K] };
type ElementOf<T> = T extends (infer E)[] ? E : never;
function make() { return { id: 1, tags: ["a"] }; }
type Made = ReturnType<typeof make>;
function describe(u: Ref<User>, k: keyof User): string {
  return k === "id" ? String(u.id) : k === "name" ? u.name : u.email ?? "none";
}
function main() {
  const patch: Partial<User> = { name: "bo" };
  const card: Pick<User, "id" | "name"> = { id: 1, name: "ann" };
  const key: keyof Getters<User> = "getEmail";
  const e: ElementOf<Made["tags"]> = "tag";
  const u: User = { id: 7, name: "cy" };
  console.log(patch.name ?? "none", card.name, key, e, describe(u, "email")); // expect: bo ann getEmail tag none
}
```

A `keyof` value can't index an object at run time: `u[k]` is `error[E0120]: a computed key has to
be known while compiling`. Branch on the key, as `describe` does, or use a `Map`. An optional
field `name?: string` and a field `name: string | null` are the same type, read as `null` when
absent. More: `examples/types.fsh`.

## 15. Classes as types

`extends` embeds the base as the subclass's first field. Inherited members work and `instanceof`
of the base is true, but a subclass is never passed as its base (section 1) and nothing dispatches
virtually through `this`: if `Base.greet()` calls `this.name()` and `Kid` overrides `name`, that is
`error[E0704]: overriding 'name' is an error here: 'Base' reaches it through 'this', and with
'extends' as embedding that would still run 'Base.name'; extract an interface instead`. An
`abstract` class is the supported form: its abstract methods are called through `this`.

```fsh
abstract class Shape {
  constructor(public name: string) {}
  abstract area(): f64;
  describe(): string { return this.name + " " + String(this.area()); }
}
class Sq extends Shape {
  constructor(public side: f64) { super("sq"); }
  area(): f64 { return this.side * this.side; } // a missing 'area' is E0701
}
class Tally {
  static readonly LIMIT = 100; // a static field must be readonly (E0706)
  #pin: i64 = 1;
  private n: i64 = 0;
  get count(): i64 { return this.n; }
  set count(v: i64) { this.n = v; } // a setter may change 'this' without declaring it
  bump(this: Mut<this>) { this.n += this.#pin; } // without 'this: Mut<this>', E0206
}
function len(x: string): i64;
function len(x: i64[]): i64;
function len(x: string | i64[]): i64 { return (typeof x === "string" ? x.length : x.length) as i64; }
function main() {
  let t = new Tally();
  t.count = 4;
  t.bump();
  console.log(new Sq(2.0).describe(), t.count, Tally.LIMIT, len("abc"), len([1])); // expect: sq 4 5 100 3 1
}
```

- `function f(s: Shape)` with the abstract `Shape`: `error[E0701]: 'Shape' is an abstract class,
  which only exists embedded in its subclasses, so it can't be a value's type; describe what they
  share with an interface instead`. `new Shape()` is E0701 too.
- `private`, `protected` and `#x` are enforced (E0709). Parameter properties work; a default on
  one is E0801. Every field needs an initializer or a constructor assignment (E0703).
- Overloads need an implementation whose signature covers them; a call no signature takes is
  `error[E0507]: no overload of 'len' takes (boolean); its overloads are (x: string): i64, (x:
  i64[]): i64`. Constructor overloads and overloaded async functions are E0801, and an interface
  can't declare a method twice (E0402).
- A class is not a value: `const K = C` is `error[E0401]: classes can't be used as values yet;
  construct one with 'new'`, and `typeof C` and `new () => T` types are E0801.
- More: `examples/abstract.fsh`, `examples/extends.fsh`, `examples/access.fsh`, `examples/overloads.fsh`.

## 16. Function types

A function type is a value type: a named function, an arrow or a closure fits it, and it can be
a field, an element, a `Map` value or a union member. Parameters must match exactly (fewer is
fine, a narrower parameter type is not); the return type may be narrower.

```fsh
type Op = (a: i64, b: i64) => i64;
type Hooks = { n: i64; before?: () => void };
function add(a: i64, b: i64): i64 { return a + b; }
function apply(f: Op, a: i64, b: i64): i64 { return f(a, b); }
function run(h: Hooks): i64 { h.before?.(); return h.n; } // or check 'h.before !== null' first
function id<T>(x: T): T { return x; }
function main() {
  const k = 10;
  const ops: Op[] = [add, (a, b) => a * b, (a) => a + k];
  console.log(apply(add, 1, 2), ops[1](3, 3), ops[2](1, 0)); // expect: 3 9 11
  console.log(run({ n: 1 }), run({ n: 2, before: () => console.log("before") }));
  // expect: before
  // expect: 1 2
  const g: <T>(x: T) => T = id; // a generic function value: a local or a parameter, never a field
  console.log(g(1), g("a")); // expect: 1 a
}
```

- A function value is owned like any other: passing `f` to a parameter of type `Op` moves it, and
  `Ref<Op>` is `error[E0801]: references to functions are not supported yet`. Pass `f.clone()`.
- Not values yet (all E0801): a method (`c.get`), a function that `throws`, one with rest or
  defaulted parameters, an overloaded function. Wrap it: `(x) => c.get(x)`. Call signatures,
  `{ (x: i64): i64 }`, are E0801 too.
- A callback's parameter types are checked against what the caller passes: `xs.map((a: string) =>
  a)` on an `i64[]` is `error[E0506]: 'map' passes its callback an 'i64' here, not a 'string'`.
- More: `examples/function_value.fsh`, `examples/generic_value.fsh`, `examples/optional_function.fsh`.

## 17. The error codes for types, calls and classes

`fishc explain <code>` prints the long form; `errors.md` has every code.

| Code | Typical message | Fix |
| --- | --- | --- |
| E0101 | `type 'Ci' is not assignable to type 'Sq'`, `argument of type 'B' is not assignable to parameter of type 'A'`, `object literal may only specify known properties` | give the declared type; for a class, `new` it or share an interface; for a brand, `as` |
| E0104 | `can't infer a type for 'T'; pass the type arguments explicitly` | `f<i64>()`, `const xs: string[] = []` |
| E0107 | `type 'i64' does not satisfy the constraint 'Sized'` | pass a type with the members, or loosen the bound |
| E0108 | `'onClose' may be missing, since 'Handler' declares it optional`; `'?.' reads through an Option, and this is a '"a"', which is never empty; use '.'` | check or `?.`; drop a needless `?.` |
| E0109 | `can't assign to 'n' through '{ kind: "a"; n: i64 } \| { kind: "b"; n: i64 }'; narrow it to one member first` | narrow, then write |
| E0111 | `'as' can't narrow 'unknown' to 'i64', since nothing would check it while the program runs`; `operator '+' can't mix 'i64' and 'number'` | narrow with a check; convert numbers with `as` |
| E0114 | `'keyof' of the type parameter 'T' isn't supported yet` | apply it to a concrete type, or use an alias |
| E0115 | `a field can't have the interface type 'Shape'; use a type parameter instead` | a type parameter, or `Dyn<Shape>` |
| E0501 | `expected 2 arguments, but got 1` | pass them; `x?: T` may be left out, `x: T \| null` may not |
| E0502 | `property 'nam' does not exist on type '{ name: string }'; did you mean 'name'?` | fix the name, or narrow the union first |
| E0510 | `printing a function isn't supported yet` | print a field or a method's result |
| E0701 | `cannot create an instance of the abstract class 'Shape'`; `class 'Triangle' must implement the abstract method 'area' of 'Shape'` | construct a subclass; implement the member |
| E0704 | `'Dog' extends 'Animal' by embedding one, so it can't be used as 'Animal'` | an interface both implement, or an abstract base |
| E0706 | `a static field that isn't 'readonly' would be a global that changes` | `static readonly`, or hold an `Atomic` or a `Lock` |
| E0709 | `property 'bal' is private and only accessible within class 'Acct'` | a public method or accessor |
