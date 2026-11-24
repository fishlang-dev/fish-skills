# Porting TypeScript to Fish

Turning a TypeScript file or project into Fish that compiles and behaves the same: `fishc survey`,
`fishc lint`, the `fishc check` loop, the rule tables behind them, and a before and after for each
common rewrite (`ts` blocks are the unchecked originals; every `fsh` block is checked). What
the Fish side means is in `language.md`, `ownership.md`, `types.md` and `errors-async.md`; keeping
a part in JavaScript is in `interop.md`. Checked against fishc 0.1.3.

## 1. The procedure

The run below ports a 42-line word counter: `src/store.ts` (an `Entry` interface, a `Store` class,
two helpers) and `src/main.ts` (top-level statements reading the JSON file in `process.argv[2]`).

1. **Survey.** `fishc survey <dir>` reads every `.ts`, `.tsx` and `.mts` file outside `node_modules`
   and dot-directories (not `.d.ts`, not `.fsh`), from syntax alone, and exits 0.

```
$ fishc survey .
fishc survey: 2 files, 42 lines read
grade B (score 9 per 1000 lines)
  rejected: 0
  guided:   3
  auto-fix: 6

dependencies (3, 1 dev)
  in std:           1  express (serve and Router)
  planned:          1  vitest (Jest-style test API)
  not installed:    1  lodash
```

   (Cut: `top rewrites`, at most ten rules, here one hit each for `any`, a `number` used as an
   index and top-level code with side effects, as a count, the title and `e.g. src/main.ts:6:30`.)
2. **Decide whether to port.** A `rejected` hit is a redesign of that code, and a `waiting on Fish`
   hit blocks its file until rewritten away (section 9). Guided hits are ordinary work, about one
   decision each. Start with files that have no waiting hits and that other files import.
3. **Lint and fix, naming the files.** `fishc lint <files>` prints each hit with its source line,
   as in `src/store.ts:4:7: auto A2: the optional '?: string' becomes ': Option<string>'`, and
   exits 1 while anything is left. `--fix` first writes every `auto` hit, renames each `.ts` file
   to `.fsh` (refusing when that name exists) along with the relative `./x.ts` imports of it, then
   prints what is left. A directory stands for its `.fsh` files only, so `fishc lint src` over
   `.ts` files prints `0 to change in 0 files`. `fishc lint --fix src/store.ts src/main.ts` printed
   `fixed 6 in src/store.ts`, `renamed src/store.ts to src/store.fsh`, then the hits left, the
   first `src/store.fsh:10:23: guided A6: an ownership type the lint inserted: check it, then
   remove the marker` under `add(this: Mut<this> /* fish: review */, word: string): void {`, and
   last `7 to change in 2 files`. Keep this output: a renamed file is in the native edition, and
   `fishc lint src/main.fsh` then answers `'src/main.fsh' is in the native edition, so there's
   nothing to lint`. Section 5 says how to lint it again.
4. **Run `fishc check <entry>.fsh` until it is quiet.** File-level errors come first, then each
   function body reports only its first error per run, so fix what is shown and run it again.
   This run took six rounds (`any`, `==` and a changed `const` are left out of the table):

| Round | Printed | Fix |
| --- | --- | --- |
| 1 | `error[E0404]: only declarations are allowed at the top level; move this into main()` | wrap the statements in `function main()` |
| 2 | `error[E0115]: an array can't hold the interface type 'Entry' directly, since its values may each be a different type; use 'Dyn<Entry>[]' to hold any of them` | an `interface` of fields is data: write `type Entry = { ... }` |
| 3 | `error[E0202]: can't move a value out of a reference to it, which only borrows it; use '.clone()' to hand over a copy` | `return e.clone()` from the loop over `this.entries` |
| 3 | `error[E0111]: operator '+' can't mix 'i64' and 'number'; convert one side with 'as', like 'x as i64'` | `count: i64`, as `let sum = 0` is an `i64` |
| 3, 6 | `error[E0102]: condition must be a boolean, not the Option 'null \| string'; check it with '!== null'` | compare with `null` |
| 4 | `error[E0602]: 'load' must declare 'throws IoError' after its return type since 'readFileSyncText' can throw 'IoError', or catch it with try/catch` | add the clause |
| 5 | `error[E0602]: 'JSON.parse' can throw 'JsonError', which isn't the 'IoError' that 'load' throws; convert it, or have 'IoError' implement 'From<JsonError>'` | `throws IoError \| JsonError`, on `main` too |

5. Delete each `/* fish: review */` marker once confirmed (section 4), then prove it (section 10).

## 2. Reading the survey

- **Grade.** Score = (10 x rejected + 3 x guided) x 1000 / max(lines, 1000), to one decimal, over
  the non-blank lines of the files that parsed. `A` is up to 5, `B` up to 15, `C` up to 40, `D` up
  to 100, `F` above. The compiler's own sample has 3 rejects and 8 guided in 35 lines: 54, grade D.
  When fewer than half the lines parsed it prints `no grade: only N% of the lines could be read`.
- **`auto-fix` and `waiting on Fish` weigh nothing.** A project importing `node:events` in every
  file still prints `grade A (score 0 per 1000 lines)`. The grade measures rewriting work;
  `waiting on Fish` (the unsupported rules) and `Node built-ins` say whether it can compile at all.
