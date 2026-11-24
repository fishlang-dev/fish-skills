---
name: compiler
description: Compiler capability of the fish agent - work on the fishc compiler itself inside a checkout of fishlang-dev/fish - adding a language form, a std function or an error code, fixing a checker, borrow-analysis or codegen bug, or finding where something lives in the source. Use only when the working directory is the Fish compiler's repository.
allowed-tools: Read, Grep, Glob
---

# Fish: compiler

You change a self-hosted compiler: `fishc` is written in Fish and built by an earlier `fishc`.
That shapes everything. A full build takes about 25 minutes and the unit suite longer, so you read
and reason before you build, and you choose the cheapest check that can prove the change.

Pack: `${CLAUDE_PLUGIN_ROOT}/knowledge/compiler/`. Read `architecture.md` for where things live
and what the data looks like, and `workflows.md` for the procedure that matches the task. The
checkout's own instructions (its `CLAUDE.md` or `AGENTS.md`, when present) come first where they
differ: they are newer than this pack.

## Protocol

1. **Confirm where you are.** `fish.toml` names `fishc`, and `src/main.fsh` exists. Read the
   checkout's own agent instructions and follow its workflow and authority rules.
2. **Locate.** Use the code map in `architecture.md`, then Grep. Read the header comment of each
   file you will touch; the source explains its own invariants there.
3. **Find the tests first.** `tests/programs/<feature>.fsh` holds the cases for a feature. Read
   the neighbours of the case you will add. The expected error text is part of the contract.
4. **Follow the matching procedure in `workflows.md`:** a new form goes through every stage on
   its checklist; a std function has its place and its test; an error code has its table entry.
   Don't skip a stage because the first test passes: the checker rejects every form it has no
   meaning for, codegen's statement switch has no default, and its expression switch ends in an
   internal-error assert. A missing case is a failed build of `fishc` or a crash on the first
   program that uses the form.
5. **Check cheaply, then properly.** A changed test program can be run with the installed `fishc`
   only if the change is not needed to compile it; otherwise build once and run the goldens that
   name the feature (`<pattern>`), not the whole suite. Say which checks you ran and which you
   did not, and why.
6. **Crashes on the compiler's own source:** print the instance and the node before forming a
   theory. Keep the old path behind a switch until the two agree.
7. **Report** the change by stage, the commands run with results, and anything not verified.

## Rules

- Never edit generated source (`walk`, `rebuild`, `unquote`, `ast`, `casemap`): change the
  generator and regenerate.
- The source must compile with the pinned stage 0. A feature added today cannot be used in `src`
  until a release containing it is promoted.
- Nothing in the build, the tests or the bootstrap may run Bun or Node.
- Messages are lowercase, say what to do where they can, and are quoted exactly in tests.
- A build or suite that could not run is a blocker to state, not a pass to assume.
