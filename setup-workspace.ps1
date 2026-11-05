<#
setup-workspace.ps1 - a ready-to-use VS Code setup for several languages on Windows 10/11:
one colour-coded profile per language with its toolchain and extensions, Claude Code as the
built-in agent, and a launcher that opens each workspace with its profile.
Windows version of setup-workspace.sh (same features, same files).

  <root>\launcher.ps1               "VS Launcher" in the Start menu: pick a workspace
  <root>\Workspace\<language>\      scratch\, projects\, templates\, the workspace's Claude rules
  <root>\Workspace\setup_manager\   README.md, installed.txt (what was added), logs, this script

Start it as your normal user, in PowerShell:
  powershell -ExecutionPolicy Bypass -File setup-workspace.ps1          windows to pick languages
  powershell -ExecutionPolicy Bypass -File setup-workspace.ps1 -Help    all options
Everything it adds is listed in setup_manager\installed.txt; -Uninstall removes exactly that.
#>
[CmdletBinding()]
param(
    [string]$Profiles = '',
    [string]$Add = '',
    [string]$Root = '',
    [switch]$NoBypass,
    [switch]$NoGui,
    [switch]$Check,
    [switch]$Uninstall,
    [switch]$Help
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:NODE_NO_WARNINGS = '1'   # VS Code's command line prints deprecation warnings
# Managed PCs: a locked-down PowerShell can't run this script at all. Say so before the first error.
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host "This PC is managed (PowerShell runs in restricted language mode), so this setup can't run here. Ask your IT department."
    Read-Host 'Press Enter to close'
    exit 1
}

$ScriptVersion = '1.0'

# Where the published script can be downloaded. Set when publishing.
$SourceUrl = ''
# Started as "irm <url> | iex" there is no file: every "exit" would close this PowerShell window and
# no copy could go into setup_manager\scripts. So run a downloaded copy as a normal script instead.
if (-not $PSCommandPath) {
    $ErrorActionPreference = 'Continue'
    if (-not $SourceUrl) { Write-Host 'Save setup-workspace.ps1 as a file and run: powershell -ExecutionPolicy Bypass -File setup-workspace.ps1'; return }
    $copy = Join-Path $env:TEMP 'setup-workspace.ps1'
    try { Invoke-WebRequest -UseBasicParsing $SourceUrl -OutFile $copy } catch { Write-Host "Download failed: $($_.Exception.Message)"; return }
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $copy
    return
}

# --- Profiles -------------------------------------------------------------------------------
# Key = workspace folder name. Icons: https://code.visualstudio.com/api/references/icons-in-labels
# Winget = packages for this language; Set = extra profile settings.
$LatexTools = @{
    'latex-workshop.latex.recipes' = @(@{ name = 'pdflatex x2'; tools = @('pdflatex', 'pdflatex') })
    'latex-workshop.latex.tools'   = @(@{ name = 'pdflatex'; command = 'pdflatex'; args = @('-synctex=1', '-interaction=nonstopmode', '-file-line-error', '%DOCFILE%') })
}
$ProfileTable = @(
    @{ Key = 'python';  Name = 'Python';  Icon = 'snake';          Rgb = '0 40 110'
       Ext = 'ms-python.python ms-python.vscode-pylance ms-python.debugpy ms-toolsai.jupyter'; Winget = @()
       Info = 'Python 3, notebooks, debugger, ready environment (numpy, pandas, matplotlib)'
       Set = @{ 'python.terminal.executeInFileDir' = $true } }
    @{ Key = 'cpp';     Name = 'C++';     Icon = 'chip';           Rgb = '90 68 0'
       Ext = 'llvm-vs-code-extensions.vscode-clangd vadimcn.vscode-lldb'; Winget = @('BrechtSanders.WinLibs.POSIX.UCRT.LLVM')
       Info = 'g++ compiler (WinLibs), clangd code help, debugger'; Set = @{ 'clangd.fallbackFlags' = @('-std=c++23') } }
    @{ Key = 'latex';   Name = 'LaTeX';   Icon = 'mortar-board';   Rgb = '58 0 95'
       Ext = 'james-yu.latex-workshop'; Winget = @('MiKTeX.MiKTeX')
       Info = 'MiKTeX + LaTeX Workshop: PDF builds on save (packages install on first use)'; Set = $LatexTools }
    @{ Key = 'bash';    Name = 'Bash';    Icon = 'terminal-linux'; Rgb = '10 80 10'
       Ext = 'mads-hartmann.bash-ide-vscode timonwong.shellcheck'; Winget = @('koalaman.shellcheck')
       Info = 'Shell scripts with Git Bash and ShellCheck'; Set = @{} }
    @{ Key = 'rust';    Name = 'Rust';    Icon = 'robot';          Rgb = '95 38 0'
       Ext = 'rust-lang.rust-analyzer vadimcn.vscode-lldb'; Winget = @('Rustlang.Rustup')
       Info = 'Rust toolchain (rustup, GNU), rust-analyzer, debugger'; Set = @{} }
)
$P = @{}; foreach ($row in $ProfileTable) { $P[$row.Key] = $row }
$AllKeys = $ProfileTable | ForEach-Object { $_.Key }
$DefaultProfiles = 'python,cpp,latex,bash'
$BaseExtensions = 'usernamehw.errorlens formulahendry.code-runner anthropic.claude-code'
# winget id -> install scope ('' = the package's default)
# Git's installer always needs admin rights, whatever scope winget is told (tried in the VM, also with /CURRENTUSER).
$BaseWinget = [ordered]@{ 'Git.Git' = ''; 'Python.Python.3.14' = 'user'; 'Microsoft.VisualStudioCode' = 'user' }
$PyPackages = 'numpy pandas matplotlib ipykernel'
$SetupManagerName = 'Setup Manager'
$SetupManagerRgb = '40 40 40'

if ($Help) {
    @"
Usage: powershell -ExecutionPolicy Bypass -File setup-workspace.ps1 [options]        (version $ScriptVersion)

Windows ask which languages to set up. With -NoGui it installs the default set: $DefaultProfiles.

  -Profiles LIST   languages to set up, comma-separated (available: $($AllKeys -join ' '))
  -Add LIST        add languages to an existing setup
  -Root DIR        where everything goes (default: %USERPROFILE%\Code)
  -NoBypass        Claude Code asks before each action (default: bypass mode, it doesn't)
  -NoGui           no windows
  -Check           test that the installed languages work; changes nothing
  -Uninstall       remove what setup_manager\installed.txt lists (asks first)
  -Help            this text
"@
    exit 0
}

# --- Paths ----------------------------------------------------------------------------------
# Run from its copy in Workspace\setup_manager\scripts\, the script belongs to that setup.
$Self = $PSCommandPath
if (-not $Root -and $Self -and $Self -like '*\Workspace\setup_manager\scripts\setup-workspace.ps1') {
    $Root = $Self.Substring(0, $Self.Length - '\Workspace\setup_manager\scripts\setup-workspace.ps1'.Length)
}
# Not ~\Documents: it is often synced by OneDrive, which fights with venvs and build folders.
if (-not $Root) { $Root = Join-Path $env:USERPROFILE 'Code' }
$Root = [IO.Path]::GetFullPath($Root)
$WS = Join-Path $Root 'Workspace'
$SM = Join-Path $WS 'setup_manager'
$Manifest = Join-Path $SM 'installed.txt'
$Conf = Join-Path $SM 'setup.conf'
$Venv = Join-Path $WS '.venv'
$VscDir = Join-Path $env:APPDATA 'Code'
$VscUser = Join-Path $VscDir 'User'
$Storage = Join-Path $VscUser 'globalStorage\storage.json'
$StateDb = Join-Path $VscUser 'globalStorage\state.vscdb'
$MenuFile = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\VS Launcher.lnk'
$KernelDir = Join-Path $env:APPDATA 'jupyter\kernels\workspace-venv'
$Skills = Join-Path $env:USERPROFILE '.claude\skills'
$Marker = '<!-- installed by setup-workspace.sh -->'
$Today = Get-Date -Format 'yyyy-MM-dd'
$Trash = Join-Path $Root "Trash\$Today"
$script:Log = $null
$script:Failed = @()
$script:Unavailable = @()
$script:LangFailed = @{}; $script:Containing = $false; $script:Reason = ''
$script:Notes = @()
$script:CurrentStep = 'preparation'
$script:StepNo = 0
$script:StepCount = 1
$Utf8 = New-Object Text.UTF8Encoding $false

# --- Output, files, dialogs -----------------------------------------------------------------
function Say([string]$Text) {
    Write-Host $Text
    if ($script:Log) { [IO.File]::AppendAllText($script:Log, "$Text`n", $Utf8) }
}
function Show([string]$Path) { $Path.Replace($env:USERPROFILE, '%USERPROFILE%') }
function Write-Text([string]$Path, [string]$Text) {  # UTF-8 without BOM, LF line endings
    $dir = Split-Path $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), $Utf8)
}

# Native command, output into the log only; returns the exit code. Quiet EXE ARGS...
# (Plain $args functions: arguments like "--id" or "-m" must not be taken as parameter names.)
function Quiet {
    $Exe = $args[0]; $ArgList = @($args | Select-Object -Skip 1)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # Shown and logged. winget's spinner and bars arrive as lines of their own: not worth keeping.
        & $Exe @ArgList 2>&1 | ForEach-Object {
            $line = "$_"
            if ($line.Trim() -and $line -notmatch '^\s*[-\\|/]\s*$' -and $line -notmatch '\d+(\.\d+)? [KMG]?i?B\s*/\s*\d' -and $line -notmatch '^\s*\d+%\s*$') {
                Write-Host $line
                if ($script:Log) { [IO.File]::AppendAllText($script:Log, "$line`n", $Utf8) }
            }
        }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    return $code
}

# A click in the old console window selects text, and that freezes the whole install until a key is pressed.
function Disable-QuickEdit {
    try {
        Add-Type -Namespace SetupWS -Name Con -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint f);
"@
        $h = [SetupWS.Con]::GetStdHandle(-10); $m = [uint32]0
        if ([SetupWS.Con]::GetConsoleMode($h, [ref]$m)) { [void][SetupWS.Con]::SetConsoleMode($h, ($m -band (-bnot [uint32]0x40)) -bor 0x80) }
    } catch { }
}
function Stay-Awake { try { [void][SetupWS.Con]::SetThreadExecutionState([uint32]2147483649) } catch { } }   # ends with this process

$GUI = -not $NoGui
if ($GUI) {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
}

function New-Dialog([string]$Title, [int]$Width, [int]$Height) {
    $f = New-Object Windows.Forms.Form
    $f.Text = $Title; $f.ClientSize = New-Object Drawing.Size($Width, $Height)
    $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.TopMost = $true
    $f.Font = New-Object Drawing.Font('Segoe UI', 10)
    $f.Add_Shown({ $this.Activate() })  # otherwise the console window keeps the keyboard focus
    return $f
}
function Add-Buttons($Form, [string]$OkText, [string]$CancelText) {
    $w = $Form.ClientSize.Width; $h = $Form.ClientSize.Height
    $ok = New-Object Windows.Forms.Button; $ok.Text = $OkText; $ok.SetBounds($w - 230, $h - 48, 105, 34); $ok.DialogResult = 'OK'
    $Form.AcceptButton = $ok; $Form.Controls.Add($ok)
    if ($CancelText) {
        $c = New-Object Windows.Forms.Button; $c.Text = $CancelText; $c.SetBounds($w - 118, $h - 48, 105, 34); $c.DialogResult = 'Cancel'
        $Form.CancelButton = $c; $Form.Controls.Add($c)
    } else { $ok.Left = $w - 118 }
}
function Add-Label($Form, [string]$Text, [int]$Top, [int]$Height) {
    $l = New-Object Windows.Forms.Label; $l.Text = $Text; $l.SetBounds(16, $Top, $Form.ClientSize.Width - 32, $Height)
    $Form.Controls.Add($l)
}

function Info([string]$Text) {
    Say $Text
    if (-not $GUI) { return }
    $lines = ($Text -split "`n").Count
    $f = New-Dialog 'VS Code setup' 640 (90 + 22 * $lines)
    Add-Label $f $Text 16 (22 * $lines + 10)
    Add-Buttons $f 'OK' ''
    [void]$f.ShowDialog()
}

function Ask([string]$Text, [string]$OkText = 'Yes') {  # $true = yes
    Say $Text
    if (-not $GUI) { return $true }
    Write-Host 'Waiting for your answer in the window (it may be behind this one)...'
    $lines = ($Text -split "`n").Count
    $f = New-Dialog 'VS Code setup' 640 (90 + 22 * $lines)
    Add-Label $f $Text 16 (22 * $lines + 10)
    Add-Buttons $f $OkText 'Cancel'
    return ($f.ShowDialog() -eq 'OK')
}

function Checklist([string]$Text, [object[]]$Items) {  # items: @{Key; Label; Checked} -> keys, $null = cancelled
    Write-Host 'Waiting for your answer in the window (it may be behind this one)...'
    $h = 150 + 26 * $Items.Count
    $f = New-Dialog 'VS Code setup' 720 $h
    Add-Label $f $Text 12 46
    $c = New-Object Windows.Forms.CheckedListBox
    $c.CheckOnClick = $true; $c.IntegralHeight = $false; $c.SetBounds(16, 64, 688, 26 * $Items.Count + 12)
    foreach ($i in $Items) { [void]$c.Items.Add($i.Label, [bool]$i.Checked) }
    $f.Controls.Add($c)
    Add-Buttons $f 'OK' 'Cancel'
    if ($f.ShowDialog() -ne 'OK') { return $null }
    $keys = @()
    for ($n = 0; $n -lt $Items.Count; $n++) { if ($c.GetItemChecked($n)) { $keys += $Items[$n].Key } }
    return , $keys
}

# Did the last lines of the log come from a lost connection?
function Net-Hint {
    if (-not $script:Log -or -not (Test-Path $script:Log)) { return '' }
    if (Select-String -InputObject ((Get-Content $script:Log -Tail 30) -join "`n") -Quiet -Pattern '0x80072E(E2|E7|FD|FE)|0x80072F78|Could not resolve|Could not connect|getaddrinfo|Temporary failure|Connection (timed out|reset|refused)|ReadTimeoutError|NewConnectionError|curl: \(\d+\)') {
        return "`n`nThis looks like a lost internet connection: check it first."
    }
    return ''
}