- **`dependencies`** sorts `package.json`: `in std` (as `serve` and `Router` replace express, hono,
  fastify and koa, and `fetch` replaces axios, got and node-fetch), `planned` (nothing in the
  release), `native` (a compiled addon), `pure` (plain JavaScript, a candidate for npm interop)
  and `not installed` (only installed copies are read: run `npm install` first).
- **`Node built-ins`** lists a built-in only when an import needs something std lacks, as in
  `events    2 files  planned: EventTarget and EventEmitter`, `dns    1 file   nothing planned`, or
  `fs    1 file   in std: fs, for readFileSync, ...` when a file imports `createReadStream`.
- **`--json`** prints the report as JSON (`files`, `lines`, `unread`, `score`, `grade`, `counts`,
  `rules`, `waiting`, and `dependencies` and `builtins` when present; a rule has `id`, `action`,
  `title`, `count` and up to three `examples`). **`--compare <old.json>`** surveys again and prints
  the change from such a report. After one `any` was typed: `grade B -> B, score 9 -> 6 (-3) per
  1000 lines`, `  guided    3 -> 2 (-1)`, and under `rewrites that changed` the rule with `(1 -> 0)`.
- **`fishc survey --rank <dir>...`** starts with `portable now: N% of lines (M files)`.

## 3. The survey's rules

`reject` (weight 10): no Fish equivalent, so the code is redesigned. `guided` (weight 3): a person
chooses the rewrite; the lint reports `G1` to `G12`, never editing them, and only the survey counts
the rest. `auto` (weight 0): `fishc lint --fix` rewrites it. `unsupported` (weight 0, printed as
`waiting on Fish`): not compiled yet, often `error[E0801]` with a message ending `not supported yet`.

