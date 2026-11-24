#!/usr/bin/env bash
# UserPromptSubmit hook: notices Fish Lang work and points Claude at the `fish` skill.
#
# Reads the hook's JSON on stdin and may print additionalContext on stdout. Always exits 0 and
# prints nothing on any failure, so it can never block or garble a prompt.

set +e
INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$PROMPT" ] || exit 0
[ -d "$CWD" ] || CWD="$PWD"
LP="$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')"

# The fish shell shares the name. Its signals win: stay quiet.
printf '%s' "$LP" | grep -Eq 'config\.fish|\.fish\b|fish shell|fish_|fisher|oh-my-fish|funcsave|abbr -a' && exit 0

ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$ROOT" ] || ROOT="$CWD"
MANIFEST=""
[ -f "$ROOT/fish.toml" ] && MANIFEST="$ROOT/fish.toml"
[ -f "$CWD/fish.toml" ] && MANIFEST="$CWD/fish.toml"

# The compiler's own repository has its own instructions, and a nudge on every prompt there is
# noise. The compiler skill is still found by its description.
[ -n "$MANIFEST" ] && grep -Eq '^name *= *"fishc"' "$MANIFEST" && exit 0

HIT=0
printf '%s' "$LP" | grep -Eq '\.fsh\b|\bfishc\b|fish\.toml|fish\.lock|fish lang|fishlang|\bref<|\bmut<|\bshared<|to fish\b|in fish\b|fish (program|package|code|compiler|service|module)' && HIT=1
if [ "$HIT" -eq 0 ] && [ -n "$MANIFEST" ]; then
  printf '%s' "$LP" | grep -Eq '\b(function|class|type|module|compile|build|test|error|panic|borrow|moved|port|refactor|implement|fix|add|write)\b' && HIT=1
fi
[ "$HIT" -eq 1 ] || exit 0

if [ -n "$MANIFEST" ]; then
  CTX="[fish] This is a Fish Lang package (fish.toml present). Fish has TypeScript syntax and Rust ownership, and code written from TypeScript habit does not compile. Use the \`fish\` skill: it loads the compiler-checked knowledge pack and verifies code with fishc before claiming it works."
else
  CTX="[fish] This looks like Fish Lang work (.fsh, fishc). Fish has TypeScript syntax and Rust ownership, and is not the fish shell. Use the \`fish\` skill: it loads the compiler-checked knowledge pack and verifies code with fishc before claiming it works."
fi
jq -cn --arg ctx "$CTX" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}' 2>/dev/null
exit 0
