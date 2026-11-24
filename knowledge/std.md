# The standard library

What a Fish program can call with no dependency: how names are found, which Node and web APIs
exist and where they differ, and one program per area to adapt. `std-api.md` lists every
declaration and signature; this slice says what to reach for and what is missing. Tasks, `spawn`,
`Channel`, `Lock` and `throws` are in `errors-async.md`, moves and borrows in `ownership.md`,
`@derive(Json)` in `meta.md`, npm packages and C in `interop.md`. Checked against fishc 0.1.1.
Assume nothing from Node or the browser exists until it is named here or in `std-api.md`.

## 1. How names are found

Three kinds of name need no install:

- **Globals**, in scope everywhere: `console`, `Math`, `JSON`, `Number`, `String`, `Object`,
  `Array`, `Map`, `Set`, `Date`, `URL`, `Buffer`, `fetch`, `serve`, `Router`, `process`, the
  sockets, and the rest of section 3.
- **Modules**, imported as `node:<name>` or `<name>` (`"node:fs"` and `"fs"` are the same module).
  Named, default and `* as` imports all work. `"bun"` names the `Bun` module.
- **`fish:` modules**, `fish:tar` and `fish:zip`, reached only with the prefix: a bare `"tar"` is
  looked up as an npm package.

A module's name also works as a global when a member is read from it, so `path.join(...)`,
`fs.existsSync(...)`, `os.platform()`, `crypto.randomUUID()`, `util.format(...)`, `zlib.gzipSync(...)`,
`Bun.which(...)` and `postgres.Pool` need no import. The name alone is not a value.

```fsh
import { basename } from "node:path";
import fs from "fs";

function main() {
  console.log(basename("/a/b.txt"), fs.existsSync("/"), path.extname("x.md"), os.platform().length > 0);
  // expect: b.txt true .md true
}
```

What a missing name looks like depends on where it was written, and two of the messages point
at the wrong thing:

| Written | Error |
| --- | --- |
| `import { x } from "node:http"` | `error[E0908]: 'node:http' is a Node module Fish's std doesn't have yet` |
| `import { appendFileSync } from "node:fs"` | `error[E0902]: 'node:fs' has no export named 'appendFileSync'` |
| `import { x } from "tar"` | `error[E0902]: can't find the package 'tar'` (npm lookup) |
| `structuredClone(x)` | `error[E0401]: unknown function 'structuredClone'` |
| `console.table(x)`, `process.uptime()`, `crypto.subtle` | `error[E0401]: cannot find name 'console'` (the member is what is missing) |
| `new WebSocket(url)`, `new FormData()` | `error[E0503]: only a class can be constructed with 'new'` |

```fsh
function main() {
  console.info("x");
}
// error: error[E0401]: cannot find name 'console'
```

## 2. The module table

Every importable module in the release. "Lacks" names what an agent is most likely to reach for.

| Module | Has | Lacks |
| --- | --- | --- |
| `assert` | default `assert(cond, message?)` and `ok`, which panic | `equal`, `deepStrictEqual`, `throws` |
| `buffer` | `Buffer` (also a global) | `Blob` |
| `child_process` | `spawnSync`, `execFileSync`, `execSync`, `ExecError` | async `spawn`, `exec`, `fork` (use `Bun.spawn`) |
| `crypto` | `randomUUID`, `randomBytes`, `getRandomValues`, `sha1`, `sha256`, `hmac`, `hash`, `createHash`, `createHmac` | every algorithm but SHA-1 and SHA-256, ciphers, `randomInt`, `timingSafeEqual`, `subtle` |
| `fs` | the `*Sync` calls listed in `std-api.md`, descriptors (`openSync`, `readSync`, `writeSync`, `closeSync`, `fstatSync`), `constants` | `appendFileSync`, streams, the callback API, `fs.promises` |
| `fs/promises` | `readFile`, `writeFile`, `open` (a `FileHandle`), `access`, `chmod`, `utimes`, `lutimes`, `symlink`, `link`, `readlink`, `realpath`, `watch` | `readdir`, `stat`, `mkdir`, `rm`, `rename`, `unlink`, `copyFile`, `appendFile` (use the sync ones) |
| `os` | `hostname`, `tmpdir`, `homedir`, `platform`, `availableParallelism`, `constants.signals` | `cpus`, `arch`, `EOL`, memory |
| `path`, `path/posix` | `join`, `resolve`, `normalize`, `relative`, `dirname`, `basename`, `extname`, `isAbsolute`, `parse`, `format`, `sep`, `delimiter` | `win32`, `path.posix`, `matchesGlob` |
| `process` | `argv`, `env`, `exit`, `platform`, `arch`, `execPath`, `cwd`, `chdir`, `pid`, `kill`, `on`, `once`, `signals`, `shutdown`, `stdout`, `stderr`, `stdin` | `exitCode`, `nextTick`, `uptime`, `memoryUsage`, `hrtime`, `version`, `ppid`; `env` is read-only |
| `stdin` | `lines()`, `text()`, `bytes()` | (Fish's own; `readline` is not a module) |
| `tls` | `connect(host, port, options)` giving a `TcpStream` | Node's `tls` API |
| `url` | `fileURLToPath`, `pathToFileURL` | `URL` and `URLSearchParams` are globals |
| `util` | `format`, `inspect`, `isDeepStrictEqual`, `parseArgs` | `promisify`, `types`, `%j`, `inspect` options |
| `zlib` | `gzip`, `gunzip`, `deflate`, `inflate`, `deflateRaw`, `inflateRaw`, `unzip`, each also as `*Sync` | brotli, streams |
| `postgres` | `Pool` with `query`, `queryOne`, `execute` | transactions that span statements |
| `fish:tar`, `fish:zip` | `entries`, `list`, `extract`, `pack`, `create` | |
| `bun` | `file`, `write`, `stdin`, `env`, `argv`, `sleep`, `sleepSync`, `which`, `spawn`, `spawnSync`, `serve`, `version` | everything else in Bun |

Not modules at all: `http`, `https`, `net`, `dgram`, `dns`, `events`, `stream`, `readline`,
`timers`, `timers/promises`, `worker_threads`, `querystring`, `perf_hooks`, `test`. Globals do
their work: `serve` and `fetch`, the sockets of section 8, `ReadableStream`, `readLine`,
`setTimeout` and `sleep`, `spawn` and `spawnBlocking`, `URLSearchParams`, `performance.now()`.

A module's error classes are imported with it (`ExecError`, `ZlibError`, `TarError`, `ZipError`,
`PostgresError`, `RowError`). `Error`, `TypeError`, `IoError`, `JsonError`, `AbortError`,
`ParseArgsError` and `AggregateError` are globals. An `Error` has `name`, `message` and `cause`,
no `stack`. There is no `SyntaxError`, and `RangeError` exists only in a program naming `Buffer`.

