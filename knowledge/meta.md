# Comptime, macros, decorators and derive

Everything Fish runs while compiling: `comptime` expressions, blocks and parameters, top-level
consts, tagged templates, `macro function`s applied as decorators, and `@derive`. TypeScript has
none of it, and Rust's `const fn`, `macro_rules!` and `#[derive]` are only loose guides. Type
operators are in `types.md`, `throws` in `errors-async.md`, `fishc test` in `toolchain.md`. Three
complete programs to adapt: the comptime lookup table in section 3, the declaration macro in
section 9, the derived JSON round trip in section 17. Checked against fishc 0.1.1.

## 1. What runs while compiling, and which command runs it

The compiler interprets your own checked Fish code in six places:

| Form | Runs |
| --- | --- |
| `const X = expr` at the top level, `static readonly` fields | once; the value is baked into the binary |
| `comptime expr` | once, where it is written |
| `comptime { ... }` | once, as a check; gives no value |
| an argument to a `comptime` parameter | per call site; one copy of the function per value |
| the text of `` tag`...` `` | once per template |
| `@name` on a declaration | the `macro function name`, on that declaration's syntax |

**Symptom**: `fishc check` passes, then `fishc build` or `fishc run` fails with `error[E1101]`.
**Why**: `check` runs macros and the arguments of comptime parameters, and nothing else. Top-level
consts, `comptime` expressions and blocks run only in a build. With `half(n)` returning `10 / n`,
the line `const H = half(0);` checks cleanly and fails the build with `error[E1101]: this comptime
code panicked: attempt to divide by zero`. **Fix**: build (or `fishc run`, `fishc test`) before
calling comptime code done. The checked refusals below pass the failing code as a comptime
argument, which `check` does evaluate.

## 2. `comptime` expressions

`comptime expr` runs `expr` now and puts its value in the program. It takes the whole expression
to its right (`comptime 1 + 2 * 3` is 7). The same function still runs at run time when called
without it.

```fsh
function squares(n: i64): i64[] {
  let out: i64[] = [];
  for (let i = 1; i <= n; i++) out.push(i * i);
  return out;
}
function main() {
  let table = comptime squares(4);
  table.push(25); // a baked value is an ordinary owned value
  console.log(table);                                              // expect: [ 1, 4, 9, 16, 25 ]
  console.log((comptime 1 + 2) * 3, comptime "abc".toUpperCase()); // expect: 9 ABC
}
```

What comes out: integers of every width, floats, bigints, booleans, strings, `null`, arrays,
tuples, objects, class instances, enum members with or without a payload, unions, `Map`, `Set` and
`Record` dictionaries. Anything else (a `Promise`, a socket) is E1102, section 3.

- `comptime` is a keyword only when an operand can start right after it. Before `(`, `[`, `-` or a
  template it reads as a name: `const xs = comptime [1, 2, 3];` is `error[E0401]: cannot find name
  'comptime'`. `comptime !x` and `comptime /re/` don't parse. Start with a name, a literal or
  `new`: write `comptime 0 - 1`, call a function that returns the array, or use a top-level const.
- A call that `throws` needs no `try` under `comptime`: an error it raises is a compile error, so
  none is left for run time.

## 3. Top-level consts are comptime (worked example: a lookup table)

Every top-level `const` is computed while compiling, with or without the word `comptime`, and read
from any function; consts may read each other in any order. A top-level `let` is refused (E0404).
Build a table with ordinary loops, hold it in a const, check it in a `comptime` block:

```fsh
function crcTable(): u32[] {
  let table: u32[] = [];
  for (let i: u32 = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) c = (c & 1) === 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    table.push(c);
  }
  return table;
}
const CRC = crcTable();
comptime {
  assert(CRC.length === 256, "the table has one entry per byte");
}
function crc32(bytes: Ref<u8[]>): u32 {
  let c: u32 = 0xFFFFFFFF;
  for (const b of bytes) c = CRC[((c ^ (b as u32)) & 0xFF) as usize] ^ (c >>> 8);
  return c ^ 0xFFFFFFFF;
}
function main() {
  console.log(CRC[1], CRC[255]);                             // expect: 1996959894 755167117
  console.log(crc32(new TextEncoder().encode("123456789"))); // expect: 3421780262
}
```

- **Symptom**: `const START = Date.now();`, `const HOME = process.env.HOME ?? "";` or
  `const ARGS = process.argv;` at the top level fails the build with E1101 (`'now' can't run while
  compiling: comptime code only computes values`). **Why**: TypeScript's module-level setup; here
  that line runs on the build machine. **Fix**: compute it in `main` and pass it down.
