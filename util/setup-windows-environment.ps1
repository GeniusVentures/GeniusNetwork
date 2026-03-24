# install-dev-stack.ps1
# Run in an elevated PowerShell window

$ErrorActionPreference = "Stop"

function Require-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this script as Administrator."
    }
}

function Require-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget was not found. Install/update App Installer first."
    }
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$Version,
        [string]$Override
    )

    Write-Host ""
    Write-Host "==> Installing $Id" -ForegroundColor Cyan

    $args = @(
        "install",
        "--id", $Id,
        "-e",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--source", "winget",
        "--silent",
        "--disable-interactivity"
    )

    if ($Version) {
        $args += @("--version", $Version)
    }

    if ($Override) {
        $args += @("--override", $Override)
    }

    & winget @args
}

function Normalize-PathEntry {
    param([string]$PathEntry)

    if ([string]::IsNullOrWhiteSpace($PathEntry)) { return $null }
    $trimmed = $PathEntry.Trim().TrimEnd('\')
    if ($trimmed.Length -eq 0) { return $null }
    return $trimmed
}

function Get-CombinedPathParts {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")

    $parts = @()
    if ($machinePath) { $parts += ($machinePath -split ';') }
    if ($userPath)    { $parts += ($userPath -split ';') }

    $seen = @{}
    $clean = New-Object System.Collections.Generic.List[string]

    foreach ($p in $parts) {
        $n = Normalize-PathEntry $p
        if ($null -ne $n) {
            $key = $n.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $clean.Add($n)
            }
        }
    }

    return $clean
}

function Set-MachinePathOrder {
    param(
        [string[]]$PriorityPaths,
        [string[]]$DeprioritizePaths
    )

    Write-Host ""
    Write-Host "==> Reordering machine PATH" -ForegroundColor Cyan

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $parts = $machinePath -split ';'

    $seen = @{}
    $clean = New-Object System.Collections.Generic.List[string]

    foreach ($p in $parts) {
        $n = Normalize-PathEntry $p
        if ($null -ne $n) {
            $key = $n.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $clean.Add($n)
            }
        }
    }

    $priorityNorm = @()
    foreach ($p in $PriorityPaths) {
        $n = Normalize-PathEntry $p
        if ($n) { $priorityNorm += $n }
    }

    $deprioritizeNorm = @()
    foreach ($p in $DeprioritizePaths) {
        $n = Normalize-PathEntry $p
        if ($n) { $deprioritizeNorm += $n }
    }

    $remaining = New-Object System.Collections.Generic.List[string]
    foreach ($p in $clean) {
        $lower = $p.ToLowerInvariant()
        $skip = $false

        foreach ($pp in $priorityNorm) {
            if ($lower -eq $pp.ToLowerInvariant()) { $skip = $true; break }
        }
        if (-not $skip) {
            foreach ($dp in $deprioritizeNorm) {
                if ($lower -eq $dp.ToLowerInvariant()) { $skip = $true; break }
            }
        }

        if (-not $skip) {
            $remaining.Add($p)
        }
    }

    $final = New-Object System.Collections.Generic.List[string]

    foreach ($p in $priorityNorm) {
        if (Test-Path $p) { $final.Add($p) }
    }

    foreach ($p in $remaining) {
        $final.Add($p)
    }

    foreach ($p in $deprioritizeNorm) {
        if (Test-Path $p) { $final.Add($p) }
    }

    $newMachinePath = ($final | Select-Object -Unique) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newMachinePath, "Machine")
}

function Ensure-UserPathContains {
    param([string[]]$PathsToAdd)

    Write-Host ""
    Write-Host "==> Ensuring user PATH has required entries" -ForegroundColor Cyan

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($userPath) { $parts += ($userPath -split ';') }

    $seen = @{}
    $clean = New-Object System.Collections.Generic.List[string]

    foreach ($p in $parts) {
        $n = Normalize-PathEntry $p
        if ($null -ne $n) {
            $key = $n.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $clean.Add($n)
            }
        }
    }

    foreach ($p in $PathsToAdd) {
        $n = Normalize-PathEntry $p
        if ($n -and (Test-Path $n)) {
            $key = $n.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $clean.Add($n)
            }
        }
    }

    $newUserPath = $clean -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
}

function Refresh-ProcessPath {
    Write-Host ""
    Write-Host "==> Refreshing PATH in current session" -ForegroundColor Cyan

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")

    if ([string]::IsNullOrWhiteSpace($userPath)) {
        $env:Path = $machinePath
    } else {
        $env:Path = "$machinePath;$userPath"
    }
}

function Show-CommandResolution {
    param([string]$CommandName)

    Write-Host ""
    Write-Host "==> Resolution for $CommandName" -ForegroundColor Cyan

    $all = Get-Command $CommandName -All -ErrorAction SilentlyContinue
    if ($all) {
        $all | ForEach-Object {
            Write-Host ("{0} -> {1}" -f $CommandName, $_.Source)
        }
    } else {
        Write-Host "$CommandName not found in current session." -ForegroundColor Yellow
    }
}

Require-Admin
Require-Winget

# Pick the Python minor version you want
$PythonId = "Python.Python.3.13"

# Install packages
Install-WingetPackage -Id $PythonId
Install-WingetPackage -Id "StrawberryPerl.StrawberryPerl"
Install-WingetPackage -Id "RubyInstallerTeam.Ruby.3.4"
Install-WingetPackage -Id "Kitware.CMake"
Install-WingetPackage -Id "Rustlang.Rustup"
Install-WingetPackage -Id "jqlang.jq"
Install-WingetPackage -Id "Git.Git"
Install-WingetPackage -Id "GitHub.cli"

# Visual Studio Build Tools 2022 with C++ tools
$vsOverride = "--passive --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools;includeRecommended"
Install-WingetPackage -Id "Microsoft.VisualStudio.2022.BuildTools" -Override $vsOverride

# Keep CMake ahead of Strawberry Perl's bundled tools
Set-MachinePathOrder `
    -PriorityPaths @(
        "C:\Program Files\CMake\bin"
    ) `
    -DeprioritizePaths @(
        "C:\Strawberry\c\bin"
    )

# Ensure rust/cargo user bin is present
Ensure-UserPathContains @(
    "$env:USERPROFILE\.cargo\bin"
)

# Refresh current session PATH so newly-installed tools work immediately
Refresh-ProcessPath

# Diagnostics
Show-CommandResolution -CommandName "cmake"
Show-CommandResolution -CommandName "perl"
Show-CommandResolution -CommandName "ruby"
Show-CommandResolution -CommandName "python"
Show-CommandResolution -CommandName "rustup"
Show-CommandResolution -CommandName "cargo"
Show-CommandResolution -CommandName "jq"
Show-CommandResolution -CommandName "git"
Show-CommandResolution -CommandName "gh"

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Recommended checks:" -ForegroundColor Cyan
Write-Host "  where.exe cmake"
Write-Host "  cmake --version"
Write-Host "  rustup --version"
Write-Host "  cargo --version"
Write-Host "  jq --version"
Write-Host "  git --version"
Write-Host "  gh --version"