## 3. Built-in globals

These are known to the checker and are not in `std-api.md`. Each row is what was run against the
release; anything in "Absent" is a compile error.

| Family | Exists | Absent |
| --- | --- | --- |
| `console` | `log`, `error`, `warn` (the last two on stderr), `%s` and `%d` in the first argument; `print(x)` | `info`, `debug`, `table`, `dir`, `time`, `trace`, `assert`, `group` |
| `Math` | `abs floor ceil round trunc sign sqrt cbrt pow hypot min max random exp expm1 log log2 log10`, trigonometry, `PI E LN2 SQRT2` | `imul`, `clz32`, `fround`; `Math.max(...xs)` (spread is refused) |
| `Number` | `Number(s)`, `parseInt`, `parseFloat`, `Number.isNaN isFinite isInteger isSafeInteger parseInt parseFloat`, `MAX_SAFE_INTEGER MIN_SAFE_INTEGER EPSILON MAX_VALUE NaN POSITIVE_INFINITY`, `x.toFixed(n)` | bare `NaN`, `Infinity`, `isNaN`, `isFinite`; `x.toString()` in any radix, `toPrecision`, `toExponential`, `toLocaleString` |
| `String` | `String(x)`, `String.fromCharCode`, `String.fromCodePoint`, `String.raw`; methods `at charAt charCodeAt codePointAt indexOf lastIndexOf includes startsWith endsWith slice substring toUpperCase toLowerCase trim trimStart trimEnd padStart padEnd repeat split replace replaceAll match matchAll search concat` | `substr`, `localeCompare`, `normalize`, `toLocaleUpperCase`, `isWellFormed`, `toString`, `trimLeft` |
| Regex | literals, `test`, `exec`, and the string methods above; named groups typed from the pattern | `lastIndex`; `new RegExp` of anything but string literals; `match("text")` |
| `Array` | `Array.isArray from of`, `new Array(n).fill(x)`; `map filter reduce reduceRight find findIndex findLast findLastIndex some every includes indexOf lastIndexOf slice splice concat join at flat flatMap forEach push pop shift unshift sort reverse fill copyWithin toSorted toReversed toSpliced with entries keys values` | `toString`, `groupBy`; `new Array(n)` unfilled; `Array.from(aSet)` (spread it) |
| `Map`, `Set` | `get set has delete clear size forEach keys values entries`, `add`; `for...of` and spread | `getOrInsert`, `Map.groupBy`, `union` and the other set algebra, `WeakMap`, `WeakSet`; keys other than strings and numbers |
| Iterator helpers | on generators and on an array's `values()`, `keys()`, `entries()`: `map filter take drop flatMap reduce forEach some every find toArray` | `Iterator.from` |
| `Object` | `Object.keys`, `values`, `entries` of a variable or field | `assign`, `fromEntries`, `freeze`, `groupBy` |
| `JSON` | `JSON.stringify(x)`, `JSON.parse<T>(text)`, untyped `JSON.parse(text)` giving a `Json` | indent and replacer arguments, revivers |
| `Date` | `new Date()`, `new Date(ms)`, `Date.now()`, `getTime`, `valueOf`, `equals`, the `getUTC*` getters, `toISOString`, `toJSON`, `toUTCString` | parsing (`new Date(text)`, `Date.parse`), `new Date(y, m, d)`, `Date.UTC`, local-time getters, setters, `toLocale*` |
| Timers | `setTimeout`, `setInterval`, `clearTimeout`, `clearInterval`, `sleep(ms)`, `performance.now()` | `setImmediate`, `queueMicrotask`, `process.nextTick`, `performance.mark` |
| URLs | `URL` (`new URL`, `URL.parse`, `URL.canParse`, the usual getters, `searchParams`), `URLSearchParams` | `encodeURIComponent`, `decodeURIComponent`, `encodeURI`, `decodeURI` |
| Bytes | `u8[]` is the byte type and `Uint8Array` is the same type; `Int8Array` to `Uint32Array`, `Float32Array`, `Float64Array`, `ArrayBuffer`, `DataView`; `TextEncoder`, `TextDecoder` (UTF-8, `{ fatal: true }`); `bytes.toBase64()`, `bytes.toHex()`, `u8.fromBase64(s)`, `u8.fromHex(s)`, `btoa`, `atob` | `Uint8ClampedArray`, `BigInt64Array`, `BigUint64Array`, other `TextDecoder` encodings, `Blob` |
| `Buffer` | `Buffer.from alloc allocUnsafe concat byteLength compare`; `toString(encoding)`, `equals`, `compare`, `indexOf`, `includes`, the `read*` methods, and every `u8[]` method | the `write*` methods, `Buffer.isBuffer`, `copy`, `utf16le` |
| Other web | `fetch`, `Request`, `Response`, `Headers`, `ReadableStream`, `WritableStream`, `AbortController`, `AbortSignal` (`timeout`, `any`), `crypto.randomUUID()`, `crypto.getRandomValues`, `import.meta.dir`, `import.meta.url`, `prompt`, `readLine`, `assert` | `structuredClone` (use `x.clone()`), `globalThis`, `navigator`, `WebSocket` (client), `EventSource`, `EventTarget`, `FormData`, `Intl`, `TransformStream`, `CompressionStream`, `Symbol()`, `Boolean()`, `require`, `__dirname` |

