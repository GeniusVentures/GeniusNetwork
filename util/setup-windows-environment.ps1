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

function Ensure-Chocolatey {
    $choco = Get-Command choco -ErrorAction SilentlyContinue

    if ($choco) {
        Write-Host ""
        Write-Host "==> Chocolatey already installed" -ForegroundColor DarkGreen
    } else {
        Write-Host ""
        Write-Host "==> Installing Chocolatey" -ForegroundColor Cyan

        # Official installer script from community.chocolatey.org (requires elevation).
        # Run it in a child process so its state changes cannot pollute this script,
        # then rebuild this session's PATH from the machine PATH it updated
        # (choco.exe lands in C:\ProgramData\chocolatey\bin).
        $chocoInstallScript = Join-Path $env:TEMP "chocolatey-install.ps1"
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri "https://community.chocolatey.org/install.ps1" `
                -OutFile $chocoInstallScript -UseBasicParsing
        } finally {
            $ProgressPreference = 'Continue'
        }

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $chocoInstallScript
        if ($LASTEXITCODE -ne 0) {
            throw "Chocolatey installer exited with code $LASTEXITCODE."
        }

        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine")
    }

    # Auto-confirm every choco operation (equivalent of always passing -y).
    # Runs on reruns too, so an existing install converges to the same state.
    & choco feature enable -n allowGlobalConfirmation | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to enable choco feature allowGlobalConfirmation (exit $LASTEXITCODE)."
    }
    Write-Host "==> choco allowGlobalConfirmation enabled" -ForegroundColor DarkGreen
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

function Ensure-MachinePathContains {
    param([string[]]$PathsToAdd)

    Write-Host ""
    Write-Host "==> Ensuring machine PATH has required entries" -ForegroundColor Cyan

    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $parts = @()
    if ($machinePath) { $parts += ($machinePath -split ';') }

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

    $newMachinePath = $clean -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newMachinePath, "Machine")
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

function Test-JdkUsable {
    param([string]$JdkHome)

    if (-not $JdkHome) { return $false }

    # The jni plugin's CMake FindJNI needs the JNI headers and jvm.lib...
    if (-not (Test-Path (Join-Path $JdkHome "include\jni.h"))) { return $false }

    # ...and Gradle / Android Gradle Plugin 8+ need JDK 17 or newer. Machines
    # with a newer manual install (e.g. Temurin 25 LTS) are perfectly fine and
    # are kept as-is instead of gaining a second side-by-side JDK.
    $releaseFile = Join-Path $JdkHome "release"
    if (Test-Path $releaseFile) {
        $match = [regex]::Match((Get-Content $releaseFile -Raw), 'JAVA_VERSION="(\d+)')
        if ($match.Success -and ([int]$match.Groups[1].Value -lt 17)) {
            return $false
        }
    }

    return $true
}

function Get-AdoptiumJdkHome {
    # 1) Existing machine-wide JAVA_HOME that still points at a usable JDK
    $javaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "Machine")
    if (Test-JdkUsable $javaHome) {
        return $javaHome
    }

    # 2) Temurin MSI registry keys (the same keys CMake's FindJNI reads)
    $jdkRegKey = "HKLM:\SOFTWARE\JavaSoft\JDK"
    if (Test-Path $jdkRegKey) {
        $candidates = Get-ChildItem $jdkRegKey |
            Where-Object { $_.PSChildName -match '^\d+(\.\d+)*$' } |
            Sort-Object { [version]$_.PSChildName } -Descending
        foreach ($c in $candidates) {
            $home = (Get-ItemProperty -Path $c.PSPath -Name "JavaHome" -ErrorAction SilentlyContinue).JavaHome
            if (Test-JdkUsable $home) {
                return $home
            }
        }
    }

    # 3) Newest jdk-* directory under the default Adoptium install root
    $adoptiumRoot = Join-Path $env:ProgramFiles "Eclipse Adoptium"
    if (Test-Path $adoptiumRoot) {
        $candidates = Get-ChildItem $adoptiumRoot -Directory |
            Where-Object { $_.Name -match '^jdk-([\d.]+)' } |
            Sort-Object { [version]([regex]::Match($_.Name, '^jdk-([\d.]+)').Groups[1].Value) } -Descending
        foreach ($c in $candidates) {
            if (Test-JdkUsable $c.FullName) {
                return $c.FullName
            }
        }
    }

    return $null
}

function Ensure-JavaHome {
    Write-Host ""
    Write-Host "==> Setting machine-wide JAVA_HOME and adding JDK bin to system PATH" -ForegroundColor Cyan

    $jdkHome = Get-AdoptiumJdkHome
    if (-not $jdkHome) {
        throw "Could not locate the Temurin JDK install directory (expected an Eclipse Adoptium JDK with include\jni.h)."
    }

    Write-Host "JDK home: $jdkHome"

    # MACHINE scope, not user scope: the GitHub Actions runner service only
    # inherits machine environment variables, so a per-user JAVA_HOME makes CI
    # fail intermittently depending on which user/session defined it.
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $jdkHome, "Machine")

    # Expose to the current session for the diagnostics below
    $env:JAVA_HOME = $jdkHome

    # A user-scope JAVA_HOME shadows the machine one for that user's sessions,
    # which is the suspected cause of A7_MAX's intermittent JNI failures.
    # Flag it instead of deleting it - it may have been set on purpose.
    $userJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", "User")
    if ($userJavaHome -and ($userJavaHome -ne $jdkHome)) {
        Write-Host "WARNING: a user-scope JAVA_HOME is also set ($userJavaHome)." -ForegroundColor Yellow
        Write-Host "         It shadows the machine value for that user's sessions - consider removing it." -ForegroundColor Yellow
    }

    # The literal JDK bin path (not "%JAVA_HOME%\bin") is used because this
    # script rewrites PATH through the .NET environment APIs, which read and
    # write expanded values and would corrupt an unexpanded %JAVA_HOME% entry.
    Ensure-MachinePathContains @((Join-Path $jdkHome "bin"))
}

function Ensure-VsBuildToolsAtl {
    Write-Host ""
    Write-Host "==> Ensuring VS Build Tools 2022 has the C++ ATL component" -ForegroundColor Cyan

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        Write-Host "vswhere.exe not found - cannot check the ATL component." -ForegroundColor Yellow
        return
    }

    $installPath = (& $vswhere -products Microsoft.VisualStudio.Product.BuildTools -version "[17.0,18.0)" -property installationPath |
        Where-Object { $_ } |
        Select-Object -First 1)
    if (-not $installPath) {
        Write-Host "VS Build Tools 2022 not found - skipping ATL check." -ForegroundColor Yellow
        return
    }

    $atlInstalled = (& $vswhere -products Microsoft.VisualStudio.Product.BuildTools -version "[17.0,18.0)" `
        -requires Microsoft.VisualStudio.Component.VC.ATL -property installationPath |
        Where-Object { $_ })
    if ($atlInstalled) {
        Write-Host "ATL component already installed." -ForegroundColor DarkGreen
        return
    }

    # ATL is missing (CI symptom: error C1083 "Cannot open include file:
    # 'atlstr.h'"). winget does not run the VS installer on machines that
    # already had Build Tools, so modify the existing instance directly.
    $setupExe = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\setup.exe"
    Write-Host "Adding Microsoft.VisualStudio.Component.VC.ATL to $installPath"
    & $setupExe modify --installPath "$installPath" `
        --add Microsoft.VisualStudio.Component.VC.ATL `
        --passive --norestart --wait
    if ($LASTEXITCODE -notin @(0, 3010, 1641)) {
        throw "VS setup.exe modify (ATL) exited with code $LASTEXITCODE."
    }
    Write-Host "==> ATL component installed (exit $LASTEXITCODE)." -ForegroundColor DarkGreen
}

