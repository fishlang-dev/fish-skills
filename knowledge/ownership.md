# Ownership and borrowing

Who owns a value, what moves it, how it is lent, and what the compiler refuses: every E02xx error.
A TypeScript developer has met none of this; a Rust developer will guess wrong, because Fish writes
no `&`, copies strings, and makes copies Rust would make you ask for (section 19). Types are in
`types.md`, tasks and `spawn` in `errors-async.md`, symptom-first fixes in `gotchas.md`. Checked
against fishc 0.1.3.

## 1. One owner: what is copied and what moves

Every value has one owner. Assigning it or handing it over copies it or moves it, by its type.
Copied: numbers, booleans, bigints, strings, enum members, literal types, a tuple or an Option
(`T | null`) of copied values, and a closure that only reads what it captures.

```fsh
function main() {
  const n = 1; const n2 = n;
  const s = "he" + "llo"; const s2 = s;
  const t: [i64, string] = [1, "a"]; const t2 = t;
  const f = (x: i64) => x + n; const f2 = f;
  console.log(n + n2, s, s2, t[0] + t2[0], f(1) + f2(1)); // expect: 2 hello hello 2 4
}
```

Everything else moves: arrays, objects (even `{ x: i64; y: i64 }`, whose fields all copy), class
instances, `Map` and `Set`, a tuple or Option holding any of those, a closure that changes or holds
a capture, an `Rc` or `shared` handle, and a value of a type parameter `T`.

```fsh
type Point = { x: i64; y: i64 };

function main() {
  const a: Point = { x: 1, y: 2 };
  const b = a;
  console.log(a.x, b.y);
}
// error: error[E0201]: 'a.x' can't be used here because 'a' was moved
// error: note: 'a' moved here: 'b' owns it now; use 'a.clone()' to keep a copy
```

Rust habit: a `string` is not Rust's `String`. It copies, so `take(s)` leaves `s` usable and
`Ref<string>` is rarely worth writing.

## 2. What counts as a move

A value that moves is handed over by each of these, and the note under E0201 says which:

- assigning it to a variable: `'a' moved here: 'b' owns it now; use 'a.clone()' to keep a copy`
- passing it to a parameter not typed `Ref` or `Mut`, `push` and `set` included: `'p' moved here:
  passing it to 'push' hands it over, as if 'push' kept it; pass 'p.clone()' to keep a copy`
- storing it in a field: `'p' moved here into 'h.p'; use 'p.clone()' to keep a copy`
- putting it in a literal: `'p' moved here into the new object; use 'p.clone()' to keep a copy`
- a closure moving it out: `'p' moved here into a closure, which holds it now`
- returning it, or choosing it in a `?:` whose result is kept (both arms count as moved)

Reading is not a move: a field of a copied type (`p.name`), `console.log(p)`, a template, a
comparison, a method call, and passing to a `Ref` or `Mut` parameter all leave the owner in place.

## 3. Use after move: branches, loops, assigning again

A move counts on every path that reaches the use. Moved in one branch is moved after the `if`.
Moved in a loop body is moved on the next pass: `'xs' was moved, so it can't be used here (in an
earlier pass through this loop)`. A branch that returns takes its move with it, and assigning a
moved `let` makes it usable again. Moves have no "last use" rule: `const b = a` moves `a` even if
`a` is never read again. Borrows do (section 9). More: `examples/move.fsh` (`move_flow`).

## 4. Moving a part out: fields, elements, loop variables, `this`

A field can be moved out of a variable that owns it, by assignment or destructuring. The other
fields stay usable; the whole does not until the field is assigned again (`'p' can't be used as a
whole here because 'p.left' was moved out of it`). Nothing can be moved out of what is only
borrowed (E0202): a `Ref` or `Mut` parameter, `this` in an ordinary method (`'this.inner' can't be
moved out of 'this', since it is only borrowed here; use 'this.inner.clone()'`), an array element,
a `for...of` variable.

