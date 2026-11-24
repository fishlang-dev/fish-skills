---
name: scaffold
description: Scaffolding capability of the fish agent - set up a new Fish Lang package or service with fishc new or fishc init, a correct fish.toml, a sensible layout, a first test and a verified build. Use for "start a new Fish project", "set up an HTTP service in Fish", "add Fish to this folder". Usually reached through the fish skill.
allowed-tools: Read, Grep, Glob
---

# Fish: scaffold

You set up the least that works and prove it builds. Pack: `${CLAUDE_PLUGIN_ROOT}/knowledge/`.
Load `toolchain.md` (packages and `fish.toml`), and `std.md` if the project serves HTTP.

## Protocol

1. **Check the toolchain.** `command -v fishc` and `clang --version` (15 or newer). If either is
   missing, say how to install it and stop: nothing below can be verified without them.
2. **Ask only what changes the layout:** a program or a library; if a program, a CLI or an HTTP
   service. Take the name from the folder unless told otherwise.
3. **Create it with the tool, not by hand.** `fishc new <name>` for a new folder, `fishc init` in
   an existing one. Read what it wrote before adding to it. Never run either in a folder that
   already has a `fish.toml`.
4. **Add the smallest real starting point:**
   - CLI: `main` reading `process.argv`, one function with the logic, one test of that function.
   - HTTP service: `serve` with a `Router`, a health route and one JSON route, state passed
     explicitly, a test that calls the handler. Take the shape from `std.md`'s worked example and
     `examples/router.fsh`, not from Express habits.
   - Library: a `lib` entry exporting one function, and its test.
5. **Dependencies only if asked.** `fishc add <name>` writes the manifest and the lockfile; don't
   edit versions by hand. For npm or Rust dependencies, load `interop.md` first.
6. **Verify.** `fishc check`, `fishc test`, `fishc build`, and run the binary once (for a service:
   start it on port 0 or a free port, request the health route, stop it). Paste the results.
7. **Report** the layout, the commands to build, run and test, and what was deliberately left out.

## Rules

- No framework, folder structure or config the user did not ask for.
- No dependency for something std does.
- Don't invent manifest keys: `toolchain.md` lists the ones the compiler reads.
