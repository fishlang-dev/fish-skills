---
name: test
description: Testing capability of the fish agent - write and run tests for Fish Lang code with fishc test and test() blocks, including async tests and tests that expect a panic or a thrown error. Use when asked to add, write, fix or run Fish tests. Usually reached through the fish skill.
allowed-tools: Read, Grep, Glob
---

# Fish: test

You write tests that would fail if the code were wrong. Pack: `${CLAUDE_PLUGIN_ROOT}/knowledge/`.
Load the tests section of `toolchain.md` first; it has the exact shape of a `test()` block, where
test files go, and what `fishc test` prints.

## Protocol

1. **Read the code under test** and decide what is worth asserting: pure logic with real edge
   cases (empty, absent, malformed, boundary integers, overflow), every `throws` path, every arm
   of a `match`. Skip what the type checker already proves.
2. **Retrieve.** Grep `${CLAUDE_PLUGIN_ROOT}/examples/tests.fsh` and the package's existing tests
   for the house style. Match it.
3. **Write.** One behaviour per test, named for the behaviour. Arrange with owned values the test
   builds itself; a helper that takes `Ref<T>` keeps a fixture usable after the call. For a
   function that throws, assert both the success and the error. For async code, the test is
   `async` and awaits; remember an un-awaited future never runs.
4. **Run.** `fishc test`, or `fishc test <filter>` for the ones you touched; it works only inside
   a package. It is also the only command that compiles test bodies: `fishc check` and
   `fishc build` skip them, so a type error in a test shows up here and nowhere else. Paste the
   summary.
5. **Make sure it can fail.** Break the code under test in one place (or flip the assertion), see
   the test fail with a useful message, and put it back. A test you have not seen fail proves
   little.
6. **Report** what is covered, what is not and why, and the command with its result.

## Rules

- Never weaken an assertion to make a test pass. If the code is wrong, say so and hand it to
  `fish:debug`.
- No sleeping to wait for async work; await the handle, the channel or the promise.
- Tests clean up what they create (temp files, servers on port 0).
- An empty test run is a failure, not a pass.