```fsh
type P = { x: i64 };

function main() {
  let ps: P[] = [{ x: 1 }, { x: 2 }];
  const a = ps[0];
  console.log(a.x);
}
// error: error[E0202]: 'ps[0]' can't be moved out of its array; use 'ps[0].clone()' to take a copy, or 'pop()' to take the last element out
```

**Symptom**: `const a = ps[0]`, or `keep.push(p)` inside `for (const p of ps)`, fails with E0202
(`can't move a value out of a reference to it, which only borrows it; use '.clone()' to hand over a
copy`). **Why**: reading an element of a moving type is a move, and a loop variable is a `Ref`.
**Fix**: read the field you need, borrow with a `Ref` annotation, clone, or `pop()` or `shift()`.

```fsh
type P = { x: i64 };
type Pair = { left: P[]; right: P[] };

function main() {
  let pair: Pair = { left: [{ x: 1 }, { x: 2 }], right: [] };
  let ps = pair.left;
  pair.left = [];
  const a: Ref<P> = ps[0];
  for (const p of ps) pair.right.push(p.clone());
  const first = a.x;
  const last = ps.pop()!;
  console.log(first, last.x, ps.length, pair.left.length, pair.right.length); // expect: 1 2 1 0 2
}
```

## 5. `.clone()`, and the copies Fish makes without it

`.clone()` is a deep copy of an array, object, instance, union, `Map` or `Set`: nothing is shared
with the original. A class may write its own `clone(): C`, which runs instead. On an `Rc` or a
`shared` value it makes another handle to the same value, and a deep copy keeps the handles inside
it pointing where they did. It works through a type parameter (`examples/clone.fsh`).

Rust habit: Fish also deep-copies where Rust would move or borrow. Spread (`[...xs]`, `{ ...o }`),
`slice`, `concat`, `filter` and `find` give copies of the elements, `map.get(k)` gives a copy of
the value, and reading a field through an `Rc` or `shared` copies it out. Changing the result never
changes the source (section 16).

```fsh
type Doc = { tags: string[]; owner: Rc<{ n: i64 }> };

function main() {
  let a: Doc = { tags: ["x"], owner: new Rc({ n: 1 }) };
  let b = a.clone();
  b.tags.push("y");
  b.owner.update((v) => v.n++);
  let docs = [a, b];
  let found = docs.find((d) => d.tags.length === 2)!;
  found.tags.push("z");
  let all = [...docs];
  all[0].tags.push("w");
  console.log(docs[0].tags.length, docs[1].tags.length, docs[0].owner.n, found.tags.length); // expect: 1 2 2 3
}
```

What can't be cloned is E0213: a value holding a `Mut`, and so a closure that changes a capture
(`can't clone a value holding a mutable reference ('Mut'), since the copy would change the same
thing`), `clone` with arguments, and a class's `clone` that doesn't return its own class.

## 6. Borrowing parameters: `Ref<T>` and `Mut<T>`

A parameter typed `Ref<T>` borrows its argument to read it, `Mut<T>` borrows it to change it, and
a plain `T` takes it over. The caller writes the same thing for all three: there is no `&` and no
`&mut` (`look(&p)` is `error[E0001]: expected an expression, found '&'`). A `Mut` lends itself on
to `Mut` and `Ref` parameters as often as needed, and a temporary can be lent.

```fsh
type P = { x: i64 };

function look(p: Ref<P>): i64 { return p.x; }
function bump(p: Mut<P>) { p.x += 1; }
function inc(n: Mut<i64>) { n += 10; }
function twice(p: Mut<P>): i64 { bump(p); bump(p); return look(p); }

function main() {
  let p: P = { x: 1 };
  let n = 1;
  bump(p);
  inc(n);
  console.log(look(p), twice(p), p.x, n, look({ x: 7 })); // expect: 2 4 4 11 7
}
```

