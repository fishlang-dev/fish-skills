# Gotchas: symptom, why, fix

The index to search when `fishc` or a running program says something you did not expect. Entries
are keyed by what you see: the error text with its code, a panic message, or a wrong output. Each
gives the cause and the fix and names the slice that explains the area. They come from writing
ordinary TypeScript-style and Rust-style programs and recording every stumble. Sections 9 and 10
list the forms the compiler parses and then refuses. Every code has a longer explanation in
`errors.md` and from `fishc explain E0201`. Checked against fishc 0.1.1.

## 1. Values and conditions

**`error[E0102]: condition must be a boolean, not 'i64'; compare explicitly, e.g. 'n !== 0'`**
(for `!s`: `error[E0103]: operator '!' cannot be applied to type 'string'`)
**Why**: there is no truthiness: `if`, `while`, `?:`, `!`, `&&` and `||` take only `boolean`.
**Fix**: compare: `n !== 0`, `s !== ""`, `xs.length > 0`. More: `language.md`.
```fsh
function main() { const n = 3; if (n) console.log("yes"); }
// error: error[E0102]: condition must be a boolean, not 'i64'; compare explicitly, e.g. 'n !== 0'
```

**`error[E0103]: operator '||' cannot be applied to types 'i64 | null' and 'i64'`**
**Why**: `||` is boolean-only, so `x || fallback` is not a default. **Fix**: `??` when the left
side may be null; for an empty string, `s === "" ? fallback : s`.
```fsh
function main() { let m = new Map<string, i64>(); m.set("a", (m.get("a") || 0) + 1); }
// error: error[E0103]: operator '||' cannot be applied to types 'i64 | null' and 'i64'
```

**Wrong output: `7 / 2` prints `3`**, and
`error[E0101]: argument of type 'i64[]' is not assignable to parameter of type 'number[]'`,
`error[E0111]: operator '+' can't mix 'i64' and 'number'; convert one side with 'as', like 'x as i64'`
**Why**: an integer literal is an `i64`, and `/` on integers truncates. `number` is `f64`, a
separate type, and nothing converts implicitly: `const xs = [1, 2]` is an `i64[]`, and
`Math.floor` refuses an `i64`. **Fix**: float literals (`7.0 / 2.0`), an annotation
(`const xs: number[] = [1, 2]`), or `as f64`. Use `i64` for counts and `number` for real floats.
```fsh
function mean(xs: number[]): number { return xs.reduce((a, b) => a + b, 0.0) / (xs.length as number); }
function main() { const xs = [1, 2, 3]; console.log(mean(xs)); }
// error: error[E0101]: argument of type 'i64[]' is not assignable to parameter of type 'number[]'
```

**`error[E0101]: argument of type 'usize' is not assignable to parameter of type 'i64'; convert it with 'as i64'`**
(the other way: `an array's index is a 'usize', not 'i64'; convert it with 'as usize'`), and the
**panic `attempt to subtract with overflow`** on `xs.length - 1`
**Why**: `.length` and indexes are `usize`, which has no negatives, and an unannotated integer
`let` takes its type from its uses: a counter compared with `.length` becomes `usize` (one used
as a `**` exponent, `u32`). Integer overflow panics in debug builds, and integer division by zero
in every build (`attempt to divide by zero`). **Fix**: convert where the two meet
(`(xs.length as i64) - 1`), or annotate the counter (`let i: i64 = 0`).
```fsh
function main() { const s = "hello"; let i = 0; while (i < s.length) i++; console.log(s.slice(0, i)); }
// error: error[E0101]: argument of type 'usize' is not assignable to parameter of type 'i64'
```
```fsh
function main() { const xs: i64[] = []; console.log(xs.length - 1); }
// panic: attempt to subtract with overflow
```

**Panic: `index out of bounds: the len is 3 but the index is 5`**
**Why**: `xs[i]` is a `T`, never `undefined`, so a bad index stops the program (strings too).
**Fix**: test the length first, or use `xs.at(i)`, which gives `T | null`.
```fsh
function main() { const xs = [1, 2, 3]; console.log(xs[5]); }
// panic: index out of bounds: the len is 3 but the index is 5
```

**`error[E0404]: a top-level 'let' would be a global that changes; use 'const', whose value is computed while compiling, or a const holding an Atomic or a Lock`**
(a top-level `const` collection: `error[E0212]: 'set' changes its Map, so call it on a variable or a field`;
a class: `error[E0706]: a static field that isn't 'readonly' would be a global that changes`)
**Why**: there are no mutable globals. **Fix**: own the state in `main` and pass it as `Mut<T>`
(section 3), or keep a counter in a top-level `const hits = new Atomic<i64>(0)`.
```fsh
const cache = new Map<i64, i64>();
function remember(n: i64) { cache.set(n, n * n); }
// error: error[E0212]: 'set' changes its Map, so call it on a variable or a field
```

