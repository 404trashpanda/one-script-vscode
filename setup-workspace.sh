#!/usr/bin/env bash
# setup-workspace.sh — a ready-to-use VS Code setup for several languages on Ubuntu/Debian:
# one colour-coded profile per language with its toolchain and extensions, Claude Code as the
# built-in agent, and a launcher menu that opens each workspace with its profile.
#
#   <root>/launcher.sh               "VS Launcher" in the app menu: pick a workspace
#   <root>/Workspace/<language>/     scratch/, projects/, templates/, the workspace's Claude rules
#   <root>/Workspace/setup_manager/  README.md, installed.txt (what was added), logs, this script
#
# Start it as your normal user (it asks for your password when it installs packages):
#   bash setup-workspace.sh             windows to pick languages and options (on a desktop)
#   bash setup-workspace.sh --help      all options
# Everything it adds is listed in setup_manager/installed.txt; --uninstall removes exactly that.
if [ -z "${BASH_VERSION:-}" ]; then echo "Please start this with: bash $0" >&2; exit 1; fi
set -euo pipefail
# The script reads the tools' output and compares sorted lists: same language and sort order everywhere
# (on a German system apt says "Installationskandidat", and sort and comm can disagree).
export LC_ALL=C.UTF-8
unset PYTHONHOME PYTHONPATH   # would redirect every Python below

SCRIPT_VERSION=1.0

# Where the published script can be downloaded. Started as a pasted one-liner (curl | bash) there is
# no file to copy into setup_manager/scripts/, so it is downloaded from here instead. Set when publishing.
SOURCE_URL=""

# ─── Profiles ─────────────────────────────────────────────────────────────────────────────────
# key|profile name|icon|background R G B|extensions|apt packages|extra profile settings (JSON)
# The key is also the workspace folder name. Icons: https://code.visualstudio.com/api/references/icons-in-labels
PROFILE_TABLE='
python|Python|snake|0 40 110|ms-python.python ms-python.vscode-pylance ms-python.debugpy ms-toolsai.jupyter|python3-venv python-is-python3 python3-tk|"python.terminal.executeInFileDir": true
cpp|C++|chip|90 68 0|llvm-vs-code-extensions.vscode-clangd vadimcn.vscode-lldb|build-essential clangd|"clangd.fallbackFlags": ["-std=c++23"], "code-runner.executorMap": {"python": "\"$pythonPath\" -u $fullFileName", "cpp": "cd $dir \u0026\u0026 g++ -std=c++23 $fileName -o $fileNameWithoutExt \u0026\u0026 $dir$fileNameWithoutExt"}
latex|LaTeX|mortar-board|58 0 95|james-yu.latex-workshop|texlive-latex-base texlive-latex-recommended texlive-latex-extra texlive-fonts-recommended texlive-pictures texlive-science latexmk|
bash|Bash|terminal-linux|10 80 10|mads-hartmann.bash-ide-vscode timonwong.shellcheck|shellcheck|
rust|Rust|robot|95 38 0|rust-lang.rust-analyzer vadimcn.vscode-lldb|rustup build-essential|"code-runner.executorMap": {"python": "\"$pythonPath\" -u $fullFileName", "rust": "cd $dir \u0026\u0026 rustc --edition 2024 $fileName \u0026\u0026 $dir$fileNameWithoutExt"}, "terminal.integrated.env.linux": {"PATH": "${env:HOME}/.cargo/bin:${env:PATH}"}
'
DEFAULT_PROFILES=python,cpp,latex,bash
declare -A P_INFO=(
    [python]="Python 3, notebooks, debugger, ready environment (numpy, pandas, matplotlib)"
    [cpp]="g++ compiler, clangd code help, debugger"
    [latex]="TeX Live + LaTeX Workshop: PDF builds on save (large download)"
    [bash]="Shell scripts with ShellCheck"
    [rust]="Rust toolchain (rustup), rust-analyzer, debugger"
)
BASE_EXTENSIONS="usernamehw.errorlens formulahendry.code-runner anthropic.claude-code"
BASE_PACKAGES="git curl zenity python3"
PY_PACKAGES="numpy pandas matplotlib ipykernel"
SETUP_MANAGER_NAME="Setup Manager"
SETUP_MANAGER_RGB="40 40 40"
COMMON_SETTINGS='"files.eol": "\n", "files.insertFinalNewline": true, "chat.disableAIFeatures": true, "code-runner.runInTerminal": true, "code-runner.saveFileBeforeRun": true, "code-runner.fileDirectoryAsCwd": true, "code-runner.ignoreSelection": true, "code-runner.executorMap": {"python": "\"$pythonPath\" -u $fullFileName"}'
BYPASS_SETTINGS='"claudeCode.allowDangerouslySkipPermissions": true, "claudeCode.initialPermissionMode": "bypassPermissions"'

declare -A P_NAME P_ICON P_RGB P_EXT P_PKG P_SET
ALL_KEYS=()
while IFS='|' read -r key name icon rgb ext pkg set; do
    [[ -n $key ]] || continue
    ALL_KEYS+=("$key")
    P_NAME[$key]=$name P_ICON[$key]=$icon P_RGB[$key]=$rgb P_EXT[$key]=$ext P_PKG[$key]=$pkg P_SET[$key]=$set
done <<< "$PROFILE_TABLE"

