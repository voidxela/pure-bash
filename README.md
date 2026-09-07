# Pure Bash

A Bash-native implementation of the ideas behind [Pure](https://github.com/sindresorhus/pure): a spacious, minimal two-line prompt with useful context that stays fast.

```text
~/dev/pure main* ⇡
❯
```

It is written for Bash rather than emulating Zsh. There is no Zsh compatibility layer, prompt framework, daemon, Python helper, or Node dependency. Git is the only required external tool for Git integration.

## Features

- Pure-style two-line prompt and `❯` prompt symbol.
- Prompt symbol turns red after a failed command.
- Current path, Git branch, dirty state, rebase/merge/cherry-pick state, ahead/behind arrows, and optional stash indicator.
- Git dirty checks and remote checks run in a background Bash worker.
- Command duration appears after the configured threshold.
- Username/host appears for SSH sessions, containers, and root shells.
- Python virtualenv, Conda, and Nix shell integration.
- Optional Node major-version display when a parent directory contains `package.json`.
- Optional dimmed path separators and detailed Git dirty markers.
- Terminal title set to the current path.
- Custom prefix/suffix hook.
- Existing `PROMPT_COMMAND` and `PS0` content is preserved.

## Requirements

- Bash 4.4+
- Git 2.15.2+ for Git features
- A terminal/font capable of displaying the configured Unicode symbols

## Install

Clone or copy this directory somewhere stable, then source `pure.bash` at the end of `~/.bashrc`:

```bash
source "$HOME/.config/pure-bash/pure.bash"
```

Open a new interactive Bash shell. Run `pure_bash_preview` to see every major segment and its current colors.

## Bash-specific behavior

Pure on Zsh can redraw the current prompt when asynchronous work finishes because ZLE exposes a supported prompt-reset API. Bash Readline does not provide an equivalent safe idle-redraw API. Pure Bash therefore renders cheap state such as the path and branch immediately, performs expensive Git work in the background, and consumes completed results at the next prompt. It deliberately does not inject cursor-control redraw tricks while you are typing.

The same limitation means Pure's live `vicmd`/`viins` prompt-symbol reversal is not reproduced. `PURE_PROMPT_VICMD_SYMBOL` is kept as a familiar configuration name for compatibility/future use, but Bash cannot reliably redraw the already-rendered PS1 when Readline changes vi keymaps.

Pure's active-command terminal-title update is also omitted. The title is updated to the current path at each prompt; this avoids a `DEBUG` trap or per-command helper subprocess.

## Git behavior

Branch discovery is synchronous and cheap. Dirty status, stash status, ahead/behind checks, and optional remote refresh happen in a background worker.

When `PURE_GIT_PULL=1` (the default, matching Pure), the worker fetches only the current branch's configured upstream into a temporary `refs/pure-bash/<shell-pid>/upstream` ref, computes divergence, and deletes the ref. It does **not** rewrite the normal `refs/remotes/...` tracking ref. Authentication prompting is disabled for background fetches.

If a dirty check takes more than five seconds, its result is treated as cached and the branch turns red. Further dirty checks are delayed for `PURE_GIT_DELAY_DIRTY_CHECK` seconds (default: 1800), matching Pure's intent for very large repositories.

## Configuration

Set options **before** sourcing `pure.bash`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `PURE_CMD_MAX_EXEC_TIME` | `5` | Show command duration when execution exceeds this many seconds. |
| `PURE_GIT` | `1` | Enable Git integration. |
| `PURE_GIT_PULL` | `1` | Refresh the current upstream in the background. |
| `PURE_GIT_UNTRACKED_DIRTY` | `1` | Include untracked files in dirty checks. |
| `PURE_GIT_DELAY_DIRTY_CHECK` | `1800` | Delay repeated dirty checks after a slow check. |
| `PURE_GIT_DIRTY_DETAILED` | `0` | Show `*` unstaged, `+` staged, `?` untracked instead of one `*`. |
| `PURE_GIT_STASH` | `0` | Show a stash indicator when stashes exist. |
| `PURE_NODE_VERSION` | `0` | Show Node's major version under a `package.json` tree. |
| `PURE_VIRTUALENV` | `1` | Show Python virtualenv/Conda environment. |
| `PURE_NIX_SHELL` | `1` | Show Nix shell name. |
| `PURE_HOST` | `1` | Show hostname when remote/container/root identity is active. |
| `PURE_TITLE` | `1` | Manage the terminal title. |
| `PURE_PATH_SEPARATOR_DIM` | `0` | Dim `/` separators in the path. |

### Symbols

```bash
PURE_PROMPT_SYMBOL='❯'
PURE_SUSPENDED_JOBS_SYMBOL='✦'
PURE_GIT_DOWN_ARROW='⇣'
PURE_GIT_UP_ARROW='⇡'
PURE_GIT_STASH_SYMBOL='≡'
PURE_NODE_VERSION_SYMBOL='⬢'
```

Set a symbol to an empty string where that segment supports disabling it, such as `PURE_SUSPENDED_JOBS_SYMBOL=''` or `PURE_GIT_STASH_SYMBOL=''`.

### Colors

Colors accept `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, `default`, a 0–255 palette index, or `#RRGGBB` true color.

```bash
PURE_COLOR_PATH=white
PURE_COLOR_PROMPT_SUCCESS='#c678dd'
PURE_COLOR_GIT_DIRTY=218
source "$HOME/.config/pure-bash/pure.bash"
```

Available color variables:

```text
PURE_COLOR_CUSTOM_PREFIX       PURE_COLOR_CUSTOM_SUFFIX
PURE_COLOR_EXECUTION_TIME      PURE_COLOR_GIT_ARROW
PURE_COLOR_GIT_STASH           PURE_COLOR_GIT_BRANCH
PURE_COLOR_GIT_BRANCH_CACHED   PURE_COLOR_GIT_ACTION
PURE_COLOR_GIT_DIRTY           PURE_COLOR_HOST
PURE_COLOR_NODE_VERSION        PURE_COLOR_PATH
PURE_COLOR_PROMPT_ERROR        PURE_COLOR_PROMPT_SUCCESS
PURE_COLOR_PROMPT_CONTINUATION PURE_COLOR_SUSPENDED_JOBS
PURE_COLOR_USER                PURE_COLOR_USER_ROOT
PURE_COLOR_VIRTUALENV
```

### Custom prefix and suffix

Define `pure_bash_precustom` after sourcing the prompt. It is called on each prompt render, so keep it fast.

```bash
pure_bash_precustom() {
    PURE_BASH_CUSTOM_PREFIX=${KUBE_CONTEXT:-}
    PURE_BASH_CUSTOM_SUFFIX=$(date +%H:%M)
}
```

For expensive commands, update a cached variable elsewhere and only read it from the hook.

## Diagnostics

```bash
pure_bash_preview
pure_bash_system_report
```

## Design notes

Command timing uses Bash's `PS0`, which is expanded after a complete command is read and immediately before it executes. Pure Bash uses a zero-length parameter substring containing an arithmetic assignment to stamp Bash's built-in `SECONDS` counter. This avoids the `DEBUG` trap commonly used by Bash prompt frameworks and avoids measuring time spent merely typing at the prompt.

Dynamic prompt text is held in variables referenced by PS1 rather than interpolated into executable prompt expansions. Control characters are stripped from displayed path/environment data. This avoids turning unusual Git/path text into prompt-time command substitutions or terminal control sequences.

## License and attribution

Pure Bash is released into the public domain under [The Unlicense](LICENSE).

Pure Bash is an independent Bash implementation inspired by the behavior and visual design of Sindre Sorhus's Pure prompt. Pure is MIT licensed; its upstream license notice is included in `UPSTREAM-LICENSE`.