The differences that compile in TypeScript and mean something else, or nothing, in Fish:

- **Parsing gives `null`, not `NaN`.** `parseInt`, `parseFloat` and `Number(text)` return
  `i64 | null` or `number | null`. Handle the null with `??` or a check; passing the result
  to `Number.isNaN` compiles and then panics on a null.
- **`Math.floor`, `ceil`, `round`, `trunc` and `pow` give `number` (an `f64`)**, so an `i64`
  needs `as i64`. `.length` is a `usize`; `indexOf` and `Date.now()` give `i64`.
- **Methods that change an array in place return nothing**: `push`, `unshift`, `sort`, `reverse`,
  `fill`, `copyWithin`. `xs.sort().map(...)` and `const n = xs.push(x)` are refused with
  `error[E0118]`; use `toSorted` and `toReversed` to chain. `find`, `findLast`, `at`, `pop`,
  `shift` and `Map.get` give `T | null`.
- **`xs.sort()` with no comparator orders numbers numerically**, where JavaScript orders them as
  text. Strings sort by UTF-16 code units.
- **`Map` and `Set` `keys()`, `values()` and `entries()` give arrays**, already collected. An
  array's own `values()` gives a generator, which is where `take` and `toArray` live.
- **`String(x)` and templates take strings, numbers and booleans only** (`error[E0510]` for an
  array or object). Print with `console.log`, or build text with `JSON.stringify` or
  `util.inspect`.
- **An object's keys come out sorted by name**, in `Object.keys`, `JSON.stringify` and
  `console.log` alike, whatever order its type declares. A dictionary (`{ [k: string]: V }`) and
  a `Map` keep insertion order.
- **A regex is compiled with the program** and keeps no state: `test` on a `g` regex is
  `error[E0508]`, and a pattern known only at run time has no regex at all.

```fsh
function main() {
  const port = parseInt(process.env.PORT ?? "") ?? 8080; // null for unset or not a number
  console.log(port, parseInt("12px"), Number("abc"), Math.floor(7.9) as i64); // expect: 8080 12 null 7
  let nums = [10, 9, 100];
  nums.sort(); // in place, no value
  const top = nums.toSorted((a, b) => b - a).slice(0, 2);
  console.log(nums, top, nums.find((n) => n > 500), nums.at(-1)); // expect: [ 9, 10, 100 ] [ 100, 10 ] null 100
  let seen = new Map<string, i64>();
  seen.set("b", 2);
  seen.set("a", (seen.get("a") ?? 0) + 1);
  const big = seen.values().filter((v) => v > 1); // values() is an array here
  console.log(seen.keys(), big, nums.values().map((n) => n * 2).take(2).toArray()); // expect: [ 'b', 'a' ] [ 2 ] [ 18, 20 ]
  const cfg = { port: 80, host: "h" };
  console.log(Object.keys(cfg), JSON.stringify(cfg)); // expect: [ 'host', 'port' ] {"host":"h","port":80}
  const m = "2026-11-24".match(/(\d+)-(\d+)-(?<day>\d+)/);
  if (m !== null) console.log(m[1], m.groups.day, "a1b22".replace(/\d+/g, (d) => `<${d}>`)); // expect: 2026 24 a<1>b<22>
  console.log("héllo".length, new TextEncoder().encode("héllo").length); // expect: 5 6
}
```