| Id | Action | Title | `fishc lint` says |
| --- | --- | --- | --- |
| `R1` | reject | eval and new Function: a native binary has no compiler to run code made at run time | eval and new Function run code made while the program runs, and a native binary has no compiler for it; write the code itself, or choose among functions with a Map or a switch |
| `R2` | reject | prototype edits and Object.defineProperty: Fish types have fixed layouts | prototype edits and Object.defineProperty change a type after it is declared, and Fish types have fixed layouts; declare the field or method on the class, or wrap the value |
| `R3` | reject | delete on an object not declared as a dictionary: Fish objects have fixed layouts; use an Option field, a dictionary type or a Map | delete removes a field, and Fish objects have fixed layouts; make the field an Option and set it to null, or keep the entries in a dictionary, '{ [k: string]: T }', or a Map |
| `R5` | reject | the arguments object: use rest parameters | the arguments object isn't in Fish; take the arguments as a rest parameter, as in '...args: T[]' |
| `R6` | reject | Symbol: Fish has no runtime reflection | Symbol is runtime reflection, which Fish doesn't have beyond a '[Symbol.iterator]' method and a class's '[Symbol.dispose]' and '[Symbol.asyncDispose]' methods; use a string or an enum for a key, and an interface for a protocol |
| `R7` | reject | declaration merging and module augmentation: Fish types are closed after they are declared | declaration merging and module augmentation reopen a type after it is declared, and Fish types are closed; give everything in one declaration, or a new name |
| `dynamicRegex` | reject | regexes built while the program runs: Fish compiles every regex while compiling | - |
| `G1` | guided | any: choose a concrete type, a union, unknown narrowed before use, or the dynamic Json value | 'any' turns type checking off, which Fish doesn't do; choose a concrete type, a union, 'unknown' narrowed with 'typeof' or 'instanceof' before use, or the dynamic 'Json' value |
| `G2` | guided | a promise dropped un-awaited: add await, or spawn() it to run on its own | the promise this call gives is dropped, and a Fish future runs only when it is awaited; add 'await', or wrap the call in 'spawn()' to run it on its own |
| `G3` | guided | a number used as a count or an index: make it i64, or usize for an index | this 'number' counts or indexes, and a Fish 'number' is a float; make it 'i64', or 'usize' for an index |
| `G4` | guided | class extends with the base used as a type: Fish embeds the base, so a polymorphic hierarchy becomes an interface | this class extends one that is also used as a type, so a subclass stands in for its base, which Fish's embedded bases don't allow; extract an interface for what they share, and hold the base as a field |
| `G5` | guided | instanceof a class others extend: match on an interface or an enum instead | 'instanceof' tests a class that others extend, and Fish has no subclass checks at run time; 'match' on an interface or an enum instead |
| `G6` | guided | indexing an object not declared as a dictionary with a string key, or testing a key known only at run time with 'in': declare it '{ [k: string]: T }' or 'Record<string, T>', or use a Map | indexing with a string key, or testing one with 'in' that isn't written as a literal, reads the object as a dictionary, which a Fish object isn't; declare it as one, '{ [k: string]: T }' or 'Record<string, T>', or use a 'Map<string, T>' |
| `G7` | guided | top-level code with side effects: move it into main() or a Lazy<T> | top-level code runs when the module loads, which Fish doesn't do; move it into 'main()', or into a 'Lazy<T>' for a value made once |
| `G8` | guided | isNaN after parsing: Fish's parsing gives an Option to check | parsing gives an 'Option' in Fish rather than NaN; 'match' on the parsed 'Option' instead of checking 'isNaN' |
| `G9` | guided | .call, .apply and .bind: pass the receiver explicitly or use a closure | '.call', '.apply' and '.bind' choose a function's 'this' at run time; pass the receiver as an argument, or use a closure |
| `G10` | guided | an async callback passed to forEach: use for...of with await, or spawned tasks | 'forEach' doesn't wait for an async callback; use 'for...of' with 'await', or spawn a task for each |
| `G11` | guided | a value aliased and changed from two names: Rc<T> in one thread, shared<T> across tasks, a .clone(), or restructuring | hold one value, changed through one while the other is still used, which Fish's ownership refuses; share it as 'shared<T>', give one its own '.clone()', or restructure so one name is used at a time |
| `G12` | guided | DisposableStack, and Symbol.dispose and Symbol.asyncDispose beyond a class's methods: give a class a [Symbol.dispose]() method, which runs when an instance is dropped, or an async [Symbol.asyncDispose]() one for 'await using' | Fish disposes through a class's own methods alone: '[Symbol.dispose]()', which it runs when an instance is dropped, and 'async [Symbol.asyncDispose]()', which an 'await using' declaration awaits; 'DisposableStack', a call of either by hand, and either member on an object literal or an interface aren't in Fish yet, so give a class the method and let its instance go out of scope |
| `destructuring` | guided | destructuring Fish can't take as written: computed keys known only at run time, a default on a whole destructured parameter, or nesting, defaults and rest in a loop head; name the parts, or destructure in the body | - |
| `localCaptures` | guided | a class or enum declared inside a function that uses the function's variables: pass them to its constructor | - |
| `destructuringAssignment` | guided | a destructuring assignment used as a value or as a for update: write it as a statement of its own | - |
| `defaults` | guided | a default Fish can't take as written: before a required parameter, on a parameter that may be null, or neither typed nor a literal; move it last, use '?' and default in the body, or write the type | - |
| `declarators` | guided | a let with neither a type nor a value: write its type, as in 'let x: string', since Fish doesn't work it out from later assignments | - |
| `spread` | guided | rest parameters on arrow functions, and spread arguments: Fish takes rest parameters on declared functions and methods, and spreads an array argument only into a rest parameter, or a tuple held in a variable into any parameters | - |
| `forAwaitArrays` | guided | for await over an array of promises: Fish loops with for await over an async generator or a Channel, so await Promise.all(...) and loop over its result with for...of | - |
| `regexStrings` | guided | match, matchAll and search given a string, and next() on matchAll: Fish takes a regex literal there, and matchAll gives an array | - |
| `regexState` | guided | exec or test on a g or y regex, and lastIndex: a Fish regex keeps no state; use matchAll, or drop the flag | - |
| `tagged` | guided | tagged templates: a Fish tag takes its strings as 'comptime strings: TemplateStringsArray', so its code over them runs while compiling | - |
| `A1` | auto | var: const or let | rewrites it: section 4 |
| `A2` | auto | null, undefined and ?: Option | rewrites it: section 4 |
| `A3` | auto | == and !=: === and !== | rewrites it: section 4 |
| `A4` | auto | a top-level let: a const holding an Atomic | rewrites it: section 4 |
| `A8` | auto | JSON.parse(s) as T: JSON.parse<T>(s) | rewrites it: section 4 |
| `A9` | auto | function expressions: arrow functions | rewrites it: section 4 |
| `parse` | unsupported | files Fish's parser can't read | - |
| `unreadable` | unsupported | files that couldn't be opened | - |
| `jsx` | unsupported | JSX in .tsx files | - |
| `moduleForms` | unsupported | namespace imports, 'import x = require()', 'export =' and dynamic import() | - |
| `pathAliases` | unsupported | imports through path aliases such as '@/lib' or '~/lib' | - |
| `bunModules` | unsupported | imports of Bun's own modules such as bun:test | - |
| `untypedPackages` | unsupported | imports of installed npm packages with no TypeScript declarations | - |
| `nodeBuiltins` | unsupported | imports of Node built-in modules such as node:fs | - |
| `tuples` | unsupported | a rest element before the end of a tuple type, or one beside optional elements | - |
| `collections` | unsupported | WeakMap and WeakSet | - |
| `readonlyCollections` | unsupported | ReadonlyMap and ReadonlySet (more utility types) | - |
| `forIn` | unsupported | for...in loops over an object's keys | - |
| `decorators` | unsupported | decorators, which Fish runs as macros, so a framework's decorators need a Fish macro of the same name | - |
| `namespaces` | unsupported | namespaces and module declarations | - |
| `genericFunctionsHeld` | unsupported | generic function types held in class fields, arrays or unions, which would box a family of functions | - |
| `classForms` | unsupported | abstract fields, and '#x in obj' checks | - |
| `process` | unsupported | process members besides argv, env, exit, platform, arch, execPath, cwd, chdir, on, once, kill, pid, stdout.write and stderr.write, and writes to process.env | - |
| `bunGlobals` | unsupported | Bun members besides file, stdin, write, env, argv, sleep, sleepSync, which, spawn, spawnSync, serve and version | - |
| `importMeta` | unsupported | import.meta besides its path, file, dir, url, main, dirname and filename members | - |
| `timerForms` | unsupported | setImmediate, unref on a timer, and more than two arguments passed on to a timer's function | - |
| `console` | unsupported | console methods besides log, error and warn | - |
| `json` | unsupported | JSON.parse revivers, and JSON.stringify's replacer and indent arguments | - |
| `nestedFunctions` | unsupported | generic or generator function declarations inside a function | - |

## 4. What the lint rewrites, and the review marker