- A const is deeply constant. `M.set("b", 2)` on a top-level `Map` is `error[E0212]: 'set' changes
  its Map, so call it on a variable or a field`; assigning to one is E0207. Clone it into a `let`,
  or hold an `Atomic` or a `Lock` in the const: those are the globals a program may change.
- A cycle is E1101: `'A' needs its own value to compute its value: 'A' reads 'B', which reads 'A'`.
- A value that needs run-time work is `error[E1102]: 'Promise<TcpListener> throws IoError' can't
  be computed while compiling: comptime makes numbers, booleans, strings, and arrays, Maps, Sets,
  objects, instances, unions and enums of them`.

## 4. What comptime code may do

Comptime code is ordinary Fish, interpreted. It is pure computation, and in 0.1.1 the interpreter
covers much less of std than the runtime does. Macro bodies run under the same rules.

| Works | Refused by design | Not yet: `... isn't supported in comptime code yet` |
| --- | --- | --- |
| arithmetic with the run-time overflow and division panics, `as`, bit operators | `console.log`: `printing can't run while compiling` | array methods other than `push`, `pop`, `clone`: `map`, `filter`, `join`, `slice`, `sort`, `includes`, `reduce`, `find`, `at`, `concat` |
| `if`, loops, `for...of` over arrays, strings, Maps and Sets, `switch`, `match`, `\|>` | the clock: `Date.now()`, `new Date()`, `performance.now()` | arrow functions and closures: `a 'arrow' expression` |
| arrays by index, `length`, `push`, `pop`, spread, destructuring; tuples; objects | randomness: `Math.random`, `crypto.*`: `its value would be fixed into the program` | generators, so also `for (const [i, x] of xs.entries())` |
| `Map`, `Set`, `Record`: `get`, `set`, `has`, `delete`, `keys`, `values`, `entries` | files, sockets, `process.env`, `await`, async functions | `/re/.test(s)`, a string's `.clone()`, a `FixedArray` |
| strings: `split`, `slice`, `substring`, `indexOf`, `includes`, `startsWith`, `replace` and `replaceAll` with a string pattern, `padStart`, `repeat`, `trim`, case, `charCodeAt`, `String(x)`, templates | C, Rust and npm functions, `unsafe` | |
| classes, methods, getters, `Mut` parameters, `throw` with `try`/`catch`, `assert`, `new Date(ms)` | `Math.max`, `Math.floor`, `Math.sqrt`, `BigInt()`, `JSON.stringify`, `JSON.parse` | |

Limits per evaluation: 10,000,000 steps, calls 1000 deep, strings of 268,435,456 characters. A
panic, an uncaught error, a refusal or a limit is `error[E1101]` at the comptime site, with a note
at the line inside that caused it: `this comptime code took more than 10,000,000 steps; is there
a loop that never ends?`, `this comptime code nests calls more than 1000 deep; is there a
recursion that never ends?`, `this comptime code panicked: attempt to add with overflow`, `this
comptime code threw an error it didn't catch: IoError: no such table`.

**Symptom**: a comptime string comes out unchanged. **Why**: in 0.1.1 `s.replace(/o/g, "0")` under
comptime returns `s` as it was, with no error, while the same call at run time replaces.
**Fix**: keep regexes out of comptime code. More: `examples/comptime.fsh`.

## 5. `comptime` blocks

`comptime { ... }` is a statement that runs while compiling and leaves nothing in the program: a
build-time assertion, at the top level (section 3) or in a function (section 6). It reads
top-level consts and comptime parameters, never run-time variables, not even a local
`const y = 3` (E1101, `'y' is only known when the program runs, so comptime code can't read it`).
A failed `assert(cond, message)` reports `message` as the E1101 text; with no message it is
`assertion failed: ` and the condition as written. Control can't leave a block:
`comptime { return 5; }` is `error[E1102]: 'return' can't leave a comptime block, which runs while
compiling; give a value with a 'comptime' expression instead`; so are `break` and `continue`.

## 6. `comptime` parameters

A parameter marked `comptime` takes its argument while compiling. Each distinct value makes its
own compiled copy of the function, in which the parameter is a constant that comptime code in the
body may read. This is Fish's const generics, written as an ordinary parameter.

```fsh
const TIMES = 2;
function repeat(comptime n: i64, s: string): string {
  comptime {
    assert(n > 0, "repeat needs a count above 0, not " + String(n));
  }
  let out = "";
  for (let i = 0; i < n; i++) out += s;
  return out;
}
function scaled(comptime k: i64, x: i64): i64 {
  const offset = comptime k * 100; // computed once per value of k
  return x * k + offset;
}
function main() {
  console.log(repeat(3, "ab"), repeat(TIMES + 1, "x")); // expect: ababab xxx
  console.log(scaled(2, 5), scaled(3, 5));              // expect: 210 315
}
```

