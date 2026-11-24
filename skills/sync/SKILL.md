---
name: sync
description: Maintenance capability of the fish agent - bring the Fish Lang knowledge pack up to date with a new fishc release, in a checkout of fishlang-dev/fish-skills - regenerate the mechanical slices, re-check every example, and rewrite what the release changed. Use when the installed fishc is newer than the pack, or for "sync/refresh the Fish knowledge".
allowed-tools: Read, Grep, Glob
---

# Fish: sync

The mechanical half is scripted. The judgement, what changed and what the slices should now say,
is yours. This skill works in a checkout of the `fish-skills` repository with the compiler's
source beside it (or at `FISH_SRC`); an installed copy of the plugin is read-only.

## Protocol

1. **Assess.** `fishc run scripts/sync.fsh -- report`. No drift: stop. Don't churn files.
2. **Install the release being synced to**, so the `fishc` on PATH is that release. The scripts
   refuse to pull otherwise, since its `fishc explain` is what gets written.
3. **Pull.** `fishc run scripts/sync.fsh -- pull [<tag>]` rewrites `errors.md`, `std-api.md`,
   `examples/` and `VERSION`. Review `git diff --stat`: new error codes, new std declarations and
   new or changed example files are the list of what the release changed.
4. **Re-check everything.** `fishc run scripts/verify.fsh`. Every failure is a place where the
   language moved: an example that no longer compiles, a message that was reworded, a refusal
   that became support. Fix the claim, not just the example.
5. **Promote what shipped.** Each slice's "Not released yet" section: test every item with the new
   compiler. What now works moves into the body with a checked example; what still doesn't stays.
6. **Cover what is new.** For each new feature in the diff (a new example file, a new std module,
   a new code), add it to the slice that owns the area, with a checked example taken from running
   the compiler, in the style `knowledge/README.md` sets. Update `gotchas.md` for forms that are
   no longer refused. The `compiler/` slices follow the source's main line: re-read the code map
   against `src/` and fix what moved.
7. **Verify again**, then read the diff of each slice as its reader would.
8. **Record.** Bump the plugin version in `.claude-plugin/plugin.json`. Journal what the release
   changed that the pack had wrong. Commit only if asked.

## Rules

- Generated files are never edited by hand.
- A slice says only what the compiler was seen to do. If a change can't be shown, leave it out.
- Keep each slice inside its scope and its length; move material rather than letting one grow.
- No plan numbers, roadmap phases, issue ids or machine paths in anything committed.
