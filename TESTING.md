# What has been tested

- **Linux and Windows:** full install, use and uninstall in Ubuntu 26.04 and Windows 11 virtual machines (install and
  uninstall also on Ubuntu 24.04 without a desktop), including no internet, a wrong clock and a failing language. On
  real hardware: one Ubuntu laptop and one Windows 11 laptop (both with Claude Code signed in), and one Linux Mint
  computer.
- **macOS:** only a simulator: the real bash 3.2 with stand-ins for Homebrew, `osascript` and a few others. It checks
  the script's logic, not how macOS behaves. **Never on a real Mac.**

## Not tested

A real Mac, Debian, Windows 10, Windows on ARM, a real proxy or hotel login page.

## Known limitations

- **Linux** without `zenity` (Kubuntu, for example) has no windows: the script asks in the terminal and installs the
  default languages; pick others with `--profiles`.
- **Windows:** Git asks once for administrator permission, also at uninstall. The first notebook run can bring up a
  firewall question; Cancel is fine.
- **Windows:** on one real laptop, Microsoft Defender removed the installers during the first run; the second run
  finished. The script says so when this happens.
- **Windows, harmless:** every LaTeX build prints "major issue: So far, you have not checked for MiKTeX updates", and
  New project prints two Git warnings about line endings.

A `/test-setup` report from a real Mac would help most (see the README, "If something goes wrong").