usage() {
    cat <<EOF
Usage: bash setup-workspace.sh [options]        (version $SCRIPT_VERSION)

On a desktop, windows ask which languages to set up. Without a desktop (or with --no-gui)
it installs the default set: $DEFAULT_PROFILES.

  --profiles LIST   languages to set up, comma-separated (available: ${ALL_KEYS[*]})
  --add LIST        add languages to an existing setup
  --root DIR        where everything goes (default: Code in your Documents folder)
  --no-bypass       Claude Code asks before each action (default: bypass mode, it doesn't)
  --terminal-log    record VS Code terminals so Claude can read what you ran (default: off)
  --no-gui          terminal only, no windows
  --check           test that the installed languages work; changes nothing
  --uninstall       remove what setup_manager/installed.txt lists (asks first)
  -h, --help        this text
EOF
}

# ─── Options ──────────────────────────────────────────────────────────────────────────────────
DIED=0
die() { DIED=1; printf 'error: %s\n' "$*" >&2; exit 1; }
FLATPAK_CHOICE="" UNAVAILABLE="" ROOT="" PROFILES="" ADD="" BYPASS="" TERMLOG="" NO_GUI=0 UNINSTALL=0 CHECK=0
ARGS=("$@")
while (($#)); do
    case $1 in
        --profiles) [[ $# -ge 2 ]] || die "--profiles needs a value"; PROFILES=$2; shift ;;
        --profiles=*) PROFILES=${1#*=} ;;
        --add) [[ $# -ge 2 ]] || die "--add needs a value"; ADD=$2; shift ;;
        --add=*) ADD=${1#*=} ;;
        --root) [[ $# -ge 2 ]] || die "--root needs a value"; ROOT=$2; shift ;;
        --root=*) ROOT=${1#*=} ;;
        --no-bypass) BYPASS=0 ;;
        --terminal-log) TERMLOG=1 ;;
        --no-gui) NO_GUI=1 ;;
        --check) CHECK=1 ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

# Run from its copy in Workspace/setup_manager/scripts/, the script belongs to that setup.
SELF=$(readlink -f "${BASH_SOURCE[0]:-}" 2>/dev/null || true)
if [[ -z $ROOT && $SELF == */Workspace/setup_manager/scripts/setup-workspace.sh ]]; then
    ROOT=${SELF%/Workspace/setup_manager/scripts/setup-workspace.sh}
fi
if [[ -z $ROOT ]]; then
    ROOT=$(xdg-user-dir DOCUMENTS 2>/dev/null || true)   # ~/Dokumente on a German system
    if [[ -z $ROOT || $ROOT == "$HOME" ]]; then ROOT=$HOME/Documents; fi
    ROOT=$ROOT/Code
fi
ROOT=$(realpath -m "$ROOT")
WS=$ROOT/Workspace
SM=$WS/setup_manager
MANIFEST=$SM/installed.txt
CONF=$SM/setup.conf
VENV=$WS/.venv
VSC_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/Code
VSC_USER=$VSC_DIR/User
STORAGE=$VSC_USER/globalStorage/storage.json
DESKTOP_FILE=${XDG_DATA_HOME:-$HOME/.local/share}/applications/vs-launcher.desktop
KERNEL_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/jupyter/kernels/workspace-venv
SKILLS=$HOME/.claude/skills
MARKER='<!-- installed by setup-workspace.sh -->'
TODAY=$(date +%F)
TRASH=$ROOT/Trash/$TODAY
LOG=""
FAILED=() NOTES=()

# ─── Output, questions, progress ──────────────────────────────────────────────────────────────
exec 4>&1
say()   { printf '%s\n' "$*" >&4; if [[ -n $LOG ]]; then printf '%s\n' "$*" >> "$LOG"; fi; }
warn()  { say "  ! $*"; }
logged() { if [[ -n $LOG ]]; then "$@" 2>&1 | tee -a "$LOG" >&4; else "$@" >&4 2>&1; fi; }   # output in the terminal and the log
show()  { printf '%s' "${1/#"$HOME"/\~}"; }

GUI=0
if ((!NO_GUI)) && [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && command -v zenity >/dev/null; then GUI=1; fi
TTY=0
if ( : </dev/tty ) 2>/dev/null; then TTY=1; fi
Z=(zenity --title="VS Code setup" --width=520)

info() { if ((GUI)); then "${Z[@]}" --info --no-wrap --no-markup --text="$1" 2>/dev/null || true; else say "$1"; fi; }
fail() { if ((GUI)); then "${Z[@]}" --error --no-markup --text="$1" 2>/dev/null || true; fi; die "$1"; }

cancelled() { say "Cancelled. (If no window appeared: windows can't open here; start it with --no-gui.)"; exit 0; }
ask() { # ask "question" [ok-label] -> success = yes
    if ((GUI)); then say "Waiting for your answer in the window (it may be behind this one)..."; "${Z[@]}" --question --no-wrap --no-markup --text="$1" --ok-label="${2:-Yes}" --cancel-label="Cancel" 2>/dev/null; return; fi
    ((TTY)) || return 0
    local reply
    read -rp "$1 [Y/n] " reply </dev/tty || reply=""
    [[ ${reply,,} != n* ]]
}

SUDO_KEEPER="" PROGRESS_PID="" STEP_NO=0 STEP_COUNT=1 CURRENT_STEP=""
progress_start() { # number of steps
    STEP_COUNT=$1 STEP_NO=0
    if ((GUI)); then
        exec 5> >("${Z[@]}" --progress --pulsate --auto-close --no-cancel --text="Starting..." 2>/dev/null)
        PROGRESS_PID=$!
    fi
}
step() {
    CURRENT_STEP=$1
    STEP_NO=$((STEP_NO + 1))
    say "== $1"
    if [[ -n $PROGRESS_PID ]] && kill -0 "$PROGRESS_PID" 2>/dev/null; then
        printf '# Step %d of about %d: %s\n' "$STEP_NO" "$STEP_COUNT" "$1" >&5 || true
    fi
}
progress_end() {
    if [[ -n $PROGRESS_PID ]]; then
        exec 5>&-
        PROGRESS_PID=""
    fi
}

# Any unexpected failure (set -e) ends up here: say where it stopped and where the details are.
on_exit() {
    local code=$1
    if [[ -n $SUDO_KEEPER ]]; then kill "$SUDO_KEEPER" 2>/dev/null || true; fi
    if ((${LOCKED:-0})); then rm -rf "$LOCK"; fi
    if [[ -n ${PREP_LOG:-} && -e $PREP_LOG ]]; then
        if ((code == 0 && !DIED)); then rm -f "$PREP_LOG"; else printf 'Log of the checks so far: %s\n' "$PREP_LOG" >&2; fi
    fi
    if ((${SOURCE_PENDING:-0})); then as_root rm -f "$SOURCE_FILE" >/dev/null 2>&1 || true; fi   # Cancel before Install
    if ((code != 0)); then record_new_pkgs; fi
    ((code != 0 && !DIED)) || return 0
    progress_end
    local msg="Setup stopped during: ${CURRENT_STEP:-preparation} (exit code $code)."
    if ((!DIED)) && [[ -n ${STOPPED_AT:-} ]]; then
        msg+=$'\n'"Stopped at ${STOPPED_AT:0:200}"
        if [[ -n $LOG ]]; then printf '%s\n' "Stopped at $STOPPED_AT" >> "$LOG"; fi
    fi
    if [[ -n $LOG ]]; then
        if tail -n 30 "$LOG" | grep -qE 'Unable to fetch|Failed to fetch|Temporary failure|Could not resolve|Could not connect|Connection (timed out|reset|refused)|Network is unreachable|ReadTimeoutError|NewConnectionError|curl: \([0-9]+\)'; then
            msg+=$'\n\nThis looks like a lost internet connection: check it first.'
        fi
        msg+=$'\n\nDetails: '"$(show "$LOG")"$'\n\nLast lines:\n'"$(tail -n 8 "$LOG" | cut -c1-110)"
    fi
    msg+=$'\n\nOnce the cause is fixed, running the script again continues where it stopped.'
    if ((GUI)); then "${Z[@]}" --error --no-markup --text="$msg" 2>/dev/null || true; fi
    printf '\n%s\n' "$msg" >&2
}

# ─── Sudo ─────────────────────────────────────────────────────────────────────────────────────
# In GUI mode the password stays in memory and goes to every sudo call: without a terminal,
# sudo's cached login is bound to the exact parent process, so it can't be relied on.
SUDO_PW=""
need_sudo() {
    [[ -z $SUDO_KEEPER && -z $SUDO_PW ]] || return 0
    if ! command -v sudo >/dev/null; then
        fail "sudo is not installed, so this account can't install software. As root (su -): apt install sudo; usermod -aG sudo $(id -un). Then log out and back in, and start the setup again."
    fi
    if ! sudo -n true 2>/dev/null; then
        if ! id -nG | grep -qwE 'sudo|admin|wheel'; then
            fail "This account is not an administrator, so it can't install software. Log in as an administrator, or ask one to add this account (sudo usermod -aG sudo $(id -un)); then log out and back in."
        fi
        if ((GUI)); then
            local tries=0 pw
            while :; do
                tries=$((tries + 1))
                ((tries <= 3)) || fail "Wrong password three times."
                say "Waiting for your password in the window (it may be behind this one)..."
                pw=$("${Z[@]}" --password --title="Password needed for system packages" 2>/dev/null) || cancelled
                if sudo -S -k -p '' true <<< "$pw" 2>/dev/null; then SUDO_PW=$pw; return 0; fi
            done
        fi
        ((TTY)) || die "a password is needed for system packages: start the script from a terminal or on the desktop"
        say "Your password is needed to install or remove packages."
        sudo -v </dev/tty || die "sudo failed"
    fi
    # Keep the sudo login fresh: a TeX Live download can outlast its 15 minutes.
    ( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &
    SUDO_KEEPER=$!
    disown "$SUDO_KEEPER" 2>/dev/null || true   # no "Terminated" message when it is stopped at the end
}
# Root commands get no stdin: no password left on it, and a prompt can't silently wait.
# With SUDO_PW, -k makes sudo read the password line every time, so stdin is used up.
as_root() {
    local v envs=(DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8)
    # sudo drops the proxy settings, and behind a proxy apt then finds nothing.
    for v in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
        if [[ -n ${!v:-} ]]; then envs+=("$v=${!v}"); fi
    done
    if [[ -n $SUDO_PW ]]; then sudo -S -k -p '' env "${envs[@]}" "$@" <<< "$SUDO_PW"
    else sudo env "${envs[@]}" "$@" </dev/null; fi
}
# Waits up to 10 minutes for the package lock (a fresh Ubuntu updates itself in the background),
# keeps changed config files without asking, and never removes packages while installing.
apt_get() {
    as_root apt-get -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}
set -E
trap 'STOPPED_AT="line $LINENO: $BASH_COMMAND"' ERR
trap 'on_exit $?' EXIT

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
    printf '%s\n' "${content//@ROOT@/"$ROOT"}" > "$file"
    chmod "$mode" "$file"
    record file "$file"
}
mkd() { local d; for d; do if [[ ! -d $d ]]; then mkdir -p "$d"; record dir "$d"; fi; done; }

# ─── VS Code state ────────────────────────────────────────────────────────────────────────────
vscode_pid() {
    local pid
    pid=$(cat "$VSC_DIR/code.lock" 2>/dev/null) || return 1
    [[ $pid =~ ^[0-9]+$ && $(ps -o comm= -p "$pid" 2>/dev/null) == code ]] || return 1
    echo "$pid"
}

close_vscode() { # VS Code rewrites its profile list when it exits, so it must be closed meanwhile
    local pid
    pid=$(vscode_pid) || return 0
    if [[ ${TERM_PROGRAM:-} == vscode || -n ${VSCODE_PID:-} ]]; then
        fail "This runs inside VS Code's terminal, and VS Code has to be closed while the setup changes its profiles. Close VS Code and run the same command in a normal terminal."
    fi
    ask "VS Code is open. It has to be closed while the setup changes its profiles.
Unsaved files are kept (VS Code restores them).

Close VS Code now?" "Close VS Code" || cancelled
    kill -TERM "$pid" 2>/dev/null || true
    for _ in {1..30}; do vscode_pid >/dev/null || return 0; sleep 0.5; done
    fail "VS Code did not close. Close it yourself and start the setup again."
}

# JSON edits (VS Code's profile list and settings files).
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
    colors = {k: dark for k in keys_dark} | {k: mid for k in keys_mid} | {k: lite for k in keys_lite}
    colors["titleBar.activeForeground"] = "#cccccc"
    colors["titleBar.inactiveForeground"] = "#999999"
    return colors

cmd, *args = sys.argv[1:]

if cmd in ("trust", "untrust"):  # STATE_DB FOLDER — VS Code's list of trusted folders (covers subfolders)
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
        save(args[0], data | missing)

elif cmd == "set-keys":         # FILE JSON -> sets these keys
    data.update(json.loads(args[1]))
    save(args[0], data)

elif cmd == "del-keys":         # FILE KEY... -> removes these keys
    if any(k in data for k in args[1:]):
        save(args[0], {k: v for k, v in data.items() if k not in args[1:]})
PY
)
# The system's Python: conda or pyenv may come first on the PATH, and the shared environment must not depend on them.
py3() { if [[ -x /usr/bin/python3 ]]; then /usr/bin/python3 "$@"; else python3 "$@"; fi; }
py() { py3 -c "$PY_HELPER" "$@"; }

# ─── Templates ────────────────────────────────────────────────────────────────────────────────
base_rules() {
    cat <<'EOF'
# Shared rules for every workspace

Loaded by Claude Code in every folder below this one (each workspace adds its own `CLAUDE.md`).

## Layout

- `Workspace/<language>/`: `scratch/` for experiments, `projects/<name>/` for projects (VS Code task "New project" copies `templates/basic/`).
- `Workspace/.venv/`: the shared Python environment. Install packages with `.venv/bin/pip install <package>`; never with sudo or system-wide.
- `Workspace/setup_manager/`: the setup itself (README.md, installed.txt, logs, the setup script).

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

- g++ (GCC) as C++23, with clangd for code help. Single files: the run button compiles and runs, F5 debugs (CodeLLDB), Ctrl+Shift+B only builds. All three build the current file only.
- Don't introduce a build system for a single-file program unless asked. Multi-file projects: generate `compile_commands.json` (CMake: `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) so clangd sees the real flags.
- Compile after every change; fix every error and warning you introduced.
EOF
        ;;
        latex) cat <<'EOF'
# LaTeX workspace

- TeX Live with latexmk; LaTeX Workshop builds on save and shows the PDF in a tab. Build files (.aux, .log, ...) are disposable.
- When transcribing or reformatting, keep content and wording exactly. Keep the document's macros and preamble; don't add a package when a loaded one does the job.
- After editing, build (`latexmk -pdf file.tex`) and fix the errors you introduced; report remaining warnings.
- You cannot see the PDF: don't claim the layout looks right.
- Missing for babel or biblatex: `sudo apt install texlive-lang-<language>`, `sudo apt install texlive-bibtex-extra biber`; for XeLaTeX or LuaLaTeX: `sudo apt install texlive-xetex`, `sudo apt install texlive-luatex` (tell the user).
EOF
        ;;
        bash) cat <<'EOF'
# Bash workspace

- Run scripts with `bash file.sh` (in VS Code: the run button); ShellCheck lints in the editor. LF line endings only.
- Small, reviewable changes; never rewrite a whole script when only part needs updating.
- Run the script after editing and check its output. On unexplained failures, check for CRLF line endings first.
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

- VS Code keeps its profile list in `~/.config/Code/User/globalStorage/storage.json` and rewrites it while running: never edit it with VS Code open.
- Adding a language the script knows: the user closes VS Code and runs `bash scripts/setup-workspace.sh --add <language>` in a terminal. Anything else: create the profile in VS Code (Manage > Profiles), install its extensions there, and add a workspace folder like the existing ones.
- Before changing profiles, settings.json, .code-workspace files or the launcher: say what you will change and wait for approval. One profile at a time.
- System packages need sudo: give the user the exact `sudo apt install ...` command to run.
- A language the install reported as failed: read the newest `logs/install-*.log`, find the cause, then fix it or give the user the command. `bash scripts/setup-workspace.sh --check` tests the installed languages.
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
            "command": "g++ -g -std=c++23 \"${file}\" -o \"${fileDirname}/${fileBasenameNoExtension}\"",
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
installed_pkgs() { dpkg-query -W -f='${Status} ${Package}\n' 2>/dev/null | awk '$3 == "installed" { print $4 }' | sort; }

missing_of() { # language keys (none: the basic set) -> wanted packages that are not installed
    local key wanted=() pkgs=()
    if (($# == 0)); then read -ra wanted <<< "$BASE_PACKAGES"; fi
    for key; do read -ra pkgs <<< "${P_PKG[$key]}"; wanted+=("${pkgs[@]}"); done
    # LaTeX in the system's language needs its own package (babel: "Unknown option ngerman").
    if [[ " $* " == *" latex "* ]]; then
        case ${LANG:-} in
            de*) wanted+=(texlive-lang-german) ;; fr*) wanted+=(texlive-lang-french) ;; es*) wanted+=(texlive-lang-spanish) ;;
            it*) wanted+=(texlive-lang-italian) ;; pt*) wanted+=(texlive-lang-portuguese) ;; pl*) wanted+=(texlive-lang-polish) ;;
            cs*|sk*) wanted+=(texlive-lang-czechslovak) ;; ru*|uk*|bg*) wanted+=(texlive-lang-cyrillic) ;;
            ja*) wanted+=(texlive-lang-japanese) ;; zh*) wanted+=(texlive-lang-chinese) ;; ko*) wanted+=(texlive-lang-korean) ;;
        esac
    fi
    # rustup conflicts with the distribution's rustc/cargo: keep a Rust that already works.
    if rustc --version >/dev/null 2>&1; then
        local w=() p; for p in "${wanted[@]}"; do [[ $p == rustup ]] || w+=("$p"); done; wanted=("${w[@]}")
    fi
    comm -23 <(printf '%s\n' "${wanted[@]}" | sort -u) <(installed_pkgs) | sed '/^$/d'
}
missing_packages() { { missing_of; missing_of "${SELECTED[@]}"; } | sort -u; }

download_mb() { # packages... -> download size in MB, including dependencies; nothing if apt can't tell
    local out
    out=$(apt-get install --print-uris -qq "$@" 2>/dev/null | awk '{ s += $3 } END { printf "%d", s / 1048576 }') || return 0
    printf '%s' "$out"
}

# ─── Package sources ───
# rustup, shellcheck and TeX Live are in Ubuntu's "universe" source, which can be switched off on a
# fresh install. It goes into a file of our own, so that the user's sources stay untouched and
# uninstalling just removes that file.
SOURCE_FILE=/etc/apt/sources.list.d/setup-workspace-universe.sources SOURCE_PENDING=0 CLOCK_TRIED=0 NET_TRIES=0 LOCK_WAITS=0

universe_configured() {
    # Not all of these files exist: cat's complaint must not count as "not configured".
    { cat /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true; } |
        grep -E '^[[:space:]]*(Components:|deb[[:space:]]).*[[:space:]]universe([[:space:]]|$)' >/dev/null
}

