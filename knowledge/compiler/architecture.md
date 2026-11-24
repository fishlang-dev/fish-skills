# The fishc compiler: architecture

How `fishc` is built inside: the stages, what crosses each boundary, the data model, and which
file owns what. It is for someone about to change the compiler, and it is restated from the
source under `src/`, which is the authority wherever this page and the code differ. Procedures
(building, testing, adding a feature) are in `workflows.md`. What the language means is in
`language.md`, `ownership.md` and `types.md`. This slice follows the compiler's main line of
development after release 0.1.1, not the release.

## 1. The pipeline

`fishc` is written in Fish and compiled by an earlier `fishc`. A build runs these stages in
order. Any stage before clang may throw a `CompileError`, which the CLI renders once.

| Stage | Owner | Takes | Gives |
| --- | --- | --- | --- |
| load | `modules.fsh` | the entry path, imports found as it parses | `Loaded`: one `Module` per file, each parsed in its own offset range |
| lex | `lexer.fsh` | source text | `Token`s, on demand |
| parse | `parser.fsh`, `types.fsh`, `expressions.fsh`, `patterns.fsh`, `declarations.fsh` | tokens through a `Cursor` | `Stmt[]` |
| tests | `tests.fsh` | each file's top-level `test(...)` blocks | stripped for a build, lifted into functions for `fishc test` and the editor |
| macros | `macros.fsh`, `quote.fsh`, `unquote.fsh` | decorated top-level declarations | the declarations each macro returned, in place |
| link | `modules.fsh` (`flatten`) | every file's statements | one `Stmt[]`, top-level names made unique |
| lower | `overloads.fsh`, `locals.fsh`, `keys.fsh`, `defaults.fsh`, then std added by `std.fsh` | the linked program | the program the checker reads |
| check | `check.fsh`, `values.fsh` and the checker's modules | that program | `Checked`: instances and tables |
| moves | `moves.fsh` | one checked body and its instance | ownership errors, captures, consumed places |
| comptime | `comptime.fsh` | the checked program | values baked into the binary, macro results |
| codegen | `codegen.fsh`, `layout.fsh`, `arithmetic.fsh`, `runtime.fsh` | `Checked` | LLVM IR as text |
| compile, link | `main.fsh`, `split.fsh`, `mathlib.fsh` | the IR, cached runtime objects | an executable, through clang |

`analysis.fsh` holds the front half as every compile and check starts it. `queries.fsh` is the
door every check goes through, so a rebuild can reuse a kept one (section 16). `main.fsh` is the
CLI and drives codegen and clang. `--timings` prints the stages as `parse`, `macros`, `check`,
`moves`, `comptime`, `codegen`, `compile`, `runtime`, `link`; a stage timed inside another is
taken out of the outer one, so `moves` is not counted in `check` twice.

## 2. Tokens and the lexer

`lexer(src)` returns a `Lexer` that makes tokens on demand, because only the parser knows
whether a `/` divides or starts a regular expression. `Lexer.regex(slash)` scans again from a
`/` or `/=` token and gives a `regex` token. A `Token` has:

- `kind`: `ident` (keywords are idents, since most TypeScript keywords are contextual),
  `private` (`#name`), `int`, `float`, `bigint`, `string`, `regex`, `template`, `templateHead`,
  `templateMiddle`, `templateTail`, `punct`, `eof`
- `text` (for strings and templates, the decoded value), `start` and `end` (source offsets)
- `newlineBefore`: drives automatic semicolon insertion and the "on its line" rules

`<` and `>` are always single tokens. The parser rejoins `>=`, `>>`, `>>>` and `<<` from adjacent
tokens, so `A<B<C>>` closes two generics. The lexer keeps every comment it scans (`Comment`),
which the formatter and JSDoc `@throws` read.

## 3. The Cursor and the parser

Every grammar function is a plain function taking the shared `Cursor` (`c: Mut<Cursor>`):
recursive descent, with Pratt parsing for binary operators in `expressions.fsh`. The cursor
holds the lexer, every token lexed so far, and `pos`. Its helpers are `peek(offset)`, `token`,
`next`, `at`, `atAny`, `eat`, `expect`, `ident`, `list`, `end`, `error`, `regex` and `attempt`.
Its context flags:

- `conditionalAllowed`: false only directly inside a conditional type's `extends` clause
- `inAllowed`: false only directly inside a `for` initializer, so `for (x in y)` is not read as
  an expression; `allowingIn` sets it for a nested parse and restores it
- `inPipe` and `topicUsed`: set while parsing the right side of `|>`, and whether it used `%`
- `docs`: whether JSDoc `@throws` tags count as a `throws` clause (true when compiling, false
  when formatting or linting)

`attempt(parse)` is speculative parsing: on a `CompileError` it puts `pos` and the flags back
and returns `undefined`. Two rules that bite:

- Never `peek` past a `/` where an expression may start. It may begin a regex, and lexing a
  regex body as tokens can fail.