A `Mut` argument must be a `let`: passing a `const` is `error[E0207]: cannot mutably borrow 'p'
because it is a constant`. A `Ref` gives neither change nor ownership: writing through one is
`error[E0206]: cannot assign to 'p.x' because 'p' is a shared reference ('Ref'), which only reads`,
passing one to a plain `T` parameter is the E0202 of section 4, and passing one to a `Mut`
parameter is `error[E0101]` ending `a shared reference can't lend itself as mutable`. A plain owned
parameter may be changed inside the function, like a `let`.

**Symptom**: `p = { x: 0 }` through `p: Mut<P>` is `error[E0206]: can't assign a whole value
through 'p', which may point to a wider value; assign its fields instead`. **Why**: a parameter
typed with an object type accepts any value with those members (`types.md`). **Fix**: assign the
fields, or type the parameter with a class, through which a whole value can be assigned.

## 7. Methods: `this`, `this: Mut<this>`, `this: Own<this>`

A method borrows `this` read-only unless its first parameter says otherwise. `this: Mut<this>` may
change the object and needs a `let` receiver. `this: Own<this>` takes the object over and may move
its fields out; for the caller the call is a move of the object (E0201 on its next use).

```fsh
class Counter {
  n = 0;
  log: string[] = [];
  bump(this: Mut<this>) { this.n += 1; }
  finish(this: Own<this>): string[] { return this.log; }
}

function main() {
  let c = new Counter();
  c.bump();
  console.log(c.n, c.finish().length); // expect: 1 0
}
```

```fsh
class Counter {
  n = 0;
  bump() { this.n += 1; }
}
// error: error[E0206]: cannot assign to 'this.n' because 'this' is read-only here; declare 'this: Mut<this>'
```

Calling a `Mut<this>` method on a `const` is `error[E0207]: cannot call 'bump' on 'c' because it is
a constant`, and through a `Ref` it is E0206. More: `examples/own.fsh`, `examples/mut.fsh`.

## 8. `let`, `const` and what may change

There is no `mut` keyword. `let` may change. `const` is deeply immutable: neither it nor anything
it owns can be assigned (`error[E0207]: cannot assign to 'p.x' because 'p' is a constant`), pushed
to (`cannot push to 'xs' because it is a constant`) or lent as `Mut`. A `const` holding a `Mut` can
still write through it (`const m: Mut<P> = p; m.x = 2;`), since only the reference is constant.

Two neighbours that are not about ownership: assigning a `readonly` field, even of a `let`, is
`error[E0208]: cannot assign to 'id' because it is a read-only property`, and reading a `let`
declared without a value before every path assigns it is `error[E0205]: 'n' is used before being
assigned; give it a value on every path that reaches here, as TypeScript requires`.

## 9. The borrow rules

A place may be lent to any number of shared references, or to one mutable reference, never both.
Lent shared, it can be read but not changed, moved or reassigned. Lent mutably, it can't be used at
all except through that reference. Every conflict is E0203, with a note where the loan was made.

```fsh
type P = { x: i64 };

function main() {
  let p: P = { x: 1 };
  const r: Ref<P> = p;
  p.x = 5;
  console.log(r.x);
}
// error: error[E0203]: cannot change 'p.x' while 'r' borrows 'p' and is used later
// error: note: 'p' is lent here, so it can't change or move until the borrow's last use
```

With `take(p)` in place of the assignment it reads `cannot move 'p' while 'r' borrows 'p' and is
used later`; with `let m: Mut<P> = p; console.log(p.x); m.x = 2;` it reads `cannot use 'p.x' while
'm' borrows 'p' mutably and is used later`.

A loan to a variable lasts until that variable's last use or until it is pointed elsewhere, not to
the end of its scope, and a loan to a call lasts for the call. Different fields of one value are
different places.