Each rewrite is made only when the source alone makes it certain; otherwise the hit stays, most
often with the same rule id printed as `guided`, and sometimes still as `auto` with the reason it
couldn't be made (`a comment sits where this change would go`). `A5`, `A6`, `A7` and `A10` are the lint's own and not in the survey's table.

| Rule | Rewrite | Not made when |
| --- | --- | --- |
| `A1` | `var` to `const`, or `let` when it is assigned again | function scoping matters: declared twice, used outside its block, or its value carries between loop turns |
| `A2` | `T \| null`, `T \| undefined` and `x?: T` to `Option<T>`; `?.` and `??` stay | |
| `A3` | `==` to `===`, `!=` to `!==` | both sides' types are not evident from literals, as in `o.a == 1` |
| `A4` | a top-level `let n = 0` that is only counted up or down to `const n = new Atomic(0)`, `n.add(1)`, `n.load()` | it is exported, or used any other way |
| `A5` | an object parameter the body only reads to `Ref<T> /* fish: review */` | the body returns it or assigns it somewhere |
| `A6` | an object parameter the body changes to `Mut<T> /* fish: review */` | as `A5` |
| `A7` | a method assigning its fields gets `this: Mut<this> /* fish: review */` as first parameter | |
| `A8` | `JSON.parse(s) as T` to `JSON.parse<T>(s)` | the cast is `as const` |
| `A9` | a `function` expression to an arrow function | it uses its own `this` or `arguments`, calls itself, or is constructed |
| `A10` | `"./x.ts"` in an import to `"./x.fsh"`, and the file's own name | both `x.ts` and `x.fsh` exist |

A fix that would delete a comment is not made (`a comment sits where this change would go, so it
can't be made automatically; make it by hand`). `/* fish: review */` follows every ownership type
the lint inserted: a guess from one file's syntax, reported as `an ownership type the lint
inserted: check it, then remove the marker` until deleted. Two wrong guesses `fishc check` catches:

- **Symptom**: `error[E0101]: argument of type 'Ref<{ lines: string[] }>' is not assignable to
  parameter of type 'Mut<{ lines: string[] }>': a shared reference can't lend itself as mutable`.
  **Why**: the parameter is passed to a function in another file that changes it. **Fix**: `Mut<T>`.
- **Symptom**: `error[E0202]: can't move a value out of a reference to it, which only borrows it;
  use '.clone()' to hand over a copy` at `logs.push(log)`. **Why**: the body stores the parameter,
  so it must own it. **Fix**: remove the wrapper and keep the plain type.

## 5. Editions

The first line of a file (the second after a shebang) may be `// @fish-edition native` or
`// @fish-edition ts-compat`, and `fish.toml` may set `edition = "ts-compat"` under `[package]`
for files without one. Anything else is `error[E0005]`, or in the manifest `error[E0905]: 'ts'
isn't an edition; it is "native", the default, or "ts-compat" for TypeScript not yet migrated`.
In this release `ts-compat` relaxes no rule: the compiler refuses the file, and the lint reads it.

```fsh
// @fish-edition ts-compat
function main() {}
// error: error[E0006]: this file is in the TS-compat edition, which Fish doesn't compile; run 'fishc lint' to find what to change, then mark it '// @fish-edition native'
```

A native file importing a ts-compat file fails with the same E0006 at the imported file. For a
whole project: set the manifest key, rename everything to `.fsh`, and `fishc lint` with no arguments
lists every unfinished file's hits. Mark each finished file native, and remove the key at the end.

## 6. Node built-ins

A std module is imported under its Node name, with or without `node:`. A member std lacks is
`error[E0902]: 'node:fs' has no export named 'createReadStream'`; a module std lacks is
`error[E0908]: 'node:events' is a Node module Fish's std doesn't have yet`. The survey's table:

| Node module | In Fish's std |
| --- | --- |
| `assert` | assert, for the default export and ok |
| `buffer` | Buffer, for from, alloc, allocUnsafe, concat, byteLength, compare, equals, toString, indexOf and includes of text, and the read methods |
| `child_process` | child_process, for spawnSync, execFileSync and execSync |
| `crypto` | crypto, for createHash, createHmac, randomBytes, randomUUID, getRandomValues and hash |
| `fs` | fs, for readFileSync, writeFileSync, existsSync, statSync and lstatSync with throwIfNoEntry, readdirSync with withFileTypes, realpathSync, mkdtempSync, rmSync, mkdirSync, renameSync, copyFileSync, unlinkSync, accessSync, utimesSync, lutimesSync, chmodSync, symlinkSync, linkSync, readlinkSync, openSync, readSync, writeSync, closeSync, fstatSync, ftruncateSync, fchmodSync, fsyncSync and constants with the open flags |
| `fs/promises` | fs/promises, for readFile, writeFile, open, access, utimes, lutimes, chmod, symlink, link, readlink, realpath and watch |
| `os` | os, for hostname, tmpdir, homedir, platform and availableParallelism |
| `path` | path, for join, dirname, basename, extname, resolve, relative, normalize, isAbsolute, parse and format |
| `process` | process, for argv, env, exit, platform, arch, execPath, cwd, chdir, pid, on, once, kill, signals, stdout.write and stderr.write |
| `url` | url, for fileURLToPath and pathToFileURL |
| `util` | util, for format, inspect, isDeepStrictEqual and parseArgs |
| `sqlite` | the sqlite module's Database, each call awaited |
| `zlib` | zlib, for gzipSync, gunzipSync, deflateSync, inflateSync, deflateRawSync, inflateRawSync and unzipSync, and those seven as promises |