- A new keyword is contextual. It is an `ident` token, and the grammar decides from what follows
  on the line (`newlineBefore`) whether it is the keyword or a name.

Entry points: `parse(src, ids)` for a program, `parseWithComments` for the formatter,
`parseExpression` and `parseType` for quotes. A syntax error is `E0001`, made by `c.error(...)`
as `expected X, found Y`.

## 4. The AST

Nodes are plain objects discriminated by a `kind` string. Every node is `Span & Id & {...}`:
`start` and `end` source offsets, and `id`, a number unique in its compilation. The types are
declared at the top of `parser.fsh`:

- `Stmt`: every TypeScript statement and declaration plus `comptime` and `unsafe` blocks. A
  program is `Stmt[]`. A `let` holds its `keyword` (`let`, `const`, `var`, `using`,
  `await using`) and `Declarator[]`; an assignment or `x++` is an `expr` statement; `Func` has
  `async`, `generator`, `macro`, an optional `throws` type and an optional `body` (absent for an
  overload signature or `declare function`).
- `Expr`: every TypeScript expression plus `match`, `pipe`, `topic`, `comptime`, `unsafe` and
  `tagged`. Assignments are expressions: `assign`, and `destructure` when the left side is a
  pattern.
- `TypeNode`: the full TypeScript type grammar (`ref`, `literal`, `array`, `tuple`, `object`,
  `function`, `union`, `intersection`, `operator`, `indexed`, `query`, `import`, `conditional`,
  `infer`, `mapped`, `template`, `predicate`). Keyword types are `ref`s.
- `Pattern`: `ident`, `object`, `array`, `default`, `expr` for binding and assignment, plus
  `wildcard`, `literal`, `variant` and `or`, which only `match` makes. A bare name such as
  `None` stays an `ident`: whether it binds or names a variant is the checker's call.
- `Param`: `pattern`, `type`, `optional`, `rest`, `default`, `modifiers` (parameter
  properties), `decorators`, `comptime`. `this` is an identifier pattern named `this`.
- `ClassNode`, shared by class declarations and expressions, with `ClassMember`s (`field`,
  `method`, `constructor`, `get`, `set`, `index`, `staticBlock`) carrying `modifiers` and
  `decorators`.
- `BinaryOp` is TypeScript's whole table; `ArithmeticOp` is the `+ - * / %` subset.

Code branches on `kind` with `switch` or `if`. There are no visitor classes. `src/ast.fsh` is
the same tree as Fish type declarations (`AstExpr`, `AstStmt`, `AstType`, `AstPattern`),
generated from `parser.fsh`: it is what a macro sees, without the ids.

## 5. Node ids, node tables, Rewrites and the generated walkers

Fish's `Map` and `Set` key on strings and integers, not objects, so every per-node table keys on
the node's `id`. `Ids` (`{ last }`) is the counter; each compilation has its own, and `nextId`
gives a fresh one. `nodes.fsh` holds the tables:

- `NodeMap<K, V>` and `NodeSet<K>`: a map and a set of nodes by id
- `SiteTable<V>`: a value per expression id beside a `Site`, the few parts of the expression its
  readers look at (id, span, kind, a name, a callee). An instance's `types`, `calls` and
  `coercions` are `SiteTable`s, because keeping a copy of each expression held most of the
  program many times over.
- `TypeMap` and `TypeSet` (in `typing.fsh`) do the same for types.

**Rewrites.** Lowering never changes a node's kind or children in place. It records a
replacement in the compilation's `Rewrites` (`rewrites.replace(node, by)`), and the replacement
takes the id of the node it replaces, so every table reads one entry for either. While a body is
being checked, code reads a node through `rewrites.current(node)`. After the body's check, a
rebuild puts each replacement into the tree (`startRebuild`, `rebuiltStmts`, `refresh` in
`BodyChecker`), so the move check, comptime and codegen read a plain tree. A pass that lowers
before checking keeps a `Rewrites` of its own and rebuilds before it returns. A statement list
the checker edits is recorded by its body, its owner's id and its field.

**Generated walkers.** `walk.fsh` (children of each node, tagged, in field order) and
`rebuild.fsh` (clone, id and rebuild helpers per node type) are generated from the AST types.
`walk(root, each)`, `walkWhile`, `someNode` and `forEachChild` in `nodes.fsh` are how a pass
visits a tree, with a root tagged like `{ of: "stmts", node: program }`. Adding a field or a
kind to the AST means regenerating them (`workflows.md`).

## 6. Loading, tests, macros and linking

`load` reads the entry and every file it imports, each parsed once. Offsets say which file a
position is in: each file after the entry starts at its own multiple of `FILE_SPAN` (2^24, in
`program.fsh`), and std's source sits at `STD_BASE` (2^40). A `Module` has its `path`, `src`,
`base`, `statements` and the module each import names (`targets`). Std modules are loaded as
files named `std:<name>`. A package's `.d.ts` is found by `typings.fsh` and turned into Fish
declarations by `js.fsh`; npm code is bundled by `bundle.fsh` for the embedded JS engine.