```fsh
type P = { x: i64 };
type Line = { a: P; b: P };
function swap(a: Mut<P>, b: Mut<P>) { const t = a.x; a.x = b.x; b.x = t; }

function main() {
  let l: Line = { a: { x: 1 }, b: { x: 2 } };
  let r: Ref<P> = l.a;
  const seen = r.x;
  r = l.b;
  l.a.x = 5;
  const also = r.x;
  swap(l.a, l.b);
  let m: Mut<P> = l.b;
  m.x += 10;
  console.log(seen, also, l.a.x, l.b.x); // expect: 1 2 2 15
}
```

Arguments are lent left to right, and a mutable loan made for a call shuts out the arguments after
it: `swap(p, p)` is `cannot use 'p' while 'p' is lent mutably to 'swap' for this call`. All the
elements of an array are one place, written `ps[...]` in messages, so `swap(ps[0], ps[1])` is
refused the same way.

**Symptom**: `add(xs, xs.length)`, where `add` takes `Mut<i64[]>`, fails with `cannot use
'xs.length' while 'xs' is lent mutably to 'add' for this call`. **Why**: the loan of `xs` starts
before `xs.length` is read. **Fix**: read it into a `const` first. A method's own arguments may
read its receiver: `xs.push(xs.length as i64)` compiles. More: `examples/borrow.fsh`.

## 10. Loops, iterators and callbacks over a collection

`for...of` lends its collection for as long as the loop runs, an iterator or generator holds what
it was given until its last use, and an array method lends its array for the call. The collection
can't be changed meanwhile, and each element arrives as a shared reference. A `push` inside
`for (const x of xs)` is `error[E0203]: cannot change 'xs' while a 'for...of' loop is reading
'xs'`. Changing an element through the loop variable, `for (let p of ps) p.x += 1` or
`ps.forEach((p) => { p.x += 1; })`, is the E0206 of section 6, and a `push` inside a `forEach`
callback is `cannot mutably lend 'xs' while 'xs' is lent to 'forEach' for this call`. **Fix**: loop
by index to change elements or the array, or loop over a clone. Unlike Rust's `for x in v`, the
loop does not consume the array.

```fsh
type P = { x: i64 };

function main() {
  let ps: P[] = [{ x: 1 }, { x: 2 }];
  for (let i = 0; i < ps.length; i++) ps[i].x *= 10;
  for (const p of ps.clone()) {
    if (p.x > 10) ps.push({ x: 0 });
  }
  console.log(ps[0].x, ps[1].x, ps.length); // expect: 10 20 3
}
```

## 11. References as local variables

A local borrows only when its type says so: `const r: Ref<P> = p` or `let m: Mut<P> = p`, as in
section 9. Without the annotation the initializer is an ordinary read, which copies or moves
(section 4). What is already a reference (a `for...of` variable, a call returning `Ref`) needs no
annotation. A reference can't outlive what it points at (E0204): a temporary, or a block's local
(`'b' doesn't live long enough: 'v' still borrows it after its block ends`).

```fsh
class P { x = 1 }
function make(): P { return new P(); }

function main() {
  const r: Ref<P> = make();
  console.log(r.x);
}
// error: error[E0204]: 'r' would keep borrowing this temporary, which is gone once its statement ends; give it a name first, as in 'const xs = ...;'
```

## 12. Returning references and lifetimes

A function may return `Ref<T>` or `Mut<T>` pointing into what it was lent, and the caller's
argument stays lent until the result's last use. With one reference parameter nothing more is
written; a method's result borrows `this` (`get(): Ref<Inner> { return this.inner; }`). With
several, the function says which one the result points into: a lifetime is a type parameter
declared `extends Lifetime` and written as the second argument of `Ref` or `Mut`.

```fsh
class P { x = 1 }
function pick(a: Ref<P>, b: Ref<P>): Ref<P> { return a.x > b.x ? a : b; }
// error: error[E0209]: this function returns a reference and takes several, so say which it points into: declare '<A extends Lifetime>' and write 'Ref<T, A>' on that parameter and the return type
```

