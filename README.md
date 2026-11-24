# fish-skills

Agent skills for [Fish Lang](https://github.com/fishlang-dev/fish): TypeScript syntax, Rust
ownership, native binaries.

Fish looks like TypeScript, so a coding agent writes it like TypeScript, and it doesn't compile:
values have one owner, there is no truthiness, `===` compares values, absence is an Option,
integers are `i64`, and functions say what they throw. This plugin gives the agent what it is
missing: a knowledge pack whose every example the compiler has checked, the compiler's own test
programs as an example bank, and skills that run `fishc` before claiming anything works.

## Install

In Claude Code:

```
/plugin marketplace add fishlang-dev/fish-skills
/plugin install fish@fish-skills
```

The skills expect `fishc` on `PATH` (and the clang it needs). The prompt hook needs `jq`; without
it the hook stays silent and the skills still work.

## Skills

| Skill | Use it to |
| --- | --- |
| `fish` | Start here. Routes to the others, answers questions from the pack. |
| `fish:author` | Write or change Fish code. |
| `fish:explain` | Explain code, a concept, or a compiler diagnostic. |
| `fish:port` | Turn TypeScript into Fish. |
| `fish:debug` | Fix a compile error, panic, leak or wrong output. |
| `fish:test` | Write and run tests. |
| `fish:scaffold` | Set up a new package or service. |
| `fish:audit` | Review Fish code, read-only. |
| `fish:compiler` | Work on `fishc` itself, in a checkout of the compiler. |
| `fish:sync` | Bring the pack up to date with a new release. |
| `fish:distill` | Fold what runs learned into lessons. |

A prompt that mentions `.fsh`, `fishc` or `fish.toml`, or any coding prompt inside a Fish package,
gets a one-line nudge toward the `fish` skill. Prompts about the fish shell don't.

## What is in the pack

`knowledge/` holds one slice per area: the language for TypeScript developers, ownership, types,
errors and async, comptime and macros, std, interop, the toolchain, porting, a symptom index, and
two slices on the compiler's source. `knowledge/README.md` says how slices are written.

Three things are generated from a compiler release by `scripts/sync.fsh` and never edited by hand:

- `knowledge/errors.md`: every error code with what `fishc explain` prints;
- `knowledge/std-api.md`: every declaration std gives a program;
- `examples/`: the compiler's test programs, thousands of small cases that each state what they
  print or how they fail.

`knowledge/VERSION` names the release all of it was checked against.

## How it stays true

Every Fish example in the pack is a whole program that says what the compiler must do with it,
and this runs the compiler on each one:

```
fishc run scripts/verify.fsh
```

An example that no longer behaves as it claims fails the run. After a new release:

```
fishc run scripts/sync.fsh -- report
fishc run scripts/sync.fsh -- pull
fishc run scripts/verify.fsh
```

and the `fish:sync` skill walks through rewriting what the release changed. Both scripts are Fish.
`sync.fsh` reads the compiler's source from `FISH_SRC`, or from a `fish` checkout beside this one.

## What the agent learns

After a run where the compiler surprised it, the agent appends a line to
`~/.claude/fish/learning/journal.md`. `fish:distill` turns repeated or corrected observations into
`lessons.md` beside it, which every later run reads first. That state is yours and stays on your
machine. If a lesson shows the pack is wrong, an issue or pull request here fixes it for everyone.

## Contributing

Fix a slice, add a checked example, run `fishc run scripts/verify.fsh -- knowledge/<slice>.md`,
and open a pull request. A claim the compiler can't be shown to support doesn't go in.

## License

MIT or Apache-2.0, at your option, as Fish itself is.