`tests.fsh` handles top-level `test("name", () => {})` blocks: `stripTests` removes them from a
build, and `liftTests` turns them into functions for `fishc test`, which generates a harness
`main`, and for the editor.

`expandMacros` runs before linking. Each round checks the macros and what they use as a program
of their own (`macroCompilation`, so the real compilation is not used up), runs each
`macro function` through the comptime interpreter on the declaration it decorates, and puts
what it returns in place. `quote.fsh` parses a `quote` template into an `Ast` value;
`unquote.fsh` turns an `Ast` value back into a tree with fresh ids.

`flatten` links the files into one `Stmt[]`. A top-level name is told apart from another
file's by a suffix (`helper-fsh2`), which `diag.fsh` strips again when a message is shown.

## 7. Lowering before the check

`lowered` in `check.fsh` prepares the program the checker reads, in this order:

1. `lowerOverloads`: each overload signature becomes a function that calls the implementation
2. `hoistLocals`: a `type`, `interface`, `enum` or `class` written in a body becomes a top-level
   declaration under a name only its scope can write (`Point@0`)
3. `lowerKeys`: computed property names known while compiling become field names
4. `lowerDefaults`: `x: T = v` becomes an optional parameter and a first statement
   `let x: T = <it> ?? v`
5. `stdFor`: std's statements are put in front (section 14)

Everything else that lowering does happens during the check, through `Rewrites`.

## 8. A compilation and its arenas

`compilation.fsh` holds the state. Nothing is module state: a test asserts `src/` has no
top-level `let` and never mutates a top-level table.

- `Session`: what outlives one compilation (a CLI run, a language server, a test): the lockfile
  option, `timings`, whether cached checks may be read. `BuildSession` (`mathlib.fsh`) adds the
  caches only building objects needs. `cachedSession()` in `stdcache.fsh` is what the CLI and
  tests start from.
- `Compilation`: one program's `ids`, `rewrites`, `names` (made-up names and how to show them),
  `typing`, `arenas`, `counts`, `files`, and its `session`.
- `Tables`: what one check fills in and the later passes read. It carries the compilation's
  parts plus program-wide node tables (`declarations`, `nestedFunctions`, `equalities`,
  `disposers` and many more, each documented where it is declared).
- `Arenas` (`arenas.fsh`): the compilation's `Instance`s, `Body`s, `Local`s and `ClassInfo`s.
  Each is named by its place from 1, as a branded id: `InstanceId`, `BodyId`, `LocalId`,
  `ClassId`. Read them with `instanceOf`, `bodyOf`, `localOf`, `classOf`, change them through
  `instanceMut`, `bodyMut`, `localMut`, `classMut`, and lend one beside the arena with
  `swapInstance` and `swapBody`. These records refer to each other only by id, never by holding
  one another, which a test enforces.

## 9. Body, Instance and Checked

A `Body` (`classes.fsh`) is a function as written: a top-level function, a class's constructor,
method, static or accessor, a closure, or a top-level `const` treated as a function giving its
value. It has `name`, `params`, `body`, `returnType`, `throws`, `typeParams`, `self` (`type`,
`constructor`, `mutable`, `owned`), `owner`, `scope` (what a generic class's parameters stand
for), `overloads`, `copyOf`, and `closure` (with its `parent` instance). `bodyId` names it in
the arena, apart from its node `id`.

An `Instance` (`check.fsh`) is a body checked with concrete types, and is one compiled function:

- `id`, `body` (a `BodyId`), `symbol`, `bindings` (type parameter name to type), `concrete`,
  `depth`, `returns`, `throws`
- `types: SiteTable<Type>`: every value expression's type
- `locals: NodeMap<Expr | Stmt | Param | ObjectProp, LocalId>`: the binding each name use,
  declaration, parameter and shorthand property refers to, after shadowing
- `calls: SiteTable<InstanceId>`: the instance each call, `new` and accessor read runs
- `setters: NodeMap<Expr, InstanceId>`: the setter each assignment to an accessor runs
- `coercions: SiteTable<Type>`: each value meeting a narrower declared type, and the type it
  is copied down to
- `jumps: NodeMap<Stmt, JumpTarget>`: the loop, `switch` or labeled statement each `break`
  leaves and each `continue` repeats
- also `borrowsFrom`, `raises` and `caught` (error flow), `consumes` (places handed over, set
  by the move check), `patterns` (what each `match` pattern tests) and `copiesOut`

A `Local` is `{ name, type, mutable, param, id, localId }`: `id` is unique within one check and
names the IR slot, `localId` is its arena id. `Checked` is `{ instances: InstanceId[], tables,
warnings }`, and `compiledOf(checked)` in `codegen.fsh` gives the instances as records.

## 10. The type model

