---
name: debug
description: Debugging capability of the fish agent - diagnose and fix a Fish Lang compile error (ownership, borrow, type, throws), a runtime panic, a leak, a data race or wrong output, using fishc explain, the pack's symptom index and the compiler's leak and sanitizer builds. Use when Fish code fails to compile or misbehaves. Usually reached through the fish skill.
allowed-tools: Read, Grep, Glob
---

# Fish: debug

You find the cause before you change anything. Pack: `${CLAUDE_PLUGIN_ROOT}/knowledge/`.

## Protocol

1. **Reproduce.** Run the exact command and keep the whole output. For a compile error:
   `fishc check <file>`. For a panic or wrong output: `fishc run <file> -- <args>`.
2. **Read the whole diagnostic.** The first error, its code, its span, and every `note:` under it.
   A note on a move says where the value went; a note on a borrow says what still holds it. Later
   errors are often consequences of the first: fix one, check again.
3. **Look it up.** Grep `gotchas.md` for the message text, read the code's entry in `errors.md`
   (or `fishc explain <code>`), then the slice for the area:
   - E02xx: `ownership.md`. Run `fishc explain-borrows <file> --fn <name>` to see every move and
     loan in the function, then say in one sentence who owns the value and who wanted it.
   - E01xx, E05xx, E07xx: `types.md`.
   - E03xx, E06xx: `errors-async.md`.
   - E0801 / E0802: the form is not supported, or left out; `gotchas.md` lists the workaround.
   - E09xx: `toolchain.md`. E10xx: `interop.md`. E11xx: `meta.md`.
4. **Name the cause, then choose the smallest fix that keeps the meaning.** In order of
   preference for ownership errors: use the value through its new owner; borrow (`Ref`/`Mut`
   parameter); reorder so the borrow ends first; restructure who owns it; `.clone()` when a second
   copy really is wanted; `Rc` or `shared` when it really is shared.
5. **Runtime failures.**
   - Panic: the message names the file, line and reason (`attempt to add with overflow`, an index
     out of range, `!` on an absent value). Build with `-g` for a backtrace.
   - Leak or growth: `fishc run <file> --leaks` reports what was still allocated at exit.
   - Builds fail after a clean check: `check` does not run `comptime` code or top-level `const`
     initializers (E1101), and only `fishc test` compiles test bodies.
   - Memory error in `unsafe` or C: `fishc build --sanitize address`. Race: `--sanitize thread`.
   - Nothing happens in async code: futures are lazy; an un-awaited call never ran.
6. **Prove the fix.** The same command as step 1 now passes, and the tests still do.
7. **Report** the cause in one sentence, the fix, and the commands with results. Journal the
   symptom if `gotchas.md` did not have it.

## Rules

- Don't change code you haven't run. Don't stack fixes: one change, one check.
- A fix that silences the checker and changes behaviour (a clone of something meant to be shared,
  an `as` over a real mismatch) is not a fix. Say what the trade is if you must make one.
- A crash inside `fishc` itself (an internal error, not a diagnostic) is a compiler bug: reduce it
  to the smallest program that still crashes and report that, with the fishc release.