no_candidate() { # packages... -> those apt has no version of
    local p
    for p; do [[ $(apt-cache policy "$p" 2>/dev/null) == *"Candidate: "[!\(]* ]] || echo "$p"; done
}

# apt-get update, and what to do about the ways it goes wrong on real machines. Everything it prints is in the log.
refresh_lists() {
    local mark rc=0 out ok i
    say "Checking package lists..."
    mark=$(wc -l < "$LOG")
    logged apt_get update || rc=$?
    out=$(tail -n +"$((mark + 1))" "$LOG")
    # Another program is updating the lists (a new system does this by itself): its lock isn't
    # covered by the timeout for dpkg's lock.
    if grep -q 'Could not get lock' <<< "$out"; then
        LOCK_WAITS=$((LOCK_WAITS + 1))
        if ((LOCK_WAITS > 40)); then fail "Another program has been using the package system for 10 minutes. Close it (Software Updater?), or restart the computer, and start the setup again."; fi
        if ((LOCK_WAITS == 1)); then say "Another program is using the package system (a new system updates itself): waiting, up to 10 minutes..."; fi
        sleep 15
        refresh_lists
        return
    fi
    # A wrong clock makes apt refuse the lists, and would break the downloads too.
    if grep -q 'not valid yet' <<< "$out"; then
        if ((CLOCK_TRIED)); then
            fail "This computer's clock is wrong (it says $(date '+%Y-%m-%d %H:%M')), so the package lists are refused. Set the right date and time in Settings, then start the setup again."
        fi
        CLOCK_TRIED=1
        say "The computer's clock is wrong ($(date '+%Y-%m-%d %H:%M')): switching on automatic time sync..."
        logged as_root timedatectl set-ntp true || true
        for i in {1..20}; do
            if [[ $(timedatectl show -p NTPSynchronized --value 2>/dev/null) == yes ]] && ((i > 2)); then break; fi
            sleep 2
        done
        NOTES+=("The computer's clock was wrong, so automatic time sync was switched on (now $(date '+%Y-%m-%d %H:%M')).")
        refresh_lists
        return
    fi
    if ((rc == 0)) && ! grep -qE '^(W: Failed to fetch|W: Some index files failed)' <<< "$out"; then return 0; fi
    # How many sources really answered? ("Get:5" followed by "Err:5" is a failure.)
    ok=$(awk '/^Hit:/ { n++ } /^Get:[0-9]+/ { split($1, a, ":"); g[a[2]] = 1 } /^Err:[0-9]+/ { split($1, a, ":"); delete g[a[2]] }
              END { for (i in g) n++; print n + 0 }' <<< "$out")
    if ((ok == 0)); then   # no connection at all, or a login page answering instead of the server
        NET_TRIES=$((NET_TRIES + 1))
        if ((NET_TRIES > 5 || (!GUI && !TTY))); then
            fail "No internet connection: the package lists could not be downloaded. Connect to the internet (Wi-Fi? a login page in the browser? a proxy?), then start the setup again. Details: $(show "$LOG")"
        fi
        ask "No internet connection: the setup has to download packages.

Connect to the internet (Wi-Fi? a login page in the browser? a proxy?), then try again." "Try again" || cancelled
        refresh_lists
        return
    fi
    # Only some sources failed (a dead PPA, an old cdrom line): not a reason to stop. Whether all the
    # packages can be found gets checked next.
    say "Note: some package sources did not answer; carrying on with the others."
    NOTES+=("Some package sources on this computer did not answer: $(grep -E '^(E|W): .*(Release file|Failed to fetch)' <<< "$out" | head -2 | cut -c1-90 | paste -sd' ' -)")
}

enable_universe() {
    local codename uri tmp
    # shellcheck disable=SC1091
    codename=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
    uri=$(cat /etc/apt/sources.list.d/*.sources 2>/dev/null | awk '$1 == "URIs:" && $2 ~ /^https?:.*ubuntu/ { print $2; exit }')
    if [[ -z $uri ]]; then uri=$(awk '$1 == "deb" && $2 ~ /^https?:.*ubuntu/ { print $2; exit }' /etc/apt/sources.list 2>/dev/null); fi
    tmp=$(mktemp)
    cat > "$tmp" <<EOF
# Added by setup-workspace.sh (rustup, shellcheck, TeX Live); its --uninstall removes this file.
Types: deb
URIs: ${uri:-http://archive.ubuntu.com/ubuntu}
Suites: $codename $codename-updates $codename-security
Components: universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    chmod 644 "$tmp"
    logged as_root cp "$tmp" "$SOURCE_FILE"
    logged as_root chmod 644 "$SOURCE_FILE"
    rm -f "$tmp"
    SOURCE_PENDING=1   # kept only once the user says Install
}

existing_ancestor() { local d=$1; while [[ ! -e $d ]]; do d=$(dirname "$d"); done; printf '%s' "$d"; }

# Enough room? Rough but on the safe side: unpacked packages are about 3x their download.
check_disk() { # download size in MB
    local need free
    need=$(( ${1:-0} * 3 + 2000 ))
    if has_key rust; then need=$((need + 1500)); fi
    free=$(df -Pm / "$HOME" "$(existing_ancestor "$ROOT")" | awk 'NR > 1 { if (min == "" || $4 < min) min = $4 } END { print min }')
    ((free < need)) || return 0
    ask "Only $((free / 1024)) GB of disk space is free; this needs about $((need / 1024 + 1)) GB.

Continue anyway?" "Continue" || cancelled
}

# Better to find out now than after all the downloads: can things be created where they must go?
check_writable() {
    local base t foreign
    base=$(existing_ancestor "$ROOT")
    if ! t=$(mktemp -d "$base/.setup-test-XXXXXX" 2>/dev/null); then
        fail "$(show "$base") can't be written to, so the setup can't put its folder there. Choose another place: --root DIR"
    fi
    # The Python environment needs symlinks and running programs: some drives (NTFS, exFAT, noexec) refuse them.
    printf '#!/bin/sh\nexit 0\n' > "$t/x"; chmod +x "$t/x"
    if ! ln -s x "$t/y" 2>/dev/null || ! "$t/x" 2>/dev/null; then
        rm -rf "$t"
        fail "$(show "$base") can't hold programs (no links or no running programs on this drive). Choose a folder on the main drive: --root DIR"
    fi
    rm -rf "$t"
    # Left over from "sudo code": VS Code's own files belonging to root.
    foreign=$(find "$VSC_DIR" "$HOME/.vscode" ! -user "$(id -un)" -print -quit 2>/dev/null || true)
    if [[ -n $foreign ]]; then
        fail "$(show "$foreign") belongs to another user (VS Code run with sudo?). Fix it with: sudo chown -R $(id -un): $(show "$VSC_DIR") ~/.vscode"
    fi
}

# Sleep would cut the network and stop the install; ends by itself when the script ends.
stay_awake() {
    command -v systemd-inhibit >/dev/null || return 0
    systemd-inhibit --what=sleep:idle --who="VS Code setup" --why="Installing packages" tail --pid=$$ -f /dev/null >/dev/null 2>&1 &
    disown "$!" 2>/dev/null || true
}

# Before anything is installed: can apt get everything?
check_candidates() {
    ((${#MISSING[@]})) || return 0
    local none
    none=$(no_candidate "${MISSING[@]}" | paste -sd' ' -)
    [[ -n $none ]] || return 0
    # shellcheck disable=SC1091
    if [[ $(. /etc/os-release && echo "$ID") == ubuntu && ! -e $SOURCE_FILE ]] && ! universe_configured; then
        ask "Some of the packages are in Ubuntu's \"universe\" package source,
which is switched off on this computer.

Switch it on? (The setup's uninstall switches it off again.)" "Switch on" || cancelled
        enable_universe
        refresh_lists
        mapfile -t MISSING < <(missing_packages)
        none=$(no_candidate "${MISSING[@]}" | paste -sd' ' -)
        [[ -n $none ]] || return 0
    fi
    local p
    for p in $none; do
        if [[ " $BASE_PACKAGES " == *" $p "* ]]; then
            fail "This system has no package $p, which the setup can't do without. Nothing was installed. Details: $(show "$LOG")"
        fi
    done
    UNAVAILABLE=$none   # the languages needing them will fail and get reported; the others carry on
}

install_vscode() {
    local arch tmp
    case $(dpkg --print-architecture) in
        amd64) arch=x64 ;; arm64) arch=arm64 ;; armhf) arch=armhf ;;
        *) fail "There is no VS Code package for this computer's architecture." ;;
    esac
    tmp=$(mktemp -d)
    chmod 755 "$tmp"   # apt reads the file as user _apt
    say "Downloading VS Code (about 250 MB)..."
    curl -fL --progress-bar --connect-timeout 20 --speed-time 60 --speed-limit 1000 --retry 5 --retry-all-errors \
        -o "$tmp/code.deb" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-$arch" >&4 2>&1 ||
        fail "Downloading VS Code failed. Check the internet connection and start the setup again."
    # Microsoft's package adds their apt repository, so VS Code updates with the system.
    echo "code code/add-microsoft-repo boolean true" > "$tmp/debconf"
    logged as_root debconf-set-selections "$tmp/debconf"
    logged apt_get install -y --no-remove "$tmp/code.deb"
    rm -rf "$tmp"
}

# Packages that were not installed before (PKGS_BEFORE) and that apt itself reports setting up in
# this run's log, dependencies included: exactly what --uninstall may remove. Packages something
# else installs meanwhile (unattended-upgrades) are not in that output. Also called on exit, so a
# failed apt run still records what it installed. VS Code's own dependencies get their own kind:
# they go only together with VS Code.
PKGS_BEFORE="" PKG_KIND=apt LOG_MARK=0
record_new_pkgs() {
    local pkg
    [[ -n $PKGS_BEFORE && -n $LOG ]] || return 0
    for pkg in $(comm -12 <(comm -13 <(echo "$PKGS_BEFORE") <(installed_pkgs)) \
                          <(tail -n +"$((LOG_MARK + 1))" "$LOG" | sed -n 's/^Setting up \([^ :]*\).*/\1/p' | sort -u)); do
        recorded "$PKG_KIND" "$pkg" || record "$PKG_KIND" "$pkg"
    done
}

install_packages() {
    if ((${#MISSING[@]} == 0)) && command -v code >/dev/null; then return 0; fi
    step "Installing basic packages (${#MISSING[@]})$(command -v code >/dev/null || echo ' and VS Code')"
    PKGS_BEFORE=$(installed_pkgs) PKG_KIND=apt LOG_MARK=$(wc -l < "$LOG")
    # An earlier run stopped halfway through dpkg (Ctrl+C, closed terminal): finish that first.
    logged as_root dpkg --force-confdef --force-confold --configure -a || true   # does nothing if all is well
    if ((${#MISSING[@]})); then logged apt_get install -y --no-remove "${MISSING[@]}"; fi
    record_new_pkgs
    if ! command -v code >/dev/null; then
        PKGS_BEFORE=$(installed_pkgs) PKG_KIND=apt-vscode LOG_MARK=$(wc -l < "$LOG")
        install_vscode
        record vscode deb
        record_new_pkgs
    fi
    PKGS_BEFORE=""
}

# Folders created in the home folder, noted if missing before the first run. VS Code's own (settings,
# extensions) are removed only together with VS Code; the tools' caches are a separate, unticked item.
note_new_home_dirs() {
    local d
    for d in "$HOME/.vscode" "$HOME/.vscode-shared" "$VSC_DIR" "$HOME/.dotnet" "$HOME/.cache/Microsoft"; do
        if [[ ! -e $d ]] && ! recorded created-vscode "$d"; then record created-vscode "$d"; fi
    done
    for d in "$HOME/.ipython" "$HOME/.cache/pip" "$HOME/.cache/matplotlib"; do
        if [[ ! -e $d ]] && ! recorded created "$d"; then record created "$d"; fi
    done
    d=$(dirname "$(dirname "$KERNEL_DIR")")   # .../jupyter: other programs may use it too
    if [[ ! -e $d ]] && ! recorded emptydir "$d"; then record emptydir "$d"; fi
}

backup_vscode() { # once, on the first run: only a VS Code setup from before this script is backed up
    [[ -z $(manifest_lines backup) ]] || return 0
    if [[ ! -d $VSC_USER ]]; then record backup none; return 0; fi
    step "Backing up your VS Code settings"
    local items=() item file=$SM/backup/vscode-before-setup-$TODAY.tar.gz
    for item in settings.json keybindings.json snippets profiles globalStorage/storage.json; do
        if [[ -e $VSC_USER/$item ]]; then items+=("$item"); fi
    done
    if ((${#items[@]} == 0)); then record backup none; return 0; fi
    mkdir -p "$SM/backup"
    logged tar -czf "$file" --exclude='profiles/*/globalStorage' -C "$VSC_USER" "${items[@]}"
    record backup "$file"
}

# Optional, and only on a first run with no identity yet: Git works without it until the first commit.
GIT_NAME="" GIT_EMAIL=""
ask_git_identity() {
    [[ -z $INSTALLED ]] || return 0
    if command -v git >/dev/null && [[ -n $(git config --global user.name || true)$(git config --global user.email || true) ]]; then return 0; fi
    if ((GUI)); then
        local answer
        say "Waiting for your answer in the window (it may be behind this one)..."
        answer=$("${Z[@]}" --forms --text="Optional: your name and email for Git commits. They appear in the history of anything you publish.
Leave empty or press Skip if you don't want this now." --add-entry="Name" --add-entry="Email" --separator=$'\x1f' --ok-label="Save" --cancel-label="Skip" 2>/dev/null) || return 0
        IFS=$'\x1f' read -r GIT_NAME GIT_EMAIL <<< "$answer"
    elif ((TTY)); then
        say "Optional: your name and email for Git commits. They appear in the history of anything you publish. Enter skips."
        read -rp "  Name (optional): " GIT_NAME </dev/tty || GIT_NAME=""
        read -rp "  Email (optional): " GIT_EMAIL </dev/tty || GIT_EMAIL=""
    fi
}

# Flatpak VS Code is sandboxed and can't use these compilers, but the regular package can live next to it.
ask_flatpak_vscode() {
    command -v code >/dev/null && return 0
    command -v flatpak >/dev/null || return 0
    flatpak list --app --columns=application 2>/dev/null | grep -x com.visualstudio.code >/dev/null || return 0
    FLATPAK_CHOICE=keep
    local text="VS Code is installed here as a Flatpak. It runs sandboxed and can't use the compilers this setup installs, so the setup installs the regular VS Code as well."
    if ((GUI)); then
        say "Waiting for your answer in the window (it may be behind this one)..."
        FLATPAK_CHOICE=$("${Z[@]}" --list --radiolist --width=700 --height=300 --text="$text" \
            --column="" --column=key --column="What happens to the Flatpak?" --hide-column=2 --print-column=2 \
            TRUE keep "Keep both: two VS Code entries in the app menu, the languages are only in the regular one" \
            FALSE remove "Remove it: its settings stay in ~/.var/app, flatpak install brings it back" 2>/dev/null) || cancelled
        [[ -n $FLATPAK_CHOICE ]] || cancelled
    elif ((TTY)); then
        say "$text"
        local reply
        read -rp "Keep the Flatpak as well, or remove it? Its settings stay in ~/.var/app. [K]eep/[r]emove/[c]ancel " reply </dev/tty || reply=""
        case ${reply,,} in
            r*) FLATPAK_CHOICE=remove ;;
            c*) cancelled ;;
        esac
    fi
}

remove_flatpak_vscode() {
    case $FLATPAK_CHOICE in
        keep) NOTES+=("Your Flatpak VS Code stays as it was and has none of these languages: open them with VS Launcher.") ;;
        remove)
            if logged flatpak uninstall -y com.visualstudio.code; then
                NOTES+=("Flatpak VS Code removed. Its settings stay in ~/.var/app; to get it back: flatpak install flathub com.visualstudio.code")
            else
                NOTES+=("Flatpak VS Code could not be removed, so it stays. Close it and run: flatpak uninstall com.visualstudio.code")
            fi ;;
    esac
}

# Only with a Git identity: without one, a commit fails.
add_commit_rule() {
    local rule='- Projects with git: commit when a change works, with a short message. Never push unless asked; never commit secrets.'
    [[ -n $(git config --global user.name || true) && -n $(git config --global user.email || true) ]] || return 0
    if ! grep -qxF -- "$rule" "$WS/CLAUDE.md"; then printf '%s\n' "$rule" >> "$WS/CLAUDE.md"; fi
}

set_git_identity() {
    [[ -n $GIT_NAME$GIT_EMAIL ]] || return 0
    if [[ ! -e $HOME/.gitconfig ]]; then record gitfile "$HOME/.gitconfig"; fi
    if [[ -n $GIT_NAME ]]; then git config --global user.name "$GIT_NAME"; record gitkey user.name; fi
    if [[ -n $GIT_EMAIL ]]; then git config --global user.email "$GIT_EMAIL"; record gitkey user.email; fi
}

rust_retry() {
    logged "$@" || RUSTUP_USE_CURL=1 logged "$@" || RUSTUP_USE_CURL=1 logged "$@" ||
        fail "Downloading the Rust toolchain failed three times. Check the internet connection and start the setup again."
}

setup_rust() {
    has_key rust || return 0
    # The distribution's own Rust (no rustup) stays as it is, and ~/.cargo is not ours then.
    if ! command -v rustup >/dev/null; then return 0; fi
    # Any rustup call creates ~/.rustup, so note first whether it was there before.
    if [[ ! -d $HOME/.rustup ]] && ! recorded homedir "$HOME/.rustup"; then record homedir "$HOME/.rustup"; fi
    if [[ ! -d $HOME/.cargo ]] && ! recorded homedir "$HOME/.cargo"; then record homedir "$HOME/.cargo"; fi
    if rustc --version >/dev/null 2>&1; then return 0; fi   # "rustup show" exits 0 without a toolchain
    step "Rust toolchain (rustup stable)"
    # Minimal profile: no offline docs (thousands of files). rustup's own downloader fails on some
    # connections ("error decoding response body"), so retries use curl instead.
    logged rustup set profile minimal
    rust_retry rustup default stable
    rust_retry rustup component add rust-src clippy rustfmt
}

setup_python_env() {
    has_key python || return 0
    step "Python environment (Workspace/.venv: ${PY_PACKAGES// /, })"
    if [[ ! -x $VENV/bin/python || ! -x $VENV/bin/pip ]]; then   # no pip: an earlier run stopped halfway
        logged py3 -m venv "$VENV"
        recorded venv "$VENV" || record venv "$VENV"
    fi
    # shellcheck disable=SC2086  # the package list is split on purpose
    logged "$VENV/bin/pip" install --disable-pip-version-check $PY_PACKAGES ||
        fail "Installing Python packages failed. Check the internet connection and start the setup again."
    if [[ ! -d $KERNEL_DIR ]]; then
        logged "$VENV/bin/python" -m ipykernel install --user --name workspace-venv --display-name "Python (Workspace)"
        recorded kernel "$KERNEL_DIR" || record kernel "$KERNEL_DIR"
    fi
}

make_workspace() { # key
    local key=$1 dir=$WS/$1 launch
    step "Workspace ${P_NAME[$key]}"
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
            py set-keys "$dir/.vscode/settings.json" "$(py3 -c 'import json, sys; print(json.dumps({"python.defaultInterpreterPath": sys.argv[1], "files.exclude": {".venv": True}}))' "$VENV/bin/python")"
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
}

install_extensions() { # profile-name extension...
    local profile=$1 out ext missing=() args=()
    shift
    for ext; do args+=(--install-extension "$ext"); done
    NODE_NO_WARNINGS=1 logged code --profile "$profile" "${args[@]}" || true
    out=$(code --list-extensions --profile "$profile" 2>/dev/null | tr '[:upper:]' '[:lower:]') || true
    for ext; do grep -qxF "${ext,,}" <<< "$out" || missing+=("$ext"); done
    if ((${#missing[@]})); then   # one retry: most failures are a network hiccup
        args=()
        for ext in "${missing[@]}"; do args+=(--install-extension "$ext"); done
        NODE_NO_WARNINGS=1 logged code --profile "$profile" "${args[@]}" || true
        out=$(code --list-extensions --profile "$profile" 2>/dev/null | tr '[:upper:]' '[:lower:]') || true
        for ext in "${missing[@]}"; do grep -qxF "${ext,,}" <<< "$out" || FAILED+=("$profile: $ext"); done
    fi
}

# The terminal gets the Python environment through its variables. The extensions' own way is unusable on
# a first start: they type "source .../activate" into the terminal, which cuts off or feeds a program
# that is already running (KeyboardInterrupt), and warn about an "invalid interpreter" meanwhile.
venv_settings() { # os-key venv-variable path-variable bin-folder -> JSON members
    py3 - "$VENV" "$@" <<'PY'
import json, sys
venv, osname, venv_var, path_var, bindir = sys.argv[1:6]
print(json.dumps({
    "python.useEnvironmentsExtension": False,
    "python.terminal.activateEnvironment": False,
    "python-envs.terminal.autoActivationType": "off",
    "terminal.integrated.env." + osname: {venv_var: venv, path_var: venv + "/" + bindir + ":${env:" + path_var + "}"},
})[1:-1])
PY
}

setup_profile() { # key name icon rgb extensions settings
    local key=$1 name=$2 icon=$3 rgb=$4 exts=$5 settings=$6 line location current new=0
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
        settings="{$COMMON_SETTINGS${settings:+, $settings}"
        if ((BYPASS)); then settings+=", $BYPASS_SETTINGS"; fi
        if [[ $key == python ]]; then settings+=", $(venv_settings linux VIRTUAL_ENV PATH bin)"; fi
        msg=$(py settings "$file" "$rgb" "$settings}" 2>&1)
    elif ((BYPASS_CHANGED)); then
        if ((BYPASS)); then msg=$(py set-keys "$file" "{$BYPASS_SETTINGS}" 2>&1)
        else msg=$(py del-keys "$file" claudeCode.allowDangerouslySkipPermissions claudeCode.initialPermissionMode 2>&1); fi
    fi
    if [[ -n $msg ]]; then NOTES+=("Profile $name: its settings.json has comments, so the setup left it unchanged"); fi
    # shellcheck disable=SC2086  # the extension list is split on purpose
    install_extensions "$name" $BASE_EXTENSIONS $exts
}

# A language that fails must not stop the others. The subshell is what keeps set -e working: inside
# "if" or "||" bash ignores it. What the subshell changes comes back through files.
declare -A LANG_FAILED=()
CONTAIN_DIR=""   # not a local: write_examples has its own "t", and bash's locals reach into what a function calls
contained() { # key command... -> a failure lands in LANG_FAILED[key]. Never call it with || or if: see above.
    local key=$1 rc=0
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
    mapfile -t NOTES < "$CONTAIN_DIR/notes"
    mapfile -t FAILED < "$CONTAIN_DIR/failed"
    if ((rc)); then
        LANG_FAILED[$key]=$(cat "$CONTAIN_DIR/reason" 2>/dev/null || true)
        if [[ -z ${LANG_FAILED[$key]} ]]; then LANG_FAILED[$key]="stopped during: $(tail -n 1 "$CONTAIN_DIR/last" 2>/dev/null || echo setup) (exit code $rc)"; fi
    fi
    rm -rf "$CONTAIN_DIR"
}
keep_state() {
    printf '%s\n' "$STEP_NO" > "$CONTAIN_DIR/step"
    printf '%s\n' "$CURRENT_STEP" > "$CONTAIN_DIR/last"
    : > "$CONTAIN_DIR/notes"; : > "$CONTAIN_DIR/failed"
    if ((${#NOTES[@]})); then printf '%s\n' "${NOTES[@]}" > "$CONTAIN_DIR/notes"; fi
    if ((${#FAILED[@]})); then printf '%s\n' "${FAILED[@]}" > "$CONTAIN_DIR/failed"; fi
}
language_tools() { # key
    local key=$1 pkgs=()
    mapfile -t pkgs < <(missing_of "$key")
    if ((${#pkgs[@]})); then
        step "Packages for ${P_NAME[$key]} (${#pkgs[@]})"
        # An earlier run stopped halfway through dpkg (Ctrl+C, closed terminal): finish that first.
        logged as_root dpkg --force-confdef --force-confold --configure -a || true   # does nothing if all is well
        logged apt_get install -y --no-remove "${pkgs[@]}"
    fi
    if [[ $key == rust ]]; then setup_rust; fi
    make_workspace "$key"
    if [[ $key == python ]]; then setup_python_env; fi
}
language_profile() { # key
    # shellcheck disable=SC2153  # P_SET is filled from the table at the top
    setup_profile "$1" "${P_NAME[$1]}" "${P_ICON[$1]}" "${P_RGB[$1]}" "${P_EXT[$1]}" "${P_SET[$1]}"
}
install_language() { # key
    PKGS_BEFORE=$(installed_pkgs) PKG_KIND=apt LOG_MARK=$(wc -l < "$LOG")
    contained "$1" language_tools "$1"
    record_new_pkgs
    PKGS_BEFORE=""
    if [[ -n ${LANG_FAILED[$1]:-} ]]; then return 0; fi
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
            timeout 120 "$VENV/bin/python" -c 'import numpy, pandas, matplotlib, ipykernel, tkinter' 2>&1 | tail -n 1 || rc=$?
            ;;
        cpp)
            printf '#include <iostream>\n#include <ranges>\nint main() { for (int i : std::views::iota(0, 1)) std::cout << i; }\n' > "$t/hello.cpp"
            { timeout 120 g++ -std=c++23 "$t/hello.cpp" -o "$t/hello" && timeout 20 "$t/hello" >/dev/null && timeout 20 clangd --version >/dev/null; } || rc=$?
            ;;
        latex)
            printf '%s\n' '\documentclass{article}' '\usepackage[T1]{fontenc}' '\usepackage{lmodern}' '\usepackage{amsmath,amssymb}' '\usepackage{graphicx}' '\usepackage{hyperref}' '\begin{document}' 'Hello: $e^{i\pi} + 1 = 0$.' '\end{document}' > "$t/hello.tex"
            { (cd "$t" && timeout 180 latexmk -pdf -interaction=nonstopmode -halt-on-error hello.tex >"$t/out" 2>&1) && [[ -s $t/hello.pdf ]]; } || { rc=1; grep -E '^!|not found' "$t/out" | head -3; }
            ;;
        bash)
            printf '#!/usr/bin/env bash\necho hello\n' > "$t/hello.sh"
            { timeout 20 shellcheck "$t/hello.sh" && timeout 20 bash "$t/hello.sh" >/dev/null; } || rc=$?
            ;;
        rust)
            { (cd "$t" && timeout 60 cargo new --vcs none hello >/dev/null 2>&1 && cd hello && timeout 180 cargo run -q >/dev/null) && timeout 20 rustc --version >/dev/null; } || rc=$?
            # The workspace folder too: a deleted project still listed in Cargo.toml stops cargo there.
            if ((rc == 0)); then (cd "$WS/rust" && timeout 60 cargo metadata -q --no-deps --format-version 1 >/dev/null) || rc=$?; fi
            ;;
    esac
    rm -rf "$t"
    return "$rc"
}

run_checks() { # the languages in SELECTED; with extensions when asked for: an install has just verified them
    local key name out ext line missing
    step "Checking that everything works"
    for key in "${SELECTED[@]}"; do
        name=${P_NAME[$key]}
        if [[ -n ${LANG_FAILED[$key]:-} ]]; then
            CHECK_BAD+=("$name: ${LANG_FAILED[$key]}")
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
        missing=""
        out=$(code --list-extensions --profile "$name" 2>/dev/null | tr '[:upper:]' '[:lower:]') || true
        for ext in $BASE_EXTENSIONS ${P_EXT[$key]:-}; do grep -qxF "${ext,,}" <<< "$out" || missing+=" $ext"; done
        if [[ -n $missing ]]; then CHECK_BAD+=("Profile $name: extensions missing:$missing"); say "  Profile $name: extensions missing:$missing"; fi
    done < <(manifest_lines profile)
}

check_only() {
    [[ -f $MANIFEST ]] || fail "Nothing to check: $(show "$MANIFEST") not found."
    local k keys=()
    for k in $(manifest_lines profile | cut -f1 | sed 's/^jupyter$/python/' | awk '!s[$0]++'); do
        if [[ $k != setup_manager && -v "P_NAME[$k]" ]]; then keys+=("$k"); fi
    done
    SELECTED=("${keys[@]}")
    LOG=$SM/logs/check-$(date +%F_%H%M).log
    : > "$LOG"
    run_checks with-extensions
    if ((${#CHECK_BAD[@]})); then
        info "The check found problems:
$(printf ' - %s\n' "${CHECK_BAD[@]}")

Running the setup again repairs what it can. Details: $(show "$LOG")"
        DIED=1
        exit 1
    fi
    info "Everything works: ${CHECK_OK[*]}, and all the extensions are there."
}

# Optional. The shell records itself: VS Code's terminals only, not Claude Code's own shells.
TERMLOG_START='# >>> setup-workspace terminal-log >>>' TERMLOG_END='# <<< setup-workspace terminal-log <<<'
setup_terminal_log() {
    ((TERMLOG)) || return 0
    step "Terminal log"
    put "$SM/scripts/read_terminal_log.py" 755 <<'EOF'
#!/usr/bin/env python3
"""Print a recorded VS Code terminal (~/.terminal-logs/) as plain text, without the terminal's control codes.

read_terminal_log.py [N] [LINES]   N-th newest log (default 1), its last LINES lines (default 200, 0 = all)
read_terminal_log.py --list        the 10 newest logs, numbered
"""
import re
import sys
from pathlib import Path

CODES = re.compile(
    r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"   # window title, VS Code's shell integration
    r"|\x1b\[[0-?]*[ -/]*[@-~]"            # colours, cursor movement
    r"|\x1b[()][0-9A-Za-z]|\x1b[=>78]"     # character sets, keypad modes
    r"|\x07"
)


def clean(text):
    lines = []
    for line in CODES.sub("", text).replace("\r\n", "\n").split("\n"):
        line = line.rsplit("\r", 1)[-1]   # a progress bar rewriting its line: only the last state
        while "\b" in line:               # corrections while typing
            line = re.sub(r"[^\x08]\x08|^\x08+", "", line, count=1)
        lines.append(line)
    return lines


logs = sorted((Path.home() / ".terminal-logs").glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True)
args = sys.argv[1:]
if args == ["--list"]:
    for i, log in enumerate(logs[:10], 1):
        print(f"{i}  {log.name}  {log.stat().st_size} bytes")
    sys.exit(0)
n = int(args[0]) if args else 1
count = int(args[1]) if len(args) > 1 else 200
if not 1 <= n <= len(logs):
    sys.exit(f"no log number {n}: {len(logs)} logs in ~/.terminal-logs")
lines = clean(logs[n - 1].read_text(errors="replace"))
print(f"--- {logs[n - 1].name}")
print("\n".join(lines[-count:] if count else lines))
EOF
    if [[ -f $WS/CLAUDE.md ]] && ! grep -qF read_terminal_log.py "$WS/CLAUDE.md"; then
        printf -- '- The user'"'"'s VS Code terminals are recorded to `~/.terminal-logs/`, kept about a day. When the user refers to something they ran or an error they saw, read it instead of asking them to paste it: `%s` prints the newest log without control codes (`[N] [LINES]`: N-th newest, last LINES lines; `--list` shows the newest 10). Anything shown on screen is in there, so don'"'"'t quote secrets from it.\n' "$SM/scripts/read_terminal_log.py" >> "$WS/CLAUDE.md"
    fi
    local rc=$HOME/.bashrc
    if [[ ${SHELL##*/} != bash ]]; then NOTES+=("Terminal log: it only records bash, and your default shell is ${SHELL##*/}."); fi
    if grep -qE 'TERMINAL_LOG|\.terminal-logs' "$rc" 2>/dev/null; then
        if [[ -z $(manifest_lines bashblock) ]]; then NOTES+=("Terminal log: ~/.bashrc already records terminals, so it was left as it is."); fi
        return 0
    fi
    if [[ -e $rc ]]; then mkdir -p "$SM/backup"; cp "$rc" "$SM/backup/bashrc-before-terminal-log-$TODAY"; fi
    if [[ ! -e $HOME/.terminal-logs ]] && ! recorded termdir "$HOME/.terminal-logs"; then record termdir "$HOME/.terminal-logs"; fi
    if [[ -s $rc && -n $(tail -c 1 "$rc") ]]; then echo >> "$rc"; fi
    {
        printf '%s\n' "$TERMLOG_START"
        cat <<'EOF'
# Records every interactive VS Code terminal (commands and output) to ~/.terminal-logs/ so Claude can read it.
# Logs untouched for 24 hours are deleted when a new terminal opens, unless their terminal is still open.
if [[ $- == *i* && -t 0 && "$TERM_PROGRAM" == "vscode" && -z "$TERMINAL_LOG" && -z "$CLAUDECODE" ]] && command -v script >/dev/null; then
  mkdir -p -m 700 "$HOME/.terminal-logs"
  # The number in the name is the recording's process. A deleted log of an open terminal would lose what it records from then on.
  find "$HOME/.terminal-logs" -name '*.log' -mmin +1440 2>/dev/null | while read -r f; do p=${f##*_}; kill -0 "${p%.log}" 2>/dev/null || rm -f "$f"; done
  export TERMINAL_LOG="$HOME/.terminal-logs/$(date +%Y-%m-%d_%H%M%S)_$$.log"
  # A log that can't be written must not cost the terminal: "exec script" failing would close it.
  if touch "$TERMINAL_LOG" 2>/dev/null; then exec script -q -f "$TERMINAL_LOG"; fi
  unset TERMINAL_LOG
fi
# VS Code injects its shell integration only into the outer shell; load it again inside the recorded one.
for _vscode_si in /usr/share/code /snap/code/current/usr/share/code; do
  _vscode_si=$_vscode_si/resources/app/out/vs/workbench/contrib/terminal/common/scripts/shellIntegration-bash.sh
  if [[ -n "$TERMINAL_LOG" && "$TERM_PROGRAM" == "vscode" && -f "$_vscode_si" ]]; then . "$_vscode_si"; break; fi
done
unset _vscode_si
EOF
        printf '%s\n' "$TERMLOG_END"
    } >> "$rc"
    record bashblock "$rc"
}

make_launcher() {
    step "Launcher"
    put "$ROOT/launcher.sh" 755 <<'EOF'
#!/usr/bin/env bash
# Pick a workspace; VS Code opens it with its own profile.
# The entries are the profiles listed in Workspace/setup_manager/installed.txt.
ws=$(dirname "$(readlink -f "$0")")/Workspace
declare -A profile file
while IFS=$'\t' read -r kind key name _; do
    [[ $kind == profile ]] || continue
    if [[ $key == setup_manager ]]; then file[$name]=$ws/setup_manager/setup.code-workspace
    else file[$name]=$ws/$key/$key.code-workspace; fi
    profile[$name]=$name
    [[ $key == setup_manager ]] && top=$name
done < "$ws/setup_manager/installed.txt"

labels=()
[[ -n ${top:-} ]] && labels+=("$top")
while IFS= read -r label; do labels+=("$label"); done < <(printf '%s\n' "${!profile[@]}" | grep -vxF "${top:-}" | sort -f)

choice=$(zenity --list --title="" --text="" --column="" --hide-header \
    --width=300 --height=$((120 + 34 * ${#labels[@]})) "${labels[@]}") || exit 0
[[ -n $choice && -n ${profile[$choice]:-} ]] || exit 0
exec code --profile "${profile[$choice]}" "${file[$choice]}"
EOF
    local icon=vscode
    if [[ ! -e /usr/share/pixmaps/vscode.png && ! -e /usr/share/icons/hicolor/512x512/apps/vscode.png ]]; then icon=code; fi
    local exec=$ROOT/launcher.sh   # .desktop quoting: \ " ` $ get a backslash, % is doubled
    exec=${exec//\\/\\\\}; exec=${exec//\"/\\\"}; exec=${exec//\`/\\\`}; exec=${exec//\$/\\\$}; exec=${exec//%/%%}
    put "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=VS Launcher
Comment=Open a VS Code workspace with its own profile
Exec="$exec"
Icon=$icon
Terminal=false
Categories=Development;
EOF
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

# /test-setup - test this setup (Linux)

You are testing this setup, not repairing it. It takes about 15 minutes, with questions for the
person at the end.
- Change nothing: no settings, profiles, packages, or files. The exceptions are a temporary folder (mktemp -d),
  the test project in F (you remove it again), and the report.
- Never run the setup with --uninstall or --add. Never use sudo or apt.
- When you run the setup script, always add --no-gui. Without it, the script opens windows or a new terminal.
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

A. THE INSTALL
A1  md5sum SM/scripts/setup-workspace.sh, and its SCRIPT_VERSION line. Record both.
A2  System: /etc/os-release (NAME, VERSION), uname -m, $XDG_CURRENT_DESKTOP and $XDG_SESSION_TYPE,
    locale (LANG), whether a battery exists (/sys/class/power_supply/BAT*), free space on ~ (df -h ~).
A3  SM/setup.conf as it is. From SM/installed.txt: the profile lines (key and name) and the count of
    lines of each kind.
A4  The install logs, SM/logs/install-*.log. List them with dates. In each, find the lines matching
    "^== |^error|DOES NOT WORK|Stopped at|Setup stopped|Not finished|: works$". Record those lines:
    at most 60 from the newest log and 15 from each older one. PASS if the newest log has no
    error, DOES NOT WORK, or Stopped at.
A5  bash SM/scripts/setup-workspace.sh --check --no-gui. Record the exit code and the result lines.

B. THE LANGUAGES (SKIP any language that isn't installed; build in the temporary folder)
B1  Python: WS/.venv/bin/python --version. Import numpy, pandas, matplotlib, ipykernel and tkinter
    in one command. Run WS/python/scratch/hello.py with it.
    Run WS/.venv/bin/jupyter kernelspec list. Check where the link WS/python/.venv points (readlink).
B2  C++: g++ --version and clangd --version (first lines). Copy WS/cpp/scratch/hello.cpp to the
    temporary folder, compile it with g++ -std=c++23, and run it.
B3  LaTeX: latexmk -v (first line). Copy WS/latex/scratch/hello.tex to the temporary folder and run
    latexmk -pdf -interaction=nonstopmode hello.tex there. PASS if hello.pdf exists.
B4  Bash: bash --version and shellcheck --version. Run shellcheck on WS/bash/scratch/hello.sh, then
    run the script with bash.
B5  Rust: rustc --version and cargo --version, also from ~/.cargo/bin if they're not on the PATH.
    In WS/rust, run: cargo run -q --bin hello, then cargo metadata -q --no-deps --format-version 1 >/dev/null
B6  Terminal log, only if TERMLOG=1 in setup.conf (otherwise SKIP): does ~/.terminal-logs/ have files?
    Run python3 SM/scripts/read_terminal_log.py --list.

C. VS CODE
C1  code --version (first two lines). Which VS Code it is: command -v code; snap list code;
    flatpak list | grep -i code. Note any of these that are missing.
C2  For each profile name in installed.txt, Setup Manager included:
        code --list-extensions --show-versions --profile "<name>"
    The expected list for each profile is BASE_EXTENSIONS plus that language's extension column in the
    table at the top of SM/scripts/setup-workspace.sh. FAIL if any are missing. Record the versions.
C3  For each folder id: ~/.config/Code/User/profiles/<id>/settings.json and globalStorage/ exist.
    The Claude bypass keys (claudeCode.allowDangerouslySkipPermissions, claudeCode.initialPermissionMode)
    must be present exactly when BYPASS=1 in setup.conf. In the Python profile,
    terminal.integrated.env.linux must point to WS/.venv.
C4  Trust: is WS listed as trusted in both of these? Key content.trust.model.key, opened read-only with
    python3, sqlite3 and a "file:...?mode=ro" URI:
        ~/.config/Code/User/globalStorage/state.vscdb
        ~/.vscode-shared/sharedStorage/state.vscdb
    PASS if WS is in the one under .vscode-shared.
C5  The newest folder in ~/.config/Code/logs/: count the lines in the exthost logs that match
    "Cannot find module|failed to activate|Activating extension .* failed". Quote up to 5 different ones.

D. LAUNCHER, SKILLS, GIT
D1  ROOT/launcher.sh and ~/.local/share/applications/vs-launcher.desktop exist. Record the Exec= line.
D2  ~/.claude/skills/log/SKILL.md and ~/.claude/skills/distill/SKILL.md exist.
D3  git --version. Are user.name and user.email set (yes or no)? WS/CLAUDE.md must contain the line
    about committing exactly when both are set.

E. YOU, CLAUDE, IN THIS SETUP
E1  Before reading any file: which CLAUDE.md files came with your instructions in this session? Name
    them and quote the first heading of each. Then read WS/CLAUDE.md and SM/CLAUDE.md and compare.
    PASS if both were loaded.
E2  Are /log and /distill in your list of available skills?
E3  The Claude Code extension's version (from C2). Your permission mode, if you can tell.

F. NEW PROJECT (only if Python is installed)
F1  In WS/python, take the "New project" task's command from .vscode/tasks.json and run it the way VS
    Code would, with PROJECT_NAME=zz-setup-test. Replace its final `code "..."` call with `true`, so no
    window opens.
    Check: projects/zz-setup-test/ holds main.py and a .git folder. A commit exists exactly when Git's
    name and email are set. Then delete projects/zz-setup-test (this test created it).
F2  The same with PROJECT_NAME=../zz-escape. It must be refused with exit code 1, and nothing may be
    created outside projects/.

G. ASK THE PERSON (one at a time; record the answer in a few words; "skip" means SKIP)
G1  Start VS Launcher from the app menu. Is Setup Manager on top, with every language listed? Does each
    one open in its own colours?
G2  Python: open scratch/hello.py and click the run button (top right). What is printed? Then set a
    breakpoint and press F5. Does it stop there?
G3  Notebook: open scratch/hello.ipynb and click Run All. Which kernel choices appear? Choose Python
    Environments, then .venv (Recommended). Does the plot show?
G4  C++ (if installed): run button on hello.cpp, then F5 with a breakpoint.
G5  LaTeX (if installed): open hello.tex, add a space, and save. Does a PDF tab with the formula appear?
G6  Bash and Rust (if installed): the run button on scratch/hello.sh and on scratch/src/bin/hello.rs.
G7  Type in this Claude panel: /log test entry from the test run
    Then you check that SM/.claude/friction.md has that entry.
G8  During this test, did VS Code ask you to approve any command or file change? With bypass mode on,
    it shouldn't have.
G9  Was anything confusing, slow, or wrong during the install or since? Think of warnings, popups, and
    wording. How long did the install take?

THE REPORT
Write SM/logs/test-report-<YYYY-MM-DD_HHMM>.txt in this layout:

    TEST REPORT  setup-workspace.sh (Linux)
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
# Choices of setup-workspace.sh; reruns read them. Edit only if you know why.
PROFILES=$(IFS=,; echo "${SELECTED[*]}")
BYPASS=$BYPASS
TERMLOG=$TERMLOG
EOF
}

write_readme() {
    local f=$SM/README.md key name rows="" pkgs vscode="" cmd
    if [[ -f $SM/scripts/setup-workspace.sh ]]; then cmd="bash $(show "$SM")/scripts/setup-workspace.sh"
    else cmd="bash setup-workspace.sh --root $(show "$ROOT")"; fi   # no copy: started as curl | bash
    while IFS=$'\t' read -r key name _; do
        [[ $key == setup_manager ]] && continue
        rows+="| $name | \`Workspace/$key/\` | ${P_INFO[$key]:-} |"$'\n'
    done < <(manifest_lines profile)
    pkgs=$(manifest_lines apt | wc -l)
    if [[ -n $(manifest_lines vscode) ]]; then vscode=" (VS Code itself included)"; fi
    cat > "$f" <<EOF
# Your VS Code setup

Made by \`scripts/setup-workspace.sh\` $SCRIPT_VERSION on $TODAY. Everything it added is listed in \`installed.txt\`.

## Open a workspace

Start **VS Launcher** from the app menu (or run \`$(show "$ROOT")/launcher.sh\`) and pick a workspace. Each one opens with its own colour-coded VS Code profile.

| Profile | Folder | Contents |
|---|---|---|
$rows| Setup Manager | \`Workspace/setup_manager/\` | This setup: sees the whole Workspace folder and VS Code's settings and profiles |

First time:
- The Workspace folder is marked as trusted in VS Code, so run buttons, tasks and the debugger work there.
- C++/Rust: the first F5 downloads the debugger's platform part (about a minute).
- **Claude Code**: click the Claude icon (top right of an open file, or the side bar) and sign in once; it needs a paid Claude plan or API account (the free plan doesn't include it). $( ((BYPASS)) && echo 'Bypass mode is on: Claude acts without asking for each step (turn off: Settings > "Claude Code: Initial Permission Mode").' || echo 'Claude asks before each action.')

## Work

- Try the \`hello\` file in each workspace's \`scratch/\` (Rust: \`scratch/src/bin/hello.rs\`): the **run button** (top right) runs the file, **F5** debugs it (Python, C++, Rust), LaTeX builds the PDF on save, Python's \`hello.ipynb\` runs cells.
- F5, the run button and the C++/Rust build task use the current file only. Rust projects with crates: \`cargo run\`. C++ with several files: your own build, for example CMake.
- Deleting a Rust project: also remove its line from \`members\` in \`rust/Cargo.toml\`, or cargo fails for the whole folder.
- Notebooks: the first time you run a notebook, VS Code asks for a kernel: choose **Python Environments**, then **.venv** (Recommended; \`Workspace/.venv\`). It remembers the choice.
- New project: **Terminal > Run Task > New project**: copies \`templates/basic/\` to \`projects/<name>/\` and starts its version history (git), with a first commit if Git has your name and email. Nothing is uploaded.
- Undo what Claude did: hover over a message in the Claude panel and choose **Rewind code to here**. It covers files Claude edited, not what you changed yourself; git is the long-term history.
- Git commits need your name and email; if you skipped that question: \`git config --global user.name "Your Name"\`, then the same for \`user.email\`.
- Python packages: \`Workspace/.venv/bin/pip install <package>\`.
- Claude reads \`Workspace/CLAUDE.md\` (shared rules) and the workspace's own \`CLAUDE.md\` (language rules). \`/log <note>\` collects friction, \`/distill\` turns it into rules.

## Change the setup

- Test that everything still works: \`$cmd --check\`.
- Check everything in detail: type \`/test-setup\` in Setup Manager's Claude panel. Claude tests the whole setup, asks you to try a few things and writes a report to \`logs/\`. It changes nothing.
- Terminal log: $( ((TERMLOG)) && echo "on. VS Code's terminals are recorded to \`~/.terminal-logs/\` for about a day, so Claude can read what you ran; anything shown on screen is saved too. \`--uninstall\` switches it off." || echo "off. To record VS Code's terminals so that Claude can read what you ran: \`$cmd --terminal-log\`. Anything shown on screen is saved too, for about a day.")
- Add a language (close VS Code first): \`$cmd --add rust\`. Available: ${ALL_KEYS[*]}.$( [[ -f $SM/scripts/setup-workspace.sh ]] || echo " (Download setup-workspace.sh again first: this setup was started as a one-liner, so there is no copy in \`scripts/\`.)")
- Changes are logged in \`logs/setup_log.txt\`; each install's details in \`logs/install-*.log\`.
- Your VS Code settings from before the setup$( [[ $(manifest_lines backup) != none ]] && echo " are in \`backup/\`" || echo ": there were none"). The setup never changed them.

## Uninstall

\`$cmd --uninstall\` shows everything from \`installed.txt\` and removes what you tick: profiles, menu entry, Claude skills, the Python environment, the $pkgs packages it installed$vscode. Nothing that was there before. Your files stay unless you tick the Workspace folder; removed folders go to \`$(show "$ROOT")/Trash/\`. Claude's login and chat history stay, because they are Claude's own files; \`/logout\` in Claude signs out.
EOF
}

finish() {
    step "Finishing"
    local dest=$SM/scripts/setup-workspace.sh names=() key
    if [[ -f $SELF && $SELF != "$dest" ]] && ! cmp -s "$SELF" "$dest" 2>/dev/null; then
        install -m 755 "$SELF" "$dest"
        recorded file "$dest" || record file "$dest"
    elif [[ ! -f $SELF && ! -f $dest && -n $SOURCE_URL ]]; then   # started as curl | bash
        if logged curl -fsSL --retry 3 -o "$dest.tmp" "$SOURCE_URL" && bash -n "$dest.tmp"; then
            mv "$dest.tmp" "$dest"; chmod 755 "$dest"; record file "$dest"
        else
            rm -f "$dest.tmp"
        fi
    fi
    write_readme
    for key in "${SELECTED[@]}"; do names+=("${P_NAME[$key]}"); done
    {
        printf '\n[%s] setup-workspace.sh: %s\n' "$TODAY" "$1"
        printf -- '- Profiles: %s (+ Setup Manager); Claude bypass mode: %s\n' "${names[*]}" "$( ((BYPASS)) && echo on || echo off)"
        printf -- '- Packages added this run: %s; details: logs/%s\n' "$NEW_PKGS" "$(basename "$LOG")"
        if ((${#FAILED[@]})); then printf -- '- Extensions NOT installed: %s\n' "${FAILED[*]}"; fi
        if ((${#CHECK_BAD[@]})); then printf -- '- Check found problems: %s\n' "${CHECK_BAD[*]}"; fi
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
    local items=() apt_pkgs=() vscode_pkgs=() profiles=() line p
    mapfile -t profiles < <(manifest_lines profile)
    # Only names that are still installed: after a release upgrade or a manual purge, apt would
    # stop at an unknown name.
    for p in $(manifest_lines apt) $(manifest_lines apt-vscode); do
        if ! dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed'; then
            unrecord apt "$p"; unrecord apt-vscode "$p"
        fi
    done
    mapfile -t apt_pkgs < <(manifest_lines apt)
    mapfile -t vscode_pkgs < <(manifest_lines apt-vscode; if [[ -n $(manifest_lines vscode) ]]; then echo code; fi)
    # id | default | description
    ((${#profiles[@]})) && items+=("profiles|TRUE|VS Code profiles: $(printf '%s\n' "${profiles[@]}" | cut -f2 | paste -sd, - | sed 's/,/, /g')")
    [[ -n $(manifest_lines file | grep -xF "$DESKTOP_FILE") ]] && items+=("menu|TRUE|App-menu entry \"VS Launcher\"")
    [[ -n $(manifest_lines skill) ]] && items+=("skills|TRUE|The Claude Code skills the setup added")
    [[ -n $(manifest_lines trust) ]] && items+=("trust|TRUE|VS Code's trust for $(manifest_lines trust | while read -r d; do show "$d"; echo; done | paste -sd, - | sed 's/,/, /g')")
    [[ -n $(manifest_lines kernel) ]] && items+=("kernel|TRUE|Jupyter kernel \"Python (Workspace)\"")
    [[ -n $(manifest_lines venv) ]] && items+=("venv|TRUE|Python environment Workspace/.venv")
    [[ -n $(manifest_lines homedir) ]] && items+=("rust|TRUE|Rust toolchain (~/.rustup, ~/.cargo)")
    ((${#apt_pkgs[@]})) && items+=("apt|TRUE|${#apt_pkgs[@]} system packages the setup installed")
    [[ -n $(manifest_lines aptsource) ]] && items+=("source|TRUE|Ubuntu's universe package source (other packages from it would stop getting updates)")
    [[ -n $(manifest_lines vscode) ]] && items+=("vscode|FALSE|VS Code itself, with its settings and extensions folders (the setup installed it)")
    local created=()
    mapfile -t created < <(manifest_lines created | while read -r d; do if [[ -e $d ]]; then echo "$d"; fi; done)
    ((${#created[@]})) && items+=("created|FALSE|Cache folders the tools created: $(for d in "${created[@]}"; do show "$d"; echo; done | paste -sd, - | sed 's/,/, /g')")
    [[ -n $(manifest_lines bashblock) ]] && items+=("termlog|TRUE|Terminal log: the lines in ~/.bashrc, and the logs (moved to the Trash)")
    if [[ -n $(manifest_lines gitkey) ]] && command -v git >/dev/null; then items+=("gitid|FALSE|Your Git name and email (in ~/.gitconfig)"); fi
    items+=("workspace|FALSE|The Workspace folder, including your own files")

    local selected=""
    if ((GUI)); then
        local args=() it
        for it in "${items[@]}"; do IFS='|' read -r id def desc <<< "$it"; args+=("$def" "$id" "$desc"); done
        say "Waiting for your answer in the window (it may be behind this one)..."
        selected=$("${Z[@]}" --list --checklist --width=700 --height=640 --text="Remove what the setup added. Ticked items are removed; nothing that existed before is touched." \
            --column="" --column=id --column="Item" --hide-column=2 --print-column=2 --separator=, "${args[@]}" 2>/dev/null) || cancelled
    else
        local it reply
        ((TTY)) || die "uninstall asks what to remove: start it from a terminal or on the desktop"
        say "Uninstall: answer y/n for each item (Enter = the default)."
        for it in "${items[@]}"; do
            IFS='|' read -r id def desc <<< "$it"
            read -rp "  Remove: $desc? [$([[ $def == TRUE ]] && echo Y/n || echo y/N)] " reply </dev/tty || reply=""
            case ${reply,,} in y*) def=TRUE ;; n*) def=FALSE ;; esac
            if [[ $def == TRUE ]]; then selected+=",$id"; fi
        done
    fi
    selected=",$selected,"
    [[ $selected != ",," ]] || exit 0

    local sys=() extra=""
    if [[ $selected == *,apt,* ]]; then sys+=("${apt_pkgs[@]}"); fi
    if [[ $selected == *,vscode,* ]]; then sys+=("${vscode_pkgs[@]}"); fi
    if [[ $selected == *,source,* ]]; then need_sudo; fi
    if ((${#sys[@]})); then
        # apt also removes packages that depend on these; show them before anything happens.
        extra=$(apt-get remove -s "${sys[@]}" 2>/dev/null | awk '/^Remv/ { print $2 }' | grep -vxF -f <(printf '%s\n' "${sys[@]}") | paste -sd' ' - || true)
        if [[ -n $extra ]]; then
            ask "Removing the packages also removes these, which were installed later and depend on them:

$extra

Continue?" "Continue" || cancelled
        fi
        need_sudo
    fi
    if [[ $selected == *,profiles,* || $selected == *,trust,* || $selected == *,vscode,* || $selected == *,created,* ]]; then close_vscode; fi

    progress_start 8
    local name location key path
    if [[ $selected == *,profiles,* ]]; then
        step "Removing VS Code profiles"
        for line in "${profiles[@]}"; do
            IFS=$'\t' read -r key name location <<< "$line"
            py remove-profile "$STORAGE" "$location"
            trash "$VSC_USER/profiles/$location" vscode-profiles
            unrecord profile "$key" "$name" "$location"
            say "  removed profile $name"
        done
    fi
    if [[ $selected == *,menu,* ]]; then
        step "Removing the app-menu entry"
        trash "$DESKTOP_FILE" menu
        unrecord file "$DESKTOP_FILE"
    fi
    if [[ $selected == *,skills,* ]]; then
        step "Removing the Claude Code skills"
        while IFS= read -r path; do
            if grep -qF "$MARKER" "$path/SKILL.md" 2>/dev/null; then trash "$path" claude-skills; fi
            unrecord skill "$path"
        done < <(manifest_lines skill)
    fi
    if [[ $selected == *,trust,* ]]; then
        step "Removing the folder from VS Code's trusted folders"
        while IFS= read -r path; do py untrust "$VSC_USER/globalStorage/state.vscdb" "$path"; unrecord trust "$path"; done < <(manifest_lines trust)
    fi
    if [[ $selected == *,kernel,* ]]; then
        step "Removing the Jupyter kernel"
        while IFS= read -r path; do trash "$path" jupyter-kernel; unrecord kernel "$path"; done < <(manifest_lines kernel)
    fi
    if [[ $selected == *,venv,* ]]; then
        step "Removing the Python environment"
        while IFS= read -r path; do trash "$path" python-env; unrecord venv "$path"; done < <(manifest_lines venv)
    fi
    if [[ $selected == *,rust,* ]]; then
        step "Removing the Rust toolchain"
        while IFS= read -r path; do trash "$path" rust; unrecord homedir "$path"; done < <(manifest_lines homedir)
    fi
    if [[ $selected == *,termlog,* ]]; then
        step "Switching off the terminal log"
        while IFS= read -r path; do
            if grep -qxF "$TERMLOG_START" "$path" && grep -qxF "$TERMLOG_END" "$path"; then
                awk -v a="$TERMLOG_START" -v b="$TERMLOG_END" '$0 == a { s = 1; next } s && $0 == b { s = 0; next } !s' "$path" > "$path.setup-tmp"
                cat "$path.setup-tmp" > "$path"   # not mv: ~/.bashrc may be a link
                rm -f "$path.setup-tmp"
            else
                say "  The terminal log's lines in $(show "$path") were changed: remove them yourself."
            fi
            unrecord bashblock "$path"
        done < <(manifest_lines bashblock)
        while IFS= read -r path; do trash "$path" home-folders; unrecord termdir "$path"; done < <(manifest_lines termdir)
        if [[ -f $WS/CLAUDE.md ]]; then
            grep -vF read_terminal_log.py "$WS/CLAUDE.md" > "$WS/CLAUDE.md.setup-tmp" || true
            mv "$WS/CLAUDE.md.setup-tmp" "$WS/CLAUDE.md"
        fi
        trash "$SM/scripts/read_terminal_log.py" files
        unrecord file "$SM/scripts/read_terminal_log.py"
        if [[ -f $CONF ]]; then sed -i 's/^TERMLOG=.*/TERMLOG=0/' "$CONF"; fi
    fi
    if [[ $selected == *,gitid,* ]]; then   # before the packages: Git itself may go with them
        step "Removing your Git name and email"
        while IFS= read -r path; do git config --global --unset "$path" || true; unrecord gitkey "$path"; done < <(manifest_lines gitkey)
        if [[ -f $WS/CLAUDE.md ]]; then
            grep -vF 'Projects with git: commit when a change works' "$WS/CLAUDE.md" > "$WS/CLAUDE.md.setup-tmp" || true
            mv "$WS/CLAUDE.md.setup-tmp" "$WS/CLAUDE.md"
        fi
        while IFS= read -r path; do
            if [[ ! -s $path ]]; then trash "$path" home-folders; fi
            unrecord gitfile "$path"
        done < <(manifest_lines gitfile)
    fi
    if ((${#sys[@]})); then
        step "Removing ${#sys[@]} packages"
        logged as_root dpkg --force-confdef --force-confold --configure -a || true   # after an interrupted dpkg, apt refuses to work
        logged apt_get remove -y "${sys[@]}"
        for p in "${sys[@]}"; do unrecord apt "$p"; unrecord apt-vscode "$p"; done
        if [[ $selected == *,vscode,* ]]; then unrecord vscode deb; fi
    fi
    if [[ $selected == *,source,* ]]; then
        step "Switching off the universe package source"
        while IFS= read -r path; do
            logged as_root rm -f "$path"
            unrecord aptsource "$path"
        done < <(manifest_lines aptsource)
        logged apt_get update || true
    fi
    if [[ $selected == *,created,* ]]; then
        step "Moving the cache folders to the Trash"
        while IFS= read -r path; do trash "$path" home-folders; unrecord created "$path"; done < <(manifest_lines created)
    fi
    if [[ $selected == *,vscode,* ]]; then
        step "Moving VS Code's settings and extensions folders to the Trash"
        while IFS= read -r path; do trash "$path" home-folders; unrecord created-vscode "$path"; done < <(manifest_lines created-vscode)
    fi
    {
        printf '\n[%s] setup-workspace.sh --uninstall\n' "$TODAY"
        printf -- '- Removed: %s\n' "$(tr ',' ' ' <<< "$selected" | xargs)"
        printf -- '- Moved (not deleted) to %s\n' "$TRASH"
    } >> "$SM/logs/setup_log.txt"
    while IFS= read -r path; do   # folders the setup created that hold no files now (deepest first)
        if [[ -d $path ]]; then find "$path" -depth -type d -empty -delete 2>/dev/null || true; fi
        if [[ ! -e $path ]]; then unrecord emptydir "$path"; fi
    done < <(manifest_lines emptydir | sort -r)
    if [[ $selected == *,workspace,* ]]; then
        step "Moving the Workspace folder to the Trash"
        LOG=""   # it is inside the folder that moves
        mkdir -p "$TRASH"
        mv "$WS" "$TRASH/Workspace-$(date +%H%M%S)"
        if [[ -e $ROOT/launcher.sh ]]; then mv "$ROOT/launcher.sh" "$TRASH/"; fi
    fi
    progress_end
    info "Uninstall finished. Removed folders are in $(show "$TRASH")."
}

# ─── Main ─────────────────────────────────────────────────────────────────────────────────────
has_key() { [[ " ${SELECTED[*]} " == *" $1 "* ]]; }
# Notebooks used to be a language of their own, "jupyter": they are part of Python now.
normalize() { tr 'A-Z ' 'a-z,' <<< "$1" | tr -s ',' | sed 's/^,//; s/,$//; s/c++/cpp/g; s/jupyter/python/g'; }

# One run at a time: two at once would both create the same profiles.
LOCK=${TMPDIR:-/tmp}/setup-workspace-$(id -u).lock
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
LOCKED=0

# Started without a terminal (file manager, app launcher): open one, so that it shows what is happening.
open_terminal() {
    ((GUI && !TTY)) || return 0
    [[ -f $SELF && -z ${SETUP_IN_TERMINAL:-} ]] || return 0
    # shellcheck disable=SC2016  # expanded by the inner bash
    local run=(env SETUP_IN_TERMINAL=1 bash -c 'bash "$0" "$@"; echo; read -rp "Press Enter to close this window. " _' "$SELF" "${ARGS[@]}") t
    for t in gnome-terminal ptyxis konsole xfce4-terminal xterm; do
        command -v "$t" >/dev/null || continue
        case $t in
            gnome-terminal|ptyxis) "$t" -- "${run[@]}" >/dev/null 2>&1 & ;;
            xfce4-terminal) "$t" -x "${run[@]}" >/dev/null 2>&1 & ;;
            *) "$t" -e "${run[@]}" >/dev/null 2>&1 & ;;
        esac
        disown "$!" 2>/dev/null || true
        exit 0
    done
}

# Everything runs from here, after the whole file has been read: a download cut off halfway
# (curl | bash) then fails to parse instead of running half a script.
main() {
    open_terminal
    [[ $EUID -ne 0 ]] || die "start this as your normal user, not with sudo: VS Code and your files must belong to you. The script asks for your password itself when it installs packages."
    command -v apt-get >/dev/null && command -v dpkg-query >/dev/null ||
        die "this script supports Ubuntu/Debian (apt) only. On other systems install VS Code, git, python3 and the compilers you need yourself."
    if grep -qi microsoft /proc/version 2>/dev/null; then
        die "this is WSL: profiles made here wouldn't reach the VS Code on your Windows. Run setup-workspace.ps1 in Windows instead."
    fi
    take_lock

    if ((UNINSTALL)); then uninstall; exit 0; fi
    if ((CHECK)); then check_only; exit 0; fi

    if command -v python3 >/dev/null && ! py3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null; then
        fail "This system's Python is too old (below 3.9), so this setup can't work here. Update the system first."
    fi
    ask_flatpak_vscode

    # Earlier choices (rerun from the Setup Manager or with --add)
    local key preset rows tick note choice names summary dir prev_bypass=""
    # Installed = has its profile. The saved choices may be from a run that stopped: they only preset the ticks.
    local chosen=""
    INSTALLED=$(normalize "$(manifest_lines profile | cut -f1 | { grep -vx setup_manager || true; } | paste -sd, -)")
    if [[ -f $CONF ]]; then
        chosen=$(normalize "$(sed -n 's/^PROFILES=//p' "$CONF")")
        prev_bypass=$(sed -n 's/^BYPASS=//p' "$CONF")
        [[ -n $BYPASS ]] || BYPASS=$prev_bypass
        [[ -n $TERMLOG ]] || TERMLOG=$(sed -n 's/^TERMLOG=//p' "$CONF")
    fi
    PROFILES=$(normalize "${PROFILES:-}")
    ADD=$(normalize "$ADD")
    if [[ -n $ADD ]]; then PROFILES=${chosen:+$chosen,}$ADD; fi

    if ((GUI)) && [[ -z $ADD ]]; then
        preset=",${PROFILES:-${chosen:-$DEFAULT_PROFILES}},"
        rows=()
        for key in "${ALL_KEYS[@]}"; do
            tick=FALSE note=""
            if [[ $preset == *",$key,"* || ,$INSTALLED, == *",$key,"* ]]; then tick=TRUE; fi
            if [[ ,$INSTALLED, == *",$key,"* ]]; then note=" (installed)"; fi
            rows+=("$tick" "$key" "${P_NAME[$key]}$note" "${P_INFO[$key]}")
        done
        say "Waiting for your answer in the window (it may be behind this one)..."
        PROFILES=$("${Z[@]}" --list --checklist --width=700 --height=470 \
            --text="Which languages? Each gets its own VS Code profile, folder and tools.
Claude Code and a run button come with every one. (Claude Code itself needs a paid
Claude plan or API account; everything else works without it.)" \
            --column="" --column=key --column="Language" --column="Includes" --hide-column=2 --print-column=2 --separator=, \
            "${rows[@]}" 2>/dev/null) || cancelled
        if [[ -z $PROFILES && -z $INSTALLED ]]; then info "No language selected, so nothing was installed."; exit 0; fi
        PROFILES=$(normalize "$PROFILES")
        if [[ -z $BYPASS ]]; then
            choice=$("${Z[@]}" --list --checklist --width=700 --height=290 \
                --text="Bypass mode: Claude Code works without asking before each step. Faster, but it can
change files and run commands without asking. Untick to approve each action.

Terminal log: Claude can read what you ran in VS Code's terminals. Anything shown there
is saved, also passwords or keys printed on screen; logs are kept for about a day." \
                --column="" --column=id --column="Option" --hide-column=2 --print-column=2 \
                TRUE bypass "Claude Code in bypass mode" \
                FALSE termlog "Terminal log" \
                2>/dev/null) || cancelled
            BYPASS=0
            if [[ $choice == *bypass* ]]; then BYPASS=1; fi
            if [[ $choice == *termlog* ]]; then TERMLOG=1; fi
        fi
    fi
    PROFILES=${PROFILES:-${chosen:-$DEFAULT_PROFILES}}
    if [[ -n $INSTALLED ]]; then PROFILES=$INSTALLED,$PROFILES; fi
    BYPASS=${BYPASS:-1}
    TERMLOG=${TERMLOG:-0}
    BYPASS_CHANGED=0
    if [[ -n $prev_bypass && $prev_bypass != "$BYPASS" ]]; then BYPASS_CHANGED=1; fi
    IFS=, read -ra SELECTED <<< "$(tr ',' '\n' <<< "$PROFILES" | awk 'NF && !seen[$0]++' | paste -sd, -)"
    for key in "${SELECTED[@]}"; do
        [[ -v "P_NAME[$key]" ]] || die "unknown language '$key' (available: ${ALL_KEYS[*]})"
    done
    ((${#SELECTED[@]})) || die "no language selected"
    # An older Rust from the system stays (see missing_packages), but the workspace needs edition 2024.
    if has_key rust && ! command -v rustup >/dev/null && command -v rustc >/dev/null; then
        local rv
        rv=$(rustc --version | sed -n 's/^rustc 1\.\([0-9]*\).*/\1/p')
        if [[ -n $rv ]] && ((rv < 85)); then
            fail "The Rust on this system is too old (1.$rv; the Rust workspace needs 1.85). Untick Rust, or remove the old one (sudo apt remove rustc cargo) so that the setup can install a current one, then start again."
        fi
    fi

    ask_git_identity
    close_vscode

    # What is missing, and how big is it? (Logged to a temporary file until the user says Install.)
    LOG=$(mktemp "${TMPDIR:-/tmp}/setup-workspace-XXXXXX.log")
    PREP_LOG=$LOG
    mapfile -t MISSING < <(missing_packages)
    if ((${#MISSING[@]})) || ! command -v code >/dev/null; then
        need_sudo
        refresh_lists
        mapfile -t MISSING < <(missing_packages)
        check_candidates
    fi
    names=()
    for key in "${SELECTED[@]}"; do names+=("${P_NAME[$key]}"); done
    summary="Languages: ${names[*]}  (+ Setup Manager)
Folder: $(show "$ROOT")
Packages: "
    local mb=0
    if ((${#MISSING[@]})); then
        mb=$(download_mb "${MISSING[@]}")
        summary+="${#MISSING[@]} to install${mb:+, about $mb MB download}"
    else summary+="all present"; fi
    if [[ $mb != [0-9]* ]]; then mb=0; fi
    check_disk "$mb"
    check_writable
    if [[ -d $VSC_USER && ! -f $MANIFEST ]]; then summary+="
VS Code: found; your settings are backed up first and stay unchanged"
    elif command -v code >/dev/null; then summary+="
VS Code: found"
    else summary+="
VS Code: will be installed (about 250 MB)"; fi
    case $FLATPAK_CHOICE in
        keep) summary+="
Flatpak VS Code: stays as it is" ;;
        remove) summary+="
Flatpak VS Code: gets removed once the regular one is installed" ;;
    esac
    if ((SOURCE_PENDING)); then summary+="
Package source: Ubuntu's universe gets switched on"; fi
    if [[ -n $UNAVAILABLE ]]; then summary+="
Not available here, so the languages that need them will fail: $UNAVAILABLE"; fi
    if has_key rust && ! rustc --version >/dev/null 2>&1; then summary+="
Rust: toolchain download, about 300 MB"; fi
    summary+="
Extensions and Python packages: about 400 MB download
Claude: bypass mode $( ((BYPASS)) && echo on || echo off)"
    if [[ -n $GIT_NAME$GIT_EMAIL ]]; then summary+="
Git: commits as ${GIT_NAME:-(no name)} <${GIT_EMAIL:-no email}>"; fi
    if ((TERMLOG)); then summary+="
Terminal log: on (~/.terminal-logs, kept for about a day)"; fi
    say "$summary"
    ask "$summary" "Install" || cancelled
    write_conf
    stay_awake

    # ─── Install ───
    mkdir -p "$SM/logs"
    local prep=$LOG
    LOG=$SM/logs/install-$(date +%F_%H%M).log
    printf 'setup-workspace.sh %s\n' "$SCRIPT_VERSION" >> "$LOG"
    cat "$prep" >> "$LOG"; rm -f "$prep"; PREP_LOG=""
    if [[ ! -f $MANIFEST ]]; then
        printf '# Everything setup-workspace.sh added (kind<TAB>value). --uninstall reads this file.\n' > "$MANIFEST"
    fi
    if ((SOURCE_PENDING)); then record aptsource "$SOURCE_FILE"; SOURCE_PENDING=0; fi
    say ""
    say "Installing. Details appear here and in $(show "$LOG"). Please keep this window open."
    progress_start $((8 + ${#SELECTED[@]} * 3))
    local apt_before
    apt_before=$(manifest_lines apt | wc -l)
    note_new_home_dirs
    backup_vscode
    MISSING=()
    mapfile -t MISSING < <(missing_of)
    install_packages
    command -v code >/dev/null || fail "VS Code is not available after installing it; see $(show "$LOG")."
    remove_flatpak_vscode
    set_git_identity
    make_setup_manager
    add_commit_rule
    close_vscode
    setup_profile setup_manager "$SETUP_MANAGER_NAME" tools "$SETUP_MANAGER_RGB" "" ""
    # Without this VS Code opens every workspace in Restricted Mode: no run button, tasks, debugger or
    # Claude. Only the Workspace folder: other folders under the root (cloned repos) still ask.
    for dir in "$WS" "$VSC_USER"; do
        if ! recorded trust "$dir"; then
            py trust "$VSC_USER/globalStorage/state.vscdb" "$dir"
            record trust "$dir"
        fi
    done
    make_launcher
    setup_skills
    setup_terminal_log
    for key in "${SELECTED[@]}"; do install_language "$key"; done
    NEW_PKGS=$(( $(manifest_lines apt | wc -l) - apt_before ))
    run_checks
    finish "$( [[ -n $INSTALLED ]] && echo "added/repaired" || echo "installed")"
    progress_end

    local done_text
    done_text="$(if ((${#CHECK_OK[@]})); then printf 'Done, and tested. Working: %s.' "$(printf '%s, ' "${CHECK_OK[@]}" | sed 's/, $//')"; else echo 'VS Code, Claude and Setup Manager are in place.'; fi)
Start \"VS Launcher\" from the app menu and pick a workspace.

First time in VS Code:
 - Claude Code: open its panel and sign in once (needs a paid Claude plan or API account)$(if has_key python; then printf '\n - Notebooks: the first run asks for a kernel: Python Environments, then .venv (Recommended)'; fi)

More: $(show "$SM")/README.md"
    if ((${#FAILED[@]})); then
        say "Not installed:"; printf ' - %s\n' "${FAILED[@]}" >&4
        done_text="Not finished: ${#FAILED[@]} extensions could not be installed. VS Code says:
$(grep -E '^(Error|Failed Installing)' "$LOG" | tail -1 | cut -c1-120)

If that's the internet connection: connect and run this again, it only adds what is missing:
bash $(show "$SM")/scripts/setup-workspace.sh

Profiles affected: $(printf '%s\n' "${FAILED[@]}" | sed 's/: .*//' | awk '!seen[$0]++' | paste -sd, - | sed 's/,/, /g')"
    fi
    if ((${#CHECK_BAD[@]})); then
        done_text="Installed, but these don't work:
$(printf ' - %s\n' "${CHECK_BAD[@]}")

The rest of the setup is in place. To fix this, open Setup Manager in VS Launcher and ask Claude: its rules point to the log. Or run this again, it repairs what it can:
bash $(show "$SM")/scripts/setup-workspace.sh
Details: $(show "$LOG")

$done_text"
    fi
    if ((${#NOTES[@]})); then done_text+="

Note:
$(printf ' - %s\n' "${NOTES[@]}")"; fi
    info "$done_text"
}

main "$@"
