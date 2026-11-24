# Working on fishc

Procedures for changing the compiler: bootstrapping, building, the two test suites, the
end-to-end checklist for a new language form, std, error codes, generated source, measuring,
debugging and releasing. Commands are run from the root of the compiler's checkout unless a
step says otherwise, and each was read out of the script it runs. How the compiler is put
together is in `architecture.md`. Using `fishc` as a tool (flags, `fish.toml`, `fishc test` for
your own package) is in `toolchain.md`. This slice follows the compiler's main line of
development after release 0.1.1, not the release.

## 1. What you need

- clang 15 or newer on `PATH`. `fishc` writes LLVM IR as text and hands it to clang.
- git, curl, tar and a POSIX shell for the bootstrap.
- macOS or Linux, x86-64 or ARM64. `stage0.toml` pins a release tarball and a digest for ARM64
  macOS only so far; another machine builds stage 0 from source and records its own digest
  (section 2).
- Time and memory. Building `fishc` takes about 25 minutes on a fast machine, and the compiler
  holds gigabytes while it compiles itself. Plan work so you build as rarely as you can
  (section 6).

**Bun and Node are references, not tools.** Nothing new in the build, the tests or the
bootstrap may run them. The compiler's own imports such as `node:fs`, and its `Bun.spawn`
calls, are Fish's std modules under those names, not the JavaScript runtimes. What still runs
a real `bun` process today, and should shrink rather than grow:

- building stage 0 from source down to its first commit (`--from-source`), once
- `src/bundle.fsh`, when a program imports an npm package
- a few unit tests that ask Bun for JavaScript's answer as a reference (`regex`, `os`, `error`,
  `inspect`, `native`, `lsp`) and `scripts/casemap.fsh`

The editor grammars under `editors/` are JavaScript because their hosts require it. They are
not part of the compiler's build or of either test suite.

## 2. Stage 0 and the bootstrap

`fishc` is built by stage 0, an earlier `fishc`. `stage0.toml` pins it:

- `commit`: the commit stage 0 is built from
- `release` and `releases`: the release that is stage 0, and where its tarballs are downloaded
- `[tarballs]`: per target (`arm64-darwin`), the sha256 of the release tarball
- `[digests]`: per target, the sha256 of the stage 0 binary with the Mach-O UUID zeroed and the
  code signature left out, since every link makes those anew
- `chain`: the commits stage 0 can be rebuilt from instead of downloaded. The first was built
  from TypeScript by Bun, each later one by the one before.

Stage 0 lives in the cache, `$FISH_CACHE_DIR`, else `$XDG_CACHE_HOME/fish`, else
`~/.cache/fish`, under `stage0/<commit>/` (a release unpacks as `bin/fishc` beside the
`share/fishc` it reads). Its digest is checked every time it is used.

With no `fishc` at all:

```sh
sh scripts/bootstrap.sh
```

When `stage0.toml` pins a release with a tarball for this machine, the script downloads it with
curl, checks its sha256, unpacks it into the cache and runs `scripts/build.fsh` with it. No Bun
is involved. Otherwise, or with `--from-source`, it unpacks the first commit of the chain and
runs that commit's compiler under Bun, which builds stage 0 from source (about an hour, once).
Arguments are passed on to `scripts/build.fsh`. On a target `stage0.toml` has no digest for,
the built stage 0 can't be checked, so pass `--record` to write this machine's digest.

With a `fishc` already (an installed release, or an earlier `build/fishc`):

```sh
fishc run scripts/build.fsh
```

`scripts/build.fsh` takes:

| Flag | Effect |
| --- | --- |
| `-o <path>` | where to write the compiler; default `build/fishc` |
| `--stage0 <fishc>` | adopt a binary into the cache as stage 0, once its digest matches |
| `--stage0 <tarball>` | adopt a release tarball, once its sha256 matches |
| `--from-source` | build stage 0 from its chain instead of downloading |
| `--record` | rebuild stage 0 and write this machine's digest into `stage0.toml` |
| `--source <tree>` | build the `src` of another tree, as a release builds its tagged commit |
| `--leaks` | build `fishc` with `--leaks`, for `scripts/memsites.fsh` |

A script after `--` is given its arguments, so flags follow a `--`:
`fishc run scripts/build.fsh -- -o /tmp/fishc-test`.