Replaced by globals or other std names: `dgram` by UdpSocket; `net` by TcpListener, TcpStream,
UnixListener and UnixStream; `perf_hooks` by the global performance, for now(); `readline` by the
readLine global and the stdin module, for lines, text and bytes; `stream` by ReadableStream and
WritableStream, as globals; `string_decoder` by TextDecoder, with fatal; `timers` by the setTimeout
and setInterval globals; `timers/promises` by sleep; `worker_threads` by spawn and spawnBlocking.
Nothing in the release (the survey prints `planned: <feature>`): `async_hooks`, `console`, `events`,
`http`, `http2`, `https`, `querystring`, `test`, `tty`. The survey prints `planned: node:tls` for
`tls` too, though std has a `tls` module with `connect` alone (`std.md`). Not in the table (`nothing
planned`): `cluster`, `constants`, `diagnostics_channel`, `dns`, `domain`, `inspector`, `module`,
`punycode`, `repl`, `sys`, `trace_events`, `v8`, `vm`, `wasi`.

## 7. Recipes
### 7.1 `null`, `undefined`, optional fields, truthiness, indexing, `!`
```ts
function contact(u: { name: string; email?: string }) { return u.email ? `${u.name} <${u.email}>` : u.name; }
const title = input || "untitled", n = counts.get(key)! + 1, first = xs[0];
```
```fsh
type User = { name: string; email?: string };
function contact(u: Ref<User>): string {
  if (u.email === undefined) return u.name;
  return `${u.name} <${u.email}>`;
}
function main() {
  const bo: User = { name: "bo" };
  const input = "";
  console.log(contact(bo), input !== "" ? input : "untitled"); // expect: bo untitled
  let xs = ["a", "b"];
  const m = new Map<string, i64>([["a", 1]]);
  console.log(m.get("a")! + 1, xs.at(7) ?? "none", xs.pop(), xs.find((x) => x === "z")); // expect: 2 none b null
  console.log(xs[5]);
}
// panic: index out of bounds: the len is 1 but the index is 5
```
- A condition is a `boolean`: `if (s)`, `if (n)`, `if (xs.length)` and `if (opt)` are
  `error[E0102]`, and `s || "anon"` on a string is `error[E0103]`. Write the comparison the test
  stood for (`!== ""`, `!== 0`, `=== null`); `??` and `?.` stay, and work on Options only.
- `x?: T`, `T | null` and `T | undefined` are all `Option<T>`; comparing with `null` or `undefined`
  narrows, fields included. A literal may omit an optional field, but not when passed straight to
  a `Ref` parameter (`it has no 'email', which a reference can't fill in`).
- `xs[i]` panics out of range where TypeScript read `undefined`: use `xs.at(i)`. `pop`, `shift`,
  `find`, `at` and `Map.get` give Options, and `!` on an empty one panics.

### 7.2 `any` and untyped JSON
```ts
const cfg: any = JSON.parse(text);
```
```fsh
type Config = { host: string; port?: i64 };
function main() {
  try {
    const cfg = JSON.parse<Config>("{\"host\":\"h\"}");
    const loose = JSON.parse("{\"a\":[1,2]}");
    console.log(cfg.host, cfg.port ?? 8080, loose instanceof Map ? loose.size : 0); // expect: h 8080 1
    JSON.parse<Config>("{\"host\":1}");
  } catch (e) {
    console.log(e.message); // expect: expected string at $.host
  }
}
```
There is no `any` (`error[E0105]: cannot find type 'any'`). Name the shape, and `JSON.parse<T>`
checks it while parsing, throwing `JsonError`. With no type argument the result is a `Json` (`null`,
a boolean, number, string, `Json[]` or `Map<string, Json>`) to narrow. More: `examples/json.fsh`.

### 7.3 `number`
```ts
function average(xs: number[]) { let sum = 0; for (let i = 0; i < xs.length; i++) sum += xs[i]; return sum / xs.length; }
```
```fsh
function average(xs: Ref<i64[]>): f64 {
  let sum = 0;
  for (let i: usize = 0; i < xs.length; i++) sum += xs[i];
  return (sum as f64) / (xs.length as f64);
}
function main() {
  console.log(average([1, 2, 4]), 7 / 2, 7.0 / 2.0, 2.9 as i64, String(7) + "!"); // expect: 2.3333333333333335 3 3.5 2 7!
  console.log(parseInt("8080") ?? 80, parseInt("12abc"), parseInt("x"), Number("x")); // expect: 8080 12 null null
}
```
Choose per variable: a count, an id or anything compared with `.length` is `i64` (`usize` for an
index: `error[E0101]: an array's index is a 'usize', not 'i64'; convert it with 'as usize'`); a
measurement or a ratio is `f64`, which is what `number` means in Fish. A bare `0` is an `i64`, a
bare `0.5` an `f64`, and they never mix (`error[E0111]`) or convert on assignment, so `as` appears
where TypeScript relied on one float type. At run time `/` on integers truncates, overflow panics
in a debug build, and `parseInt`, `parseFloat` and `Number(text)` give `null`, not `NaN`.