**`error[E0112]: values of type 'P' can't be compared with '===': a class compares through 'equals(other: Ref<this>): boolean', which 'P' doesn't have; add one, or '@derive(Eq)'`**
**Why**: `===` compares values, not identity: two object literals or arrays with equal contents
are `===`. A class has to say how. **Fix**: `@derive(Eq)` (`meta.md`). Printing has the same
gap: `error[E0502]: 'i64' has no method 'toString'` (use `String(n)` or a template), and a
template refuses an instance (E0510). The fixes of this section, together:
```fsh
@derive(Eq)
class P { constructor(public x: i64) {} }
function main() {
  const n = 3;
  let xs: i64[] = n !== 0 ? [n] : [];
  if (xs.length > 0) console.log(7 / 2, 7.0 / 2.0, (7 as f64) / 2.0, (xs.length as i64) - 2, xs.at(5), String(n) + "!");
  // expect: 3 3.5 3.5 -1 null 3!
  console.log(new P(1) === new P(1), { a: 1 } === { a: 1 }, [1, 2] === [1, 2]); // expect: true true true
}
```

## 2. Absence

**`error[E0102]: condition must be a boolean, not the Option 'null | string[]'; check it with '!== null'`**
**Why**: `T | null`, `T | undefined` and an optional `x?: T` are one type, an Option, whose empty
value prints `null` and equals both `null` and `undefined`. It is not a condition, and a `let`
declared without a value does not start out empty (E0205). **Fix**: `!== null`, which narrows.
```fsh
type Config = { host: string; tags?: string[] };
function main() { const c: Config = { host: "h" }; if (c.tags) console.log(c.tags.length); }
// error: error[E0102]: condition must be a boolean, not the Option 'null | string[]'; check it with '!== null'
```

**`error[E0108]: operator '+' can't use the Option 'i64 | null' until it is checked; check it with '!== null' first, or give a default with '??'`**
**Why**: where JavaScript answers `NaN` or `undefined`, Fish answers with an Option: `parseInt`,
`parseFloat`, `Number(text)`, `Map.get`, `pop`, `find`, `at`. There is no global `isNaN`
(`error[E0401]: unknown function 'isNaN'`); test `=== null`.
```fsh
function main() { console.log(parseInt("12") + 1); }
// error: error[E0108]: operator '+' can't use the Option 'i64 | null' until it is checked
```

**Panic: ``called `Option::unwrap()` on a `None` value``**
**Why**: `x!` is checked when the program runs; it is `unwrap`, not a compile-time assertion.
**Fix**: keep `!` for what you have just proven; otherwise `?? fallback` or a `!== null` test.
```fsh
function main() { const m = new Map<string, i64>(); console.log(m.get("a")!); }
// panic: called `Option::unwrap()` on a `None` value
```

**`error[E0101]: type 'null | i64[]' is not assignable to type 'i64[]'`** on `m.get(k) ?? []`
**Why**: a bare `[]` has no element type, and `??` doesn't give it one. `[] as i64[]` is refused
too (E0111, `'never[]' can't be converted to 'i64[]' with 'as'`), as is `new Array<i64>()` (E0104).
**Fix**: name a typed empty array: `const none: i64[] = [];`, then `m.get(k) ?? none`.
```fsh
function main() { const m = new Map<string, i64[]>(); const list: i64[] = m.get("a") ?? []; }
// error: error[E0101]: type 'null | i64[]' is not assignable to type 'i64[]'
```

**`error[E0502]: 'i64 | null' has no method 'unwrap_or'`** (and `error[E0401]: unknown function 'Some'`)
**Why**: `Option<T>` is another spelling of `T | null`: a present value is the value itself, the
empty one is `null`, and there are no Option methods. **Fix**: `??` for `unwrap_or`, `!` for
`unwrap`, a `!== null` test for `if let`, and `match` with `case Some(v)` and `case None`. There
is no `Result` either (`error[E0105]: cannot find type 'Result'`): a function declares `throws E`
(`errors-async.md`). The fixes of this section, together:
```fsh
function first(xs: Ref<i64[]>): Option<i64> { return xs.length > 0 ? xs[0] : null; }
function main() {
  const none: i64[] = [];
  let list = new Map<string, i64[]>().get("a") ?? none;
  list.push(4);
  let file: string | null = null;
  const found = match (first(list)) { case Some(v) => v * 10, case None => 0 };
  console.log(list, file === undefined, (parseInt("12") ?? 0) + 1, Number("x"), found);
  // expect: [ 4 ] true 13 null 40
}
```

