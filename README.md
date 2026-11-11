# WinUtil

WinUtil is a Windows PowerShell utility with a WPF interface. It is distributed as a single compiled PowerShell script built from modular source in this repository.

- **Primary target:** Windows 11
- **Windows 10:** best-effort support where possible (Windows 10 reached end of support on October 14, 2025). Items that are not applicable to your Windows version, edition, or build are skipped, hidden/disabled, or reported with an explicit message. Some capabilities are Windows 11-only (for example, Win11 Creator and certain Windows 11-specific tweaks/features). Upstream app/package availability on Windows 10 depends on the publisher and package manager.

## Run

**Stable branch (recommended)**

```powershell
irm https://christitus.com/win | iex
```

**Development branch**

```powershell
irm https://christitus.com/windev | iex
```

### Open an admin terminal

- **Start menu:** Right-click Start → *Windows PowerShell (Admin)* or *Terminal (Admin)*
- **Search:** Press the `Windows` key, type `PowerShell` or `Terminal`, then `Ctrl + Shift + Enter`

WinUtil requires Administrator rights for system-level changes and an internet connection for downloading applications/updates.

## Source, build, and docs

- Source lives under `functions/`, `config/`, `xaml/`, `scripts/`, and `tools/`. `winutil.ps1` is generated build output and is not edited or committed directly.
- Compile/verify locally: `.\Compile.ps1` (and `.\Compile.ps1 -Run` for GUI verification on Windows).
- Project contract and architecture: [`SPEC.md`](SPEC.md). Contribution/process notes: [`AGENTS.md`](AGENTS.md).
- Documentation: [`docs/`](docs/) (Astro + Starlight site) and https://winutil.christitus.com/
