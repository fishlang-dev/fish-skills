---
name: port
description: Porting capability of the fish agent - turn TypeScript (a file, a module or a project) into Fish Lang that compiles and behaves the same, using fishc survey and fishc lint, the pack's rewrite recipes, and the compiler as the judge. Use for "port/convert/migrate this TypeScript to Fish". Usually reached through the fish skill.
allowed-tools: Read, Grep, Glob
---

# Fish: port

You turn TypeScript into Fish without changing what it does. Most of a port is mechanical; the
part that needs thought is ownership, and that is where you slow down. Pack:
`${CLAUDE_PLUGIN_ROOT}/knowledge/`. Load `porting.md` first, all of it.

## Protocol

1. **Survey before promising anything.** `fishc survey <dir>` on the TypeScript. Read the grade,
   the rejected and unsupported rules, the dependencies and the Node built-ins. Tell the user what
   ports as is, what needs rewriting, and what cannot be ported yet, before changing a file. A
   reject (`eval`, a proxy, a prototype edit) is a design conversation, not a rewrite.
2. **Agree the scope and order.** Leaves first: files that import nothing local. The next step
   renames files in place, so work on a copy or on a clean git tree, and say which. Removing the
   TypeScript for good is the user's call.
3. **Mechanical pass.** `fishc lint <files.ts>` lists every hit; name the files, since a directory
   stands for its `.fsh` files only. `fishc lint --fix <files.ts>` applies the automatic rewrites
   and renames each `.ts` to `.fsh`, fixing the imports between them. Keep its output: once
   renamed, a file is in the native edition and the lint will not read it again. Every
   `/* fish: review */` it left marks a guessed `Ref` or `Mut`; the guesses are wrong when the
   parameter is stored or handed on to something that changes it. Check each, then remove it.
4. **Hand pass, by recipe.** Work through `porting.md`'s recipes for what the lint reported:
   absence, truthiness, `number`, dictionaries, shared mutable objects, callbacks, errors,
   promises. Decide each parameter's mode from how the body uses it.
5. **The check loop.** `fishc check <entry>.fsh`, again and again: file-level errors come first,
   then each function body shows one error per run. Expect top-level statements to move into
   `main`, a data `interface` to become a `type`, and `await` inside an expression to need a name. Look up each code in `errors.md` and
   `gotchas.md`. When two names changed one object in the TypeScript, don't reach for `.clone()`:
   a clone changes behaviour. Restructure, pass a `Mut`, or use `shared` if tasks share it.
6. **Prove it.** Run the original and the port on the same inputs and compare output and exit
   code. Port the tests too, or write a few (`fish:test`). Say what you compared.
7. **Report.** Files ported, behaviour that differs on purpose (integer overflow panics, value
   equality, lazy futures), what was left in TypeScript and why. Journal any recipe that was
   missing or wrong.

## Rules

- Same behaviour first, idiomatic Fish second. Offer the idiomatic rewrite as a follow-up.
- A port that compiles and was not run is not done.
- Don't paper over a refusal with `as`, `!` or `unknown`.
- If a dependency has no Fish counterpart, say so early; `interop.md` covers calling npm packages
  and what that costs.