```fsh
class P { x = 1 }
function pick<A extends Lifetime>(a: Ref<P, A>, b: Ref<P, A>): Ref<P, A> { return a.x > b.x ? a : b; }
function left<A extends Lifetime>(a: Ref<P, A>, b: Ref<P>): Ref<P, A> { return b.x > 0 ? a : a; }
function first(ps: Mut<P[]>): Mut<P> { return ps[0]; }

function main() {
  let ps = [new P()];
  let other = new P();
  first(ps).x = 5;
  const l = left(ps[0], other);
  other.x = 9;
  console.log(l.x, pick(ps[0], other).x); // expect: 5 9
}
```

`other.x = 9` is allowed while `l` is live because `left` ties its result to `a` alone. The other
E0209 messages: `the returned reference points into 'b', but its lifetime ties it to 'a'; give 'b'
that lifetime, or return an owned value`; `can't return a reference to 'p', which belongs to this
function and is gone once it returns; return an owned value instead`; `this function returns a
reference but borrows nothing it could point into; return an owned value instead`.

**Symptom**: `function nameOf(p: Ref<P>): Ref<string> { return p.name; }` fails with
`error[E0204]: can't return a reference to a temporary or a copy, which is gone once the function
returns; return an owned value instead`. **Why**: reading a string or number field copies it.
**Fix**: return `string`. More: `examples/lifetime.fsh`, `examples/lifetimes.fsh`.

## 13. References inside values

An object type or a class may have `Ref` and `Mut` fields, with no lifetime written on the type. A
value holding references keeps what they point at lent until the value's last use, and so does a
copy of it, or a value a function built from its reference parameters. References also go in
arrays, in Options, and in the members of a tagged union (`{ kind: "one"; p: Ref<P> }`).

```fsh
class P { x = 1 }
class View {
  r: Ref<P>;
  constructor(r: Ref<P>) { this.r = r; }
}
function find(ps: Ref<P[]>, x: i64): Ref<P> | null {
  for (const p of ps) if (p.x === x) return p;
  return null;
}

function main() {
  let ps = [new P(), new P()];
  const v = new View(ps[0]);
  const rs: Ref<P>[] = [ps[0], ps[1]];
  const hit = find(ps, 1);
  console.log(v.r.x, rs.length, hit !== null); // expect: 1 2 true
  ps.push(new P());
}
```

Move the `ps.push` above the `console.log` and it is E0203, `cannot change 'ps' while 'v' borrows
'ps[...]' and is used later`. A class may name a lifetime, `class Parser<A extends Lifetime> {
src: Ref<P, A> }`, so that a function returning one borrows only the arguments with that lifetime
(`examples/ref.fsh`, `ref_class_lifetimes`). A method can't store in `this` a reference to its own
local: `error[E0209]: can't store in 'this' a reference to 'local', which belongs to this function
and is gone once it returns; store an owned value instead`.

Refused in this release with E0801: `references to references are not supported yet`
(`Ref<Ref<T>>`), `maps of references are not supported yet` (`Map<K, Ref<V>>`), `unions of bare
references are not supported yet; hold each in an object member with a tag` (`Ref<A> | Ref<B>`),
and storing a new reference in a holder reached through a `Mut` or captured by a closure (`keeping
references through the reference 'm' is not supported yet`). An `Rc`, a `shared` value and a
spawned task can't hold one at all. More: `examples/ref_arrays.fsh`, `examples/union_refs.fsh`.

## 14. Closures and nested functions

A closure borrows what it reads, borrows mutably what it changes, and takes over what it moves out.
It holds those loans from where it is made to its last call, so between its calls the variable is
shut out as in section 9: `const inc = () => { count++; }; console.log(count); inc();` is
`error[E0203]: cannot use 'count' while 'inc' borrows 'count' mutably and is used later`.
`move (...) => ...` takes over everything it captures; a copied capture then lives on as the
closure's own copy. A nested `function` declaration called by name borrows only for each call, so
its variables are free between calls, which is the fix when a helper changes local state.

