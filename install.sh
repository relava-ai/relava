#!/usr/bin/env bash
# relava installer. Ensures a stable copy of this tool's source lives at
# RELAVA_SRC_DIR, installs a `relava` command onto PATH that forwards to it,
# then runs first-run setup (sync/init.sh).
#
# Cross-platform: macOS, Linux, and Windows via Git Bash — the same
# environment Claude Code's own hook commands already invoke bash through
# (see sync/bootstrap.sh's hook wiring, and sync/adapters/claude_code.sh's
# existing is_windows() handling). git is already a hard dependency of this
# tool, and Git for Windows bundles Git Bash by default, so no separate
# PowerShell/cmd.exe implementation is maintained — a small relava.cmd shim
# lets native Windows shells find `relava` too, routed through Git Bash.
#
# Run:  curl -fsSL https://raw.githubusercontent.com/relava-ai/relava/main/install.sh | bash
#   or: git clone https://github.com/relava-ai/relava.git && cd relava && bash install.sh

set -uo pipefail

SRC_DIR="${RELAVA_SRC_DIR:-$HOME/.relava/src}"
BIN_DIR="${RELAVA_BIN_DIR:-$HOME/.local/bin}"
REPO_URL="${RELAVA_REPO_URL:-https://github.com/relava-ai/relava.git}"

is_windows() {
    case "$(uname -s 2>/dev/null || echo unknown)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
    esac
    [ -n "${OS:-}" ] && [ "$OS" = "Windows_NT" ]
}

command -v git > /dev/null 2>&1 || {
    echo "relava install: git is required, not found in PATH" >&2
    exit 1
}

# 1. Ensure a stable copy of the tool source exists at SRC_DIR.
#    - If SRC_DIR already exists as a git checkout, update it in place.
#    - Else if this script is itself running from inside a real checkout of
#      *this* repo (has sync/relava.tpl and .git as siblings — true for
#      `git clone` + `bash install.sh`), use that checkout directly rather
#      than cloning a second copy.
#    - Otherwise (curl | bash — no real script file, so no meaningful
#      SCRIPT_DIR at all), clone fresh.
#
# BASH_SOURCE[0] must resolve to a real, existing file before we trust it
# for checkout detection — under `curl | bash`, bash reads the script from
# a pipe with no backing file, BASH_SOURCE is empty, and $0 falls back to
# the literal string "bash". dirname("bash") is ".", which used to resolve
# to whatever the *invoking shell's* cwd happened to be — a false positive
# if that directory happened to contain an unrelated repo with its own
# sync/ folder (this bit us for real: relava-pipeline, this tool's own
# private sibling repo, still has a pre-split sync/ copy). Never fall back
# to $0 here; an empty SCRIPT_DIR correctly always falls through to "clone
# fresh". Checking for sync/relava.tpl specifically (not just a sync/
# directory) is a second layer of the same fix — that file only exists in
# this actual repo, not in any other repo that merely happens to have a
# directory named sync/.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if [ -d "$SRC_DIR/.git" ]; then
    echo "relava install: updating existing checkout at $SRC_DIR"
    git -C "$SRC_DIR" pull --quiet --ff-only \
        || echo "relava install: could not fast-forward $SRC_DIR — leaving as-is" >&2
elif [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/sync/relava.tpl" ] && [ -d "$SCRIPT_DIR/.git" ]; then
    echo "relava install: using existing checkout at $SCRIPT_DIR"
    SRC_DIR="$SCRIPT_DIR"
else
    echo "relava install: cloning to $SRC_DIR"
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone --quiet "$REPO_URL" "$SRC_DIR"
fi

# 2. Install the `relava` dispatcher command from its checked-in template
#    (sync/relava.tpl), substituting the real SRC_DIR path. Plain bash
#    string replacement, not sed -i, to avoid GNU/BSD sed flag differences.
mkdir -p "$BIN_DIR"

template="$(cat "$SRC_DIR/sync/relava.tpl")"
printf '%s\n' "${template//__SRC_DIR__/$SRC_DIR}" > "$BIN_DIR/relava"
chmod +x "$BIN_DIR/relava"

# Windows-only: a .cmd shim so native shells (cmd.exe, PowerShell) that
# don't understand shebangs can also find `relava` on PATH, routing through
# Git Bash (already a hard dependency, same assumption bootstrap.sh's hook
# commands already make).
if is_windows; then
    printf '@echo off\r\nbash "%%~dp0relava" %%*\r\n' > "$BIN_DIR/relava.cmd"
fi

echo "relava install: installed \`relava\` to $BIN_DIR"

# 3. PATH check — report, don't silently edit shell rc files or the Windows
#    registry on the user's behalf.
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        echo
        echo "$BIN_DIR is not on your PATH yet. Add it, then restart your shell:"
        if is_windows; then
            echo "  setx PATH \"%PATH%;$BIN_DIR\"   (from cmd.exe or PowerShell)"
        else
            echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.bashrc   (or ~/.zshrc, etc.)"
        fi
        echo
        ;;
esac

# 4. Hand off to first-run setup.
echo "relava install: running first-run setup"
bash "$SRC_DIR/sync/init.sh"
