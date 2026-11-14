# New Install

Personal Windows workstation setup scripts for installing applications, development tools, editor extensions, and shell configuration.

**Use [`windows/install_v2.ps1`](windows/install_v2.ps1).** It supports dry runs, independent installation steps, configurable paths, portable-tool selection, and timestamped logs. [`windows/install_v1.ps1`](windows/install_v1.ps1) is the legacy script; it contains machine-specific paths and does not provide v2's command-line controls.

This is a configurable bootstrap script, not an unattended installer or a rollback system. Review the package lists, default exclusions, and personal shortcut targets before a real run.

## Repository layout

| Path | Purpose |
| --- | --- |
| `windows/install_v2.ps1` | Current Windows installer and embedded PowerShell help. |
| `windows/install_v1.ps1` | Legacy installer, retained for reference. |
| `.gitignore` | Excludes local package lists, extension lists, and logs. |
| `windows/winget_install.txt` | Local WinGet package IDs; **not tracked**. |
| `windows/vscode_install.txt` | Local VS Code extension IDs; **not tracked**. |
| `windows/install.log` | Default runtime log; generated locally and **not tracked**. |

The three local files may exist in a working copy, but a fresh clone does not include them. Create the input lists, supply alternate paths, or skip the corresponding steps.

## Requirements

- **Windows x64**: portable downloads target Windows x86-64, and shortcut creation uses Windows COM.
- **PowerShell 7+** (`pwsh`), not Windows PowerShell 5.1.
- Internet access for application downloads and release discovery.
- `winget.exe` for the package-list and Visual Studio steps; install or repair Windows App Installer if missing.
- `curl.exe` for payload downloads and Arm metadata discovery.
- The VS Code CLI (`code.cmd` or `code.exe`) for extension installation.
- Nushell (`nu.exe`) and zoxide for shell configuration. These can be installed through your WinGet list.
- Permission to write the chosen directories and approve elevation when installers request it. VirtualBox explicitly requests elevation.

Dependencies apply to the steps you enable. Skipping a prerequisite's installation does not make it unnecessary for a later enabled step.

## Getting started

All commands below assume **the repository root** is the working directory.

### 1. Inspect the available options

```powershell
Get-Help .\windows\install_v2.ps1 -Full
Get-Help .\windows\install_v2.ps1 -Examples
Get-Help .\windows\install_v2.ps1 -Parameter SkipPortableTool
```

From another shell, launch PowerShell help with:

```powershell
pwsh -NoProfile -File .\windows\install_v2.ps1 -?
```

Help does not install anything. `--help` and `/help` are not supported.

### 2. Prepare your configuration