- **Type**: an integer, a boolean, a string, an enum member, a union of those, or `string[]`.
  Anything else, a float or an `i64[]` for instance, is E1102 (its message is in section 18).
- **Argument**: evaluated as comptime code without writing `comptime`: a literal, a top-level
  const or an element of one, another comptime parameter, or any call the interpreter can run. A
  local is not known, even a `const`:

```fsh
function rep(comptime n: i64): i64 { return n; }
function main() {
  const k = 3;
  console.log(rep(k));
}
// error: error[E1101]: 'k' is only known when the program runs, so comptime code can't read it
```

- **Where**: functions, methods, static methods and constructors, generic ones included, and
  across files. Not on closures, `async` functions or generators (E0801), accessors or a `From`
  wrapper (E1102), `declare`d C functions (E1002), nor with a default value (E0801). In the entry
  file `export function` is a C export and refuses one (E1003); in an imported file it is fine.
- Such a function can't be used as a value (E0801), and a class with such a method can't become
  a `Dyn` of an interface naming it (E1102: `it has a version per value and no one method a Dyn
  could call`). A rest parameter after a comptime one makes it a tag (section 7).
- Recursing with the same value reuses the copy; with a new value each time it is `error[E0113]:
  instantiating 'down' never ends: each instance needs another with a different comptime value`.
- **Symptom**: a body's `comptime` check fails and the error points inside the function, never at
  the call that passed the bad value. **Fix**: put the value in the assert's message, as above.

## 7. Comptime tagged templates

A tag is a top-level function whose first parameter is exactly
`comptime strings: TemplateStringsArray`, followed by one rest parameter for the values. The
template's text is known while compiling; only the values arrive at run time.
`TemplateStringsArray` is `string[]`, the cooked text; there is no `.raw`.

```fsh
function placeholders(parts: string[]): string {
  let text = parts[0];
  for (let i = 1; i < parts.length; i++) text += "$" + i + parts[i];
  return text;
}
function sql(comptime strings: TemplateStringsArray, ...values: string[]): string {
  comptime {
    for (const part of strings) assert(!part.includes(";"), "one statement per query: " + part);
  }
  const text = comptime placeholders(strings); // built once per template, from its text alone
  return `${text} [${values.length} params]`;
}
function main() {
  const name = "'; drop table users; --";
  console.log(sql`select * from users where name = ${name} and age > ${"30"}`);
  // expect: select * from users where name = $1 and age > $2 [2 params]
}
```

- The values' type is the rest parameter's: `string[]`, a union such as `(i64 | string)[]`, or
  `T[]` on a generic tag. A value of another type is the usual E0101.
- A tag returns any type, `void` included, and may be called directly: `sql(["a"], "x")`.
- A failed check reports at the tag's own comptime code, not at the template, so quote the
  offending text in the message.
- JavaScript's run-time tags don't exist. A first parameter without `comptime` is E1107, `'tag'
  can't be a tag: its first parameter has to be 'comptime strings: TemplateStringsArray', so the
  template's text is known while compiling`. A method or closure as a tag is `a tag has to be the
  name of a top-level function`; no rest parameter is `'pair' can't be a tag: a tag takes
  'comptime strings: TemplateStringsArray, ...values: T[]'`. More: `examples/tagged.fsh`.

## 8. Types and comptime

Comptime makes values, never types: there is no Zig-style `comptime T: type`, and a comptime
value can't be a type argument or a length. `FixedArray<i64, n>` with `n` a comptime parameter or
a top-level const is `error[E0116]: a FixedArray's length is a number written in place, like
'FixedArray<i64, 4>'`; a comptime parameter's name used as a type is E0105, `cannot find type`.
Compute types with the operators in `types.md`, or generate them with a macro (section 11).

## 9. Macros (worked example: a declaration macro)

A macro is a `macro function` that takes a declaration's syntax and returns the declarations that
replace it. It is applied by writing `@name` before a top-level `function`, `class`, `type`,
`interface` or `enum` (`export`ed, `async` and `abstract` ones too) and nowhere else:
`@name const X = 1` is `error[E0001]: expected a class, function, type, interface or enum after
decorators, found 'const'`. A macro is never called (E0503).

