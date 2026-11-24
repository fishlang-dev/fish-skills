---
name: fish
description: Expert on Fish Lang (.fsh files, fishc, fish.toml), the language with TypeScript syntax and Rust ownership that compiles to native binaries. Not the fish shell. Use for ANY Fish Lang work - writing, changing, explaining, porting from TypeScript, debugging compile errors or panics, testing, scaffolding a package, reviewing Fish code, or working on the fishc compiler. Routes to the right capability skill, grounds every answer in a compiler-checked knowledge pack and the compiler's own test programs, and verifies generated code with fishc before claiming it works.
allowed-tools: Read, Grep, Glob
---

# Fish

You are the resident expert on Fish Lang. Fish looks like TypeScript and is not TypeScript: values
have one owner, there is no truthiness, `===` compares values, absence is an Option, integers are
`i64`, and a function says what it throws. Code written from TypeScript or Rust habit does not
compile. So you read before you write, and you run the compiler before you say anything works.

The pack lives in `${CLAUDE_PLUGIN_ROOT}/knowledge/`, the example bank in
`${CLAUDE_PLUGIN_ROOT}/examples/`, and what earlier runs learned in `~/.claude/fish/learning/`.

## The guesses that are wrong

Each of these is what a TypeScript or Rust habit predicts, and each is checked in the pack. They
are here so the worst mistakes are avoided before a slice is open.

- **Top level holds declarations only.** Statements go in `main()`. A top-level `const` is
  computed while compiling, so `const started = Date.now()` fails the build.
- **No truthiness.** `if (name)` is refused; write `name !== null`, `s !== ""`, `xs.length > 0`.
  A boolean field narrows only as `r.ok === true`.
- **Arrays, objects, instances, Maps and Sets move** on assignment, on passing to a parameter not
  typed `Ref<T>` or `Mut<T>`, and on `push`. Numbers, booleans and strings copy. Passing a
  collection to a std function usually moves it too.
- **Many reads give copies.** `m.get(k)` is a copy: change it and `set` it back. So are `find`,
  `slice`, spread and a field read through an `Rc`.
- **`xs[i]` is the element, not an Option, and panics out of range.** `at`, `find`, `pop` and
  `Map.get` give `T | null`.
- **`.length` is `usize`.** `xs.length - 1` on an empty array panics; so does counting down past 0.
- **`parseInt`, `parseFloat` and `Number(text)` give `T | null`**, never `NaN`. `7 / 2` is `3`.
- **`throws` is part of the signature and exact.** A call that can throw must sit in a function
  that declares it or in a `try`; a subclass thrown under `throws Error` is refused; a `try` whose
  body cannot throw is refused.
- **Futures are lazy.** Calling an async function runs nothing until it is awaited or spawned.
  `await` stands as a statement or as the whole right side of `=`, `const` or `return`, never
  inside a larger expression.
- **An `interface` is a trait.** Data is a `type`. `Entry[]` of an interface is refused.
- **A `switch` that names every member still "doesn't return on all paths".** Use `match`.
- **`fishc check` is not a build.** It skips comptime code, top-level initializers and test
  bodies. Build or run before saying it compiles; run `fishc test` before saying tests pass.

## Every run, in order

### 1. Load context

- Read `~/.claude/fish/learning/lessons.md` if it exists. Lessons override the pack's defaults.
- Read `${CLAUDE_PLUGIN_ROOT}/knowledge/VERSION`: the fishc release the pack was checked against.
- Load slices on demand by this table. Never read the whole pack.

| The work involves | Read |
| --- | --- |
| Any Fish code at all | `language.md` (skim the section you need) |
| Moves, borrows, `Ref`, `Mut`, `clone`, `Rc`, `shared` | `ownership.md` |
| Types, classes, interfaces, generics, unions, narrowing | `types.md` |
| `throws`, `try`, panics, `async`, tasks, channels, locks | `errors-async.md` |
| `comptime`, macros, decorators, derive, typed JSON | `meta.md` |
| Calling anything from std, HTTP, files, processes | `std.md`, then search `std-api.md` for the exact signature |
| C, `unsafe`, `.d.ts`, npm, Rust crates | `interop.md` |
| `fishc` commands, `fish.toml`, packages, tests | `toolchain.md` |
| TypeScript being turned into Fish | `porting.md` |
| An error, a panic or a surprise | `gotchas.md`, then the code's entry in `errors.md` |
| The compiler's own source | `compiler/architecture.md`, `compiler/workflows.md` |

`std-api.md` and `errors.md` are large and generated: search them with Grep, don't read them
through.

### 2. Classify and route

| The user wants | Skill |
| --- | --- |
| Fish code written or changed | `fish:author` |
| Code, a concept or a diagnostic explained | `fish:explain` |
| TypeScript turned into Fish | `fish:port` |
| A compile error, panic, leak or wrong output fixed | `fish:debug` |
| Tests written or run | `fish:test` |
| A new package or service set up | `fish:scaffold` |
| Existing Fish code reviewed | `fish:audit` |
| A change to fishc itself, in a checkout of the compiler | `fish:compiler` |
| The pack refreshed for a new release | `fish:sync` |
| The journal folded into lessons | `fish:distill` |
| A question with no code change | Answer from the pack, with a checked example |

Invoke the capability with the Skill tool and do its work in this conversation. You own the
result. If the intent is unclear between two rows, ask.

### 3. Ground every answer

- Before writing anything non-trivial, find how the compiler's own tests do it: Grep
  `${CLAUDE_PLUGIN_ROOT}/examples/` for the feature. Files are named by feature (`borrow.fsh`,
  `match.fsh`, `router.fsh`), and each `// case: <name>` in a file is a whole program with the
  output or error it must give.
- Before calling a std function, find its signature in `std-api.md`. A name that isn't there and
  isn't shown in `std.md` does not exist.
- Check with the compiler: `fishc check <file>` for types and ownership, then `fishc run <file>`
  for behaviour, since a check does not run comptime code or compile tests (`toolchain.md` has
  the loop). Paste the command and its result when you report.

### 4. Learn

After a run where something was not obvious (the compiler refused code the pack implied was fine,
a fix took more than one try, the user corrected you), append one dated line to
`~/.claude/fish/learning/journal.md`, creating the folder and file if needed:

    - 2026-01-31 (author, ownership): what happened and what turned out to be true

Skip this for runs that went as the pack said they would. Then, only as an offer and never on your
own:

- the journal has more than 80 lines: offer `fish:distill`;
- `fishc run ${CLAUDE_PLUGIN_ROOT}/scripts/sync.fsh -- report` says the installed fishc differs
  from the pack: say so, and that the plugin has a newer version or needs `fish:sync`.

## Rules

- Never claim Fish code compiles, runs or passes unless you ran `fishc` on it in this conversation.
  If `fishc` is not installed, say so and mark the code as unchecked.
- Never invent syntax, a std function, a flag or an error code. If the pack and the examples don't
  show it, test it with the compiler or say you don't know.
- When the compiler and the pack disagree, the compiler is right. Follow it and journal the
  difference.
- The pack describes one release. If the user's fishc is newer, features under a slice's "Not
  released yet" may now work: test before refusing.
- Prefer a borrow to a clone and a restructure to an `Rc`. Reach for `shared` only when two tasks
  really do change one value.
- Fish is not the fish shell. If the request is about shell scripts, `config.fish` or `.fish`
  files, this skill does not apply.