Create or review the local package and extension lists described under [Configuration](#configuration). Review the script's portable-tool defaults and the personal application shortcuts as well.

### 3. Preview the selected work

```powershell
pwsh -NoProfile -File .\windows\install_v2.ps1 -WhatIf
```

A dry run can still fail if input files, prerequisite commands, or release metadata are unavailable. See [Dry-run behavior](#dry-run-behavior).

For a preview that needs neither local input list, skip their consumers and other network-discovery steps:

```powershell
pwsh -NoProfile -File .\windows\install_v2.ps1 -WhatIf -SkipWinget -SkipVisualStudio -SkipVSCodeExtensions -SkipArmToolchain -SkipVirtualBox -SkipShellConfiguration -SkipShortcuts -SkipPortableTool "Clangd,Rufus"
```

This previews AnyZig, AnyZls, LanXchange, and Rust. Zigup remains excluded by default. No tool payloads are downloaded or installed.

### 4. Run the installer

After reviewing the preview and configuration:

```powershell
pwsh -NoProfile -File .\windows\install_v2.ps1
```

This performs real installation. Rust and Visual Studio may prompt interactively; some installers request elevation. If the personal shortcut paths do not apply to your machine, edit them first or add `-SkipShortcuts`.

## What the installer does

The normal execution order is:

1. Install package IDs from the WinGet list.
2. Install Visual Studio Community through a separate WinGet step.
3. Install the configured VS Code extensions.
4. Install selected portable tools in catalog order.
5. Discover and install the Windows x64 Arm GNU Toolchain ZIP.
6. Run rustup interactively and add the Cargo bin directory to user PATH.
7. Install VirtualBox and its extension pack.
8. Initialize zoxide for Nushell, load its generated configuration, and disable the Nushell banner.
9. Create the separately configured application shortcuts in the current user's Start Menu.

The script is not a version lockfile: several downloads resolve the latest available release. Reruns can invoke installers again and overwrite extracted files; there is no rollback or uninstall command.

## Options and defaults

Switch names and tool names are case-insensitive. All switches default to **false**; supplying a switch enables it. PowerShell also accepts an explicit value such as `-SkipRust:$false`.

Only the two portable-tool lists are positional. Supply every other argument by its parameter name.

### Paths and URL

| Option | Input and default | Behavior |
| --- | --- | --- |
| `-WingetListPath` | Text-file path; `windows/winget_install.txt` beside the script. | Read one package ID per line, unless `-SkipWinget` is set. |
| `-VSCodeExtensionListPath` | Text-file path; `windows/vscode_install.txt` beside the script. | Read one extension ID per line; must contain at least one usable entry unless skipped. |
| `-InstallRoot` | Directory path; `$HOME\terminal`. | Root for portable tools and the Arm toolchain, except LanXchange. External installers choose their own locations. |
| `-DownloadRoot` | Directory path; `$HOME\Downloads`. | Stage downloaded archives/installers. Rufus is downloaded directly into its installation directory instead. |
| `-ArmToolchainUrl` | Absolute HTTP(S) URL to a compatible Windows x64 ZIP; unset by default. | Override automatic Arm release discovery. Ignored when the Arm step is skipped. |
| `-LogPath` | File path; `windows/install.log` beside the script. | Write timestamped UTF-8 messages to this file and the console. |

Default list/log locations are relative to **the script**, even when launched from another directory. User-supplied relative paths are relative to **the working directory**.

Example using custom local inputs and directories:

```powershell
pwsh -NoProfile -File .\windows\install_v2.ps1 -WhatIf -WingetListPath '.\packages.txt' -VSCodeExtensionListPath '.\extensions.txt' -InstallRoot 'D:\Tools' -DownloadRoot 'D:\InstallDownloads' -LogPath '.\preview.log'
```

Create the two input files before using that example. To override Arm discovery, supply `-ArmToolchainUrl $url` from PowerShell, where `$url` is a direct URL to the appropriate ZIP.

### Preview and skip switches

| Option | Effect when supplied |
| --- | --- |
| `-WhatIf` | Preview actions instead of downloading payloads or installing/configuring tools. |
| `-SkipWinget` | Skip the WinGet package-list step, not the separate Visual Studio step. |
| `-SkipVisualStudio` | Skip the separate Visual Studio Community installation. |
| `-SkipVSCodeExtensions` | Skip extension-list reading and extension installation. |
| `-SkipPortableTool` | With no lists, skip all portable tools; with lists, select tools as described below. |
| `-SkipArmToolchain` | Skip Arm release discovery, download, extraction, and PATH configuration. |
| `-SkipRust` | Skip rustup execution, Cargo checking, and its PATH update. |
| `-SkipVirtualBox` | Skip VirtualBox and extension-pack discovery and installation. |
| `-SkipShellConfiguration` | Skip Nushell/zoxide configuration. |
| `-SkipShortcuts` | Skip only the final personal application-shortcut step. |

**Steps are independent.** For example, `-SkipRust` does not remove Rust-related IDs from the WinGet list. `-SkipShortcuts` does not suppress the LanXchange and Rufus shortcuts created by their portable installers. Skip those tools separately if their shortcuts are unwanted.

To skip every installation/configuration step:

```powershell
pwsh -NoProfile -File .\windows\install_v2.ps1 -WhatIf -SkipWinget -SkipVisualStudio -SkipVSCodeExtensions -SkipPortableTool -SkipArmToolchain -SkipRust -SkipVirtualBox -SkipShellConfiguration -SkipShortcuts
```

This still writes a log. Without `-WhatIf`, directory initialization also occurs even when every step is skipped.

## Portable-tool selection

The current ordered catalog is:

| Tool name | Default selection | Location |
| --- | --- | --- |
| `Zigup` | Excluded; requires explicit inclusion. | `InstallRoot\zigup-x86_64-windows` |
| `AnyZig` | Included. | `InstallRoot\anyzig-x86_64-windows` |
| `AnyZls` | Included. | `InstallRoot\anyzls-x86_64-windows`; exposes `zls.exe`. |
| `Clangd` | Included. | Release directory beneath `InstallRoot`; its `bin` directory is added to PATH. |
| `LanXchange` | Included. | `C:\LanXchange`, independent of `InstallRoot`. |
| `Rufus` | Included. | `InstallRoot\Rufus`. |

Use one switch with up to two lists:

```text
-SkipPortableTool [exclusion-list] [inclusion-list]
```

| Arguments | Meaning |
| --- | --- |
| Option omitted | Install the catalog minus its default exclusions. |
| `-SkipPortableTool` | Skip every portable tool. |
| `-SkipPortableTool "Rufus,Clangd"` | Exclude Rufus and Clangd, plus the remaining default exclusions. |
| `-SkipPortableTool "Rufus,Clangd" "Zigup"` | Exclude Rufus and Clangd; explicitly enable Zigup. |
| `-SkipPortableTool "" "Zigup"` | Add no explicit exclusions and enable Zigup. |
| `-SkipPortableTool ""` | Use the normal defaults; an explicit empty list is not the same as no lists. |

For example, preview enabling Zigup while skipping Rufus and Clangd:

```powershell
pwsh -NoProfile -File .\windows\install_v2.ps1 -WhatIf -SkipPortableTool "Rufus,Clangd" "Zigup"
```

Inside PowerShell, arrays also work: `-SkipPortableTool Rufus,Clangd Zigup`, or `-SkipPortableTool @() Zigup` to leave the first list empty. For `pwsh -File`, use quoted comma-separated strings as above.

The positional inputs are internally named `PortableToolExclusions` and `PortableToolInclusions`, each defaulting to an empty string array. Normal invocation needs only the single `-SkipPortableTool` switch.

Selection rules:

- Names are case-insensitive; whitespace is trimmed and duplicate entries collapse.
- Explicit inclusions override **default** exclusions. Inclusion is additive, not an “install only these tools” mode.
- A name cannot occur in both explicit lists. For example, `-SkipPortableTool Zigup zigup` errors rather than choosing a winner.
- Unknown names, a third list, or lists without the switch are rejected before directory/log initialization.
- Remaining tools run in catalog order. Selection never changes the separate WinGet, Arm, Rust, or other steps.

## Configuration

### Application and extension lists

Create `windows/winget_install.txt` with one WinGet package ID per line. For example:

```text
# Applications and shell prerequisites
7zip.7zip
Microsoft.VisualStudioCode
Nushell.Nushell
ajeetdsouza.zoxide
// Commented-out WinGet entry
```

Blank lines, full-line `#`/`//` comments, and duplicate package IDs are ignored. These are examples, not a required or exhaustive package list.

Create `windows/vscode_install.txt` with one extension ID per line:

```text
# Editor extensions
ms-vscode.powershell
ziglang.vscode-zig
```

Blank lines and full-line `#` comments are ignored. The extension list must have at least one usable entry when its step is enabled. Unlike the WinGet parser, it does not support `//` comments or remove duplicates.

These filenames are ignored by Git at any directory depth. To keep a shared list in version control without changing the ignore rules, give it another filename and select it with the corresponding path option.

### Tool catalog and default exclusions

Edit these adjacent variables in `windows/install_v2.ps1`:

- `$script:PortableTools`: all available tools, in installation order.
- `$script:DefaultExcludedPortableTools`: tools skipped unless explicitly included; currently `Zigup`.

Default exclusions should name tools in the catalog. They are combined with explicit exclusions using a case-insensitive set, then explicit inclusions remove default exclusions. Explicit-list conflicts are checked first.

Adding another default exclusion only requires editing its list. Registering a new tool requires adding its catalog entry **and** defining a matching `Install-<name>` function; a name alone does not implement installation.

### Personal shortcuts

The final shortcut step contains an ordered name-to-executable map inside the script. It currently points to personal game installations on `D:`. Replace those targets with paths that exist on your machine, or use `-SkipShortcuts`.

Shortcuts are created in the current user's Start Menu. Their target is the executable; their **Start in** field is its parent directory. LanXchange and Rufus have separate shortcut creation inside their own installers.

## Dry-run behavior

`-WhatIf` uses the same selection logic as a real run. Selected actions are logged with `WHATIF`; excluded portable tools are logged as skipped.

It does **not** download tool/installer payloads, extract archives, run installers, delete downloaded artifacts, update PATH, or create shortcuts.

It **does** write logs, read local input lists, and check some prerequisites. Release discovery can make network requests, launch `curl.exe`, and create then remove temporary metadata files. Consequently, a dry run is neither offline nor entirely write-free, and unavailable upstream metadata can make it fail.

## Logs, failures, and troubleshooting

- By default, logs go to `windows/install.log`. Use `-LogPath` to keep a run elsewhere.
- Normal runs clear an existing log first; dry runs append. The log's parent directory is created if necessary.
- Most step errors are recorded while later steps continue. An error within the portable group stops the remaining tools in that group, but later top-level steps can continue.
- Recorded installation failures produce process exit code `1`; malformed arguments or invalid portable selections also fail. There is no rollback of earlier changes.
- Successfully processed downloaded artifacts are removed; interrupted or failed steps may leave files to inspect.
- Open a new terminal to pick up persistent user PATH changes in other processes.

| Symptom | Check |
| --- | --- |
| Package/extension list missing | Create the local file, supply a path override, or skip its step. The lists are not included in a clone. |
| `winget.exe` missing | Repair/install App Installer, or skip both WinGet consumers. |
| VS Code CLI missing | Make `code.cmd` or `code.exe` available on PATH, or skip extension installation. |
| Nushell/zoxide missing | Install their prerequisites, or skip shell configuration. |
| Arm metadata discovery fails | Supply a direct compatible ZIP URL through `-ArmToolchainUrl`, or skip that step. |
| Shortcut target does not exist | Edit the personal shortcut map or use `-SkipShortcuts`. |
| Portable selection rejected | Check catalog names, switch presence, number of lists, and explicit-set overlap. |

For the complete parameter-by-parameter reference, use the installer's embedded `Get-Help` documentation.
