#!/bin/bash
# setup-workspace-mac.sh — a ready-to-use VS Code setup for several languages on macOS:
# one colour-coded profile per language with its toolchain and extensions, Claude Code as the
# built-in agent, and a launcher app that opens each workspace with its profile.
# macOS version of setup-workspace.sh (same features, same files).
#
#   ~/Applications/VS Launcher.app   pick a workspace (Spotlight, Launchpad)
#   <root>/Workspace/<language>/     scratch/, projects/, templates/, the workspace's Claude rules
#   <root>/Workspace/setup_manager/  README.md, installed.txt (what was added), logs, this script
#
# Start it in Terminal as your normal user (it asks for your password when it installs things):
#   bash setup-workspace-mac.sh          windows to pick languages and options
#   bash setup-workspace-mac.sh --help   all options
# Everything it adds is listed in setup_manager/installed.txt; --uninstall removes exactly that.
#
# Written for the bash 3.2 that macOS ships: no associative arrays, no mapfile, no ${x,,}.
# "sh file" on a Mac is bash in POSIX mode: it would run on and fail in the middle.
if [ -z "${BASH_VERSION:-}" ] || (shopt -oq posix) 2>/dev/null; then echo "Please start this with: bash $0" >&2; exit 1; fi
set -Eeo pipefail   # no -u: bash 3.2 treats an empty array as unset. -E: the ERR trap below also works in functions
SYSTEM_LANG=${LANG:-}
# The script reads the tools' output and compares sorted lists: same language and order everywhere.
if locale -a 2>/dev/null | grep -qi '^en_US.UTF-8$'; then export LC_ALL=en_US.UTF-8; else export LC_ALL=C; fi
unset PYTHONHOME PYTHONPATH   # would redirect every Python below
export NODE_NO_WARNINGS=1     # VS Code's command line prints deprecation warnings
# Homebrew's bash 5.2+ would treat "&" in ${x//@ROOT@/$ROOT} as "the match" (not in bash 3.2).
shopt -u patsub_replacement 2>/dev/null || true

SCRIPT_VERSION=1.0

# Where the published script can be downloaded. Started as a pasted one-liner (curl | bash) there is
# no file to copy into setup_manager/scripts/, so it is downloaded from here instead. Set when publishing.
SOURCE_URL=""

# ─── Profiles ─────────────────────────────────────────────────────────────────────────────────
# key|profile name|icon|background R G B|extensions|brew formulas|brew casks|description
# The key is also the workspace folder name. Icons: https://code.visualstudio.com/api/references/icons-in-labels
PROFILE_TABLE='
python|Python|snake|0 40 110|ms-python.python ms-python.vscode-pylance ms-python.debugpy ms-toolsai.jupyter|||Python 3, notebooks, debugger, ready environment (numpy, pandas, matplotlib)
cpp|C++|chip|90 68 0|llvm-vs-code-extensions.vscode-clangd vadimcn.vscode-lldb|||Apple clang compiler, clangd code help, debugger
latex|LaTeX|mortar-board|58 0 95|james-yu.latex-workshop||basictex|BasicTeX + LaTeX Workshop: PDF builds on save (about 400 MB)
bash|Bash|terminal-linux|10 80 10|mads-hartmann.bash-ide-vscode timonwong.shellcheck|bash shellcheck||Shell scripts with a current Bash and ShellCheck
rust|Rust|robot|95 38 0|rust-lang.rust-analyzer vadimcn.vscode-lldb|||Rust toolchain (rustup), rust-analyzer, debugger
'
ALL_KEYS=$(awk -F'|' 'NF > 1 { printf "%s ", $1 }' <<< "$PROFILE_TABLE")
ALL_KEYS=${ALL_KEYS% }
p_field() { awk -F'|' -v k="$1" -v n="$2" '$1 == k { print $n }' <<< "$PROFILE_TABLE"; }  # key column
p_name() { p_field "$1" 2; }
DEFAULT_PROFILES=python,cpp,latex,bash
BASE_EXTENSIONS="usernamehw.errorlens formulahendry.code-runner anthropic.claude-code"
BASE_FORMULAS="python"
TEX_PACKAGES="latexmk collection-latexrecommended collection-fontsrecommended"
PY_PACKAGES="numpy pandas matplotlib ipykernel"
SETUP_MANAGER_NAME="Setup Manager"
SETUP_MANAGER_RGB="40 40 40"
COMMON_SETTINGS='"files.eol": "\n", "files.insertFinalNewline": true, "chat.disableAIFeatures": true, "code-runner.runInTerminal": true, "code-runner.saveFileBeforeRun": true, "code-runner.fileDirectoryAsCwd": true, "code-runner.ignoreSelection": true, "python.terminal.executeInFileDir": true, "code-runner.executorMap": {"python": "\"$pythonPath\" -u $fullFileName"}'
BYPASS_SETTINGS='"claudeCode.allowDangerouslySkipPermissions": true, "claudeCode.initialPermissionMode": "bypassPermissions"'

