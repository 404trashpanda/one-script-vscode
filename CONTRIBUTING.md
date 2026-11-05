# Working on the scripts

- Each script stands alone, so that one file is all anyone has to download. A feature goes into all three.
- The order is the design: everything the setup needs first, then each language contained, so that a failed language
  can't take the others down. Setup Manager is where failures get fixed. Prefer carrying on to stopping, and prefer
  removing a minor feature to adding code that can fail.
- `setup-workspace-mac.sh` must run on bash 3.2: no associative arrays, no `mapfile`, no `${x,,}`.
- `setup-workspace.ps1` must run on PowerShell 5.1 and stay pure ASCII, with LF line endings.
- A stand-in with one fixed answer hides a branch: run both answers.
- Test a first open only from a clean install, since VS Code remembers kernels and interpreters.
