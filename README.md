# zh - Minimal Shell

A minimal, POSIX-like shell written in Zig.

Implements core shell features: command execution, I/O redirection, pipelines, history, and common builtins.

## Features

###  Completed

- **Builtins**: `echo`, `exit`, `cd`, `pwd`, `type`
- **External Commands**: PATH-based executable resolution
- **Argument Parsing**: Quoted strings and escape sequences
- **I/O Redirection**: `>`, `>>`, `<` operators
- **Pipelines**: Multi-command piping with `|`
- **History**: In-memory storage with persistence
- **File Completion**: Directory and filename auto-completion

### TODO

- Command name completion
- Completion suggestions refinement
- Signal handling
- Job control
- Alias support
- Glob pattern expansion

## Building

```bash
zig build
```

## Running

```bash
zig build run
```

## Builtins

| Command | Description |
|---------|-------------|
| `echo [args]` | Print to stdout |
| `exit [code]` | Exit shell |
| `cd [path]` | Change directory |
| `pwd` | Print working directory |
| `type <cmd>` | Show command type |