`typing.fsh`. A `Type` is a primitive's name (a sized integer or float such as `"i64"`, or
`"boolean"`, `"string"`, `"bigint"`, `"void"`, `"null"`, `"never"`) or a branded integer id
indexing the `Typing`'s arena of records, read with `typing.rec(t)` (a copy), `recRef(t)` (no
copy, for a read that does not outlive a change) or `kindOf(t)`, and changed with `setRec`. Ids
start at 21; 21 to 23 are fixed (`SLEEP`, `YIELD_NOW`, `ANY_REGEX`). `TypeMap` and `TypeSet`
key primitives by reserved ids 1 to 20.

Record kinds include `object`, `class`, `interface`, `param`, `literal`, `union`, `ref`,
`variant`, `array`, `fixed`, `map`, `closure`, `function`, `pattern`, `brand`, `interior`
(`Atomic`, `Lock`, `RwLock`, `Cell`), `shared` (`shared`, `Rc`, `Weak`), `dyn`, `block`
(runtime handles such as `Channel` and `TcpStream`), `handle`, `future`, `generator`,
`pointer`, `regex`, `recursive` and `unknown`.

- Interning: object types (fields sorted by name) and unions (flattened, deduplicated, ordered)
  are interned, so `===` on two types is structural identity for them. Classes are nominal: one
  type per declaration or per generic instance.
- A `Field` is `{ name, type, access?, readonly?, optional? }`. `fieldsOf(t)` gives a type's
  fields, a type parameter's through its bound.
- A `LiteralType` has one value and fits its base type; an enum member is a literal that knows
  its enum (`owner`).
- `fits(from, to)` is assignability: the same type, `never` into anything, a literal into its
  base, a type parameter as the concrete type it stands for, and an object or an instance into
  an object type it has at least the fields of (extra fields allowed, only public ones count).
- `unsatisfied(type, trait, members, at)` in `interfaces.fsh` checks a type against an
  interface by shape and returns why it fails, or `undefined`. `implements` is never needed.
- `lower(t)` replaces each type parameter with the concrete type it stands for in an instance,
  and `show(t)` is how a message names a type.
- Instances are monomorphized, so type parameters never reach codegen. A value used through an
  interface at run time is a `Dyn`.

## 11. Generics

`generics.fsh`. A generic body, and a generic class, is checked once at its definition with
placeholder `param` types (the definition check: an instance with `concrete: false`, never
compiled). Each call infers or reads its type arguments, checks them against the bounds (an
interface or object type, or a type naming values such as `K extends "a" | "b"`), and requests
the instance for exactly those bindings. Only concrete instances are compiled.

- A parameter typed with an interface is an implicit type parameter (so is one typed `RegExp`):
  `function show(x: Shape)` is instantiated per concrete argument type.
- A concrete instance's symbol is its name plus `#` and a hash of its type arguments
  (`first#rv34vv`), so it is the same in every program and build order.
- `depth` counts the instantiations that led to an instance. Past 64 the checker reports a
  generic that instantiates without end.
- A generic class is declared again for each set of type arguments (`templates` on the
  `Checker`, `GenericClasses`), giving a class named with them (`Box<i64>`).

## 12. Classes, unions, enums, narrowing and match

- **Classes** (`classes.fsh`, `registry.fsh`): a `ClassInfo` has `type`, `fields`, its
  `constructor` body, `methods`, `statics`, `staticFields`, `required` (fields a constructor
  must assign before `this` is otherwise used) and its abstract members. The `Registry` links
  each class to its base, lays it out and checks `override` and `implements`. `extends` embeds
  the base as the first field and delegates to it. A method borrows `this` read-only unless it
  declares `this: Mut<this>`, or takes it with `this: Own<this>`.