# Optional, and only on a first run with no identity yet: Git works without it until the first commit.
function Ask-GitIdentity {  # -> @(name, email)
    if (-not $GUI -or $Installed) { return @('', '') }
    if ((Get-Command git -ErrorAction SilentlyContinue) -and "$(Capture git config --global user.name)$(Capture git config --global user.email)") { return @('', '') }
    Write-Host 'Waiting for your answer in the window (it may be behind this one)...'
    $f = New-Dialog 'VS Code setup' 640 220
    Add-Label $f "Optional: your name and email for Git commits. They appear in the history of anything you publish.`nLeave empty or press Skip if you don't want this now." 12 46
    Add-Label $f 'Name' 72 24
    Add-Label $f 'Email' 112 24
    $n = New-Object Windows.Forms.TextBox; $n.SetBounds(80, 68, 544, 28); $f.Controls.Add($n)
    $e = New-Object Windows.Forms.TextBox; $e.SetBounds(80, 108, 544, 28); $f.Controls.Add($e)
    $n.BringToFront(); $e.BringToFront()   # the labels are as wide as the window and would cover them
    Add-Buttons $f 'Save' 'Skip'
    $f.Add_Shown({ $n.Select() })
    if ($f.ShowDialog() -ne 'OK') { return @('', '') }
    return @($n.Text.Trim(), $e.Text.Trim())
}
# Only with a Git identity: without one, a commit fails.
function Add-CommitRule {
    $rule = '- Projects with git: commit when a change works, with a short message. Never push unless asked; never commit secrets.'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }
    if (-not "$(Capture git config --global user.name)" -or -not "$(Capture git config --global user.email)") { return }
    $f = "$WS\CLAUDE.md"
    $t = [IO.File]::ReadAllText($f)
    if ($t.Contains($rule)) { return }
    if (-not $t.EndsWith("`n")) { $t += "`n" }
    [IO.File]::WriteAllText($f, "$t$rule`n", $Utf8)
}
function Set-GitIdentity {
    if (-not "$script:GitName$script:GitEmail") { return }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }
    $file = Join-Path $env:USERPROFILE '.gitconfig'
    if (-not (Test-Path $file)) { Record gitfile $file }
    if ($script:GitName) { [void](Quiet git config --global user.name $script:GitName); Record gitkey user.name }
    if ($script:GitEmail) { [void](Quiet git config --global user.email $script:GitEmail); Record gitkey user.email }
}

function Fail([string]$Text) {
    if ($script:Containing) { $script:Reason = $Text; throw $Text }   # stops this language only: see Contained
    Stop-Progress
    if ($Text -notmatch 'internet') { $Text += Net-Hint }
    if ($script:Log -and (Test-Path $script:Log)) { $Text += "`n`nDetails: $($script:Log)" }
    Say "error: $Text"
    if ($GUI) { [void][Windows.Forms.MessageBox]::Show($Text, 'VS Code setup', 'OK', 'Error') }
    exit 1
}

# Progress window in its own thread, so it keeps moving while a step runs.
$script:Sync = [hashtable]::Synchronized(@{ Text = 'Starting...'; Close = $false })
$script:ProgressPS = $null
function Start-Progress([int]$Steps) {
    $script:StepCount = $Steps; $script:StepNo = 0
    if (-not $GUI) { return }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync', $script:Sync)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $f = New-Object Windows.Forms.Form
        $f.Text = 'VS Code setup'; $f.ClientSize = New-Object Drawing.Size(560, 110); $f.StartPosition = 'CenterScreen'
        $f.FormBorderStyle = 'FixedDialog'; $f.ControlBox = $false; $f.TopMost = $true
        $f.Font = New-Object Drawing.Font('Segoe UI', 10)
        $l = New-Object Windows.Forms.Label; $l.SetBounds(16, 16, 528, 40); $f.Controls.Add($l)
        $b = New-Object Windows.Forms.ProgressBar; $b.Style = 'Marquee'; $b.SetBounds(16, 64, 528, 22); $f.Controls.Add($b)
        $t = New-Object Windows.Forms.Timer; $t.Interval = 300
        $t.Add_Tick({ $l.Text = $Sync.Text; if ($Sync.Close) { $t.Stop(); $f.Close() } })
        $t.Start()
        [void]$f.ShowDialog()
    })
    $script:ProgressHandle = $ps.BeginInvoke()
    $script:ProgressPS = $ps
}
function Step([string]$Text) {
    $script:CurrentStep = $Text
    $script:StepNo++
    Say "== $Text"
    $script:Sync.Text = "Step $($script:StepNo) of about $($script:StepCount): $Text"
}
function Stop-Progress {
    if (-not $script:ProgressPS) { return }
    $script:Sync.Close = $true
    [void]$script:ProgressHandle.AsyncWaitHandle.WaitOne(3000)
    $script:ProgressPS.Dispose()
    $script:ProgressPS = $null
}

# --- Manifest (installed.txt): one "kind<TAB>value..." line per thing this script added -----
function Record { $Fields = $args
    [IO.File]::AppendAllText($Manifest, (($Fields -join "`t") + "`n"), $Utf8) }
function Recorded { $Fields = $args
    if (-not (Test-Path $Manifest)) { return $false }
    $line = $Fields -join "`t"
    return [bool](Get-Content $Manifest -Encoding UTF8 | Where-Object { $_ -ceq $line })
}
function Manifest-Lines([string]$Kind) {  # values of all lines of that kind (tab-separated)
    if (-not (Test-Path $Manifest)) { return @() }
    return @(Get-Content $Manifest -Encoding UTF8 | Where-Object { $_.StartsWith("$Kind`t") } | ForEach-Object { $_.Substring($Kind.Length + 1) })
}
function Unrecord { $Fields = $args
    $line = $Fields -join "`t"
    $keep = @(Get-Content $Manifest -Encoding UTF8 | Where-Object { $_ -cne $line })
    [IO.File]::WriteAllText($Manifest, (($keep -join "`n") + "`n"), $Utf8)
}

# Put FILE CONTENT - create FILE unless it exists (never overwrites); @ROOT@ is replaced.
function Put([string]$File, [string]$Content) {
    if (Test-Path $File) { return }
    $codeExe = ''; if ($script:Code) { $codeExe = Join-Path (Split-Path (Split-Path $script:Code)) 'Code.exe' }
    Write-Text $File $Content.Replace('@ROOT@', $Root).Replace('@CODEEXE@', $codeExe)
    Record file $File
}
function Mkd {
    foreach ($d in $args) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force $d | Out-Null; Record dir $d } }
}

# --- Tools ----------------------------------------------------------------------------------
# Native command's standard output as lines; errors ignored (PowerShell 5.1 would abort on stderr).
function Capture {
    $Exe = $args[0]; $ArgList = @($args | Select-Object -Skip 1)
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = @(& $Exe @ArgList 2>$null) } finally { $ErrorActionPreference = $old }
    return $out
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Find-Code {
    foreach ($c in @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd", "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd")) {
        if (Test-Path $c) { return $c }
    }
    $c = Get-Command code.cmd -ErrorAction SilentlyContinue   # installed somewhere else
    if ($c) { return $c.Source }
    return $null
}
function Find-Python {  # the real python.exe (not the Microsoft Store stub), newest 64-bit first
    foreach ($want in @("$env:LOCALAPPDATA\Programs\Python\Python314\python.exe", "$env:LOCALAPPDATA\Programs\Python\Python314-arm64\python.exe")) {
        if (Test-Path $want) { return $want }
    }
    # Folder names sort wrongly as text (Python39 > Python314): compare the version numbers.
    $cands = @(Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe", "$env:ProgramFiles\Python3*\python.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -match '^Python3(\d+)(-arm64)?$' } | Sort-Object { [int]($_.Directory.Name -replace '^Python3(\d+).*$', '$1') } -Descending)
    if ($cands.Count) { return $cands[0].FullName }
    return $null
}
function Find-GitBash {
    foreach ($c in @("$env:ProgramFiles\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) { if (Test-Path $c) { return $c } }
    return $null
}

# Entries in Windows' list of installed programs (Settings > Apps), without hidden components.
# An installer can add more than its own entry (Python adds "Python Launcher"); only entries that
# match the package's pattern are recorded, so a program something else installs meanwhile
# (Windows Update, the Store, the user) is never taken for the setup's.
$ProgramPattern = @{
    'Git.Git' = '^Git$'; 'Python.Python.3.14' = '^Python 3\.14|^Python Launcher$'
    'Microsoft.VisualStudioCode' = '^Microsoft Visual Studio Code'; 'BrechtSanders.WinLibs.POSIX.UCRT.LLVM' = '^WinLibs'
    'MiKTeX.MiKTeX' = '^MiKTeX'; 'koalaman.shellcheck' = '^ShellCheck'; 'Rustlang.Rustup' = '^Rustup'
}
function Program-Names {
    $keys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    return @(Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.SystemComponent -ne 1 -and -not $_.ParentKeyName } |
        ForEach-Object { $_.DisplayName } | Sort-Object -Unique)
}

function Winget-Installed([string]$Id) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & winget list --id $Id -e --accept-source-agreements --disable-interactivity *> $null; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
    return ($code -eq 0)
}
# What winget's failure codes mean, in words. (Full list: AppInstallerErrors.h in winget-cli.)
function Winget-Error([int]$Code) {
    switch ('0x{0:X8}' -f $Code) {
        '0x8A15000F' { return "winget's package list is damaged or couldn't be read (try: winget source reset --force, as administrator)" }
        '0x8A150010' { return 'no installer of it fits this computer' }
        '0x8A150011' { return 'the download did not match its checksum (it may just have been updated: try again later)' }
        '0x8A15003A' { return 'blocked by a policy on this PC' }
        '0x8A15010F' { return 'blocked by a policy on this PC' }
        '0x8A15005E' { return "the server's certificate did not match (wrong clock? a proxy or antivirus inspecting connections?)" }
        '0x8A150102' { return 'another installation is running' }
        '0x8A150105' { return 'the disk is full' }
        '0x8A15010A' { return 'Windows needs a restart first' }
        '0x8A15010C' { return 'cancelled, or the permission window was answered with No' }
        '0x80072F05' { return "the computer's clock is wrong" }
        '0x80072EE7' { return 'no internet connection' }
        '0x80072EFD' { return 'no internet connection' }
    }
    return "winget error $('0x{0:X8}' -f $Code)"
}
function Wait-OtherInstaller {  # Windows runs one installer at a time; a new PC installs things by itself in its first hours
    $said = $false
    for ($i = 0; $i -lt 60; $i++) {
        $m = $null
        if (-not [Threading.Mutex]::TryOpenExisting('Global\_MSIExecute', [ref]$m)) { return }
        $m.Dispose()
        if (-not $said) { Say 'Another installer is running: waiting, up to 10 minutes...'; $said = $true }
        Start-Sleep -Seconds 10
    }
}
function Winget-Install([string]$Id, [string]$Scope) {
    $a = @('install', '--id', $Id, '-e', '--source', 'winget', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    if ($Scope) { $a += @('--scope', $Scope) }
    # The long path of winget's own package folder pushes g++'s includes over Windows' 260 characters on longer user names.
    if ($Id -eq 'BrechtSanders.WinLibs.POSIX.UCRT.LLVM') { $a += @('--location', "$env:LOCALAPPDATA\Programs\WinLibs") }
    # Noted first: if this run gets killed during the install, the rerun and the uninstall still know.
    if (-not (Recorded winget $Id)) { Record winget $Id }
    Wait-OtherInstaller
    $start = Get-Date
    $code = Quiet winget @a
    if ($code -ne 0) { Start-Sleep -Seconds 20; Wait-OtherInstaller; $code = Quiet winget @a }  # one retry: downloads fail now and then
    # winget also reports success when antivirus software removed the installer while it ran (seen with Microsoft Defender).
    if ($code -eq 0 -and ((Program-Names) -match $ProgramPattern[$Id])) { return }
    if (-not (Winget-Installed $Id)) { Unrecord winget $Id }
    if ($code -eq 0) {
        $threat = ''
        try {   # only a detection of this package's download (winget keeps it in %TEMP%\WinGet\<id>.<version>\)
            $d = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object {
                $_.InitialDetectionTime -ge $start.AddMinutes(-1) -and "$($_.Resources)" -like "*\WinGet\$Id.*" })
            if ($d.Count) { $threat = "$((Get-MpThreat -ThreatID $d[0].ThreatID -ErrorAction SilentlyContinue).ThreatName)" }
        } catch { }
        if ($threat) { Fail "Microsoft Defender removed the installer of $Id while it ran (detection: $threat), most likely a false alarm. Start the setup again: it continues where it stopped. If it happens again, see Windows Security > Virus & threat protection > Protection history." }
        Fail "winget reported success, but $Id is not installed: antivirus software may have removed its installer (Windows Security > Virus & threat protection > Protection history). Start the setup again: it continues where it stopped."
    }
    Fail "Installing $Id failed: $(Winget-Error $code). Fix that, then start the setup again."
}

function Ensure-Winget {
    if ([Environment]::OSVersion.Version.Build -lt 17763) { Fail 'This Windows version is too old for this setup: it needs Windows 10 1809 or newer.' }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        # Fresh Windows installs sometimes have App Installer present but not yet registered.
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe } catch { }
    }
    $v = ''
    if (Get-Command winget -ErrorAction SilentlyContinue) { $v = (Capture winget --version | Select-Object -First 1) }
    # Below 1.6.3482 it can exit without a word: a new PC gets updated in the background by the Store.
    if ($v -notmatch '^v?(\d+)\.(\d+)\.(\d+)' -or [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" -lt [version]'1.6.3482') {
        Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' -ErrorAction SilentlyContinue
        Fail "winget (Microsoft's App Installer) is missing or too old$(if ($v) { " ($v)" }). Update 'App Installer' in the Microsoft Store window that just opened, then start the setup again. (No Store on this Windows: https://aka.ms/getwinget)"
    }
    # With a time limit: on a stalled connection it can wait for a long time, and the checks after it say more.
    $u = Start-Process winget -ArgumentList 'source', 'update', '--name', 'winget', '--disable-interactivity' -PassThru -WindowStyle Hidden
    if (-not $u.WaitForExit(120000)) { try { $u.Kill() } catch { } }
}

# Before anything changes: internet, clock, blocked servers.
function Check-Internet {
    for ($try = 1; ; $try++) {
        $problem = ''
        try {
            $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 'http://www.msftconnecttest.com/connecttest.txt'
            if ("$($r.Content)".Trim() -ne 'Microsoft Connect Test') { $problem = 'A login page is answering instead of the internet (hotel, school, public Wi-Fi?): log in with the browser.' }
            elseif ($r.Headers['Date']) {
                $off = [math]::Abs(((Get-Date).ToUniversalTime() - ([datetime]$r.Headers['Date']).ToUniversalTime()).TotalHours)
                if ($off -gt 2) {
                    Start-Process 'ms-settings:dateandtime' -ErrorAction SilentlyContinue
                    $problem = "This computer's clock is wrong (it says $(Get-Date -Format 'yyyy-MM-dd HH:mm')), so secure downloads would fail. Set the time in the Settings window that just opened (Sync now)."
                }
            }
        } catch { $problem = 'No internet connection: the setup has to download programs. Connect to the internet (Wi-Fi? a proxy?).' }
        if (-not $problem) { break }
        if (-not $GUI -or $try -gt 5) { Fail $problem }
        if (-not (Ask "$problem`n`nThen try again." 'Try again')) { exit 0 }
    }
    # Everything else the install needs. A firewall or proxy can block single servers.
    $blocked = @()
    foreach ($u in 'https://cdn.winget.microsoft.com', 'https://github.com', 'https://www.python.org', 'https://update.code.visualstudio.com', 'https://marketplace.visualstudio.com', 'https://pypi.org') {
        try { [void](Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec 15 $u) }
        catch { if ($_.Exception.Response -eq $null) { $blocked += ($u -replace '^https://', '') } }
    }
    if ($blocked.Count) {
        if (-not (Ask "These servers can't be reached (firewall, proxy or antivirus?):`n$($blocked -join ', ')`n`nThe setup will probably fail. Continue anyway?" 'Continue')) { exit 0 }
    }
}