## 3. Ownership

**`error[E0201]: 'xs' was moved, so it can't be used here`**, with the note
`'xs' moved here: passing it to 'total' hands it over, as if 'total' kept it; pass 'xs.clone()' to keep a copy`
**Why**: an array, object, Map, Set or instance has one owner, and a parameter typed `T` takes
it. `const b = a` and `[p, p]` move the same way. Strings, numbers and booleans copy.
**Fix**: a function that only reads takes `Ref<T>`; the call stays `total(xs)`. Clone only when
a second copy is really wanted. More: `ownership.md`.
```fsh
function total(xs: i64[]): i64 { let t = 0; for (const x of xs) t += x; return t; }
function main() { const xs = [1, 2]; console.log(total(xs), total(xs)); }
// error: error[E0201]: 'xs' was moved, so it can't be used here
```

**`error[E0206]: cannot assign to 'this.n' because 'this' is read-only here; declare 'this: Mut<this>'`**
(a parameter: `error[E0206]: cannot push to 'xs' because 'xs' is a shared reference ('Ref'), which only reads`)
**Why**: a method borrows `this` read-only, and a `Ref<T>` only reads. What changes its target
says `Mut`: `inc(this: Mut<this>)`, `fill(out: Mut<i64[]>)`. A plain `T` parameter changes its
own value and leaves the caller's moved, which is where TypeScript's accumulator-parameter
pattern ends (E0201, `(in an earlier pass through this loop)`). The caller's binding must be a
`let`, since `const` is deep: `error[E0207]: cannot call 'inc' on 'c' because it is a constant`,
`error[E0207]: cannot push to 'xs' because it is a constant`.
```fsh
class Counter { n: i64 = 0; inc() { this.n++; } }
// error: error[E0206]: cannot assign to 'this.n' because 'this' is read-only here; declare 'this: Mut<this>'
```

**`error[E0202]: 'this.items' can't be moved out of 'this', since it is only borrowed here; use 'this.items.clone()'`**
(an element: `'xs[0]' can't be moved out of its array; use 'xs[0].clone()' to take a copy, or 'pop()' to take the last element out`)
**Why**: returning or binding a field or element by value would take it from its owner.
**Fix**: return `Ref<T>` to lend it, or clone.
```fsh
class Box { items: string[] = []; all(): string[] { return this.items; } }
// error: error[E0202]: 'this.items' can't be moved out of 'this', since it is only borrowed here
```

**`error[E0203]: cannot change 'xs' while a 'for...of' loop is reading 'xs'`** (the element:
`error[E0206]: cannot assign to 'a.n' because 'a' is a shared reference ('Ref'), which only reads`)
**Why**: `for...of` lends the array and each element read-only. **Fix**: loop by index
(`xs[i].n++` works), or collect the changes and apply them after the loop.
```fsh
function main() { let xs = [1, 2, 3]; for (const x of xs) { if (x === 2) xs.push(4); } }
// error: error[E0203]: cannot change 'xs' while a 'for...of' loop is reading 'xs'
```

**Wrong output: a change to what `map.get(k)` gave is lost**, and
`error[E0212]: 'push' changes its array, so call it on a variable or a field` (also for `[...xs].sort(cmp)`)
**Why**: `get` gives a copy of the value, not a view into the Map, and a changing method on a
temporary would change nothing that lasts. **Fix**: change the copy, then `set` it back; for a
sorted copy, `xs.toSorted(cmp)`. (`sort()` with no comparator orders numbers numerically.)
```fsh
function main() {
  let groups = new Map<string, i64[]>();
  groups.set("a", [1]);
  let list = groups.get("a")!;
  list.push(2);
  console.log(groups.get("a")); // expect: [ 1 ]
  groups.set("a", list);
  console.log(groups.get("a")); // expect: [ 1, 2 ]
}
```
```fsh
function main() { let groups = new Map<string, i64[]>(); groups.set("a", [1]); groups.get("a")!.push(2); }
// error: error[E0212]: 'push' changes its array, so call it on a variable or a field
```

**`error[E0210]: this closure changes 'n', which it captures, but a stored callable can't change what it captures; keep that state in an 'Atomic' or a 'Lock'`**
(or `this closure borrows 'count', but a stored callable owns what it captures; write the closure where it is stored, so it captures by move, or as 'move (...) => ...'`)
**Why**: a closure handed straight to the call that runs it (`forEach`, `map`) may read and
change locals. One that is returned or stored (a listener, a memoiser) must own its captures and
can't change them. **Fix**: `move`, with the state in an `Atomic`, or in a `shared` value when
several closures need it (an `Rc` is refused, E0303, since a stored callable may cross threads).
A function passed by name to an array method must take the elements as `Ref<T>` (E0506).
```fsh
function counter(): () => i64 { let n = 0; return () => { n++; return n; }; }
// error: error[E0210]: this closure changes 'n', which it captures, but a stored callable can't change what it captures
```

