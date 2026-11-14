# pwsh -NoProfile -File .\install_v2.ps1 -SkipWinget -SkipPortableTool -SkipRust -SkipVirtualBox -SkipVisualStudio -SkipArmToolchain -SkipVSCodeExtensions -SkipShellConfiguration -SkipShortcuts
#requires -Version 7.0

<#
.SYNOPSIS
Install applications, portable tools, and development environment configuration.

.PARAMETER SkipPortableTool
With no positional lists, skip all portable tools.
With one positional list, exclude those tools.
With two positional lists, exclude the first list and explicitly include the second.
Omitting this switch installs the configured tools except the default exclusions.
Explicit inclusions override default exclusions.

Edit $script:PortableTools and $script:DefaultExcludedPortableTools in the
configuration section to change available tools and default exclusions.
Names are case-insensitive and duplicates are ignored.
Explicit exclusions and inclusions must not overlap; invalid selections fail before installation.
Lists require this switch. Other installer arguments must use their parameter names.

Use PowerShell arrays or quoted comma-separated lists. For pwsh -File, use quoted
comma-separated lists. An empty first list allows inclusion without explicit exclusions;
an explicitly empty list is distinct from supplying no lists.

.EXAMPLE
.\install_v2.ps1 -SkipPortableTool
Skip all portable tools.

.EXAMPLE
.\install_v2.ps1 -SkipPortableTool Rufus,Clangd
Exclude Rufus and Clangd. Other default exclusions still apply.

.EXAMPLE
pwsh -NoProfile -File .\install_v2.ps1 -SkipPortableTool "Rufus,Clangd" "Zigup"
Exclude Rufus and Clangd, and enable Zigup. Other default exclusions still apply.

.EXAMPLE
pwsh -NoProfile -File .\install_v2.ps1 -SkipPortableTool "" "Zigup"
Enable Zigup without explicit exclusions. Other default exclusions still apply.

.EXAMPLE
pwsh -NoProfile -File .\install_v2.ps1 -SkipWinget -SkipPortableTool -SkipRust -SkipVirtualBox -SkipVisualStudio -SkipArmToolchain -SkipVSCodeExtensions -SkipShellConfiguration -SkipShortcuts
Skips Everything.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$WhatIf,

    [string]$WingetListPath = (
        Join-Path $PSScriptRoot 'winget_install.txt'
    ),

    [string]$VSCodeExtensionListPath = (
        Join-Path $PSScriptRoot 'vscode_install.txt'
    ),

    [string]$InstallRoot = (
        Join-Path $HOME 'terminal'
    ),

    [string]$DownloadRoot = (
        Join-Path $HOME 'Downloads'
    ),

    [string]$ArmToolchainUrl,

    [switch]$SkipWinget,
    [switch]$SkipVisualStudio,
    [switch]$SkipVSCodeExtensions,
    [switch]$SkipPortableTool,

    [Parameter(Position = 0, DontShow = $true)]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]$PortableToolExclusions = @(),

    [Parameter(Position = 1, DontShow = $true)]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]$PortableToolInclusions = @(),

    [switch]$SkipArmToolchain,
    [switch]$SkipRust,
    [switch]$SkipVirtualBox,
    [switch]$SkipShellConfiguration,
    [switch]$SkipShortcuts,

    [string]$LogPath = (
        Join-Path $PSScriptRoot 'install.log'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration and state
# ---------------------------------------------------------------------------

# Edit these lists to configure available tools and their default exclusions.
# Each tool name must have a matching Install-<name> function below.
$script:PortableTools = @(
    'Zigup'
    'AnyZig'
    'AnyZls'
    'Clangd'
    'LanXchange'
    'Rufus'
)
$script:DefaultExcludedPortableTools = @(
    'Zigup'
)

$script:ExcludedPortableTools = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
$includedPortableTools = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
$hasPortableToolLists = (
    $PSBoundParameters.ContainsKey('PortableToolExclusions') -or
    $PSBoundParameters.ContainsKey('PortableToolInclusions')
)

if ($hasPortableToolLists -and -not $SkipPortableTool) {
    throw 'Portable tool lists require -SkipPortableTool.'
}

foreach ($selection in @(
    @{ Values = $PortableToolExclusions; Set = $script:ExcludedPortableTools },
    @{ Values = $PortableToolInclusions; Set = $includedPortableTools }
)) {
    foreach ($value in $selection.Values) {
        foreach ($entry in ($value -split ',')) {
            $tool = $entry.Trim()
            if ($tool -eq '') {
                continue
            }
            if ($script:PortableTools -notcontains $tool) {
                throw "Unknown portable tool '$tool'. Valid tools: $($script:PortableTools -join ', ')."
            }
            [void]$selection.Set.Add($tool)
        }
    }
}

if ($script:ExcludedPortableTools.Overlaps($includedPortableTools)) {
    $conflicts = $script:PortableTools | Where-Object {
        $script:ExcludedPortableTools.Contains($_) -and $includedPortableTools.Contains($_)
    }
    throw "Portable tools cannot be both excluded and included: $($conflicts -join ', ')."
}

# Explicit inclusion overrides default exclusions, not explicit skips.
$script:ExcludedPortableTools.UnionWith([string[]]$script:DefaultExcludedPortableTools)
$script:ExcludedPortableTools.ExceptWith($includedPortableTools)
if ($SkipPortableTool -and -not $hasPortableToolLists) {
    $script:ExcludedPortableTools.UnionWith([string[]]$script:PortableTools)
}

$script:DryRun = $WhatIf.IsPresent
$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:Successes = [System.Collections.Generic.List[string]]::new()

$script:InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$script:Downloads = [IO.Path]::GetFullPath($DownloadRoot)
$script:LogPath = [IO.Path]::GetFullPath($LogPath)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp [$Level] $Message"

    Write-Host $line

    $logDirectory = Split-Path -Parent $script:LogPath

    if (-not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force |
            Out-Null
    }

    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding utf8
}