Two things that surprise people:

- A `fishc` holds the path of the source tree it was built from, and reads the runtime's C
  sources and `vendor/` from there (a release reads `../share/fishc` beside the binary).
  Stage 0's tree is therefore unpacked at one fixed path on every machine,
  `/tmp/fish-stage0/<commit>`, and `scripts/build.fsh` unpacks it again when a reboot cleared
  it. A `build/fishc` can no longer find them if the checkout it was built in moves.
- The cached stage 0 failing its digest check stops the build with
  `the cached stage 0 has changed`. Adopt a good one with `--stage0`.

## 3. Building and trying a change

The build is one command, `fishc run scripts/build.fsh -- [-o <path>]`. Underneath it runs stage 0
as `fishc build main.fsh --release -o <out>` inside `src/`, and prints a line a minute while it
works. There is no incremental build of the compiler itself: every build is the full 25 minutes.

Cheaper checks first, in this order:

```sh
fishc check src/main.fsh                      # type and borrow check the whole compiler, no codegen
fishc run scripts/walkgen.fsh                 # only after an AST change (section 10)
fishc run scripts/build.fsh                   # about 25 minutes
build/fishc build hello.fsh -o hello && ./hello
```

`fishc check src/main.fsh` uses whatever `fishc` is on `PATH`. If that is the pinned stage 0
release, a clean check means stage 0 accepts your source, which is the first thing the build
needs. To see what a change did to generated code, compare `build/fishc build x.fsh --emit-llvm`
before and after.

## 4. The golden programs

`tests/programs/` holds the end-to-end tests: about 250 files and 4,300 programs. The runner is
`tests/run.fsh`, itself a Fish program:

```sh
build/fishc run tests/run.fsh -- --fishc "$PWD/build/fishc"            # everything, about 2 minutes
build/fishc run tests/run.fsh -- --fishc "$PWD/build/fishc" dispose    # tests whose name contains "dispose"
build/fishc run tests/run.fsh -- --fishc "$PWD/build/fishc" --list     # names only
```

The compiler under test is `--fishc`, else `FISHC`, else `fishc` on `PATH`. Programs are built
and run in parallel, as many as the machine has cores, or `FISH_TEST_JOBS`, or `--jobs <n>`. A
pattern keeps the tests whose name contains it. The run exits 1 if any test failed.

A program states its result in comments:

| Directive | Meaning |
| --- | --- |
| `// expect: <line>` | the next line of stdout, in order |
| `// error: <text>` | compilation must fail with a message containing the text, and with exactly one error |
| `// errors: <n>` | compilation must fail with n errors, its `error:` texts in order |
| `// panic: <text>` | exit code 101 and stderr containing the text |
| `// fails: <text>` | exit code 1 (an error escaping `main`) and stderr containing the text |
| `// stderr: <line>` | a line of stderr; a program's `stderr:` lines must appear together, in order |
| `// warning: <text>` | the build must warn with this text, and give no other warning |
| `// mode: release` | build with `--release` |
| `// mode: abort` | build with `--panic=abort` |
| `// mode: parse` | only parse (`fishc parse`); passing means it parsed |
| `// link: <name>` | link the C library, as `--link <name>` does |
| `// stdin: "<text>"` | what the program reads on stdin, a JSON string |

A file holds one program per case. A case starts at a `// case: <name>` line (letters, digits,
`_` and `-`) and runs to the next. Each case is built on its own as the file `<name>.fsh`
holding just its lines, so line numbers in its messages count from the case's first line. Its
test is named `<file> > <name>`. Text before the first case is the file's comment.

A case that must print:

```fsh
function total(xs: Ref<i64[]>): i64 {
  let sum = 0;
  for (const x of xs) sum += x;
  return sum;
}
function main() {
  const xs = [1, 2, 3];
  console.log(total(xs));
  console.log(xs.length);
}
// expect: 6
// expect: 3
```

A case that must be refused. Pin the position, the code and enough of the message that a
follow-on error can't pass for it:

```fsh
function keep(xs: i64[]) {
  console.log(xs.length);
}
function main() {
  const xs = [1, 2, 3];
  keep(xs);
  console.log(xs.length);
}
// error: 7:15: error[E0201]: 'xs.length' can't be used here because 'xs' was moved
```