### 7.4 Objects as dictionaries, `for...in`, changing a `const` collection
```ts
const counts: { [word: string]: number } = {};
for (const w of words) counts[w] = (counts[w] || 0) + 1;
```
```fsh
function main() {
  let counts = new Map<string, i64>();
  for (const w of ["a", "b", "a"]) counts.set(w, (counts.get(w) ?? 0) + 1);
  for (const [w, n] of counts) if (n > 1) console.log(w, n); // expect: a 2
  let seen: { [word: string]: boolean } = { a: true, b: true };
  delete seen["a"];
  console.log("a" in seen, seen["b"], seen["zzz"], Object.keys(seen)); // expect: false true null [ 'b' ]
}
```
A `Map` is the usual target; a type declared `{ [k: string]: T }` or `Record<string, T>` is also a
dictionary, whose reads give Options. `for (const k in o)` is `error[E0801]: 'for...in' loops are
not supported yet`: use `Object.keys(o)` or `Object.entries(o)`. A `const` is deeply immutable, so
`xs.push(x)` on one is `error[E0207]: cannot push to 'xs' because it is a constant`: use `let`.

### 7.5 Two names for one mutable object
```ts
const alias = cart; alias.items.push("tea"); badge.cart = cart; checkout.cart = cart;
```
`let alias = cart` moves the value, and the next use of `cart` is `error[E0201]: 'cart.items.length'
can't be used here because 'cart' was moved`. Choose by what the second name was for:
- a shorter name, or a leftover: delete it and use one name;
- a parameter of a helper: `Ref<T>` to read, `Mut<T>` to change, with the call site unchanged;
- a snapshot that must not see later changes: `.clone()`, which copies (on an `Rc` or a `shared`
  it gives another handle to the same value instead);
- a second long-lived holder in one thread: `Rc<T>`, changed through `.update(...)`;
- state several tasks or stored handlers change: `shared<T>`, changed through `.update(...)` (7.9).
```fsh
type Cart = { items: string[] };
function addItem(cart: Mut<Cart>, item: string) { cart.items.push(item); }
function main() {
  let cart: Cart = { items: [] };
  addItem(cart, "tea");
  const snapshot = cart.clone();
  addItem(cart, "milk");
  const badge = new Rc<Cart>(cart);
  const checkout = badge.clone();
  checkout.update((c) => c.items.push("jam"));
  console.log(snapshot.items.length, badge.items.length); // expect: 1 3
}
```
More: `ownership.md`, `examples/rc.fsh`, `examples/shared.fsh`.

### 7.6 Callbacks that capture and change
```ts
let total = 0; xs.forEach((x) => { total += x; }); function makeCounter() { let n = 0; return () => ++n; }
```
```fsh
function makeCounter(): () => i64 {
  const n = new Atomic(0);
  return () => n.add(1) + 1;
}
function main() {
  let total = 0;
  [1, 2, 3].forEach((x) => { total += x; });
  const next = makeCounter();
  console.log(total, next(), next()); // expect: 6 1 2
}
```
A callback run on the spot may change a local it captures. One returned or stored may not
(`error[E0210]: this closure changes 'n', which it captures, but a stored callable can't change
what it captures; keep that state in an 'Atomic' or a 'Lock'`), nor may two live closures change
one local (`error[E0203]`): give each a clone of an `Rc`. `Atomic.add` returns the old value.

### 7.7 Classes, hierarchies and interfaces
```ts
class Animal { heard = 0; constructor(public name: string) {} speak() { return `${this.name} makes a sound`; } hear() { this.heard++; } }
const zoo: Animal[] = [new Dog("rex"), new Animal("cat")];   // Dog extends Animal
```
```fsh
interface Speaker { speak(): string; }
class Animal {
  heard: i64 = 0;
  constructor(public name: string) {}
  speak(): string { return `${this.name} makes a sound`; }
  hear(this: Mut<this>) { this.heard++; }
}
class Dog extends Animal {
  speak(): string { return `${this.name} barks, then ${super.speak()}`; }
}
function intro(s: Ref<Speaker>): string { return s.speak(); }
function main() {
  let d = new Dog("rex");
  d.hear();
  console.log(intro(d), d.heard); // expect: rex barks, then rex makes a sound 1
  const zoo: Dyn<Speaker>[] = [new Dog("rex"), new Animal("cat")];
  console.log(zoo.map((z) => z.speak().length)); // expect: [ 33, 17 ]
}
```
`extends` embeds the base, so fields, methods and `super` work, but a `Dog` is not an `Animal`
(`error[E0704]: 'Dog' extends 'Animal' by embedding one, so it can't be used as 'Animal'; extract
an interface both classes implement`). Where the base was used as a type, name an interface, which
classes satisfy by shape: `Ref<Speaker>` for a parameter, `Dyn<Speaker>[]` for a mixed collection.
A method assigning a field declares `this: Mut<this>` (`error[E0206]: cannot assign to 'this.heard'
because 'this' is read-only here; declare 'this: Mut<this>'`) and is called on a `let`.