function Add-Failure {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $message = "$Name`: $($Exception.Message)"
    $script:Failures.Add($message)
    Write-Log -Level ERROR -Message $message
}

function Invoke-InstallationStep {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    try {
        Write-Log "Starting: $Name"
        & $Action
        $script:Successes.Add($Name)

        if ($script:DryRun) {
            Write-Log "Dry run completed for: $Name"
        }
        else {
            Write-Log "Completed: $Name"
        }
    }
    catch {
        Add-Failure -Name $Name -Exception $_.Exception
    }
}

# ---------------------------------------------------------------------------
# Filesystem helpers
# ---------------------------------------------------------------------------

function Initialize-Directories {
    foreach ($directory in @(
        $script:InstallRoot,
        $script:Downloads
    )) {
        if ($script:DryRun) {
            Write-Log "WHATIF: Create directory $directory"
        }
        else {
            New-Item -ItemType Directory -Path $directory -Force |
                Out-Null
        }
    }
}

function New-StartMenuShortcut {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $programsDirectory = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $shortcutPath = Join-Path $programsDirectory "$Name.lnk"

    if ($script:DryRun) {
        Write-Log "WHATIF: Create Start Menu shortcut $shortcutPath -> $TargetPath"
        return
    }

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        throw "Shortcut target does not exist: $TargetPath"
    }

    New-Item -ItemType Directory -Path $programsDirectory -Force |
        Out-Null

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = Split-Path -LiteralPath $TargetPath
    $shortcut.Save()

    Write-Log "Created Start Menu shortcut $shortcutPath"
}

function Get-DownloadPath {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$FallbackName
    )

    $name = $FallbackName

    try {
        $uriObject = [uri]$Uri
        $candidate = [IO.Path]::GetFileName($uriObject.AbsolutePath)

        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $name = $candidate
        }
    }
    catch {
        # Keep the caller-provided filename.
    }

    return (Join-Path $script:Downloads $name)
}

function Save-Download {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if ($script:DryRun) {
        Write-Log "WHATIF: Download $Uri -> $Destination"
        return
    }

    $directory = Split-Path -Parent $Destination

    New-Item -ItemType Directory -Path $directory -Force |
        Out-Null

    Write-Log "Downloading $Uri"

    $curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
    if (-not $curl) {
        throw 'curl.exe was not found; install or enable Windows curl before downloading files.'
    }

    $downloadPath = "$Destination.$([guid]::NewGuid().ToString()).download"
    $headersPath = Join-Path ([IO.Path]::GetTempPath()) (
        [guid]::NewGuid().ToString() + '.headers'
    )
    try {
        $status = & $curl.Source `
            --silent `
            --show-error `
            --location `
            --max-redirs 10 `
            --fail `
            --dump-header $headersPath `
            --output $downloadPath `
            --write-out '%{http_code}' `
            -- $Uri
        $curlExitCode = $LASTEXITCODE

        if ($curlExitCode -ne 0) {
            throw "curl.exe failed with exit code $curlExitCode while downloading $Uri."
        }

        $headers = if (Test-Path -LiteralPath $headersPath) {
            Get-Content -LiteralPath $headersPath -Raw
        }
        else {
            ''
        }

        if ($headers -match '(?im)^x-amzn-waf-action:\s*challenge\s*$') {
            throw "AWS WAF challenge detected while downloading $Uri."
        }

        if ($status -notmatch '^2\d\d$') {
            throw "Download returned HTTP $status for $Uri."
        }

        if (-not (Test-Path -LiteralPath $downloadPath -PathType Leaf)) {
            throw "Download did not create the expected file: $Destination"
        }

        if ((Get-Item -LiteralPath $downloadPath).Length -eq 0) {
            throw "Downloaded file is empty: $Destination"
        }

        Move-Item -LiteralPath $downloadPath -Destination $Destination -Force
    }
    finally {
        Remove-Item -LiteralPath $downloadPath, $headersPath `
            -Force -ErrorAction SilentlyContinue
    }

}