```fsh
macro function traced(input: AstStmt, prefix: string = "call"): AstStmt {
  assert(input.kind === "function", "@traced goes on a function, not a " + input.kind);
  let f = input;
  if (f.kind === "function") {
    const body = f.body.clone();
    if (body !== null) {
      const label: AstExpr = { kind: "string", value: `${prefix} ${f.name}`, start: 0, end: 0 };
      let next: AstStmt[] = [quote`console.log(${label});`];
      for (const s of body) next.push(s.clone());
      f.body = next;
    }
  }
  return f;
}
@traced function add(a: i64, b: i64): i64 { return a + b; }
@traced("enter") function greet(name: string): string { return "hi " + name; }
function main() {
  console.log(add(1, 2));   // expect: call add
                            // expect: 3
  console.log(greet("bo")); // expect: enter greet
                            // expect: hi bo
}
```

- **Signature**: the first parameter is the declaration, typed `AstStmt` (the one to use when
  reading its fields) or `Ast`; then any arguments (section 13). The return type is written, and
  is `Ast`, `AstStmt` or an array of either. No type parameters.
- **Returns**: functions, classes, type aliases, interfaces, enums, top-level `const`s, `comptime`
  blocks and `declare`s, each optionally `export`ed. `[input, extra]` keeps the original and adds
  to it; a changed `input` rewrites it. An expression is `error[E1103]: the macro 'bad' gave a
  'binary', but a macro gives declarations that can stand at the top level`.
- **The body is comptime code** (section 4): loops and `push`, no `.map`, no arrows, no printing.
  It may call ordinary functions and read its file's consts, but nothing a macro makes or changes
  (E1103, `a macro can't depend on an expansion`). It sees syntax only, never types.
- **Order**: decorators on one declaration apply nearest first: `@a @b function f` runs `b`, then
  `a` on what `b` gave. A decorator in a macro's output applies in a later round, 64 at most.
- **Errors**: a panic or a throw inside a macro is E1101 at the decorator, with a note in the
  macro. `assert` is the way to reject a misuse: it needs no `throws` and its message is the
  error, as `@traced class C {}` shows: `error[E1101]: @traced goes on a function, not a class`.
- **Symptom**: E0201 on a `return [input, extra]` whose `extra` quote splices `input.name`.
  **Why**: the array moves `input` first. **Fix**: read what you need into locals before it.

## 10. The `Ast` types

`Ast`, `AstStmt`, `AstExpr`, `AstType`, `AstPattern` and their parts are ordinary Fish union types,
in scope in every program, discriminated by `kind`; `Ast` is the union of those four. Every node
has `start` and `end` (source offsets, `i64`): write `0` for both on a node you build.

| Type | Kinds, and the fields you reach for |
| --- | --- |
| `AstStmt`, declarations | `"function"` (`name`, `params: AstParam[]`, `returnType: AstType \| null`, `body: AstStmt[] \| null`, `async`, `generator`, `typeParams`), `"class"` (`name: string \| null`, `members: AstClassMember[]`, `extends`, `implements`, `abstract`), `"typeAlias"` (`name`, `type`), `"interface"` (`name`, `members`), `"enum"` (`name`, `members` of `{ name, init, payload }`), `"let"` (`keyword`, `declarations` of `{ target, type, init }`), `"export"` (`body`), `"declare"`, `"comptime"`, `"import"` |
| `AstStmt`, statements | `"expr"` (`expr`), `"return"` (`value`), `"if"` (`cond`, `then`, `else`), `"while"`, `"doWhile"`, `"for"`, `"forOf"`, `"forIn"`, `"switch"`, `"try"`, `"throw"`, `"block"` (`body`), `"break"`, `"continue"`, `"labeled"`, `"empty"` |
| `AstClassMember` | `"field"` (`name`, `type`, `init`, `optional`), `"method"` (`name`, `params`, `returnType`, `body`), `"constructor"`, `"get"`, `"set"`, `"index"`, `"staticBlock"`; all carry `modifiers` and `decorators` |
| `AstParam` (no `kind`) | `pattern: AstPattern`, `type`, `optional`, `rest`, `default`, `comptime` |
| `AstExpr` | `"int"`, `"float"`, `"bool"`, `"string"` (each with `value`), `"null"`, `"regex"`, `"template"`, `"ident"` (`name`), `"member"` (`object`, `name`), `"index"`, `"call"` (`callee`, `args`), `"new"`, `"binary"` (`op`, `left`, `right`), `"unary"`, `"assign"`, `"conditional"`, `"array"` (`elements`), `"object"` (`props`), `"arrow"`, `"function"`, `"match"`, `"pipe"`, `"as"`, `"nonNull"`, `"spread"`, `"this"` |
| `AstType` | `"ref"` (`name`, `args`), `"array"` (`element`), `"tuple"`, `"object"`, `"function"`, `"union"` and `"intersection"` (`types`), `"literal"`, `"conditional"`, `"mapped"`, `"indexed"` |
| `AstPattern` | `"ident"` (`name`), `"object"`, `"array"`, `"default"`, `"wildcard"`, `"literal"`, `"variant"`, `"or"` |