function Free-GB([string]$Path) {
    try { return [math]::Floor((Get-PSDrive ([IO.Path]::GetPathRoot($Path).Substring(0, 1))).Free / 1GB) } catch { return 9999 }
}

# Who is this? As administrator with another account's password, everything would land in that account.
function Check-Account {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $owner = $null
    try {
        # This session's desktop only: on a shared PC other users' desktops run too.
        $o = Get-CimInstance Win32_Process -Filter "Name='explorer.exe' AND SessionId=$((Get-Process -Id $PID).SessionId)" -ErrorAction Stop | Select-Object -First 1 | Invoke-CimMethod -MethodName GetOwner
        if ($o.User) { $owner = "$($o.Domain)\$($o.User)" }
    } catch { }
    if ($owner -and $owner -ne $me) {
        Fail "This runs as $me, but $owner is logged in: everything would be set up for the wrong account. Start it without 'Run as administrator'. (A standard account works: Windows asks for an administrator's password only for Git.)"
    }
}

$MySession = (Get-Process -Id $PID).SessionId
function VSCode-Running {  # only this user's session: other logged-in users' VS Code is none of our business
    return [bool](Get-Process -Name Code -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $MySession })
}
function In-VSCode-Terminal {
    if ($env:TERM_PROGRAM -eq 'vscode') { return $true }
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 8 -and $p; $i++) {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.ParentProcessId)" -ErrorAction SilentlyContinue
        if ($p -and $p.Name -eq 'Code.exe') { return $true }
    }
    return $false
}
function Close-VSCode {  # VS Code rewrites its profile list when it exits, so it must be closed meanwhile
    if (-not (VSCode-Running)) { return }
    if (In-VSCode-Terminal) {
        Fail "This runs inside VS Code's terminal, and VS Code has to be closed while the setup changes its profiles. Close VS Code and run the same command in a normal PowerShell window."
    }
    if (-not (Ask "VS Code is open. It has to be closed while the setup changes its profiles.`nUnsaved files are kept (VS Code restores them).`n`nClose VS Code now?" 'Close VS Code')) { exit 0 }
    Get-Process -Name Code -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $MySession } | ForEach-Object { [void]$_.CloseMainWindow() }
    for ($i = 0; $i -lt 30; $i++) { if (-not (VSCode-Running)) { return }; Start-Sleep -Milliseconds 500 }
    Fail 'VS Code did not close. Close it yourself and start the setup again.'
}

# JSON / state edits run in Python (installed as a base package; PowerShell 5.1 has no SQLite).
$PyHelper = @'
import json, os, secrets, sys

def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}

def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8", newline="\n") as f:
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

def file_uri(p):  # the form VS Code stores Windows paths in
    from urllib.parse import quote
    p = os.path.abspath(p)
    if p.startswith("\\\\"):  # \\server\share\...
        host, _, rest = p[2:].partition("\\")
        rest = "/" + rest.replace("\\", "/")
        return {"$mid": 1, "fsPath": p, "_sep": 1, "external": f"file://{host}{quote(rest)}",
                "path": rest, "scheme": "file", "authority": host}
    drive, rest = p[0].lower(), p[2:].replace("\\", "/")
    return {"$mid": 1, "fsPath": drive + ":" + p[2:], "_sep": 1, "external": f"file:///{drive}%3A{quote(rest)}",
            "path": f"/{drive}:{rest}", "scheme": "file"}

cmd, *args = sys.argv[1:]

if cmd in ("trust", "untrust"):  # STATE_DB FOLDER - VS Code's list of trusted folders (covers subfolders)
    import sqlite3
    # VS Code keeps this list in the shared database once it has been started; before that it
    # copies it from the old one. So: always the old one, and the shared one if it exists.
    shared = os.path.expanduser("~/.vscode-shared/sharedStorage/state.vscdb")
    for state_db in [args[0]] + ([shared] if os.path.exists(shared) else []):
        os.makedirs(os.path.dirname(state_db), exist_ok=True)
        db = sqlite3.connect(state_db)
        db.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
        row = db.execute("SELECT value FROM ItemTable WHERE key = 'content.trust.model.key'").fetchone()
        trust = json.loads(row[0]) if row else {"uriTrustInfo": []}
        want = file_uri(args[1])
        entries = [e for e in trust.get("uriTrustInfo", []) if e.get("uri", {}).get("path", "").lower() != want["path"].lower()]
        if cmd == "trust":
            entries.append({"uri": want, "trusted": True})
        trust["uriTrustInfo"] = entries
        db.execute("INSERT INTO ItemTable VALUES ('content.trust.model.key', ?)", (json.dumps(trust),))
        db.commit()
        db.close()
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

elif cmd == "settings":         # FILE "R G B" JSONFILE -> adds the keys that are not set yet
    with open(args[2], encoding="utf-8-sig") as f:
        wanted = json.load(f)
    wanted["workbench.colorCustomizations"] = scheme(*map(int, args[1].split()))
    missing = {k: v for k, v in wanted.items() if k not in data}
    if missing:
        save(args[0], data | missing)

elif cmd == "set-keys":         # FILE JSONFILE -> sets these keys
    with open(args[1], encoding="utf-8-sig") as f:
        data.update(json.load(f))
    save(args[0], data)

elif cmd == "del-keys":         # FILE KEY... -> removes these keys
    if any(k in data for k in args[1:]):
        save(args[0], {k: v for k, v in data.items() if k not in args[1:]})
'@
$script:Python = $null
$script:Tmp = Join-Path $env:TEMP "setup-workspace-$PID"   # private: Python would import a planted json.py next to the helper
function Py {
    $ArgList = $args
    New-Item -ItemType Directory -Force $script:Tmp | Out-Null
    $helper = Join-Path $script:Tmp 'helper.py'
    Write-Text $helper $PyHelper
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = & $script:Python -I $helper @ArgList 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
    if ($code -ne 0) { Fail "Internal helper failed ($($ArgList[0])): $out" }
    return ($out | Out-String).Trim()
}

# --- Templates ------------------------------------------------------------------------------
$BaseRules = @'
# Shared rules for every workspace

Loaded by Claude Code in every folder below this one (each workspace adds its own `CLAUDE.md`).

## Layout

- `Workspace\<language>\`: `scratch\` for experiments, `projects\<name>\` for projects (VS Code task "New project" copies `templates\basic\`).
- `Workspace\.venv\`: the shared Python environment. Install packages with `.venv\Scripts\python -m pip install <package>`; never system-wide.
- `Workspace\setup_manager\`: the setup itself (README.md, installed.txt, logs, the setup script).
- This is Windows: the VS Code terminal is PowerShell; Git Bash is at `C:\Program Files\Git\bin\bash.exe`.

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

- `/log <message>` notes friction in `<workspace>\.claude\friction.md`; `/distill` later turns those notes into rules, only after approval.
- Changes to the setup (profiles, extensions, settings, packages, scripts) go into `setup_manager\logs\setup_log.txt`: `[YYYY-MM-DD] title`, then `- ` bullets.
'@

$LangRules = @{
    python = @'
# Python workspace

- Python 3 with the shared environment `..\.venv` (numpy, pandas, matplotlib); VS Code uses it as the interpreter. Install packages with `..\.venv\Scripts\python -m pip install <package>`.
- Run a file: `..\.venv\Scripts\python file.py` (in VS Code: the run button; F5 debugs).
- Notebooks (.ipynb) use the same environment, shown as ".venv" (a link in this folder); the first run of each notebook asks once: Python Environments, then .venv (Recommended). Edit individual cells and keep the user's cell structure. You only see cell outputs that are saved in the file; say what you couldn't check.
- Change only what was asked; if asked to change one line, change one line.
- Run the script after changing it and report what actually happened.
'@
    cpp = @'
# C++ workspace

- g++ (GCC, WinLibs) as C++23, with clangd for code help. Single files: the run button compiles and runs, F5 debugs (CodeLLDB), Ctrl+Shift+B only builds. All three build the current file only.
- Don't introduce a build system for a single-file program unless asked. Multi-file projects: generate `compile_commands.json` (CMake: `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) so clangd sees the real flags.
- Compile after every change; fix every error and warning you introduced.
'@
    latex = @'
# LaTeX workspace

- MiKTeX (installs missing LaTeX packages on first use); LaTeX Workshop builds with pdflatex on save and shows the PDF in a tab. Build files (.aux, .log, ...) are disposable.
- When transcribing or reformatting, keep content and wording exactly. Keep the document's macros and preamble; don't add a package when a loaded one does the job.
- After editing, build (`pdflatex -interaction=nonstopmode file.tex`, twice for references) and fix the errors you introduced; report remaining warnings.
- You cannot see the PDF: don't claim the layout looks right.
'@
    bash = @'
# Bash workspace

- Scripts run in Git Bash (the run button uses it; in a terminal: `& "C:\Program Files\Git\bin\bash.exe" file.sh`). ShellCheck lints in the editor. LF line endings only.
- Small, reviewable changes; never rewrite a whole script when only part needs updating.
- Run the script after editing and check its output. On unexplained failures, check for CRLF line endings first.
'@
    rust = @'
# Rust workspace

- rustup stable toolchain (GNU target, no Visual Studio needed). Projects: `cargo new projects/<name>`, then `cargo run`, `cargo test`, `cargo clippy`. Everything is one Cargo workspace (`Cargo.toml` here; `cargo new` adds projects to it), so rust-analyzer sees all files. Deleting a project: also remove its line from `members` in `Cargo.toml`, or cargo fails for the whole folder. Quick experiments: one file per program in `scratch\src\bin\<name>.rs` (run button, F5, or `cargo run --bin <name>`).
- Ask before adding a crate; prefer the standard library.
- `cargo build` (and clippy/test where relevant) after every change; fix what you introduced.
'@
}

$SetupManagerRules = @'
# Setup Manager

You maintain this VS Code setup: profiles, extensions, workspace folders, the launcher and packages. Read `README.md` and `installed.txt` before changing anything.

- VS Code keeps its profile list in `%APPDATA%\Code\User\globalStorage\storage.json` and rewrites it while running: never edit it with VS Code open.
- Adding a language the script knows: the user closes VS Code and runs `powershell -ExecutionPolicy Bypass -File scripts\setup-workspace.ps1 -Add <language>`. Anything else: create the profile in VS Code (Manage > Profiles), install its extensions there, and add a workspace folder like the existing ones.
- Before changing profiles, settings.json, .code-workspace files or the launcher: say what you will change and wait for approval. One profile at a time.
- Programs are installed with winget (`winget install --id <id> -e`); tell the user before installing anything.
- "Still doesn't work" means stop: look at the actual state (the files, `code --list-extensions --profile <name>`), say what was tried, then propose the next step.
- Log every change in `logs\setup_log.txt`.
- A language the install reported as failed: read the newest `logs\install-*.log`, find the cause, then fix it or give the user the command. `powershell -ExecutionPolicy Bypass -File scripts\setup-workspace.ps1 -Check` tests the installed languages.
'@

function Main-File([string]$Key) {
    switch ($Key) { 'python' { 'main.py' } 'cpp' { 'main.cpp' } 'latex' { 'main.tex' } 'bash' { 'main.sh' } 'rust' { 'src/main.rs' } }
}

