# Neds Personal WinUtils

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![Platform: Windows 11](https://img.shields.io/badge/platform-Windows%2011-0078D6)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)

Install apps, apply Windows tweaks, run fixes, and build a custom Windows 11 ISO from one window.

WinUtil is a PowerShell utility with a WPF interface. Its source is modular and compiles into a single `winutil.ps1`. This repository is a personal copy of [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) with its own branding and changes.

> [!WARNING]
> WinUtil changes system settings, including registry values, services, and installed or removed apps. Not every tweak can be undone. Create a restore point before you apply tweaks (**Tweaks tab → Essential Tweaks → Restore Point - Create**), and read each tweak's description first.

## Features

| Tab | What it does |
| --- | --- |
| **Install** | Install, upgrade, or uninstall curated apps with WinGet or Chocolatey. Search, filter by category, or upgrade everything at once. |
| **Tweaks** | Apply or undo tweaks from the Essential, Customize Preferences, and Advanced (caution) sections. Start from the Standard, Minimal, or Advanced preset, change the DNS provider, or add or remove the Ultimate Performance power plan (not for laptops). |
| **AppX** | Install or remove Windows AppX packages. Removal applies to all users. |
| **Config** | Turn Windows optional features on or off (.NET Framework, Hyper-V, WSL, Windows Sandbox, and more), run fixes such as Network - Reset and WinGet - Reinstall, open legacy Windows panels, or enable an OpenSSH server. |
| **Win11 Creator** | Build a customized Windows 11 ISO from an official Microsoft image. It removes bundled apps, skips hardware checks, sets up a local account, and saves the result as an ISO or writes it to USB. Windows 11 only. |

Also included:

- **Job queue:** an action started while another runs waits its turn. You can reorder or cancel waiting actions.
- **Import and export:** save your selections as JSON and reuse them on other PCs.
- **Environment report:** a JSON summary of your Windows and WinUtil state for bug reports. WinUtil never uploads it.
- **Themes:** Auto, Light, or Dark.

## Requirements

- **Windows 11** is the primary target. **Windows 10** is supported on a best-effort basis: features that don't apply to your version are skipped or reported.
- **PowerShell 5.1** or later.
- **Administrator rights.** If WinUtil starts without them, it relaunches itself elevated after a UAC prompt.
- **Internet access** for app installs and downloads.

## Getting started

This repository has no releases of its own, so build the script from source. Clone it with Git, or download the ZIP from GitHub.

```powershell
git clone https://github.com/norodd93/personal_winutils.git
cd personal_winutils
.\Compile.ps1 -Run
```

`Compile.ps1` builds `winutil.ps1` from the sources. Add `-Run` to launch it right after. Without `-Run`, start it later with `.\winutil.ps1`, and rebuild after you change the sources. If Windows blocks the script, run `powershell -ExecutionPolicy Bypass -File .\Compile.ps1 -Run` instead.

> [!NOTE]
> `irm https://christitus.com/win | iex` runs the upstream project's latest stable release, not this repository's code.

## Automation

`-Preset` and `-Config` apply their selections without opening the window. Give both, and the preset sets a baseline that the config adds to.

```powershell
.\winutil.ps1 -Preset Standard
.\winutil.ps1 -Config "C:\Configs\my-setup.json"
.\winutil.ps1 -Offline
```

- `-Preset` accepts `Minimal`, `Standard`, or `Advanced`. [`config/preset.json`](config/preset.json) lists what each one selects.
- `-Config` takes a file saved with **Export** in the gear menu.
- `-Offline` opens the window with the Install tab disabled, for machines without internet access.

## Troubleshooting

- **Logs:** each session writes a timestamped `winutil_*.log` file to `%LocalAppData%\winutil\logs`.
- **Diagnostics:** click the gear icon and choose **Export Environment Report**, then attach the file to your issue.

## Documentation

- User guides and the code reference live in [`docs/`](docs/), an Astro + Starlight site. Pages are in `docs/src/content/docs/`.
- [`SPEC.md`](SPEC.md) covers the architecture, build model, and configuration rules.
- The hosted site at winutil.christitus.com is the upstream project's. This repository doesn't deploy its own copy.

## Development

```powershell
# Once: install the Pester version the tests use
Install-Module -Name Pester -RequiredVersion 5.8.0 -Repository PSGallery -Scope CurrentUser -Force -SkipPublisherCheck

# From the repository root
.\Compile.ps1
Import-Module Pester -RequiredVersion 5.8.0 -Force
Invoke-Pester -Path 'pester/*.Tests.ps1' -Output Detailed -CI
```

Windows ships an older Pester, so import 5.8.0 explicitly before you run the tests.

Edit the sources and rebuild. `winutil.ps1` is generated and git-ignored, so don't edit or commit it.

| Path | Contents |
| --- | --- |
| `functions/public/`, `functions/private/` | PowerShell functions for UI actions and internal helpers |
| `config/` | JSON catalogs for apps, tweaks, features, presets, DNS providers, and AppX packages |
| `xaml/inputXML.xaml` | WPF interface markup |
| `scripts/` | `start.ps1` (startup) and `main.ps1` (entry point) |
| `tools/` | Build and docs helpers, the unattended setup XML, and the title-screen generator |
| `pester/`, `lint/` | Tests, and PSScriptAnalyzer settings |
| `docs/` | Documentation site |

To run the docs site locally, run `docker compose up winutil-astro` from `docs/` (Docker required), then open http://localhost:4321.

## Contributing

Guidelines are in [`.github/CONTRIBUTING.md`](.github/CONTRIBUTING.md). That file is inherited from upstream and still describes its workflow. In short: keep each change focused, document any new tweak together with its undo, and report bugs in this repository's Issues tab.

## License and credits

- Licensed under the [MIT License](LICENSE). Copyright (c) 2022 CT Tech Group LLC.
- WinUtil was created by Chris Titus Tech and its contributors. See [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil).
- Components in [`docs/src/components/react-bits/`](docs/src/components/react-bits/) are adapted from React Bits under MIT + Commons Clause. See the `LICENSE.md` in that folder.