```fsh
function each(xs: Ref<i64[]>, f: (x: i64) => void) { for (const x of xs) f(x); }

function main() {
  let total = 0;
  each([1, 2, 3], (x) => { total += x; });
  let n = 10;
  const own = move () => { n++; return n; };
  let xs: i64[] = [];
  function add(k: i64) { xs.push(k); }
  add(1);
  console.log(total, own(), own(), n, xs.length); // expect: 6 11 12 10 1
  add(2);
  console.log(xs.length); // expect: 2
}
```

A closure that moves a capture out can run only once. Calling it moves it (E0201, `'once' moved
here: calling it runs it once, since it moves out what it captured`), and a function that may call
its callback more than once refuses it: `error[E0210]: 'map' calls its callback once per element,
but this closure moves 's' out, so it can run only once; clone it inside instead`. A nested
function can't move a capture out (E0202). More: `examples/closure.fsh`, `examples/nested.fsh`.

## 15. Closures that outlive their scope

A closure returned from a function, or stored in a field or an object, is a stored callable: it
owns what it captures and can't change it. Written where it is returned or stored it captures by
move without the keyword. Passed in from elsewhere and then stored, it needs `move`, or it is
`error[E0210]: this closure borrows 'tags', but a stored callable owns what it captures; write the
closure where it is stored, so it captures by move, or as 'move (...) => ...'`. The JavaScript
counter closure does not compile:

```fsh
function counter(): () => i64 {
  let n = 0;
  return () => { n++; return n; };
}
// error: error[E0210]: this closure changes 'n', which it captures, but a stored callable can't change what it captures; keep that state in an 'Atomic' or a 'Lock'
```

A stored callable may cross threads, so a `Cell` or an `Rc` inside one is refused too (E0303). The
state goes in an `Atomic`, whose `add` returns the value before the addition. Timer callbacks and
async arrows have E0210 messages of their own (`errors-async.md`).

```fsh
function counter(): () => i64 {
  const n = new Atomic(0);
  return () => n.add(1) + 1;
}

function main() {
  const next = counter();
  console.log(next(), next()); // expect: 1 2
}
```

## 16. Changes that would reach only a copy

Where a read gives a copy (section 5), a mutating call on it is refused rather than silently lost.

```fsh
function main() {
  let m = new Map<string, i64[]>();
  m.set("k", [1]);
  m.get("k")!.push(2);
}
// error: error[E0212]: 'push' changes its array, so call it on a variable or a field
```

**Fix**: take the value into a `let`, change it, and `set` it back. E0212 also meets
`make().push(1)`, `(c ? a : b).push(1)`, a `push` on a call that returns `Mut` (name the result
first), and a `Mut<this>` method called through `!` on an optional field (`can't call 'bump'
through '!', which would change a copy; check '!== null' first, or call it with '?.'`). Through a
`Dyn<I>` whose interface has a field `items`, `d.items.push(1)` is `error[E0211]: 'push' changes
its array, and this one is read through a Dyn, which gives a copy; change it through a method`.

## 17. Shared ownership: `Rc`, `Weak`, `Cell`, `shared`

`new Rc(v)` is one value with several owners on one thread. `.clone()` makes another handle, fields
read through any handle, and changes happen inside `update`, whose callback gets the value mutably
and whose result `update` returns; `read` lends it shared. Assigning outside `update` is
`error[E0304]: cannot assign to 'r.n' because 'r' is an 'Rc', whose value every clone of it reads;
change it inside 'r.update(...)'`. An `Rc` is Rust's `Rc<RefCell<T>>` in one piece: an `update`
nested in an `update` of the same value panics. `Rc.ptrEq(a, b)` compares identity.

`Cell<T>` is a field that changes through a shared reference, a `const` or an `Rc` handle, on one
thread. `get()` copies the value out (copied types only), `set(v)` stores, and `replace(v)` stores
and returns the old value, which is how a moving value comes out.

