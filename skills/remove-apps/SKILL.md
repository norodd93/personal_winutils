---
name: remove-apps
description: Remove applications from WinUtil's Install tab (edit config/applications.json + config/icons, then verify)
---

# Remove Applications (skill)

Remove applications from WinUtil's Install tab. Apps are declarative entries consumed at runtime, so removal is a config + icon edit — no PowerShell function changes are needed.

## When to use

- Removing applications from the Install tab (e.g. browsers, tools) so they no longer appear.

## Workflow

1. **Find keys and icons.** `config/applications.json` keys are case-sensitive (e.g. `chrome`, `ZenBrowser`). Matching icon: `config/icons/<key>.png`.
2. **Get entry line ranges.** File uses CRLF. Run:
   ```bash
   awk 'BEGIN{RS="\r\n"} /"<key>" *: *{/ {print NR}' config/applications.json
   ```
   Then pair each key with its closing `    },` line (awk tracking the `    },` terminator).
3. **Delete the entries.** Use `sed -i` with the exact `[key,close]` ranges so CRLF is preserved:
   ```bash
   sed -i '209,217d; 425,433d; ...' config/applications.json
   ```
4. **Delete the icons.** `rm config/icons/<key>.png` for each removed key.
5. **Verify:**
   - JSON parses and entry count is 231 (239 − 8 for the batch above).
   - CRLF count drops by `8 entries × 9 lines = 72` (→ 2079).
   - Icons: every remaining app has an icon ≤8 KB, no orphan icons:
     ```bash
     python3 -c "import json; from pathlib import Path; d=json.load(open('config/applications.json',encoding='utf-8')); keys=list(d.keys()); icons={f.stem for f in Path('config/icons').glob('*.png')}; print('keys',len(keys),'icons',len(icons),'missing',sorted(set(keys)-icons),'orphans',sorted(icons-set(keys)),'big',[(k,(Path('config/icons')/k+'.png').stat().st_size) for k in keys if (Path('config/icons')/k+'.png').stat().st_size>8192]); print('ALL_OK',set(keys)==icons and not big)"
     ```
   - `git diff --stat` shows only `applications.json` + the icon files.

## Caveats

- Never edit `functions/` — apps are read dynamically from `$sync.configs` at runtime.
- Never touch `docs/src/content/docs/code-reference/tweaks/` or `/features/` (auto-generated).
- Docs Config Builder / Tweak Explorer fetch the **latest GitHub release** config in-browser — local removals don't show there until a new release.
- Never commit `winutil.ps1`, `binary/`, or other generated/ignored artifacts.
- Not every file in `config/` is an app list — `tweaks.json`, `feature.json`, `dns.json`, `preset.json`, `themes.json`, `appx.json` are separate; only `applications.json` + `config/icons/` hold applications.

## Limitations

- PowerShell/Pester/Script Analyzer only run on Windows. This Linux host has neither `pwsh` nor `powershell`, so the Pester suite and `.\Compile.ps1` cannot be executed here; verify by inspection instead.