**Adding a test.** Find the file for the feature (`map.fsh` for Map behaviour, `borrow.fsh`,
`dispose.fsh`) and append a `// case: <name>` with the program. Start a new file only for a new
feature. A program that spans several files is a directory holding `main.fsh`, whose comments
state the result, and the files it imports (`tests/programs/macro_imported/`). Write one case
per behaviour and one per refusal: the accepted form, each error with its code, and the edge
that made you write the code.

## 5. The unit tests

`tests/unit/` is a Fish package of its own (`fish.toml` names it `unit`). Its files hold
`test("name", () => { ... })` blocks, grouped by area (`parse.fsh`, `unsupported.fsh`,
`codes.fsh`, `modules.fsh`, `survey.fsh`, `fmt.fsh`, `lsp.fsh`, `incremental.fsh` and about
sixty more), and `support.fsh` holds what they share. They import the compiler's modules
directly (`../../src/parser.fsh`) and call them in process.

```sh
cd tests/unit
FISHC="$PWD/../../build/fishc" ../../build/fishc test --release
FISHC="$PWD/../../build/fishc" ../../build/fishc test --release "interface" --timeout 600000 --jobs 4
```

- `FISHC` names the compiler the CLI tests spawn. Without it they run `fishc` from `PATH`,
  which is usually the release and not your change.
- The filter keeps tests whose name, the string given to `test(...)`, contains it. It is not a
  file name.
- The whole package is built into one program before any test runs, filter or not. Most files
  import the whole compiler, so the build dominates: the full run takes about 31 minutes, and a
  filtered run saves only the running.
- Each test runs in a process of its own. `--timeout <ms>` sets the limit for a test and
  `--jobs <n>` how many run at once.

What some of these tests pin, so you know why one fails:

- `parse.fsh`: tables of source against the parsed tree printed fully parenthesised
- `unsupported.fsh`: each checker rejection with its exact span
- `codes.fsh`: every `new CompileError` names a code in the table, every code is used and is
  numbered in its area, and each explanation's example fails with its code while its fixed
  program compiles
- `walk.fsh`, `ast.fsh`: the generated files match what their generators give now
- `nodes.fsh`: no table keyed by a node, a type or an arena record; no lowering pass changing a
  node in place
- `modules.fsh`, `selfhost.fsh`: the module convention, declared `throws`, no module state
- `format_corpus.fsh`: the compiler's own files format, parse back to the same tree and format
  the same again

## 6. Which suite for which change

| Change | Run before the build | Run after the build |
| --- | --- | --- |
| lexer or parser | `fishc check src/main.fsh` | golden pattern for the form; unit `parse` tests |
| AST type | regenerate (section 10), then check | golden suite; unit `walk`, `ast`, `nodes` |
| checker, moves, codegen | `fishc check src/main.fsh` | the feature's golden file, then the whole golden suite |
| error message or code | check | golden suite (messages are matched as text); unit `codes` |
| std source | check | the module's golden file; unit `std`, `survey` if tables changed |
| formatter, lint, survey, LSP, CLI | check | the matching unit tests |
| anything that changes emitted IR for the compiler itself | check | golden suite, then the fixpoint (section 11) |

Costs to plan around: check, minutes; build, about 25 minutes; golden suite, about 2 minutes;
unit tests, about 31 minutes; fixpoint, one to two hours. The golden suite is the default gate.
Run the unit suite once at the end of a piece of work, not after every edit.

## 7. Adding a language form, end to end

The checklist, front to back. Skip a step only when you have checked it does not apply.

1. **Grammar and AST.** Add the kind or the field to the type in `src/parser.fsh` and parse it
   in the grammar file for its area (`parser.fsh` statements, `expressions.fsh`, `types.fsh`,
   `patterns.fsh`, `declarations.fsh`). A new keyword is contextual: decide from the next token
   and `newlineBefore` whether it is the keyword, and keep every TypeScript reading that used
   the word as a name. Give every node `id: nextId(c.ids)`, `start` and `end`.
2. **Regenerate** `walk.fsh`, `rebuild.fsh`, `unquote.fsh` and `ast.fsh` (section 10).
3. **Unsupported until it means something.** If the form parses before the checker handles it,
   name it in `src/unsupported.fsh` so it is refused with `E0801`. `EXPRESSION_FORMS` is typed
   as a record over the expression kinds the checker does not handle, so a new `Expr` kind must
   be handled or listed.
