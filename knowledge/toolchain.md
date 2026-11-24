# Toolchain: fishc, packages and tests

How to drive the compiler and lay out a project: every `fishc` command and flag, build modes,
the cache, diagnostics, `fish.toml`, dependencies, import resolution, `fishc test`, the formatter
and the editor support. The language itself is in `language.md`, C, npm and Rust linking in
`interop.md`, the migration lint's rules and `fishc survey` in `porting.md`, each error code in
`errors.md`. Checked against fishc 0.1.1 on macOS ARM64; every session below was run, with long
output trimmed. `$` lines are typed, `exit=` shows the exit code where it matters.

## 1. Installing, and what the machine needs

A release unpacks under `~/.fishc/fishc-<version>-<arch>-<os>/` and `fishc` on `PATH` is a
symlink to its `bin/fishc`. Beside it, `share/fishc/` holds C sources the compiler builds on
demand (the `Math` runtime and a vendored JS engine). The release's README gives the installer,
`curl -fsSL https://raw.githubusercontent.com/fishlang-dev/fish/main/install.sh | sh`, which
links `fishc` into `~/.local/bin`, and says releases exist for macOS on ARM64 so far.

There is no `--version` flag (`fishc: Unknown option '--version'`, exit 2) and no `help`
command: `readlink "$(command -v fishc)"` shows the release in the install path, and `fishc`
alone prints the usage text.

`fishc` emits LLVM IR as text and hands it to **clang, 15 or newer, on `PATH`**. Whatever
produces a binary needs it (`build`, `run`, `watch`, `test`); `check`, `fmt`, `lint`, `parse`,
`explain` and `survey` don't. Without clang a build prints
`Executable not found in $PATH: "clang"` and exits 1.

Other tools are looked for on `PATH` only when a feature needs them: `git` for registry and git
dependencies and `publish`, `curl` to download a registry archive, `gh` for `publish --submit`,
`ld.lld` or `ld64.lld` to link for another OS. npm and Rust interop add their own: `interop.md`.

## 2. The commands

One parser reads the flags of every command, so a flag no command has is refused before
anything runs, and a real flag given to a command that doesn't take it (`check --release`)
prints the usage text. Both exit 2.

| Command | What it does |
| --- | --- |
| `fishc check [<file.fsh>] [--timings] [--no-check-cache]` | Parse, type-check, move- and borrow-check. Writes nothing. Silent when clean. |
| `fishc build [<file.fsh>] [flags]` | Compile to a native executable (flags: sections 4 and 5). |
| `fishc run [<file.fsh>] [--release] [-g] [--leaks] [--timings] [-- <args>...]` | Build, then run with the arguments after `--`. |
| `fishc watch [<file.fsh>] [same flags as run]` | `run`, again each time a file the program was read from changes. |
| `fishc new <name>` / `fishc init [<name>]` | Make a package in a new directory, or in this one. |
| `fishc add <name>[@<range>]` / `fishc update [<name>]` | Add a registry dependency; move `fish.lock` to the newest versions that fit. |
| `fishc publish [--dry-run] [--allow-dirty] [--submit [--fork <url>] [--yes]]` | Pack the package for the registry. |
| `fishc test [<filter>] [--release] [--timeout <ms>] [--jobs <n>]` | Build and run the package's `test()` blocks. The usage text omits the last two flags; they work. |
| `fishc fmt [<path>...] [--check]`, `fishc fmt - [--check]` | Format files, a package, or stdin. |
| `fishc lint [<path>...] [--fix]` | The TypeScript migration lint. |
| `fishc survey <dir> [--compare <old.json>] [--json]`, `fishc survey --rank <dir>...` | Grade a TypeScript project's portability. |
| `fishc explain <code>` | The long explanation of an error or warning code. |
| `fishc parse <file.fsh>` | Parse only: silent and 0, or the syntax error and 1. |
| `fishc lsp` | The language server, over stdio (section 15). |