- **Unions** (`unions.fsh`, `layout.fsh`): a `UnionRecord` lists its members. At run time a
  union is a tag (the member's index) and enough 64-bit words for its largest member. `Option`
  is a union with `null`.
- **Enums** (`enums.fsh`): a C-like enum is the union of its members, each a literal that knows
  its enum. One with computed members is `pending` until first read. A data-carrying enum is a
  union of `variant` types, made once per set of type arguments.
- **Narrowing** (`narrow.fsh`): `Facts` is a `Map<string, Type>` from a binding's id, or a field
  path such as `3.next.value`, to the narrower type a condition proved. `typeof`, literal and
  discriminant comparisons and `instanceof` narrow through `if`, early exits, `&&`, `||`, `?:`,
  `while` and `switch`. A narrowed read gives the narrower type, which codegen takes out of the
  union.
- **Match** (`match.fsh`): each pattern gets a `PatternInfo` in the instance's `patterns`
  (`any`, `literal`, `variant`, `some`, `none`, `or`) with the type of the value it meets, and
  the same module computes which values no arm covers.
- Conditions must be `boolean`: there is no truthiness. A form that parses but has no meaning
  yet is refused with `E0801`, `<description> are not supported yet` (`unsupported.fsh`).

## 13. The Checker and its modules

`check(compilation, program)` builds one `Checker` per compilation and calls `run()`, which
links and lays out every class, starts the generic classes, validates aliases, settles enums,
checks `implements` claims, then checks each function's definition. Checking a body requests the
instances its calls need, which are checked in turn. A `BodyChecker` checks one body: it holds
its `Checker` as `cx` and its state in `BodyState`, `ContextState` and `ExpressionsState`, and
runs the statements, then the rebuild, then the move check. Each declaration and body is checked
on its own and errors are collected, so one build reports several.

**The module convention.** The checker's and the back end's modules are classes, of two kinds:

- A self-contained module is owned as a field: `Typing`, `Arenas`.
- A module that calls back into a host is a view made where it is used, over that host, and its
  lasting state lives in a data class the host owns. `this.registry()` returns
  `new Registry(this)` and its state is `RegistryState`; the same holds for `GenericClasses`,
  `Instancing`, `Resolver`, `Expressions` (over a `BodyChecker`), `TypeFunctions` and comptime's
  `Interpreter`. In the back end, `Lowering<H extends Builder>` (`arithmetic.fsh`),
  `Conversions<H extends Slots>` (`layout.fsh`) and `Printer<H extends PrintHost>`
  (`runtime.fsh`) are views over `Codegen`.

The reason is ownership: a module owned as a field would run its methods on the field while the
host is lent to them, which Fish refuses. `tests/unit/modules.fsh` parses the checker's files
and guards the convention:

- no top-level function returns an object of its own inner functions
- no code destructures a method out of a module's instance
- no class holds, as a field, a module that calls back into its host
- no module that calls back into its host keeps state of its own
- the checker's files import only the modules meant to be checked with them
- every fallible function, method and constructor declares what it throws

## 14. Moves, comptime and std

**Moves and borrows** (`moves.fsh`). `checkMoves(tables, body, instance, origins)` runs per
instance right after the body's rebuild, with the body and instance swapped out of the arena.
It walks the checked body in evaluation order tracking a `State`: `moves` (place to where it
moved) and `loans` (a place lent to references, shared or mutable, and who holds it). A place
is a local's id or `this` followed by a field path, like `3.inner.x`. It reads the instance's
`types`, `locals`, `calls` and `borrowsFrom`, and returns the closure `captures`, the `consumes`
set codegen needs to know which places are handed over rather than copied, and `keeps`. Errors
are `CompileError`s in the `E02xx` range, most with a `note` pointing at the move or the loan.
With `session.borrows` set it also logs every move and loan, which `fishc explain-borrows`
prints.

**Comptime** (`comptime.fsh`). An `Interpreter` runs the checked program directly: it evaluates
`Expr` and `Stmt` nodes using an instance's tables, over `Value`s (`record`, `array`, `variant`
and so on). It is pure computation: anything that would reach outside the program or wait is
refused at the comptime site, and a run is limited to 10,000,000 steps and a call depth of
1,000. It is entered from the checker (comptime arguments, computed enum members), from macro
expansion (`comptimeCall`), and from codegen, which bakes `comptime expr` values, runs
`comptime { }` blocks and computes top-level consts into globals.

**Std** (`std.fsh`). Fish's std library is Fish source held in template strings inside the
compiler. `STD_SOURCE` joins sections (`PRELUDE`, `HTTP`, `FETCH`, `BYTES`, `DATE`, `STREAMS`
and others). `stdFor` parses it for each compilation, always keeps the prelude, and adds a
section only when the program names something it declares, then renames helpers to names no
program can write and moves the spans past `STD_BASE`. `STD_MODULES` maps a module name (`fs`,
`path`, `os`, `child_process`, `sqlite`, `fish:tar`, `Bun`) to its source, loaded as a file when
imported; `stdModule` resolves `node:fs` and `fs` to the same entry. The session can hold a
parsed std tree, but `cachedSession()` does not fill it, so each compilation parses std.

## 15. Codegen and the runtime

`Codegen` (`codegen.fsh`) lowers `Checked` to one LLVM IR module as text, with no target
triple, so clang targets the host. It trusts the checker and does no checking of its own: the
statement switch in `lowerStatement` lists the kinds and has no `default`, and the expression
switch ends in `assert(false, "internal error: no lowering for <kind>")`. A form reaching
codegen without a lowering is a compiler bug, never a user diagnostic.

```fsh
function add(a: i64, b: i64): i64 {
  const sum = a + b;
  return sum;
}
function main() {
  console.log(add(1, 2)); // expect: 3
}
```

`fishc build --emit-llvm` prints the module. For `add` in a dev build it holds these lines,
among others:

```text
define internal i64 @"fsh.add"(i64 %"a.arg", i64 %"b.arg") uwtable personality ptr @__gcc_personality_v0 {
entry:
  %a.0 = alloca i64
  %b.1 = alloca i64
  %sum.2 = alloca i64
  store i64 %"a.arg", ptr %a.0
  %t2 = call { i64, i1 } @llvm.sadd.with.overflow.i64(i64 %t0, i64 %t1)
  call void @fsh_rt_panic(ptr @.str.2fya2nt3hzean)
  store i64 %t3, ptr %sum.2
```

- **Symbols.** Each instance is `@"fsh.<symbol>"`: `fsh.add`, `fsh.Counter.bump`,
  `fsh.Counter.constructor`, `fsh.first#rv34vv`, `fsh.Box<i64>.get#rv34vv`. Quotes in a symbol
  are escaped, long type argument lists are replaced by a digest (`shortened`), and symbols that
  read alike are told apart by a digest of the whole symbol, never by the order instances were
  made in. A C `@main` calls `@"fsh.main"`. A C or Rust function keeps its own name.
- **Slots.** Parameters arrive as `%"<name>.arg"`. Every binding is an entry-block `alloca`
  named `%<name>.<id>` from `Local.id`, which clang promotes.
- **Layout** (`layout.fsh`, `sizes.fsh`). `llvmOf` gives the type a value is held as. An object
  is a named struct of its fields in sorted order (`%"<o.<hash>>"`). An instance is a named
  struct (`%"<Counter>"`) of its embedded base, if any, then its own fields in declaration
  order. A union is `{ i32, [N x i64] }` (`%"<u.<hash>>"`). An array is `{ ptr, i64, i64 }`:
  buffer, length, capacity. A `Dyn` is `{ ptr, ptr }`: the value's block and a vtable. A
  string, reference, map, shared value, handle and recursive type is a `ptr`. `boolean` is
  `i1`. Aggregates pass by value. `Conversions` moves a value between two types that hold it
  differently (into, out of and between unions) and decides equality.
- **Methods and `new`.** Constructors, methods and accessors take `ptr %this` first. `new`
  reserves a slot, calls the constructor on it and loads the value. Field reads use
  `extractvalue`; field writes use a `getelementptr` from the slot.
- **Arithmetic** (`arithmetic.fsh`). `+ - *` and unary `-` on integers call the
  `llvm.*.with.overflow` intrinsics and panic in dev builds, and wrap in `--release`. Division
  and remainder by zero panic in every build.
- **Panics.** A panic calls `fsh_rt_panic` with `panicked at <file>:<line>:<col>:` and the
  reason, worded as Rust words it (`attempt to divide by zero`). The program exits with 101.
  Dev builds keep a frame record per function (`%fsh.site`, linked through `@fsh_rt_frames`)
  for the backtrace. With `--panic=unwind` (the default) a panic unwinds and runs drops; calls
  that can panic inside a scope holding values are `invoke`s with a cleanup `landingpad`.
- **Printing.** `console.log` lowers through `Printer` to a `printf` call between
  `fsh_rt_print_begin` and `fsh_rt_print_end`, with string literals folded into the format.
- **Async and generators.** A `future` or `generator` type has a `frame` of fields. The body is
  lowered to a poll (or resume) function over that frame, and the runtime's executor polls it.

**The runtime.** `runtime.fsh` holds `RUNTIME`, the IR declarations of what compiled code calls
(`printf`, the `fsh_rt_*` functions). `native.fsh` holds the C half as text: `NATIVE` (the
allocator that counts live blocks, strings, arrays, maps, tasks, the reactor, files, sockets)
plus `TLS_NATIVE`, `ZLIB_NATIVE` and `SQLITE_NATIVE`, each compiled and linked only when the
program's IR calls into it. A string is a block: a reference count, a byte length, a pointer to
its bytes, the block it shares them with when it is a slice, its UTF-16 length once known, then
its bytes; a count below zero marks a literal. `mathlib.fsh` builds the correctly rounded `Math`
functions from `src/runtime/math.cpp` and `vendor/`. `js_native.fsh` is the glue to the vendored
JS engine, linked only into programs that use npm packages.

## 16. Incremental builds and caches

- **Queries** (`queries.fsh`). A `Queries` holds what a program is checked with; a kept check
  (`Kept`, in `incremental.fsh`) is passed in and handed back. If every file read still has the
  text it had, the kept check is reused. If only bodies changed (`edits.fsh` compares the old and
  new text of each file), `recheckKept` checks just those bodies again. Anything else falls back to
  a fresh check: an edit that is more than bodies, a changed constructor, or a change to a file
  that is not the program's own.