### 7.8 Thrown errors, promise chains, `Promise.all`
```ts
async function fetchUser(id: number) { if (id < 0) throw new NotFound(`no user ${id}`); return `user${id}`; }
fetchUser(1).then((u) => console.log(u)).catch((e) => console.error(e.message));
const users = await Promise.all(ids.map((id) => fetchUser(id)));
```
```fsh
class NotFound extends Error {}
async function fetchUser(id: i64): Promise<string> throws NotFound {
  console.log("fetching", id);
  if (id < 0) throw new NotFound(`no user ${id}`);
  await sleep(1);
  return `user${id}`;
}
async function main() {
  try {
    const pending = fetchUser(1);
    console.log("not started yet"); // expect: not started yet
    const one = await pending; // expect: fetching 1
    const more = await Promise.all([fetchUser(2), fetchUser(3)]);
    // expect: fetching 2
    // expect: fetching 3
    console.log(one, more); // expect: user1 [ 'user2', 'user3' ]
    await fetchUser(-1); // expect: fetching -1
  } catch (e) {
    console.log(e instanceof NotFound, e.message); // expect: true no user -1
  }
}
```
- A function that throws, or calls one that does without catching, says so after its return type
  (`throws A | B`); the compiler asks for each clause in turn (`error[E0602]`), up to `main`.
- A promise is lazy: the call runs nothing until awaited. A dropped call is `error[E0302]: this
  Promise does nothing until it's awaited, since Fish's promises are lazy; add 'await', or wrap
  the call in 'spawn(...)' for fire-and-forget`. There is no `.then` (`error[E0502]`).
- `ids.map((id) => f(id))` with an async `f` is `error[E0801]: 'map' with a callback giving a
  Promise isn't supported yet`: push the calls into a `Promise<T>[]` in a loop, which only takes
  calls that cannot throw (`error[E0602]: a stored 'Promise<string>' can't throw yet`).
- `console.log(await f())` is `error[E0801]: 'await' inside an expression isn't supported yet;
  give its value a name first, as in 'const x = await ...;'`.

### 7.9 An Express or `Bun.serve` handler
```ts
app.get("/todos", (req, res) => res.json(todos));
app.post("/todos", (req, res) => { todos.push({ id: todos.length + 1, title: req.body.title }); res.status(201).end(); });
```
```fsh
type Todo = { id: i64; title: string };
async function main(): Promise<void> throws IoError {
  const todos = shared<Todo[]>([]);
  let app = new Router();
  const all = todos.clone();
  app.get("/todos", async (_req) => Response.json(all.update((t) => t.clone())));
  const store = todos.clone();
  app.post("/todos", async (req) => {
    try {
      const body = await req.json<{ title: string }>();
      store.update((t) => t.push({ id: (t.length as i64) + 1, title: body.title }));
      return new Response("", { status: 201 });
    } catch (e) {
      return new Response(e.message, { status: 400 });
    }
  });
  const made = await app.handle(new Request("http://h/todos", { method: "POST", body: "{\"title\":\"port it\"}" }));
  const list = await app.handle(new Request("http://h/todos"));
  const text = await list.text();
  console.log(made.status, text); // expect: 201 [{"id":1,"title":"port it"}]
  if (process.argv.includes("--listen")) await serve({ port: 3000 }, app.handler());
}
```
A handler takes a `Request` and returns a `Response`; there is no `res`. Handlers are stored, so
state they change lives in a `shared`, one clone each. `req.json<T>()` checks the body,
`req.param("id")` reads a `:id` segment, and `app.handle(request)` runs a request with no socket.

