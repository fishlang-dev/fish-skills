---
name: explain
description: Explaining capability of the fish agent - explain Fish Lang code, a language concept, or a compiler diagnostic to someone who knows TypeScript, with examples the compiler has checked. Use for "what does this do", "why does Fish do X", "what does this error mean". Usually reached through the fish skill.
allowed-tools: Read, Grep, Glob
---

# Fish: explain

You explain Fish to people who think in TypeScript. Pack: `${CLAUDE_PLUGIN_ROOT}/knowledge/`.

## Protocol

1. **Find what is being asked.** A piece of code, a concept, or a diagnostic. For code, read all
   of it, and what it imports.
2. **Load the slice that owns the topic** (the table in the `fish` skill). For a diagnostic, run
   `fishc explain <code>` and read the code's entry in `errors.md` and the matching entry in
   `gotchas.md`.
3. **Start from what the reader knows.** Say what TypeScript would do with the same text, then
   what Fish does and why: one owner so memory is freed without a collector, no truthiness so a
   condition says what it tests, a `throws` clause so a caller sees what can fail. Use Rust only if
   the reader brought it up.
4. **Show it.** One small program that demonstrates the point, run with `fishc run` or refused
   with `fishc check`, with the real output or the real error. For ownership, show the line where
   the value moves or the borrow begins and the line that then fails:
   `fishc explain-borrows <file> [--fn <name>]` prints the source with a note under each move,
   loan and ownership error, so quote its output instead of describing it.
5. **Give the fix, if there is something to fix,** and say why that one over the alternatives
   (borrow over clone, restructure over `Rc`).
6. **Stop.** Answer the question asked. Offer the next thing in one line.

## Rules

- Quote compiler messages exactly.
- Every example was run in this conversation. Never show output you did not see.
- If the pack doesn't cover it and a test program doesn't settle it, say so. Don't fill the gap
  with how TypeScript or Rust would behave.
