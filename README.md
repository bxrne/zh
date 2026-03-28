# zh - Minimal Shell

A minimal, POSIX-inspired shell written in Zig.

Implements core shell features: command execution, I/O redirection, pipelines, history, startup configuration via `~/.zhrc`, a configurable prompt (including optional Git branch), and common builtins.

## Features

### Completed

- **Builtins**: `echo`, `exit`, `cd`, `pwd`, `type`, `export`, `eval`, `unset`, `:` (no-op)
- **External Commands**: PATH-based executable resolution using an internal environment map (inherited from the process at startup, then mutable via `export` / `unset` / `zhrc`)
- **Argument Parsing**: Quoted strings and escape sequences
- **I/O Redirection**: `>`, `>>`, `<` operators
- **Pipelines**: Multi-command piping with `|`
- **History**: In-memory storage with persistence
- **File Completion**: Directory and filename auto-completion
- **Startup file**: `~/.zhrc` — see **[ZHRC.md](ZHRC.md)** for the full format, prompt escapes (`ZH_PROMPT` / `PS1`), and examples
- **Sample config**: [examples/zhrc.sample](examples/zhrc.sample) (user, host, cwd, Git branch in prompt)

### TODO

- Command name completion
- Completion suggestions refinement
- Signal handling
- Job control
- Alias support
- Glob pattern expansion
- Compound commands (`;`, `&&`, `||`)

## Configuration (`~/.zhrc`)

`zh` loads **`$HOME/.zhrc`** once at startup. The format is **zh-specific** (not a POSIX script).

**Documentation:** [ZHRC.md](ZHRC.md) — line types (`export`, `eval`, commands, comments), size limits, and **prompt escapes** (`\u`, `\h`, `\w`, `\g` for Git, `\$`, etc.).

**Quick start:** copy the sample and edit:

```bash
cp examples/zhrc.sample ~/.zhrc
```

## Binary size vs bash (x86-64 Linux)

Sizes below are **on-disk** ELF sizes for **64-bit x86** (`x86_64-linux-gnu`), not memory use. They are **not** directly comparable in isolation because **zh** is typically a **static, stripped** Zig binary while **bash** is usually **dynamically linked** against libc and other libraries.

| Binary | Bytes (example) | Linking (example) |
|--------|-----------------|-------------------|
| `zh` (`zig build -Dtarget=x86_64-linux-gnu`, default optimize) | 72,720 | static, stripped |
| `/usr/bin/bash` (Arch Linux system package) | 1,162,312 | dynamic (e.g. libc, readline) |

In that measurement, **bash’s executable file is about 16× larger** than `zh`. Re-run `stat` on your machine after `zig build` to match your toolchain and distro.

## Building

Default optimization is **`ReleaseSmall`** (smaller binary; still safe). Override when developing:

```bash
zig build                    # ReleaseSmall, host target
zig build -Doptimize=Debug   # faster compile, larger binary, easier debugging
zig build -Dtarget=x86_64-linux-gnu   # explicit x86-64 Linux ELF
```

## Running

```bash
zig build run
```

You can pipe a session (e.g. `printf 'exit\n' | zig build run`) or run interactively.

## Installing

```bash
zig build
./zig-out/bin/zh
```

### Making zh Your Default Shell

1. **Find the full path to zh**:
   ```bash
   which zh  # or use full path: /path/to/zh
   ```

2. **Add zh to /etc/shells** (if not already present):
   ```bash
   echo /path/to/zh | sudo tee -a /etc/shells
   ```

3. **Change your default shell**:
   ```bash
   chsh -s /path/to/zh
   ```

4. **Log out and log back in** for changes to take effect.

5. Optionally install **`~/.zhrc`** from [examples/zhrc.sample](examples/zhrc.sample); details in **[ZHRC.md](ZHRC.md)**.

## POSIX and standards alignment

`zh` is **POSIX-inspired**, not a conforming POSIX shell. The sections below summarize how it relates to [POSIX.1 (shell & utilities)](https://pubs.opengroup.org/onlinepubs/9699919799/).

### Partially aligned with common shell behavior

- Simple commands, pipelines (`|`), and basic redirections (`>`, `>>`, `<`, `1>`, `2>`) for builtins and external programs.
- Working directory: `cd`, `pwd` (logical cwd via `chdir`).
- `echo` (minimal; not all POSIX `echo` options/escapes).
- `exit` (currently exits with status 0; no optional exit code yet).
- `export` / `eval` / `unset` exist but with **zh** semantics (see builtins table); `eval` nesting is capped (`max_eval_depth` in the source).

### Not POSIX-conforming (major gaps)

- No `sh` grammar for compound lists: no `;`, `&`, `&&`, `||`, `|` beyond single pipelines as already parsed.
- No parameter expansion (`$VAR`, `${…}`), tilde expansion only where `cd` already supports it; no globs, no here-documents.
- No job control, signals, `trap`, subshells, functions, or `return`.
- No `.` / `source` builtin (use `zhrc` and `eval` for startup).
- `zhrc` is a **custom** line-oriented format, not `.` of a POSIX script.

### POSIX shell builtins (XCU §2.14) — status in zh

| Builtin | In zh? | Notes |
|---------|--------|--------|
| `:` | Yes | No-op |
| `.` | No | |
| `break` / `continue` | No | No loops |
| `command` | No | |
| `eval` | Yes | Nested depth limited |
| `exec` | No | |
| `exit` | Yes | No optional status yet |
| `export` | Yes | With env map + PATH refresh |
| `readonly` | No | |
| `return` | No | |
| `set` | No | |
| `shift` | No | |
| `times` | No | |
| `trap` | No | |
| `unset` | Yes | |

Additional **zh** builtins: `echo`, `cd`, `pwd`, `type`.

## Builtins

| Command | Description |
|---------|-------------|
| `:` | No-op (exit status 0) |
| `echo [args]` | Print to stdout |
| `eval [args…]` | Concatenate arguments with spaces, parse as one command line, and run it |
| `exit [code]` | Exit shell |
| `export [NAME[=value] …]` | With no arguments, print all variables as `export NAME=value`. Otherwise set/update exported variables (visible to child processes). Changing `PATH` rebuilds the command hash table |
| `cd [path]` | Change directory |
| `pwd` | Print working directory |
| `type <cmd>` | Show command type |
| `unset NAME …` | Remove variables from the environment; `PATH` triggers a path table refresh |

**Prompt:** set **`ZH_PROMPT`** or **`PS1`** in `zhrc` (or `export` at the prompt). See escapes in **[ZHRC.md](ZHRC.md)**.