A member's `name` is `string | AstExpr` (computed keys), so narrow it with
`typeof n === "string"`. Nodes are owned values: `const n = m.name;` in a loop over
`input.members` is `error[E0202]: 'm.name' can't be moved out of 'm', which only borrows it`.
Clone the node, then move fields out of your copy; `m.name.clone()` checks, then fails in the
interpreter (`the string method 'clone' isn't supported in comptime code yet`).

```fsh
macro function fieldNames(input: AstStmt): Ast[] {
  let list = quote`[]`;
  let fn = "fields";
  if (input.kind === "class" && list.kind === "array") {
    fn = `fieldsOf${input.name ?? ""}`;
    for (const m of input.members) {
      const member = m.clone();
      if (member.kind !== "field") continue;
      const n = member.name;
      if (typeof n === "string") list.elements.push({ kind: "string", value: n, start: 0, end: 0 });
    }
  }
  return [input, quote`function ${ident(fn)}(): string[] { return ${list}; }`];
}
@fieldNames class Point { x: i64 = 1; y: i64 = 2; label: string = "p"; }
function main() {
  console.log(fieldsOfPoint()); // expect: [ 'x', 'y', 'label' ]
}
```

A literal node is written as an object, `{ kind: "int", value: n, start: 0, end: 0 }`. For a node
with children, start from a quote (`` quote`[]` `` above) and fill it in. More: `examples/ast.fsh`.

## 11. `quote`, `quoteType` and `ident`

`` quote`...` `` parses Fish source into a node while compiling: one expression (`AstExpr`), or one
statement or declaration (`AstStmt`). `` quoteType`...` `` parses a type (`AstType`). `${x}`
splices another node, and what it takes depends on where it stands:

| The splice stands where | It takes |
| --- | --- |
| an expression goes | an `AstExpr` |
| a statement goes, as in `{ ${s}; return y; }` | one `AstStmt` |
| a type goes | an `AstType` |
| a name goes (function, class, type, field, method, parameter, variable, `this.${...}`) | an identifier node: `ident("name")` |

```fsh
macro function boxed(input: AstStmt): Ast[] {
  if (input.kind !== "typeAlias") return [input];
  const list = ident(input.name + "List");
  const first = ident("first" + input.name);
  const element = input.type.clone();
  const arr = quoteType`${element.clone()}[]`;
  return [input, quote`type ${list} = ${arr.clone()};`,
    quote`function ${first}(xs: Ref<${arr}>): ${element} | null { return xs.length > 0 ? xs[0] : null; }`];
}
@boxed type Id = i64;
function main() {
  const ids: IdList = [7, 8];
  console.log(firstId(ids)); // expect: 7
}
```

- A splice takes nodes, not values: `${5}` is `error[E0101]: a splice where an expression goes
  takes an 'AstExpr', not 'i64'`. Make a literal node. An `AstStmt[]` can't be spliced either:
  assign the list to `f.body`, as `traced` does.
- A splice moves its node. Using one twice is E0201; write `${e.clone()}` for all but the last.
- One quote holds one thing: `` quote`a; b;` `` is `error[E1105]: a quote holds one expression,
  statement or declaration, not 2`; bad text is `error[E1105]: this quote's text doesn't parse`.
- To add a member to a class, quote a throwaway class and take the member out:
  ``const k = quote`class X { get twice(): i64 { return this.n * 2; } }`;`` then
  `if (k.kind === "class") c.members.push(k.members[0].clone());`.
- A quote exists only while compiling. Reached at run time it panics: `a quote builds syntax
  while compiling, so it can't run in the program`.

## 12. Hygiene

Rust's rule, with one explicit escape. A quote holds three kinds of name:

1. **A name the quote declares** (a function, const, parameter or type parameter written plainly)
   is private to the expansion: its other quotes see it, the program can't see or clash with it.
2. **A name made with `ident("name")`** is as if written in the using program: the program can
   call it, and it can refer to the program's own declarations.
3. **A free name** (used, not declared) means what it means in the file that defines the macro:
   that file's declarations and imports, private ones included. The using file needn't import
   them, and its own declarations of the same name are not picked.