function Restart-ActionsRunnerService {
    Write-Host ""
    Write-Host "==> Restarting GitHub Actions runner service (if present)" -ForegroundColor Cyan

    # The runner service reads machine environment variables only when it
    # starts, so the new JAVA_HOME/PATH only reach CI jobs after a restart.
    $runnerServices = @(Get-Service |
        Where-Object { $_.Name -like "actions.runner*" -or $_.DisplayName -like "*GitHub Actions Runner*" })

    if ($runnerServices.Count -eq 0) {
        Write-Host "No GitHub Actions runner service found - skipping." -ForegroundColor Yellow
        return
    }

    foreach ($svc in $runnerServices) {
        try {
            Restart-Service -Name $svc.Name -Force -ErrorAction Stop
            Write-Host "Restarted '$($svc.DisplayName)' ($($svc.Name))" -ForegroundColor DarkGreen
        } catch {
            Write-Host "Could not restart '$($svc.Name)': $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

Require-Admin
Require-Winget

# Pick the Python minor version you want
$PythonId = "Python.Python.3.13"

# Temurin JDK for the jni plugin / CMake FindJNI (17 = minimum supported)
$TemurinId = "EclipseAdoptium.Temurin.17.JDK"

# Install packages
Install-WingetPackage -Id $PythonId
Install-WingetPackage -Id "StrawberryPerl.StrawberryPerl"
Install-WingetPackage -Id "RubyInstallerTeam.Ruby.3.4"
Install-WingetPackage -Id "Kitware.CMake"
Install-WingetPackage -Id "Rustlang.Rustup"
Install-WingetPackage -Id "jqlang.jq"
Install-WingetPackage -Id "Git.Git"
Install-WingetPackage -Id "GitHub.cli"

# JDK for the jni Flutter plugin's CMake FindJNI
# ("Could NOT find JNI (missing: JAVA_INCLUDE_PATH JAVA_INCLUDE_PATH2 JVM)").
# Any JDK 17+ satisfies CI, so if a machine already has one (e.g. an older
# runner with a manual Temurin 25 LTS install) it is kept as-is instead of
# installing a second JDK side by side.
if (Get-AdoptiumJdkHome) {
    Write-Host ""
    Write-Host "==> JDK already present ($(Get-AdoptiumJdkHome)) - skipping Temurin install" -ForegroundColor DarkGreen
} else {
    Install-WingetPackage -Id $TemurinId
}

# Visual Studio Build Tools 2022 with C++ tools. ATL is included because some
# build steps need atlstr.h and CI hit C1083 "Cannot open include file:
# 'atlstr.h'" on runners provisioned before this component was added.
$vsOverride = "--passive --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools;includeRecommended --add Microsoft.VisualStudio.Component.VC.ATL"
Install-WingetPackage -Id "Microsoft.VisualStudio.2022.BuildTools" -Override $vsOverride

# CI build scripts use "choco install ..."
Ensure-Chocolatey

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

# Machine-wide JAVA_HOME + JDK on the SYSTEM PATH. The runner service only
# sees machine environment variables, which is why per-user JDK installs
# caused intermittent "Could NOT find JNI" failures.
Ensure-JavaHome

# Converge pre-existing Build Tools installs that winget skipped (fresh
# installs already get ATL through the winget override above).
Ensure-VsBuildToolsAtl

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
Show-CommandResolution -CommandName "choco"
Show-CommandResolution -CommandName "java"

# The runner service only reads machine environment variables when it starts,
# so restart it to expose the new JAVA_HOME/PATH to CI jobs.
Restart-ActionsRunnerService

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Recommended checks:" -ForegroundColor Cyan
Write-Host "  choco --version"
Write-Host "  where.exe cmake"
Write-Host "  cmake --version"
Write-Host "  rustup --version"
Write-Host "  cargo --version"
Write-Host "  jq --version"
Write-Host "  git --version"
Write-Host "  gh --version"
Write-Host "  java -version"
Write-Host "  echo $env:JAVA_HOME"