function Notebook-Json([string]$Source) {  # first cell source as a JSON string array
    return @"
{
 "cells": [
  {"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [], "source": $Source}
 ],
 "metadata": {
  "kernelspec": {"display_name": "Python (Workspace)", "language": "python", "name": "workspace-venv"},
  "language_info": {"name": "python"}
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
"@
}

function Write-Examples([string]$Key, [string]$Dir) {  # scratch\hello.* (a first thing to run) and templates\basic\
    $t = Join-Path $Dir 'templates\basic'
    switch ($Key) {
        'python' {
            Put "$Dir\scratch\hello.py" "import numpy as np`n`nprint(`"Hello from Python, numpy`", np.__version__, np.arange(5) ** 2)`n"
            Put "$t\main.py" "def main():`n    print(`"Hello from a new project`")`n`n`nif __name__ == `"__main__`":`n    main()`n"
            Put "$t\.gitignore" "__pycache__/`n.venv/`n"
            Put "$Dir\scratch\hello.ipynb" (Notebook-Json '["import numpy as np\n", "import matplotlib.pyplot as plt\n", "\n", "x = np.linspace(0, 2 * np.pi, 100)\n", "plt.plot(x, np.sin(x))\n", "plt.show()"]')
        }
        'cpp' {
            Put "$Dir\scratch\hello.cpp" "#include <iostream>`n`nint main() {`n    std::cout << `"Hello from C++`" << std::endl;`n    return 0;`n}`n"
            Put "$t\main.cpp" "#include <iostream>`n`nint main() {`n    std::cout << `"Hello from a new project`" << std::endl;`n    return 0;`n}`n"
            Put "$t\.gitignore" "main.exe`n*.o`n"
        }
        'latex' {
            Put "$Dir\scratch\hello.tex" "\documentclass{article}`n\usepackage{amsmath}`n`n\begin{document}`nHello from \LaTeX: `$e^{i\pi} + 1 = 0`$.`n\end{document}`n"
            Put "$t\main.tex" @'
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
'@
            Put "$t\.gitignore" "*.aux`n*.fdb_latexmk`n*.fls`n*.log`n*.out`n*.synctex.gz`n*.toc`n"
        }
        'bash' {
            Put "$Dir\scratch\hello.sh" "#!/usr/bin/env bash`nset -euo pipefail`n`necho `"Hello from Bash `$BASH_VERSION`"`n"
            Put "$t\main.sh" "#!/usr/bin/env bash`nset -euo pipefail`n`necho `"Hello from a new project`"`n"
        }
        'rust' {
            # One Cargo workspace for the folder: rust-analyzer ignores .rs files outside a Cargo project.
            Put "$Dir\Cargo.toml" "[workspace]`nmembers = [`"scratch`"]`nresolver = `"3`"`n"
            Put "$Dir\scratch\Cargo.toml" "[package]`nname = `"scratch`"`nversion = `"0.1.0`"`nedition = `"2024`"`n"
            Put "$Dir\scratch\src\bin\hello.rs" "fn main() {`n    println!(`"Hello from Rust`");`n}`n"
        }
    }
}

function Tasks-Json([string]$Key) {
    $main = Main-File $Key
    if ($Key -eq 'rust') { $new = 'cargo new --vcs none $p; if ($LASTEXITCODE -ne 0) { exit 1 }' }
    else { $new = "Copy-Item -LiteralPath 'templates/basic' -Destination `$p -Recurse; if (-not `$?) { exit 1 }" }
    $tasks = @()
    if ($Key -eq 'cpp') {
        $tasks += [ordered]@{ label = 'Build current file'; type = 'process'; command = 'g++'
            args = @('-g', '-std=c++23', '${file}', '-o', '${fileDirname}\${fileBasenameNoExtension}.exe'); group = @{ kind = 'build'; isDefault = $true }; problemMatcher = @() }
    }
    if ($Key -eq 'rust') {
        $tasks += [ordered]@{ label = 'Build current file'; type = 'process'; command = 'rustc'
            args = @('-g', '--edition', '2024', '${file}', '-o', '${fileDirname}\${fileBasenameNoExtension}.exe'); group = @{ kind = 'build'; isDefault = $true }; problemMatcher = @() }
    }
    $tasks += [ordered]@{
        label = 'New project'; type = 'process'; command = 'powershell.exe'
        # No double quotes in here: they don't survive the way VS Code passes this to PowerShell.
        args = @('-NoProfile', '-Command', ('$n = $env:PROJECT_NAME; if (-not $n -or $n.StartsWith(''.'') -or $n -match ''[/\\:]'') { Write-Host ''Use a plain name: no / or \ or : and no dot at the start.''; exit 1 }; $p = ''projects/'' + $n; if (Test-Path -LiteralPath $p) { Write-Host ($p + '' already exists''); exit 1 }; @NEW@; git init -q $p; if ($LASTEXITCODE -eq 0 -and (git config user.name) -and (git config user.email)) { git -C $p add -A; git -C $p commit -qm ''New project'' }; code ($p + ''/@MAIN@'')').Replace('@NEW@', $new).Replace('@MAIN@', $main))
        options = @{ cwd = '${workspaceFolder}'; env = @{ PROJECT_NAME = '${input:projectName}' } }; problemMatcher = @()
    }
    $obj = [ordered]@{
        version = '2.0.0'; tasks = $tasks
        inputs  = @(@{ id = 'projectName'; type = 'promptString'; description = 'Name of the new project (folder in projects/)' })
    }
    return ($obj | ConvertTo-Json -Depth 10)
}

function Launch-Json([string]$Key) {  # F5 configuration, $null if none
    switch ($Key) {
        'python' { $c = [ordered]@{ name = 'Debug current file'; type = 'debugpy'; request = 'launch'; program = '${file}'; cwd = '${fileDirname}'; console = 'integratedTerminal' } }
        { $_ -in 'cpp', 'rust' } { $c = [ordered]@{ name = 'Debug current file'; type = 'lldb'; request = 'launch'; program = '${fileDirname}\${fileBasenameNoExtension}.exe'; cwd = '${fileDirname}'; preLaunchTask = 'Build current file' } }
        default { return $null }
    }
    return ([ordered]@{ version = '0.2.0'; configurations = @($c) } | ConvertTo-Json -Depth 10)
}

# --- Install steps --------------------------------------------------------------------------
function Missing-Winget {  # [ordered] id -> scope of the packages that are not installed
    $want = [ordered]@{}
    foreach ($k in $BaseWinget.Keys) { $want[$k] = $BaseWinget[$k] }
    foreach ($key in $Selected) { foreach ($id in $P[$key].Winget) { $want[$id] = 'user' } }
    # shellcheck and WinLibs are portable: winget has no scope for them.
    foreach ($id in 'koalaman.shellcheck', 'BrechtSanders.WinLibs.POSIX.UCRT.LLVM', 'Rustlang.Rustup') { if ($want.Contains($id)) { $want[$id] = '' } }
    # A TeX that already works stays: a second one would only compete with it.
    if ($want.Contains('MiKTeX.MiKTeX') -and -not (Recorded winget MiKTeX.MiKTeX) -and (Get-Command pdflatex -ErrorAction SilentlyContinue)) { [void]$want.Remove('MiKTeX.MiKTeX') }
    # One "winget export" lists every installed program winget knows, with exact ids (fast; "list" per id is not).
    $tmp = Join-Path $script:Tmp 'installed.json'
    if (Test-Path $tmp) { Remove-Item $tmp }
    [void](Quiet winget export -o $tmp --source winget --accept-source-agreements --disable-interactivity)
    $have = @()
    if (Test-Path $tmp) { $have = @((Get-Content $tmp -Raw | ConvertFrom-Json).Sources | ForEach-Object { $_.Packages } | ForEach-Object { $_.PackageIdentifier }) }
    $missing = [ordered]@{}
    foreach ($id in $want.Keys) { if ($have -notcontains $id) { $missing[$id] = $want[$id] } }
    return $missing
}

function Recover-ProgramRecords {
    # A run killed between installing and noting it: the program is there, its entries aren't recorded.
    foreach ($id in Manifest-Lines winget) {
        if ($Missing.Contains($id)) { continue }
        $kind = 'program'; if ($id -eq 'Microsoft.VisualStudioCode') { $kind = 'program-vscode' }
        if (-not (@(Manifest-Lines $kind) | Where-Object { $_.StartsWith("$id`t") })) {
            foreach ($n in Program-Names) { if ($n -match $ProgramPattern[$id]) { Record $kind $id $n } }
        }
    }
}

function Install-Programs([string[]]$Ids) {
    foreach ($id in $Ids) {
        if (-not $Missing.Contains($id)) { continue }
        Step "Installing $id"
        $before = Program-Names
        $cache = "$env:LOCALAPPDATA\Package Cache"   # installers keep copies there (Python's launcher.msi)
        $cacheBefore = @(Get-ChildItem $cache -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        Winget-Install $id $Missing[$id]
        foreach ($c in @(Get-ChildItem $cache -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })) {
            if ($cacheBefore -notcontains $c -and -not (Recorded created $c)) { Record created $c }
        }
        $kind = 'program'; if ($id -eq 'Microsoft.VisualStudioCode') { $kind = 'program-vscode' }
        foreach ($n in Program-Names) {
            if ($before -notcontains $n -and $n -match $ProgramPattern[$id] -and -not (Recorded $kind $id $n)) { Record $kind $id $n }
        }
    }
    Refresh-Path
}

function Backup-VSCode {  # once, on the first run: only a VS Code setup from before this script is backed up
    if ((Manifest-Lines backup).Count) { return }
    if (-not (Test-Path $VscUser)) { Record backup none; return }
    Step 'Backing up your VS Code settings'
    $file = Join-Path $SM "backup\vscode-before-setup-$Today.zip"
    New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
    $items = @('settings.json', 'keybindings.json', 'snippets', 'profiles', 'globalStorage\storage.json') |
        ForEach-Object { Join-Path $VscUser $_ } | Where-Object { Test-Path $_ }
    if ($items) { Compress-Archive -Path $items -DestinationPath $file -Force }
    Record backup $file
}

# Folders created in the home folder, noted if missing before the first run. VS Code's own (settings,
# extensions) are removed only together with VS Code; the tools' caches are a separate, unticked item.
function Note-New-Home-Dirs {
    foreach ($d in @("$env:USERPROFILE\.vscode", "$env:USERPROFILE\.vscode-shared", $VscDir, "$env:USERPROFILE\.dotnet")) {
        if (-not (Test-Path $d) -and -not (Recorded created-vscode $d)) { Record created-vscode $d }
    }
    $caches = @("$env:USERPROFILE\.ipython", "$env:LOCALAPPDATA\pip", "$env:LOCALAPPDATA\matplotlib", "$env:APPDATA\jupyter")
    if ($Missing.Contains('MiKTeX.MiKTeX')) { $caches += @("$env:LOCALAPPDATA\MiKTeX", "$env:APPDATA\MiKTeX", "$env:USERPROFILE\miktex-console.lock") }
    foreach ($d in $caches) {
        if (-not (Test-Path $d) -and -not (Recorded created $d)) { Record created $d }
    }
    foreach ($d in @("$env:USERPROFILE\.claude", $Skills)) {   # ~\.claude also holds the Claude login
        if (-not (Test-Path $d) -and -not (Recorded emptydir $d)) { Record emptydir $d }
    }
    # Shared folders other programs use too: removed only if empty after the uninstall.
    foreach ($d in @("$env:LOCALAPPDATA\Programs", "$env:LOCALAPPDATA\Package Cache")) {
        if (-not (Test-Path $d) -and -not (Recorded emptydir $d)) { Record emptydir $d }
    }
    if ($Selected -contains 'rust') {  # before the Rustup installer creates them
        foreach ($d in @("$env:USERPROFILE\.rustup", "$env:USERPROFILE\.cargo")) {
            if (-not (Test-Path $d) -and -not (Recorded homedir $d)) { Record homedir $d }
        }
    }
}

function Setup-Rust {
    if ($Selected -notcontains 'rust') { return }
    # Only a Rust this setup installed: an existing one (e.g. MSVC with Visual Studio) stays as it is.
    if (-not ($Missing.Contains('Rustlang.Rustup') -or (Recorded winget Rustlang.Rustup))) { return }
    $rustup = "$env:USERPROFILE\.cargo\bin\rustup.exe"
    if (-not (Test-Path $rustup)) {
        if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) { return }   # its install failed; reported at the end
        $rustup = 'rustup'
    }
    # The Rustup installer sets up the MSVC toolchain, which can't link without Visual Studio.
    if ((Capture $rustup show active-toolchain) -match 'windows-gnu') { return }
    Step 'Rust toolchain (rustup stable, GNU)'
    # GNU target: links with its own bundled MinGW, so no multi-GB Visual Studio Build Tools.
    [void](Quiet $rustup set default-host x86_64-pc-windows-gnu)
    [void](Quiet $rustup set profile minimal)
    foreach ($a in @(@('default', 'stable-x86_64-pc-windows-gnu'), @('component', 'add', 'rust-src', 'clippy', 'rustfmt'))) {
        $ok = $false
        for ($i = 0; $i -lt 3 -and -not $ok; $i++) { $ok = ((Quiet $rustup @a) -eq 0) }
        if (-not $ok) { Fail 'Downloading the Rust toolchain failed three times. Check the internet connection and start the setup again.' }
    }
    [void](Quiet $rustup toolchain uninstall stable-x86_64-pc-windows-msvc)
}

function Setup-MiKTeX {
    if ($Selected -notcontains 'latex') { return }
    if (-not ($Missing.Contains('MiKTeX.MiKTeX') -or (Recorded winget MiKTeX.MiKTeX))) { return }   # an existing MiKTeX keeps its settings
    $initexmf = @("$env:LOCALAPPDATA\Programs\MiKTeX\miktex\bin\x64\initexmf.exe", "$env:ProgramFiles\MiKTeX\miktex\bin\x64\initexmf.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $initexmf) { return }
    # Install missing LaTeX packages on first use without asking.
    [void](Quiet $initexmf '--set-config-value=[MPM]AutoInstall=1')
    # Otherwise every build warns "you have not checked for MiKTeX updates".
    [void](Quiet (Join-Path (Split-Path $initexmf) 'miktex.exe') packages check-update)
}

function Setup-PythonEnv {
    if ($Selected -notcontains 'python') { return }
    $pkgs = $PyPackages
    Step "Python environment (Workspace\.venv: $($pkgs.Replace(' ', ', ')))"
    $vpy = Join-Path $Venv 'Scripts\python.exe'
    if (-not (Test-Path $vpy)) {
        if ((Quiet $script:Python -m venv $Venv) -ne 0) { Fail "Creating the Python environment failed. Details: $(Show $script:Log)" }
        if (-not (Recorded venv $Venv)) { Record venv $Venv }
    }
    # Only an environment inside the workspace folder is found at once: without this link the notebook
    # kernel picker doesn't list .venv on the first open and offers the system Python, without ipykernel.
    # A junction: links proper need administrator rights. Get-Item, because Test-Path says no to a dead link.
    $link = Join-Path $WS 'python\.venv'
    if (-not (Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue)) {
        [void](New-Item -ItemType Junction -Path $link -Value $Venv)
        Record file $link
    }
    $code = Quiet $vpy -m pip install --disable-pip-version-check @($pkgs -split ' ')
    if ($code -ne 0) { Fail 'Installing Python packages failed. Check the internet connection and start the setup again.' }
    if (-not (Test-Path $KernelDir)) {
        [void](Quiet $vpy -m ipykernel install --user --name workspace-venv --display-name 'Python (Workspace)')
        if (-not (Recorded kernel $KernelDir)) { Record kernel $KernelDir }
    }
}

function Make-Workspace([string]$Key) {
    $dir = Join-Path $WS $Key
    Step "Workspace $($P[$Key].Name)"
    Mkd "$dir\scratch" "$dir\projects" "$dir\templates\basic"
    Put "$dir\$Key.code-workspace" "{`n    `"folders`": [`n        { `"path`": `".`" }`n    ]`n}`n"
    $rules = $LangRules[$Key]
    if ($script:GitBash) { $rules = $rules.Replace('C:\Program Files\Git\bin\bash.exe', $script:GitBash) }
    Put "$dir\CLAUDE.md" $rules
    Put "$dir\.vscode\tasks.json" (Tasks-Json $Key)
    $launch = Launch-Json $Key
    if ($launch) { Put "$dir\.vscode\launch.json" $launch }
    if ($Key -eq 'python') {
        Put "$dir\.vscode\settings.json" (([ordered]@{ 'python.defaultInterpreterPath' = (Join-Path $Venv 'Scripts\python.exe'); 'files.exclude' = @{ '.venv' = $true } }) | ConvertTo-Json)
    }
    Write-Examples $Key $dir
}

function Make-SetupManager {
    Step 'Setup Manager'
    Mkd "$SM\scripts" "$SM\logs"
    $bash = 'C:\Program Files\Git\bin\bash.exe'
    Put "$WS\CLAUDE.md" $(if ($script:GitBash) { $BaseRules.Replace($bash, $script:GitBash) } else { $BaseRules })
    Put "$SM\CLAUDE.md" $SetupManagerRules
    $ws = [ordered]@{ folders = @(
        [ordered]@{ path = '.'; name = 'setup_manager' },
        [ordered]@{ path = '..'; name = 'Workspace' },
        [ordered]@{ path = $VscUser; name = 'VS Code settings and profiles' }) }
    Put "$SM\setup.code-workspace" ($ws | ConvertTo-Json -Depth 5)
    $dest = "$SM\scripts\setup-workspace.ps1"
    if ($Self -and $Self -ne $dest) {
        Copy-Item $Self $dest -Force
        if (-not (Recorded file $dest)) { Record file $dest }
    }
    Put "$SM\logs\setup_log.txt" "SETUP LOG - every change to the setup, newest at the bottom.`nFormat: [YYYY-MM-DD] Title, then `"- `" bullets: what changed and why.`n"
}

function Install-Extensions([string]$ProfileName, [string[]]$Exts) {
    $a = @('--profile', $ProfileName); foreach ($e in $Exts) { $a += @('--install-extension', $e) }
    [void](Quiet $script:Code @a)
    $have = @(Capture $script:Code --list-extensions --profile $ProfileName | ForEach-Object { "$_".ToLower() })
    $missing = @($Exts | Where-Object { $have -notcontains $_.ToLower() })
    if ($missing.Count) {  # one retry: most failures are a network hiccup
        $a = @('--profile', $ProfileName); foreach ($e in $missing) { $a += @('--install-extension', $e) }
        [void](Quiet $script:Code @a)
        $have = @(Capture $script:Code --list-extensions --profile $ProfileName | ForEach-Object { "$_".ToLower() })
        foreach ($e in $missing) { if ($have -notcontains $e.ToLower()) { $script:Failed += "${ProfileName}: $e" } }
    }
}

function Setup-Profile([string]$Key, [string]$Name, [string]$Icon, [string]$Rgb, [string]$Exts, [hashtable]$Extra) {
    Step "VS Code profile $Name"
    $line = @(Manifest-Lines profile | Where-Object { $_.StartsWith("$Key`t") })
    $location = $null; $new = $false
    if ($line.Count) {
        $f = $line[0] -split "`t"; $Name = $f[1]; $location = $f[2]
        # Found by its folder, not its name: the user may have renamed it in VS Code.
        $current = Py name-of $Storage $location
        if (-not $current) { Unrecord profile $Key $Name $location; $location = $null }   # deleted in VS Code meanwhile
        elseif ($current -ne $Name) { Unrecord profile $Key $Name $location; $Name = $current; Record profile $Key $Name $location }
    }
    if (-not $location) {
        $Name = Py free-name $Storage $Name
        $location = Py add-profile $Storage $Name $Icon
        Record profile $Key $Name $location
        $new = $true
    }
    # VS Code's own profile creation makes this folder; without it the profile can't save its state.
    New-Item -ItemType Directory -Force (Join-Path $VscUser "profiles\$location\globalStorage") | Out-Null
    $file = Join-Path $VscUser "profiles\$location\settings.json"
    $tmp = Join-Path $script:Tmp 'settings.json'
    $bypassKeys = [ordered]@{ 'claudeCode.allowDangerouslySkipPermissions' = $true; 'claudeCode.initialPermissionMode' = 'bypassPermissions' }
    $msg = ''
    if ($new -or -not (Test-Path $file)) {
        # Only for a new profile: a rerun must not bring back settings the user removed.
        $s = [ordered]@{
            'files.eol' = "`n"; 'files.insertFinalNewline' = $true; 'chat.disableAIFeatures' = $true
            'terminal.integrated.defaultProfile.windows' = 'PowerShell'
            'code-runner.runInTerminal' = $true; 'code-runner.saveFileBeforeRun' = $true
            'code-runner.fileDirectoryAsCwd' = $true; 'code-runner.ignoreSelection' = $true
            'code-runner.respectShebang' = $false  # "#!/usr/bin/env bash" doesn't exist on Windows; use the executor map
        }
        $runner = [ordered]@{ python = '& "$pythonPath" -u $fullFileName' }
        if ($script:GitBash) { $runner.shellscript = "& '$($script:GitBash)'" }
        if ($Key -eq 'cpp') { $runner.cpp = 'cd $dir && g++ -std=c++23 $fileName -o $fileNameWithoutExt && $dir$fileNameWithoutExt' }
        if ($Key -eq 'rust') { $runner.rust = 'cd $dir && rustc --edition 2024 $fileName && $dir$fileNameWithoutExt' }
        $s['code-runner.executorMap'] = $runner
        foreach ($k in $Extra.Keys) { $s[$k] = $Extra[$k] }
        if ($Key -eq 'python') {
            # The terminal gets the Python environment through its variables. The extensions' own way is
            # unusable on a first start: they type the activation into the terminal, which cuts off or feeds
            # a running program, warn about an "invalid interpreter", and Activate.ps1 is blocked by the
            # execution policy on a normal Windows anyway.
            $s['python.useEnvironmentsExtension'] = $false
            $s['python.terminal.activateEnvironment'] = $false
            $s['python-envs.terminal.autoActivationType'] = 'off'
            $s['terminal.integrated.env.windows'] = [ordered]@{ VIRTUAL_ENV = $Venv; Path = (Join-Path $Venv 'Scripts') + ';${env:Path}' }
        }
        if ($Bypass) { foreach ($k in $bypassKeys.Keys) { $s[$k] = $bypassKeys[$k] } }
        Write-Text $tmp ($s | ConvertTo-Json -Depth 10)
        $msg = Py settings $file $Rgb $tmp
    } elseif ($BypassChanged) {
        if ($Bypass) { Write-Text $tmp ($bypassKeys | ConvertTo-Json); $msg = Py set-keys $file $tmp }
        else { $msg = Py del-keys $file claudeCode.allowDangerouslySkipPermissions claudeCode.initialPermissionMode }
    }
    if ($msg) { $script:Notes += "Profile ${Name}: its settings.json has comments, so the setup left it unchanged" }
    Install-Extensions $Name (@($BaseExtensions -split ' ') + @($Exts -split ' ' | Where-Object { $_ }))
}

# A failed language must not take the rest down: Setup Manager's Claude can fix it afterwards.
function Contained([string]$Key, [scriptblock]$Work) {
    $script:Containing = $true; $script:Reason = ''
    try { & $Work }
    catch {
        $why = $script:Reason
        if (-not $why) { $why = "stopped during: $($script:CurrentStep) (line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message))" }
        $script:LangFailed[$Key] = $why
        Say "error: $why"
    } finally { $script:Containing = $false }
}
function Language-Tools([string]$Key) {
    foreach ($id in $P[$Key].Winget) { if ($script:Unavailable -contains $id) { Fail "winget can't find $id." } }
    Install-Programs $P[$Key].Winget
    if ($Key -eq 'rust') { Setup-Rust }
    if ($Key -eq 'latex') { Setup-MiKTeX }
    Make-Workspace $Key
    if ($Key -eq 'python') { Setup-PythonEnv }
}
function Install-Language([string]$Key) {
    Contained $Key { Language-Tools $Key }
    if ($script:LangFailed.ContainsKey($Key)) { return }
    Close-VSCode   # again: someone may have opened it during the downloads
    Contained $Key { Setup-Profile $Key $P[$Key].Name $P[$Key].Icon $P[$Key].Rgb $P[$Key].Ext $P[$Key].Set }
}

# Does each language really work? Everything happens in a temporary folder; the workspaces stay untouched.
$script:CheckOk = @(); $script:CheckBad = @()
function Check-Lang([string]$Key, [string]$T) {  # $true = works
    Push-Location $T
    try {
        switch ($Key) {
            'python' { return ((Quiet (Join-Path $Venv 'Scripts\python.exe') -c 'import numpy, pandas, matplotlib, ipykernel') -eq 0) }
            'cpp' {
                [IO.File]::WriteAllText("$T\hello.cpp", "#include <iostream>`n#include <ranges>`nint main() { for (int i : std::views::iota(0, 1)) std::cout << i; }`n")
                if ((Quiet g++ -std=c++23 hello.cpp -o hello.exe) -ne 0) { return $false }
                if ((Quiet "$T\hello.exe") -ne 0) { return $false }
                return ((Quiet clangd --version) -eq 0)
            }
            'latex' {
                [IO.File]::WriteAllText("$T\hello.tex", "\documentclass{article}`n\usepackage[T1]{fontenc}`n\usepackage{lmodern}`n\usepackage{amsmath,amssymb}`n\usepackage{graphicx}`n\usepackage{hyperref}`n\begin{document}`nHello.`n\end{document}`n")
                [void](Quiet pdflatex -interaction=nonstopmode hello.tex)
                return (Test-Path "$T\hello.pdf")
            }
            'bash' {
                [IO.File]::WriteAllText("$T\hello.sh", "#!/usr/bin/env bash`necho hello`n")
                if (-not $script:GitBash) { return $false }
                if ((Quiet shellcheck hello.sh) -ne 0) { return $false }
                return ((Quiet $script:GitBash hello.sh) -eq 0)
            }
            'rust' {
                if ((Quiet cargo new --vcs none hello) -ne 0) { return $false }
                Push-Location "$T\hello"
                try { if ((Quiet cargo run -q) -ne 0) { return $false } } finally { Pop-Location }
                # The workspace folder too: a deleted project still listed in Cargo.toml stops cargo there.
                Push-Location "$WS\rust"
                try { return ((Quiet cargo metadata -q --no-deps --format-version 1) -eq 0) } finally { Pop-Location }
            }
        }
    } catch { return $false } finally { Pop-Location }
    return $false
}
function Run-Checks([bool]$Extensions) {
    Step 'Checking that everything works'
    Refresh-Path
    $envs = (Join-Path $env:USERPROFILE '.cargo\bin')
    if ($env:Path -notlike "*$envs*") { $env:Path += ";$envs" }
    foreach ($k in $Selected) {
        if ($script:LangFailed.ContainsKey($k)) {
            $script:CheckBad += "$($P[$k].Name): $($script:LangFailed[$k])"
            Say "  $($P[$k].Name): DOES NOT WORK"
            continue
        }
        $t = Join-Path $script:Tmp "check-$k"
        New-Item -ItemType Directory -Force $t | Out-Null
        if (Check-Lang $k $t) { $script:CheckOk += $P[$k].Name; Say "  $($P[$k].Name): works" }
        else { $script:CheckBad += "$($P[$k].Name): it did not run"; Say "  $($P[$k].Name): DOES NOT WORK" }
    }
    if (-not $Extensions) { return }
    foreach ($l in Manifest-Lines profile) {
        $f = $l -split "`t"
        $have = @(Capture $script:Code --list-extensions --profile $f[1] | ForEach-Object { "$_".ToLower() })
        $want = @($BaseExtensions -split ' ')
        if ($P.ContainsKey($f[0])) { $want += @($P[$f[0]].Ext -split ' ') }
        $miss = @($want | Where-Object { $have -notcontains $_.ToLower() })
        if ($miss.Count) { $script:CheckBad += "Profile $($f[1]): extensions missing: $($miss -join ' ')"; Say "  Profile $($f[1]): extensions missing: $($miss -join ' ')" }
    }
}
function Check-Only {
    if (-not (Test-Path $Manifest)) { Fail "Nothing to check: $(Show $Manifest) not found." }
    $script:Selected = @(Manifest-Lines profile | ForEach-Object { ($_ -split "`t")[0] } | ForEach-Object { if ($_ -eq 'jupyter') { 'python' } else { $_ } } | Select-Object -Unique | Where-Object { $P.ContainsKey($_) })
    $script:Code = Find-Code
    if (-not $script:Code) { Fail 'VS Code was not found.' }
    $script:GitBash = Find-GitBash
    $script:Log = "$SM\logs\check-$(Get-Date -Format yyyy-MM-dd_HHmm).log"
    Write-Text $script:Log ''
    Run-Checks $true
    if ($script:CheckBad.Count) {
        Info "The check found problems:`n - $($script:CheckBad -join "`n - ")`n`nRunning the setup again repairs what it can. Details: $($script:Log)"
        exit 1
    }
    Info "Everything works: $($script:CheckOk -join ', '), and all the extensions are there."
}

function Make-Launcher {
    Step 'Launcher'
    Put "$Root\launcher.ps1" @'
# Pick a workspace; VS Code opens it with its own profile.
# The entries are the profiles listed in Workspace\setup_manager\installed.txt.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$ws = Join-Path $PSScriptRoot 'Workspace'
$entries = [ordered]@{}
$rows = Get-Content (Join-Path $ws 'setup_manager\installed.txt') -Encoding UTF8 | Where-Object { $_.StartsWith("profile`t") } |
    ForEach-Object { $f = $_ -split "`t"; [pscustomobject]@{ Key = $f[1]; Name = $f[2] } }
foreach ($r in @($rows | Where-Object Key -eq 'setup_manager') + @($rows | Where-Object Key -ne 'setup_manager' | Sort-Object Name)) {
    if ($r.Key -eq 'setup_manager') { $entries[$r.Name] = Join-Path $ws 'setup_manager\setup.code-workspace' }
    else { $entries[$r.Name] = Join-Path $ws "$($r.Key)\$($r.Key).code-workspace" }
}
$f = New-Object Windows.Forms.Form
$f.Text = 'VS Launcher'; $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
$f.Font = New-Object Drawing.Font('Segoe UI', 11); $f.TopMost = $true
$f.ClientSize = New-Object Drawing.Size(300, (32 * $entries.Count + 20))
$l = New-Object Windows.Forms.ListBox; $l.IntegralHeight = $false; $l.SetBounds(10, 10, 280, 32 * $entries.Count)
foreach ($k in $entries.Keys) { [void]$l.Items.Add($k) }
$l.SelectedIndex = 0
$open = { if ($l.SelectedItem) { $f.Tag = $l.SelectedItem; $f.Close() } }
$l.Add_DoubleClick($open); $l.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Enter') { & $open } elseif ($e.KeyCode -eq 'Escape') { $f.Close() } })
$f.Controls.Add($l)
$f.ActiveControl = $l
$f.Add_Shown({ $this.Activate(); $l.Focus() })
[void]$f.ShowDialog()
if (-not $f.Tag) { exit 0 }
$code = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe", "$env:ProgramFiles\Microsoft VS Code\Code.exe", '@CODEEXE@') | Where-Object { Test-Path $_ } | Select-Object -First 1
try { Start-Process -FilePath $code -ArgumentList @('--profile', "`"$($f.Tag)`"", "`"$($entries[$f.Tag])`"") }
catch { [void][Windows.Forms.MessageBox]::Show("VS Code could not be started:`n$($_.Exception.Message)", 'VS Launcher', 'OK', 'Error') }
'@
    if (-not (Test-Path $MenuFile)) {
        $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($MenuFile)
        $sh.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $sh.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Root\launcher.ps1`""
        $codeExe = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe", "$env:ProgramFiles\Microsoft VS Code\Code.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($codeExe) { $sh.IconLocation = "$codeExe,0" }
        $sh.Description = 'Open a VS Code workspace with its own profile'
        $sh.Save()
        Record file $MenuFile
    }
}

function Setup-Skills {
    Step 'Claude Code skills /log, /distill and /test-setup'
    if (-not (Test-Path "$Skills\log\SKILL.md")) {
        Put "$Skills\log\SKILL.md" @'
---
name: log
description: Append a friction/feedback note to the current workspace's issue journal. Use when the user invokes /log with a message - capture in-the-moment annoyances, observations or improvement ideas without breaking the conversation flow. The journal lives at <workspace>/.claude/friction.md and is distilled later via /distill.
---
<!-- installed by setup-workspace.sh -->

# /log - append to the workspace issue journal

When the user types `/log <message>`, append the message to the current workspace's journal. Capture it verbatim; do not interpret, paraphrase or sanitize it. Then reply with one short confirmation line and continue the conversation unchanged.

## Steps

1. **Find the workspace root:** walk up from the current directory to the first folder that contains a `.code-workspace` file, a `.git` directory or a `.claude` directory. If there is none inside `@ROOT@\Workspace\`, use the current directory.
2. **Context:** one short, factual sentence on what was happening just before `/log`.
3. If `<workspace>/.claude/friction.md` is missing, create it with the header `# Issue journal - <workspace name>` and the line `Append-only. Distilled into CLAUDE.md via /distill.`
4. **Append**, followed by a blank line:
   ```markdown
   ## YYYY-MM-DD HH:MM - <workspace name>
   **Context**: <one sentence>
   **Issue**: <the user's message, verbatim>
   ```
5. **Confirm in one line**, e.g. `Logged to python/.claude/friction.md.`, then resume what was in progress.

## Don't

- Paraphrase the message: the raw words are the data.
- Try to fix the issue now, ask follow-up questions or discuss it. Capture only.
- `/log` without a message: ask "What should I log?".
'@
        Record skill "$Skills\log"
    }
    if (-not (Test-Path "$Skills\distill\SKILL.md")) {
        Put "$Skills\distill\SKILL.md" @'
---
name: distill
description: Review the current workspace's issue journal (.claude/friction.md, filled by /log) and propose rules for its CLAUDE.md. Use when the user invokes /distill. Groups similar entries, drafts short rules, waits for approval, applies the approved ones and archives processed entries.
---
<!-- installed by setup-workspace.sh -->

# /distill - turn the issue journal into rules

Turns raw `/log` notes into a few durable rules. Nothing changes before the user approves.

## Steps

1. **Find the workspace root** as `/log` does.
2. **Read `<workspace>/.claude/friction.md`.** No entries: say there is nothing to distill and stop.
3. **Read the existing rules:** `<workspace>/CLAUDE.md` and the shared `@ROOT@\Workspace\CLAUDE.md`.
4. **Group the entries by theme.** A single entry that isn't a pattern gets no rule.
5. **Draft one rule per theme:** one clear sentence, plus one verbatim quote from the journal as anchor, and where it goes (this workspace's `CLAUDE.md`, or the shared one if the theme recurs across workspaces). Prefer sharpening an existing rule to adding a new one; rules files stay short.
6. **Present all proposals in one response; apply nothing yet.** The user answers e.g. `apply 1, 3`, `apply all`, `skip 2`, or with edits.
7. **Apply the approved rules** with precise edits.
8. **Archive:** move the processed entries verbatim from `friction.md` to `friction.archive.md`.
9. **Log** to `@ROOT@\Workspace\setup_manager\logs\setup_log.txt`: `[YYYY-MM-DD] /distill: <workspace> - N rules, M entries archived`.

## Don't

- Apply rules without explicit approval, or resolve a contradiction with an existing rule yourself.
- Paraphrase or delete journal entries; archive them verbatim.
- Turn an entry about a fact you got wrong into a rule: fix the fact and archive the entry.
'@
        Record skill "$Skills\distill"
    }
    if (-not (Test-Path "$Skills\test-setup\SKILL.md")) {
        Put "$Skills\test-setup\SKILL.md" @'
---
name: test-setup
description: Test the whole setup (toolchains, extensions, settings, logs), ask the person to try a few things, and write a report. Changes nothing. Only when the user types /test-setup.
disable-model-invocation: true
---
<!-- installed by setup-workspace.sh -->

# /test-setup - test this setup (Windows)

You are testing this setup, not repairing it. It takes about 15 minutes, with questions for the
person at the end.
- Change nothing: no settings, profiles, programs, PATH, or files. The exceptions are a temporary folder
  under $env:TEMP, the test project in F (you remove it again), and the report.
- Never run the setup with -Uninstall or -Add. Never run winget install or uninstall.
- When you run the setup script, always add -NoGui. Without it, the script opens windows.
- The commands below are PowerShell. If your shell is Git Bash, wrap them in single quotes, so that bash leaves
  every $ alone: powershell -NoProfile -Command '...'
- Keep going after a failure: record it and continue. Batch commands to save time.
- Write %USERPROFILE% for the user folder. Never copy secrets, tokens, or the Git name or email into the
  report; write "set" or "not set" instead.
- Result words: PASS, FAIL, WARN (works, but something is off), SKIP (not installed or not applicable).
- Don't fix anything. For each FAIL or WARN, add your guess at the cause, and mark it "guess"
  unless you verified it.

Names used below. ROOT is @ROOT@, WS is ROOT\Workspace, and SM is WS\setup_manager.
This test expects to run in Setup Manager, with SM as the current folder. If it doesn't, tell the
person and mark E1 SKIP. The languages are the "profile" lines in SM\installed.txt: tab-separated,
with key, profile name, and folder id. The key setup_manager is not a language.

A. THE INSTALL
A1  Get-FileHash -Algorithm MD5 SM\scripts\setup-workspace.ps1, and its $ScriptVersion line. Record both.
A2  System: Get-CimInstance Win32_OperatingSystem (Caption, Version, OSArchitecture), Get-Culture,
    whether a battery exists (Get-CimInstance Win32_Battery), free space on the system drive,
    winget --version, and $PSVersionTable.PSVersion.
A3  SM\setup.conf as it is. From SM\installed.txt: the profile lines (key and name) and the count of
    lines of each kind.
A4  The install logs, SM\logs\install-*.log. List them with dates. In each, find the lines matching
    "^== |^error|DOES NOT WORK|Stopped at|Setup stopped|Not finished|: works$". Record those lines:
    at most 60 from the newest log and 15 from each older one. PASS if the newest log has no
    error, DOES NOT WORK, or Stopped at.
A5  powershell -NoProfile -ExecutionPolicy Bypass -File "SM\scripts\setup-workspace.ps1" -Check -NoGui
    Record the exit code and the result lines.
A6  The user PATH: [Environment]::GetEnvironmentVariable('Path','User'). Record the entries the setup
    added (WinLibs, shellcheck, cargo, MiKTeX, Python, VS Code). Do they all exist on disk?

B. THE LANGUAGES (SKIP any language that isn't installed; build in the temporary folder)
B1  Python: WS\.venv\Scripts\python.exe --version. Import numpy, pandas, matplotlib and ipykernel in
    one command. Run WS\python\scratch\hello.py with it.
    Run WS\.venv\Scripts\jupyter.exe kernelspec list. Check where the junction WS\python\.venv points:
    (Get-Item WS\python\.venv).Target
B2  C++: g++ --version and clangd --version (first lines), plus (Get-Command g++).Source; it should be
    under WinLibs. Copy WS\cpp\scratch\hello.cpp to the temporary folder, compile it with
    g++ -std=c++23, and run it.
B3  LaTeX: pdflatex --version (first line) and (Get-Command pdflatex).Source. Copy
    WS\latex\scratch\hello.tex to the temporary folder and run pdflatex -interaction=nonstopmode
    hello.tex there. MiKTeX may download packages the first time. PASS if hello.pdf exists.
B4  Bash: the Git Bash path, which is %ProgramFiles%\Git\bin\bash.exe or
    %LOCALAPPDATA%\Programs\Git\bin\bash.exe. Also shellcheck --version. Run shellcheck on
    WS\bash\scratch\hello.sh, then run the script with that Git Bash.
B5  Rust: rustc --version, cargo --version, and rustup show active-toolchain (expected: a windows-gnu
    toolchain). In WS\rust, run: cargo run -q --bin hello, then
    cargo metadata -q --no-deps --format-version 1 | Out-Null

C. VS CODE
C1  code --version (first two lines), and (Get-Command code).Source.
C2  For each profile name in installed.txt, Setup Manager included:
        code --list-extensions --show-versions --profile "<name>"
    The expected list for each profile is $BaseExtensions plus that language's Ext in the table at the
    top of SM\scripts\setup-workspace.ps1. FAIL if any are missing. Record the versions.
C3  For each folder id: %APPDATA%\Code\User\profiles\<id>\settings.json and globalStorage\ exist.
    The Claude bypass keys (claudeCode.allowDangerouslySkipPermissions, claudeCode.initialPermissionMode)
    must be present exactly when BYPASS=1 in setup.conf. In the Python profile,
    terminal.integrated.env.windows must point to WS\.venv.
C4  Trust: is WS listed as trusted in both of these? Key content.trust.model.key, opened read-only with
    WS\.venv\Scripts\python.exe, sqlite3 and a "file:...?mode=ro" URI:
        %APPDATA%\Code\User\globalStorage\state.vscdb
        %USERPROFILE%\.vscode-shared\sharedStorage\state.vscdb
    PASS if WS is in the one under .vscode-shared.
C5  The newest folder in %APPDATA%\Code\logs\: count the lines in the exthost logs that match
    "Cannot find module|failed to activate|Activating extension .* failed". Quote up to 5 different ones.

D. LAUNCHER, SKILLS, GIT
D1  ROOT\launcher.ps1 exists. Does the Start menu entry
    %APPDATA%\Microsoft\Windows\Start Menu\Programs\VS Launcher.lnk exist? Record its target and
    arguments; read them with the WScript.Shell COM object.
D2  %USERPROFILE%\.claude\skills\log\SKILL.md and ...\distill\SKILL.md exist.
D3  git --version. Are user.name and user.email set (yes or no)? WS\CLAUDE.md must contain the line
    about committing exactly when both are set.

E. YOU, CLAUDE, IN THIS SETUP
E1  Before reading any file: which CLAUDE.md files came with your instructions in this session? Name
    them and quote the first heading of each. Then read WS\CLAUDE.md and SM\CLAUDE.md and compare.
    PASS if both were loaded.
E2  Are /log and /distill in your list of available skills?
E3  The Claude Code extension's version (from C2). Your permission mode, if you can tell. Which shell
    your commands run in (Git Bash or PowerShell).

F. NEW PROJECT (only if Python is installed)
F1  In WS\python, take the "New project" task's command from .vscode\tasks.json (powershell.exe with
    -Command) and run it the way VS Code would, with the environment variable PROJECT_NAME=zz-setup-test.
    Remove its final "code ..." call, so no window opens.
    Check: projects\zz-setup-test\ holds main.py and a .git folder. A commit exists exactly when Git's
    name and email are set. Then delete projects\zz-setup-test (this test created it).
F2  The same with PROJECT_NAME=..\zz-escape. It must be refused with exit code 1, and nothing may be
    created outside projects\.

G. ASK THE PERSON (one at a time; record the answer in a few words; "skip" means SKIP)
G1  Start VS Launcher from the Start menu. Does it get keyboard focus? Is Setup Manager on top, with
    every language listed? Does each one open in its own colours?
G2  Python: open scratch\hello.py and click the run button (top right). What is printed? Then set a
    breakpoint and press F5. Does it stop there? Did "An Invalid Python interpreter is selected" appear?
G3  Notebook: open scratch\hello.ipynb and click Run All. Which kernel choices appear? Choose Python
    Environments, then .venv (Recommended). Did a firewall question come up? Does the plot show?
G4  C++ (if installed): run button on hello.cpp, then F5 with a breakpoint.
G5  LaTeX (if installed): open hello.tex, add a space, and save. Does a PDF tab with the formula appear?
    Did MiKTeX ask about installing packages?
G6  Bash and Rust (if installed): the run button on scratch\hello.sh and on scratch\src\bin\hello.rs.
G7  Type in this Claude panel: /log test entry from the test run
    Then you check that SM\.claude\friction.md has that entry.
G8  During this test, did VS Code ask you to approve any command or file change? With bypass mode on,
    it shouldn't have.
G9  The install: how many times did Windows ask for permission (UAC)? The expected answer is once, for
    Git. Did the last window take keyboard input without a click? Was anything confusing, slow, or
    wrong? Think of antivirus messages, popups, and wording. How long did it take?

THE REPORT
Write SM\logs\test-report-<YYYY-MM-DD_HHMM>.txt in this layout:

    TEST REPORT  setup-workspace.ps1 (Windows)
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
'@
        Record skill "$Skills\test-setup"
    }
}

function Write-Conf {  # saved before installing, so a rerun after a failure keeps the choices
    Write-Text $Conf "# Choices of setup-workspace.ps1; reruns read them. Edit only if you know why.`nPROFILES=$($Selected -join ',')`nBYPASS=$([int]$Bypass)`n"
}

function Write-Readme {
    $rows = ''
    foreach ($l in Manifest-Lines profile) {
        $f = $l -split "`t"
        if ($f[0] -eq 'setup_manager') { continue }
        $rows += "| $($f[1]) | ``Workspace\$($f[0])\`` | $(if ($P.ContainsKey($f[0])) { $P[$f[0]].Info }) |`n"
    }
    $pkgs = (Manifest-Lines program).Count
    if ($Bypass) { $claude = 'Bypass mode is on: Claude acts without asking for each step (turn off: Settings > "Claude Code: Initial Permission Mode").' }
    else { $claude = 'Claude asks before each action.' }
    if ((Manifest-Lines backup) -contains 'none') { $backup = ': there were none' } else { $backup = ' are in `backup\`' }
    $scriptPath = "$SM\scripts\setup-workspace.ps1"   # the real path: %USERPROFILE% is not expanded in PowerShell
    Write-Text "$SM\README.md" @"
# Your VS Code setup

Made by ``scripts\setup-workspace.ps1`` $ScriptVersion on $Today. Everything it added is listed in ``installed.txt``.

## Open a workspace

Start **VS Launcher** from the Start menu and pick a workspace. Each one opens with its own colour-coded VS Code profile.

| Profile | Folder | Contents |
|---|---|---|
$rows| Setup Manager | ``Workspace\setup_manager\`` | This setup: sees the whole Workspace folder and VS Code's settings and profiles |

First time:
- **Claude Code**: click the Claude icon (top right of an open file, or the side bar) and sign in once; it needs a paid Claude plan or API account (the free plan doesn't include it). $claude
- The Workspace folder is marked as trusted in VS Code, so run buttons, tasks and the debugger work there.
- C++/Rust: the first F5 downloads the debugger's platform part (about a minute).

## Work

- Try the ``hello`` file in each workspace's ``scratch\`` (Rust: ``scratch\src\bin\hello.rs``): the **run button** (top right) runs the file, **F5** debugs it (Python, C++, Rust), LaTeX builds the PDF on save, Python's ``hello.ipynb`` runs cells.
- F5, the run button and the C++/Rust build task use the current file only. Rust projects with crates: ``cargo run``. C++ with several files: your own build, for example CMake.
- Deleting a Rust project: also remove its line from ``members`` in ``rust\Cargo.toml``, or cargo fails for the whole folder.
- Notebooks: the first time you run a notebook, VS Code asks for a kernel: choose **Python Environments**, then **.venv** (Recommended; ``Workspace\.venv``). It remembers the choice. If Windows then asks whether VS Code may use networks, **Cancel** is fine (the notebook only talks to VS Code on this computer).
- LaTeX: the first build of a document downloads the LaTeX packages it uses (MiKTeX), which takes a moment.
- New project: **Terminal > Run Task > New project**: copies ``templates\basic\`` to ``projects\<name>\`` and starts its version history (git), with a first commit if Git has your name and email. Nothing is uploaded.
- Undo what Claude did: hover over a message in the Claude panel and choose **Rewind code to here**. It covers files Claude edited, not what you changed yourself; git is the long-term history.
- Git commits need your name and email; if you skipped that question: ``git config --global user.name `"Your Name`"``, then the same for ``user.email``.
- A program you built gets quarantined or blocked: that's antivirus or Smart App Control reacting to a new unknown program. Check Windows Security > Protection history.
- Python packages: ``Workspace\.venv\Scripts\python -m pip install <package>``.
- Claude reads ``Workspace\CLAUDE.md`` (shared rules) and the workspace's own ``CLAUDE.md`` (language rules). ``/log <note>`` collects friction, ``/distill`` turns it into rules.

## Change the setup

- Test that everything still works: ``powershell -ExecutionPolicy Bypass -File "$scriptPath" -Check``.
- Check everything in detail: type ``/test-setup`` in Setup Manager's Claude panel. Claude tests the whole setup, asks you to try a few things and writes a report to ``logs\``. It changes nothing.
- Add a language (close VS Code first): ``powershell -ExecutionPolicy Bypass -File "$scriptPath" -Add rust``. Available: $($AllKeys -join ', ').
- Changes are logged in ``logs\setup_log.txt``; each install's details in ``logs\install-*.log``.
- Your VS Code settings from before the setup$backup. The setup never changed them.

## Uninstall

``powershell -ExecutionPolicy Bypass -File "$scriptPath" -Uninstall`` shows everything from ``installed.txt`` and removes what you tick: profiles, Start menu entry, Claude skills, the Python environment, the $pkgs programs it installed (each one separately). Nothing that was there before. Your files stay unless you tick the Workspace folder; removed folders go to ``$(Show $Root)\Trash\``. Claude's login and chat history stay, because they are Claude's own files; ``/logout`` in Claude signs out.
"@
}

function Finish([string]$What) {
    Step 'Finishing'
    Write-Readme
    $names = ($Selected | ForEach-Object { $P[$_].Name }) -join ' '
    $text = "`n[$Today] setup-workspace.ps1: $What`n- Profiles: $names (+ Setup Manager); Claude bypass mode: $(if ($Bypass) { 'on' } else { 'off' })`n- Programs added this run: $($script:NewPkgs); details: logs\$(Split-Path $script:Log -Leaf)`n"
    if ($script:Failed.Count) { $text += "- Extensions NOT installed: $($script:Failed -join ', ')`n" }
    [IO.File]::AppendAllText("$SM\logs\setup_log.txt", $text, $Utf8)
}

# --- Uninstall ------------------------------------------------------------------------------
function Move-ToTrash([string]$Path, [string]$Sub = 'files') {  # moved, never deleted
    if (-not (Test-Path $Path)) { return }
    $dest = Join-Path $Trash $Sub
    New-Item -ItemType Directory -Force $dest | Out-Null
    $target = Join-Path $dest ("$(Split-Path $Path -Leaf)-$(Get-Date -Format HHmmss)")
    if (Test-Path $target) { $target += '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) }   # same name in the same second
    if ([IO.Path]::GetPathRoot($Path) -eq [IO.Path]::GetPathRoot($Trash)) { Move-Item $Path $target }
    else { Copy-Item $Path $target -Recurse -Force; Remove-Item $Path -Recurse -Force }   # Move-Item can't move folders across drives
}

function Remove-ProfileEntry([string]$Location) {  # without Python (already uninstalled) PowerShell's JSON does it
    if ($script:Python) { [void](Py remove-profile $Storage $Location); return }
    if (-not (Test-Path $Storage)) { return }
    $j = Get-Content $Storage -Raw -Encoding UTF8 | ConvertFrom-Json
    $j.userDataProfiles = @($j.userDataProfiles | Where-Object { $_.location -ne $Location })
    if ($j.profileAssociations) {
        foreach ($g in $j.profileAssociations.PSObject.Properties) {
            if ($g.Value -is [pscustomobject]) {
                foreach ($k in @($g.Value.PSObject.Properties | Where-Object { $_.Value -eq $Location })) { $g.Value.PSObject.Properties.Remove($k.Name) }
            }
        }
    }
    Write-Text $Storage ($j | ConvertTo-Json -Depth 100)
}

# Uninstallers that would wait for a click: MiKTeX's uninstall entry only opens MiKTeX Console, and
# Rustup's may ask y/N. Their own command-line removal instead, then what they leave goes to the Trash.
function Uninstall-Special([string]$Id) {
    switch ($Id) {
        'MiKTeX.MiKTeX' {
            $dir = "$env:LOCALAPPDATA\Programs\MiKTeX"
            $setup = Join-Path $dir 'miktex\bin\x64\miktexsetup.exe'
            Get-Process miktex-console -ErrorAction SilentlyContinue | Stop-Process -Force
            if (Test-Path $setup) { [void](Quiet $setup --quiet --shared=no uninstall) }
            Move-ToTrash $dir miktex
            Move-ToTrash "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\MiKTeX" miktex
            return $true
        }
        'Rustlang.Rustup' {
            $rustup = "$env:USERPROFILE\.cargo\bin\rustup.exe"
            if (Test-Path $rustup) { [void](Quiet $rustup self uninstall -y) }
            return $true
        }
    }
    return $false
}

function Program-Records([string]$Kind) {  # -> objects Id, Name (older records have only the name)
    foreach ($l in Manifest-Lines $Kind) {
        $f = $l -split "`t"
        if ($f.Count -ge 2) { [pscustomobject]@{ Id = $f[0]; Name = $f[1]; Line = $f } } else { [pscustomobject]@{ Id = ''; Name = $f[0]; Line = $f } }
    }
}

function Do-Uninstall {
    if (-not (Test-Path $Manifest)) { Fail "Nothing to uninstall: $(Show $Manifest) not found." }
    Set-Location $env:USERPROFILE   # Windows refuses to move a folder that is the current one
    $script:Log = "$SM\logs\uninstall-$(Get-Date -Format yyyy-MM-dd_HHmm).log"
    Write-Text $script:Log ''
    $script:Python = Find-Python
    $profiles = @(Manifest-Lines profile)
    $programs = @(Program-Records program)
    $created = @(Manifest-Lines created | Where-Object { Test-Path $_ })
    $items = @()
    if ($profiles.Count) { $items += @{ Key = 'profiles'; Checked = $true; Label = 'VS Code profiles: ' + (($profiles | ForEach-Object { ($_ -split "`t")[1] }) -join ', ') } }
    if ((Manifest-Lines file) -contains $MenuFile) { $items += @{ Key = 'menu'; Checked = $true; Label = 'Start menu entry "VS Launcher"' } }
    if ((Manifest-Lines skill).Count) { $items += @{ Key = 'skills'; Checked = $true; Label = 'The Claude Code skills the setup added' } }
    if ((Manifest-Lines trust).Count) { $items += @{ Key = 'trust'; Checked = $true; Label = "VS Code's trust for " + ((Manifest-Lines trust | ForEach-Object { Show $_ }) -join ', ') } }
    if ((Manifest-Lines kernel).Count) { $items += @{ Key = 'kernel'; Checked = $true; Label = 'Jupyter kernel "Python (Workspace)"' } }
    if ((Manifest-Lines venv).Count) { $items += @{ Key = 'venv'; Checked = $true; Label = 'Python environment Workspace\.venv' } }
    # One line per program, so each can be kept.
    foreach ($g in @($programs | Group-Object { if ($_.Id) { $_.Id } else { $_.Name } })) {
        $items += @{ Key = "prog:$($g.Name)"; Checked = $true; Label = 'Program: ' + (($g.Group | ForEach-Object { $_.Name }) -join ', ') }
    }
    if ((Manifest-Lines homedir).Count) { $items += @{ Key = 'rust'; Checked = $true; Label = 'Rust toolchain folders (%USERPROFILE%\.rustup, .cargo)' } }
    if ((Manifest-Lines program-vscode).Count) { $items += @{ Key = 'vscode'; Checked = $false; Label = 'VS Code itself, with its settings and extensions folders (the setup installed it)' } }
    if ($created.Count) { $items += @{ Key = 'created'; Checked = $false; Label = 'Cache folders the tools created: ' + (($created | ForEach-Object { (Show $_) -replace '(Package Cache)\\.*', '$1' } | Select-Object -Unique) -join ', ') } }
    if ((Manifest-Lines gitkey).Count -and (Get-Command git -ErrorAction SilentlyContinue)) { $items += @{ Key = 'gitid'; Checked = $false; Label = 'Your Git name and email (in %USERPROFILE%\.gitconfig)' } }
    $items += @{ Key = 'workspace'; Checked = $false; Label = 'The Workspace folder, including your own files' }

    if ($GUI) {
        $sel = Checklist "Remove what the setup added. Ticked items are removed; nothing that existed before is touched." $items
        if ($null -eq $sel) { exit 0 }
    } else {
        $sel = @()
        Say 'Uninstall: answer y/n for each item (Enter = the default).'
        foreach ($i in $items) {
            $hint = if ($i.Checked) { 'Y/n' } else { 'y/N' }
            $r = Read-Host "  Remove: $($i.Label)? [$hint]"
            if (($r -match '^y') -or ($r -eq '' -and $i.Checked)) { $sel += $i.Key }
        }
    }
    if (-not $sel.Count) { exit 0 }
    if ($sel -contains 'profiles' -or $sel -contains 'trust' -or $sel -contains 'vscode') { Close-VSCode }

    Start-Progress (8 + $programs.Count)
    if ($sel -contains 'profiles') {
        Step 'Removing VS Code profiles'
        foreach ($l in $profiles) {
            $f = $l -split "`t"
            Remove-ProfileEntry $f[2]
            Move-ToTrash (Join-Path $VscUser "profiles\$($f[2])") vscode-profiles
            Unrecord profile $f[0] $f[1] $f[2]
            Say "  removed profile $($f[1])"
        }
    }
    if ($sel -contains 'menu') { Step 'Removing the Start menu entry'; Move-ToTrash $MenuFile menu; Unrecord file $MenuFile }
    if ($sel -contains 'skills') {
        Step 'Removing the Claude Code skills'
        foreach ($s in Manifest-Lines skill) {
            if ((Test-Path "$s\SKILL.md") -and (Select-String -Path "$s\SKILL.md" -SimpleMatch $Marker -Quiet)) { Move-ToTrash $s claude-skills }
            Unrecord skill $s
        }
    }
    if ($sel -contains 'trust') {
        Step "Removing the folders from VS Code's trusted folders"
        if ($script:Python) { foreach ($d in Manifest-Lines trust) { [void](Py untrust $StateDb $d); Unrecord trust $d } }
        else { $script:Failed += "VS Code's trust entries (Python is gone; remove them in VS Code: Manage Workspace Trust)" }
    }
    if ($sel -contains 'kernel') { Step 'Removing the Jupyter kernel'; foreach ($d in Manifest-Lines kernel) { Move-ToTrash $d jupyter-kernel; Unrecord kernel $d } }
    if ($sel -contains 'venv') { Step 'Removing the Python environment'; foreach ($d in Manifest-Lines venv) { Move-ToTrash $d python-env; Unrecord venv $d } }
    # Programs by their winget id: that also finds a Python whose name changed with an update. Before
    # the Rust folders: Rustup's own uninstaller lives in .cargo.
    if ($sel -contains 'gitid') {   # before the programs: Git itself may go with them
        Step 'Removing your Git name and email'
        foreach ($k in Manifest-Lines gitkey) { [void](Quiet git config --global --unset $k); Unrecord gitkey $k }
        if (Test-Path "$WS\CLAUDE.md") {
            $kept = @(Get-Content "$WS\CLAUDE.md" -Encoding UTF8 | Where-Object { $_ -notlike '*Projects with git: commit when a change works*' })
            [IO.File]::WriteAllText("$WS\CLAUDE.md", (($kept -join "`n") + "`n"), $Utf8)
        }
        foreach ($g in Manifest-Lines gitfile) {
            if ((Test-Path $g) -and (Get-Item $g -Force).Length -eq 0) { Move-ToTrash $g home-folders }
            Unrecord gitfile $g
        }
    }
    $remove = @($programs | Where-Object { $sel -contains "prog:$(if ($_.Id) { $_.Id } else { $_.Name })" })
    if ($sel -contains 'vscode') { $remove += @(Program-Records program-vscode) }
    foreach ($g in @($remove | Group-Object { if ($_.Id) { $_.Id } else { $_.Name } })) {
        Step "Uninstalling $($g.Name)"
        $first = $g.Group[0]
        if ($first.Id -and -not (Uninstall-Special $first.Id)) {
            [void](Quiet winget uninstall --id $first.Id -e --silent --disable-interactivity --accept-source-agreements)
        }
        $now = Program-Names
        foreach ($r in $g.Group) {   # what --id didn't cover (Python Launcher) goes by its name
            if ($now -contains $r.Name) { [void](Quiet winget uninstall --name $r.Name --exact --silent --disable-interactivity --accept-source-agreements) }
        }
        $now = Program-Names
        foreach ($r in $g.Group) {
            $kind = if ($r.Id -eq 'Microsoft.VisualStudioCode') { 'program-vscode' } else { 'program' }
            $fields = $r.Line
            if ($now -contains $r.Name) { $script:Failed += $r.Name } else { Unrecord $kind @fields }
        }
        if ($first.Id -and -not (Winget-Installed $first.Id)) {
            Unrecord winget $first.Id
            # winget leaves the PATH entry of a removed portable package (ShellCheck, WinLibs) behind.
            $path = [Environment]::GetEnvironmentVariable('Path', 'User')
            $keep = @($path -split ';' | Where-Object { $_ -and -not (($_ -like "*\WinGet\Packages\$($first.Id)_*" -or $_ -like "$env:LOCALAPPDATA\Programs\WinLibs\*") -and -not (Test-Path $_)) })
            if ($keep.Count -ne @($path -split ';' | Where-Object { $_ }).Count) { [Environment]::SetEnvironmentVariable('Path', ($keep -join ';'), 'User') }
        }
    }
    if ($sel -contains 'rust') { Step 'Removing the Rust toolchain folders'; foreach ($d in Manifest-Lines homedir) { Move-ToTrash $d rust; Unrecord homedir $d } }
    if ($sel -contains 'created') { Step 'Moving the cache folders to the Trash'; foreach ($d in Manifest-Lines created) { Move-ToTrash $d home-folders; Unrecord created $d } }
    if ($sel -contains 'vscode') {
        Step "Moving VS Code's settings and extensions folders to the Trash"
        foreach ($d in Manifest-Lines created-vscode) { Move-ToTrash $d home-folders; Unrecord created-vscode $d }
    }
    foreach ($d in @(Manifest-Lines emptydir | Sort-Object -Descending)) {   # folders the setup created that hold no files now
        if (-not (Test-Path $d)) { Unrecord emptydir $d }
        elseif (-not (Get-ChildItem $d -Recurse -Force -File -ErrorAction SilentlyContinue)) { Remove-Item $d -Recurse -Force; Unrecord emptydir $d }
    }
    [IO.File]::AppendAllText("$SM\logs\setup_log.txt", "`n[$Today] setup-workspace.ps1 -Uninstall`n- Removed: $($sel -join ' ')`n- Moved (not deleted) to $Trash`n", $Utf8)
    if ($sel -contains 'workspace') {
        Step 'Moving the Workspace folder to the Trash'
        $script:Log = $null   # it is inside the folder that moves
        New-Item -ItemType Directory -Force $Trash | Out-Null
        Move-ToTrash $WS .
        if (Test-Path "$Root\launcher.ps1") { Move-ToTrash "$Root\launcher.ps1" . }
    }
    Stop-Progress
    $msg = "Uninstall finished. Removed folders are in $(Show $Trash)."
    if ($script:Failed.Count) { $msg += "`n`nCould not remove (do it in Settings > Apps): $($script:Failed -join ', ')" }
    Info $msg
}

# --- Main -----------------------------------------------------------------------------------
function Normalize([string]$List) {
    # Notebooks used to be a language of their own, "jupyter": they are part of Python now.
    return (($List.ToLower() -replace 'c\+\+', 'cpp' -replace 'jupyter', 'python') -split '[,\s]+' | Where-Object { $_ } | Select-Object -Unique) -join ','
}

# One run at a time: two at once would both create the same profiles.
$script:Mutex = New-Object Threading.Mutex($false, 'Local\setup-workspace')
try {
    try { if (-not $script:Mutex.WaitOne(0)) { Fail 'The setup is already running.' } }
    catch [Threading.AbandonedMutexException] { }   # a run that was killed: the lock is ours now
    New-Item -ItemType Directory -Force $script:Tmp | Out-Null
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { Fail 'This is the Windows version; on Linux use setup-workspace.sh.' }
    Disable-QuickEdit
    Check-Account
    if ($Uninstall) { Do-Uninstall; exit 0 }
    if ($Check) { Check-Only; exit 0 }

    # Earlier choices (rerun from the Setup Manager or with -Add)
    # Installed = has its profile. The saved choices may be from a run that stopped: they only preset the ticks.
    $Installed = Normalize (@(Manifest-Lines profile | ForEach-Object { ($_ -split "`t")[0] } | Where-Object { $_ -ne 'setup_manager' }) -join ',')
    $ChosenBefore = ''
    $Bypass = $null; $PrevBypass = $null
    if ($NoBypass) { $Bypass = $false }
    if (Test-Path $Conf) {
        $c = Get-Content $Conf -Encoding UTF8
        $ChosenBefore = Normalize (($c | Where-Object { $_ -like 'PROFILES=*' }) -replace '^PROFILES=', '')
        $b = ($c | Where-Object { $_ -like 'BYPASS=*' }) -replace '^BYPASS=', ''
        if ($b) { $PrevBypass = ($b -eq '1') }
        if ($null -eq $Bypass) { $Bypass = $PrevBypass }
    }
    $Profiles = Normalize $Profiles
    $Add = Normalize $Add
    if ($Add) { $Profiles = (@($ChosenBefore, $Add) | Where-Object { $_ }) -join ',' }

    if ($GUI -and -not $Add) {
        if ($Profiles) { $preset = ",$Profiles," } elseif ($ChosenBefore) { $preset = ",$ChosenBefore," } else { $preset = ",$DefaultProfiles," }
        $items = foreach ($k in $AllKeys) {
            $note = ''; if (",$Installed," -like "*,$k,*") { $note = ' (installed)' }
            @{ Key = $k; Checked = ($preset -like "*,$k,*" -or ",$Installed," -like "*,$k,*"); Label = "$($P[$k].Name)$note  -  $($P[$k].Info)" }
        }
        $chosen = Checklist "Which languages? Each gets its own VS Code profile, folder and tools.`nClaude Code and a run button come with every one. (Claude Code needs a paid Claude plan or API account.)" $items
        if ($null -eq $chosen) { exit 0 }
        if (-not $chosen.Count -and -not $Installed) { Info 'No language selected, so nothing was installed.'; exit 0 }
        $Profiles = Normalize ((@($Installed) + $chosen | Where-Object { $_ }) -join ',')
        if ($null -eq $Bypass) {
            $o = Checklist "Bypass mode: Claude Code works without asking before each step. Faster, but it can change`nfiles and run commands without asking. Untick to approve each action." @(@{ Key = 'bypass'; Checked = $true; Label = 'Claude Code in bypass mode' })
            if ($null -eq $o) { exit 0 }
            $Bypass = ($o -contains 'bypass')
        }
    }
    if (-not $Profiles) { if ($ChosenBefore) { $Profiles = $ChosenBefore } else { $Profiles = $DefaultProfiles } }
    if ($Installed) { $Profiles = "$Installed,$Profiles" }
    if ($null -eq $Bypass) { $Bypass = $true }
    $BypassChanged = ($null -ne $PrevBypass -and $PrevBypass -ne $Bypass)
    $Selected = @($Profiles -split ',' | Where-Object { $_ } | Select-Object -Unique)
    foreach ($k in $Selected) { if (-not $P.ContainsKey($k)) { Fail "unknown language '$k' (available: $($AllKeys -join ' '))" } }
    if (-not $Selected.Count) { Fail 'no language selected' }

    $script:GitName, $script:GitEmail = Ask-GitIdentity
    Close-VSCode
    Check-Internet
    Ensure-Winget
    Say 'Checking installed programs...'
    $Missing = Missing-Winget
    # Everything findable? Better to find out now than halfway through.
    foreach ($id in @($Missing.Keys)) {
        [void](Capture winget show --id $id -e --source winget --accept-source-agreements --disable-interactivity)
        if ($LASTEXITCODE -ne 0) {
            if ($id -in 'Git.Git', 'Python.Python.3.14', 'Microsoft.VisualStudioCode') { Fail "winget can't find $id, so the setup can't work here. Check for updates to 'App Installer' in the Microsoft Store." }
            $Missing.Remove($id)
            $script:Unavailable += $id
        }
    }
    $names = ($Selected | ForEach-Object { $P[$_].Name }) -join ' '
    $mb = @{ 'Git.Git' = 70; 'Python.Python.3.14' = 35; 'Microsoft.VisualStudioCode' = 120; 'BrechtSanders.WinLibs.POSIX.UCRT.LLVM' = 380; 'MiKTeX.MiKTeX' = 150; 'koalaman.shellcheck' = 5; 'Rustlang.Rustup' = 300 }
    $total = 800; foreach ($id in $Missing.Keys) { $total += $mb[$id] }   # 800: extensions and Python packages
    $need = [math]::Ceiling($total * 4 / 1024) + 1
    foreach ($d in @($env:SystemDrive + '\', $Root) | Select-Object -Unique) {
        if ((Free-GB $d) -lt $need) {
            if (-not (Ask "Only $(Free-GB $d) GB of disk space is free on $([IO.Path]::GetPathRoot($d)); this needs about $need GB.`n`nContinue anyway?" 'Continue')) { exit 0 }
        }
    }
    $summary = "Languages: $names  (+ Setup Manager)`nFolder: $(Show $Root)`n"
    if ($Missing.Count) { $summary += "Programs to install: $($Missing.Keys -join ', ')`n" } else { $summary += "Programs: all present`n" }
    $summary += "Download: about $([math]::Round($total / 1024, 1)) GB, disk: about $need GB`n"
    if ((Test-Path $VscUser) -and -not (Test-Path $Manifest)) { $summary += "VS Code settings: backed up first, and they stay unchanged`n" }
    $summary += "Claude: bypass mode $(if ($Bypass) { 'on' } else { 'off' })`n"
    if ("$script:GitName$script:GitEmail") { $summary += "Git: commits as $(if ($script:GitName) { $script:GitName } else { '(no name)' }) <$(if ($script:GitEmail) { $script:GitEmail } else { 'no email' })>`n" }
    if ($script:Unavailable.Count) { $summary += "winget can't find $($script:Unavailable -join ', '): that language won't work, the others will.`n" }
    if ($Missing.Contains('Git.Git')) { $summary += "Windows will ask for permission once, for Git: click Yes (on a standard account, an administrator's password).`n" }
    try {
        [void][Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
        $cost = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile().GetConnectionCost().NetworkCostType
        if ("$cost" -in 'Fixed', 'Variable') { $summary += "`nThis connection is marked as metered (phone hotspot?)." }
    } catch { }
    try { if ("$((Get-MpComputerStatus).SmartAppControlState)" -eq 'On') { $summary += "`nSmart App Control is on: it may block compilers and the programs you build (C++, Rust)." } } catch { }
    if ((Get-CimInstance Win32_Processor | Select-Object -First 1).Architecture -eq 12 -and ($Selected -contains 'cpp' -or $Selected -contains 'rust')) {
        $summary += "`nARM computer: F5 debugging for C++ and Rust isn't available (no CodeLLDB for it)."
    }
    if (-not (Ask $summary.TrimEnd() 'Install')) { exit 0 }
    Stay-Awake

    # --- Install ---
    New-Item -ItemType Directory -Force "$SM\logs" | Out-Null
    Write-Conf
    $script:Log = "$SM\logs\install-$(Get-Date -Format yyyy-MM-dd_HHmm).log"
    Write-Text $script:Log "setup-workspace.ps1 $ScriptVersion`n"
    if (-not (Test-Path $Manifest)) { Write-Text $Manifest "# Everything setup-workspace.ps1 added (kind<TAB>value). -Uninstall reads this file.`n" }
    Say ''
    Say "Installing. Details appear here and in $($script:Log). Please keep this window open."
    Start-Progress (8 + $Missing.Count + 2 * $Selected.Count)
    $before = (Manifest-Lines winget).Count
    Note-New-Home-Dirs
    Backup-VSCode
    Recover-ProgramRecords
    Install-Programs @($BaseWinget.Keys)
    Set-GitIdentity
    $script:Code = Find-Code
    if (-not $script:Code) { Fail 'VS Code is not available after installing it.' }
    # The Claude extension needs 1.94 or newer; older ones would look like failed downloads.
    $vcv = "$(Capture $script:Code --version | Select-Object -First 1)"
    if ($vcv -match '^(\d+)\.(\d+)' -and ([int]$Matches[1] -eq 1 -and [int]$Matches[2] -lt 94)) {
        Fail "This VS Code is too old ($vcv; the Claude extension needs 1.94 or newer). Update it (Help > Check for Updates), then start the setup again."
    }
    $script:Python = Find-Python
    if (-not $script:Python) { Fail 'Python is not available after installing it.' }
    $script:GitBash = Find-GitBash
    Make-SetupManager
    Add-CommitRule
    Close-VSCode
    Setup-Profile 'setup_manager' $SetupManagerName 'tools' $SetupManagerRgb '' @{}
    # Without this VS Code opens every workspace in Restricted Mode: no run button, tasks, debugger or
    # Claude. Only the Workspace folder: other folders under the root (cloned repos) still ask.
    foreach ($d in @($WS, $VscUser)) {
        if (-not (Recorded trust $d)) { [void](Py trust $StateDb $d); Record trust $d }
    }
    Make-Launcher
    Setup-Skills
    foreach ($k in $Selected) { Install-Language $k }
    $script:NewPkgs = (Manifest-Lines winget).Count - $before
    # A compiler or tool from an older install may come first on the PATH.
    if ($Selected -contains 'cpp') {
        $gpp = Get-Command g++ -ErrorAction SilentlyContinue
        if ($gpp -and $gpp.Source -notlike '*WinLibs*') { $script:Notes += "g++ comes from $($gpp.Source), not from the setup's WinLibs (it is first on the PATH)." }
    }
    Run-Checks $false
    if ($Installed) { Finish 'added/repaired' } else { Finish 'installed' }
    Stop-Progress

    $first = 'VS Code, Claude and Setup Manager are in place.'
    if ($script:CheckOk.Count) { $first = "Done, and tested. Working: $($script:CheckOk -join ', ')." }
    $done = "$first`nStart `"VS Launcher`" from the Start menu and pick a workspace.`n`nFirst time in VS Code:`n - Claude Code: open its panel and sign in once (needs a paid Claude plan or API account)$(if ($Selected -contains 'python') { "`n - Notebooks: the first run asks for a kernel: Python Environments, then .venv (Recommended)" })`n`nMore: $SM\README.md"
    if ($script:Failed.Count) {
        $done = "Not finished. Not installed:`n - $($script:Failed -join "`n - ")`n`nOnce the cause is fixed, run this again; it only adds what is missing:`npowershell -ExecutionPolicy Bypass -File `"$SM\scripts\setup-workspace.ps1`""
    }
    if ($script:CheckBad.Count) {
        $done = "Installed, but these don't work:`n - $($script:CheckBad -join "`n - ")`n`nThe rest of the setup is in place. To fix this, open Setup Manager in VS Launcher and ask Claude: its rules point to the log. Or run this again, it repairs what it can:`npowershell -ExecutionPolicy Bypass -File `"$SM\scripts\setup-workspace.ps1`"`nDetails: $($script:Log)`n`n$done"
    }
    if ($script:Notes.Count) { $done += "`n`nNote:`n - $($script:Notes -join "`n - ")" }
    Info $done
} catch {
    Stop-Progress
    $line = "$($_.InvocationInfo.Line)".Trim(); if ($line.Length -gt 200) { $line = $line.Substring(0, 200) }
    $msg = "Setup stopped during: $($script:CurrentStep)`n$($_.Exception.Message)`nStopped at line $($_.InvocationInfo.ScriptLineNumber): $line$(Net-Hint)"
    if ($script:Log -and (Test-Path $script:Log)) {
        $msg += "`n`nDetails: $script:Log`n`nLast lines:`n" + ((Get-Content $script:Log -Tail 8) -join "`n")
    }
    $msg += "`n`nOnce the cause is fixed, running the script again continues where it stopped."
    Say $msg
    if ($GUI) { [void][Windows.Forms.MessageBox]::Show($msg, 'VS Code setup', 'OK', 'Error') }
    exit 1
} finally {
    if (Test-Path $script:Tmp) { Remove-Item $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue }
    try { $script:Mutex.ReleaseMutex() } catch { }
}
