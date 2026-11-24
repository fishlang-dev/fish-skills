# Errors and async

How a Fish function fails and how Fish code runs concurrently: `throws` clauses, `try`/`catch`,
panics, then `async`/`await`, tasks, the types tasks share, and cancellation. `Option` and
narrowing are in `types.md`, moves and borrows in `ownership.md`, the HTTP server, `fetch` and
files in `std.md`. Checked against fishc 0.1.3.

Three habits to drop first. From TypeScript: a function's errors are part of its type, and an
async call does nothing until it is awaited. From Rust: there is no `?` and no `Result`; a call
that can throw propagates by itself once the caller declares the error.

## 1. `throws` is part of the signature

A function, method, constructor or arrow that can throw says `throws E` after its return type. A
caller writes nothing at the call: it either catches, or declares the error and lets it pass.

```fsh
function half(n: i64): i64 throws string {
  if (n % 2 !== 0) throw "odd";
  return n / 2;
}
function twice(n: i64): i64 throws string { return half(n) + half(n); }
function main() {
  try {
    console.log(twice(4)); // expect: 4
    console.log(twice(3));
  } catch (e) {
    console.log("caught", e); // expect: caught odd
  }
}
```

A call that neither catches nor declares is E0602, even with its result dropped, and so is a
`throw` in a function with no clause (`'half' must declare 'throws Error' after its return type`).

```fsh
function half(n: i64): i64 throws string { return n % 2 === 0 ? n / 2 : throw "odd"; }
function main() {
  half(4);
}
// error: error[E0602]: 'main' must declare 'throws string' after its return type since 'half' can throw 'string', or catch it with try/catch
```

- Only an arrow with no written clause has its error inferred from its body. Named and nested
  functions and methods (`m(): void throws E`) must write it; an interface method may declare one.
- `throw` is also an expression, as above and in `find(n) ?? throw "missing"`.
- A constructor may declare `throws`, but only throws before it assigns its first field (E0602: `a
  constructor can only throw before it assigns its first field`). `new` is then a fallible call.
- An async function writes the clause after the Promise: `Promise<string> throws IoError`.

## 2. What can be thrown