4. **Checker.** Statements and declarations in `check.fsh`, expressions in `values.fsh`, types
   in `resolve.fsh` and `typing.fsh`, classes in `classes.fsh` and `registry.fsh`. Record what
   codegen will need in the instance's tables or in `Tables` (declare a new table in
   `compilation.fsh` with a comment and add it to `newTables`). Lower through `Rewrites`, never
   by editing a node.
5. **Moves** (`moves.fsh`): what the form moves, lends and keeps. Add it to the walk so its
   operands are visited in evaluation order.
6. **Warnings** (`warnings.fsh`): whether unused-binding and unreachable-code rules see it right.
7. **Comptime** (`comptime.fsh`): evaluate it in the interpreter, or refuse it there with a
   message that says why.
8. **Codegen** (`codegen.fsh`, `layout.fsh`): lower it. Add a case to `lowerStatement` or to the
   expression switch. If it needs the runtime, declare the function in `RUNTIME`
   (`runtime.fsh`) and define it in `NATIVE` (`native.fsh`).
9. **Error codes** (section 9) for each new refusal.
10. **Formatter** (`printer.fsh`): print the form. `fishc fmt` must round-trip it.
11. **Migration lint and survey** (`migrate.fsh`, `survey.fsh`): if a rule reported the form as
    unsupported or as a rewrite, change or remove the rule, and its unit test.
12. **Editor grammars**: `editors/tree-sitter-fsh/grammar.js` with a corpus entry in
    `test/corpus/fish.txt` and highlights in `queries/highlights.scm`, then regenerate the
    parser (`npm run generate` there, which rewrites `src/parser.c`); and a line in
    `editors/vscode/test/grammar/` for the TextMate grammar.
13. **Tests**: golden cases for every accepted shape and every refusal, a `parse.fsh` table for
    the grammar, and unit tests for any tool you touched.

**Worked example: `using` and `await using` declarations.** The commit that added them touched,
in pipeline order:

- `parser.fsh`: `"using" | "await using"` joined the `let` statement's `keyword` union.
  `atDeclaration` treats `using` as a declaration only before a name or `{` on the same line,
  so `using(x)`, `using = 1` and `using.y` keep their TypeScript meaning, and `declaration`
  consumes the extra `await`.
- `ast.fsh` and `unquote.fsh`: regenerated, since the keyword union widened. `walk.fsh` and
  `rebuild.fsh` did not change, because no node gained a child.
- `check.fsh`, `values.fsh`, `classes.fsh`, `typing.fsh`, `registry.fsh`, `keys.fsh`: a class's
  `[Symbol.dispose]` method is its disposer, a `Local` gained `using`, and a new `disposers`
  table in `compilation.fsh` maps each class to the instance a drop runs.
- `moves.fsh`: two new refusals, moving a `using` binding (`E0215`) and moving a field out of a
  value that has a disposer (`E0214`).
- `warnings.fsh`: a `using` binding is not reported as unused, since holding the value to the
  end of the scope is its use.
- `comptime.fsh`: one line refusing to make a disposable class while compiling, with the reason.
- `codegen.fsh`: the drop of an instance runs its disposers, the class's own first, then each
  base's.
- `codes.fsh`: the new codes, each with a title, the common ones with an explanation.
- `migrate.fsh` and `survey.fsh`: lint rule `R6`'s message now allows `Symbol.dispose` as a
  method key, and a new guided rule `G12` covers `DisposableStack` and other uses.
- `editors/tree-sitter-fsh/`: a `using_declaration` rule, corpus entries, highlights, and the
  regenerated parser; a few lines in the VS Code grammar test.
- Tests: a new golden file `tests/programs/dispose.fsh` with a case per behaviour and refusal,
  a `USING` table in `tests/unit/parse.fsh` (including `using` as a plain name), and unit tests
  for the lint and the survey rule.

`printer.fsh` needed no change: it prints a declaration's `keyword` as written. Check that for
your form; do not assume it.

## 8. Adding a std function or module

Std is Fish source inside `src/std.fsh` (`architecture.md`, section 14).