usage() {
    cat <<EOF
Usage: bash setup-workspace-mac.sh [options]        (version $SCRIPT_VERSION)

Windows ask which languages to set up. With --no-gui it installs the default set: $DEFAULT_PROFILES.

  --profiles LIST   languages to set up, comma-separated (available: $ALL_KEYS)
  --add LIST        add languages to an existing setup
  --root DIR        where everything goes (default: ~/Code)
  --no-bypass       Claude Code asks before each action (default: bypass mode, it doesn't)
  --no-gui          terminal only, no windows
  --check           test that the installed languages work; changes nothing
  --uninstall       remove what setup_manager/installed.txt lists (asks first)
  -h, --help        this text
EOF
}

# ─── Options ──────────────────────────────────────────────────────────────────────────────────
DIED=0
die() { DIED=1; printf 'error: %s\n' "$*" >&2; exit 1; }
ROOT="" PROFILES="" ADD="" BYPASS="" NO_GUI=0 UNINSTALL=0 CHECK=0
while (($#)); do
    case $1 in
        --profiles) [[ $# -ge 2 ]] || die "--profiles needs a value"; PROFILES=$2; shift ;;
        --profiles=*) PROFILES=${1#*=} ;;
        --add) [[ $# -ge 2 ]] || die "--add needs a value"; ADD=$2; shift ;;
        --add=*) ADD=${1#*=} ;;
        --root) [[ $# -ge 2 ]] || die "--root needs a value"; ROOT=$2; shift ;;
        --root=*) ROOT=${1#*=} ;;
        --no-bypass) BYPASS=0 ;;
        --no-gui) NO_GUI=1 ;;
        --check) CHECK=1 ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

abs_path() { # no realpath -m on macOS; the path need not exist yet
    local p=$1
    [[ $p == /* ]] || p=$PWD/$p
    while [[ $p == */ && $p != / ]]; do p=${p%/}; done
    printf '%s' "$p"
}

# Run from its copy in Workspace/setup_manager/scripts/, the script belongs to that setup.
SELF=""
if [[ -f ${BASH_SOURCE[0]:-} ]]; then SELF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}"); fi
if [[ -z $ROOT && $SELF == */Workspace/setup_manager/scripts/setup-workspace-mac.sh ]]; then
    ROOT=${SELF%/Workspace/setup_manager/scripts/setup-workspace-mac.sh}
fi
# Not ~/Documents: iCloud often syncs it (venvs, build folders), and macOS asks before programs may use it.
ROOT=$(abs_path "${ROOT:-$HOME/Code}")
WS=$ROOT/Workspace
SM=$WS/setup_manager
MANIFEST=$SM/installed.txt
CONF=$SM/setup.conf
VENV=$WS/.venv
VSC_DIR="$HOME/Library/Application Support/Code"
VSC_USER=$VSC_DIR/User
STORAGE=$VSC_USER/globalStorage/storage.json
STATE_DB=$VSC_USER/globalStorage/state.vscdb
VSC_APP="/Applications/Visual Studio Code.app"
APP_DIR=$HOME/Applications
LAUNCHER_APP=$APP_DIR/VS\ Launcher.app
KERNEL_DIR=$HOME/Library/Jupyter/kernels/workspace-venv
TEXBIN=/Library/TeX/texbin
ZPROFILE=$HOME/.zprofile
BLOCK_BEGIN='# >>> setup-workspace >>>'
BLOCK_END='# <<< setup-workspace <<<'
SKILLS=$HOME/.claude/skills
MARKER='<!-- installed by setup-workspace.sh -->'
TODAY=$(date +%F)
TRASH=$ROOT/Trash/$TODAY
LOG=""
FAILED=() NOTES=()

# ─── Output, questions ────────────────────────────────────────────────────────────────────────
exec 4>&1
say()   { printf '%s\n' "$*" >&4; if [[ -n $LOG ]]; then printf '%s\n' "$*" >> "$LOG"; fi; }
# Output in the terminal and the log, no input: Homebrew's installer could wait for a key nobody can see.
quiet() { if [[ -n $LOG ]]; then "$@" </dev/null 2>&1 | tee -a "$LOG" >&4; else "$@" </dev/null >&4 2>&1; fi; }
show()  { if [[ $1 == "$HOME"* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi; }
lower() { tr '[:upper:]' '[:lower:]' <<< "$1"; }

# Dialogs need the logged-in desktop session (not ssh).
GUI=0
if ((!NO_GUI)) && [[ $(launchctl managername 2>/dev/null) == Aqua ]]; then GUI=1; fi
TTY=0
if ( : </dev/tty ) 2>/dev/null; then TTY=1; fi

# Exit 2 = the dialog could not open at all (not a Cancel): the caller carries on in Terminal.
osa() {
    local err rc=0
    err=$(mktemp)
    osascript "$@" 2>"$err" || rc=$?
    if ((rc)) && ! grep -q '(-128)' "$err"; then rc=2; fi
    rm -f "$err"
    return $rc
}
cancelled() { say "Cancelled."; exit 0; }
as_text() { # AppleScript string literal
    local s=${1//\\/\\\\}
    printf '"%s"' "${s//\"/\\\"}"
}
info() {
    say "$1"
    if ((GUI)); then osa -e "display dialog $(as_text "$1") with title \"VS Code setup\" buttons {\"OK\"} default button \"OK\"" >/dev/null || true; fi
}
net_hint() { # did the last lines of the log come from a lost connection?
    if [[ -n $LOG ]] && tail -n 30 "$LOG" | grep -qiE 'Failed to (connect|download)|Download failed|Temporary failure|Could not resolve|Could not connect|Connection (timed out|reset|refused)|Network is unreachable|ReadTimeoutError|NewConnectionError|curl: \([0-9]+\)'; then
        printf '\n\nThis looks like a lost internet connection: check it first.'
    fi
}
fail() {
    if [[ $1 != *internet* ]]; then set -- "$1$(net_hint)"; fi
    set -- "$1${LOG:+

Details: $(show "$LOG")}"
    if ((GUI)); then osa -e "display alert \"VS Code setup\" message $(as_text "$1") as critical" >/dev/null || true; fi
    die "$1"
}
ask() { # ask "question" [ok-label] -> success = yes
    if ((GUI)); then
        say "Waiting for your answer in the window (it may be behind this one)..."
        local rc=0
        osa -e "display dialog $(as_text "$1") with title \"VS Code setup\" buttons {\"Cancel\", $(as_text "${2:-Yes}")} default button $(as_text "${2:-Yes}") cancel button \"Cancel\"" >/dev/null || rc=$?
        if ((rc != 2)); then return $rc; fi
        GUI=0; say "(Windows can't open here: asking in Terminal.)"
    fi
    ((TTY)) || return 0
    local reply
    read -rp "$1 [Y/n] " reply </dev/tty || reply=""
    [[ $(lower "$reply") != n* ]]
}
choose() { # choose "prompt" "default items (lines)" items (lines) -> chosen lines; fails on Cancel
    local list defaults
    say "Waiting for your answer in the window (it may be behind this one)..."
    list=$(while IFS= read -r l; do if [[ -n $l ]]; then printf '%s, ' "$(as_text "$l")"; fi; done <<< "$3")
    defaults=$(while IFS= read -r l; do if [[ -n $l ]]; then printf '%s, ' "$(as_text "$l")"; fi; done <<< "$2")
    osa -e "set r to choose from list {${list%, }} with title \"VS Code setup\" with prompt $(as_text "$1") default items {${defaults%, }} with multiple selections allowed and empty selection allowed" \
        -e 'if r is false then error number -128' \
        -e 'set AppleScript'"'"'s text item delimiters to linefeed' -e 'return r as text'
}

STEP_NO=0 STEP_COUNT=1 CURRENT_STEP="" SUDO_KEEPER=""
progress_start() { STEP_COUNT=$1 STEP_NO=0; }
step() { # progress is shown in Terminal: there is no built-in macOS progress window for scripts
    CURRENT_STEP=$1
    STEP_NO=$((STEP_NO + 1))
    say "== [$STEP_NO/~$STEP_COUNT] $1"
}

# Any unexpected failure (set -e) ends up here: say where it stopped and where the details are.
on_exit() {
    local code=$1
    if [[ -n $SUDO_KEEPER ]]; then kill "$SUDO_KEEPER" 2>/dev/null || true; fi
    if ((${LOCKED:-0})); then rm -rf "$LOCK"; fi
    if ((code != 0)); then record_new_brew; fi
    ((code != 0 && !DIED)) || return 0
    local msg="Setup stopped during: ${CURRENT_STEP:-preparation} (exit code $code)."
    if [[ -n ${STOPPED_AT:-} ]]; then
        msg+=$'\n'"Stopped at ${STOPPED_AT:0:200}"
        if [[ -n $LOG ]]; then printf '%s\n' "Stopped at $STOPPED_AT" >> "$LOG"; fi
    fi
    msg+=$(net_hint)
    if [[ -n $LOG ]]; then msg+=$'\n\nDetails: '"$(show "$LOG")"$'\n\nLast lines:\n'"$(tail -n 8 "$LOG" | cut -c1-110)"; fi
    msg+=$'\n\nOnce the cause is fixed, running the script again continues where it stopped.'
    if ((GUI)); then osa -e "display alert \"VS Code setup\" message $(as_text "$msg") as critical" >/dev/null || true; fi
    printf '\n%s\n' "$msg" >&2
}
trap 'STOPPED_AT="line $LINENO: $BASH_COMMAND"' ERR
trap 'on_exit $?' EXIT

# ─── Sudo (Homebrew, BasicTeX) ────────────────────────────────────────────────────────────────
need_sudo() {
    [[ -z $SUDO_KEEPER ]] || return 0
    if ! id -Gn | tr ' ' '\n' | grep -qx admin; then
        fail "This account is not an administrator, so it can't install software. Log in as an administrator (System Settings > Users & Groups), then start the setup again."
    fi
    if ! sudo -n true 2>/dev/null; then
        ((TTY)) || fail "The password is asked in Terminal: start the script from Terminal."
        printf '\a' >&4
        say ""
        say ">>> Click into this Terminal window and type your Mac login password (not your Apple ID), then press Return."
        say ">>> Nothing appears on screen while you type; that's normal."
        local tries
        for tries in 1 2 3; do
            if sudo -v </dev/tty; then break; fi
            if ((tries == 3)); then fail "Wrong password three times."; fi
        done
    fi
    # Keep the sudo login fresh: downloads can outlast its 5 minutes.
    ( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &
    SUDO_KEEPER=$!
    disown "$SUDO_KEEPER" 2>/dev/null || true   # no "Terminated" message when it is stopped at the end
}

# ─── Manifest (installed.txt): one "kind<TAB>value..." line per thing this script added ───────
record() { local IFS=$'\t'; printf '%s\n' "$*" >> "$MANIFEST"; }
recorded() { [[ -f $MANIFEST ]] && grep -qxF -- "$(IFS=$'\t'; printf '%s' "$*")" "$MANIFEST"; }
manifest_lines() { # kind -> the values of all lines of that kind (tab-separated)
    if [[ -f $MANIFEST ]]; then awk -F'\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print }' "$MANIFEST"; fi
}
unrecord() { # kind value... -> drop that exact line
    local line
    line=$(IFS=$'\t'; printf '%s' "$*")
    grep -vxF -- "$line" "$MANIFEST" > "$MANIFEST.tmp" || true
    mv "$MANIFEST.tmp" "$MANIFEST"
}

# put FILE [MODE] < content — create FILE unless it exists (never overwrites); @ROOT@ is replaced.
put() {
    local file=$1 mode=${2:-644} content
    content=$(cat)
    [[ ! -e $file ]] || return 0
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "${content//@ROOT@/$ROOT}" > "$file"
    chmod "$mode" "$file"
    record file "$file"
}
mkd() { local d; for d; do if [[ ! -d $d ]]; then mkdir -p "$d"; record dir "$d"; fi; done; }

# ─── Tools ────────────────────────────────────────────────────────────────────────────────────
BREW="" BREW_PREFIX="" CODE="" PYTHON=""
find_brew() {
    local b
    # Only the Apple Silicon one: a /usr/local Homebrew migrated from an Intel Mac can't run or install here.
    b=/opt/homebrew/bin/brew
    if [[ -x $b ]]; then BREW=$b; BREW_PREFIX=${b%/bin/brew}; return 0; fi
    return 1
}
find_code() {
    local c
    for c in ${BREW_PREFIX:+"$BREW_PREFIX/bin/code"} "$VSC_APP/Contents/Resources/app/bin/code" "$APP_DIR/Visual Studio Code.app/Contents/Resources/app/bin/code"; do
        if [[ -x $c ]]; then CODE=$c; return 0; fi
    done
    return 1
}
code_cli() { "$CODE" "$@"; }

vscode_running() { pgrep -u "$(id -u)" -f 'Visual Studio Code.app/Contents/MacOS/' >/dev/null 2>&1; }
close_vscode() { # VS Code rewrites its profile list when it exits, so it must be closed meanwhile
    vscode_running || return 0
    if [[ ${TERM_PROGRAM:-} == vscode || -n ${VSCODE_PID:-} ]]; then
        fail "This runs inside VS Code's terminal, and VS Code has to be closed while the setup changes its profiles. Quit VS Code and run the same command in Terminal."
    fi
    ask "VS Code is open. It has to be closed while the setup changes its profiles.
Unsaved files are kept (VS Code restores them).

Close VS Code now?" "Close VS Code" || cancelled
    # macOS may ask whether Terminal may control VS Code; if that is denied, the user quits it.
    osa -e 'quit app "Visual Studio Code"' >/dev/null ||
        ask "Please quit VS Code yourself (Cmd+Q in VS Code), then click Continue." "Continue" || cancelled
    for _ in {1..40}; do vscode_running || return 0; sleep 0.5; done
    fail "VS Code did not close. Quit it yourself (Cmd+Q) and start the setup again."
}

# JSON / state edits (VS Code's profile list, settings and trusted folders).
PY_HELPER=$(cat <<'PY'
import json, os, secrets, sys

def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w") as f:
        json.dump(data, f, indent=4)
        f.write("\n")
    os.replace(path + ".tmp", path)

def hexcol(r, g, b):
    return f"#{r:02x}{g:02x}{b:02x}"

def scheme(r, g, b):
    dark = hexcol(int(r * 0.6), int(g * 0.6), int(b * 0.6))
    mid = hexcol(r, g, b)
    lite = hexcol(min(int(r * 1.5), 255), min(int(g * 1.5), 255), min(int(b * 1.5), 255))
    keys_dark = ["sideBar.background", "sideBarSectionHeader.background", "activityBar.background",
                 "panel.background", "statusBar.background", "statusBar.noFolderBackground",
                 "titleBar.activeBackground", "titleBar.inactiveBackground",
                 "editorGroupHeader.tabsBackground", "tab.inactiveBackground",
                 "notificationCenterHeader.background", "peekViewResult.background",
                 "debugToolBar.background"]
    keys_mid = ["editor.background", "tab.activeBackground", "tab.selectedBackground",
                "terminal.background", "menu.background", "dropdown.listBackground",
                "notifications.background", "peekViewEditor.background", "breadcrumb.background"]
    keys_lite = ["quickInput.background", "dropdown.background", "editorWidget.background",
                 "input.background", "welcomePage.tileBackground"]
    colors = {**{k: dark for k in keys_dark}, **{k: mid for k in keys_mid}, **{k: lite for k in keys_lite}}
    colors["titleBar.activeForeground"] = "#cccccc"
    colors["titleBar.inactiveForeground"] = "#999999"
    return colors

cmd, *args = sys.argv[1:]

if cmd in ("trust", "untrust"):  # STATE_DB FOLDER - VS Code's list of trusted folders (covers subfolders)
    import sqlite3
    from urllib.parse import quote
    # VS Code keeps this list in the shared database once it has been started; before that it
    # copies it from the old one. So: always the old one, and the shared one if it exists.
    shared = os.path.expanduser("~/.vscode-shared/sharedStorage/state.vscdb")
    for state_db in [args[0]] + ([shared] if os.path.exists(shared) else []):
        os.makedirs(os.path.dirname(state_db), exist_ok=True)
        db = sqlite3.connect(state_db)
        db.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
        row = db.execute("SELECT value FROM ItemTable WHERE key = 'content.trust.model.key'").fetchone()
        trust = json.loads(row[0]) if row else {"uriTrustInfo": []}
        p = args[1]
        entries = [e for e in trust.get("uriTrustInfo", []) if e.get("uri", {}).get("path") != p]
        if cmd == "trust":
            entries.append({"uri": {"$mid": 1, "fsPath": p, "external": "file://" + quote(p), "path": p, "scheme": "file"}, "trusted": True})
        trust["uriTrustInfo"] = entries
        db.execute("INSERT INTO ItemTable VALUES ('content.trust.model.key', ?)", (json.dumps(trust),))
        db.commit()
        db.close()
    sys.exit(0)

if cmd == "workspace-file":     # OUT name=path... -> a .code-workspace file (JSON-escaped)
    folders = [{"path": a.split("=", 1)[1], "name": a.split("=", 1)[0]} for a in args[1:]]
    save(args[0], {"folders": folders})
    sys.exit(0)

try:
    data = load(args[0])
except ValueError:   # VS Code allows comments in settings files; Python's json does not
    print(f"{args[0]}: not plain JSON (comments?), left unchanged", file=sys.stderr)
    sys.exit(0 if cmd in ("settings", "set-keys", "del-keys") else 3)
profiles = data.get("userDataProfiles", [])

if cmd == "name-of":            # STORAGE LOCATION -> current name of that profile, or nothing
    print(next((p.get("name", "") for p in profiles if p.get("location") == args[1]), ""))

elif cmd == "free-name":        # STORAGE NAME -> NAME, or "NAME 2", "NAME 3"... if taken
    taken = {p.get("name") for p in profiles}
    name, n = args[1], 1
    while name in taken:
        n += 1
        name = f"{args[1]} {n}"
    print(name)

elif cmd == "add-profile":      # STORAGE NAME ICON -> new location
    location = secrets.token_hex(4)
    data.setdefault("userDataProfiles", []).append({"location": location, "name": args[1], "icon": args[2]})
    save(args[0], data)
    print(location)

elif cmd == "remove-profile":   # STORAGE LOCATION
    data["userDataProfiles"] = [p for p in profiles if p.get("location") != args[1]]
    for group in data.get("profileAssociations", {}).values():
        if isinstance(group, dict):
            for key in [k for k, v in group.items() if v == args[1]]:
                del group[key]
    save(args[0], data)

elif cmd == "settings":         # FILE "R G B" JSON -> adds the keys that are not set yet
    wanted = json.loads(args[2])
    wanted["workbench.colorCustomizations"] = scheme(*map(int, args[1].split()))
    missing = {k: v for k, v in wanted.items() if k not in data}
    if missing:
        data.update(missing)
        save(args[0], data)

elif cmd == "set-keys":         # FILE JSON -> sets these keys
    data.update(json.loads(args[1]))
    save(args[0], data)

elif cmd == "del-keys":         # FILE KEY... -> removes these keys
    if any(k in data for k in args[1:]):
        save(args[0], {k: v for k, v in data.items() if k not in args[1:]})
PY
)
py() { "$PYTHON" -c "$PY_HELPER" "$@"; }

# ─── Templates ────────────────────────────────────────────────────────────────────────────────
base_rules() {
    cat <<'EOF'
# Shared rules for every workspace

Loaded by Claude Code in every folder below this one (each workspace adds its own `CLAUDE.md`).

## Layout

- `Workspace/<language>/`: `scratch/` for experiments, `projects/<name>/` for projects (VS Code task "New project" copies `templates/basic/`).
- `Workspace/.venv/`: the shared Python environment. Install packages with `.venv/bin/pip install <package>`; never with sudo or system-wide.
- `Workspace/setup_manager/`: the setup itself (README.md, installed.txt, logs, the setup script).
- This is macOS: programs come from Homebrew (`brew install <name>`), the compiler is Apple clang.

## How to work

- Match the requested scope. No unrequested refactoring, extra features or "improvements".
- Read the relevant files before acting; don't guess about files or configuration you haven't read.
- Verify before claiming: run what you changed. If you can't check something (a rendered PDF, hardware), say so.
- Track what has been tried; don't re-suggest a failed approach. If you're out of ideas, say so.
- Admit limitations early instead of guessing with confidence.
- Terse and direct. No filler.
- Faithful transfer: when asked to copy, transcribe or reformat, preserve the source.
- Plan non-trivial work as a todo list and work through it one item at a time.
- Re-read your result critically before calling it done.
- You have no memory between sessions: write what must persist into a file.

## Issue journal and log

- `/log <message>` notes friction in `<workspace>/.claude/friction.md`; `/distill` later turns those notes into rules, only after approval.
- Changes to the setup (profiles, extensions, settings, packages, scripts) go into `setup_manager/logs/setup_log.txt`: `[YYYY-MM-DD] title`, then `- ` bullets.
EOF
}

lang_rules() {
    case $1 in
        python) cat <<'EOF'
# Python workspace

- Python 3 with the shared environment `../.venv` (numpy, pandas, matplotlib); VS Code uses it as the interpreter. Install packages with `../.venv/bin/pip install <package>`.
- Run a file: `../.venv/bin/python file.py` (in VS Code: the run button; F5 debugs).
- Notebooks (.ipynb) use the same environment, shown as ".venv" (a link in this folder); the first run of each notebook asks once: Python Environments, then .venv (Recommended). Edit individual cells and keep the user's cell structure. You only see cell outputs that are saved in the file; say what you couldn't check.
- Change only what was asked; if asked to change one line, change one line.
- Run the script after changing it and report what actually happened.
EOF
        ;;
        cpp) cat <<'EOF'
# C++ workspace

- Apple clang (`clang++`; `g++` is the same compiler) as C++23, with clangd for code help. Single files: the run button compiles and runs, F5 debugs (CodeLLDB), Cmd+Shift+B only builds. All three build the current file only.
- Don't introduce a build system for a single-file program unless asked. Multi-file projects: generate `compile_commands.json` (CMake: `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) so clangd sees the real flags.
- Compile after every change; fix every error and warning you introduced.
EOF
        ;;
        latex) cat <<'EOF'
# LaTeX workspace

- BasicTeX (a small TeX Live) with latexmk; LaTeX Workshop builds on save and shows the PDF in a tab. Build files (.aux, .log, ...) are disposable.
- When transcribing or reformatting, keep content and wording exactly. Keep the document's macros and preamble; don't add a package when a loaded one does the job.
- After editing, build (`latexmk -pdf file.tex`) and fix the errors you introduced; report remaining warnings.
- You cannot see the PDF: don't claim the layout looks right.
- A missing package ("File `x.sty' not found"): tell the user to run `sudo tlmgr install <package>`.
EOF
        ;;
        bash) cat <<'EOF'
# Bash workspace

- Run scripts with `bash file.sh` (in VS Code: the run button); this is Homebrew's current Bash, macOS's own `/bin/bash` is the old 3.2. ShellCheck lints in the editor. LF line endings only.
- macOS tools are the BSD versions (`sed -i ''`, no `readlink -f` before macOS 12.3): say so when a script must run on Linux too.
- Small, reviewable changes; never rewrite a whole script when only part needs updating.
- Run the script after editing and check its output.
EOF
        ;;
        rust) cat <<'EOF'
# Rust workspace

- rustup stable toolchain. Projects: `cargo new projects/<name>`, then `cargo run`, `cargo test`, `cargo clippy`. Everything is one Cargo workspace (`Cargo.toml` here; `cargo new` adds projects to it), so rust-analyzer sees all files. Deleting a project: also remove its line from `members` in `Cargo.toml`, or cargo fails for the whole folder. Quick experiments: one file per program in `scratch/src/bin/<name>.rs` (run button, F5, or `cargo run --bin <name>`).
- Ask before adding a crate; prefer the standard library.
- `cargo build` (and clippy/test where relevant) after every change; fix what you introduced.
EOF
        ;;
    esac
}

setup_manager_rules() {
    cat <<'EOF'
# Setup Manager

You maintain this VS Code setup: profiles, extensions, workspace folders, the launcher and packages. Read `README.md` and `installed.txt` before changing anything.

- VS Code keeps its profile list in `~/Library/Application Support/Code/User/globalStorage/storage.json` and rewrites it while running: never edit it with VS Code open.
- Adding a language the script knows: the user closes VS Code and runs `bash scripts/setup-workspace-mac.sh --add <language>` in Terminal. Anything else: create the profile in VS Code (Manage > Profiles), install its extensions there, and add a workspace folder like the existing ones.
- Before changing profiles, settings.json, .code-workspace files or the launcher: say what you will change and wait for approval. One profile at a time.
- Programs come from Homebrew (`brew install <name>`); tell the user before installing anything.
- A language the install reported as failed: read the newest `logs/install-*.log`, find the cause, then fix it or give the user the command. `bash scripts/setup-workspace-mac.sh --check` tests the installed languages.
- "Still doesn't work" means stop: look at the actual state (the files, `code --list-extensions --profile <name>`), say what was tried, then propose the next step.
- Log every change in `logs/setup_log.txt`.
EOF
}

main_file() { case $1 in python) echo main.py ;; cpp) echo main.cpp ;; latex) echo main.tex ;; bash) echo main.sh ;; rust) echo src/main.rs ;; esac; }