**`error[E0001]: expected an expression, found '&'`** (Rust habit), and a silent trap
**Why**: there are no borrow operators: no `&x`, `&mut x`, `*x`. The parameter's type decides and
the argument is written plain. The trap: `&T` in a type position parses (as an intersection with
a leading `&`) and means plain owned `T`, so `len` below takes ownership.
```fsh
function len(s: &string[]): usize { return s.length; }
function main() { const xs = ["a"]; console.log(len(xs), len(xs)); }
// error: error[E0201]: 'xs' was moved, so it can't be used here
```

The fixes of this section, together:
```fsh
type Item = { n: i64 };
class Box {
  items: Item[] = [];
  add(this: Mut<this>, n: i64) { this.items.push({ n }); }
  all(): Ref<Item[]> { return this.items; }
}
function step(sum: i64, item: Ref<Item>): i64 { return sum + item.n; }
function total(xs: Ref<Item[]>): i64 { return xs.reduce(step, 0); }
function fill(out: Mut<i64[]>, n: i64) { out.push(n); }
function counter(): () => i64 { const n = new Atomic<i64>(0); return move () => n.add(1) + 1; }
function main() {
  let box = new Box();
  for (const n of [1, 2]) box.add(n);
  for (let i = 0; i < box.items.length; i++) box.items[i].n++;
  let out: i64[] = [3];
  fill(out, 1);
  const next = counter();
  console.log(total(box.all()), total(box.all()), out.toSorted((a, b) => a - b), next(), next());
  // expect: 5 5 [ 1, 3 ] 1 2
}
```

## 4. Types

**`error[E0502]: property 'value' does not exist on type '{ error: string; ok: false } | { ok: true; value: i64 }'`**
**Why**: a union's member is reached only after narrowing, and a bare boolean discriminant
(`if (r.ok)`, `r.ok ? a : b`) does not narrow. **Fix**: compare with the literal, `r.ok === true`.
`typeof x === "string"`, `!== null`, `instanceof` and `x.kind === "a"` narrow as in TypeScript.
```fsh
type Res = { ok: true; value: i64 } | { ok: false; error: string };
function show(r: Res) { if (r.ok) console.log(r.value); }
// error: error[E0502]: property 'value' does not exist on type
```

**`error[E0601]: not all code paths return a value`** after a `switch` that covers every case
**Why**: a `switch` is not checked for exhaustiveness. (A Rust-style body ending in a bare
expression, `{ a + b }`, gets the same error: write `return`.) **Fix**: make the last case
`default:`, or use `match`, which must cover every case (E0607) and is an expression.
```fsh
enum State { Idle, Busy }
function label(s: State): string { switch (s) { case State.Idle: return "idle"; case State.Busy: return "busy"; } }
// error: error[E0601]: not all code paths return a value
```

**`error[E0104]: can't infer a type for 'T'; pass the type arguments explicitly`**
(a different E0104: `'depth' needs a return type annotation because it calls itself`)
**Why**: type arguments are inferred from the arguments only, never from the type the result is
assigned or returned to. So `req.json()`, and helpers like `ok(v)` and `err(e)` of a hand-rolled
`Result<T, E>`, need them written. **Fix**: `fail<i64>(...)`, `req.json<{ name: string }>()`.
```fsh
type Res<T> = { ok: true; value: T } | { ok: false; error: string };
function fail<T>(error: string): Res<T> { return { ok: false, error }; }
function parse(s: string): Res<i64> { return fail("not a number: " + s); }
// error: error[E0104]: can't infer a type for 'T'; pass the type arguments explicitly
```

**`error[E0111]: 'as' can't narrow 'unknown' to 'string', since nothing would check it while the program runs; narrow it with a check, like 'typeof', 'instanceof' or '!== null'`**
(and `error[E0105]: cannot find type 'any'`)
**Why**: there is no `any`, and `as` converts between number types and widens; it never asserts.
**Fix**: a union, a type parameter, or `unknown` narrowed by a check. More: `types.md`.
```fsh
function main() { const x = 1 as unknown as string; }
// error: error[E0111]: 'as' can't narrow 'unknown' to 'string'
```

