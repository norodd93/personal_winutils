# WinUtil customization overview

Everything below is data-driven or isolated enough to change without touching the generated
`winutil.ps1`. The applications list is already customized; this covers the other surfaces.

## At a glance

| Area | What it controls | Edit | Risk |
| --- | --- | --- | --- |
| Tweaks | Registry/service/script changes under **Tweaks** | `config/tweaks.json` | High (system changes) |
| Features & Fixes | Windows features, repair buttons, legacy panels | `config/feature.json` | High |
| AppX / Store apps | Removal list under **AppX** | `config/appx.json` | Medium |
| Presets | Checkbox bundles for Standard/Minimal/Advanced/AppxDefault | `config/preset.json` | Low |
| DNS providers | Provider list, IPv4/IPv6, DoH, benchmark opt-in | `config/dns.json` | Medium |
| Theme & sizing | Colours, fonts, spacing, button/card geometry | `config/themes.json` | Low |
| Install-tab sidebar | Action buttons/notes beside the app list | `config/appnavigation.json` | Low–medium |
| Branding | Window title, logo, console banner, sponsor link | `xaml/inputXML.xaml`, `scripts/start.ps1`, `scripts/main.ps1`, `functions/private/Invoke-WinUtilAssets.ps1` | Low |
| App icons | 48x48 PNG per app | `config/icons/<key>.png` via `tools/New-WinUtilIcon.ps1` | Low |
| Unattended ISO | Answer file injected by Win11 Creator | `tools/autounattend.xml` | High |
| Defaults | Starting theme and package manager | `scripts/main.ps1` | Low |
| Docs site | Guides, reference, landing page | `docs/` | Low |

After any config/UI change: `.\Compile.ps1` (and `-Run` to see the GUI). Run Pester for
config-shape changes.

---

## 1. Tweaks — `config/tweaks.json`

69 entries in four categories:

- Essential Tweaks (18)
- Customize Preferences (25)
- z__Advanced Tweaks - CAUTION (24)
- Performance Plans - NOT FOR LAPTOPS (2)

Each entry supports these change fields (combine as needed):

| Field | Shape | Purpose |
| --- | --- | --- |
| `registry` | `Path`, `Name`, `Value`, `Type`, `OriginalValue`/`DefaultValue`, `Values` | Set/remove registry values; `Values` maps Combobox choices to values |
| `service` | `Name`, `StartupType`, `OriginalType` | Change service startup type |
| `InvokeScript` | array of script strings | Arbitrary PowerShell on apply |
| `UndoScript` | array of script strings | Reversal for `InvokeScript` |
| `appx` | array of package names | Remove provisioned AppX packages |

UI/behaviour fields:

- `Type`: `Toggle`, `Combobox`, or omitted for a plain checkbox/button.
- `ComboItems` (pipe-separated) and optional `ComboDescriptions` for `Combobox`.
- `DefaultState` on Toggle registry entries.
- `panel` groups entries into columns (`0`, `1`, `2`); `category` is the section heading.
- Key prefix decides which selection list it lands in: `WPFTweaks*` vs `WPFToggle*`.

Rules:

- Keep `OriginalValue`/`OriginalType` so Undo restores the machine.
- Use `<RemoveEntry>` where the correct undo is deleting a value.
- Tweak keys are referenced by presets and docs, so rename them everywhere at once.

## 2. Features & Fixes — `config/feature.json`

33 entries across Features (10), Fixes (6), Legacy Windows Panels (14), PowerShell Profile
(2), Remote Access (1).

- `feature`: Windows optional-feature names passed to `Invoke-WinUtilFeatureInstall`.
- `InvokeScript`: inline work for Fixes/panels.
- `function`: name of an existing `Invoke-WPF*` function to run instead of inline script.
- `Type: Button` + `ButtonWidth` for action buttons.
- `panel` and `category` place entries in the Config tab columns.

Selecting a feature appends it to `selectedFeatures` (prefix `WPFFeature*`).

## 3. AppX removals — `config/appx.json`

34 entries in six categories. Fields: `Content`, `Description`, `Category`, `Panel`,
`PackageId`, `StoreId`.

- `PackageId` is what removal targets; `StoreId` is used to reinstall/open the Store page.
- Keys use the `WPFAppx*` prefix so selection tracking picks them up.
- Add removal candidates here rather than hard-coding package names in PowerShell.

## 4. Presets — `config/preset.json`

Four ready-made selections:

| Preset | Used by |
| --- | --- |
| `Standard` (12 keys) | Tweaks tab button |
| `Minimal` (4 keys) | Tweaks tab button |
| `Advanced` (17 keys) | Tweaks tab button |
| `AppxDefault` (18 keys) | AppX tab "default removals" |