- **`fishc watch`** (`watch.fsh`) keeps the `Kept` between rebuilds, and codegen's `Emitted`
  (each function's text and what it uses), so only rechecked instances are emitted again.
  With `FISH_WATCH_VERIFY` set, each rebuild is also built clean and a difference is reported.
- **The language server** (`lsp.fsh`, `navigate.fsh`) holds one `Queries` per program and checks
  with `editing` set: tests are lifted in and the entry needs no `main`.
- **Objects.** A dev build's IR is split by `split.fsh` into std's part, a part per source
  file and the program's part. Each is compiled to an object cached under the cache directory
  (`FISH_CACHE_DIR`, else `~/.cache/fish`) by a hash of clang, target, flags and text, as the
  runtime's C and the `Math` objects are. A release build is one module, so `-O2` inlines
  across std and the program.
- **The check cache** (`checkcache.fsh`). A check's key covers the compiler binary, the entry,
  the flags and every file read. Today only an envelope is written under `checks/` in the cache
  directory: `--timings` notes a hit and the check still runs. `--no-check-cache` turns it off.

## 17. Diagnostics

`CompileError(code, message, start, end, note?)` in `diag.fsh` is the one user-facing error,
with at most one `note` (a second location with its own message). It is thrown where the
mistake is found and formatted once at the CLI boundary by `formatError`:

```text
m.fsh:5:15: error[E0201]: 'a.length' can't be used here because 'a' was moved
 5 |   console.log(a.length);
   |               ^^^^^^^^
m.fsh:4:8: note: 'a' moved here: passing it to 'keep' hands it over, as if 'keep' kept it; pass 'a.clone()' to keep a copy
 4 |   keep(a);
   |        ^
```

- `code` is from `codes.fsh`, numbered by area (`E00xx` syntax, `E01xx` types, `E02xx`
  ownership, `E03xx` async, `E04xx` names, `E05xx` calls and members, `E06xx` control flow and
  errors, `E07xx` classes, `E08xx` unsupported forms, `E09xx` modules and packages, `E10xx`
  interop, `E11xx` comptime and macros, `W0xxx` warnings). `fishc explain <code>` prints its
  title and, for common ones, a long explanation with a failing and a fixed program.
- Several errors from one build travel as one error whose `errors` holds them; it renders each,
  then `error: could not compile due to N previous errors`.
- `sources` and `names` are attached where the error leaves the compilation (`sourced`,
  `named`), so the renderer finds the file an offset is in and shows made-up names as written.
- Warnings (`warnings.fsh`) are `CompileError`s in `Checked.warnings`, rendered with kind
  `warning`. Any other exception (a clang failure, an `assert`) is an internal error.

## 18. Code map

Every file in `src/`. Generated files are marked.

- `analysis.fsh`: load, expand macros, link and check, as every compile starts; `analyze`
- `arenas.fsh`: the arenas of instances, bodies, locals and classes, and their ids
- `arithmetic.fsh`: lowering of integer operators with their overflow and division panics
- `ast.fsh`: generated; the `Ast` type declarations macros see
- `astgen.fsh`: the generator of `ast.fsh`
- `bundle.fsh`: bundling a program's npm packages into one module for the JS engine
- `casemap.fsh`: generated; JavaScript's case mapping tables for the C runtime
- `check.fsh`: `check`, the `Checker`, `BodyChecker`, declarations, statements, control flow
- `checkcache.fsh`: the key and envelope of a check cached on disk
- `classes.fsh`: `Body`, `ClassInfo`, class members, constructors, `extends`, overrides
- `codegen.fsh`: checked program to LLVM IR text
- `codes.fsh`: every error and warning code, its title and long explanation; `explain`
- `comments.fsh`: attaching comments to the tree for the formatter, as Prettier does
- `compilation.fsh`: `Session`, `Compilation`, `Tables`, timings
- `comptime.fsh`: the interpreter over the checked program
- `debuginfo.fsh`: DWARF line tables added to the IR for `-g`
- `declarations.fsh`: grammar of classes, decorators, enums, namespaces, `declare`, imports
- `defaults.fsh`: default parameter values lowered before checking
- `dependencies.fsh`: a program's Fish packages: resolving, fetching, the lockfile
- `deps.fsh`: a surveyed project's `package.json` dependencies sorted by what a port does
- `diag.fsh`: `CompileError`, notes, made-up names, `formatError`, `locate`
- `doc.fsh`: the formatter's document model and line breaking
- `edits.fsh`: what an edit to a file changed: which bodies, which signatures
- `enums.fsh`: C-like and data-carrying enum declarations
- `explain.fsh`: `fishc explain-borrows` output
- `expressions.fsh`: the expression grammar
- `flow.fsh`: whether control reaches the end of a body; which names a body assigns
- `fmt.fsh`: the `fishc fmt` command: files, `--check`, stdin
- `generics.fsh`: placeholders, inference, bounds, implicit parameters, instancing
- `git.fsh`: running git safely for packages and the registry
- `ids.fsh`: `Id`, `Ids`, `nextId`
- `incremental.fsh`: `Kept`, what a watch build keeps for the next
- `interfaces.fsh`: satisfying an interface by shape
- `js.fsh`: a `.d.ts` declaration turned into Fish declarations
- `js_native.fsh`: C glue between Fish and the vendored JS engine
- `keys.fsh`: computed property names known while compiling
- `layout.fsh`: LLVM types, named structs, conversions between representations
- `lexer.fsh`: `Token`, `Lexer`
- `locals.fsh`: local type, interface, enum and class declarations hoisted
- `lsp.fsh`: `fishc lsp`, the language server over stdio
- `macros.fsh`: macro expansion on declarations
- `main.fsh`: the CLI, `compile`, `build`, clang, linking
- `manifest.fsh`: `fish.toml` parsing and package scaffolding
- `match.fsh`: what patterns test and bind; exhaustiveness
- `mathlib.fsh`: the `Math` runtime, the cache directory, cached objects, `BuildSession`
- `migrate.fsh`: editions and the migration lint's rules and fixes
- `modules.fsh`: loading files, resolving specifiers, linking a program
- `moves.fsh`: the move and borrow check
- `narrow.fsh`: what a condition proves about a type
- `native.fsh`: the C half of the runtime, as text
- `navigate.fsh`: what the language server reads from a check
- `nodes.fsh`: node tables, `Rewrites`, `SiteTable`, walking, renumbering
- `openapi.fsh`: the OpenAPI document of a program's routes
- `operators.fsh`: which operators have a meaning and their types
- `overloads.fsh`: overload signatures lowered to functions
- `parseargs.fsh`: the lowering of std's `parseArgs` config literal
- `parser.fsh`: the AST types, `Cursor`, statements, entry points
- `patterns.fsh`: binding, assignment and `match` pattern grammar
- `printer.fsh`: the formatter's printer for every node
- `program.fsh`: `FILE_SPAN`, `fileAt`, what the checker shares with the loader
- `publish.fsh`: packing and submitting a package
- `queries.fsh`: the one path every check takes; reuse of a kept check
- `quote.fsh`: `quote` and `quoteType` templates parsed into `Ast` values
- `rank.fsh`: `fishc survey --rank`
- `rebuild.fsh`: generated; clone, id and rebuild helpers per node type
- `regex.fsh`: regex literals parsed while compiling, with JavaScript's early errors
- `registry.fsh`: every class the program uses: linking, layout, claims
- `registry_index.fsh`: the package registry's index and version resolution
- `resolve.fsh`: type annotations and aliases resolved to types
- `runtime.fsh`: IR declarations of the runtime; `Printer`
- `rust.fsh`: a compilation's Rust declarations
- `rustshim.fsh`: the generated cargo shim crate for Rust functions
- `semver.fsh`: versions and npm ranges
- `sizes.fsh`: a type's size and alignment
- `split.fsh`: a dev build's IR split into cacheable parts
- `std.fsh`: std as Fish source; `stdFor`, `STD_MODULES`
- `stdcache.fsh`: `cachedSession()`
- `suggest.fsh`: near-miss names for "cannot find" errors
- `survey.fsh`: `fishc survey`: rules, grade, Node built-ins
- `tar.fsh`: reading tar archives safely
- `target.fsh`: build targets and their clang flags
- `tests.fsh`: `test()` blocks stripped, lifted and run by a harness
- `typefns.fsh`: utility, conditional and mapped types
- `types.fsh`: the type grammar, parameters, type parameters
- `typing.fsh`: the type model
- `typings.fsh`: finding a package's declarations
- `unions.fsh`: what goes into a union and what comparing one means
- `unquote.fsh`: generated; an `Ast` value read back as a tree
- `unsupported.fsh`: names of forms with no meaning yet, and `unsupported(...)`
- `values.fsh`: expression checking in one body (`Expressions`)
- `walk.fsh`: generated; each node's children, tagged
- `warnings.fsh`: unused bindings and unreachable code
- `watch.fsh`: `fishc watch`

## 19. Conventions

- **One stage per file.** The parser spans files by grammar area and the checker by concern.
  A file starts with a comment saying what belongs in it; read it before adding to the file.
- **No visitors, no module state.** Branch on `kind` and walk with the generated walkers. State
  lives in the session, the compilation, the tables or a class.
- **Ids, not objects.** Tables key on ids, arena records hold each other's ids, and lowering
  records a replacement in `Rewrites` instead of editing a node.
- **Errors.** Anything the user got wrong is a `CompileError` with a code and a span, thrown
  where it is found. Messages are lowercase, quote source names in single quotes, and say what
  to do where they can. Fallible functions declare `throws` or a JSDoc `@throws`.
- **Naming.** camelCase functions and variables, PascalCase types, lowercase file names.
  Imports name the `.fsh` extension, and only std modules are imported, by their `node:` names.
- **Comments say why**, or state what a declaration is in a line or two. None restate the code.
- **Generated files** (`walk.fsh`, `rebuild.fsh`, `unquote.fsh`, `ast.fsh`, `casemap.fsh`) are
  changed by changing their generator and running it. A unit test fails when one is stale.
- **Deterministic output.** IR names come from content, never from counters that depend on what
  was compiled before, so two builds of one program give identical IR.