notebook_json() { # first cell source (JSON string array)
    cat <<EOF
{
 "cells": [
  {"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [], "source": $1}
 ],
 "metadata": {
  "kernelspec": {"display_name": "Python (Workspace)", "language": "python", "name": "workspace-venv"},
  "language_info": {"name": "python"}
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
EOF
}

write_examples() { # key dir — scratch/hello.* (a first thing to run) and templates/basic/
    local key=$1 dir=$2 t=$2/templates/basic
    case $key in
        python)
            put "$dir/scratch/hello.py" <<'EOF'
import numpy as np

print("Hello from Python, numpy", np.__version__, np.arange(5) ** 2)
EOF
            put "$t/main.py" <<'EOF'
def main():
    print("Hello from a new project")


if __name__ == "__main__":
    main()
EOF
            put "$t/.gitignore" <<'EOF'
__pycache__/
.venv/
EOF
            notebook_json '["import numpy as np\n", "import matplotlib.pyplot as plt\n", "\n", "x = np.linspace(0, 2 * np.pi, 100)\n", "plt.plot(x, np.sin(x))\n", "plt.show()"]' | put "$dir/scratch/hello.ipynb"
        ;;
        cpp)
            put "$dir/scratch/hello.cpp" <<'EOF'
#include <iostream>

int main() {
    std::cout << "Hello from C++" << std::endl;
    return 0;
}
EOF
            put "$t/main.cpp" <<'EOF'
#include <iostream>

int main() {
    std::cout << "Hello from a new project" << std::endl;
    return 0;
}
EOF
            put "$t/.gitignore" <<'EOF'
main
*.o
EOF
        ;;
        latex)
            put "$dir/scratch/hello.tex" <<'EOF'
\documentclass{article}
\usepackage{amsmath}

\begin{document}
Hello from \LaTeX: $e^{i\pi} + 1 = 0$.
\end{document}
EOF
            put "$t/main.tex" <<'EOF'
\documentclass[a4paper,11pt]{article}
\usepackage[T1]{fontenc}
\usepackage{lmodern}
\usepackage{amsmath,amssymb}
\usepackage{graphicx}
\usepackage{hyperref}

\title{Title}
\author{}
\date{\today}

\begin{document}
\maketitle

\section{Introduction}

\end{document}
EOF
            put "$t/.gitignore" <<'EOF'
*.aux
*.fdb_latexmk
*.fls
*.log
*.out
*.synctex.gz
*.toc
EOF
        ;;
        bash)
            put "$dir/scratch/hello.sh" 755 <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Hello from Bash $BASH_VERSION"
EOF
            put "$t/main.sh" 755 <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "Hello from a new project"
EOF
        ;;
        rust)
            # One Cargo workspace for the folder: rust-analyzer ignores .rs files outside a Cargo project.
            put "$dir/Cargo.toml" <<'EOF'
[workspace]
members = ["scratch"]
resolver = "3"
EOF
            put "$dir/scratch/Cargo.toml" <<'EOF'
[package]
name = "scratch"
version = "0.1.0"
edition = "2024"
EOF
            put "$dir/scratch/src/bin/hello.rs" <<'EOF'
fn main() {
    println!("Hello from Rust");
}
EOF
        ;;
    esac
}

tasks_json() { # key
    local key=$1 new build=""
    if [[ $key == rust ]]; then
        new='cargo new --vcs none \"$P\"'
    else
        new='cp -r templates/basic \"$P\"'
    fi
    case $key in
        cpp) build='
        {
            "label": "Build current file",
            "type": "shell",
            "command": "clang++ -g -std=c++2b \"${file}\" -o \"${fileDirname}/${fileBasenameNoExtension}\"",
            "group": { "kind": "build", "isDefault": true },
            "problemMatcher": []
        },' ;;
        rust) build='
        {
            "label": "Build current file",
            "type": "shell",
            "command": "rustc -g --edition 2024 \"${file}\" -o \"${fileDirname}/${fileBasenameNoExtension}\"",
            "group": { "kind": "build", "isDefault": true },
            "problemMatcher": []
        },' ;;
    esac
    cat <<EOF
{
    "version": "2.0.0",
    "tasks": [$build
        {
            "label": "New project",
            "type": "shell",
            "command": "P=\"projects/\$PROJECT_NAME\"; case \"\$PROJECT_NAME\" in ''|.*|*/*) echo 'Use a plain name: no / and no dot at the start.'; exit 1 ;; esac; if [ -e \"\$P\" ]; then echo \"\$P already exists\"; exit 1; fi; $new || exit 1; if git init -q \"\$P\"; then git config user.name >/dev/null \u0026\u0026 git config user.email >/dev/null \u0026\u0026 git -C \"\$P\" add -A \u0026\u0026 git -C \"\$P\" commit -qm 'New project'; fi; code \"\$P/$(main_file "$key")\"",
            "options": { "cwd": "\${workspaceFolder}", "env": { "PROJECT_NAME": "\${input:projectName}" } },
            "problemMatcher": []
        }
    ],
    "inputs": [
        { "id": "projectName", "type": "promptString", "description": "Name of the new project (folder in projects/)" }
    ]
}
EOF
}

launch_json() { # key -> F5 configuration, empty if none
    case $1 in
        python) cat <<'EOF'
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Debug current file",
            "type": "debugpy",
            "request": "launch",
            "program": "${file}",
            "cwd": "${fileDirname}",
            "console": "integratedTerminal"
        }
    ]
}
EOF
        ;;
        cpp|rust) cat <<'EOF'
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Debug current file",
            "type": "lldb",
            "request": "launch",
            "program": "${fileDirname}/${fileBasenameNoExtension}",
            "cwd": "${fileDirname}",
            "preLaunchTask": "Build current file"
        }
    ]
}
EOF
        ;;
    esac
}

# ─── Install steps ────────────────────────────────────────────────────────────────────────────
python_formula() { "$BREW" list --formula -1 2>/dev/null | grep -E '^python@3\.[0-9]+$' | sort -t. -k2 -n | tail -1 | grep .; }
brew_list() { "$BREW" list "--$1" -1 2>/dev/null | sort; }   # formula | cask

wanted_brew() { # kind (formula|cask) [core|language] -> wanted names, one per line; no second argument: everything
    local key col=7 keys=${2:-${SELECTED[*]}}
    if [[ -z ${2:-} || $2 == core ]]; then
        if [[ $1 == cask && -z $CODE ]]; then echo visual-studio-code; fi
        # Any Homebrew Python 3 will do: "python" moves to each new version and would add a second one.
        if [[ $1 == formula ]] && { [[ -z $BREW ]] || ! python_formula >/dev/null; }; then printf '%s\n' $BASE_FORMULAS; fi
    fi
    if [[ ${2:-} == core ]]; then return 0; fi
    if [[ $1 == formula ]]; then col=6; fi
    # shellcheck disable=SC2046  # a field holds a space-separated list
    for key in $keys; do
        # An existing TeX (MacTeX, or a TeX Live from its .pkg) stays: BasicTeX would replace it.
        if [[ $1 == cask && $key == latex && -x $TEXBIN/pdflatex ]]; then continue; fi
        printf '%s\n' $(p_field "$key" $col)
    done
}

missing_brew() { # kind [core|language] -> wanted names that are not installed
    local n
    [[ -n $BREW ]] || { wanted_brew "$@" | sort -u | { grep . || true; }; return 0; }
    wanted_brew "$@" | sort -u | while read -r n; do
        [[ -n $n ]] || continue
        "$BREW" list "--$1" --versions "$n" >/dev/null 2>&1 || echo "$n"
    done
}

# Everything Homebrew installed since BREW_BEFORE_*, dependencies included: exactly what --uninstall
# may remove. Also called on exit, so a failed run still records what it installed.
BREW_BEFORE_F="" BREW_BEFORE_C="" BREW_TRACKING=0
record_new_brew() {
    local n
    ((BREW_TRACKING)) || return 0
    for n in $(comm -13 <(echo "$BREW_BEFORE_F") <(brew_list formula)); do recorded formula "$n" || record formula "$n"; done
    for n in $(comm -13 <(echo "$BREW_BEFORE_C") <(brew_list cask)); do recorded cask "$n" || record cask "$n"; done
}

install_homebrew() {
    if find_brew; then
        # Another account's Homebrew: everything would fail with permission errors later.
        [[ -w $BREW_PREFIX/Cellar || ! -e $BREW_PREFIX/Cellar ]] || fail "This Mac's Homebrew belongs to another user, so this account can't install with it. Log in as that user, or give this account access (https://docs.brew.sh/FAQ)."
        return 0
    fi
    step "Installing Homebrew (and Apple's command line tools if needed). This can take 10 minutes or more"
    need_sudo
    local tmp had=0
    if [[ -e /opt/homebrew ]]; then had=1; fi
    tmp=$(mktemp -d)
    quiet curl -fsSL --connect-timeout 20 --speed-time 60 --speed-limit 1000 --retry 5 --retry-all-errors -o "$tmp/install.sh" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh ||
        fail "Downloading the Homebrew installer failed. Check the internet connection and start the setup again."
    # Noted first: even if it stops near its end, the uninstall can still offer it.
    if ((!had)); then record homebrew /opt/homebrew; fi
    NONINTERACTIVE=1 quiet /bin/bash "$tmp/install.sh" || fail "Installing Homebrew failed; the reason is in the last lines above and in the log."
    rm -rf "$tmp"
    find_brew || fail "Homebrew is not available after installing it."
}

# The login shell (Terminal, VS Code) must find Homebrew and Rust: one marked block in ~/.zprofile,
# and in ~/.bash_profile for accounts whose login shell is still bash.
shell_files() {
    echo "$ZPROFILE"
    if [[ $(dscl . -read "$HOME" UserShell 2>/dev/null) == *bash ]]; then echo "$HOME/.bash_profile"; fi
}
block_of() { [[ -f $1 ]] && awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '$0 == b { on = 1; next } $0 == e { on = 0 } on' "$1"; }
write_block() { # file lines — replace (or with empty lines: remove) the block; keeps a symlinked file a symlink
    local f=$1 want=$2 tmp
    tmp=$(mktemp)
    if [[ -f $f ]]; then awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$f" > "$tmp"; fi
    if [[ -n $want ]]; then printf '%s\n%s%s\n' "$BLOCK_BEGIN" "$want" "$BLOCK_END" >> "$tmp"; fi
    cat "$tmp" > "$f"
    rm -f "$tmp"
}
shell_block() {
    local f want have brew_line rust_line
    brew_line="eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
    rust_line='export PATH="$HOME/.cargo/bin:$PATH"'
    while IFS= read -r f; do
        want="" have=$(block_of "$f" || true)
        # Homebrew's installer puts it behind /usr/bin (/etc/paths.d), so bash and python3 would be Apple's.
        # Skip the line only if the user's own shell files really set it up (but keep it once it is ours).
        if [[ $BREW_PREFIX != /usr/local ]]; then
            if grep -qxF -- "$brew_line" <<< "$have" || ! env -i HOME="$HOME" /bin/zsh -lc '[[ -n $HOMEBREW_PREFIX ]]' >/dev/null 2>&1; then want+=$brew_line$'\n'; fi
        fi
        if has_key rust || grep -qxF -- "$rust_line" <<< "$have"; then want+=$rust_line$'\n'; fi
        if [[ -z $want$have || $have$'\n' == "$want" ]]; then continue; fi
        step "Login shell settings ($(show "$f"))"
        if [[ ! -e $f ]] && ! recorded file "$f"; then record file "$f"; fi
        write_block "$f" "$want"
        recorded shellblock "$f" || record shellblock "$f"
    done <<< "$(shell_files)"
}

brew_tracking_on() { BREW_BEFORE_F=$(brew_list formula) BREW_BEFORE_C=$(brew_list cask) BREW_TRACKING=1; }
brew_tracking_off() { record_new_brew; BREW_TRACKING=0; }

install_packages() { # core or a language
    local formulas casks
    formulas=$(missing_brew formula "$1" | paste -s -d' ' -)
    casks=$(missing_brew cask "$1" | paste -s -d' ' -)
    [[ -n $formulas$casks ]] || return 0
    if [[ -n $casks ]]; then need_sudo; fi   # pkg installers (BasicTeX) ask for the password
    if [[ -n $formulas ]]; then
        step "Installing $formulas"
        # shellcheck disable=SC2086  # the list is split on purpose
        quiet "$BREW" install --formula $formulas ||
            fail "Installing $formulas with Homebrew failed. Details: $(show "$LOG")"
    fi
    if [[ -n $casks ]]; then
        step "Installing $casks"
        # shellcheck disable=SC2086
        quiet "$BREW" install --cask $casks ||
            fail "Installing $casks with Homebrew failed. Details: $(show "$LOG")"
    fi
}

# Apple's command line tools (clang, git, the linker Rust needs) are often broken after a macOS
# upgrade even when Homebrew is there. xcode-select --install opens Apple's own installer window.
check_clt() {
    local out
    if out=$(printf '#include <iostream>\nint main() {}\n' | clang++ -x c++ -std=c++20 - -o /dev/null 2>&1); then return 0; fi
    if grep -qi license <<< "$out"; then
        fail "Xcode's license has to be accepted first. Run: sudo xcodebuild -license accept. Then start the setup again."
    fi
    xcode-select --install >/dev/null 2>&1 || true
    fail "Apple's command line tools (compiler, linker) are missing or broken. Install them in the window that just opened (or: softwareupdate --list, then --install), then start the setup again."
}

setup_tex() {
    [[ -x $TEXBIN/tlmgr ]] || fail "BasicTeX is not available after installing it."
    local langs=""
    case $SYSTEM_LANG in
        de*) langs="babel-german hyphen-german" ;; fr*) langs="babel-french hyphen-french" ;; es*) langs="babel-spanish hyphen-spanish" ;;
        it*) langs="babel-italian hyphen-italian" ;; pt*) langs="babel-portuges hyphen-portuguese" ;;
    esac
    # latexmk alone doesn't say it's complete: the network may have gone during the collections.
    if [[ -x $TEXBIN/latexmk ]] && "$TEXBIN/kpsewhich" lmodern.sty >/dev/null 2>&1; then return 0; fi   # MacTeX, or an earlier run
    step "LaTeX packages (latexmk, recommended packages and fonts)"
    need_sudo
    local mark v envs="" t
    for v in http_proxy https_proxy no_proxy; do eval "t=\${$v:-}"; if [[ -n $t ]]; then envs+=" $v=$t"; fi; done
    mark=$(wc -l < "$LOG")
    # shellcheck disable=SC2086
    quiet sudo env $envs "$TEXBIN/tlmgr" update --self || true
    # shellcheck disable=SC2086
    if ! quiet sudo env $envs "$TEXBIN/tlmgr" install $TEX_PACKAGES $langs && ! quiet sudo env $envs "$TEXBIN/tlmgr" install $TEX_PACKAGES $langs; then
        if tail -n +"$((mark + 1))" "$LOG" | grep -q 'older than remote'; then
            fail "This TeX installation is older than the current TeX Live, so tlmgr can't add packages. Update it (brew upgrade --cask basictex), then start the setup again."
        fi
        fail "Installing LaTeX packages failed. Check the internet connection and start the setup again."
    fi
}

rust_retry() {
    quiet "$@" || RUSTUP_USE_CURL=1 quiet "$@" || RUSTUP_USE_CURL=1 quiet "$@" ||
        fail "Downloading the Rust toolchain failed three times. Check the internet connection and start the setup again."
}