**A global** (available without an import) goes in the section it belongs to. The prelude is in
every program; any other section is added by `stdFor` only when the program names one of the
section's listed names (`HTTP_NAMES`, `STREAM_NAMES` and the like), so a new global outside the
prelude must be added to its section's list or no program will ever see it. A helper only std
calls takes one of the prefixes `stdFor` renames to a name no program can write (`__array`,
`__iter`, `__promise`, `__timer`, `__timeout`, `__router`, `__url`, `__date`, `__number`):
`__arrayFilled` becomes `array filled`.

**A module** is an entry in `STD_MODULES`, keyed by its bare name (`sqlite`, `fs/promises`,
`fish:tar`), holding Fish source with ordinary `export`s. `stdModule` makes `node:<name>` and
`<name>` the same module. Model a module on Node's shape when Node has one.

**The C side.** Std reaches the runtime with `declare function fsh_rt_<area>_<name>(...)` in its
own source and calls inside `unsafe { }`. Define the function in `src/native.fsh`. A part that
needs a system library is its own text (`TLS_NATIVE`, `ZLIB_NATIVE`, `SQLITE_NATIVE`) and is
compiled and linked only when the program's IR calls into it: add a `callsX` test, a unit in
`runtimeUnits` and the `-l` flag in `runtimeLinks`, all in `src/main.fsh`.

**What must follow:**

- a golden file `tests/programs/<module>.fsh`, including each error the module throws
- the survey's tables: the Node built-in or npm package the module answers moves from planned
  to std in `src/survey.fsh` and `src/deps.fsh`, with their unit tests in
  `tests/unit/survey.fsh`
- anything the checker special-cases (a call the checker rewrites, a method on a built-in type)
  lives in `values.fsh` and `codegen.fsh`, not in std's source

## 9. Adding an error code

1. Pick the next free number in the right area of `src/codes.fsh` (`E02xx` ownership, `E05xx`
   calls, and so on; the ranges are listed at the top of the file). A code names a kind of
   error, not one place that raises it, and keeps its meaning once given. Reuse an existing code
   when the new refusal is the same kind of mistake.
2. Add `E0xxx: { title: "..." }`. For an error people will meet often, add `long`: `text` (what
   it means, what TypeScript would have done, how to fix it), `example` (a whole program that
   fails with exactly this code) and `fixed` (the same program compiling).
3. Raise it: `throw new CompileError("E0xxx", message, start, end, note?)`. Write the code as a
   string literal (or a `?:` between literals), because the unit test reads the compiler's
   source to match call sites against the table.
4. Message style: lowercase, source names in single quotes, no trailing period, and say what
   to do where you can (`...; use 'x.clone()'`).
5. Tests: a golden case with `// error: error[E0xxx]: <message start>`, and `tests/unit/codes.fsh`
   then checks the table for you. `fishc explain E0xxx` prints the entry.

## 10. Regenerating generated source

| File | Generator | Run |
| --- | --- | --- |
| `src/walk.fsh`, `src/rebuild.fsh` | `scripts/gen/walkgen.fsh` | `fishc run scripts/walkgen.fsh` |
| `src/unquote.fsh` | `scripts/gen/unquotegen.fsh` | `fishc run scripts/unquotegen.fsh` |
| `src/ast.fsh` | `src/astgen.fsh` | `fishc run src/astgen.fsh` |
| `src/casemap.fsh` | `scripts/casemap.fsh` | `fishc run scripts/casemap.fsh` |

The first three read the AST types out of `src/parser.fsh`, so run them after any change to
those types and commit the results with the change. Never edit a generated file: change its
generator. `scripts/casemap.fsh` takes JavaScript's case mapping from a Bun child process, as a
reference, and only needs running when Unicode's tables change. The generators run with the
`fishc` on `PATH`, so they work before the compiler is rebuilt.

## 11. The bootstrap fixpoint

```sh
fishc run scripts/fixpoint.fsh -- --from "$PWD/build/fishc" --out /tmp/fixpoint
```