`JSON.parse<T>` checks the text against `T` and throws `JsonError` with a path
(`missing field 'y' at $`); untyped `JSON.parse` gives a `Json`: `null`, a boolean, a number, a
string, an array or a `Map<string, Json>`, never an object with fields. More: `examples/json.fsh`,
`array.fsh`, `string.fsh`, `regex.fsh`, `iterator.fsh`, `date.fsh`, `buffer.fsh`, `typed_arrays.fsh`.

## 4. The HTTP server

`serve(options, handler)` serves HTTP/1.1 (and HTTPS with `tls: { cert, key }`), each connection
on its own task. It follows the Fetch API's `Request`, `Response` and `Headers`, with a `Router`
shaped like Hono's. The habits that fail:

- **A handler is `async (req) => Response`.** A plain arrow is refused; so is `await` inside an
  expression (`console.log(await res.text())`): name the value first.
- **`serve` returns when the server stops**, so `await serve(...)` blocks. To run beside other
  code, `spawn(serve(...))`. A call neither awaited nor spawned is `error[E0302]`: promises are lazy.
- **Headers are a `Headers`, built with `set`**: `new Headers()` takes no argument and an object
  literal for `headers` is refused. `Headers` has `get`, `has`, `set`, `append`, `delete`,
  `forEach`, and no iteration.
- **Route parameters are read with `req.param("id")`** (a string, `""` when absent).
  `req.params` is a flat `string[]`. The query string is read with
  `new URL(req.url).searchParams`.
- **`req.json<T>()` needs its type**, and throws `JsonError`. A request has `method`, `url`,
  `path`, `headers`, `signal`, `cookies`, `body`, `text()`, `bytes()`, `json<T>()`, `clone()`.
  There is no `formData()`, `arrayBuffer()` or `blob()`, and no client address.
- **Shared state is `shared({...})` holding `Lock` and `Atomic`**, cloned once per handler, since
  each handler owns what it captures (`errors-async.md`).

```fsh
type Todo = { id: i64; title: string; done: boolean };
type NewTodo = { title: string };
async function main(): Promise<void> throws IoError | AbortError | JsonError {
  const none: Todo[] = [];
  const db = shared({ todos: new Lock(none), next: new Atomic(1) });
  let app = new Router();
  const create = db.clone();
  app.post("/todos", async (req) => {
    try {
      const body = await req.json<NewTodo>();
      const todo: Todo = { id: create.next.add(1), title: body.title, done: false };
      const kept = todo.clone();
      create.todos.update((t) => { t.push(kept); });
      return Response.json(todo, { status: 201 });
    } catch (e) {
      return Response.json({ error: e.message }, { status: 400 });
    }
  });
  const one = db.clone();
  app.get("/todos/:id", async (req) => {
    const id = parseInt(req.param("id"));
    const found = one.todos.update((t) => t.find((x) => x.id === id));
    if (found === null) return Response.json({ error: "not found" }, { status: 404 });
    return Response.json(found);
  });
  // Port 0 asks the system for a free port, which onListen reports; the signal stops the server.
  const stop = new AbortController();
  const up = shared({ port: new Atomic(0) });
  const seen = up.clone();
  const server = spawn(serve({ port: 0, hostname: "127.0.0.1", signal: stop.signal, onListen: (info) => { seen.port.store(info.port); } }, app.handler()));
  while (up.port.load() === 0) await sleep(1);
  const base = "http://127.0.0.1:" + String(up.port.load());
  let h = new Headers();
  h.set("content-type", "application/json");
  const made = await fetch(base + "/todos", { method: "POST", headers: h, body: JSON.stringify({ title: "write docs" }) });
  const text = await made.text();
  console.log(made.status, text); // expect: 201 {"done":false,"id":1,"title":"write docs"}
  const got = await fetch(base + "/todos/1");
  const todo = await got.json<Todo>();
  console.log(todo.title, got.headers.get("content-type")); // expect: write docs application/json
  const bad = await fetch(base + "/todos", { method: "POST", body: "{}" });
  const why = await bad.text();
  console.log(bad.status, why); // expect: 400 {"error":"missing field 'title' at $"}
  const missing = await fetch(base + "/nope");
  console.log(missing.status, missing.ok); // expect: 404 false
  stop.abort(); // requests in flight are answered, idle connections closed
  await server;
  console.log("stopped"); // expect: stopped
}
```

The rest of the surface, run here through `app.handle(request)`, which routes a request with no
socket and is the way to test a router:

```fsh
async function* ticks(): AsyncGenerator<string> {
  for (let i = 0; i < 3; i++) yield "tick " + String(i) + "\n";
}

async function main(): Promise<void> {
  let api = new Router();
  api.get("/users/:id", async (req) => new Response("user " + req.param("id")));
  api.use(async (req, next) => { // middleware: answer early, or call next and change what comes back
    if (req.headers.get("authorization") === null) return new Response("no", { status: 401 });
    let res = await next(req);
    res.headers.set("x-served-by", "fish");
    return res;
  });
  let app = new Router();
  app.route("/api", api); // a group: api moves into app, its middleware around its routes only
  app.get("/login", async (req) => {
    let res = new Response("hello " + (req.cookies.get("name") ?? "stranger"));
    res.cookies.set("sid", "abc123", { httpOnly: true, maxAge: 3600 }); // request cookies are read-only
    return res;
  });
  app.get("/stream", async (_req) => new Response(ticks())); // sent chunked, a piece per yield
  let h = new Headers();
  h.set("cookie", "name=ann");
  const login = await app.handle(new Request("http://h/login", { headers: h }));
  const said = await login.text();
  console.log(said, "|", login.cookies.toSetCookieHeaders()[0]); // expect: hello ann | sid=abc123; Path=/; Max-Age=3600; HttpOnly; SameSite=Lax
  const refused = await app.handle(new Request("http://h/api/users/7"));
  const stream = await app.handle(new Request("http://h/stream"));
  const all = await stream.text();
  console.log(refused.status, all.split("\n").length - 1); // expect: 401 3
}
```

- **Router**: `get`, `post`, `put`, `patch`, `delete`, `all`, `route(method, path, handler)`,
  `route(prefix, router)`, `use(middleware)`, `static(prefix, dir)`, `ws(path, handler, options?)`,
  `handle(req)`, `handler()`. The first matching route runs; `:name` matches one segment; no
  wildcards or patterns. `handler()` takes the router over, so call it last.
- **Response**: `new Response(body?, init?)` with a string, `u8[]`, async generator of strings,
  `ReadableStream<u8[]>` or `null`; `Response.json(value, init?)`; `Response.sse(generator)` for
  server-sent events. `status`, `statusText`, `headers`, `cookies`, `ok`, `url`, `body`, `text()`,
  `bytes()`, `json<T>()`, `clone()`. No `Response.redirect`: set `status` and a `location` header.
- **Static files**: `app.static("/assets", dir)` serves GET and HEAD with content types and ETags,
  `index.html` for a directory, and a 404 for anything outside `dir`.
- **WebSockets**: a route, below. Text arrives as `string`, binary as `u8[]`; `ws.send`,
  `ws.close(code?, reason?)`, `ws.flush()`, `ws.sender()` (a handle other tasks send on). No client.
- **Limits** (`ServeOptions`): `maxBodySize` (128 MiB, a 413 past it), `headerTimeout` (60 s) and
  `idleTimeout` (10 s), a 408 for a request that stalls; `0` is no timeout. `port` defaults to
  8000 and `hostname` to `0.0.0.0`. A chunked request body gets a 501.
- **Shutdown**: with no `signal`, the first SIGINT or SIGTERM stops the server gracefully and
  `serve` returns; a second exits at once. `req.signal` aborts when the client goes away.

```fsh
async function main(): Promise<void> throws IoError {
  let app = new Router();
  app.ws("/chat", async (ws, req) => {
    ws.send("hello " + (req.headers.get("origin") ?? "you"));
    for await (const m of ws) { // ends when either side closes
      if (typeof m === "string") ws.send(m.toUpperCase());
      else ws.send(m);
    }
  }, { maxMessageSize: 65536, idleTimeout: 30000 });
  await serve({ port: 8080 }, app.handler());
}
```

More: `examples/http.fsh`, `router.fsh`, `cookies.fsh`, `static_files.fsh`,
`readable_stream.fsh` and `websocket.fsh` there.

## 5. The HTTP client

`fetch(input, init?)` takes a string, `URL` or `Request`, and throws `IoError | AbortError`.
Its options are `method`, `headers` (a `Headers`), `body` (string, `u8[]` or
`ReadableStream<u8[]>`), `signal`, `unix` (a socket path) and `tls: { ca }`; any other key is a
compile error. Unlike the browser's, **redirects are returned, not followed**, and each call
opens its own connection. A 4xx or 5xx is a response; a refused connection is an `IoError` whose
`code` is `"ECONNREFUSED"`. Read a body once with `text()`, `bytes()` or `json<T>()`, or as
`res.body`, a `ReadableStream<u8[]> | null` for `for await`. More: `examples/fetch.fsh`.

```fsh
async function main(): Promise<void> throws IoError {
  const stop = new AbortController();
  const up = shared({ port: new Atomic(0) });
  const seen = up.clone();
  const server = spawn(serve({ port: 0, hostname: "127.0.0.1", signal: stop.signal, onListen: (info) => { seen.port.store(info.port); } }, async (req) => {
    let h = new Headers();
    h.set("location", "/new");
    if (req.path === "/old") return new Response(null, { status: 301, headers: h });
    await sleep(500);
    return new Response("late");
  }));
  while (up.port.load() === 0) await sleep(1);
  const base = "http://127.0.0.1:" + String(up.port.load());
  try {
    const moved = await fetch(base + "/old");
    console.log(moved.status, moved.ok, moved.headers.get("location")); // expect: 301 false /new
    const slow = await fetch(base + "/slow", { signal: AbortSignal.timeout(50) });
    console.log(slow.status);
  } catch (e) {
    if (e instanceof AbortError) console.log("aborted:", e.message); // expect: aborted: This operation was aborted
    else console.log(e.code, e.syscall);
  }
  stop.abort();
  await server;
}
```