**`error[E0509]: values of type 'Config' can't be read from JSON: it has no JSON form`**
(and `error[E0111]: 'Json' can't be converted to 'Config' with 'as', since neither fits the other`)
**Why**: `JSON.parse<T>(text)` decodes and validates into `T`, which must be a `type` of objects,
arrays, unions and primitives, or a class with `@derive(Json)`; an `interface` is neither. Plain
`JSON.parse(text)` gives a `Json` value that `as` cannot turn into your type. **Fix**: declare
the shape with `type` and pass it as the type argument. A missing field then throws `JsonError`
and unknown keys are dropped. More: `std.md`.
```fsh
interface Config { host: string }
function load(text: string): Config throws JsonError { return JSON.parse<Config>(text); }
// error: error[E0509]: values of type 'Config' can't be read from JSON: it has no JSON form
```

## 5. Classes

**`error[E0704]: 'Dog' extends 'Animal' by embedding one, so it can't be used as 'Animal'; extract an interface both classes implement`**,
`error[E0701]: 'Shape' is an abstract class, which only exists embedded in its subclasses, so it can't be a value's type; describe what they share with an interface instead`,
`error[E0115]: an array can't hold the interface type 'HasArea' directly, since its values may each be a different type; use 'Dyn<HasArea>[]' to hold any of them`
**Why**: `extends` shares code, not a type: a subclass is not a value of its base, so there is no
`Animal[]` of mixed subclasses and `instanceof Dog` narrows nothing on an `Animal`. An interface
as a parameter type makes the function generic. **Fix**: for values of mixed classes, an
interface and `Dyn<I>`, in arrays, fields and return types. More: `types.md`.
```fsh
class Animal { speak(): string { return "..."; } }
class Dog extends Animal { speak(): string { return "woof"; } }
function main() { const zoo: Animal[] = [new Dog(), new Animal()]; }
// error: error[E0704]: 'Dog' extends 'Animal' by embedding one, so it can't be used as 'Animal'
```
```fsh
interface Speaks { speak(): string }
class Cat { speak(): string { return "meow"; } }
class Dog { speak(): string { return "woof"; } }
function main() { const zoo: Dyn<Speaks>[] = [new Dog(), new Cat()]; console.log(zoo.map((a) => a.speak())); }
// expect: [ 'woof', 'meow' ]
```

## 6. Async

**`error[E0302]: this Promise does nothing until it's awaited, since Fish's promises are lazy; add 'await', or wrap the call in 'spawn(...)' for fire-and-forget`**
**Why**: calling an async function runs none of it. After `const p = work()`, the code that
follows runs first; the body starts at `await p`. A `Channel`'s `send` is one too (`errors-async.md`).
```fsh
async function save(n: i64): Promise<void> { console.log("saved", n); }
async function main() { save(1); }
// error: error[E0302]: this Promise does nothing until it's awaited, since Fish's promises are lazy
```

**Wrong output: a spawned task's work never happens**
**Why**: the program ends when `main` returns, whatever is still running. **Fix**: keep the
`JoinHandle` that `spawn` returns and `await` it, as the next entry does.
```fsh
async function work(): Promise<void> { await sleep(20); console.log("done"); }
async function main() { spawn(work()); console.log("main ends"); }
// expect: main ends
```

**`error[E0502]: 'Promise<i64>' has no method 'then'`**, and
`error[E0801]: 'map' with a callback giving a Promise isn't supported yet; await each value in a 'for...of' loop instead`,
`error[E0305]: 'await' needs a Promise, like an async function's call, not 'Ref<JoinHandle<void>>'`
**Why**: a Promise is only awaited (inside an `async` function, `main` included, or E0301);
there are no `then` chains, and array methods take no async callbacks. **Fix**: in order, `await`
inside `for...of`. At once, `spawn` each and await the handles by taking them out of the array
(a `for...of` over them only lends each), or `await Promise.all([a(), b()])`.
```fsh
async function work(n: i64): Promise<i64> { await sleep(1); return n * n; }
async function main() {
  let handles: JoinHandle<i64>[] = [];
  for (const n of [1, 2, 3]) handles.push(spawn(work(n)));
  let sum = 0;
  while (handles.length > 0) { const v = await handles.pop()!; sum += v; }
  const [a, b] = await Promise.all([work(2), work(3)]);
  console.log(sum, a, b); // expect: 14 4 9
}
```

**`error[E0602]: 'load' must declare 'throws JsonError' after its return type since 'JSON.parse' can throw 'JsonError', or catch it with try/catch`**
**Why**: what a function can throw is part of its type, `main` included. The reverse is an error
too: `error[E0603]: nothing in this 'try' can throw, so its 'catch' never runs; remove the try/catch`.
`catch (e)` takes no annotation (E0004); `e` already has the type the `try` can throw. An error
that leaves `main` is not a panic: stderr gets `Error: [Error: boom]` and the exit code is 1, not 101.
```fsh
type Config = { host: string };
function load(text: string): Config { return JSON.parse<Config>(text); }
// error: error[E0602]: 'load' must declare 'throws JsonError' after its return type since 'JSON.parse' can throw 'JsonError'
```

