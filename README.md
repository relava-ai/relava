# relava

Personal knowledge-base sync for [Claude Code](https://claude.com/claude-code) —
multi-machine, git-based, no daemon.

`relava` keeps your Claude Code agents, skills, commands, and per-project auto-memory
in sync across every machine you use, via a plain git repo and a few Claude Code
hooks. No server, no account, no background process — sync happens on the turn
boundaries Claude Code already gives you (`SessionStart`, `UserPromptSubmit`, `Stop`).

It also bootstraps a personal knowledge wiki (the
[LLM-wiki pattern](https://karpathy.bearblog.dev/) — sources, pages, index, log) that
compounds across sessions and machines the same way.

## Install

```
curl -fsSL https://raw.githubusercontent.com/relava-ai/relava/main/install.sh | bash
```

or, if you'd rather not curl-pipe-bash:

```
git clone https://github.com/relava-ai/relava.git
cd relava
bash install.sh
```

Either way, `install.sh`:
1. Puts a stable copy of this tool at `~/.relava/src` (or reuses the checkout you're
   already in, if run the second way).
2. Installs a `relava` command to `~/.local/bin` — a small dispatcher that forwards to
   the real scripts (see [Layout](#layout)). Prints instructions if that directory
   isn't already on your `PATH`, rather than editing your shell config for you.
3. Runs first-run setup: checks for `git`/`gh`, and — if `gh` is authenticated —
   offers to create a private GitHub repo for your personal knowledge base. Decline
   and it falls back to a local-only repo (`git init`, no remote); add one later.

Safe to re-run — every step is idempotent.

**Windows**: runs via [Git Bash](https://gitforwindows.org/) (bundled with Git for
Windows, which you already need for `git` itself). `relava` works the same from Git
Bash as it does from a native `cmd.exe`/PowerShell prompt — `install.sh` also writes a
small `.cmd` shim so native shells find it too, routed through Git Bash underneath.

## What gets synced

- `~/.claude/agents/`, `~/.claude/skills/`, `~/.claude/commands/` — symlinked
  (macOS/Linux) or copied (Windows) to/from your kb repo, so anything you add on one
  machine shows up on the next.
- `CLAUDE.md`'s wiki import line — kept pointed at your personal wiki.
- Claude Code auto-memory — copied per-project (never across projects), filtered
  through the denylist below first.
- Your personal wiki (`wiki/` in the kb repo, bootstrapped from `wiki-template/` on
  first run).

Sync runs automatically via three Claude Code hooks, wired into
`~/.claude/settings.json` by `bootstrap.sh`:

| Event | Action |
|---|---|
| `SessionStart` | full sync: pull, then push any local work |
| `UserPromptSubmit` | pull only — start of turn, pick up anything new |
| `Stop` | push only if there's something to send — end of turn |

Every check is local first; `push` makes no network call at all when there's nothing
to send.

## Multi-machine

First run creates a repo. On a second machine, point `relava init` at that same repo
instead of creating a new one:

```
relava init git@github.com:you/your-kb-repo.git
```

It clones the existing repo, wires the same hooks, and you're syncing across both
machines from then on — ordinary `git pull --rebase`/`push` under the hood, with
denylist enforcement and lock-based serialization on top.

(No `relava` on `PATH` yet? The same thing works directly:
`bash sync/bootstrap.sh git@github.com:you/your-kb-repo.git`, or
`RELAVA_KB_REMOTE=... bash sync/bootstrap.sh`.)

## Multiple git/GitHub accounts

If you use more than one GitHub account on the same machine (personal + work, say),
there are two separate things that can go wrong — worth knowing about even though
only the first one is something `relava` actively checks for.

**`gh` CLI account.** `gh` operates against whichever account is currently "active,"
with no other signal — `relava init` could otherwise silently create your kb repo
under the wrong one. `init.sh` detects when more than one account is logged in, shows
which one is active, and asks for confirmation before creating anything:

```
$ gh auth switch --hostname github.com --user <the-account-you-want>
$ relava init
```

**SSH identity for `git clone`/`push`/`pull`.** This is a plain git/SSH concern, not
something `relava` manages — but it's the more common way multi-account setups
actually break (auth failures on push, or pushing as the wrong identity entirely). If
your default SSH key isn't the one authorized for the account you want to use, add a
host alias in `~/.ssh/config`:

```
Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
```

then use `git@github-work:you/your-kb-repo.git` (instead of `github.com`) anywhere
you'd give `relava init`/`bootstrap.sh` a repo URL — `ssh` routes through the right
key automatically from then on.

**Commit author identity.** `sync.sh`'s auto-generated commits use your machine's
default `git config user.name`/`user.email`. If you want commits in your kb repo
attributed to something else, set a local override once, inside the kb repo itself:

```
git -C ~/.relava/kb config user.name "Your Name"
git -C ~/.relava/kb config user.email "you@example.com"
```

## Safety: the denylist

`sync/denylist.txt` lists glob patterns (`*.pem`, `*credential*`, `.env`, SSH private
keys, etc.) checked against every file before it's ever read or committed. Every sync
adapter checks it before reading a source file; `sync.sh` itself checks it again as a
last line of defense before committing — a denylisted file gets unstaged and left in
your working tree, never entering git history.

Add your own patterns (one glob per line) if you have other local files that should
never sync.

## Configuration

All optional — sane defaults if unset.

| Variable | Default | Purpose |
|---|---|---|
| `RELAVA_KB_DIR` | `~/.relava/kb` | Where your personal kb repo lives |
| `RELAVA_CLAUDE_DIR` | `~/.claude` | Your Claude Code config directory |
| `RELAVA_KB_REMOTE` | _(unset)_ | Remote URL to clone from on first bootstrap |
| `RELAVA_KB_REPO_NAME` | `kb-$(whoami)` | Name used when `init.sh` auto-creates a GitHub repo |
| `RELAVA_SRC_DIR` | `~/.relava/src` | Where `install.sh` keeps this tool's own source |
| `RELAVA_BIN_DIR` | `~/.local/bin` | Where `install.sh` installs the `relava` command |

## Layout

```
install.sh                installs the `relava` command + runs first-run setup
sync/                   bash: hook-invoked pull/push, no daemon
  sync.sh               pull | push | full
  init.sh               friendly first-run entry point
  bootstrap.sh           one-time hook wiring + kb repo setup
  denylist.txt           shared secret-pattern denylist
  relava.tpl             template for the installed `relava` command
  adapters/
    claude_code.sh        reconciles ~/.claude/{agents,skills,commands}
  tests/
    nuke-and-restore.sh    delete everything, re-bootstrap, verify full recovery
wiki-template/           personal wiki skeleton, bootstrapped into your kb repo
```

## The `relava` command

Installed by `install.sh`, on `PATH`, forwarding to the scripts above:

```
relava init [<existing-repo-url>]   first-run setup, or join an existing kb repo
relava sync [pull|push|full]        manually run a sync (normally automatic via hooks)
```

Deliberately thin — if this ever becomes a compiled binary instead of bash, only the
command itself changes; everything that already types `relava init`/`relava sync`
keeps working.

## License

MIT — see [LICENSE](LICENSE).