## 6. Files

`node:fs` is the full set of blocking calls, `node:fs/promises` a short list that runs on the
blocking pool (section 2). The blocking calls work inside async functions. All throw `IoError`,
which carries Node's `code` (`"ENOENT"`), `syscall` and `path`.

- **The encoding decides the type and must be a literal**: `readFileSync(p, "utf8")` is a
  `string`, `readFileSync(p)` a `u8[]`. Only `"utf8"` is known.
- `statSync` gives a `Stats` (`size`, `mode`, `mtimeMs`, `mtime`, `isFile()`, `isDirectory()`);
  with `{ throwIfNoEntry: false }` it gives `undefined` for a missing path.
- `readdirSync(dir, { withFileTypes: true })` gives `Dirent`s; there is no recursive option.
- `watch(path, { recursive, signal })` from `node:fs/promises` is an async generator that ends,
  rather than throws, when its signal aborts.

More: `examples/fs.fsh`, `examples/watch.fsh`, `examples/path.fsh`, `examples/os.fsh`.

```fsh
import { closeSync, existsSync, mkdirSync, mkdtempSync, openSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync, writeSync } from "node:fs";
import { open, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, extname, join } from "node:path";
async function main(): Promise<void> throws IoError {
  const dir = mkdtempSync(join(tmpdir(), "fish-std-"));
  const file = join(dir, "notes", "a.txt");
  mkdirSync(join(dir, "notes"), { recursive: true });
  writeFileSync(file, "one\n");
  const fd = openSync(file, "a"); // no appendFileSync: open for append and write the descriptor
  writeSync(fd, "two\n");
  closeSync(fd);
  const text = readFileSync(file, "utf8");
  const bytes = readFileSync(file);
  console.log(text.split("\n").length, bytes.length, basename(file), extname(file)); // expect: 3 8 a.txt .txt
  console.log(readdirSync(dir), existsSync(file), statSync(file).size); // expect: [ 'notes' ] true 8
  console.log(statSync(join(dir, "nope"), { throwIfNoEntry: false }) === undefined); // expect: true
  await writeFile(join(dir, "b.bin"), bytes); // takes bytes over (section 10)
  const again = await readFile(join(dir, "b.bin"), "utf8");
  const handle = await open(file, "r");
  let buf: u8[] = new Array(3).fill(0 as u8);
  const got = await handle.read(buf, 0, 3, 0);
  await handle.close();
  console.log(again === text, got.bytesRead, new TextDecoder().decode(buf)); // expect: true 3 one
  try {
    readFileSync(join(dir, "missing"));
  } catch (e) {
    console.log(e.code, e.syscall); // expect: ENOENT open
  }
  rmSync(dir, { recursive: true });
}
```

## 7. Process

`process` is a global. `process.argv` is `[program, program, ...arguments]`, under `fishc run` and
in a built binary alike, so `process.argv.slice(2)` is the arguments. `process.env.NAME` and
`process.env[name]` are `string | null`; `process.env` can't be assigned to or taken whole.

- `parseArgs` from `node:util` is Node's in strict mode. Its config must be an object literal in
  the call, because the result's type is built from it, and it throws `ParseArgsError`.
- `node:child_process` is blocking only. `{ encoding: "utf8" }` written in the call makes the
  output a string; otherwise it is `u8[]`. `execFileSync` throws `ExecError` on a nonzero exit.
  For a child that runs beside the program use `Bun.spawn(cmd)` and await its `exited`.
- `process.stdout.write(chunk)` adds no newline; the streams have `write` and `isTTY` only.
- Standard input: `readLine()` (global, `string | null`), `prompt(message)`, the `stdin`
  module's `lines()`, `text()`, `bytes()`, or `readFileSync(0, "utf8")`.
- Signals: `process.on(name, listener)`, `once`, `process.kill(pid, name)`, the `signals(...names)`
  async generator, and `process.shutdown`, an `AbortSignal` the first SIGINT or SIGTERM aborts.

More: `examples/process.fsh`, `examples/stdin.fsh`, `examples/util.fsh`, `examples/bun.fsh`.

```fsh
import { ExecError, execFileSync, spawnSync } from "node:child_process";
import { signals } from "node:process";
import { parseArgs } from "node:util";
async function main(): Promise<void> throws ParseArgsError | IoError | ExecError {
  const { values, positionals } = parseArgs({
    args: ["--name", "ann", "-v", "in.txt"], // leave args out to read process.argv
    options: { name: { type: "string", default: "nobody" }, verbose: { type: "boolean", short: "v" } },
    allowPositionals: true,
  });
  console.log(values.name, values.verbose ?? false, positionals); // expect: ann true [ 'in.txt' ]
  console.log(process.env.HOME !== null, process.env["FISH_NOT_SET"] ?? "unset"); // expect: true unset
  const out = execFileSync("echo", ["hi"], { encoding: "utf8" });
  const r = spawnSync("sh", ["-c", "echo oops >&2; exit 3"], { encoding: "utf8" });
  console.log(out.trim(), r.status, r.stderr.trim()); // expect: hi 3 oops
  try {
    execFileSync("false");
  } catch (e) {
    if (e instanceof ExecError) console.log("exit", e.status); // expect: exit 1
  }
  let seen = signals("SIGUSR1"); // listening starts at the call
  process.kill(process.pid, "SIGUSR1");
  const first = await seen.next();
  if (first.done === false) console.log(first.value); // expect: SIGUSR1
  process.stdout.write("bye\n"); // expect: bye
  process.exit(0);
}
```