**`error[E0801]: functions that throw used as values are not supported yet`**, and
`error[E0801]: function types giving a Promise that throw are not supported yet`,
`error[E0101]: argument of type '() => Promise<i64>' is not assignable to parameter of type '() => Promise<T>'`
**Why**: these are what a generic `retry(fn)` helper needs, and none is there yet: a callback
type can't be async and throwing, and a `() => Promise<T>` parameter with `T` a type parameter
accepts no async function. **Fix**: write the helper for a concrete type, and have the callback
catch and answer `null`:
```fsh
async function flaky(): Promise<string> throws Error { throw new Error("down"); }
async function attempt(): Promise<string | null> { try { return await flaky(); } catch (e) { return null; } }
async function retry(fn: () => Promise<string | null>, attempts: i64): Promise<string | null> {
  for (let i: i64 = 0; i < attempts; i++) {
    const r = await fn();
    if (r !== null) return r;
    await sleep(2 ** (i as u32));
  }
  return null;
}
async function main() { const r = await retry(attempt, 3); console.log(r); }
// expect: null
```

**`error[E0210]: this async arrow changes 'store', which it captured, but each call's future works on its own copy, so the change would be lost; keep that state in an 'Atomic' or a 'Lock'`**
**Why**: a `serve` handler runs once per request, on any thread; it can't write a local of `main`.
A handler that throws is refused as well (E0602, `catch it inside the closure with try/catch`).
**Fix**: state shared between requests lives in a `shared<T>` and changes inside `update`:
```fsh
type User = { id: i64; name: string };
type Store = { users: User[]; nextId: i64 };
async function main() throws IoError {
  const store = shared<Store>({ users: [], nextId: 1 });
  await serve({ port: 3000 }, async (req) => {
    try {
      if (req.method !== "POST") return Response.json(store.update((s) => s.users.clone()));
      const body = await req.json<{ name: string }>();
      const user = store.update((s) => { s.users.push({ id: s.nextId++, name: body.name }); return s.users.at(-1)!.clone(); });
      return Response.json(user, { status: 201 });
    } catch (e) {
      return new Response("bad request", { status: 400 });
    }
  });
}
```

**`error[E0305]: an async function's return type is 'Promise<T>', the type of what it gives once awaited`**
on an async arrow, inside a function, whose return type is already written `Promise<T>`
**Why**: a local async arrow accepts no return annotation in this release. **Fix**: drop it; the
type is inferred. (Top-level `const f = async (n: i64): Promise<i64> => ...` is accepted.)
```fsh
async function main() { const load = async (n: i64): Promise<i64> => n * 3; const v = await load(2); }
// error: error[E0305]: an async function's return type is 'Promise<T>'
```

## 7. Std and modules

**`error[E0908]: 'http' is a Node module Fish's std doesn't have yet`** (also `events`; for
CommonJS, `error[E0401]: unknown function 'require'`; for npm, `error[E0902]: can't find the package 'lodash'`)
**Why**: only some Node modules exist (`fs`, `path`, `os`, `child_process` and more, under bare
or `node:` names), imported with ES imports only. HTTP is built in: `serve`, `Router`, `fetch`,
`Request` and `Response` are globals, as are `sleep`, `spawn` and `Channel`. Check `std-api.md`
before importing; npm packages are `interop.md`.
```fsh
import { createServer } from "http";
// error: error[E0908]: 'http' is a Node module Fish's std doesn't have yet
```

**`error[E0502]: 'Date' has no method 'getFullYear'; did you mean 'getUTCFullYear'?`**
**Why**: there is no local time and no date parsing. A `Date` is made from milliseconds
(`new Date(ms)`, `Date.now()`) and read through the `getUTC*` methods and `toISOString()`. The
other constructors and `Date.parse` are E0801 (section 9). Std has most, not all, of JavaScript's
methods; a missing one reads `strings have no method 'localeCompare' yet`, and a Rust name gets
the same wording (`arrays have no method 'len' yet`), so look the type up in `std-api.md`.
```fsh
function main() { console.log(new Date(0).getFullYear()); }
// error: error[E0502]: 'Date' has no method 'getFullYear'; did you mean 'getUTCFullYear'?
```

## 8. Tooling

**`fishc check` never returns.** Seen with one shape in this release: a `let` with two
declarators, one of them a `usize`, followed by a type error in the same function. **Fix**: stop
it and write one declarator per `let`; the real error (here E0101, a `usize` returned as `i64`)
is then reported.
```fsh fragment
function mid(xs: i64[]): i64 {
  let lo = 0, hi = xs.length;   // write: let lo = 0; let hi = xs.length;
  const m = lo + hi;
  return m;
}
```