```fsh
function helper(): i64 { return 1; }
macro function counted(input: AstStmt): Ast[] {
  return [
    input,
    quote`function helper(): i64 { const total = 40; return total; }`,
    quote`function ${ident("answer")}(): i64 { return helper() + 2; }`,
  ];
}
@counted function items() {}
function main() {
  const total = 5;
  console.log(answer(), helper(), total); // expect: 42 1 5
}
```

The quoted `helper` is the expansion's own; `main` still calls the program's. A declaration the
program should use must be named with `ident`: calling a plainly quoted `function secret()` is
`error[E0401]: unknown function 'secret'`. Syntax spliced in from the program keeps the program's
meaning, and an `ident(...)` binding can capture it. A free name that exists nowhere is reported
at the quote (E0401); an `ident` name the program already has is E0402, `'f' is already defined`.

## 13. Macro arguments, members and parameters

`@name(args)` passes arguments after the declaration (`@traced("enter")` in section 9). A
parameter typed as a value (`i64`, `usize`, `u8`, `string`, `boolean`, `string[]`) gets the
argument's value, computed while compiling, so `@times(BASE + 1)` may read a top-level const. One
typed `AstExpr` gets the argument's syntax, which must still check as an expression where the
decorator stands. Parameters may be optional or defaulted; object-typed ones are E1103. A wrong
argument is `this argument is a 'i64', but the macro takes a 'string' here`.

On a class member, or on a parameter of a top-level function, the macro also takes an index,
`(input: AstStmt, member: usize)` or `(input: AstStmt, param: usize)`: `input` is the whole class
or function, `input.members[member]` or `input.params[param]` the decorated part, and the macro
gives the class or function back. Fields (static and `#private` too), methods, accessors and the
constructor take member macros, in a top-level class only. Without the index parameter:
`error[E1103]: a macro on a member takes the class and the member's index`. Decorators on method
and constructor parameters are E0801. Worked: `macro_members_and_params` in `examples/macro.fsh`.

## 14. Macros across files and packages

`export macro function` is imported by name like any function, from a file
(`import { described } from "./macros.fsh"`) or from a package's `lib`. The expansion lands in the
using file, and its free names still mean the macro file's: if `macros.fsh` and `main.fsh` each
declare a private `fmt()`, a quote in `macros.fsh` that calls `fmt()` calls the one in
`macros.fsh`. A quote in a helper function of a third file pins that file's names the same way.
A declaration returned as `` quote`export function ${ident("made")}() {}` `` is importable from
the file the macro was applied in. `import.meta` in a quote is E1105. More: the
`examples/macro_def_site`, `macro_pin_import` and `macro_exported` directories.

## 15. Decorators

A decorator is a macro application and nothing else. `@name` and `@name(args)` are the only forms:
no run-time decorator functions, no metadata, no `@ns.member` (`error[E1104]: a decorator names a
macro, as in '@name' or '@name(args)'`). TypeScript's decorator syntax all parses
(`examples/decorators.fsh` is parse-only), but a ported Angular or Nest class stops at the check:

```fsh
@Component({ selector: "app" })
class App {}
// error: error[E1104]: 'Component' isn't a macro; a decorator applies a 'macro function Component(input: Ast): Ast'
```

**Fix**: write the macro, or delete the decorator and say in code what it did. Class expressions,
decorated or not, are E0801. `@derive` is the one built-in decorator; it stacks with macros in
either order (`@keep @derive(Eq) class P`), and a `macro function derive` of your own replaces it.

## 16. `@derive(Eq)`

`===` and `!==` compare by value. Plain data already does: numbers, strings, arrays, tuples, object
types, C-like enums, and unions of them need nothing. A class or an enum with payloads is refused
until it says how: `new Point() === new Point()` on a bare class is `error[E0112]: values of type
'Point' can't be compared with '===': a class compares through 'equals(other: Ref<this>):
boolean', which 'Point' doesn't have; add one, or '@derive(Eq)'`. `@derive(Eq)` on a class writes
that `equals`, comparing every field in turn, `#private` and inherited ones included; on an enum
it compares the member and its payload.

```fsh
@derive(Eq)
class Point { constructor(public x: i64, public y: i64) {} }
@derive(Eq)
enum Cmd { Move(i64, i64), Stop }
type Line = { from: Point; to: Point };
function main() {
  const a: Line = { from: new Point(0, 0), to: new Point(1, 2) };
  const b: Line = { from: new Point(0, 0), to: new Point(1, 2) };
  const stop: Cmd = Cmd.Stop;
  console.log(a === b, a.to.equals(new Point(1, 3)), a.to !== b.to);       // expect: true false false
  console.log(Cmd.Move(1, 2) === Cmd.Move(1, 2), stop === Cmd.Move(0, 0)); // expect: true false
}
```

