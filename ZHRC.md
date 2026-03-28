# zhrc — startup configuration for zh

When `zh` starts interactively, it reads **`$HOME/.zhrc`** once (if `HOME` is set). This file is **not** POSIX shell script syntax; only the line types below are understood.

- **Location:** `$HOME/.zhrc`
- **Missing file:** ignored (no error)
- **Max size:** 256 KiB (larger files are rejected with a message to stderr)

## Line types

Each line is processed after trimming leading and trailing ASCII whitespace (` `, `\t`, `\r`).

| Kind | Rule |
|------|------|
| Empty | Skipped |
| Comment | First non-space character is `#` (whole-line comments only) |
| `export` | Must start with the word `export` followed by a space or end of line. See [Exports](#exports) |
| `eval` | Must start with the word `eval` followed by whitespace. The rest of the line is executed as one REPL command line |
| Command | Any other non-empty line is parsed like interactive input (arguments, redirections, one pipeline) |

Lines that fail to parse or run usually print an error with a **line number**; the shell continues with the next line when possible.

## Exports

### `export NAME=value`

Sets `NAME` in the shell’s environment (visible to child processes). Only the **first** `=` separates name and value; the value is the remainder of the payload (v1 does not split on spaces inside the value).

### `export NAME`

Sets `NAME` to an empty string.

### `PATH`

Whenever `PATH` is set (via `export` or `eval`), the internal command lookup table is rebuilt from the new value.

### Interactive `export`

At the prompt you can also run `export` with the same rules; multiple `NAME=value` words on one line are supported there.

## `eval` lines

The text after `eval` is concatenated (after trimming leading spaces on the line) and passed through the same parser as a normal typed command. Nesting depth is limited (see source: `max_eval_depth`).

Example:

```text
eval echo hello
```

## Prompt (`ZH_PROMPT` / `PS1`)

The REPL prompt is **not** set from `zhrc` syntax directly; set the environment variable **`ZH_PROMPT`** (preferred) or **`PS1`** using `export`.

If neither is set or the value is empty, the prompt is `$ `.

### Escape sequences

Inside the prompt string, backslash starts an escape:

| Sequence | Expands to |
|----------|------------|
| `\u` | `USER` from the environment, or `user` |
| `\h` | Short hostname: `HOSTNAME` before the first `.`, else `uname` nodename (short) |
| `\w` | Current working directory; leading `HOME` is replaced with `~` |
| `\W` | Basename of the current working directory |
| `\g` | Current Git branch from `git rev-parse --abbrev-ref HEAD`, wrapped in `(branch)`; empty if not a repo or `git` fails |
| `\$` | `#` if effective UID is 0, else `$` |
| `\\` | Literal `\` |
| other `\x` | Literal `\` and `x` |

**Note:** `\g` runs `git` on every prompt; in large repos it may feel slow.

### Example

```text
export ZH_PROMPT=\u@\h:\w \g\$ 
```

(Include a trailing space after `\$` if you want a gap before your typing.)

## Installing a sample file

From a clone of the repository:

```bash
cp examples/zhrc.sample ~/.zhrc
```

Edit the file to match your paths and taste.

## See also

- [README.md](README.md) — build, install, POSIX notes, builtins table