```fsh
class Parent { name = "p"; kids: Rc<Kid>[] = []; seen: Cell<i64> = new Cell(0) }
class Kid {
  parent: Weak<Parent>;
  constructor(parent: Weak<Parent>) { this.parent = parent; }
}

function main() {
  const p = new Rc(new Parent());
  const k = new Rc(new Kid(p.downgrade()));
  p.update((v) => { v.kids.push(k.clone()); });
  p.seen.set(p.seen.get() + 1);
  const up = k.parent.upgrade();
  console.log(up !== null ? up.name : "gone", p.read((v) => v.kids.length), p.seen.get(), Rc.ptrEq(p, p.clone()));
  // expect: p 1 1 true
}
```

Two `Rc`s that hold each other are never freed. Make the link back a `Weak` (`rc.downgrade()`, then
`weak.upgrade()` gives `Rc<T> | null`), as above. `fishc run --leaks` reports a cycle as
`fish: leaked 2 allocations` with the line of each `new Rc`.

`shared(v)`, of type `shared<T>`, is the same idea across threads, Rust's `Arc<Mutex<T>>`:
`const t = s.clone()` for another handle, `t.update((v) => { v.n++; })` to change under the lock,
`s.n` to read a copy. A `spawn`ed task must own everything it uses, so each is passed a clone. It
can't hold an `Rc` or a `Cell`; put an `Atomic` or a `Lock` inside instead. More: `examples/rc.fsh`,
`examples/cell.fsh`, `examples/shared.fsh`, and `errors-async.md` for E03xx.

## 18. Drop, disposers and `using`

A value is freed when its owner's scope ends, not at its last use; a temporary at the end of its
statement; an old value when its variable is assigned again; a moved value by whoever it was moved
to. Locals go in reverse order of declaration. There is no garbage collector.

A class's `[Symbol.dispose]()` method is its destructor, Rust's `Drop`: Fish runs it once, just
before an instance is freed, on every way out of the scope, a panic included. TypeScript runs the
method only for a value declared with `using`; Fish runs it for every owner, so `const` is enough.

```fsh
class Conn {
  name: string;
  constructor(name: string) { this.name = name; }
  [Symbol.dispose](this: Mut<this>): void { console.log("closed", this.name); }
}
function send(c: Ref<Conn>) { console.log("sent on", c.name); }
function finish(c: Conn) { console.log("finishing", c.name); }

function main() {
  const a = new Conn("a");
  let b = new Conn("b");
  send(a);                  // expect: sent on a
  b = new Conn("c");        // expect: closed b
  finish(a);                // expect: finishing a
                            // expect: closed a
  const pool = [new Conn("p1"), new Conn("p2")];
  console.log(pool.length); // expect: 2
}
// expect: closed p1
// expect: closed p2
// expect: closed c
```

The method takes no parameters, returns nothing, and can't be `async`, `static`, a generator,
declare `throws` or take `this: Own<this>` (each E0710). Only a class's method counts: one in an
object literal or an interface is E0801. A value with a disposer moves only as a whole, so closing
it by hand, copying it and taking a field out of it are refused. To end it early, let its block
end or move it into a function; pass `c.log.clone()`; declare `clone(): Conn` to say what a copy is.

`using x = value;` adds one promise to that: the value never leaves its block. The binding can't
be moved, returned, stored or assigned to (E0215), only lent, and its fields can still change. Its
value must be an instance of a class with a disposer (E0411; `null` is refused too). It stands in
a block of a function, never at top level or in a `for` head. Reach for it when a later edit
moving the value away would be a bug, as with a lock guard, a span or a transaction; otherwise
`const` disposes at the same place.