## 8. Networking

Sockets are global types, not modules, and only work when `main` is async. Each is made by an
awaited static call and throws `IoError`; a wait given an `AbortSignal` also throws `AbortError`.

| Type | Made with | Members |
| --- | --- | --- |
| `TcpListener` | `TcpListener.bind(host, port)` | `accept(signal?)`, `port` |
| `TcpStream` | `TcpStream.connect(host, port, signal?)`, `tls.connect(host, port, { ca?, serverName?, signal? })` | `read(max, signal?)`, `write(bytes, signal?)`, `clone()` |
| `UnixListener`, `UnixStream` | `.bind(path)`, `.connect(path)` | as the TCP ones, without `port` |
| `UdpSocket` | `UdpSocket.bind(host, port)` | `sendTo(bytes, host, port)`, `receiveFrom()` giving `{ bytes, host, port }`, `connect`, `send`, `receive`, `clone()`, `port` |

- **There is no `close()`, `end()` or event**: a socket closes when it is dropped, at the end of
  its scope. Use a block to close one early.
- **`read(max)` gives at most `max` bytes, and an empty array at the end of the stream.**
  **`write` takes `u8[]` only**; a string is `error[E0101]`. Encode with `TextEncoder`.
- **No DNS module**: `connect` and `fetch` resolve host names; a name that does not resolve is an
  `IoError` with code `ENOTFOUND`.
- TLS: `serve({ tls: { cert, key } })` for a server, `fetch` for `https:` URLs, `tls.connect` for
  a raw client stream. Certificates are PEM text.

More: `examples/tcp.fsh`, `examples/udp.fsh`, `examples/unix.fsh`, `examples/tls.fsh`.

```fsh
async function echo(listener: TcpListener): Promise<void> throws IoError {
  const conn = await listener.accept();
  while (true) {
    const got = await conn.read(4096);
    if (got.length === 0) break;
    await conn.write(got);
  }
}

async function main(): Promise<void> throws IoError | AbortError {
  const listener = await TcpListener.bind("127.0.0.1", 0);
  const port = listener.port; // read before the listener moves into the task
  const server = spawn(echo(listener));
  {
    const conn = await TcpStream.connect("localhost", port, AbortSignal.timeout(1000));
    await conn.write(new TextEncoder().encode("ping"));
    const back = await conn.read(16);
    console.log(new TextDecoder().decode(back)); // expect: ping
  } // conn dropped: the server's read gives an empty array
  await server;
  const a = await UdpSocket.bind("127.0.0.1", 0);
  const b = await UdpSocket.bind("127.0.0.1", 0);
  await a.sendTo(new TextEncoder().encode("hi"), "127.0.0.1", b.port);
  const got = await b.receiveFrom();
  console.log(new TextDecoder().decode(got.bytes), got.host, got.port === a.port); // expect: hi 127.0.0.1 true
}
```

## 9. Data