**A fix brings new errors.** Errors are found in passes: a syntax error comes alone; type errors
come several at once, ending `error: could not compile due to 2 previous errors`; use-after-move
and borrow errors (E0201, E0203) are reported only once the types check, and then one at a time.
Move errors after a clean type check are the normal next round, not a regression. Warnings
(`warning[W0001]: unused variable 'unused'; if it's intentional, name it '_unused'`) never fail a build.

## 9. Not supported yet (E0801)

Forms the release parses and then refuses, each seen refused with exactly this text after
`error[E0801]: `. Many more refusals concern references held in particular places (`ownership.md`).

| You wrote | Message | Write instead |
| --- | --- | --- |
| `for (const k in o)` | `'for...in' loops are not supported yet` | `for (const k of Object.keys(o))` |
| `typeof x` as a value | `operator 'typeof' is not supported yet` | fine inside a test: `typeof x === "string"` |
| `delete o.a` | `operator 'delete' is not supported yet` | a `Map` and `m.delete(k)` |
| `x ??= 1` | `operator '??=' is not supported yet` | `x = x ?? 1` |
| `i++, j++`, Rust's `(1, "a")` | `comma expressions are not supported yet` | two statements; a tuple is `[1, "a"]` |
| `function (x) { }` as a value | `function expressions are not supported yet` | an arrow |
| `namespace Util { }` | `namespaces are not supported yet` | top-level names in a file of their own |
| `await import("m")` | `dynamic imports are not supported yet` | a static `import` |
| `import fs = require("fs")` | `'import fs = ...' isn't supported yet; import what you use with 'import { a, b } from "./file"'` | as it says |
| `<i64>x` | `type assertions are not supported yet` | `x as i64` |
| `Color[0]`, `m.get(k)?.[0]` | `indexed access expressions are not supported yet` | a string enum; test `!== null`, then index |
| `xs?.map(f)`, `xs?.join(",")` | `optional chains calling array methods are not supported yet` | test `!== null` first |
| `const g = p.get` | `methods can't be used as values yet; call it` | `() => p.get()` |
| `{ f() { } }` | `methods in object literals are not supported yet` | `{ f: () => ... }` |
| `{ get n() { } }` | `accessors in object literals are not supported yet` | a field, or a class |
| `interface A { get n(): i64 }` | `accessors in object types are not supported yet` | a method or a field |
| class field `get = () => this.x` | `functions stored in fields are not supported yet` | a method |
| `(...xs: i64[]) => 0` | `rest parameters on arrow functions are not supported yet` | a `function` with the rest parameter |
| `function f<T = string>()` | `default type arguments are not supported yet` | pass the argument |
| `x!: i64` in a class | `definite assignment assertions are not supported yet` | an initializer, or `i64 \| null` |
| two `constructor(...)` signatures | `constructor overloads are not supported yet` | static factory methods |
| `abstract n: i64` | `abstract fields are not supported yet` | `abstract get n(): i64` |
| `C: new () => T` | `constructor types are not supported yet` | a factory parameter, `() => T` |
| top-level `const { a, b } = o` | `destructuring top-level consts are not supported yet` | one `const` each |
| top-level `const f = twice` | `a top-level const holding a function is supported when its value is an arrow written in place, as in 'const f = (x: i64) => ...'; declare the function with 'function', or call it by its own name` | as it says |
| `xs.map(dbl)`, `dbl` a nested function | `a local function passed by name isn't supported yet; write an arrow calling it, as in '(x) => dbl(x)'` | as it says |
| `for (x of xs)`, `x` declared before | `'for...of' loops over a variable declared outside them are not supported yet` | `for (const y of xs) x = y;` |
| `const y: typeof x`, `x` a local | `'typeof' of the local 'x' isn't supported yet; 'typeof' in a type names a top-level function or const` | name the type |
| `return 2` in a `function*` | `a generator can't return a value yet; 'return;' ends it` | as it says |
| `console.log(await f())` | `'await' inside an expression isn't supported yet; give its value a name first, as in 'const x = await ...;'` | as it says |
| `sum += await h` | `'await' can only be assigned with '=' to a variable or a field for now; await into a 'const' first, then use it` | as it says |
| `xs.forEach(async (x) => { })` | `'forEach' with a callback giving a Promise isn't supported yet; await each value in a 'for...of' loop instead` | as it says |
| `run(risky)`, `risky` declared `throws` | `functions that throw used as values are not supported yet` | `run(() => risky(4))` |
| `(node: T \| null = dflt)` | `a parameter that may be null can have only 'null' as its default so far, since a passed null and a missing argument would look the same; write 'node?: ...' and give the default in the body` | as it says |
| `r["a"] += 1` on a `Record` | `a dictionary's entry is read as an Option, so it isn't updated in place; read it, then write it back, as in 'r[...] = (r[...] ?? 0) + 1'` | as it says |
| `JSON.stringify(x, null, 2)` | `'JSON.stringify' replacer and indent arguments are not supported yet` | `JSON.stringify(x)` |
| `JSON.parse(text, reviver)` | `'JSON.parse' revivers are not supported yet` | `JSON.parse<T>(text)` |
| `console.log("%j", x)` | `'%j' in a format isn't supported yet; pass 'JSON.stringify(x)' to '%s' instead` | as it says |
| `new Date(2024, 0, 15)` | `'new Date(year, month, ...)' isn't supported yet, as local time isn't; give 'new Date(ms)' milliseconds since the epoch` | as it says |
| `new Date("2024-01-15")` | `'new Date(text)' isn't supported yet, as reading dates from strings isn't; give 'new Date(ms)' milliseconds since the epoch` | as it says |
| `Date.parse(s)`, `Date.UTC(...)` | `'Date.parse' isn't supported yet, as reading dates from strings isn't; give 'new Date(ms)' milliseconds since the epoch`, `'Date.UTC' isn't supported yet; 'Date.now()' is` | as it says |

