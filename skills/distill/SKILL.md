---
name: distill
description: Maintenance capability of the fish agent - fold the raw learning journal (~/.claude/fish/learning/journal.md) into curated lessons (lessons.md), and factual corrections into the knowledge pack when working in a fish-skills checkout. Use when the journal has grown, or for "distill the Fish lessons".
allowed-tools: Read, Grep, Glob
---

# Fish: distill

The journal is raw: one line per surprise. Lessons are what every later run reads first, so each
one has to earn its place. A wrong lesson is worse than none.

Files, in `~/.claude/fish/learning/`: `journal.md` (raw), `lessons.md` (curated),
`journal.archive.md` (processed entries).

## Protocol

1. **Read** `journal.md` and `lessons.md` in full.
2. **Sort each journal entry:**
   - **Promote:** it happened more than once, or it corrected the pack, or the user said it.
   - **Already covered:** a lesson or a slice says it. Drop it.
   - **One-off:** specific to one project or one moment. Drop it.
3. **Verify before promoting.** Write the smallest program that shows the claim and run `fishc` on
   it. If the compiler does not agree, the entry was wrong: drop it, and if a lesson says the
   same wrong thing, remove that too.
4. **Write lessons.** One per heading, updating an existing lesson rather than adding a near
   duplicate:

       ## Passing an array to a std function moves it
       **When it applies:** calling a std function with a collection you use afterwards.
       Take what you need from it first, or pass a clone. Checked on fishc 0.1.3.

   Name the fishc release each lesson was checked on. A lesson about a refusal goes stale when the
   compiler learns the form.
5. **Corrections to the pack.** If an entry shows a slice is wrong and you are in a checkout of
   `fish-skills`, fix the slice with a checked example and run
   `fishc run scripts/verify.fsh -- knowledge/<slice>.md`. Otherwise keep it as a lesson and tell
   the user it is worth reporting to the plugin's repository.
6. **Archive.** Only after the lessons are written: move the processed entries under a
   `## Distilled <date>` heading in `journal.archive.md` and leave `journal.md` with its header.
7. **Report** what was promoted, what was dropped and why, in a few lines.

## Rules

- Three verified lessons beat ten padded ones.
- Remove lessons the current release has made untrue.
- Lessons are about Fish and how to work with it, never about one user's project.