Hashing is SHA-1 and SHA-256 only. `zlib` works on whole buffers and gives `u8[]`. `fish:tar`
and `fish:zip` share one shape: `list` (headers), `entries` (an async generator with each
entry's `data`), `extract(source, dir)`, `create(file, paths, options)` and `pack`; a source is a
path, bytes or a stream, and extraction refuses any entry that would land outside `dir`.
More: `examples/crypto.fsh`, `examples/zlib.fsh`, `examples/tar.fsh`, `examples/zip.fsh`.

```fsh
import { createHash, createHmac, hash, randomBytes } from "node:crypto";
import { gunzipSync, gzipSync, ZlibError } from "node:zlib";
import { create as tarCreate, list as tarList, TarError } from "fish:tar";
import { create as zipCreate, entries as zipEntries, ZipError } from "fish:zip";
async function main(): Promise<void> throws IoError | ZlibError | TarError | ZipError {
  console.log(hash("sha256", "abc").slice(0, 16)); // expect: ba7816bf8f01cfea
  console.log(createHash("sha1").update("a").update("bc").digest("hex")); // expect: a9993e364706816aba3e25717850c26c9cd0d89d
  console.log(createHmac("sha256", "key").update("msg").digest("base64").length, randomBytes(8).length); // expect: 44 8
  const packed = gzipSync("hello ".repeat(100));
  const small = packed.length < 600; // read before gunzipSync takes packed over
  const plain = gunzipSync(packed);
  console.log(small, new TextDecoder().decode(plain).length); // expect: true 600
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "fish-data-")); // module names as globals
  fs.writeFileSync(path.join(dir, "a.txt"), "hello");
  await tarCreate(path.join(dir, "out.tgz"), ["a.txt"], { cwd: dir, gzip: true });
  const headers = await tarList(path.join(dir, "out.tgz"));
  console.log(headers[0].path, headers[0].size); // expect: a.txt 5
  await zipCreate(path.join(dir, "out.zip"), ["a.txt"], { cwd: dir });
  for await (const e of zipEntries(path.join(dir, "out.zip"))) console.log(e.path, new TextDecoder().decode(e.data)); // expect: a.txt hello
  fs.rmSync(dir, { recursive: true });
}
```

The Postgres driver speaks the wire protocol itself. `Pool.connect(url)` opens one connection at
once, so a bad address or password fails there; the URL takes `sslmode` (`disable`, `require`,
`verify-full`) and `max`. Parameters are `$1`, `$2`, sent apart from the SQL: `null`, `boolean`,
`i64`, `f64`, `string`, `u8[]` or `Date` (convert a narrower integer first). Rows are read by
column name into an object type or a `@derive(Json)` class. Each statement may run on another
connection, and a transaction one leaves open is rolled back. More: `examples/postgres.fsh`.

```fsh
import { Pool, PostgresError, RowError } from "postgres";
type User = { id: i64; name: string; email: string | null };

async function main(): Promise<void> throws IoError | AbortError | TypeError | PostgresError | RowError {
  const url = process.env.DATABASE_URL ?? "postgres://app:secret@localhost:5432/app?sslmode=disable&max=10";
  const pool = await Pool.connect(url);
  const changed = await pool.execute("insert into users (name) values ($1)", ["ann"]); // rows affected
  const users = await pool.query<User>("select id, name, email from users where id > $1", [0]);
  const one = await pool.queryOne<User>("select id, name, email from users where id = $1", [changed]);
  console.log(users.length, one === null ? "none" : one.name);
}
```

## 10. Ownership at the API surface

A std function is an ordinary Fish function: **a parameter written as a bare type takes its
argument over, and one written `Ref<T>` or `Mut<T>` borrows it.** Read the signature in
`std-api.md` before passing an array, a `Headers` or any other object you still need. Strings,
numbers and booleans are never lost by passing them.

| Takes its argument over | Borrows |
| --- | --- |
| `sha256(data)`, `hash`, `hmac`, `gzipSync(data)` and the rest of `zlib` | `new TextDecoder().decode(bytes)` (`Ref<u8[]>`) |
| `writeFileSync(path, data)`, `writeFile`, `Bun.write`, `handle.write(data)` | `writeSync(fd, bytes)` (`Ref<u8[]>`), `readSync(fd, buf)` and `handle.read(buf)` (`Mut<u8[]>`) |
| `conn.write(bytes)`, `socket.sendTo(bytes, ...)`, `ws.send(data)` | `bytes.toHex()`, `bytes.toBase64()`, `Buffer.from(bytes)`, `new Uint8Array(bytes)` (copies) |
| `new Response(body)`, and `headers` or `body` inside an init object | `Response.json(value)` (`Ref<T>`), `JSON.stringify(x)`, `console.log(x)` |
| `xs.push(item)`, `map.set(key, value)`, `app.route(prefix, router)`, `app.handler()` | `xs.concat(ys)`, `xs.map(f)` and the other array methods that give a new array |

**Symptom**: `error[E0201]` on a later use of the value. **Why**: the callee's parameter is a
bare `u8[]` (or `string | u8[]`), so the call moved the array. **Fix**: pass `x.clone()`, or read
what you need before the call. A generator handed to `map`, `filter` or `take` moves the same way.

```fsh
import { sha256 } from "node:crypto";
function main() {
  const bytes = new TextEncoder().encode("abc");
  const digest = sha256(bytes); // sha256(bytes.clone()) keeps bytes, and this program then compiles
  console.log(digest.toHex(), bytes.length);
}
// error: error[E0201]: 'bytes.length' can't be used here because 'bytes' was moved
```

The other borrow an agent meets here is a temporary: `await new Response(x).text()` and
`const it = [1, 2].values()` are refused with `error[E0204]`, because the method borrows a value
that is gone at the end of the statement. Give the value a name first.

## Not released yet

In the compiler's source, and refused by fishc 0.1.1 (the modules with `error[E0902]`):

- **`sqlite`**, over the system's SQLite: `Database.open(path)` (`":memory:"` too),
  `db.run(sql, params)` giving `{ changes, lastInsertRowid }`, `db.query<T>`, `db.queryOne<T>`,
  `db.prepare(sql)` giving a `Statement` with `all<T>`, `get<T>` and `run`, and `close()`.
  Parameters are `?`, errors `SqliteError` and `RowError`.
- **`fish:trace`**: `span(name)` begins a span under the current one, which follows its task
  across awaits and into spawned tasks; `span.end()`, `configureTracing({ endpoint, serviceName })`
  and `flushTraces()`. `serve` makes a span per request and takes `trace: false`.
- **Typed route handlers**: a handler may take its JSON body as a second, typed parameter and
  return a value instead of a `Response`. The body is checked before the handler runs (a 400
  with the reason otherwise), the value is answered as JSON, and a handler returning nothing
  answers 204, as in `app.post("/users", async (req, body: NewUser): Promise<User> => ...)`.
- **`fishc openapi <file.fsh> [-o <out>]`** prints the OpenAPI document of the routes a program
  adds to std's `Router`, from those typed handlers.