Any owned value: a number, a string, an object type, any class, with no base class needed (a
reference can't: E0801, `errors holding references are not supported yet`). `Error` is an ordinary
prelude class with `name`, `message` and `cause` (a `Dyn<ErrorLike> | null`, set with `new Error(m,
{ cause })`); a class extending it that sets `this.name` prints as `[NotFound: no k] { key: 'k' }`.
The prelude's other error classes do not extend `Error` and, except `TypeError`, have no `name`:

| Class | Fields | Thrown by |
| --- | --- | --- |
| `IoError` | `message`, `code` (`"ENOENT"`), `syscall`, `path: string \| null` | file, socket, process calls |
| `JsonError` | `message` | `JSON.parse<T>` |
| `AbortError` | `message` (`This operation was aborted`) | an aborted wait, `throwIfAborted()` |
| `TaskPanic` | `message` (the panic's reason) | `await handle.join()` |
| `TypeError` | `name`, `message`, `cause` | `new URL` and other std calls |
| `AggregateError<E>` | `name`, `message`, `cause`, `errors: E[]` | `Promise.any` |

```fsh
import { readFileSync } from "node:fs";
function main() {
  try {
    console.log(readFileSync("/no/such/file", "utf8").length);
  } catch (e) {
    console.log(e.code, e.syscall, e.path); // expect: ENOENT open /no/such/file
  }
}
```

## 3. Error types are exact

**Symptom**: a subclass of `Error` thrown from a function declared `throws Error` is refused.
**Why**: a `throws` type is never widened to a base class, and `as Error` is refused too (E0111).
**Fix**: name each class in a union (`throws NotFound | Denied`), or convert with `From`.

```fsh
class NotFound extends Error { constructor() { super("missing"); } }
function find(): i64 throws Error {
  throw new NotFound();
}
// error: error[E0602]: this 'throw' throws 'NotFound', which isn't the 'Error' that 'find' throws; convert it, or have 'Error' implement 'From<NotFound>'
```

A caller's clause must cover every member of what it calls. A class that implements `From<E>`
with a `static from` wraps an `E` automatically, both when one propagates and when one is thrown:

```fsh
class DbError { constructor(public code: i64) {} }
class ApiError implements From<DbError> {
  constructor(public status: i64) {}
  static from(e: DbError): ApiError { return new ApiError(500 + e.code); }
}
function query(n: i64): i64 throws DbError { return n < 0 ? throw new DbError(7) : n; }
function handler(n: i64): i64 throws ApiError { return query(n) * 2; }
function main() {
  try { console.log(handler(-1)); } catch (e) { console.log("api", e.status); }
}
// expect: api 507
```

## 4. `try`, `catch`, `finally`, and a `main` that throws

The catch variable's type is the union of everything the `try` body can throw. It is never
`unknown` or `any`, and it takes no annotation (E0004: `a catch parameter takes no type
annotation: its type is what the 'try' can throw`). Narrow it as any union, with `instanceof` or
`typeof`; a field every member has reads without narrowing. `throw e` in a `catch` rethrows what
is left, and the function must declare it. `catch { }` binds nothing.

```fsh
class Missing { constructor(public key: string) {} }
class Denied { constructor(public user: string) {} }
function read(key: string): i64 throws Missing | Denied | string {
  if (key === "") throw new Missing(key);
  if (key === "root") throw new Denied("guest");
  return key === "?" ? throw "bad key" : key.length as i64;
}
function lookup(key: string): i64 throws Denied {
  try {
    return read(key);
  } catch (e) {
    if (typeof e === "string") return -1;
    if (e instanceof Missing) return 0;
    throw e;
  } finally {
    console.log("looked up", key); // expect: looked up ?
  }
}
function main() throws Denied {
  console.log(lookup("?")); // expect: -1
}
```

- A `finally` runs however its `try` or `catch` is left (normally, `return`, `break`, an error
  passing through); a `return` inside it replaces the value on its way out.
- A value moved into a call that then threw is gone in the `catch` (E0201).
- `main` may declare `throws`, as above. An error that leaves it is printed to stderr as `Error: `
  and the value as `console.log` prints it (`Error: [Error: config missing]`, `Error: bad key`),
  and the process exits with status 1. `main` can't return a value (E0405); use `process.exit`.
- A `try` whose body can't throw is refused, so a defensive `try` around infallible code fails
  (E0603: `nothing in this 'try' can throw, so its 'catch' never runs; remove the try/catch`).

More: `examples/throws.fsh`, `examples/try.fsh`, `examples/finally.fsh` (moves across a `finally`).

## 5. Closures, callbacks, JSDoc

A function type carries its own clause, `(x: i64) => i64 throws string`. A closure that throws
nothing fits a throwing type; one that throws does not fit a type that throws nothing. Array and
Map methods that take a callback (`map`, `filter`, `forEach`, `reduce`, `find`, `some`) pass on
what it throws, so the method call becomes the fallible call. A JSDoc `@throws {T}` tag with a
type in braces is a `throws` clause, so ported TypeScript keeps its comments and gains the check;
several tags make a union, and a tag with no type declares nothing.

```fsh
/** @throws {string} when the list is empty */
function head(xs: Ref<i64[]>): i64 { return xs.length === 0 ? throw "empty" : xs[0]; }
function apply(f: (x: i64) => i64 throws string, x: i64): i64 throws string { return f(x) * 10; }
function main() {
  const check = (n: i64) => n < 0 ? throw "negative" : n;
  try {
    console.log(apply((x) => x + 1, 1), head([7])); // expect: 20 7
    console.log([1, -2].map((x) => check(x)));
  } catch (e) {
    console.log("caught", e); // expect: caught negative
  }
}
```

A parameter whose function type has no clause, a `sort` comparator for one, can't be given a
closure that throws (E0602: `'cmp' can throw 'string', but the closure is given as '(a: i64, b:
i64) => void', which throws nothing; catch it inside the closure with try/catch`). E0801 refuses
a generic function type that throws and a function type giving a Promise that throws, so an async
callback parameter can't throw. More: `examples/closures_throw.fsh`, `examples/jsdoc_throws.fsh`.

## 6. Panics

A panic is a bug, not an error value. It prints `panicked at <file>:<line>:<col>:`, the reason,
and in a debug build a `stack backtrace:` of the program's own frames, all to stderr, then exits
with status 101. No `catch` sees it and no `finally` runs for it:

```fsh
function pick(xs: Ref<i64[]>, i: usize): i64 throws string { return i > 9 ? throw "far" : xs[i]; }
function main() {
  try { console.log(pick([1], 3)); } catch (e) { console.log("caught"); } finally { console.log("finally"); }
}
// panic: index out of bounds: the len is 1 but the index is 3
```

| Cause | Reason printed (Rust's wording) |
| --- | --- |
| `+ - *` overflow in a debug build | `attempt to add with overflow` |
| `/` or `%` by zero, any build | `attempt to divide by zero`, `attempt to calculate the remainder with a divisor of zero` |
| index past the end of an array or string | `index out of bounds: the len is 3 but the index is 5` |
| `x!` on an absent value | ``called `Option::unwrap()` on a `None` value`` |
| `assert(cond)`, `assert(cond, message)` | `assertion failed: <source of cond>`, or the message |

- `--release` wraps on overflow instead of panicking, and prints no backtrace.
- There is no `panic()` function (E0401: `unknown function 'panic'`); use `assert(false, "why")`.
- `xs[i]` gives a `T`, not `T | undefined`, and takes a `usize`: check the length first.
- `fishc build --panic=abort` makes a panic abort the process (SIGABRT, no unwinding) after the
  same message. The default unwinds, which lets one task's panic leave the others running.

Which to use: return `T | null` for absence that is a normal answer (as `Map.get`, `find` and
`pop` do); `throw` a typed value for a failure the caller can act on; `assert`, `!` or indexing
for a broken invariant. Do not `throw` for bugs, since every caller would have to declare it.
More: `examples/panic.fsh`, `examples/backtrace.fsh`, `examples/overflow.fsh`.

## 7. Promises are lazy

Calling an async function builds a `Promise<T>` and runs nothing. The body starts when the
Promise is awaited, or at once on another thread when it is given to `spawn`. `main` may be async.

```fsh
async function work(label: string): Promise<i64> { console.log("running", label); return 1; }
async function main() {
  const p = work("lazy");
  console.log("made, not started"); // expect: made, not started
  const h = spawn(work("spawned")); // expect: running spawned
  await sleep(50);
  const a = await p; // expect: running lazy
  const b = await h;
  console.log(a + b); // expect: 2
}
```

**Symptom**: TypeScript's fire-and-forget call, `save(x);`, is a compile error, since the
Promise would be dropped without running.
**Fix**: `await save(x);`, or `spawn(save(x));` to run it alongside.

```fsh
async function save(n: i64) { console.log(n); }
async function main() {
  save(1);
}
// error: error[E0302]: this Promise does nothing until it's awaited, since Fish's promises are lazy; add 'await', or wrap the call in 'spawn(...)' for fire-and-forget
```

- Awaiting moves the Promise: a second `await p` is E0201 (`awaiting a Promise runs it to
  completion, after which it is gone`). One kept in a variable and never awaited never runs, and
  only the unused-variable warning says so.
- An async function's written return type is `Promise<T>` (E0305 otherwise); unwritten, it is
  inferred. An async arrow takes the same annotation, `async (n: i64): Promise<i64> => n + 1`.
- `await` outside an async function is E0301, `await` of a non-Promise E0305, and an async
  function awaiting a call of itself E0113 (loop instead).
- An awaited call may borrow: `await first(names)` with a `Ref` parameter is fine, since the
  caller waits. Only `spawn` and stored Promises need owned values (section 12).

## 8. Where `await` may be written

In this release `await` is a statement, or the whole right side of `const x = await e;`, `x =
await e;`, `o.f = await e;` or `return await e;`, anywhere but the two places in the table's last
rows (so loops, `if`, `switch` and `try`/`catch` are fine). Anything else is E0801:

```fsh
async function one(): Promise<i64> { return 1; }
async function main() {
  console.log(1 + (await one()));
}
// error: error[E0801]: 'await' inside an expression isn't supported yet; give its value a name first, as in 'const x = await ...;'
```

| Written | Message (all E0801) |
| --- | --- |
| `f(await p)`, `if (await p)`, `[await p]`, `` `${await p}` ``, `for (const x of await p)`, `await p as T` | the one above |
| `n += await p`, `xs[i].f = await p` | `'await' can only be assigned with '=' to a variable or a field for now; await into a 'const' first, then use it` |
| `await` in a `match` arm | `'await' inside match arms are not supported yet` |
| `await` in a `try` that has a `finally`, or in the `finally` | `'await' statements in a 'try' with a 'finally' are not supported yet` |

## 9. `spawn`, `JoinHandle`, `spawnBlocking`, and a task that panics

`spawn(call)` takes an async function's call or an async arrow, starts it on the runtime's worker
threads (tasks really run in parallel), and gives a `JoinHandle<T>`. `await handle` gives the
task's `T` and passes on what the task throws. A handle is awaited once and can't be cloned
(E0213); keep several in an array and take them out with `pop()`. `spawnBlocking(f)` runs a
synchronous function of no arguments on a thread of its own, for work that would block a worker,
and gives the same kind of handle; an async function is refused there (E0305).

A panic in a task prints its message and ends that task only. `await handle` then panics in turn
(`a task this awaited panicked: <reason>`, with the hint `await 'handle.join()' to catch it as a
TaskPanic instead`), while `await handle.join()` throws `TaskPanic` beside the task's own errors.

```fsh
class Oops { constructor(public why: string) {} }
async function risky(n: i64): Promise<i64> throws Oops {
  await sleep(1);
  if (n === 1) throw new Oops("thrown");
  return [10][n as usize];
}
async function main() {
  let handles = [spawn(risky(1)), spawn(risky(0))];
  try {
    while (handles.length > 0) {
      const h = handles.pop()!;
      const v = await h;
      console.log("ok", v); // expect: ok 10
    }
  } catch (e) {
    console.log("error:", e.why); // expect: error: thrown
  }
  try {
    await spawn(risky(2)).join();
  } catch (e) {
    if (e instanceof TaskPanic) console.log("panic:", e.message);
  }
  const big = [1, 2, 3];
  const n = await spawnBlocking(() => big.length);
  console.log(n);
}
// expect: panic: index out of bounds: the len is 1 but the index is 2
// expect: 3
```

- The annotation `JoinHandle<i64>` fits only a task that throws nothing. A throwing task's handle
  has the type `JoinHandle<i64> throws Oops`, which can't be written: let it be inferred.
- `spawn(work());` with the handle dropped is a detached task; its panic is printed and changes
  nothing else. When `main` returns the program ends and tasks still running are abandoned.
- A task that panics inside a `Lock`, `RwLock` or `shared` `update` poisons it: the next use
  panics with `a task panicked while holding this lock, so the value it guards may be half
  changed`. More: the `async_task_panic_*` cases of `examples/async.fsh`.

## 10. Promise combinators

Each is awaited where it is called (E0305 otherwise) and takes an array literal of Promises or
`spawn` handles, or a `Promise<T>[]`. The listed Promises run concurrently.

| Call | Gives | Throws |
| --- | --- | --- |
| `Promise.all([a, b])` | a tuple, one element per Promise (`void` ones give `null`) | the first error; the rest are cancelled |
| `Promise.race([a, b])` | the union of their values, from the first to finish; losers are cancelled | the winner's error |
| `Promise.allSettled([a, b])` | per element `{ status: "fulfilled"; value }` or `{ status: "rejected"; reason }` | nothing |
| `Promise.any([a, b])` | the first success | `AggregateError<E>` when all fail |

```fsh
class Boom { constructor(public message: string) {} }
async function after(ms: i64, v: i64): Promise<i64> { await sleep(ms); return v; }
async function fail(ms: i64): Promise<i64> throws Boom { await sleep(ms); throw new Boom("boom"); }
async function main() {
  const [a, b] = await Promise.all([after(5, 1), Promise.resolve("n")]);
  const timed = await Promise.race([after(200, 1), sleep(5)]);
  console.log(a, b, timed); // expect: 1 n null
  const [x, y] = await Promise.allSettled([after(1, 7), fail(1)]);
  console.log(x.status, x.value); // expect: fulfilled 7
  if (y.status === "rejected") console.log(y.reason.message); // expect: boom
  try {
    await Promise.any([fail(1), fail(2)]);
  } catch (e) {
    console.log(e.name, e.errors.length); // expect: AggregateError 2
  }
}
```

- `Promise.race([work(), sleep(ms)])` is the timeout idiom: a `null` result means the sleep won.
- A `Promise<T>` stored in a variable, field or array can't throw and can't hold a `Ref` (E0602:
  `a stored 'Promise<i64>' can't throw yet`): build the list in the call, or catch inside the
  async function. A `JoinHandle<T>[]` variable isn't accepted either; list the handles.
- `new Promise<T>((resolve, reject) => { })` runs its executor at once, and using `reject` makes
  it throw what it is given. `Promise.reject<T>(e)` and `Promise.withResolvers<T>()` exist too;
  `.then` does not (E0502: `'Promise<i64>' has no method 'then'`).
  More: `examples/promise.fsh`, `examples/promise_new.fsh`.

## 11. Timers

`await sleep(ms)` suspends the task; `await yieldNow()` lets other tasks run. `setTimeout(f, ms,
...args)` and `setInterval` give a `Timeout` (an `i64` id) for `clearTimeout` and
`clearInterval`. Timers work from a sync `main` too, and the program stays alive until pending
ones have fired. The callback owns what it captures, so it can't change a captured local (E0210:
`a timer's function owns what it captures, so changing 'n' would change only its own copy`); it
counts in an `Atomic`, and an interval that stops itself reads its own id from one.

```fsh
async function main() {
  const state = shared({ n: new Atomic(0), id: new Atomic(0) });
  const s = state.clone();
  state.id.store(setInterval(() => {
    const n = s.n.add(1) + 1;
    console.log("tick", n);
    if (n === 2) clearInterval(s.id.load());
  }, 5));
  clearTimeout(setTimeout(() => { console.log("never"); }, 1));
  setTimeout((label: string) => { console.log(label); }, 60, "late");
  console.log("main ends");
}
// expect: main ends
// expect: tick 1
// expect: tick 2
// expect: late
```

## 12. What may cross into a task

A spawned task, a `spawnBlocking` function, a `shared` value, a `Channel` and a stored Promise
may be used from another thread, so they must own everything they hold. This is Rust's `Send`
rule, enforced as E0303. The fix is to move or clone into the task: `spawn(first(names.clone()))`
with an owned parameter, or an async arrow, which takes over what it names.

```fsh
async function first(xs: Ref<string[]>): Promise<string> { return xs[0]; }
async function main() {
  const names = ["a"];
  const h = spawn(first(names));
  const x = await h;
  console.log(x);
}
// error: error[E0303]: 'spawn' runs this Promise on another thread, so it must own everything it uses; it holds a 'Ref<string[]>', which borrows from this function; pass an owned value, or a clone
```

The other E0303 messages, the first with the same opening for `spawn` and `spawnBlocking`:

- `it holds a 'Cell<i64>', which changes without a lock, so only one thread may use it`
- `a 'shared' value is used from many threads at once, so it can't hold a 'Cell<i64>'` (or `a
  'Ref<i64>', which borrows from one place`), and `a 'shared' value can't hold a JoinHandle`
- `a 'Channel' carries values to other tasks, so it can't carry a 'Cell<i64>'`
- `a stored 'Promise<i64>' may be awaited on any thread, so its future can't hold a 'Ref<string>'`

## 13. `shared`, `Lock`, `RwLock`, `Atomic`

State that several tasks change lives in one of these. None has a guard object: every access is
a method call, and `update` and `read` take an arrow written in place.

| Type | Made with | Used with |
| --- | --- | --- |
| `shared<T>` | `shared(value)`, `shared<T>(value)` | `.clone()` for another handle to the same value, fields read directly, `.update((v) => ...)` to change |
| `Lock<T>` | `new Lock(value)` | `.update((v) => ...)`, which gives what the arrow returns |
| `RwLock<T>` | `new RwLock(value)` | `.read((v) => ...)` for many readers, `.update((v) => ...)` for one writer |
| `Atomic<T>`, integer or boolean | `new Atomic(0)`, `new Atomic(false)` | `load`, `store`; `exchange`, `compareExchange(expected, next)` and, on integers, `add` and `sub` give the old value |

Of these only `shared` can be cloned (a `Channel` can too). `Lock`, `RwLock`, `Atomic` and
`Semaphore` can't (E0213): to reach one from several tasks, make it a field of a `shared` value.

```fsh
type Stats = { hits: i64; names: string[]; live: Atomic<i64>; log: Lock<string[]> };
async function visit(stats: shared<Stats>, name: string): Promise<void> {
  stats.live.add(1);
  await sleep(1);
  stats.log.update((lines) => lines.push("visit " + name));
  stats.update((s) => { s.hits += 1; s.names.push(name); });
  stats.live.sub(1);
}
async function main() {
  const stats = shared<Stats>({ hits: 0, names: [], live: new Atomic(0), log: new Lock<string[]>([]) });
  const a = spawn(visit(stats.clone(), "a"));
  const b = spawn(visit(stats.clone(), "b"));
  await Promise.all([a, b]);
  const names = stats.update((s) => s.names.length);
  console.log(stats.hits, names, stats.live.load()); // expect: 2 2 0
  const config = new RwLock<string[]>(["a"]);
  config.update((xs) => xs.push("b"));
  const flag = new Atomic(false);
  const was = flag.exchange(true);
  console.log(config.read((xs) => xs.length), was, flag.load()); // expect: 2 false true
}
```

Rules the compiler enforces (E0304 unless noted). More: `examples/shared.fsh`, `lock.fsh`,
`rwlock.fsh` and `atomic.fsh` there.

- A `shared` value's plain fields change only inside `update`: `state.hits = 1` is `cannot assign
  to 'state.hits' because 'state' is shared between threads; change it inside 'state.update(...)'`.
  Its `Atomic` and `Lock` fields are used through their own methods, inside `update` or not.
- The callback of `update` or `read` can't `await`: `'update' holds its lock while the callback
  runs, so the callback can't 'await'`. Copy what you need out, then await.
- The callback can't return the guarded value itself (E0801: `closures returning references are
  not supported yet`): return a copy, `(v) => v + 0` or `(xs) => xs.clone()`.
- Locks are not reentrant: an `update` inside an `update` of the same lock panics with ``this
  lock is already held by an `update` running here``.

## 14. `Channel` and `Semaphore`

`new Channel<T>(capacity)` is a bounded queue; the type argument is required (E0104) and the
capacity is at least 1. `await ch.send(v)` waits while it is full; `await ch.receive()` gives
`T | null`, `null` once the channel is closed and empty; `ch.close()` ends it; `ch.clone()` is
another handle to the same channel; `for await (const v of ch)` receives until it closes. Sending
on a closed channel panics. A `Channel<T | null>` is refused, since `null` already means closed.
`new Semaphore(n)` limits how many tasks are inside a section: `await sem.acquire()` gives a
`Permit` that returns its slot when it is dropped at the end of its scope, and `sem.available()`
counts free slots. Bind the permit, or it is dropped at once. More: `examples/channel.fsh`,
`examples/semaphore.fsh`.

```fsh
async function produce(ch: Channel<string>): Promise<void> {
  for (const s of ["a", "b", "c"]) await ch.send(s);
  ch.close();
}
async function main() {
  const ch = new Channel<string>(2);
  const p = spawn(produce(ch.clone()));
  const first = await ch.receive();
  console.log(first); // expect: a
  for await (const s of ch) console.log(s); // expect: b
  await p; // expect: c
  const after = await ch.receive();
  console.log(after === null); // expect: true
  const sem = new Semaphore(2);
  {
    const _permit = await sem.acquire();
    console.log(sem.available()); // expect: 1
  }
  await sem.acquire();
  console.log(sem.available()); // expect: 2
}
```

## 15. Cancellation

Cancellation is cooperative, through `AbortSignal`. `new AbortController()` has `signal` and
`abort()`; a signal has `aborted` (read-only), `throwIfAborted()` and `clone()`. There is no
`reason` and no `addEventListener`. The waits take a signal as their last argument: `sleep(ms,
signal)`, `ch.receive(signal)`, `ch.send(v, signal)`, `sem.acquire(signal)`. With one, the await
can throw `AbortError`, which is caught or declared like any error. `AbortSignal.timeout(ms)`
aborts by itself (it needs an async `main`), and `AbortSignal.any([a, b])` aborts when any does.
A loop that never waits checks by hand with `signal.throwIfAborted()`. Dropping a Promise also
cancels it: the losers of `Promise.race` and `Promise.any` stop at their current `await`. More:
`examples/abort.fsh`.

```fsh
async function worker(signal: AbortSignal): Promise<void> throws AbortError {
  while (true) await sleep(5, signal);
}
async function main() {
  const c = new AbortController();
  try {
    await sleep(60000, AbortSignal.any([c.signal, AbortSignal.timeout(10)]));
  } catch (e) {
    console.log("timed out", c.signal.aborted); // expect: timed out false
  }
  const h = spawn(worker(c.signal));
  await sleep(40);
  c.abort();
  try { await h; } catch (e) { console.log(e.message, c.signal.aborted); }
}
// expect: This operation was aborted true
```

## 16. Async generators, `for await`, async closures

`async function*` has the return type `AsyncGenerator<T>`, optionally with `throws E`. Like a
Promise it runs nothing until asked. `await g.next()` gives `{ done: true }` or `{ done: false;
value }`, and advancing needs a `let` binding. `for await` loops over an async generator, a
`Channel` or a `ReadableStream`, not an array of Promises (E0119), and a plain `for...of` over an
async generator is refused the same way. `next(value)` is not supported. An async arrow is a
function giving a Promise, typed `(x: i64) => Promise<i64>`; each call makes a lazy Promise. It
can't assign to a captured local (E0210: `this async arrow changes 'n', which it captured, but each
call's future works on its own copy`), and as a callback type it can't throw (section 5).

```fsh
async function* pages(n: i64): AsyncGenerator<string> throws string {
  for (let i = 0; i < n; i++) {
    await sleep(1);
    if (i === 1) throw "no page 1";
    yield "page " + i;
  }
}
async function main() {
  let g = pages(1);
  try {
    const first = await g.next();
    if (first.done === false) console.log("first", first.value); // expect: first page 0
    for await (const p of pages(5)) console.log(p); // expect: page 0
  } catch (e) {
    console.log("caught", e); // expect: caught no page 1
  }
  const base = 10;
  const add = async (n: i64) => { await sleep(1); return n + base; };
  let ps: Promise<i64>[] = [];
  for (const x of [1, 2, 3]) ps.push(add(x));
  const out = await Promise.all(ps);
  console.log(out); // expect: [ 11, 12, 13 ]
}
```

**Symptom**: `xs.map(async (x) => ...)` then `Promise.all` does not compile (E0801: `'map' with a
callback giving a Promise isn't supported yet; await each value in a 'for...of' loop instead`).
**Fix**: a `for...of` loop that awaits, or push calls into a `Promise<T>[]` as above.
More: `examples/async_generator.fsh`.

## 17. Task groups

`await taskGroup(async (group) => { ... })` is structured concurrency: `group.spawn(call)` starts
a child task, and the `await` returns only when the arrow and every child have finished, giving
what the arrow returns. Nothing a group starts outlives it, so there are no handles to collect
and no detached tasks. It is a built-in, not in `std-api.md`. Use it where TypeScript writes
`Promise.all` over tasks that should stop together; children still obey the rules of section 12,
so each is passed clones and collects into a `shared`, an `Atomic` or a `Channel`.

```fsh
async function size(text: string, ms: i64, total: shared<{ n: Atomic<i64> }>) {
  await sleep(ms);
  total.n.add(text.length as i64);
  console.log("counted", text); // expect: counted quick
}                               // expect: counted slow
async function main() {
  const total = shared({ n: new Atomic(0) });
  const mine = total.clone();
  const label = await taskGroup(async (group) => {
    group.spawn(size("slow", 60, mine.clone()));
    group.spawn(size("quick", 5, mine.clone()));
    return "sizes";
  });
  console.log(label, total.n.load()); // expect: sizes 9
}
```

When the arrow or a child throws, `group.signal` aborts, the group waits for the others to stop,
and the first error leaves the `await`: the group throws what its arrow throws and what its
children throw, with no handle to await. A child sees the abort only if it was given the signal.
A child's panic is re-raised at the `await` (`a task this awaited panicked: <reason>`). Dropping
the group's Promise, as the loser of a `Promise.race`, aborts the signal too.

```fsh
class NotFound { path: string; constructor(path: string) { this.path = path; } }
async function find(path: string): Promise<void> throws NotFound {
  await sleep(20);
  throw new NotFound(path);
}
async function slow(signal: AbortSignal) {
  try { await sleep(60000, signal); } catch (e) { console.log("sibling stopped"); }
}
async function main() {
  try {
    await taskGroup(async (group) => { group.spawn(slow(group.signal)); group.spawn(find("users/7")); });
  } catch (e) {
    console.log("caught", e.path);
  }
  // expect: sibling stopped
  // expect: caught users/7
}
```

The call is awaited where it is written and takes an async arrow written in place. A child that
can throw is spawned in the arrow's own body (a loop or a branch there is fine), not inside a
nested closure such as `forEach`, and not through a group passed to another function (E0306). A
`try` around `group.spawn(...)` catches nothing, since the error surfaces at the group's `await`
(E0603). More: `examples/taskgroup.fsh`.

```fsh
class Oops { why: string; constructor(why: string) { this.why = why; } }
async function fails(n: i64): Promise<void> throws Oops { await yieldNow(); throw new Oops("failed " + n); }
async function nested() throws Oops { await taskGroup(async (group) => { [1, 2].forEach((n) => group.spawn(fails(n))); }); } // error: error[E0306]
async function named() { const pending = taskGroup(async (group) => { await yieldNow(); }); await pending; } // error: 'taskGroup' is awaited where it is called
async function main() {}
```

## 18. `await using`

A class's `[Symbol.dispose]()` runs when an instance is dropped, and `using` pins a value to its
block (`ownership.md`, section 18). A drop can't wait, so cleanup that must `await` (a flush, a
rollback, a goodbye message) goes in `async [Symbol.asyncDispose](this: Mut<this>):
Promise<void>`, which only `await using x = value;` runs: it awaits the method on each ordinary
way out of the block, an early `return`, a `break` and a throw included. The method may declare
`throws`; the enclosing function then throws that too.

```fsh
class Conn {
  name: string;
  constructor(name: string) { this.name = name; }
  async [Symbol.asyncDispose](this: Mut<this>): Promise<void> {
    await sleep(1);
    console.log("flushed", this.name);
  }
}
async function work(stop: boolean): Promise<i64> {
  await using c = new Conn("db");
  if (stop) return 1;
  console.log("working on", c.name);
  return 2;
}
async function main() {
  const n = await work(true);
  // expect: flushed db
  console.log(n); // expect: 1
}
```

- Declared with `const`, such a value is never flushed: nothing but `await using` calls the
  method, and calling it by hand is E0710.
- A panic, or the Promise being dropped mid-way, awaits nothing. A class whose release must not
  be skipped declares both methods: `[Symbol.dispose]()` then runs alone on those two paths, and
  the async one stands in for it on the ordinary ones.
- `await using` needs an async function that is not a generator, and a class with the async
  method; a class with only `[Symbol.dispose]()` takes plain `using` (E0411 either way). It can't
  stand in a `match` arm, a `try` with a `finally`, or straight in a `switch` case, and a
  `return`, `break` or `continue` inside a `try` with a `finally` can't leave its block (E0412):
  keep the result in a variable and return after the `try`.

```fsh
class Sync { [Symbol.dispose](this: Mut<this>): void {} }
class Conn { async [Symbol.asyncDispose](this: Mut<this>): Promise<void> {} }
function notAsync() { await using c = new Conn(); }         // error: error[E0411]
async function wrongKind() { await using s = new Sync(); }  // error: error[E0411]
async function inTry(): Promise<i64> { await using c = new Conn(); try { return 1; } finally { console.log("done"); } } // error: error[E0412]
async function main() {}
```
