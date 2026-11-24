// Checks every Fish example in the knowledge pack against the compiler.
//   fishc run scripts/verify.fsh -- [--fishc <path>] [<file.md>...]
//
// A fenced block opened with ```fsh is a whole program, and its comments say what the compiler
// must do with it, in the directives the compiler's own test programs use:
//   // error: <text>   compilation must fail with a message containing <text>
//   // expect: <line>  the next line of stdout, in order; the program is built and run
//   // panic: <text>   the program must exit with 101 and stderr containing <text>
//   // mode: release   build with --release before running
// A block stating none of them must check cleanly, and one with no main() is given an empty one, so
// a block of declarations stands on its own. A block opened with ```fsh fragment is part of
// a program and isn't checked; the count of those is printed so it stays small.
//
// The fishc is `--fishc`, else FISHC, else `fishc` on PATH. With no files, every .md under
// knowledge/ is read. Each failure is printed as it is found, and the run exits 1 if any failed.
import { spawnSyncText } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

type Block = { file: string; line: usize; kind: string; src: string };

function directive(src: string, key: string): string[] {
  const marker = `// ${key}: `;
  let found: string[] = [];
  for (const line of src.split("\n")) {
    const at = line.indexOf(marker);
    if (at >= 0) found.push(line.slice(at + (marker.length as i64)).trim());
  }
  return found;
}

function blocksOf(file: string): Block[] throws IoError {
  let out: Block[] = [];
  const lines = readFileSync(file, "utf8").split("\n");
  let open = false;
  let kind = "";
  let start: usize = 0;
  let body: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;
    if (!open && line.startsWith("```fsh")) {
      open = true;
      kind = line.slice(6).trim();
      start = i + 1;
      body = [];
    } else if (open && line.startsWith("```")) {
      out.push({ file, line: start, kind, src: body.join("\n") + "\n" });
      open = false;
    } else if (open) body.push(line);
  }
  return out;
}

// What is wrong with a block, or "" when the compiler does with it what its comments say.
function verdict(fishc: string, path: string, src: string): string throws IoError {
  writeFileSync(path, src.includes("function main(") ? src : src + "function main() {}\n");
  const errors = directive(src, "error");
  const expects = directive(src, "expect");
  const panics = directive(src, "panic");
  if (errors.length > 0) {
    // `check` doesn't run comptime code or top-level initializers, so an error only a build finds
    // is looked for with one.
    let r = spawnSyncText(fishc, ["check", path]);
    if (r.status === 0) r = spawnSyncText(fishc, ["build", path, "-o", path + ".out"]);
    const said = r.stdout + r.stderr;
    if (r.status === 0) return "expected a compile error, and it built cleanly";
    for (const text of errors) if (!said.includes(text)) return `no error containing '${text}':\n${said}`;
    return "";
  }
  if (expects.length === 0 && panics.length === 0) {
    const r = spawnSyncText(fishc, ["check", path]);
    return r.status === 0 ? "" : r.stdout + r.stderr;
  }
  const r = spawnSyncText(fishc, directive(src, "mode").includes("release") ? ["run", "--release", path] : ["run", path]);
  const want = expects.join("\n");
  const got = r.stdout.trimEnd();
  if (got !== want) return `expected stdout:\n${want}\ngot:\n${got}\n${r.stderr}`;
  for (const text of panics) if (!r.stderr.includes(text)) return `no panic containing '${text}':\n${r.stderr}`;
  const code = panics.length > 0 ? 101 : 0;
  return r.status === code ? "" : `expected exit ${code}, got ${r.status ?? -1}:\n${r.stderr}`;
}

function packFiles(dir: string): string[] throws IoError {
  let out: string[] = [];
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (name.endsWith(".md")) out.push(path);
    else if (statSync(path).isDirectory()) for (const inner of readdirSync(path)) if (inner.endsWith(".md")) out.push(join(path, inner));
  }
  return out;
}

function main(): void throws IoError {
  let fishc = process.env.FISHC ?? "fishc";
  let files: string[] = [];
  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    if (args[i]! === "--fishc" && i + 1 < args.length) fishc = resolve(args[++i]!);
    else files.push(resolve(args[i]!));
  }
  if (files.length === 0) files = packFiles(resolve(import.meta.dir, "..", "knowledge"));
  const tmp = mkdtempSync(join(tmpdir(), "fish-verify-"));
  let checked = 0;
  let fragments = 0;
  let failed = 0;
  // ponytail: one example at a time; run them across cores if the pack grows past a few minutes.
  for (const file of files) {
    for (const b of blocksOf(file)) {
      if (b.kind === "fragment") {
        fragments++;
        continue;
      }
      checked++;
      const wrong = b.kind === "" ? verdict(fishc, join(tmp, `example${checked}.fsh`), b.src) : `a block is opened with 'fsh' or 'fsh fragment', not 'fsh ${b.kind}'`;
      if (wrong === "") continue;
      failed++;
      console.log(`FAIL ${b.file}:${b.line}\n${wrong}\n`);
    }
  }
  console.log(`${checked - failed} of ${checked} examples hold, ${fragments} fragments unchecked, in ${files.length} files`);
  if (failed > 0 || checked === 0) process.exit(1);
}