setup_rust() {
    local rustup=$HOME/.cargo/bin/rustup
    # Any rustup call creates ~/.rustup, so note first whether it was there before.
    if [[ ! -d $HOME/.rustup ]] && ! recorded homedir "$HOME/.rustup"; then record homedir "$HOME/.rustup"; fi
    if [[ ! -d $HOME/.cargo ]] && ! recorded homedir "$HOME/.cargo"; then record homedir "$HOME/.cargo"; fi
    if "$HOME/.cargo/bin/rustc" --version >/dev/null 2>&1; then return 0; fi
    step "Rust toolchain (rustup stable)"
    if [[ ! -x $rustup ]]; then
        local tmp
        tmp=$(mktemp -d)
        quiet curl -fsSL --connect-timeout 20 --speed-time 60 --speed-limit 1000 --retry 5 --retry-all-errors -o "$tmp/rustup-init.sh" https://sh.rustup.rs ||
            fail "Downloading the Rust installer failed. Check the internet connection and start the setup again."
        # ~/.zprofile gets its PATH line from shell_block, so the installer must not edit shell files.
        rust_retry sh "$tmp/rustup-init.sh" -y --no-modify-path --profile minimal --default-toolchain none
        rm -rf "$tmp"
    fi
    quiet "$rustup" set profile minimal
    rust_retry "$rustup" default stable
    rust_retry "$rustup" component add rust-src clippy rustfmt
}

# Folders created in the home folder, noted if missing before the first run. VS Code's own (settings,
# extensions) are removed only together with VS Code; the tools' caches are a separate, unticked item.
note_new_home_dirs() {
    local d
    for d in "$HOME/.vscode" "$HOME/.vscode-shared" "$VSC_DIR" "$HOME/.dotnet"; do
        if [[ ! -e $d ]] && ! recorded created-vscode "$d"; then record created-vscode "$d"; fi
    done
    for d in "$HOME/.ipython" "$HOME/.matplotlib" "$HOME/Library/Caches/pip" "$HOME/Library/Jupyter"; do
        if [[ ! -e $d ]] && ! recorded created "$d"; then record created "$d"; fi
    done
    if [[ ! -e $APP_DIR ]] && ! recorded emptydir "$APP_DIR"; then record emptydir "$APP_DIR"; fi   # may hold other apps later
}