The right-hand column, compiled and run:
```fsh
enum Level { Low = "low", High = "high" }
class P { n: i64 = 3; get(): i64 { return this.n; } static make(): P { return new P(); } }
function twice(x: i64): i64 { return x * 2; }
function total(...xs: i64[]): i64 { let t = 0; for (const x of xs) t += x; return t; }
function risky(n: i64): i64 throws Error { if (n < 0) throw new Error("neg"); return n; }
function run(g: () => i64 throws Error): i64 throws Error { return g(); }
async function work(): Promise<i64> { return 20; }
async function main() throws Error {
  const o = { a: 1, b: 2 };
  const p = P.make();
  const g = () => p.get();
  const obj = { area: (r: i64) => r * r, size: 3 };
  const m = new Map<string, i64[]>([["a", [7]]]);
  const hit = m.get("a");
  const v = await work();
  let last = 0;
  for (const x of [1, 2]) last = x;
  let r: Record<string, i64> = {};
  r["a"] = (r["a"] ?? 0) + 1;
  console.log(Object.keys(o), g(), obj.area(obj.size), hit !== null ? hit[0] : 0, v + 1, last, r["a"]);
  // expect: [ 'a', 'b' ] 3 9 7 21 2 1
  console.log([1, 2].map((x) => twice(x)), total(1, 2), Level.High, run(() => risky(4)));
  // expect: [ 2, 4 ] 3 high 4
  console.log("%s", JSON.stringify(o), new Date(0).toISOString());
  // expect: {"a":1,"b":2} 1970-01-01T00:00:00.000Z
}
```

## 10. Left out on purpose (E0802)

These are not coming. `fishc lint` finds them in TypeScript source (`porting.md`).

| You wrote | Message, after `error[E0802]: ` | Write instead |
| --- | --- | --- |
| `var n = 1` | `'var' is not supported; use 'let' or 'const'` | as it says |
| `a == b`, `a != b` | `'==' is not supported; use '==='`, `'!=' is not supported; use '!=='` | as it says |
| `s[0] = "x"`, `s[0] += "x"` | `strings can't be changed; build a new one instead, joining parts with '+'` | `s = "x" + s.slice(1)` |
| `s.length = 1` | `a string's 'length' can't be changed; strings can't be changed, so build a new one instead` | `s = s.slice(0, 1)` |
| `#x in o` | `'#x in' can't be used: Fish has no run-time reflection, and a value's class is known while compiling` | the type already says it |

```fsh
function main() { let s = "abc"; s[0] = "x"; }
// error: error[E0802]: strings can't be changed; build a new one instead, joining parts with '+'
```
```fsh
function main() { let s = "abc"; s = "x" + s.slice(1); s = s.slice(0, 2); console.log(s); }
// expect: xb
```

## Not released yet

The compiler's source has these; fishc 0.1.1 answers them as below, so don't write them for it.

- `using r = open();` and `await using`: `error[E0001]: expected ';', found 'r'`. A class's
  `[Symbol.dispose]` method: `error[E0801]: '[Symbol.dispose]' members are not supported yet`.
- Task groups, `await taskGroup(async (group) => { ... })`: `error[E0401]: unknown function 'taskGroup'`.
- `import { Database } from "sqlite"` and `import { span } from "fish:trace"`:
  `error[E0902]: can't find the package 'sqlite'`, since the release has neither module.