function Remove-DownloadedArtifact {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($script:DryRun) {
        Write-Log "WHATIF: Delete downloaded artifact $Path"
        return
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Log "Deleted downloaded artifact $Path"
    }
}

function Expand-DownloadedArchive {
    param(
        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if ($script:DryRun) {
        Write-Log "WHATIF: Extract $ArchivePath -> $Destination"
        return
    }

    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Archive does not exist: $ArchivePath"
    }

    New-Item -ItemType Directory -Path $Destination -Force |
        Out-Null

    Expand-Archive `
        -LiteralPath $ArchivePath `
        -DestinationPath $Destination `
        -Force

    Write-Log "Extracted archive to $Destination"
}

# ---------------------------------------------------------------------------
# PATH management
# ---------------------------------------------------------------------------

function Add-UserPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = [IO.Path]::GetFullPath($Path)

    if ($script:DryRun) {
        Write-Log "WHATIF: Add PATH entry $resolvedPath"
        return
    }

    $currentPath = [Environment]::GetEnvironmentVariable(
        'Path',
        'User'
    )

    $entries = @(
        $currentPath -split ';' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $alreadyExists = $false

    foreach ($entry in $entries) {
        try {
            if ([string]::Equals(
                [IO.Path]::GetFullPath($entry.Trim()),
                $resolvedPath,
                [StringComparison]::OrdinalIgnoreCase
            )) {
                $alreadyExists = $true
                break
            }
        }
        catch {
            # Ignore malformed existing PATH entries.
        }
    }

    if (-not $alreadyExists) {
        $newPath = if ([string]::IsNullOrWhiteSpace($currentPath)) {
            $resolvedPath
        }
        else {
            "$currentPath;$resolvedPath"
        }

        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Log "Added user PATH entry: $resolvedPath"
    }
    else {
        Write-Log "PATH entry already exists: $resolvedPath"
    }

    # Make the entry available to child processes launched by this script.
    if (-not (($env:Path -split ';') -contains $resolvedPath)) {
        $env:Path = "$env:Path;$resolvedPath"
    }
}

# ---------------------------------------------------------------------------
# External process execution
# ---------------------------------------------------------------------------

function Invoke-External {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [string]$WorkingDirectory,

        [switch]$RunAs
    )

    $displayArguments = $ArgumentList -join ' '
    $displayCommand = "$FilePath $displayArguments".Trim()

    if ($script:DryRun) {
        $elevation = if ($RunAs) { ' (elevated)' } else { '' }
        Write-Log "WHATIF$elevation`: $displayCommand"
        return
    }

    $processParameters = @{
        FilePath     = $FilePath
        ArgumentList = $ArgumentList
        Wait         = $true
        PassThru     = $true
    }

    if ($RunAs) {
        $processParameters.Verb = 'RunAs'
    }
    else {
        $processParameters.NoNewWindow = $true
    }

    if ($WorkingDirectory) {
        $processParameters.WorkingDirectory = $WorkingDirectory
    }

    $process = Start-Process @processParameters

    if ($process.ExitCode -ne 0) {
        throw "Process exited with code $($process.ExitCode): $displayCommand"
    }

    Write-Log "Process exited successfully: $displayCommand"
}

# ---------------------------------------------------------------------------
# WinGet
# ---------------------------------------------------------------------------

function Get-WingetPackages {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "WinGet package list not found: $Path"
    }

    # Supports both '#' and '//' full-line comments.
    # Blank lines and duplicate IDs are discarded.
    $packages = @(
        Get-Content -LiteralPath $Path |
            ForEach-Object { $_.Trim() } |
            Where-Object {
                $_ -and
                -not $_.StartsWith('#') -and
                -not $_.StartsWith('//')
            } |
            Select-Object -Unique
    )

    return $packages
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    Write-Log "Installing WinGet package: $Id"

    Invoke-External `
        -FilePath 'winget.exe' `
        -ArgumentList @(
            'install',
            '--id', $Id,
            '--exact',
            '--source', 'winget',
            '--accept-source-agreements',
            '--accept-package-agreements'
        )
}