```fsh
class Conn {
  name: string;
  constructor(name: string) { this.name = name; }
  [Symbol.dispose](this: Mut<this>): void { console.log("closed", this.name); }
}
function show(c: Ref<Conn>) { console.log("using", c.name); }

function first(stop: boolean): i64 {
  using a = new Conn("a");
  using b = new Conn("b");
  if (stop) return 1;
  show(b);
  return 2;
}

function main() {
  console.log(first(true));
  // expect: closed b
  // expect: closed a
  // expect: 1
  {
    using c = new Conn("c");
    c.name = "c2";
    show(c);            // expect: using c2
  }                     // expect: closed c2
  console.log("end");   // expect: end
}
```

```fsh
class Conn {
  log: string[] = ["opened"];
  [Symbol.dispose](this: Mut<this>): void { console.log("closed"); }
}
class Plain { n = 1; }
function keep(_log: string[]) {}
function take(_c: Conn) {}
function byHand() { const c = new Conn(); c[Symbol.dispose](); }          // error: error[E0710]: a '[Symbol.dispose]' method runs when its value is dropped, so it can't be called by hand
function apart() { const c = new Conn(); keep(c.log); }                    // error: error[E0214]: 'c.log' can't be moved out of 'c'
function copied() { const c = new Conn(); const d = c.clone(); take(d); }  // error: error[E0213]: can't clone a 'Conn'
function moved() { using c = new Conn(); take(c); }                        // error: error[E0215]: 'c' can't be moved: it is declared with 'using'
function assigned() { using c = new Conn(); c = new Conn(); }              // error: error[E0215]: cannot assign to 'c': it is declared with 'using'
function plain() { using p = new Plain(); console.log(p.n); }              // error: error[E0411]: 'p' can't be declared with 'using': its type 'Plain' has no disposer
function main() {}
```

`await using` and `async [Symbol.asyncDispose]()` are in `errors-async.md`. To see where a file
moves, lends and drops, run `fishc explain-borrows <file.fsh>` (`toolchain.md`). More:
`examples/dispose.fsh`.

## 19. How this differs from Rust

- No `&`, `&mut` or `*`. The type of the parameter or local (`Ref<T>`, `Mut<T>`) makes the borrow,
  and a reference is used like the value. A local with no `Ref` annotation never borrows.
- No `mut` on bindings: `let` and owned parameters are mutable, `const` is deeply immutable.
- Strings copy. Tuples and Options copy when their parts do. Objects and instances never copy
  implicitly, whatever their fields.
- Fish copies where Rust moves or borrows: spread, `slice`, `filter`, `find`, `Map.get`, field
  reads through `Rc` and `shared`. `for...of` borrows its collection instead of consuming it.
- Lifetimes are generic parameters, `<A extends Lifetime>` and `Ref<T, A>`, required only when a
  function returning a reference takes several. Types that hold references need none.
- Fish allows what Rust refuses: a nested `function` that uses the enclosing function's variables,
  borrowing them per call, and `Rc.update` with no `RefCell`.
- Fish refuses what Rust allows: a returned or stored closure that changes its captures (Rust's
  boxed `FnMut`), `Ref<Ref<T>>`, a `Map` of references, and changing a collection's elements
  through `for...of` or through `Map.get`.

## 20. Choosing

| For | Choose |
| --- | --- |
| A parameter the function reads | `Ref<T>` (plain `T` for numbers, booleans, strings, enums) |
| A parameter the function changes for the caller | `Mut<T>` |
| A parameter the function keeps (stores, returns, sends to a task) | plain `T`; the caller clones to keep its own |
| A field | an owned value; `Ref<T>` only in a short-lived view built and dropped in one scope |
| A value several long-lived owners read and change, one thread | `Rc<T>`, with `Weak<T>` for links back |
| A value tasks or stored callbacks share | `shared<T>`, or an `Atomic` or `Lock` field |
| A counter or cache changed through a `Ref` or a `const` | a `Cell<T>` field |
| A return value | owned; `Ref<T>` or `Mut<T>` only into a parameter or `this` |
| Two owners that each change their own | `.clone()` |

When an E0201 note says to clone, first ask whether the function that took the value only reads
it. If so, type its parameter `Ref<T>`: the error is gone without a copy. No hint suggests this.
