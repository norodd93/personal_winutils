How to Run WinUtil


Option 1: Compile and Run in One Step (Recommended)
.\Compile.ps1 -Run
This compiles the source files into winutil.ps1 and immediately launches the WPF GUI.
Option 2: Compile Separately, Then Run
.\Compile.ps1
.\Winutil.ps1
Option 3: Using the Stable Release (from README)
The README also mentions installing from the official release:
irm https://christitus.com/win | iex
What the Compile Script Does
The Compile.ps1 script (as described in SPEC.md) combines these sources in order:
1. Reads scripts/start.ps1 and replaces #{replaceme} with the build date
2. Appends every file under functions/ recursively (both public/ and private/)
3. Converts config/*.json files into embedded $sync.configs objects
4. Embeds xaml/inputXML.xaml into $inputXML
5. Embeds tools/autounattend.xml into $WinUtilAutounattendXml
6. Appends scripts/main.ps1
7. Writes the result to winutil.ps1
Key Directories
- functions/public/ - UI-facing PowerShell functions (WPF buttons, installers, etc.)
- functions/private/ - Internal helper functions
- config/ - JSON configuration files consumed at compile time
- xaml/inputXML.xaml - WPF UI markup
- scripts/ - Entry points (start.ps1, main.ps1)
Notes
- winutil.ps1 is the generated build artifact and is ignored by git (per .gitignore)
- Do not edit winutil.ps1 directly - make changes to source files and recompile
- Long-running operations use runspaces and the $sync hashtable for shared state