backup_vscode() { # once, on the first run: only a VS Code setup from before this script is backed up
    [[ -z $(manifest_lines backup) ]] || return 0
    if [[ ! -d $VSC_USER ]]; then record backup none; return 0; fi
    step "Backing up your VS Code settings"
    local items=() item file=$SM/backup/vscode-before-setup-$TODAY.tar.gz
    for item in settings.json keybindings.json snippets profiles globalStorage/storage.json; do
        if [[ -e $VSC_USER/$item ]]; then items+=("$item"); fi
    done
    mkdir -p "$SM/backup"
    if ((${#items[@]})); then quiet tar -czf "$file" --exclude='profiles/*/globalStorage' -C "$VSC_USER" "${items[@]}"; fi
    record backup "$file"
}

# A language that fails must not stop the others. The subshell is what keeps set -e working: inside
# "if" or "||" bash ignores it. What the subshell changes comes back through files.
LANG_FAILED=""   # lines of key<TAB>reason: bash 3.2 has no associative arrays
lang_failed() { awk -F'\t' -v k="$1" '$1 == k { print $2; f = 1 } END { exit !f }' <<< "$LANG_FAILED"; }
CONTAIN_DIR=""   # not a local: setup_tex has its own "t", and bash's locals reach into what a function calls
contained() { # key command... -> a failure lands in LANG_FAILED. Never call it with || or if: see above.
    local key=$1 rc=0 why line
    shift
    CONTAIN_DIR=$(mktemp -d)
    keep_state
    set +e
    (
        set -e
        trap keep_state EXIT
        fail() { printf '%s\n' "$1" > "$CONTAIN_DIR/reason"; say "error: $1"; exit 1; }
        "$@"
    )
    rc=$?
    set -e
    read -r STEP_NO < "$CONTAIN_DIR/step"
    read -r SUDO_KEEPER < "$CONTAIN_DIR/sudo" || true
    NOTES=() FAILED=()
    while IFS= read -r line; do NOTES+=("$line"); done < "$CONTAIN_DIR/notes"
    while IFS= read -r line; do FAILED+=("$line"); done < "$CONTAIN_DIR/failed"
    if ((rc)); then
        why=$(cat "$CONTAIN_DIR/reason" 2>/dev/null | tr '\n\t' '  ' || true)
        why=${why% }
        if [[ -z $why ]]; then
            why="stopped during: $(tail -n 1 "$CONTAIN_DIR/last") (exit code $rc)"
            if [[ -n $(cat "$CONTAIN_DIR/at") ]]; then why+=", $(cut -c1-120 "$CONTAIN_DIR/at")"; fi
        fi
        LANG_FAILED+="$key"$'\t'"$why"$'\n'
    fi
    rm -rf "$CONTAIN_DIR"
}
keep_state() {
    printf '%s\n' "$STEP_NO" > "$CONTAIN_DIR/step"
    printf '%s\n' "$CURRENT_STEP" > "$CONTAIN_DIR/last"
    printf '%s\n' "$SUDO_KEEPER" > "$CONTAIN_DIR/sudo"
    printf '%s\n' "${STOPPED_AT:-}" > "$CONTAIN_DIR/at"
    : > "$CONTAIN_DIR/notes"; : > "$CONTAIN_DIR/failed"
    if ((${#NOTES[@]})); then printf '%s\n' "${NOTES[@]}" > "$CONTAIN_DIR/notes"; fi
    if ((${#FAILED[@]})); then printf '%s\n' "${FAILED[@]}" > "$CONTAIN_DIR/failed"; fi
}
language_tools() { # key
    local key=$1
    if [[ $key == cpp || $key == rust ]]; then check_clt; fi
    install_packages "$key"
    if [[ $key == latex ]]; then setup_tex; fi
    if [[ $key == rust ]]; then setup_rust; fi
    make_workspace "$key"
    if [[ $key == python ]]; then setup_python_env; fi
}
language_profile() { # key
    CLANGD=""
    if [[ $1 == cpp ]]; then CLANGD=$(xcrun -f clangd 2>/dev/null || true); fi
    setup_profile "$1" "$(p_name "$1")" "$(p_field "$1" 3)" "$(p_field "$1" 4)" "$(p_field "$1" 5)" "$(profile_settings "$1")"
}
install_language() { # key
    brew_tracking_on
    contained "$1" language_tools "$1"
    brew_tracking_off
    if lang_failed "$1" >/dev/null; then return 0; fi
    close_vscode   # again: someone may have opened it during the downloads
    contained "$1" language_profile "$1"
}

# Does each language really work? Everything happens in a temporary folder; the workspaces stay untouched.
CHECK_BAD=() CHECK_OK=()
check_lang() { # key -> output of what failed; fails if the language doesn't work
    local t rc=0
    t=$(mktemp -d)
    case $1 in
        python)
            "$VENV/bin/python" -c 'import numpy, pandas, matplotlib, ipykernel' 2>&1 </dev/null | tail -n 1 || rc=$?
            ;;
        cpp)
            printf '#include <iostream>\n#include <ranges>\nint main() { for (int i : std::views::iota(0, 1)) std::cout << i; }\n' > "$t/hello.cpp"
            { clang++ -std=c++2b "$t/hello.cpp" -o "$t/hello" </dev/null && "$t/hello" >/dev/null </dev/null; } || rc=$?
            ;;
        latex)
            printf '%s\n' '\documentclass{article}' '\usepackage[T1]{fontenc}' '\usepackage{lmodern}' '\usepackage{amsmath,amssymb}' '\usepackage{graphicx}' '\usepackage{hyperref}' '\begin{document}' 'Hello: $e^{i\pi} + 1 = 0$.' '\end{document}' > "$t/hello.tex"
            { (cd "$t" && "$TEXBIN/latexmk" -pdf -interaction=nonstopmode -halt-on-error hello.tex >"$t/out" 2>&1 </dev/null) && [[ -s $t/hello.pdf ]]; } || { rc=1; grep -E '^!|not found' "$t/out" | head -3; }
            ;;
        bash)
            printf '#!/usr/bin/env bash\necho hello\n' > "$t/hello.sh"
            { "$BREW_PREFIX/bin/shellcheck" "$t/hello.sh" </dev/null && "$BREW_PREFIX/bin/bash" "$t/hello.sh" >/dev/null </dev/null; } || rc=$?
            ;;
        rust)
            { (cd "$t" && "$HOME/.cargo/bin/cargo" new --vcs none hello >/dev/null 2>&1 </dev/null && cd hello && "$HOME/.cargo/bin/cargo" run -q >/dev/null </dev/null); } || rc=$?
            # The workspace folder too: a deleted project still listed in Cargo.toml stops cargo there.
            if ((rc == 0)); then (cd "$WS/rust" && "$HOME/.cargo/bin/cargo" metadata -q --no-deps --format-version 1 >/dev/null </dev/null) || rc=$?; fi
            ;;
    esac
    rm -rf "$t"
    return "$rc"
}

run_checks() { # the languages in SELECTED; with extensions when asked for: an install has just verified them
    local key name out ext missing
    step "Checking that everything works"
    for key in "${SELECTED[@]}"; do
        name=$(p_name "$key")
        if out=$(lang_failed "$key"); then
            CHECK_BAD+=("$name: $out")
            say "  $name: DOES NOT WORK"
            continue
        fi
        if out=$(check_lang "$key" 2>&1); then
            CHECK_OK+=("$name")
            say "  $name: works"
        else
            CHECK_BAD+=("$name: $(if [[ -n $out ]]; then head -n 1 <<< "$out" | cut -c1-110; else echo 'it did not run'; fi)")
            say "  $name: DOES NOT WORK"
            if [[ -n $out ]]; then say "$out"; fi
        fi
    done
    (($#)) || return 0
    while IFS=$'\t' read -r key name _; do
        [[ -n $key ]] || continue
        missing=""
        out=$(code_cli --list-extensions --profile "$name" 2>/dev/null </dev/null | lower_stream) || true
        for ext in $BASE_EXTENSIONS $(p_field "$key" 5); do grep -qxF "$(lower "$ext")" <<< "$out" || missing+=" $ext"; done
        if [[ -n $missing ]]; then CHECK_BAD+=("Profile $name: extensions missing:$missing"); say "  Profile $name: extensions missing:$missing"; fi
    done <<< "$(manifest_lines profile)"
}
lower_stream() { tr '[:upper:]' '[:lower:]'; }

check_only() {
    [[ -f $MANIFEST ]] || fail "Nothing to check: $(show "$MANIFEST") not found."
    local k
    SELECTED=()
    for k in $(manifest_lines profile | cut -f1 | sed 's/^jupyter$/python/' | awk '!s[$0]++'); do
        if [[ " $ALL_KEYS " == *" $k "* ]]; then SELECTED+=("$k"); fi
    done
    find_brew || true
    find_code || fail "VS Code was not found."
    LOG=$SM/logs/check-$(date +%F_%H%M).log
    : > "$LOG"
    if ((${#SELECTED[@]})); then run_checks with-extensions; fi
    if ((${#CHECK_BAD[@]})); then
        info "The check found problems:
$(printf ' - %s\n' "${CHECK_BAD[@]}")

Running the setup again repairs what it can. Details: $(show "$LOG")"
        DIED=1
        exit 1
    fi
    info "Everything works: $(printf '%s, ' ${CHECK_OK[@]+"${CHECK_OK[@]}"} | sed 's/, $//'), and all the extensions are there."
}

# Optional, and only on a first run with no identity yet: Git works without it until the first commit.
# Git comes with Apple's command line tools: without them, calling git would open Apple's install window.
GIT_NAME="" GIT_EMAIL=""
git_dialog() { # label -> the answer; Skip or an error: nothing
    osa -e "text returned of (display dialog $(as_text "Optional: your name and email for Git commits. They appear in the history of anything you publish.

$1 (optional):") with title \"VS Code setup\" default answer \"\" buttons {\"Skip\", \"OK\"} default button \"OK\" cancel button \"Skip\")" || true
}
ask_git_identity() {
    [[ -z $INSTALLED ]] || return 0
    if xcode-select -p >/dev/null 2>&1 && [[ -n $(git config --global user.name </dev/null 2>/dev/null || true)$(git config --global user.email </dev/null 2>/dev/null || true) ]]; then return 0; fi
    if ((GUI)); then
        say "Waiting for your answer in the window (it may be behind this one)..."
        GIT_NAME=$(git_dialog Name)
        if [[ -n $GIT_NAME ]]; then GIT_EMAIL=$(git_dialog Email); fi
    elif ((TTY)); then
        say "Optional: your name and email for Git commits. They appear in the history of anything you publish. Enter skips."
        read -rp "  Name (optional): " GIT_NAME </dev/tty || GIT_NAME=""
        read -rp "  Email (optional): " GIT_EMAIL </dev/tty || GIT_EMAIL=""
    fi
}

# Only with a Git identity: without one, a commit fails.
add_commit_rule() {
    local rule='- Projects with git: commit when a change works, with a short message. Never push unless asked; never commit secrets.'
    [[ -n $(git config --global user.name </dev/null || true) && -n $(git config --global user.email </dev/null || true) ]] || return 0
    if ! grep -qxF -- "$rule" "$WS/CLAUDE.md"; then printf '%s\n' "$rule" >> "$WS/CLAUDE.md"; fi
}

set_git_identity() {
    [[ -n $GIT_NAME$GIT_EMAIL ]] || return 0
    # Git comes from Apple's tools, which a macOS upgrade can break: no reason to stop the setup.
    if ! xcode-select -p >/dev/null 2>&1 || ! git --version >/dev/null 2>&1 </dev/null; then
        NOTES+=("Git isn't working yet, so your name and email were not saved. README.md has the commands.")
        return 0
    fi
    if [[ ! -e $HOME/.gitconfig ]]; then record gitfile "$HOME/.gitconfig"; fi
    if [[ -n $GIT_NAME ]]; then git config --global user.name "$GIT_NAME" </dev/null; record gitkey user.name; fi
    if [[ -n $GIT_EMAIL ]]; then git config --global user.email "$GIT_EMAIL" </dev/null; record gitkey user.email; fi
}

setup_python_env() {
    step "Python environment (Workspace/.venv: ${PY_PACKAGES// /, })"
    if [[ ! -x $VENV/bin/python ]]; then
        quiet "$PYTHON" -m venv "$VENV" || fail "Creating the Python environment failed. Details: $(show "$LOG")"
        recorded venv "$VENV" || record venv "$VENV"
    fi
    # shellcheck disable=SC2086  # the package list is split on purpose
    quiet "$VENV/bin/pip" install --disable-pip-version-check $PY_PACKAGES ||
        fail "Installing Python packages failed. Check the internet connection and start the setup again."
    if [[ ! -d $KERNEL_DIR ]]; then
        quiet "$VENV/bin/python" -m ipykernel install --user --name workspace-venv --display-name "Python (Workspace)"
        recorded kernel "$KERNEL_DIR" || record kernel "$KERNEL_DIR"
    fi
}

make_workspace() { # key
    local key=$1 dir=$WS/$1 launch
    step "Workspace $(p_name "$key")"
    mkd "$dir/scratch" "$dir/projects" "$dir/templates/basic"
    put "$dir/$key.code-workspace" <<'EOF'
{
    "folders": [
        { "path": "." }
    ]
}
EOF
    lang_rules "$key" | put "$dir/CLAUDE.md"
    tasks_json "$key" | put "$dir/.vscode/tasks.json"
    launch=$(launch_json "$key")
    if [[ -n $launch ]]; then put "$dir/.vscode/launch.json" <<< "$launch"; fi
    if [[ $key == python ]]; then
        # A plain absolute path: the Python tools stumble over ".." ("Inaccurate Python Environment Info").
        if [[ ! -e $dir/.vscode/settings.json ]]; then
            py set-keys "$dir/.vscode/settings.json" "$("$PYTHON" -c 'import json, sys; print(json.dumps({"python.defaultInterpreterPath": sys.argv[1], "files.exclude": {".venv": True}}))' "$VENV/bin/python")"
            record file "$dir/.vscode/settings.json"
        fi
        # Only an environment inside the workspace folder is found at once: without this link the notebook
        # kernel picker doesn't list .venv on the first open and offers the system Python, without ipykernel.
        if [[ ! -e $dir/.venv && ! -L $dir/.venv ]]; then
            ln -s ../.venv "$dir/.venv"
            record file "$dir/.venv"
        fi
    fi
    write_examples "$key" "$dir"
}

make_setup_manager() {
    step "Setup Manager"
    mkd "$SM/scripts" "$SM/logs"
    base_rules | put "$WS/CLAUDE.md"
    setup_manager_rules | put "$SM/CLAUDE.md"
    if [[ ! -e $SM/setup.code-workspace ]]; then
        py workspace-file "$SM/setup.code-workspace" "setup_manager=." "Workspace=.." "VS Code settings and profiles=$VSC_USER"
        record file "$SM/setup.code-workspace"
    fi
    put "$SM/logs/setup_log.txt" <<'EOF'
SETUP LOG — every change to the setup, newest at the bottom.
Format: [YYYY-MM-DD] Title, then "- " bullets: what changed and why.
EOF
    local dest=$SM/scripts/setup-workspace-mac.sh
    if [[ -f $SELF && $SELF != "$dest" ]] && ! cmp -s "$SELF" "$dest" 2>/dev/null; then
        install -m 755 "$SELF" "$dest"
        recorded file "$dest" || record file "$dest"
    elif [[ ! -f $SELF && ! -f $dest && -n $SOURCE_URL ]]; then   # started as curl | bash
        if quiet curl -fsSL --connect-timeout 20 --speed-time 60 --speed-limit 1000 --retry 5 --retry-all-errors -o "$dest.tmp" "$SOURCE_URL" && /bin/bash -n "$dest.tmp"; then
            mv "$dest.tmp" "$dest"; chmod 755 "$dest"; record file "$dest"
        else
            rm -f "$dest.tmp"
        fi
    fi
}

install_extensions() { # profile-name extension...
    local profile=$1 out ext missing=() args=()
    shift
    for ext; do args+=(--install-extension "$ext"); done
    quiet code_cli --profile "$profile" "${args[@]}" || true
    out=$(code_cli --list-extensions --profile "$profile" 2>/dev/null | tr '[:upper:]' '[:lower:]') || true
    for ext; do grep -qxF "$(lower "$ext")" <<< "$out" || missing+=("$ext"); done
    if ((${#missing[@]})); then   # one retry: most failures are a network hiccup
        args=()
        for ext in "${missing[@]}"; do args+=(--install-extension "$ext"); done
        quiet code_cli --profile "$profile" "${args[@]}" || true
        out=$(code_cli --list-extensions --profile "$profile" 2>/dev/null | tr '[:upper:]' '[:lower:]') || true
        for ext in "${missing[@]}"; do grep -qxF "$(lower "$ext")" <<< "$out" || FAILED+=("$profile: $ext"); done
    fi
}

profile_settings() { # key -> extra settings (JSON members) for that profile
    case $1 in
        cpp)
            if [[ -n $CLANGD ]]; then printf '"clangd.path": "%s", ' "$CLANGD"; fi
            printf '"clangd.fallbackFlags": ["-std=c++2b"], "code-runner.executorMap": {"python": "\\"$pythonPath\\" -u $fullFileName", "cpp": "cd $dir \\u0026\\u0026 clang++ -std=c++2b $fileName -o $fileNameWithoutExt \\u0026\\u0026 $dir$fileNameWithoutExt"}'
            ;;
        bash) printf '"code-runner.executorMap": {"python": "\\"$pythonPath\\" -u $fullFileName", "shellscript": "%s"}' "$BREW_PREFIX/bin/bash" ;;
        rust) printf '"code-runner.executorMap": {"python": "\\"$pythonPath\\" -u $fullFileName", "rust": "cd $dir \\u0026\\u0026 rustc --edition 2024 $fileName \\u0026\\u0026 $dir$fileNameWithoutExt"}' ;;
    esac
}

# The terminal gets the Python environment through its variables. The extensions' own way is unusable on
# a first start: they type "source .../activate" into the terminal, which cuts off or feeds a program
# that is already running (KeyboardInterrupt), and warn about an "invalid interpreter" meanwhile.
venv_settings() { # -> JSON members
    "$PYTHON" - "$VENV" <<'PY'
import json, sys
venv = sys.argv[1]
print(json.dumps({
    "python.useEnvironmentsExtension": False,
    "python.terminal.activateEnvironment": False,
    "python-envs.terminal.autoActivationType": "off",
    "terminal.integrated.env.osx": {"VIRTUAL_ENV": venv, "PATH": venv + "/bin:${env:PATH}"},
})[1:-1])
PY
}

setup_profile() { # key name icon rgb extensions settings
    local key=$1 name=$2 icon=$3 rgb=$4 exts=$5 extra=$6 line location current new=0 settings
    step "VS Code profile $name"
    line=$(manifest_lines profile | awk -F'\t' -v k="$key" '$1 == k')
    if [[ -n $line ]]; then
        IFS=$'\t' read -r _ name location <<< "$line"
        # Found by its folder, not its name: the user may have renamed it in VS Code.
        current=$(py name-of "$STORAGE" "$location")
        if [[ -z $current ]]; then   # deleted in VS Code meanwhile
            unrecord profile "$key" "$name" "$location"
            line=""
        elif [[ $current != "$name" ]]; then
            unrecord profile "$key" "$name" "$location"
            name=$current
            record profile "$key" "$name" "$location"
        fi
    fi
    if [[ -z $line ]]; then
        name=$(py free-name "$STORAGE" "$name")
        location=$(py add-profile "$STORAGE" "$name" "$icon")
        record profile "$key" "$name" "$location"
        new=1
    fi
    # VS Code's own profile creation makes this folder; without it the profile can't save its state.
    mkdir -p "$VSC_USER/profiles/$location/globalStorage"
    local file=$VSC_USER/profiles/$location/settings.json msg=""
    if ((new)) || [[ ! -e $file ]]; then
        # Only for a new profile: a rerun must not bring back settings the user removed.
        # Profile members come after the common ones: for a duplicate key (executorMap) json keeps the last.
        settings="{$COMMON_SETTINGS${extra:+, $extra}"
        if ((BYPASS)); then settings+=", $BYPASS_SETTINGS"; fi
        if [[ $key == python ]]; then settings+=", $(venv_settings)"; fi
        msg=$(py settings "$file" "$rgb" "$settings}" 2>&1)
    elif ((BYPASS_CHANGED)); then
        if ((BYPASS)); then msg=$(py set-keys "$file" "{$BYPASS_SETTINGS}" 2>&1)
        else msg=$(py del-keys "$file" claudeCode.allowDangerouslySkipPermissions claudeCode.initialPermissionMode 2>&1); fi
    fi
    if [[ -n $msg ]]; then NOTES+=("Profile $name: its settings.json has comments, so the setup left it unchanged"); fi
    # shellcheck disable=SC2086  # the extension list is split on purpose
    install_extensions "$name" $BASE_EXTENSIONS $exts
}

make_launcher() {
    step "Launcher"
    put "$ROOT/launcher.sh" 755 <<'EOF'
#!/bin/bash
# VS Launcher: pick a workspace; VS Code opens it with its own profile.
#   launcher.sh              ask (a list window)
#   launcher.sh --list       the entries, Setup Manager first (used by "VS Launcher.app")
#   launcher.sh --open NAME  open that entry
# The entries are the profiles listed in Workspace/setup_manager/installed.txt.
ws=$(cd "$(dirname "$0")" && pwd -P)/Workspace
entries() {
    awk -F'\t' '$1 == "profile" { print ($2 == "setup_manager" ? 0 : 1) "\t" $2 "\t" $3 }' "$ws/setup_manager/installed.txt" |
        sort -f -t"$(printf '\t')" -k1,1 -k3,3 | cut -f2-
}
open_entry() {
    local key file code
    key=$(entries | awk -F'\t' -v n="$1" '$2 == n { print $1; exit }')
    [[ -n $key ]] || exit 1
    if [[ $key == setup_manager ]]; then file=$ws/setup_manager/setup.code-workspace; else file=$ws/$key/$key.code-workspace; fi
    for code in /opt/homebrew/bin/code /usr/local/bin/code "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
                "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"; do
        # The app starts this with a minimal PATH, and VS Code started by its CLI skips reading the
        # login shell: --force-user-env makes it read it (Homebrew, TeX, Rust on the PATH).
        if [[ -x $code ]]; then
            export PATH="/opt/homebrew/bin:/usr/local/bin:/Library/TeX/texbin:$HOME/.cargo/bin:$PATH"
            exec "$code" --force-user-env --profile "$1" "$file"
        fi
    done
    osascript -e 'display alert "VS Launcher" message "VS Code was not found."'
}
case $1 in
    --list) entries | cut -f2 ;;
    --open) open_entry "$2" ;;
    *)  items=$(entries | cut -f2 | sed 's/["\\]/\\&/g; s/.*/"&"/' | paste -s -d, -)
        choice=$(osascript -e "set r to choose from list {$items} with title \"VS Launcher\" with prompt \"Open which workspace?\" default items {item 1 of {$items}}" \
            -e 'if r is false then return ""' -e 'return item 1 of r' 2>/dev/null) || exit 0
        [[ -z $choice ]] || open_entry "$choice" ;;
esac
EOF
    # The "New project" task and Claude call "code": a VS Code dragged to Applications has no such command.
    if [[ -n $BREW_PREFIX && ! -e $BREW_PREFIX/bin/code && $CODE != "$BREW_PREFIX/bin/code" ]]; then
        ln -s "$CODE" "$BREW_PREFIX/bin/code" && record link "$BREW_PREFIX/bin/code"
    fi
    [[ ! -e $LAUNCHER_APP ]] || return 0
    # A tiny AppleScript app, so the launcher is in Spotlight and Launchpad. It shows the list
    # itself: a dialog from a background script could open behind other windows.
    local script=$SM/logs/vs-launcher.applescript icns
    cat > "$script" <<EOF
set launcher to "$ROOT/launcher.sh"
set names to paragraphs of (do shell script "/bin/bash " & quoted form of launcher & " --list")
if names is {} then return
set r to choose from list names with title "VS Launcher" with prompt "Open which workspace?" default items {item 1 of names}
if r is false then return
do shell script "/bin/bash " & quoted form of launcher & " --open " & quoted form of (item 1 of r) & " > /dev/null 2>&1 &"
EOF
    mkdir -p "$APP_DIR"
    if ! quiet osacompile -o "$LAUNCHER_APP" "$script"; then
        say "  (could not create the launcher app; run $(show "$ROOT")/launcher.sh instead)"
        return 0
    fi
    for icns in "$VSC_APP/Contents/Resources/Code.icns" "$APP_DIR/Visual Studio Code.app/Contents/Resources/Code.icns"; do
        if [[ -f $icns ]]; then
            cp "$icns" "$LAUNCHER_APP/Contents/Resources/applet.icns"
            quiet codesign --force --sign - "$LAUNCHER_APP" || true   # the new icon breaks the app's ad-hoc signature
            break
        fi
    done
    record app "$LAUNCHER_APP"
}

setup_skills() {
    step "Claude Code skills /log, /distill and /test-setup"
    # ~/.claude also holds the Claude login: removed only if empty at uninstall.
    local d
    for d in "$HOME/.claude" "$SKILLS"; do
        if [[ ! -e $d ]] && ! recorded emptydir "$d"; then record emptydir "$d"; fi
    done
    if [[ ! -e $SKILLS/log/SKILL.md ]]; then
        put "$SKILLS/log/SKILL.md" <<'EOF'
---
name: log
description: Append a friction/feedback note to the current workspace's issue journal. Use when the user invokes /log with a message — capture in-the-moment annoyances, observations or improvement ideas without breaking the conversation flow. The journal lives at <workspace>/.claude/friction.md and is distilled later via /distill.
---
<!-- installed by setup-workspace.sh -->

# /log — append to the workspace issue journal

When the user types `/log <message>`, append the message to the current workspace's journal. Capture it verbatim; do not interpret, paraphrase or sanitize it. Then reply with one short confirmation line and continue the conversation unchanged.

## Steps

1. **Find the workspace root:** walk up from the current directory to the first folder that contains a `.code-workspace` file, a `.git` directory or a `.claude` directory. If there is none inside `@ROOT@/Workspace/`, use the current directory.
2. **Context:** one short, factual sentence on what was happening just before `/log`.
3. If `<workspace>/.claude/friction.md` is missing, create it with the header `# Issue journal — <workspace name>` and the line `Append-only. Distilled into CLAUDE.md via /distill.`
4. **Append**, followed by a blank line:
   ```markdown
   ## YYYY-MM-DD HH:MM — <workspace name>
   **Context**: <one sentence>
   **Issue**: <the user's message, verbatim>
   ```
5. **Confirm in one line**, e.g. `Logged to python/.claude/friction.md.`, then resume what was in progress.

## Don't

- Paraphrase the message: the raw words are the data.
- Try to fix the issue now, ask follow-up questions or discuss it. Capture only.
- `/log` without a message: ask "What should I log?".
EOF
        record skill "$SKILLS/log"
    fi
    if [[ ! -e $SKILLS/distill/SKILL.md ]]; then
        put "$SKILLS/distill/SKILL.md" <<'EOF'
---
name: distill
description: Review the current workspace's issue journal (.claude/friction.md, filled by /log) and propose rules for its CLAUDE.md. Use when the user invokes /distill. Groups similar entries, drafts short rules, waits for approval, applies the approved ones and archives processed entries.
---
<!-- installed by setup-workspace.sh -->

# /distill — turn the issue journal into rules

Turns raw `/log` notes into a few durable rules. Nothing changes before the user approves.

## Steps

1. **Find the workspace root** as `/log` does.
2. **Read `<workspace>/.claude/friction.md`.** No entries: say there is nothing to distill and stop.
3. **Read the existing rules:** `<workspace>/CLAUDE.md` and the shared `@ROOT@/Workspace/CLAUDE.md`.
4. **Group the entries by theme.** A single entry that isn't a pattern gets no rule.
5. **Draft one rule per theme:** one clear sentence, plus one verbatim quote from the journal as anchor, and where it goes (this workspace's `CLAUDE.md`, or the shared one if the theme recurs across workspaces). Prefer sharpening an existing rule to adding a new one; rules files stay short.
6. **Present all proposals in one response; apply nothing yet.** The user answers e.g. `apply 1, 3`, `apply all`, `skip 2`, or with edits.
7. **Apply the approved rules** with precise edits.
8. **Archive:** move the processed entries verbatim from `friction.md` to `friction.archive.md`.
9. **Log** to `@ROOT@/Workspace/setup_manager/logs/setup_log.txt`: `[YYYY-MM-DD] /distill: <workspace> — N rules, M entries archived`.

## Don't

- Apply rules without explicit approval, or resolve a contradiction with an existing rule yourself.
- Paraphrase or delete journal entries; archive them verbatim.
- Turn an entry about a fact you got wrong into a rule: fix the fact and archive the entry.
EOF
        record skill "$SKILLS/distill"
    fi
    if [[ ! -e $SKILLS/test-setup/SKILL.md ]]; then
        put "$SKILLS/test-setup/SKILL.md" <<'EOF'
---
name: test-setup
description: Test the whole setup (toolchains, extensions, settings, logs), ask the person to try a few things, and write a report. Changes nothing. Only when the user types /test-setup.
disable-model-invocation: true
---
<!-- installed by setup-workspace.sh -->

# /test-setup - test this setup (macOS)

You are testing this setup, not repairing it. It takes about 20 minutes, with questions for the
person at the end.
- Change nothing: no settings, profiles, packages, shell files, or other files. The exceptions are a
  temporary folder (mktemp -d), the test project in F (you remove it again), and the report.
- Never run the setup with --uninstall or --add. Never run brew install, uninstall or upgrade, and
  never use sudo.
- When you run the setup script, always add --no-gui. Without it, the script opens dialogs.
- Keep going after a failure: record it and continue. Batch commands to save time.
- Write ~ for the home folder. Never copy secrets, tokens, or the Git name or email into the report;
  write "set" or "not set" instead.
- Result words: PASS, FAIL, WARN (works, but something is off), SKIP (not installed or not applicable).
- Don't fix anything. For each FAIL or WARN, add your guess at the cause, and mark it "guess"
  unless you verified it.

Names used below. ROOT is @ROOT@, WS is ROOT/Workspace, and SM is WS/setup_manager.
This test expects to run in Setup Manager, with SM as the current folder. If it doesn't, tell the
person and mark E1 SKIP. The languages are the "profile" lines in SM/installed.txt: tab-separated,
with key, profile name, and folder id. The key setup_manager is not a language.
VSC is ~/Library/Application Support/Code.

A. THE INSTALL
A1  md5 -q SM/scripts/setup-workspace-mac.sh, and its SCRIPT_VERSION line. Record both.
A2  System: sw_vers, uname -m, sysctl -n machdep.cpu.brand_string, the battery state
    (pmset -g batt | head -2), free space on ~ (df -h ~), and the login shell
    (dscl . -read ~ UserShell).
A3  SM/setup.conf as it is. From SM/installed.txt: the profile lines (key and name) and the count of
    lines of each kind.
A4  The install logs, SM/logs/install-*.log. List them with dates. In each, find the lines matching
    "^== |^error|DOES NOT WORK|Stopped at|Setup stopped|Not finished|: works$". Record those lines:
    at most 60 from the newest log and 15 from each older one. PASS if the newest log has no
    error, DOES NOT WORK, or Stopped at.
A5  bash SM/scripts/setup-workspace-mac.sh --check --no-gui. Record the exit code and the result lines.
A6  Homebrew: brew --version (first line) and brew --prefix (expected: /opt/homebrew).
    Record brew doctor's first 15 lines; WARN only, since it often has harmless warnings.
A7  The login shell's PATH, as a new Terminal window gets it. Run:
        zsh -lc 'command -v bash python3 code latexmk cargo clang++'
    bash and python3 should be under /opt/homebrew, latexmk under /Library/TeX/texbin, and cargo under
    ~/.cargo/bin. Record the setup's block in ~/.zprofile (between the "setup-workspace" markers), and
    in ~/.bash_profile if the login shell is bash.

B. THE LANGUAGES (SKIP any language that isn't installed; build in the temporary folder)
B1  Python: WS/.venv/bin/python --version. Import numpy, pandas, matplotlib and ipykernel in one
    command. Run WS/python/scratch/hello.py with it.
    Run WS/.venv/bin/jupyter kernelspec list. Check where the link WS/python/.venv points (readlink).
B2  C++: xcode-select -p, clang++ --version (first line), and xcrun -f clangd. Copy
    WS/cpp/scratch/hello.cpp to the temporary folder, compile it with clang++ -std=c++2b, and run it.
B3  LaTeX: /Library/TeX/texbin/latexmk -v (first line) and kpsewhich lmodern.sty. Copy
    WS/latex/scratch/hello.tex to the temporary folder and run latexmk -pdf -interaction=nonstopmode
    hello.tex there. PASS if hello.pdf exists.
B4  Bash: /opt/homebrew/bin/bash --version (expected 5.x; /bin/bash is Apple's 3.2) and
    shellcheck --version. Run shellcheck on WS/bash/scratch/hello.sh, then run it with Homebrew's bash.
B5  Rust: ~/.cargo/bin/rustc --version and ~/.cargo/bin/cargo --version. In WS/rust, run:
    cargo run -q --bin hello, then cargo metadata -q --no-deps --format-version 1 >/dev/null

C. VS CODE
C1  code --version (first two lines). Where VS Code lives (/Applications or ~/Applications), and
    ls -l /opt/homebrew/bin/code.
C2  For each profile name in installed.txt, Setup Manager included:
        code --list-extensions --show-versions --profile "<name>"
    The expected list for each profile is BASE_EXTENSIONS plus that language's extension column in the
    table at the top of SM/scripts/setup-workspace-mac.sh. FAIL if any are missing. Record the versions.
C3  For each folder id: VSC/User/profiles/<id>/settings.json and globalStorage/ exist.
    The Claude bypass keys (claudeCode.allowDangerouslySkipPermissions, claudeCode.initialPermissionMode)
    must be present exactly when BYPASS=1 in setup.conf. In the Python profile,
    terminal.integrated.env.osx must point to WS/.venv. In the C++ profile, if clangd.path is set, that
    file must exist.
C4  Trust: is WS listed as trusted in both of these? Key content.trust.model.key, opened read-only with
    python3, sqlite3 and a "file:...?mode=ro" URI:
        VSC/User/globalStorage/state.vscdb
        ~/.vscode-shared/sharedStorage/state.vscdb
    PASS if WS is in the one under .vscode-shared.
C5  The newest folder in VSC/logs/: count the lines in the exthost logs that match
    "Cannot find module|failed to activate|Activating extension .* failed". Quote up to 5 different ones.

D. LAUNCHER, SKILLS, GIT
D1  ~/Applications/VS Launcher.app and ROOT/launcher.sh exist. Record bash ROOT/launcher.sh --list,
    codesign -v on the app (record its output), and
    xattr -l on the app (is there a quarantine flag?).
D2  ~/.claude/skills/log/SKILL.md and ~/.claude/skills/distill/SKILL.md exist.
D3  git --version. Are user.name and user.email set (yes or no)? WS/CLAUDE.md must contain the line
    about committing exactly when both are set.

E. YOU, CLAUDE, IN THIS SETUP
E1  Before reading any file: which CLAUDE.md files came with your instructions in this session? Name
    them and quote the first heading of each. Then read WS/CLAUDE.md and SM/CLAUDE.md and compare.
    PASS if both were loaded.
E2  Are /log and /distill in your list of available skills?
E3  The Claude Code extension's version (from C2). Your permission mode, if you can tell. Does your
    shell see Homebrew? Run command -v brew python3 in your own shell.

F. NEW PROJECT (only if Python is installed)
F1  In WS/python, take the "New project" task's command from .vscode/tasks.json and run it the way VS
    Code would, with PROJECT_NAME=zz-setup-test. Replace its final `code "..."` call with `true`, so no
    window opens.
    Check: projects/zz-setup-test/ holds main.py and a .git folder. A commit exists exactly when Git's
    name and email are set. Then delete projects/zz-setup-test (this test created it).
F2  The same with PROJECT_NAME=../zz-escape. It must be refused with exit code 1, and nothing may be
    created outside projects/.

G. ASK THE PERSON (one at a time; record the answer in a few words; "skip" means SKIP)
G1  The install. Did the language list appear as a window, and could you pick several with Cmd-click?
    Did the other dialogs appear in front, or behind Terminal?
G2  The install. Did Terminal ask for your password, and was it clear what to type? Did Homebrew's own
    installer, or Apple's command line tools, open a window or ask anything? Did macOS ask whether
    Terminal may control VS Code, or read Downloads? What did you answer? How long did the install take?
G3  Is VS Launcher in Spotlight with VS Code's icon? Does it open on the first try, or did macOS warn
    about it? Is Setup Manager on top, with every language listed? Does each one open in its own
    colours? Was the first start slow?
G4  Python: open scratch/hello.py and click the run button (top right). What is printed? Then set a
    breakpoint and press F5. Does it stop there?
G5  Notebook: open scratch/hello.ipynb and click Run All. Which kernel choices appear? Choose Python
    Environments, then .venv (Recommended). Does the plot show?
G6  C++ (if installed): run button on hello.cpp, then F5 with a breakpoint. Did macOS ask for a password
    (Developer Tools Access)?
G7  LaTeX (if installed): open hello.tex from a workspace opened with VS Launcher, add a space, and
    save. Does a PDF tab with the formula appear, or an error that latexmk wasn't found?
G8  Bash and Rust (if installed): the run button on scratch/hello.sh and on scratch/src/bin/hello.rs.
G9  Type in this Claude panel: /log test entry from the test run
    Then you check that SM/.claude/friction.md has that entry.
G10 During this test, did VS Code ask you to approve any command or file change? With bypass mode on,
    it shouldn't have. Was anything else confusing, slow, or wrong?

THE REPORT
Write SM/logs/test-report-<YYYY-MM-DD_HHMM>.txt in this layout:

    TEST REPORT  setup-workspace-mac.sh (macOS)
    Date:
    Script version and md5:
    System:
    Languages:
    Summary: <n> PASS, <n> FAIL, <n> WARN, <n> SKIP. Failed: <IDs>

    RESULTS
    A1  PASS  <short evidence: the key output, or the error line word for word>
    ...one line per check, in the order above...

    ANSWERS FROM THE PERSON
    G1  <answer>
    ...

    FAILURES IN DETAIL
    <for each FAIL and WARN: the command, its output (at most 30 lines), your guess at the cause>

    INSTALL LOG EXCERPT
    <the newest install log: the A4 lines, then its last 40 lines>

Then tell the person the report's path and its Summary line. To share it: on the project's GitHub
page, Issues, New issue, "Test report or problem", and attach the file. Issues are public, so they
should read the report first. Don't fix anything unless they ask.
EOF
        record skill "$SKILLS/test-setup"
    fi
}

write_conf() { # saved before installing, so a rerun after a failure keeps the choices
    mkdir -p "$SM"
    cat > "$CONF" <<EOF
# Choices of setup-workspace-mac.sh; reruns read them. Edit only if you know why.
PROFILES=$(IFS=,; echo "${SELECTED[*]}")
BYPASS=$BYPASS
EOF
}

write_readme() {
    local f=$SM/README.md key name rows="" pkgs claude backup cmd
    if [[ -f $SM/scripts/setup-workspace-mac.sh ]]; then cmd="bash $(show "$SM")/scripts/setup-workspace-mac.sh"
    else cmd="bash setup-workspace-mac.sh --root $(show "$ROOT")"; fi   # no copy: started as curl | bash
    while IFS=$'\t' read -r key name _; do
        [[ -n $key && $key != setup_manager ]] || continue
        rows+="| $name | \`Workspace/$key/\` | $(p_field "$key" 8) |"$'\n'
    done <<< "$(manifest_lines profile)"
    pkgs=$( { manifest_lines formula; manifest_lines cask; } | grep -c . || true)
    if ((BYPASS)); then claude='Bypass mode is on: Claude acts without asking for each step (turn off: Settings > "Claude Code: Initial Permission Mode").'
    else claude='Claude asks before each action.'; fi
    if [[ $(manifest_lines backup) == none ]]; then backup=': there were none'; else backup=' are in `backup/`'; fi
    cat > "$f" <<EOF
# Your VS Code setup

Made by \`scripts/setup-workspace-mac.sh\` $SCRIPT_VERSION on $TODAY. Everything it added is listed in \`installed.txt\`.

## Open a workspace

Start **VS Launcher** (Spotlight: Cmd+Space, type "VS Launcher"; it is in ~/Applications) and pick a workspace. Each one opens with its own colour-coded VS Code profile.

| Profile | Folder | Contents |
|---|---|---|
$rows| Setup Manager | \`Workspace/setup_manager/\` | This setup: sees the whole Workspace folder and VS Code's settings and profiles |

First time:
- The Workspace folder is marked as trusted in VS Code, so run buttons, tasks and the debugger work there.
- C++/Rust: the first F5 downloads the debugger's platform part (about a minute).
- **Claude Code**: click the Claude icon (top right of an open file, or the side bar) and sign in once; it needs a paid Claude plan or API account (the free plan doesn't include it). $claude

## Work

- Try the \`hello\` file in each workspace's \`scratch/\` (Rust: \`scratch/src/bin/hello.rs\`): the **run button** (top right) runs the file, **F5** debugs it (Python, C++, Rust), LaTeX builds the PDF on save, Python's \`hello.ipynb\` runs cells.
- F5, the run button and the C++/Rust build task use the current file only. Rust projects with crates: \`cargo run\`. C++ with several files: your own build, for example CMake.
- Deleting a Rust project: also remove its line from \`members\` in \`rust/Cargo.toml\`, or cargo fails for the whole folder.
- Notebooks: the first time you run a notebook, VS Code asks for a kernel: choose **Python Environments**, then **.venv** (Recommended; \`Workspace/.venv\`). It remembers the choice.
- New project: **Terminal > Run Task > New project**: copies \`templates/basic/\` to \`projects/<name>/\` and starts its version history (git), with a first commit if Git has your name and email. Nothing is uploaded.
- Undo what Claude did: hover over a message in the Claude panel and choose **Rewind code to here**. It covers files Claude edited, not what you changed yourself; git is the long-term history.
- Git commits need your name and email; if you skipped that question: \`git config --global user.name "Your Name"\`, then the same for \`user.email\`.
- Python packages: \`Workspace/.venv/bin/pip install <package>\`.
- LaTeX packages that BasicTeX lacks: \`sudo tlmgr install <package>\`; another language for babel: \`sudo tlmgr install babel-<language> hyphen-<language>\`.
- Claude reads \`Workspace/CLAUDE.md\` (shared rules) and the workspace's own \`CLAUDE.md\` (language rules). \`/log <note>\` collects friction, \`/distill\` turns it into rules.

## Change the setup

- Test that everything still works: \`$cmd --check\`.
- Check everything in detail: type \`/test-setup\` in Setup Manager's Claude panel. Claude tests the whole setup, asks you to try a few things and writes a report to \`logs/\`. It changes nothing.
- Add a language (quit VS Code first): \`$cmd --add rust\`. Available: $ALL_KEYS.$( [[ -f $SM/scripts/setup-workspace-mac.sh ]] || echo " (Download setup-workspace-mac.sh again first: this setup was started as a one-liner, so there is no copy in \`scripts/\`.)")
- Changes are logged in \`logs/setup_log.txt\`; each install's details in \`logs/install-*.log\`.
- Your VS Code settings from before the setup$backup. The setup never changed them.

## Uninstall

\`$cmd --uninstall\` shows everything from \`installed.txt\` and removes what you tick: profiles, the launcher app, Claude skills, the Python environment, the $pkgs Homebrew packages it installed. Nothing that was there before. Your files stay unless you tick the Workspace folder; removed folders go to \`$(show "$ROOT")/Trash/\`. Claude's login and chat history stay, because they are Claude's own files; \`/logout\` in Claude signs out.
EOF
}

finish() {
    step "Finishing"
    local names=() key
    write_readme
    for key in "${SELECTED[@]}"; do names+=("$(p_name "$key")"); done
    {
        printf '\n[%s] setup-workspace-mac.sh: %s\n' "$TODAY" "$1"
        printf -- '- Profiles: %s (+ Setup Manager); Claude bypass mode: %s\n' "${names[*]}" "$( ((BYPASS)) && echo on || echo off)"
        printf -- '- Homebrew packages added this run: %s; details: logs/%s\n' "$NEW_PKGS" "$(basename "$LOG")"
        if ((${#FAILED[@]})); then printf -- '- Extensions NOT installed: %s\n' "${FAILED[*]}"; fi
    } >> "$SM/logs/setup_log.txt"
}

# ─── Uninstall ────────────────────────────────────────────────────────────────────────────────
trash() { # path [subfolder] — move into Trash/<date>/ instead of deleting
    local dest=$TRASH/${2:-files}
    [[ -e $1 || -L $1 ]] || return 0
    mkdir -p "$dest"
    mv "$1" "$dest/$(basename "$1")-$(date +%H%M%S)"
}

uninstall() {
    [[ -f $MANIFEST ]] || fail "Nothing to uninstall: $(show "$MANIFEST") not found."
    cd "$HOME"   # the Workspace folder may be moved away below
    LOG=$SM/logs/uninstall-$(date +%F_%H%M).log
    : > "$LOG"
    find_brew || true
    PYTHON=""
    if [[ -n $BREW_PREFIX && -x $BREW_PREFIX/bin/python3 ]]; then PYTHON=$BREW_PREFIX/bin/python3; elif [[ -x /usr/bin/python3 ]]; then PYTHON=/usr/bin/python3; fi
    local menu="" formulas casks vscode_cask="" profiles created d
    profiles=$(manifest_lines profile)
    formulas=$(manifest_lines formula | paste -s -d' ' -)
    casks=$(manifest_lines cask | grep -vx visual-studio-code | paste -s -d' ' - || true)
    if manifest_lines cask | grep -qx visual-studio-code; then vscode_cask=visual-studio-code; fi
    created=$(manifest_lines created | while IFS= read -r d; do if [[ -e $d ]]; then show "$d"; echo; fi; done | paste -s -d, - | sed 's/,/, /g')
    # id|default|description, one per line
    [[ -z $profiles ]] || menu+="profiles|1|VS Code profiles: $(cut -f2 <<< "$profiles" | paste -s -d, - | sed 's/,/, /g')"$'\n'
    [[ -z $(manifest_lines app)$(manifest_lines link) ]] || menu+="app|1|The VS Launcher app and the setup's code command"$'\n'
    [[ -z $(manifest_lines skill) ]] || menu+="skills|1|The Claude Code skills the setup added"$'\n'
    [[ -z $(manifest_lines trust) ]] || menu+="trust|1|VS Code's trust for $(manifest_lines trust | while IFS= read -r d; do show "$d"; echo; done | paste -s -d, - | sed 's/,/, /g')"$'\n'
    [[ -z $(manifest_lines kernel) ]] || menu+="kernel|1|Jupyter kernel \"Python (Workspace)\""$'\n'
    [[ -z $(manifest_lines venv) ]] || menu+="venv|1|Python environment Workspace/.venv"$'\n'
    [[ -z $(manifest_lines homedir) ]] || menu+="rust|1|Rust toolchain (~/.rustup, ~/.cargo)"$'\n'
    [[ -z $formulas$casks ]] || menu+="brew|1|Homebrew packages the setup installed: $formulas $casks"$'\n'
    [[ -z $vscode_cask ]] || menu+="vscode|0|VS Code itself, with its settings and extensions folders (the setup installed it)"$'\n'
    [[ -z $(manifest_lines shellblock) ]] || menu+="shell|1|The setup's lines in ~/.zprofile (Rust PATH; the Homebrew line stays while Homebrew stays)"$'\n'
    [[ -z $created ]] || menu+="created|0|Cache folders the tools created: $created"$'\n'
    [[ -z $(manifest_lines homebrew) ]] || menu+="homebrew|0|Homebrew itself (the setup installed it; other programs may use it)"$'\n'
    [[ -z $(manifest_lines gitkey) ]] || menu+="gitid|0|Your Git name and email (in ~/.gitconfig)"$'\n'
    menu+="workspace|0|The Workspace folder, including your own files"$'\n'

    local selected="" id def desc reply chosen
    if ((GUI)); then
        chosen=$(choose "Remove what the setup added. Selected items are removed; nothing that existed before is touched." \
            "$(awk -F'|' '$2 == 1 { print $3 }' <<< "$menu")" "$(awk -F'|' 'NF { print $3 }' <<< "$menu")") || cancelled
        while IFS='|' read -r id def desc; do
            [[ -n $id ]] || continue
            if grep -qxF -- "$desc" <<< "$chosen"; then selected+=",$id"; fi
        done <<< "$menu"
    else
        ((TTY)) || die "uninstall asks what to remove: start it from Terminal"
        say "Uninstall: answer y/n for each item (Enter = the default)."
        while IFS='|' read -r id def desc; do
            [[ -n $id ]] || continue
            read -rp "  Remove: $desc? [$( ((def)) && echo Y/n || echo y/N)] " reply </dev/tty || reply=""
            case $(lower "$reply") in y*) def=1 ;; n*) def=0 ;; esac
            if ((def)); then selected+=",$id"; fi
        done <<< "$menu"
    fi
    selected="$selected,"
    [[ $selected != "," ]] || exit 0
    has() { [[ $selected == *",$1,"* ]]; }
    # Without Homebrew its shellenv line would make every new Terminal print an error.
    if has homebrew && [[ -n $(manifest_lines shellblock) ]] && ! has shell; then selected+="shell,"; fi

    if has profiles || has trust || has vscode || has created; then close_vscode; fi
    if has brew || has vscode || has homebrew; then need_sudo; fi

    progress_start 10
    local key name location path
    if has profiles; then
        step "Removing VS Code profiles"
        while IFS=$'\t' read -r key name location; do
            [[ -n $key ]] || continue
            py remove-profile "$STORAGE" "$location"
            trash "$VSC_USER/profiles/$location" vscode-profiles
            unrecord profile "$key" "$name" "$location"
            say "  removed profile $name"
        done <<< "$profiles"
    fi
    if has app; then
        step "Removing the VS Launcher app"
        while IFS= read -r path; do [[ -z $path ]] || { trash "$path" launcher; unrecord app "$path"; }; done <<< "$(manifest_lines app)"
        while IFS= read -r path; do [[ -z $path ]] || { if [[ -L $path ]]; then rm -f "$path"; fi; unrecord link "$path"; }; done <<< "$(manifest_lines link)"
    fi
    if has skills; then
        step "Removing the Claude Code skills"
        while IFS= read -r path; do
            [[ -n $path ]] || continue
            if grep -qF "$MARKER" "$path/SKILL.md" 2>/dev/null; then trash "$path" claude-skills; fi
            unrecord skill "$path"
        done <<< "$(manifest_lines skill)"
    fi
    if has trust; then
        step "Removing the folders from VS Code's trusted folders"
        while IFS= read -r path; do [[ -z $path ]] || { py untrust "$STATE_DB" "$path"; unrecord trust "$path"; }; done <<< "$(manifest_lines trust)"
    fi
    if has kernel; then
        step "Removing the Jupyter kernel"
        while IFS= read -r path; do [[ -z $path ]] || { trash "$path" jupyter-kernel; unrecord kernel "$path"; }; done <<< "$(manifest_lines kernel)"
    fi
    if has venv; then
        step "Removing the Python environment"
        while IFS= read -r path; do [[ -z $path ]] || { trash "$path" python-env; unrecord venv "$path"; }; done <<< "$(manifest_lines venv)"
    fi
    if has rust; then
        step "Removing the Rust toolchain"
        while IFS= read -r path; do [[ -z $path ]] || { trash "$path" rust; unrecord homedir "$path"; }; done <<< "$(manifest_lines homedir)"
    fi
    local n
    if has gitid; then
        step "Removing your Git name and email"
        while IFS= read -r path; do
            if [[ -n $path ]]; then git config --global --unset "$path" </dev/null || true; unrecord gitkey "$path"; fi
        done <<< "$(manifest_lines gitkey)"
        if [[ -f $WS/CLAUDE.md ]]; then
            grep -vF 'Projects with git: commit when a change works' "$WS/CLAUDE.md" > "$WS/CLAUDE.md.setup-tmp" || true
            mv "$WS/CLAUDE.md.setup-tmp" "$WS/CLAUDE.md"
        fi
        while IFS= read -r path; do
            if [[ -z $path ]]; then continue; fi
            if [[ ! -s $path ]]; then trash "$path" home-folders; fi
            unrecord gitfile "$path"
        done <<< "$(manifest_lines gitfile)"
    fi
    if has brew && [[ -n $casks ]]; then
        step "Uninstalling $casks"
        # shellcheck disable=SC2086
        quiet "$BREW" uninstall --cask $casks || FAILED+=("$casks")
    fi
    if has vscode; then
        step "Uninstalling VS Code"
        # Without "App Management" permission for Terminal, macOS can refuse this.
        quiet "$BREW" uninstall --cask visual-studio-code || FAILED+=("visual-studio-code (allow Terminal in System Settings > Privacy & Security > App Management, then run this again)")
    fi
    if has brew && [[ -n $formulas ]]; then
        step "Uninstalling $formulas"
        # All at once, so Homebrew sees they only depend on each other. If something else still needs
        # one of them, Homebrew refuses the whole list: then one by one, in passes, until no pass
        # removes anything more (a dependency goes once what needed it is gone).
        # shellcheck disable=SC2086
        if ! quiet "$BREW" uninstall --formula $formulas; then
            local left=$formulas removed=1 next
            while ((removed)) && [[ -n $left ]]; do
                removed=0 next=""
                for n in $left; do
                    if quiet "$BREW" uninstall --formula "$n"; then removed=1; else next+="$n "; fi
                done
                left=${next% }
            done
            for n in $left; do FAILED+=("$n (still needed by other Homebrew packages)"); done
        fi
    fi
    if [[ -n $BREW ]]; then  # drop the lines of everything that is gone now
        for n in $(manifest_lines formula); do "$BREW" list --formula --versions "$n" >/dev/null 2>&1 || unrecord formula "$n"; done
        for n in $(manifest_lines cask); do "$BREW" list --cask --versions "$n" >/dev/null 2>&1 || unrecord cask "$n"; done
    fi
    if has shell; then
        step "Removing the setup's lines from the shell files"
        local keep_brew="" bline
        while IFS= read -r path; do
            [[ -n $path ]] || continue
            [[ -f $path ]] || { unrecord shellblock "$path"; continue; }
            mkdir -p "$TRASH"
            cp "$path" "$TRASH/$(basename "$path")-before-uninstall-$(date +%H%M%S)"
            # Without its shellenv line, Homebrew in /opt/homebrew drops off the PATH: it stays while Homebrew stays.
            keep_brew=""
            if ! has homebrew; then
                bline=$(block_of "$path" | grep 'brew shellenv' || true)
                if [[ -n $bline ]]; then keep_brew=$bline$'\n'; fi
            fi
            write_block "$path" "$keep_brew"
            if [[ -z $keep_brew ]]; then
                unrecord shellblock "$path"
                if [[ ! -s $path ]] && recorded file "$path"; then trash "$path" files; unrecord file "$path"; fi
            fi
        done <<< "$(manifest_lines shellblock)"
    fi
    if has vscode && ! "$BREW" list --cask --versions visual-studio-code >/dev/null 2>&1; then   # only once the app is really gone
        step "Moving VS Code's settings and extensions folders to the Trash"
        while IFS= read -r path; do [[ -z $path ]] || { trash "$path" home-folders; unrecord created-vscode "$path"; }; done <<< "$(manifest_lines created-vscode)"
    fi
    if has created; then
        step "Moving the cache folders to the Trash"
        while IFS= read -r path; do [[ -z $path ]] || { trash "$path" home-folders; unrecord created "$path"; }; done <<< "$(manifest_lines created)"
    fi
    if has homebrew; then
        step "Uninstalling Homebrew"
        local tmp
        tmp=$(mktemp -d)
        if quiet curl -fsSL --connect-timeout 20 --speed-time 60 --speed-limit 1000 --retry 5 --retry-all-errors -o "$tmp/uninstall.sh" https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh &&
            NONINTERACTIVE=1 quiet /bin/bash "$tmp/uninstall.sh"; then
            unrecord homebrew "$BREW_PREFIX"
        else
            FAILED+=(Homebrew)
        fi
        rm -rf "$tmp"
    fi
    {
        printf '\n[%s] setup-workspace-mac.sh --uninstall\n' "$TODAY"
        printf -- '- Removed: %s\n' "$(tr ',' ' ' <<< "$selected" | xargs)"
        printf -- '- Moved (not deleted) to %s\n' "$TRASH"
        if ((${#FAILED[@]})); then printf -- '- NOT removed: %s\n' "${FAILED[*]}"; fi
    } >> "$SM/logs/setup_log.txt"
    while IFS= read -r path; do   # folders the setup created that hold no files now (deepest first)
        [[ -n $path ]] || continue
        if [[ -d $path ]]; then find "$path" -depth -type d -empty -delete 2>/dev/null || true; fi
        if [[ ! -e $path ]]; then unrecord emptydir "$path"; fi
    done <<< "$(manifest_lines emptydir | sort -r)"
    if has workspace; then
        step "Moving the Workspace folder to the Trash"
        LOG=""   # it is inside the folder that moves
        mkdir -p "$TRASH"
        mv "$WS" "$TRASH/Workspace-$(date +%H%M%S)"
        if [[ -e $ROOT/launcher.sh ]]; then mv "$ROOT/launcher.sh" "$TRASH/"; fi
    fi
    local msg
    msg="Uninstall finished. Removed folders are in $(show "$TRASH")."
    if ((${#FAILED[@]})); then msg+=$'\n\n'"Could not remove (see the log): ${FAILED[*]}"; fi
    info "$msg"
}

# ─── Main ─────────────────────────────────────────────────────────────────────────────────────
has_key() { [[ " ${SELECTED[*]} " == *" $1 "* ]]; }
# Notebooks used to be a language of their own, "jupyter": they are part of Python now.
normalize() { tr 'A-Z ' 'a-z,' <<< "$1" | tr -s ',' | sed 's/^,//; s/,$//; s/c++/cpp/g; s/jupyter/python/g'; }

# One run at a time: two at once would both create the same profiles.
LOCK=${TMPDIR:-/tmp}/setup-workspace-$(id -u).lock LOCKED=0
take_lock() {
    if ! mkdir "$LOCK" 2>/dev/null; then
        local pid
        pid=$(cat "$LOCK/pid" 2>/dev/null || true)
        if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then fail "The setup is already running (process $pid)."; fi
        rm -rf "$LOCK"; mkdir "$LOCK"   # left over from a run that was killed
    fi
    echo $$ > "$LOCK/pid"
    LOCKED=1
}

# Everything runs from here, after the whole file has been read: a download cut off halfway
# (curl | bash) then fails to parse instead of running half a script.
# What Homebrew needs. Better said now than as "Installing Homebrew failed" after the password.
check_platform() {
    if [[ $(sysctl -in sysctl.proc_translated 2>/dev/null) == 1 ]]; then
        fail "Terminal runs under Rosetta here. Untick \"Open using Rosetta\" (Finder > Applications > Utilities > Terminal > Get Info), then start the setup again."
    fi
    if [[ $(uname -m) != arm64 ]]; then
        fail "This setup needs an Apple Silicon Mac: Homebrew no longer supports Intel Macs."
    fi
    local v
    v=$(sw_vers -productMajorVersion 2>/dev/null || echo 99)
    if ((v < 15)); then
        ask "This Mac runs macOS $v. Homebrew has no ready-made packages for it, so it would build them from source, which can take hours and may fail.

Better: update macOS first. Continue anyway?" "Continue" || cancelled
    fi
}

# Before the password: internet, clock, blocked servers, room.
check_internet() {
    local try=0 page date_h now server_time problem u blocked=""
    while :; do
        problem=""
        if ! page=$(curl -sS -i --max-time 12 http://captive.apple.com/hotspot-detect.html 2>/dev/null); then
            problem="No internet connection: the setup has to download programs. Connect to the internet (Wi-Fi? a proxy?)."
        elif ! grep -q Success <<< "$page"; then
            problem="A login page is answering instead of the internet (hotel, school, public Wi-Fi?): log in with the browser."
        else
            date_h=$(tr -d '\r' <<< "$page" | sed -n 's/^[Dd]ate: //p' | head -1)
            now=$(date +%s)
            server_time=$(date -j -u -f '%a, %d %b %Y %H:%M:%S GMT' "$date_h" +%s 2>/dev/null || echo "$now")
            if (( (now > server_time ? now - server_time : server_time - now) > 7200 )); then
                problem="This Mac's clock is wrong (it says $(date '+%Y-%m-%d %H:%M')), so secure downloads would fail. Set it in System Settings > General > Date & Time."
            fi
        fi
        [[ -n $problem ]] || break
        try=$((try + 1))
        if ((try > 5 || (!GUI && !TTY))); then fail "$problem"; fi
        ask "$problem

Then try again." "Try again" || cancelled
    done
    for u in raw.githubusercontent.com ghcr.io formulae.brew.sh update.code.visualstudio.com marketplace.visualstudio.com pypi.org; do
        curl -sSI --max-time 12 -o /dev/null "https://$u" 2>/dev/null || blocked+=" $u"
    done
    if [[ -n $blocked ]]; then
        ask "These servers can't be reached (firewall, proxy?):$blocked

The setup will probably fail. Continue anyway?" "Continue" || cancelled
    fi
}

existing_ancestor() { local d=$1; while [[ ! -e $d ]]; do d=$(dirname "$d"); done; printf '%s' "$d"; }
check_room() { # MB needed
    local free base t
    base=$(existing_ancestor "$ROOT")
    free=$(df -Pm "$base" | awk 'NR == 2 { print $4 }')
    if ((free < $1)); then
        ask "Only $((free / 1024)) GB of disk space is free; this needs about $(($1 / 1024 + 1)) GB. (Empty the Trash? macOS may also free some by itself.)

Continue anyway?" "Continue" || cancelled
    fi
    if ! t=$(mktemp -d "$base/.setup-test-XXXXXX" 2>/dev/null); then
        fail "$(show "$base") can't be written to. Choose another place: --root DIR"
    fi
    rm -rf "$t"
    local foreign
    foreign=$(find "$VSC_DIR" "$HOME/.vscode" ! -user "$(id -un)" -print -quit 2>/dev/null || true)
    if [[ -n $foreign ]]; then fail "$(show "$foreign") belongs to another user (VS Code run with sudo?). Fix it with: sudo chown -R $(id -un) \"$VSC_DIR\" ~/.vscode"; fi
}

main() {
[[ $(uname -s) == Darwin ]] || die "this is the macOS version; on Linux use setup-workspace.sh, on Windows setup-workspace.ps1."
[[ $EUID -ne 0 ]] || die "start this as your normal user, not with sudo: VS Code and your files must belong to you. The script asks for your password itself when it needs it."

take_lock
if ((UNINSTALL)); then uninstall; exit 0; fi
if ((CHECK)); then check_only; exit 0; fi
check_platform

# Earlier choices (rerun from the Setup Manager or with --add)
# Installed = has its profile. The saved choices may be from a run that stopped: they only preset the ticks.
INSTALLED=$(normalize "$(manifest_lines profile | cut -f1 | { grep -vx setup_manager || true; } | paste -s -d, -)")
chosen_before="" prev_bypass=""
if [[ -f $CONF ]]; then
    chosen_before=$(normalize "$(sed -n 's/^PROFILES=//p' "$CONF")")
    prev_bypass=$(sed -n 's/^BYPASS=//p' "$CONF")
    [[ -n $BYPASS ]] || BYPASS=$prev_bypass
fi
PROFILES=$(normalize "${PROFILES:-}")
ADD=$(normalize "$ADD")
if [[ -n $ADD ]]; then PROFILES=${chosen_before:+$chosen_before,}$ADD; fi

if ((GUI)) && [[ -z $ADD ]]; then
    preset=",${PROFILES:-${chosen_before:-$DEFAULT_PROFILES}},"
    labels="" defaults=""
    for key in $ALL_KEYS; do
        label="$(p_name "$key") - $(p_field "$key" 8)"
        if [[ ,$INSTALLED, == *",$key,"* ]]; then label="$(p_name "$key") (installed) - $(p_field "$key" 8)"; fi
        labels+=$label$'\n'
        if [[ $preset == *",$key,"* || ,$INSTALLED, == *",$key,"* ]]; then defaults+=$label$'\n'; fi
    done
    chosen=$(choose "Which languages? Each gets its own VS Code profile, folder and tools. Claude Code and a run button come with every one. (Claude Code needs a paid Claude plan or API account.) Cmd-click to select several." "$defaults" "$labels") || {
        if (($? != 2)); then cancelled; fi
        GUI=0; chosen=$defaults   # the default set, as with --no-gui
        say "(Windows can't open here: installing $(tr '\n' ' ' <<< "$chosen" | sed 's/ - [^-]*  */ /g'). Choose others with --profiles.)"
    }
    PROFILES=""
    while IFS= read -r line; do
        for key in $ALL_KEYS; do
            name=$(p_name "$key")
            if [[ $line == "$name - "* || $line == "$name (installed) - "* ]]; then PROFILES+=",$key"; fi
        done
    done <<< "$chosen"
    if [[ -z $PROFILES && -z $INSTALLED ]]; then info "No language selected, so nothing was installed."; exit 0; fi
    PROFILES=$(normalize "$PROFILES")
    if [[ -z $BYPASS ]]; then
        answer=$(osa -e 'display dialog "Bypass mode: Claude Code works without asking before each step. Faster, but it can change files and run commands without asking." with title "VS Code setup" buttons {"Cancel", "Ask before each step", "Bypass mode"} default button "Bypass mode" cancel button "Cancel"') || { if (($? == 2)); then GUI=0; answer="Bypass mode"; else cancelled; fi; }
        BYPASS=0
        [[ $answer == *"Bypass mode"* ]] && BYPASS=1
    fi
fi
PROFILES=${PROFILES:-${chosen_before:-$DEFAULT_PROFILES}}
if [[ -n $INSTALLED ]]; then PROFILES=$INSTALLED,$PROFILES; fi
BYPASS=${BYPASS:-1}
BYPASS_CHANGED=0
if [[ -n $prev_bypass && $prev_bypass != "$BYPASS" ]]; then BYPASS_CHANGED=1; fi
SELECTED=()
for key in $(tr ',' '\n' <<< "$PROFILES" | awk 'NF && !seen[$0]++'); do
    [[ " $ALL_KEYS " == *" $key "* ]] || die "unknown language '$key' (available: $ALL_KEYS)"
    SELECTED+=("$key")
done
((${#SELECTED[@]})) || die "no language selected"

ask_git_identity
close_vscode
check_internet
find_brew || true
find_code || true
MISSING_F=$(missing_brew formula | paste -s -d' ' -)
MISSING_C=$(missing_brew cask | paste -s -d' ' -)
names=()
for key in "${SELECTED[@]}"; do names+=("$(p_name "$key")"); done
summary="Languages: ${names[*]}  (+ Setup Manager)
Folder: $(show "$ROOT")"
if [[ -z $BREW ]]; then summary+="
Homebrew: will be installed first (with Apple's command line tools, if missing)"; fi
if [[ -n $MISSING_F$MISSING_C ]]; then summary+="
To install with Homebrew: $MISSING_F $MISSING_C"
else summary+="
Programs: all present"; fi
if [[ -d $VSC_USER && ! -f $MANIFEST ]]; then summary+="
VS Code settings: backed up first, and they stay unchanged"; fi
summary+="
Claude: bypass mode $( ((BYPASS)) && echo on || echo off)"
if [[ -n $GIT_NAME$GIT_EMAIL ]]; then summary+="
Git: commits as ${GIT_NAME:-(no name)} <${GIT_EMAIL:-no email}>"; fi
if has_key rust && ! "$HOME/.cargo/bin/rustc" --version >/dev/null 2>&1; then summary+="
Rust: toolchain download, about 300 MB"; fi
mb=800   # extensions and Python packages
if [[ -z $BREW ]]; then mb=$((mb + 1500)); fi   # Homebrew and Apple's command line tools
if [[ $MISSING_F == *python* ]]; then mb=$((mb + 150)); fi
if [[ $MISSING_C == *visual-studio-code* ]]; then mb=$((mb + 250)); fi
if [[ $MISSING_C == *basictex* ]]; then mb=$((mb + 700)); fi
if has_key rust && ! "$HOME/.cargo/bin/rustc" --version >/dev/null 2>&1; then mb=$((mb + 300)); fi
summary+="
Download: about $(((mb + 512) / 1024)) GB, disk: about $((mb * 3 / 1024 + 1)) GB. Keep the Terminal window open; this can take a while."
if [[ -z $BREW || -n $MISSING_C ]]; then summary+="

Terminal will ask for your password."; fi
check_room $((mb * 3))
say "$summary"
ask "$summary" "Install" || cancelled
write_conf
# Sleep would cut the network and stop the install; ends by itself when the script ends.
if command -v caffeinate >/dev/null; then caffeinate -ims -w $$ & disown $! 2>/dev/null || true; fi

# ─── Install ──────────────────────────────────────────────────────────────────────────────────
mkdir -p "$SM/logs"
LOG=$SM/logs/install-$(date +%F_%H%M).log
printf 'setup-workspace-mac.sh %s\n' "$SCRIPT_VERSION" > "$LOG"
if [[ ! -f $MANIFEST ]]; then
    printf '# Everything setup-workspace-mac.sh added (kind<TAB>value). --uninstall reads this file.\n' > "$MANIFEST"
fi
say ""
say "Installing. Details appear here and in $(show "$LOG"). Please keep this window open."
progress_start $((10 + ${#SELECTED[@]} * 3))
brew_before=$( { manifest_lines formula; manifest_lines cask; } | grep -c . || true)
note_new_home_dirs
backup_vscode
install_homebrew
set_git_identity
brew_tracking_on
install_packages core
brew_tracking_off
find_code || fail "VS Code is not available after installing it."
# The Claude extension needs 1.94 or newer; older ones would look like failed downloads.
vcv=$(code_cli --version 2>/dev/null | sed -n 1p)
if [[ $vcv =~ ^1\.([0-9]+) ]] && ((BASH_REMATCH[1] < 94)); then
    fail "This VS Code is too old ($vcv; the Claude extension needs 1.94 or newer). Update it (Code > Check for Updates), then start the setup again."
fi
# Homebrew's own Python: on Intel, /usr/local/bin/python3 may be python.org's.
PYTHON=$("$BREW" --prefix "$(python_formula || echo python)" 2>/dev/null)/bin/python3
[[ -x $PYTHON ]] || fail "Python is not available after installing it."
shell_block
make_setup_manager
add_commit_rule
close_vscode
setup_profile setup_manager "$SETUP_MANAGER_NAME" tools "$SETUP_MANAGER_RGB" "" ""
# Without this VS Code opens every workspace in Restricted Mode: no run button, tasks, debugger or
# Claude. Only the Workspace folder: other folders under the root (cloned repos) still ask.
for dir in "$WS" "$VSC_USER"; do
    if ! recorded trust "$dir"; then
        py trust "$STATE_DB" "$dir"
        record trust "$dir"
    fi
done
make_launcher
setup_skills
for key in "${SELECTED[@]}"; do install_language "$key"; done
NEW_PKGS=$(( $( { manifest_lines formula; manifest_lines cask; } | grep -c . || true) - brew_before ))
run_checks
finish "$( [[ -n $INSTALLED ]] && echo "added/repaired" || echo "installed")"

done_text="$(if ((${#CHECK_OK[@]})); then printf 'Done, and tested. Working: %s.' "$(printf '%s, ' "${CHECK_OK[@]}" | sed 's/, $//')"; else echo 'VS Code, Claude and Setup Manager are in place.'; fi)
Start \"VS Launcher\" (Spotlight: Cmd+Space, VS Launcher) and pick a workspace.

First time in VS Code:
 - Claude Code: open its panel and sign in once (needs a paid Claude plan or API account)
 - F5 may ask for your password once (macOS: Developer Tools Access)$(if has_key python; then printf '\n - Notebooks: the first run asks for a kernel: Python Environments, then .venv (Recommended)'; fi)

For the terminal: open a new Terminal window, this one doesn't know the new tools yet.

More: $(show "$SM")/README.md"
if ((${#FAILED[@]})); then
    say "Not installed:"; printf ' - %s\n' "${FAILED[@]}" >&4
    done_text="Not finished: ${#FAILED[@]} extensions could not be installed. VS Code says:
$(grep -E '^(Error|Failed Installing)' "$LOG" | tail -1 | cut -c1-120)

If that's the internet connection: connect and run this again, it only adds what is missing:
bash $(show "$SM")/scripts/setup-workspace-mac.sh"
fi
if ((${#CHECK_BAD[@]})); then
    done_text="Installed, but these don't work:
$(printf ' - %s\n' "${CHECK_BAD[@]}")

The rest of the setup is in place. To fix this, open Setup Manager in VS Launcher and ask Claude: its rules point to the log. Or run this again, it repairs what it can:
bash $(show "$SM")/scripts/setup-workspace-mac.sh
Details: $(show "$LOG")

$done_text"
fi
if ((${#NOTES[@]})); then done_text+="

Note:
$(printf ' - %s\n' "${NOTES[@]}")"; fi
info "$done_text"
}

main "$@"
