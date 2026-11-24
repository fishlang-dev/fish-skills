---
name: audit
description: Review capability of the fish agent - read-only review of Fish Lang code for needless clones and wrong parameter modes, unsafe and FFI hazards, TypeScript habits that Fish makes costly or wrong, unhandled errors, task and lock misuse, and missing tests, with findings ranked by severity and each backed by evidence. Use for "review/audit this Fish code". Usually reached through the fish skill.
allowed-tools: Read, Grep, Glob
---

# Fish: audit

You review Fish code and change nothing. Pack: `${CLAUDE_PLUGIN_ROOT}/knowledge/`. Load
`ownership.md`, `gotchas.md`, and `interop.md` if the code has `unsafe`, `declare` or foreign
imports.

## Protocol

1. **Scope.** The files or package named. Run `fishc check` first: if it doesn't compile, that is
   the first finding and the rest may not be worth doing yet. Note `fishc lint` output too.
2. **Ownership pass.** For every function: does each parameter's mode match its use? An owned
   parameter that is only read forces callers to clone or give up their value. For every
   `.clone()`: is a second copy wanted, or was it added to quiet a move error? Clones in loops and
   of large collections first. For every `Rc` and `shared`: is the value really shared, or would a
   borrow do? `fishc explain-borrows <file>` shows each move and loan. A class holding something
   that must be released (a handle, a lock, a transaction) should release it in
   `[Symbol.dispose]()`, not in a `close()` callers can forget.
3. **Safety pass.** Every `unsafe` block: what invariant does it rely on, and is it stated and
   true? Pointer lifetimes across calls and awaits, lengths passed to C, strings crossing the
   boundary, who frees. Every `!`: can the value be absent on some path? Every `as` between
   integer types: can it truncate?
4. **Errors pass.** `throws` clauses that are wider than what is thrown; caught errors that are
   dropped; panics used for conditions a caller could handle; integer arithmetic on outside input
   that can overflow (a panic in debug builds, a wrap in release).
5. **Concurrency pass.** Spawned tasks nobody awaits (a `taskGroup` would own them); futures created and never awaited (they
   never run); a lock held across an `await`; shared state that one owner and a channel would
   serve better; unbounded queues.
6. **Habits pass.** TypeScript patterns that compile and cost: string building in a hot loop,
   objects copied where a borrow would do, `Dyn` where a type parameter would do, repeated
   `Map.get(k)!` where one lookup would do.
7. **Findings.** Each one: severity (High: wrong or unsafe; Medium: a real cost or a trap for the
   next change; Low: clarity), `file:line`, the code, why it matters, the fix. Confirm anything
   you can by compiling a small program or running the code. End with what is good and what was
   not looked at.

## Rules

- Read-only. Fixes are offered, and done through `fish:author` if the user says so.
- No finding without the line and a reason specific to this code. Style opinions are not findings.
- Don't report what `fishc check` would have refused: if it compiles, the borrow checker already
  ruled out use-after-free and data races in safe code. Spend the time on what it cannot see.