Preset values are arrays of config keys. They may mix `WPFTweaks*`, `WPFToggle*`,
`WPFFeature*`, `WPFAppx*`, and `WPFInstall*`.

Caveats:

- Preset names are hard-coded in `docs/src/components/config-builder/ConfigBuilder.jsx` and
  `TweakExplorer.jsx`; a new name also needs the `-Preset` `ValidateSet` in
  `scripts/start.ps1` if it should be usable headlessly.
- Unknown keys are skipped by headless runs rather than aborting, so a typo fails quietly
  and is logged as a warning.

## 5. DNS providers — `config/dns.json`

Eight providers. Per provider:

- `Primary` / `Secondary` (IPv4) and `Primary6` / `Secondary6` (IPv6)
- `DohTemplate` for DNS-over-HTTPS
- `BenchmarkEligible: true` opts a provider into the "Fastest" latency benchmark

Add a provider by copying a block and changing the addresses; the DNS tab generates the
rest.

## 6. Theme and layout — `config/themes.json`

Three sections, 43 keys each:

- `shared`: sizes, fonts, margins, corner radii, button/card geometry.
- `Light` and `Dark`: colour keys (`*Color`, `*Opacity`).

Values feed WPF dynamic resources at startup and when the theme toggles. Colour keys also
get a `C<Name>` companion for controls that need a `Color` rather than a brush (e.g. drop
shadows). Changing a key name means changing the XAML reference too.

Useful knobs: `MainBackgroundColor`, `SurfaceBackgroundColor`, `Button*` colours,
`FontFamily`/`FontSize`, `TabButtonWidth`, `AppEntryWidth`, `SearchBarWidth`,
`GroupBorderBackgroundColor`.

## 7. Install-tab sidebar — `config/appnavigation.json`

11 entries rendered into the app category column. Fields: `Content`, `Category`, `Type`
(`Button`, `RadioButton`, `Note`), `Order`, `Description`, plus `GroupName`/`Checked` for
radios.

Keys map to existing UI/action names (for example `WPFInstall` → the install action).
Adding a new button requires a matching handler or config entry; changing an order or label
is safe.

## 8. Branding

| What | Where |
| --- | --- |
| Window title (`WinUtil`) | `xaml/inputXML.xaml` line ~14 |
| Console window title | `scripts/start.ps1` (`$Host.UI.RawUI.WindowTitle`) |
| ASCII banner and author line | `scripts/main.ps1` |
| Header logo (vector paths, `#0567ff`) | `functions/private/Invoke-WinUtilAssets.ps1`, `logo` case |
| Sponsors menu source | `functions/private/Invoke-WinUtilSponsors.ps1` |
| Docs/About links | `xaml/inputXML.xaml` menu items, `scripts/start.ps1` release URL |

The logo is drawn from hard-coded SVG path data, not an image file, so replacing it means
editing that function (or adding an asset-loading path).

## 9. App icons — `config/icons/`

One PNG per application, named after the key in `applications.json` without the
`WPFInstall` prefix. Requirements: 48x48, at most 8 KB (enforced by a Pester test).

Generate with `tools/New-WinUtilIcon.ps1`; missing icons fall back to an online favicon
lookup.

## 10. Win11 Creator — `tools/autounattend.xml`

Embedded as `$WinUtilAutounattendXml` and injected into the modified ISO. This controls
OOBE answers, locale, account setup, and first-login behaviour. High risk: a malformed file
can produce an ISO that fails to install.

## 11. Runtime defaults

In `scripts/main.ps1`:

```powershell
$sync.preferences.theme = "Auto"          # Auto | Light | Dark
$sync.preferences.packagemanager = "Winget"  # Winget | Choco
$sync.currentTab = "Install"
```

Command-line surfaces are in `scripts/start.ps1`: `-Config`, `-Preset`, `-Offline`.

## 12. Docs site — `docs/`

Astro + Starlight. Customize navigation (`docs/astro.config.mjs`), hand-written guides
(`docs/src/content/docs/guides/`), architecture notes
(`code-reference/architecture.mdx`), landing page, and the Config Builder/Tweak Explorer
tools.

Do not hand-edit `docs/src/content/docs/code-reference/tweaks/` or `features/`; those are
generated by `tools/devdocs-generator.ps1` from the JSON configs.

When you add/rename a preset, add a selection prefix, or add a tweak change field, update
both tools in the same change.

---

## Workflow for any of the above

1. Edit the JSON/source file.
2. Validate JSON parses (`Get-Content file | ConvertFrom-Json`).
3. Run `.\Compile.ps1`.
4. Run the relevant Pester file under `pester/`.
5. Run `.\Compile.ps1 -Run` for UI changes.

Never edit `winutil.ps1`; it is generated.
