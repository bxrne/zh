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

## Builtins

| Command | Description |
|---------|-------------|
| `echo [args]` | Print to stdout |
| `exit [code]` | Exit shell |
| `cd [path]` | Change directory |
| `pwd` | Print working directory |
| `type <cmd>` | Show command type |