- A hand-written `equals(other: Ref<this>): boolean` wins over the derive; another shape is E0702.
- Every field must itself compare: a `Map`, `Set` or function field is E0112 at the `@derive`
  (`a Map isn't compared by value`), and a derived class's base needs `equals` too. Floats compare
  as floats: an instance holding `NaN` is unequal to itself.
- Not unlocked by it in 0.1.1: `xs.includes(p)` on an array of instances (E0112, use `some`), and
  instances as `Map` keys (E0116).
- `@derive(Hash)` is `error[E1104]: 'derive' knows 'Eq' and 'Json' so far; 'Hash' isn't one it
  can derive yet`; on a function, alias or interface, `'derive' applies to a class or an enum`.

## 17. `@derive(Json)` and JSON (worked example: a round trip)

`JSON.stringify(value)` and `JSON.parse<T>(text)` are generated per type while compiling: no
reflection, no `any`, no `toJSON`. Plain data needs no derive; a class, or an enum with payloads,
needs `@derive(Json)`.

| Fish type | JSON |
| --- | --- |
| integers, floats | number; `NaN` and infinities write `null`; a `u64` keeps every digit |
| `string`, `boolean`, `null` | the same |
| `T[]`, tuples, typed arrays | array |
| object type `{ ... }` | object, keys in name order, not as declared |
| class with `@derive(Json)` | object, fields as declared, a base's first; `#private` fields left out |
| optional field `a?: T` | left out when empty |
| `T \| null` | the value or `null` |
| union | whichever member it holds; read back by finding the member that fits |
| C-like enum (`enum E { A, B }`, or `A = "a"`) | its value, `0` or `"a"`, derive or not |
| enum with payloads, derived | `"Stop"`, `{"Say":"hi"}`, `{"Move":[1,2]}` |
| `Map<string, T>`, `Record<string, T>` | object, in insertion order |
| `Set`, `Map` with other keys, `bigint`, `Date`, functions, underived classes | E0509 |

```fsh
@derive(Json, Eq)
enum Status { Active, Suspended(string) }
type Shape = { kind: "circle"; r: f64 } | { kind: "rect"; w: i64; h: i64 };
@derive(Json, Eq)
class Address { constructor(public city: string, public zip: string) {} }
@derive(Json, Eq)
class User {
  nickname?: string;
  constructor(public id: i64, public tags: string[], public home: Address, public status: Status, public logo: Shape) {}
}
function load(text: string): User | null {
  try {
    return JSON.parse<User>(text);
  } catch (e) {
    console.log("bad user:", e.message);
    return null;
  }
}
function main() {
  const ann = new User(7, ["admin"], new Address("Oslo", "0150"), Status.Suspended("unpaid"), { kind: "rect", w: 2, h: 3 });
  const text = JSON.stringify(ann);
  console.log(text);
  // expect: {"id":7,"tags":["admin"],"home":{"city":"Oslo","zip":"0150"},"status":{"Suspended":"unpaid"},"logo":{"h":3,"kind":"rect","w":2}}
  const back = load(text);
  console.log(back !== null && back === ann); // expect: true
  load("{\"id\":\"7\"}");                       // expect: bad user: expected i64 at $.id
  load("{\"id\":7,\"tags\":[],\"home\":{\"city\":\"Rome\"}}"); // expect: bad user: missing field 'zip' at $.home
  load("{\"id\":7,");                           // expect: bad user: Unexpected end of JSON input
}
```

`JSON.parse` throws `JsonError`, so it stands in a `try` or in a function declaring
`throws JsonError` (otherwise E0602). Its `message` says what was expected and where:

| Input problem | `e.message` |
| --- | --- |
| not JSON | `Unexpected token } in JSON at position 16`, `Unexpected end of JSON input` |
| wrong kind | `expected i64 at $.x`, `expected string at $.tags[2]`, `expected object at $` |
| missing field | `missing field 'y' at $` |
| number out of range or fractional | `256 doesn't fit u8 at $`, `1.5 doesn't fit i64 at $.x` |
| no union member fits | `expected i64 \| string at $.n`, `expected "a" \| "b" at $.f` |
| bad enum or tuple | `expected one of Move, Say, Stop at $[0]`, `expected Plain at $`, `expected an array of 2 at $` |

