---
name: author
description: Authoring capability of the fish agent - write or change Fish Lang (.fsh) code, grounded in the compiler's own test programs and checked with fishc. Use when asked to write, add, implement or modify Fish code. Usually reached through the fish skill.
allowed-tools: Read, Grep, Glob
---

# Fish: author

You write Fish that compiles the first time because you looked first. Pack:
`${CLAUDE_PLUGIN_ROOT}/knowledge/`. Examples: `${CLAUDE_PLUGIN_ROOT}/examples/`.

## Protocol

1. **Pin the task.** What goes in, what comes out, what may fail, what is shared between tasks.
   For a change to existing code, read the code and its package's `fish.toml` first.
2. **Load.** `language.md` for the sections the task touches, `ownership.md` for anything that
   stores, shares or mutates, `std.md` for anything it calls. Skim `gotchas.md` headings.
3. **Retrieve.** Grep `examples/` for the feature and read one or two whole cases: how the
   compiler's tests write a `Router` handler, a `Channel`, a `match`, a generic class. Grep
   `std-api.md` for the exact signature of every std name you will call.
4. **Decide ownership before typing.** For each parameter: only read it (`Ref<T>`), change it
   (`Mut<T>`), or keep it (owned). For each field and return value: who owns it. State the choice
   in a line if it is not obvious. The decision guide is at the end of `ownership.md`.
5. **Write.** Match the surrounding code's style. In new code: `const` unless it is reassigned or
   mutated, explicit `throws` on anything that can fail, `match` over a tagged union, no `any`.
6. **Check, every time.** `fishc check <file>`, or `fishc check` in the package. Read each error
   whole, notes included: the note usually names the fix. A function body reports only its first
   error per run, so errors arrive in rounds: fix what is shown and check again. Look the code up
   in `errors.md` and the message in `gotchas.md` before guessing. Fix causes, not symptoms: a
   `.clone()` added only to quiet a move error is usually the wrong fix.
7. **Build and run.** A clean check is not a clean build: `check` does not run `comptime` code or
   top-level `const` initializers, and it skips `test()` bodies. So `fishc run <file>` (or
   `fishc build`) with an input that exercises the change, and `fishc test` in a package that has
   tests. Debug builds panic on integer overflow; that is the check working.
8. **Report.** What you wrote, the ownership choices that mattered, and the commands you ran with
   their results. Offer tests if there are none. Journal anything that surprised you.

## Rules

- No claim of "compiles" or "works" without the command and its result in this conversation, and
  "compiles" means it built, not only that it checked.
- A std name comes from `std-api.md` or `std.md`. Node and web APIs that are not there do not exist.
- If the compiler says a form is not supported yet (E0801), don't fight it: use the workaround in
  `gotchas.md` and say which form was avoided.
- Don't weaken types to pass the checker (`as`, `!`, `unknown`) where narrowing would do.
- Keep `unsafe` out of ordinary code. If the task needs it, load `interop.md` and say why.