function Install-WingetPackages {
    if (-not (Get-Command 'winget.exe' -ErrorAction SilentlyContinue)) {
        throw 'winget.exe was not found. Install or repair App Installer first.'
    }

    $packages = @(Get-WingetPackages -Path $WingetListPath)

    Write-Log "Found $($packages.Count) unique WinGet package IDs."

    foreach ($package in $packages) {
        Invoke-InstallationStep -Name "WinGet: $package" -Action {
            Install-WingetPackage -Id $package
        }
    }
}

# ---------------------------------------------------------------------------
# Nushell configuration
# ---------------------------------------------------------------------------

function Initialize-NushellConfiguration {
    # Keep existing config; reruns refresh zoxide without duplicating settings.
    $commands = @'
zoxide init nushell --cmd cd | save --force ~/.zoxide.nu
mkdir ($nu.config-path | path dirname)
let existing = if ($nu.config-path | path exists) {
    open --raw $nu.config-path | lines
} else {
    []
}
for setting in ['source ~/.zoxide.nu' '$env.config.show_banner = false'] {
    if not ($setting in $existing) {
        (char newline) + $setting + (char newline) | save --append $nu.config-path
    }
}
'@

    if (-not $script:DryRun) {
        # Prefer refreshed user and machine entries; keep process-only entries last.
        $env:Path = @(
            [Environment]::GetEnvironmentVariable('Path', 'User')
            [Environment]::GetEnvironmentVariable('Path', 'Machine')
            $env:Path
        ) -join ';'
    }

    Invoke-External `
        -FilePath 'nu.exe' `
        -ArgumentList @('--no-config-file', '--commands', "`"$commands`"")
}

function Install-VisualStudio {
    if (-not (Get-Command 'winget.exe' -ErrorAction SilentlyContinue)) {
        throw 'winget.exe was not found. Install or repair App Installer first.'
    }

    Write-Log 'Installing Visual Studio Community.'

    Invoke-External `
        -FilePath 'winget.exe' `
        -ArgumentList @(
            'install',
            '--id', 'Microsoft.VisualStudio.Community',
            '--exact',
            '--source', 'winget',
            '--interactive',
            '--force',
            '--accept-source-agreements',
            '--accept-package-agreements'
        )
}

function Install-VSCodeExtensions {
    $listPath = $VSCodeExtensionListPath
    if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) {
        throw "VS Code extension list was not found: $listPath"
    }

    $extensions = @(
        Get-Content -LiteralPath $listPath |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') }
    )

    if ($extensions.Count -eq 0) {
        throw "No VS Code extensions were listed in $listPath"
    }

    if ($script:DryRun) {
        foreach ($extension in $extensions) {
            Write-Log "WHATIF: code --install-extension $extension"
        }
        return
    }

    $code = Get-Command 'code.cmd' -ErrorAction SilentlyContinue
    if (-not $code) {
        $code = Get-Command 'code.exe' -ErrorAction SilentlyContinue
    }

    if (-not $code) {
        throw 'The VS Code CLI (code.cmd or code.exe) was not found in PATH.'
    }

    foreach ($extension in $extensions) {
        Invoke-External `
            -FilePath $code.Source `
            -ArgumentList @('--install-extension', $extension)
    }
}


# ---------------------------------------------------------------------------
# HTML link discovery
# ---------------------------------------------------------------------------

function Get-PageLink {
    param(
        [Parameter(Mandatory)]
        [string]$Page,

        [Parameter(Mandatory)]
        [string]$Pattern
    )

    Write-Log "Discovering download link on $Page"

    $bodyPath = Join-Path ([IO.Path]::GetTempPath()) (
        [guid]::NewGuid().ToString() + '.html'
    )
    $headersPath = Join-Path ([IO.Path]::GetTempPath()) (
        [guid]::NewGuid().ToString() + '.headers'
    )
    $curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
    if (-not $curl) {
        throw 'curl.exe was not found; install or enable Windows curl before retrieving web pages.'
    }

    try {
        $status = & $curl.Source `
            --silent `
            --show-error `
            --location `
            --max-redirs 10 `
            --fail `
            --dump-header $headersPath `
            --output $bodyPath `
            --write-out '%{http_code}' `
            -- $Page
        $curlExitCode = $LASTEXITCODE

        if ($curlExitCode -ne 0) {
            throw "curl.exe failed with exit code $curlExitCode while retrieving $Page."
        }

        $headers = Get-Content -LiteralPath $headersPath -Raw
        if ($headers -match '(?im)^x-amzn-waf-action:\s*challenge\s*$') {
            throw "AWS WAF challenge detected while retrieving $Page."
        }

        if ($status -notmatch '^2\d\d$') {
            throw "Page request returned HTTP $status for $Page."
        }

        $html = Get-Content -LiteralPath $bodyPath -Raw
    }
    finally {
        Remove-Item -LiteralPath $bodyPath, $headersPath `
            -Force -ErrorAction SilentlyContinue
    }

    # Read href values from the page, decode HTML entities, then match the
    # requested filename pattern. This handles both quoted and unquoted hrefs.
    $hrefPattern = '(?is)\bhref\s*=\s*(?:"([^"]+)"|''([^'']+)''|([^\s>]+))'

    $links = foreach ($match in [regex]::Matches($html, $hrefPattern)) {
        $href = @(
            $match.Groups[1].Value,
            $match.Groups[2].Value,
            $match.Groups[3].Value
        ) | Where-Object { $_ } | Select-Object -First 1

        if (-not $href) {
            continue
        }

        $href = [System.Net.WebUtility]::HtmlDecode($href)

        try {
            $absoluteUri = [uri]::new([uri]$Page, $href)
        }
        catch {
            continue
        }

        if ($absoluteUri.Scheme -notin @('http', 'https')) {
            continue
        }

        $absoluteUri.AbsoluteUri
    }

    $matchingLinks = @(
        $links |
            Where-Object {
                $link = $_
                $fileName = [IO.Path]::GetFileName(([uri]$link).AbsolutePath)

                $fileName -match $Pattern -or $link -match $Pattern
            } |
            Select-Object -Unique
    )

    if ($matchingLinks.Count -eq 0) {
        throw "No link matching '$Pattern' found on $Page"
    }

    # Prefer direct links to archives/installers over other matching URLs.
    return $matchingLinks[0]
}

# ---------------------------------------------------------------------------
# GitHub release discovery
# ---------------------------------------------------------------------------

function Get-GitHubLatestAsset {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$AssetPattern
    )

    $apiUri = "https://api.github.com/repos/$Repository/releases/latest"

    $release = Invoke-RestMethod `
        -Uri $apiUri `
        -Headers @{
            'Accept' = 'application/vnd.github+json'
            'User-Agent' = 'PowerShell-Setup-Script'
        } `
        -ErrorAction Stop

    $asset = @(
        $release.assets |
            Where-Object { $_.name -match $AssetPattern } |
            Select-Object -First 1
    )

    if ($asset.Count -eq 0) {
        throw "No asset matching '$AssetPattern' found in $Repository latest release."
    }

    return $asset[0].browser_download_url
}

# ---------------------------------------------------------------------------
# Portable tools
# ---------------------------------------------------------------------------

function Install-Zigup {
    $uri = 'https://github.com/marler8997/zigup/releases/latest/download/zigup-x86_64-windows.zip'
    $archive = Join-Path $script:Downloads 'zigup-x86_64-windows.zip'
    $destination = Join-Path $script:InstallRoot 'zigup-x86_64-windows'

    Save-Download -Uri $uri -Destination $archive
    Expand-DownloadedArchive -ArchivePath $archive -Destination $destination
    Remove-DownloadedArtifact -Path $archive
    Add-UserPath -Path $destination
}

function Install-AnyZig {
    $uri = 'https://github.com/marler8997/anyzig/releases/latest/download/anyzig-x86_64-windows.zip'
    $archive = Join-Path $script:Downloads 'anyzig-x86_64-windows.zip'
    $destination = Join-Path $script:InstallRoot 'anyzig-x86_64-windows'

    Save-Download -Uri $uri -Destination $archive
    Expand-DownloadedArchive -ArchivePath $archive -Destination $destination
    Remove-DownloadedArtifact -Path $archive
    Add-UserPath -Path $destination
}

function Install-AnyZls {
    $uri = 'https://github.com/marler8997/anyzig/releases/latest/download/anyzls-x86_64-windows.zip'
    $archive = Join-Path $script:Downloads 'anyzls-x86_64-windows.zip'
    $destination = Join-Path $script:InstallRoot 'anyzls-x86_64-windows'

    Save-Download -Uri $uri -Destination $archive
    Expand-DownloadedArchive -ArchivePath $archive -Destination $destination
    Remove-DownloadedArtifact -Path $archive
    Add-UserPath -Path $destination
}

function Install-Clangd {
    $uri = Get-GitHubLatestAsset `
        -Repository 'clangd/clangd' `
        -AssetPattern '^clangd-windows-.*\.zip$'

    $archive = Get-DownloadPath `
        -Uri $uri `
        -FallbackName 'clangd-windows.zip'

    Save-Download -Uri $uri -Destination $archive

    # clangd release archives contain a versioned directory, such as
    # clangd_snapshot_YYYYMMDD\bin.
    Expand-DownloadedArchive `
        -ArchivePath $archive `
        -Destination $script:InstallRoot
    Remove-DownloadedArtifact -Path $archive

    if (-not $script:DryRun) {
        $clangdBin = Get-ChildItem `
            -LiteralPath $script:InstallRoot `
            -Directory |
            Where-Object {
                $_.Name -like 'clangd_snapshot_*' -or
                $_.Name -like 'clangd*'
            } |
            ForEach-Object {
                Join-Path $_.FullName 'bin'
            } |
            Where-Object {
                Test-Path -LiteralPath (Join-Path $_ 'clangd.exe')
            } |
            Select-Object -First 1

        if ($clangdBin) {
            Add-UserPath -Path $clangdBin
        }
        else {
            Write-Log 'Could not locate clangd.exe after extraction.' 'WARN'
        }
    }
    else {
        Write-Log 'WHATIF: Locate clangd.exe and add its bin directory to PATH'
    }
}

function Install-LanXchange {
    $uri = 'https://github.com/tfg13/LanXchange/raw/master/releases/stable/lxc.zip'
    $archive = Join-Path $script:Downloads 'lxc.zip'
    $destination = 'C:\LanXchange'
    Save-Download -Uri $uri -Destination $archive
    Expand-DownloadedArchive -ArchivePath $archive -Destination $destination
    Remove-DownloadedArtifact -Path $archive
    New-StartMenuShortcut `
        -Name 'LanXChange' `
        -TargetPath (Join-Path $destination 'lxc.exe')
}

function Install-Rufus {
    $uri = Get-GitHubLatestAsset `
        -Repository 'pbatard/rufus' `
        -AssetPattern '^rufus-.*\.exe$'

    $destinationDirectory = Join-Path $script:InstallRoot 'Rufus'
    $destination = Join-Path $destinationDirectory (
        [IO.Path]::GetFileName(([uri]$uri).AbsolutePath)
    )

    if ($script:DryRun) {
        Write-Log "WHATIF: Create directory $destinationDirectory"
    }
    else {
        New-Item -ItemType Directory -Path $destinationDirectory -Force |
            Out-Null
    }

    Save-Download -Uri $uri -Destination $destination
    New-StartMenuShortcut `
        -Name 'Rufus' `
        -TargetPath $destination
}

function Install-PortableTools {
    foreach ($tool in $script:PortableTools) {
        if ($script:ExcludedPortableTools.Contains($tool)) {
            Write-Log "Skipping portable tool: $tool"
            continue
        }

        & "Install-$tool"
    }
}

# ---------------------------------------------------------------------------
# ARM GNU Toolchain
# ---------------------------------------------------------------------------

function Get-ArmMetadata {
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
    if (-not $curl) {
        throw 'curl.exe was not found; install or enable Windows curl before running Arm release discovery.'
    }

    $headersPath = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.headers')
    $bodyPath = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.body')
    try {
        $status = & $curl.Source -sS -L -D $headersPath -o $bodyPath -w '%{http_code}' $Uri
        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe failed with exit code $LASTEXITCODE while retrieving Arm metadata."
        }

        $headers = if (Test-Path -LiteralPath $headersPath) {
            Get-Content -LiteralPath $headersPath -Raw
        }
        else {
            ''
        }

        if ($headers -match '(?im)^x-amzn-waf-action:\s*challenge\s*$') {
            throw 'AWS WAF challenge detected; Arm GNU Toolchain release metadata was not retrieved.'
        }

        if ($status -ne '200') {
            throw "Arm metadata request returned HTTP $status."
        }

        return Get-Content -LiteralPath $bodyPath -Raw
    }
    finally {
        Remove-Item -LiteralPath $headersPath, $bodyPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-ArmLatestToolchainUrl {
    $readmeUri = 'https://gitlab.arm.com/tooling/gnu-toolchains-for-arm/-/raw/main/README.md'
    $readme = Get-ArmMetadata -Uri $readmeUri

    $releaseMatches = [regex]::Matches(
        $readme,
        '\[Arm GNU Toolchain (?<version>\d+\.\d+\.rel\d+)\]\(https://gitlab\.arm\.com/tooling/gnu-toolchains-for-arm/-/tree/releases/'
    )

    $releases = @(
        foreach ($match in $releaseMatches) {
            $match.Groups['version'].Value
        }
    )

    if ($releases.Count -eq 0) {
        throw 'No stable Arm GNU Toolchain releases were found in release metadata.'
    }

    $latest = $releases |
        Sort-Object {
            $version = [regex]::Match(
                $_,
                '^(?<major>\d+)\.(?<minor>\d+)\.rel(?<release>\d+)$'
            )
            [version]::new(
                [int]$version.Groups['major'].Value,
                [int]$version.Groups['minor'].Value,
                [int]$version.Groups['release'].Value
            )
        } -Descending |
        Select-Object -First 1
    $releaseReadmeUri = "https://gitlab.arm.com/tooling/gnu-toolchains-for-arm/-/raw/releases/$latest/README.md"
    $releaseReadme = Get-ArmMetadata -Uri $releaseReadmeUri
    $assetPattern = 'https://gitlab\.arm\.com/api/v4/projects/tooling%2Fgnu-toolchains-for-arm/packages/generic/gnu-toolchain/' +
        [regex]::Escape($latest) +
        '/(arm-gnu-toolchain-' + [regex]::Escape($latest) +
        '-mingw-w64-x86_64-[^/|]+\.zip)'
    $asset = [regex]::Match($releaseReadme, $assetPattern)

    if (-not $asset.Success) {
        throw "No Windows x86_64 Arm GNU Toolchain ZIP found for release $latest."
    }

    Write-Log "Selected latest Arm GNU Toolchain release $latest; asset $($asset.Groups[1].Value)"
    return $asset.Value
}

function Install-ArmToolchain {
    $uri = $ArmToolchainUrl

    if ([string]::IsNullOrWhiteSpace($uri)) {
        $uri = Get-ArmLatestToolchainUrl
    }
    else {
        $uriObject = $null

        if (-not [uri]::TryCreate(
            $uri,
            [UriKind]::Absolute,
            [ref]$uriObject
        ) -or $uriObject.Scheme -notin @('http', 'https')) {
            throw 'ArmToolchainUrl must be an absolute HTTP or HTTPS URL.'
        }
    }

    $archive = Get-DownloadPath `
        -Uri $uri `
        -FallbackName 'arm-gnu-toolchain-windows.zip'

    $destination = Join-Path $script:InstallRoot 'arm-gnu-toolchain'

    Save-Download -Uri $uri -Destination $archive
    Expand-DownloadedArchive -ArchivePath $archive -Destination $destination
    Remove-DownloadedArtifact -Path $archive

    if (-not $script:DryRun) {
        $binDirectory = Get-ChildItem `
            -LiteralPath $destination `
            -Directory |
            ForEach-Object {
                Join-Path $_.FullName 'bin'
            } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1

        if (-not $binDirectory) {
            $directBin = Join-Path $destination 'bin'

            if (Test-Path -LiteralPath $directBin) {
                $binDirectory = $directBin
            }
        }

        if ($binDirectory) {
            Add-UserPath -Path $binDirectory
        }
        else {
            Write-Log 'Could not find the ARM toolchain bin directory.' 'WARN'
        }
    }
    else {
        Write-Log 'WHATIF: Locate ARM toolchain bin directory and add it to PATH'
    }
}

# ---------------------------------------------------------------------------
# Rust
# ---------------------------------------------------------------------------

function Install-Rust {
    $uri = 'https://win.rustup.rs/'
    $installer = Join-Path $script:Downloads 'rustup-init.exe'

    Save-Download -Uri $uri -Destination $installer

    # Run rustup without '-y' so its installation prompts are interactive.
    Invoke-External `
        -FilePath $installer
    Remove-DownloadedArtifact -Path $installer

    $cargo = Join-Path $HOME '.cargo\bin\cargo.exe'

    if (-not $script:DryRun -and
        -not (Test-Path -LiteralPath $cargo -PathType Leaf)) {
        throw "Rust installation finished, but cargo.exe was not found at $cargo"
    }

    if (-not $script:DryRun) {
        Add-UserPath -Path (Split-Path -Parent $cargo)
    }
}

# ---------------------------------------------------------------------------
# VirtualBox
# ---------------------------------------------------------------------------

function Install-VirtualBox {

    $downloadsPage = 'https://www.virtualbox.org/wiki/Downloads'
    $uri = Get-PageLink `
        -Page $downloadsPage `
        -Pattern '^VirtualBox-[^/]+-Win\.exe$'

    $installer = Get-DownloadPath `
        -Uri $uri `
        -FallbackName 'VirtualBox-Win.exe'

    Save-Download -Uri $uri -Destination $installer

    Invoke-External `
        -FilePath $installer `
        -ArgumentList @('--silent', '--ignore-reboot') `
        -RunAs
    Remove-DownloadedArtifact -Path $installer

    $extensionPackUri = Get-PageLink `
        -Page $downloadsPage `
        -Pattern '^Oracle_VirtualBox_Extension_Pack-[^/]+\.vbox-extpack$'

    $extensionPack = Get-DownloadPath `
        -Uri $extensionPackUri `
        -FallbackName 'Oracle_VirtualBox_Extension_Pack.vbox-extpack'

    Save-Download -Uri $extensionPackUri -Destination $extensionPack

    $vboxManage = Get-Command 'VBoxManage.exe' -ErrorAction SilentlyContinue
    if ($vboxManage) {
        $vboxManagePath = $vboxManage.Source
    }
    else {
        $vboxManagePath = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
    }

    Invoke-External `
        -FilePath $vboxManagePath `
        -ArgumentList @('extpack', 'install', '--replace', $extensionPack) `
        -RunAs
    Remove-DownloadedArtifact -Path $extensionPack
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
    if (Test-Path -LiteralPath $script:LogPath) {
        if (-not $script:DryRun) {
            Clear-Content -LiteralPath $script:LogPath
        }
    }

    Write-Log 'Starting installation script.'

    if ($script:DryRun) {
        Write-Log 'Dry-run mode enabled. No files will be downloaded and no installers will run.'
    }

    Initialize-Directories

    if (-not $SkipWinget) {
        Invoke-InstallationStep -Name 'WinGet packages' -Action {
            Install-WingetPackages
        }
    }

    if (-not $SkipVisualStudio) {
        Invoke-InstallationStep -Name 'Visual Studio Community' -Action {
            Install-VisualStudio
        }
    }

    if (-not $SkipVSCodeExtensions) {
        Invoke-InstallationStep -Name 'VS Code extensions' -Action {
            Install-VSCodeExtensions
        }
    }

    Invoke-InstallationStep -Name 'Portable tools' -Action {
        Install-PortableTools
    }

    if (-not $SkipArmToolchain) {
        Invoke-InstallationStep -Name 'ARM GNU Toolchain' -Action {
            Install-ArmToolchain
        }
    }

    if (-not $SkipRust) {
        Invoke-InstallationStep -Name 'Rust and Cargo tool' -Action {
            Install-Rust
        }
    }

    if (-not $SkipVirtualBox) {
        Invoke-InstallationStep -Name 'VirtualBox' -Action {
            Install-VirtualBox
        }
    }

    if (-not $SkipShellConfiguration) {
        Invoke-InstallationStep -Name 'Nushell and zoxide configuration' -Action {
            Initialize-NushellConfiguration
        }
    }

    if (-not $SkipShortcuts) {
        Invoke-InstallationStep -Name 'Start Menu shortcuts' -Action {
            # Shortcut name = absolute path to the EXE.
            $shortcuts = [ordered]@{
                "Elden Ring" = "D:\Games\ELDEN RING\Game\eldenring.exe"
                "Need For Speed Most Wanted 2012" = "D:\Games\R.G. Catalyst\Need for Speed - Most Wanted\NFS13.exe"
                "Cyberpunk 2077" = "D:\Games\Cyberpunk 2077\bin\x64\Cyberpunk2077.exe"
            }

            foreach ($shortcut in $shortcuts.GetEnumerator()) {
                New-StartMenuShortcut `
                    -Name $shortcut.Key `
                    -TargetPath $shortcut.Value
            }
        }
    }
}
catch {
    Add-Failure -Name 'Fatal script error' -Exception $_.Exception
}
finally {
    Write-Log '---------------- Installation summary ----------------'
    Write-Log "Dry run: $($script:DryRun)"
    Write-Log "Completed steps: $($script:Successes.Count)"
    Write-Log "Failed steps: $($script:Failures.Count)"

    if ($script:Failures.Count -gt 0) {
        foreach ($failure in $script:Failures) {
            Write-Log -Level ERROR -Message $failure
        }

        Write-Log 'Installation finished with errors. Review install.log.'
    }
    elseif ($script:DryRun) {
        Write-Log 'Dry run finished. No installation was performed.'
    }
    else {
        Write-Log 'Installation script finished without reported errors.'
    }
}

if ($script:Failures.Count -gt 0) {
    exit 1
}