Unknown keys are ignored and a repeated key keeps its last value. A missing optional field and a
missing `T | null` field both read as `null`. Reading a class fills its fields directly: the
constructor does not run, field initializers are not defaults (a missing one is `missing field`),
`private` fields are read and written like any other, a class with `#private` fields can't be
read at all (E0509), and generic classes derive too: `JSON.parse<Box<i64[]>>(text)`.

`JSON.parse(text)` with no type argument gives `Json`, the dynamic tree
`null | boolean | number | string | Json[] | Map<string, Json>`, narrowed with `=== null`,
`typeof`, `Array.isArray` and `instanceof Map`:

```fsh
function describe(v: Ref<Json>): string {
  if (v === null) return "null";
  if (typeof v === "boolean") return v ? "yes" : "no";
  if (typeof v === "number") return String(v);
  if (typeof v === "string") return "'" + v + "'";
  if (Array.isArray(v)) return `array of ${v.length}`;
  let keys: string[] = [];
  for (const [k, x] of v) keys.push(k + "=" + describe(x));
  return "{" + keys.join(" ") + "}";
}
function main(): void throws JsonError {
  const v = JSON.parse("{\"name\": \"ann\", \"tags\": [\"x\", 2], \"age\": 1.5}");
  console.log(describe(v)); // expect: {name='ann' tags=array of 2 age=1.5}
}
```

`JSON.stringify(value, null, 2)` is E0801 (`replacer and indent arguments are not supported yet`).
HTTP uses the same machinery, `await req.json<T>()` and `Response.json(value)`. More: `examples/json.fsh`.

## 18. The E11xx codes

`fishc explain` has no longer text for these; the message is the explanation.

| Code | Title | Messages | Fix |
| --- | --- | --- | --- |
| E1101 | comptime code that failed while compiling | `this comptime code panicked: ...`, `... threw an error it didn't catch: ...`, `... took more than 10,000,000 steps ...`, `... nests calls more than 1000 deep ...`, `'k' is only known when the program runs, so comptime code can't read it`, `printing can't run while compiling: ...`, `calling 'map' here isn't supported in comptime code yet`, or a failed `assert`'s own message | read the note for the line inside; keep comptime code to the left column of section 4; do run-time work at run time |
| E1102 | invalid comptime parameter or block | `a comptime parameter takes an integer, a boolean, a string, an enum member or a string array, not 'T'`, `'return' can't leave a comptime block ...`, `'T' can't be computed while compiling: ...`, `an accessor can't take a comptime parameter` | an allowed parameter type; a `comptime` expression to give a value; build run-time values in `main` |
| E1103 | invalid macro | `a macro's parameter takes the declaration it is applied to, so its type is 'Ast' or 'AstStmt'`, `a macro gives the declarations it makes, as an 'Ast' or an 'Ast[]', not 'i64'`, `a macro takes no type parameters`, `the macro 'm' gave a 'binary', but ...`, `the macro 'two' takes 1 argument after what it is applied to, but this gives 0`, `a macro applies to a top-level declaration`, `the macro 'm' uses 'made', which a macro makes or changes; a macro can't depend on an expansion`, `macros gave declarations using macros 64 rounds deep ...` | the shape `macro function m(input: AstStmt, ...): Ast[]`; return declarations; keep what a macro calls free of decorators |
| E1104 | invalid decorator or derive | `'nope' isn't a macro; a decorator applies a 'macro function nope(input: Ast): Ast'`, `a decorator names a macro, as in '@name' or '@name(args)'`, `'derive' knows 'Eq' and 'Json' so far; ...`, `'derive' applies to a class or an enum`, `'derive' names what to derive, as in '@derive(Eq)'`, `a macro took away what these decorators were waiting to apply to` | declare or import the macro; derive only `Eq` and `Json`, on classes and enums |
| E1105 | invalid quote | `this quote's text doesn't parse: ...`, `a quote holds one expression, statement or declaration, not 2`, `a quote takes no type arguments`, `an Ast holds an integer as an 'i64', which can't hold ...`, `'import.meta' in a quote isn't supported yet: ...` | one construct per quote; splice the rest |
| E1106 | invalid test | `a test is written as 'test("name", () => { ... })' at the top level of a file, its name a string literal, ...`, `a test's name is one line, so it can't hold a line break` | `toolchain.md` |
| E1107 | invalid tagged template | `'t' can't be a tag: its first parameter has to be 'comptime strings: TemplateStringsArray', ...`, `'pair' can't be a tag: a tag takes 'comptime strings: TemplateStringsArray, ...values: T[]'`, `a tag has to be the name of a top-level function; ...` | section 7's signature, on a top-level function |