The compiler given with `--from` is generation 1. It prints the IR of `src`, builds generation 2,
which prints the IR and builds generation 3, which prints the IR. Generations 2 and 3 must emit
identical IR; the script exits 1 when they differ and reports where (`cmp`'s byte offset). It
also says whether generations 1 and 2 agree. Each generation is a full build, so the run takes
one to two hours. `--out` keeps the binaries and IR files.

Run it when a change could alter the code `fishc` generates for itself or make output depend on
something other than the source: codegen, layout, symbol or struct naming, anything that
iterates a table into the IR, the incremental path, and before promoting a stage 0. A feature
that only adds a new form the compiler's own source does not use does not need it. When the
generations differ, diff the two `.ll` files around the reported offset to find the function,
then look for a name or an order that came from a counter or from insertion order.

## 12. Measuring time and memory

```sh
build/fishc check src/main.fsh --timings              # time per stage, on stderr
FISH_MEM=1 build/fishc check src/main.fsh             # resident and peak memory as each stage ends
fishc run scripts/build.fsh -- --leaks -o build/fishc-leaks
fishc run scripts/memsites.fsh -- check check src/main.fsh
```

- `--timings` works on `build`, `check`, `run` and `watch`. It prints `parse`, `macros`,
  `check`, `moves`, `comptime`, `codegen`, `compile`, `runtime`, `link` and `total`, with notes
  such as `(cache miss)` and how many objects were cached.
- `FISH_MEM=1` adds a table of resident and peak memory per stage, the counts of instances,
  bodies and classes, and how many entries each per-instance table holds.
- `scripts/memsites.fsh -- <parse|check|codegen> [--fishc <path>] [--top <n>] <fishc arguments>`
  runs a `--leaks` build of the compiler with `FISH_MEM_STOP` naming the stage, so it ends
  there, and prints what is still live by function and by allocation site, largest first. The
  first word is the stage, the rest is the `fishc` command line, which is why `check` appears
  twice above. It reads `build/fishc-leaks` unless `--fishc` names another. Bytes are what was
  asked for; a `--leaks` build adds a header per block, so the process is resident at more.
- `scripts/rebuild.fsh -- <mirror src> <out dir> <fishc command>...` times cold and warm
  rebuilds of the compiler after one-file edits.

**Measure like for like.** A number means nothing without its baseline taken the same way: the
same binary kind (both `--release`), the same command, the same machine state. Run the baseline
again yourself instead of quoting an old figure, and take three runs of each. One binary's
peak memory varies between runs by roughly the size of one copy of the IR text (hundreds of
megabytes when compiling the compiler), so a saving smaller than that is not shown by one run.

## 13. A crash only on the compiler's own source

The compiler is the largest Fish program there is, so some bugs show only when `build/fishc`
compiles `src/`, or only in the second generation. The golden suite passing proves little
here. What works:

1. **Print before you guess.** Find out which instance and which node the failure is in. An
   internal error names the kind it had no lowering for; add a temporary print of the
   instance's `symbol`, the node's `kind`, `id` and span at the failing point, rebuild once,
   and read it. A theory formed without that costs a 25-minute build to disprove.
2. **Reduce it.** With the symbol and the span, cut the function out of `src/` into a small
   program that fails the same way, and work on that with the golden runner's speed.
3. **Keep the old path behind a switch.** When you change how something is lowered or read,
   keep the previous code reachable (an environment variable, as `FISH_WATCH_VERIFY` does for
   incremental builds) until the new path is proven, so one binary can run both and you can
   compare the IR of the same function. Remove the switch once the new path has passed the
   fixpoint.
4. **Never delete entries from a `Rewrites` table to make an error go away.** A replacement is
   keyed by the id of the node it replaced, and every per-node table reads through it. Removing
   one makes later passes read the unlowered node with tables filled in for the lowered one.
   If a replacement is wrong, fix what made it.
5. **Grep the mutable accessors too.** When you change how bodies or instances are read
   (`bodyOf`, `instanceOf`), also search for `bodyMut`, `instanceMut`, `swapBody` and
   `swapInstance`. A write through one of them is a read path as well, and it is easy to
   convert every reader and leave a writer on the old representation.

`FISH_WATCH_IR=<dir>` writes each watch build's IR for later comparison, and codegen can be
asked to go past a function it fails on and list every failure (`Session.failed`), which the
compiler's own tests use.

## 14. Stage 0 hazards

`build/fishc` is `src/` compiled by stage 0. So two different compilers matter for every line
you write in `src/`: the one that will run your code's logic (the new `fishc`) and the one that
compiles your code (stage 0, the last promoted release).

- **Stage 0 must accept your source.** A language feature added after the pinned release cannot
  be used in `src/`, `scripts/` or `tests/unit/` until a release containing it is promoted.
- **A miscompile fix does not reach the build that contains it.** If stage 0 miscompiles some
  pattern and you fix that in codegen, the fix is in the new compiler's logic, but the new
  compiler was itself compiled by the unfixed stage 0. If `src/` uses the pattern, `build/fishc`
  is still wrong. It stays wrong until a release with the fix is promoted to stage 0. Until
  then, rewrite the compiler's own source to avoid the pattern, and say why in a comment at the
  spot.
- **How to tell.** `build/fishc` fails on a program that a second-generation compiler (built by
  `build/fishc` from the same source, as the fixpoint's generation 2 is) handles correctly.
  When the two disagree, suspect stage 0 before your change.
- Changing `stage0.toml` by hand is never the fix. It is written by `scripts/promote.fsh` and by
  `scripts/build.fsh -- --record`.

## 15. Branches and releases

**Where work lands.** Work lands on the current release branch, `release/v<next version>`, not
on `main`. Find it by listing `origin/release/*` and taking the newest version. `main` receives
one pull request per release, from the release branch. After that is merged, the next release
branch is cut from the latest `main`. Treat the release branch like `main`: do not push to it
or merge into it without the maintainer's say.

**Cutting a release.** Needs a `build/fishc` and a clean working tree.

```sh
build/fishc run scripts/release.fsh -- 0.1.2          # bump, changelog, commit, tag; pushes nothing
build/fishc run scripts/release.fsh -- --pack 0.1.2   # tarball of the tagged release under dist/
build/fishc run scripts/release.fsh -- --nightly      # tarball of HEAD named for today, no commit or tag
```

The first form sets the version in `fish.toml`, writes a `CHANGELOG.md` section from the
conventional commits since the last tag (`feat`, `fix` and `perf`; refactors, tests, chores and
docs are left out), makes a release commit and an annotated `v<version>` tag. Commit subjects
are therefore part of the release: write `feat: what a user can now do`. Pushing the tag runs
the release workflow, which packs and publishes; `--pack` does the packing on this machine. The
tarball's `fishc` is built from the commit's own tree at `/tmp/fish-stage0/<commit>`, so any
machine building that commit there gets the same binary.

**Promoting stage 0.** After a release is published:

```sh
build/fishc run scripts/promote.fsh -- 0.1.2 [--tarball <path>] [--no-fixpoint]
```

It builds the tagged commit at its fixed path with the stage 0 pinned now, requires that
compiler to reach the bootstrap fixpoint, requires its digest to equal the `fishc` inside the
release's tarball (downloaded, or given with `--tarball`), then rewrites `stage0.toml` with the
release, the tarball's sha256, this machine's digest and the commit appended to `chain`. Other
targets' digests are dropped and must be recorded on their own machines with
`fishc run scripts/build.fsh -- --record`. Commit `stage0.toml` only once the release is
published, since a checkout with nothing cached downloads it. `--no-fixpoint` is for trying the
script, not for a real promotion.

## 16. What review enforces

- The smallest change that does the job. No refactoring of unrelated code and no capability
  nobody asked for.
- One stage per file, and code goes in the file whose header comment covers it.
- Branch on `kind`; no visitors. Modules are classes: owned when self-contained, a view over a
  host with state in a data class when they call back (`tests/unit/modules.fsh`).
- No module state, no table keyed by an object, no arena record holding another, no node edited
  in place by lowering.
- Every user mistake is a `CompileError` with a code and an exact span, lowercase, saying what
  to do. Fallible functions declare `throws` or `@throws`.
- Comments say why, or state what a declaration is. No commented-out code, no banners, no
  narration. No unused imports or variables.
- No em dashes, en dashes or ellipsis characters in code, comments, messages or commits.
- Commit messages describe what the change does (`feat:`, `fix:`, `perf:`, `refactor:`,
  `test:`, `docs:`, `build:`, `chore:`), and name no plan, phase or ticket.
- Generated files are regenerated, never edited.
- Compiler behaviour is tested end to end with golden cases; logic in tools gets unit tests. A
  claim that something passes names the command that showed it.
- No new dependency. The compiler uses std modules and finds external commands (clang, git,
  curl, cargo) on `PATH`, naming the command in the error when it is missing.