**Exit codes.** 0: done, warnings included. 1: a compile error, a failed clang, a failing test, a
lint hit, a file `fmt --check` would change. 2: wrong usage, an unknown flag, no `fish.toml`
where one is needed, an invalid package name. `fishc run` gives the program's own code: 101 for a
panic, 128 plus the signal number when a signal ended it.

## 3. check, build, run, watch

Each takes a file, or no file inside a package (section 8). Outside one, with no file, they
exit 2 with `no fish.toml here or in any directory above; give a file to build, or make a
package with 'fishc new <name>' or 'fishc init'`.

```sh
$ fishc check hello.fsh              # nothing printed: it checks
$ fishc build hello.fsh              # writes ./hello, named after the file
$ fishc run hello.fsh -- a --b c     # built in a temporary directory, removed after the run
hello
a
--b
c
```

`fishc check` covers everything before code generation, so a program that checks builds. It
does not check the bodies of `test()` blocks (section 13).

Program arguments start at `process.argv[2]`, as in Node; the two entries before them are both
the binary's path. Arguments that look like flags must come after `--`.

```fsh
function main() {
  console.log(process.argv.length, process.argv.slice(2).length); // expect: 2 0
}
```

`fishc watch` builds, runs and waits. A save of any file the build read (or looked for and
didn't find), or of the package's `fish.toml`, rebuilds and restarts; a compile error is printed
and it keeps waiting. Its own lines start with `[fishc]`:

```sh
$ fishc watch w1.fsh -- one
hello 3
one
[fishc] w1.fsh exited with code 0; waiting for changes
[fishc] restarting: w1.fsh changed
w1.fsh:1:34: error[E0101]: type '"x"' is not assignable to type 'i64'
[fishc] waiting for changes
```

## 4. Build modes and what they change

| | debug (default) | `--release` |
| --- | --- | --- |
| `+ - *` overflow | panics | wraps |
| division by zero | panics | panics |
| a panic prints | location, reason, stack backtrace | location and reason |

```fsh
function main() {
  let n: i64 = 9223372036854775807;
  n = n + (process.argv.length as i64);
  console.log(n);
}
// panic: attempt to add with overflow
```

`fishc run over.fsh` prints `panicked at over.fsh:3:7:`, the reason, then `stack backtrace:` and
`   0: main at over.fsh:3:7`, exit 101. With `--release` the same program prints
`-9223372036854775807` and exits 0.

Flags of `fishc build` (section 2 shows which of them `run` and `watch` take):

- `-o <out>`: where the binary goes. Default: the file's name without `.fsh` in the working
  directory, or `target/debug/<name>` and `target/release/<name>` in a package.
- `-g`: debug info for a debugger (`<out>.dSYM` on macOS). Debug backtraces don't need it.
- `--panic=unwind|abort`: `unwind` is the default. With `abort` a panic prints the same text and
  the process aborts (exit 134 on macOS) instead of unwinding and exiting 101.
- `--emit-llvm`: print the IR to stdout and stop before clang (about 7,000 lines for hello
  world, std included). `-o` is ignored, so redirect it.
- `--timings`: milliseconds per stage on stderr, from `parse` and `check` to `link` and `total`.
- `--leaks`: the program reports at exit what it never freed, by allocation site. The exit code
  is unchanged, and a program that frees everything prints nothing. A binary built without it
  prints the count alone (`fish: leaked 2 allocations`) when run with `FISH_LEAKS=1`.
- `--sanitize address|thread`: instrument the program, std and the C runtime with clang's
  sanitizer, with `-g` and `-O1` implied. One sanitizer per build, and `build` only: `fishc run`
  answers `'--sanitize' instruments a build; build with 'fishc build --sanitize address|thread',
  then run the binary it writes`.

Safe Fish frees what it owns, so the smallest leak to show needs `unsafe`:

```fsh
declare function fsh_rt_alloc(size: i64): MutPtr<u8>;

function build(n: i64) {
  unsafe { fsh_rt_alloc(n); }
}

function main() {
  build(16);
  build(32);
  console.log("done"); // expect: done
}
```

```sh
$ fishc run leak.fsh --leaks
done
fish: leaked 2 allocations (48 bytes)
  2 allocations, 48 bytes, at leak.fsh:4:12 in build
exit=0
```

## 5. Targets, static binaries, C libraries

`--target <triple>` builds for another platform. The triples are Rust's, and these six exist:
`aarch64-apple-darwin`, `x86_64-apple-darwin`, `aarch64-unknown-linux-gnu`,
`x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-musl`, `x86_64-unknown-linux-musl`. Any other
(`wasm32-wasi`) is `unknown target` and that list.

Between the two macOS architectures nothing else is needed (`--target x86_64-apple-darwin` on
an ARM64 Mac gave an x86-64 Mach-O). A target on another OS, or the other Linux libc, needs that
system's headers and libraries in `--sysroot <dir>` (or `FISH_SYSROOT`), and lld. Without them:
`building for x86_64-unknown-linux-musl from macOS needs a musl sysroot, a directory holding the
target's /usr/include and /usr/lib with musl and libgcc`.

`--static` links libc into the binary and exists only for the two musl targets; elsewhere it is
refused (`--static links musl into the binary, so it builds only for a musl target`).
`--dockerfile`, only with `--static`, also writes a `Dockerfile` beside the binary: `FROM
scratch`, a `COPY` of the binary and an `ENTRYPOINT`.

`--lib` (the same as `--lib=static`) or `--lib=shared` builds a library C can call: each
exported function, plus a header. No `main` is needed. The name comes from `-o` with a `lib`
prefix and the extension dropped: `fishc build mathlib.fsh --lib -o libout/libfishmath.a` wrote
that archive and `libout/fishmath.h`, declaring `int32_t add(int32_t a, int32_t b);` for an
exported `add(a: i32, b: i32): i32`. `--leaks`, `--sanitize`, `--timings` and `--static` are
refused with `--lib`. What may be exported: `interop.md`.

`--link <library>` (repeatable) passes `-l<library>` to the link, for `declare function`s.
**Symptom**: `fishc check` passes, then the build prints `clang failed:` and the linker's
`Undefined symbols` report, exit 1. **Why**: a declared C function is only looked for at link
time. **Fix**: name its library, as in `fishc run link.fsh --link z` for zlib's
`zlibCompileFlags(): u64`.

## 6. The build cache

The cache is `$FISH_CACHE_DIR`, else `$XDG_CACHE_HOME/fish`, else `~/.cache/fish`; safe to delete.

- `objects/`: compiled objects, each named by a hash of `clang --version`, the flags and the
  source text. The C runtime, the `Math` runtime and std's code are there, and in a debug build
  one object per source file of the program, so a rebuild compiles only the files whose code
  changed. A release build compiles the program as one module each time.
- `index/`, `registry/`, `git/`: registry index clones, registry packages, git dependencies.
- `checks/`: a record per checked program. In this release it only labels the `check` line of
  `--timings` as `(cache hit)` or `(cache miss)`; the check runs in full either way.
  `--no-check-cache` (or `FISH_NO_CHECK_CACHE`) skips it.

The first build on a machine, after a clang upgrade, or for a new target compiles the runtime
once: hello world took 2.3 s with an empty cache and 0.17 s after (the `runtime` line of
`--timings` went from `2156.4 ms` with `0 cached` to `37.1 ms (11 cached)`).

## 7. Diagnostics

An error is `file:line:col: error[CODE]: message`, the source line, and a caret underline. A
related place follows as a `note:` in the same shape. Everything goes to stderr. The checker
recovers at function boundaries, so one build reports each independent error, in source order,
separated by blank lines, then a count:

```sh
$ fishc check diag.fsh
diag.fsh:7:15: error[E0201]: 'v.length' can't be used here because 'v' was moved
 7 |   console.log(v.length, w.length);
   |               ^^^^^^^^
diag.fsh:6:13: note: 'v' moved here: 'w' owns it now; use 'v.clone()' to keep a copy
 6 |   const w = v;
   |             ^

error: could not compile due to 3 previous errors
exit=1
```

A misspelled name gets a `did you mean` suggestion when a near name is in scope:

```fsh
function a(): i64 {
  return "x";
}
function main() {
  const count = 1;
  console.log(a(), cont);
}
// error: error[E0101]: type '"x"' is not assignable to return type 'i64'
// error: error[E0401]: cannot find name 'cont'; did you mean 'count'?
// error: error: could not compile due to 2 previous errors
```

Warnings have the same shape with `warning[CODE]`, never fail a build, and are printed by
`check`, `build`, `run` and `watch` alike. There are two: `W0001`, an unused variable or
parameter (`warning[W0001]: unused variable 'unused'; if it's intentional, name it '_unused'`),
and `W0002` (`unreachable code after 'return'`).

`fishc explain E0201` (the code in either case) prints what the code means, what TypeScript
would have done, and a fix; some codes answer only that they have no longer explanation yet.
Output is coloured on a terminal; `NO_COLOR` turns that off and `FORCE_COLOR=1` forces it into a
pipe. More: `examples/several_errors.fsh`, `examples/suggest.fsh`, `examples/warnings.fsh`.

## 8. A package

A package is a directory with a `fish.toml`. `fishc new <name>` makes one in a new directory,
`fishc init [<name>]` in the current one (keeping an existing `src/main.fsh` and `.gitignore`).

```sh
$ fishc new greeter
created the package 'greeter' in greeter/
$ find greeter -type f               # .gitignore holds "/target"
greeter/.gitignore
greeter/fish.toml
greeter/src/main.fsh
$ cd greeter && fishc run
Hello from greeter!
$ fishc build && fishc build --release && ls target/*
target/debug:   greeter
target/release: greeter
```

Inside a package (any directory at or below the one holding `fish.toml`), `check`, `build`,
`run`, `watch`, `test`, `fmt` and `lint` need no file. `fishc run -- a b` and `fishc run a b`
both pass arguments: a first word not ending in `.fsh` is an argument, not a file.

By convention `src/main.fsh` is the program (`entry`), `src/lib.fsh` is what other packages
import (`lib`), `target/` holds builds, and `fish.lock` appears once there are dependencies.

## 9. fish.toml

Everything the release reads. Any other table or key is an error, so a misspelling is caught.

```toml
[package]
name = "app"                 # required: lowercase letters, digits, '-', starts with a letter, at most 64
version = "0.1.0"            # required: MAJOR.MINOR.PATCH, optional pre-release ("1.0.0-beta.1")
entry = "src/main.fsh"       # default shown: the program `fishc build` builds
lib = "src/lib.fsh"          # default shown: what a package depending on this one imports
edition = "native"           # default shown; or "ts-compat"

[dependencies]
strutil = { version = "^0.1.0" }                        # registry, npm-style range
util = { path = "../util" }                             # a directory holding a fish.toml
other = { git = "https://example.com/other.git", rev = "3f2a9c1" }  # pinned to a commit hash

[rust-dependencies]          # Cargo's forms; called through declare module "rust:<crate>"
serde_json = "1"
serde = { version = "1", features = ["derive"], default-features = true }
local = { path = "../crate" }                           # or git with one of rev, tag, branch

[registry]
url = "https://github.com/fishlang-dev/registry"        # default shown: the index's git repository
```

- **A Fish dependency is always a table.** Cargo's and npm's `name = "^1.2.0"` is refused:
  `error[E0905]: a dependency is a table naming where it comes from, as in { version = "^1.2.0" }, { path = "../util" } or { git = "https://...", rev = "<commit>" }`.
  Only `[rust-dependencies]` takes a bare version string.
- A git `rev` is 7 to 40 lowercase hex digits: `branches and tags move`, says the refusal.
- `entry` and `lib` are `.fsh` paths inside the package. `lib` need not exist unless another
  package depends on this one; then a missing one is an error in that package's manifest, even
  if nothing imports it.
- The TOML read: comments, `[table]` headers, bare and quoted keys, one-line strings, integers,
  booleans, inline tables, arrays. A dotted key, a multi-line string or a float is `E0904`.
- `edition = "ts-compat"` marks a package as TypeScript not yet migrated. Fish does not compile
  that edition: it is what `fishc lint` reads (`porting.md`). A file's first-line comment
  `// @fish-edition native` or `// @fish-edition ts-compat` overrides the package's edition for
  that file, and a file outside any package is native.

```fsh
// @fish-edition ts-compat
function main() {
  console.log("never built");
}
// error: error[E0006]: this file is in the TS-compat edition, which Fish doesn't compile
```

## 10. Dependencies, fish.lock, add, update, publish

A build that resolves dependencies writes `fish.lock` beside `fish.toml`, one `[[package]]` per
package used, after `version = 1`. Commit it. A registry package's entry holds `name`,
`version`, `source = "registry+<index url>"` and `checksum = "sha256:<hex>"` over its unpacked
files; a git one has `source = "git+<url>#<full commit>"` and a checksum; a path one only
`source = "path+../util"`. `--locked` (for CI) refuses to change the file: `error[E0906]:
fish.lock is out of date with fish.toml, and --locked keeps it as it is; build without --locked
to update it, then commit it`.

`fishc add <name>` looks the package up in the registry index (a git repository cloned into the
cache, so it needs `git` and the network) and writes the dependency line, with `^<latest>` when
no range is given. `fishc update` moves every registry dependency to the newest version its
range allows and rewrites `fish.lock`; `fishc update <name>` moves one. They print `added
strutil ^0.1.0` and `updated fish.lock`; an unknown name is `fishc add: the registry has no
package 'nopkg'`, exit 2.

`fishc publish` packs the files git tracks (so the package must be committed in a git
repository; `--allow-dirty` packs with uncommitted changes) and reports every `unsafe` in it. A
published package may depend only on registry packages. `--dry-run` stops after packing:

```sh
$ fishc publish --dry-run
packed strutil 0.1.0: 4 files, 1 KiB, sha256 a9b01626bb2603e5dc9829a7410ec5e9fd4d03a791cfe33dfed7b1461f11aa3d
  .gitignore
  fish.toml
  src/lib.fsh
  src/main.fsh
wrote target/publish/strutil-0.1.0.tar.gz
no unsafe in strutil or its dependencies
```

Without `--dry-run` it also commits the archive and its index line on a branch in the cached
index clone; `--submit` then pushes that branch to a fork and opens a pull request with `gh`,
asking first unless `--yes`. Only the dry run was exercised for this slice.

## 11. How imports resolve

The specifier decides, in this order:

1. **A name in the importing package's `[dependencies]`**: that package's `lib` file. Only what
   the lib exports (re-exports included) is visible; `export` in a package's other files is for
   the package itself.
2. **A std module**, `node:fs` or bare `fs`: `assert`, `buffer`, `child_process`, `crypto`,
   `fs`, `fs/promises`, `os`, `path`, `process`, `tls`, `url`, `util`, `zlib`, plus `postgres`,
   `fish:tar`, `fish:zip` and `bun`. Their contents: `std.md`. The prelude (`console`, `Map`,
   `sleep`, `assert`, `process` and so on) needs no import.
3. **`rust:<crate>`**: a crate from `[rust-dependencies]` (`interop.md`).
4. **Any other bare name**: an npm package, found as TypeScript's bundler resolution finds its
   declarations in `node_modules` (`interop.md`).
5. **A relative path**, `./` or `../`: a file. Write the extension: `./math.fsh`. Without one,
   `./math` tries `math.fsh` then `math/index.fsh`, and `./math.ts` or `./math.js` means
   `math.fsh`, so ported imports keep working.

```fsh
import * as path from "node:path";
import { hostname } from "os";

function main() {
  console.log(path.join("a", "b"), hostname().length > 0); // expect: a/b true
}
```

Supported forms between files: named imports with `as`, `import type`, default imports and
`export default`, `export { a as b }`, `export { x } from`, `export * from`. A namespace import
(`import * as m`) works for a std module only; for a file it is refused with
`namespace imports aren't supported yet`, as is `import m = require(...)`. More:
`examples/modules_forms`, `examples/modules_basic`.

Only the entry file may declare `main`; importing a file that has one is `E0405` (`only the
entry file's main() runs`). A file is checked only if the entry reaches it through imports.

## 12. Package and import errors

| Code | When | Example message |
| --- | --- | --- |
| `E0901` | a relative import's file isn't there | `can't find the file './missing.fsh' imports from; looked for 'missing.fsh'` |
| `E0902` | the module lacks the name, or the npm package isn't installed | `the package 'util' has no export named 'hidden' in its lib src/lib.fsh; it declares 'hidden' without exporting it, so add 'export' before that declaration` |
| `E0903` | reaching into another package's files | `'util/src/text.fsh' is a file inside the package 'util', and a package's files are private to it; import from 'util', which gives what its lib src/lib.fsh exports` |
| `E0904` | `fish.toml` or `fish.lock` isn't TOML the compiler reads | `this value is TOML Fish doesn't read in a manifest yet` |
| `E0905` | a manifest that parses but is wrong | `[package] has no key 'license'; it has name, version, entry, lib, edition` |
| `E0906` | a dependency can't be resolved or verified | `the package at '../strutil' is named 'strutil' in its fish.toml, not 'other'; depend on it by that name` |
| `E0907` | an import clashes with a name in the file | `'join' is both imported and declared in this file; rename the import, as in 'import { join as otherJoin }'` |
| `E0908` | a Node built-in std lacks or reads differently | `'node:http' is a Node module Fish's std doesn't have yet` |
| `E0909` | a source file of 16 MiB or more | `'<file>' is larger than the 16 MiB a source file may be` |

Manifest errors point into `fish.toml` with the same caret rendering as source errors. `E0903`
also covers a relative path that climbs into another package (`import it by name, as 'util'`).
Other `E0906` cases: a path dependency's directory is missing, an unpacked package no longer
matches its checksum, the lockfile is out of date under `--locked`. An npm name not installed
is `E0902: can't find the package 'left-pad': no 'node_modules/left-pad' in` the file's
directory or any above it.

```fsh
import { y } from "./missing.fsh";

function main() {
  console.log(y);
}
// error: error[E0901]: can't find the file './missing.fsh' imports from; looked for 'missing.fsh'
```

## 13. Tests

A test is a top-level call `test("name", () => { ... })` in any `.fsh` file: beside the code it
covers or in a file of its own. `test` is not a function to call elsewhere. The name must be a
string literal, the body an arrow or `function` taking no parameters, sync or `async`, with an
optional third argument `{ timeout: <ms> }`. Anything else is `E1106` (`a test is written as
'test("name", () => { ... })' at the top level of a file, its name a string literal`).

A build, a run and a check **leave test blocks out entirely**, body unchecked:

```fsh
function add(a: i64, b: i64): i64 {
  return a + b;
}

test("never checked by a build", () => {
  const n: i64 = "not a number";
  assert(add(1, 2) === 4);
});

function main() {
  console.log(add(1, 2)); // expect: 3
}
```

`fishc test` runs only inside a package. It loads **every `.fsh` file in the package**, imported
by the entry or not (skipping `target`, `node_modules`, dot directories and nested packages),
compiles them into one program, and runs each test in a process of its own, in parallel,
reporting in declaration order. So a compile error in any file or any test body stops the run
with exit 1 before a test starts, and test names must be unique across the package.

A test fails when its process exits non-zero or runs past its limit:

- **`assert(cond, message?)`** panics when false, printing `panicked at <file>:<line>:<col>:`,
  the message and a backtrace. `assert` is in the prelude.
- **A throw.** A test body is compiled as a function that `throws Error`, so a call that can
  throw needs no `try`, unlike in an ordinary function without a `throws` clause.
- **A panic** (overflow, an index out of bounds), or `process.exit(3)`: `exited with 3`.
- **The limit**, 10 s unless `{ timeout }` or `--timeout <ms>` says otherwise: `timed out after 50ms`.

```sh
$ cat src/math.fsh
export function add(a: i64, b: i64): i64 {
  return a + b;
}
export function half(n: i64): i64 throws Error {
  if (n % 2 !== 0) throw new Error(`${n} is odd`);
  return n / 2;
}
test("add sums", () => {
  assert(add(1, 2) === 3);
});
test("half of an even number", async () => {
  await sleep(1);
  assert(half(4) === 2, "4 halves to 2");
});
test("half of an odd number", () => {
  console.log("about to halve 3");
  assert(half(3) === 1);
});
$ fishc test
ok src/math.fsh > add sums
ok src/math.fsh > half of an even number
FAIL src/math.fsh > half of an odd number
about to halve 3
Error: [Error: 3 is odd]
2 passed, 1 failed
exit=1
```

A failing test's stdout and stderr follow its line; a passing test's output is dropped.

`fishc test <filter>` runs the tests whose name contains the text (a substring, not a pattern);
no match is `fishc test: no test's name contains 'nothing'`, exit 1. `--release` builds
optimized. `--timeout <ms>` sets the limit for tests that name none. `--jobs <n>` caps how many
run at once (default: one per core). A package with no tests prints `no tests found`, exit 0.
Tests run with the package directory as the working directory. More: `examples/tests.fsh`.

**The example bank is not `fishc test` input.** Files under `examples/` use the compiler's own
golden format: `// case: <name>` starts a separate program, and comments state its outcome
(`// expect:`, `// error:`, `// panic:`, `// errors: <count>`, `// stderr:`, and `// mode:`
`release`, `abort` or `parse` for how it is built). To try a case, copy it into its own file.

## 14. Formatter, lint, survey

`fishc fmt` rewrites files in place in one fixed style (double quotes, semicolons, two spaces).
With no path it formats the package around the working directory; a directory means the `.fsh`
files under it. `--check` writes nothing, prints each file that would change, and exits 1 if any
would. `fishc fmt -` formats stdin to stdout. A file that doesn't parse is reported as a syntax
error, exit 1, and left alone.

`fishc lint` reads TS-compat code only: `.ts` files named on the command line, files marked
`// @fish-edition ts-compat`, and packages with `edition = "ts-compat"`. Each hit is printed
like an error with `auto <rule>` or `guided <rule>` in place of `error[...]`, then a count; exit
1 when anything is left to change. `--fix` applies the `auto` rules and renames a `.ts` file to
`.fsh`. On a native file it prints `is in the native edition, so there's nothing to lint`, exit 0.
A hit reads `src/a.ts:6:14: auto A2: 'string | null' becomes 'Option<string>'` with the source
line under it, and the run ends `5 to change in 1 file`.

`fishc survey <dir>` reads a TypeScript project (`.ts`, `.tsx`, `.mts`) and prints a grade, a
score per 1000 lines and the rewrites it would need; `--json` prints the report as JSON, and
`--compare <old.json>` diffs against a saved one. The rules and the workflow: `porting.md`.

## 15. Editors

`fishc lsp` speaks the Language Server Protocol over stdio and takes no arguments. Its
`initialize` answer advertises full-document sync (with diagnostics on open and change), hover,
go to definition, find references, completion triggered by `.`, formatting, inlay hints (on
calls that can throw) and code lenses (run `main`, run a test), and nothing else: no rename,
signature help or document symbols. The compiler's repository holds two editor packages,
neither inside a release archive:

- `editors/vscode`: the VS Code extension (language id `fsh`). TextMate highlighting based on
  TypeScript's grammar, the language server, format on save, **Run** and **Run test** lenses,
  and `fishc build`, `run` and `check` tasks. It runs the `fishc` on `PATH`, or the one named by
  the `fsh.fishc.path` setting.
- `editors/tree-sitter-fsh`: a tree-sitter grammar (tree-sitter-typescript's plus Fish's forms)
  with highlight and tag queries, for Neovim, Helix and others. The language is named `fsh`
  because `fish` belongs to the fish shell.

## 16. Environment variables

| Variable | Read by | Effect |
| --- | --- | --- |
| `PATH` | fishc | where `clang`, `git`, `curl`, `gh` and the linkers are found |
| `FISH_CACHE_DIR` | fishc | the cache directory (section 6); `XDG_CACHE_HOME` is the fallback before `~/.cache` |
| `FISH_SYSROOT` | `fishc build` | the sysroot for a `--target` other than the host, when `--sysroot` isn't given |
| `FISH_REGISTRY` | fishc | the registry index, over `[registry] url` and the default |
| `FISH_NO_CHECK_CACHE` | fishc | set to anything: the same as `--no-check-cache` |
| `NO_COLOR`, `FORCE_COLOR` | fishc | colour off on a terminal; colour on in a pipe (`FORCE_COLOR=0` counts as unset) |
| `FISH_MEM=1`, `FISH_MEM_STOP=<stage>` | fishc | for work on fishc itself: print memory per compiler stage; stop after `parse`, `check` or `codegen` |
| `FISH_WATCH_VERIFY`, `FISH_WATCH_IR=<dir>` | `fishc watch` | compare each incremental rebuild with a clean one; save each build's IR |
| `FISH_LEAKS=1` | every built program | print `fish: leaked N allocations` at exit if anything is still allocated |

## 17. A verify loop for agents

Use the cheapest command that answers the question. Times are for small programs on an ARM64
Mac with a warm cache; std is checked with every program, which is most of the 0.1 s.

| Question | Command | Time | Reading the answer |
| --- | --- | --- | --- |
| Does it parse? | `fishc parse f.fsh` | 0.03 s | silent, exit 0 |
| Does it type- and borrow-check? | `fishc check f.fsh` (or `fishc check` in a package) | 0.1 s | silent or warnings, exit 0; errors, exit 1 |
| Does it run correctly? | `fishc run f.fsh -- args` | 0.7 s | the program's output and exit code; 101 is a panic |
| Do the tests pass? | `fishc test` | 0.7 s and up | `N passed, M failed`, exit 1 on any failure |
| Does it leak? | `fishc run f.fsh --leaks` | 0.7 s | a `fish: leaked` report on stderr, or nothing |
| Is it formatted? | `fishc fmt --check f.fsh` | 0.03 s | paths that would change, exit 1 |
| Does it still work optimized? | `fishc run f.fsh --release` | 0.7 s | overflow wraps instead of panicking |
| Memory errors in `unsafe` code? | `fishc build f.fsh --sanitize address -o f-asan && ./f-asan` | 0.4 s to build | the sanitizer's report |

- Loop on `fishc check` until it is clean, then `fishc run` once. `check` reports several
  errors per pass, so fix them all before checking again.
- **Symptom**: `fishc check` and `fishc build` pass, `fishc test` reports a type error.
  **Why**: only `fishc test` compiles `test()` bodies and files the entry doesn't import.
  **Fix**: run `fishc test` before calling a package done.
- A plain `fishc build` takes 0.2 s; `fishc run` takes longer because macOS spends about half a
  second on the first launch of each freshly linked binary.
- A single scratch file needs no package; tests and Fish dependencies do (`fishc new`).

## Not released yet

In the compiler's source, refused by fishc 0.1.1 (both print the usage text, exit 2):

- `fishc explain-borrows <file.fsh> [--fn <name>]`: prints a file with its moves, loans and
  ownership errors marked under the lines they happen on, for one function or all.
- `fishc openapi <file.fsh> [-o <out>]`: prints the OpenAPI document of the routes a program
  adds to std's `Router`, with the title and version from the package's manifest.