### 7.10 `fs`, `path`, `process`
```ts
const lines = fs.readFileSync(path.join(dir, "in.txt"), "utf8").split("\n").filter(Boolean);
const mode = process.env.MODE || "dev";
```
```fsh
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
function main(): void throws IoError {
  const path = join(tmpdir(), "fish-porting-demo.txt");
  writeFileSync(path, "one\ntwo\n");
  const lines = readFileSync(path, "utf8").split("\n").filter((l) => l !== "");
  const mode = process.env.FISH_PORTING_MODE ?? "dev";
  console.log(lines.length, mode, process.argv.at(2) ?? "no argument"); // expect: 2 dev no argument
}
```
File calls throw `IoError` (with Node's `code`, such as `ENOENT`), which the signature declares.
`process.env.X` is an Option, so `||` becomes `??`. `filter(Boolean)` is truthiness: write the
test. `process.argv[0]` and `[1]` are both the program's path. A `console` method other than `log`,
`error` and `warn` is reported as `error[E0401]: cannot find name 'console'`.

### 7.11 Enums, `switch`, building a string in a loop
```ts
function name(l: Level): string { switch (l) { case Level.Debug: return "debug"; case Level.Info: return "info"; } }
let out = ""; for (const row of rows) out += render(row);
```
```fsh
enum Level { Debug, Info }
function name(l: Level): string {
  return match (l) {
    case Level.Debug => "debug",
    case Level.Info => "info",
  };
}
function main() {
  let parts: string[] = [];
  for (let i = 0; i < 3; i++) parts.push(`${i}`);
  console.log(Level.Info, name(Level.Info), Level.Debug < Level.Info, parts.join(",")); // expect: 1 info true 0,1,2
}
```
Enums port as written, but a `switch` covering every member does not count as returning
(`error[E0601]: not all code paths return a value`): add a `default`, or use `match`. `Level[1]` is
`error[E0801]: indexed access expressions are not supported yet`. `out += piece` compiles, but each
append copies the string: 200,000 took 3 seconds in a release build; `push` then `join` took none.

### 7.12 Module forms
| TypeScript | fishc 0.1.3 |
| --- | --- |
| `import { a, b as c } from "./x"`, `import d from "./x"`, `import type`, `export default`, `export { a as b }`, `export * from "./x"` | accepted; write `./x` or `./x.fsh` |
| `import * as fs from "node:fs"`, `import fs from "node:fs"` | accepted for std modules |
| `import * as x from "./x"` | `error[E0801]: namespace imports aren't supported yet; import the names you use, as in 'import { a, b } from "./x"'` |
| `import x = require("./x")`, `const x = require("./x")` | `error[E0801]: 'import util = ...' isn't supported yet; import what you use with 'import { a, b } from "./file"'`, `error[E0401]: unknown function 'require'` |
| `export = f`, `await import("./x")`, `namespace N { }` | `error[E0801]`: `exports are not supported yet`, `dynamic imports are not supported yet`, `namespaces are not supported yet` |
| `import { h } from "@/lib/x"` | `error[E0902]: can't find the package '@/lib'`: write the relative path |

### 7.13 Cleanup, task lists, SQLite, tracing, API documents

| TypeScript | Fish |
| --- | --- |
| a class with `[Symbol.dispose]()`, and `using r = open()` | the same text; the method also runs for a `const`, and a `using` binding can't be moved or stored (`ownership.md`, section 18) |
| `async [Symbol.asyncDispose]()`, `await using` | the same, in an async function (`errors-async.md`, section 18) |
| `DisposableStack`, `r[Symbol.dispose]()` by hand, a disposer on an object literal or an interface | `G12`: make it a class with the method and end the value by ending its scope |
| `Promise.all` over tasks that should stop when one fails; `p-all`, `p-map` | `await taskGroup(async (group) => { ... })` (`errors-async.md`, section 17); a concurrency limit still needs a `Semaphore` |
| `node:sqlite`, `better-sqlite3`, `sqlite3` | `import { Database } from "sqlite"`, every call awaited (`std.md`, section 11) |
| the OpenTelemetry API and SDK packages | `fish:trace` (`std.md`, section 12) |
| `swagger-jsdoc`, `@fastify/swagger`, `@hono/zod-openapi`, `tsoa` | `Router` handlers that say their types, then `fishc openapi` (`toolchain.md`, section 18) |

The survey sorts each of those packages under `in std`.

## 8. Choosing a parameter's mode

Read the body one parameter at a time and take the first row that matches.

| The parameter is | Write | At the call |
| --- | --- | --- |
| a number, boolean, string or enum | the plain type | the caller keeps its value |
| an object, array, `Map`, `Set` or instance that the body stores (pushes, assigns to a field) or returns | the plain type `T` | the argument moves; a caller that still needs it passes `x.clone()` |
| the same, and the body assigns a field, calls a changing method or passes it to a `Mut` parameter | `Mut<T>` | the caller's variable is a `let` |
| the same, only read | `Ref<T>` | nothing changes |

```fsh
type Order = { id: i64; items: string[] };
function describe(o: Ref<Order>): string { return `#${o.id} (${o.items.length})`; }
function addItem(o: Mut<Order>, item: string) { o.items.push(item); }
function archive(done: Mut<Order[]>, o: Order) { done.push(o); }
function itemsOf(o: Ref<Order>): string[] { return o.items.clone(); }
```
A read-only object parameter left plain compiles, then breaks the caller's next use of the
argument: `error[E0201]: 'o' was moved, so it can't be used here`, with the note `passing it to
'total' hands it over, as if 'total' kept it; pass 'o.clone()' to keep a copy`. Returning part of
a borrowed parameter needs a copy unless it is a number or a string (`error[E0202]: 'o.items' can't
be moved out of 'o', which only borrows it; use 'o.items.clone()'`). More: `ownership.md`.

## 9. What cannot be ported yet

Recognise it before renaming anything. `rejected` hits (`eval`, prototype edits, `delete` of a
declared field, `arguments`, `Symbol`, declaration merging, run-time regexes) are redesigns. Under
`waiting on Fish`, the rules that block most often are `nodeBuiltins` (section 6),
`untypedPackages`, `moduleForms`, `pathAliases`, `bunModules`, `forIn`, `decorators`, `namespaces`,
`jsx`, `console`, `json` and `process`. In the compiler, `error[E0801]` is a form waiting on Fish,
and `error[E0802]` one Fish leaves out on purpose, whose message says what to write. Per file:

1. **Rewrite it away** where a plain equivalent exists: `for...in` to `Object.keys`, a namespace
   import to named imports, a path alias to a relative path, a `function` expression to an arrow.
2. **Keep that part in TypeScript**: port the files with no waiting hits and leave the rest running
   where it runs today, reached over HTTP (`fetch`) or as a child process.
3. **Call the package through npm interop** (`interop.md`) when a `pure` dependency is the blocker.
4. **Restructure** a pattern: decorator-driven routes become explicit `Router` calls.

## 10. Proving the port

Run the original and the port on the same inputs and compare stdout and the exit code. This run:
`bun src.orig/main.ts words.json > orig.out`, then `fishc build src/main.fsh -o tally`,
`./tally words.json > port.out` and `diff orig.out port.out`, which printed nothing. Cover an
ordinary input, an empty one, a missing argument and a malformed file. Expect these differences:

- With no argument the original threw a `TypeError` and exited 1; the port panicked at
  `process.argv[2]` with `index out of bounds: the len is 2 but the index is 2` and exited 101.
- Numbers print differently once a `number` is an `i64` and `/` truncates (7.3).
- Output order can change, because a promise starts when awaited, not when made (7.8).
- For a server, drive the ported `Router` with `app.handle(new Request(...))` and compare statuses
  and bodies with the original's responses (7.9).
