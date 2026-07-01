# install-docker-windows-containers.ps1
# Run from an elevated PowerShell window.

$ErrorActionPreference = "Stop"

# Set this to the full path of THIS script before first run if you want auto-resume after reboot.
# Example:
# $ScriptSelf = "C:\setup\install-docker-windows-containers.ps1"
$ScriptSelf = $MyInvocation.MyCommand.Path

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

function Get-EditionInfo {
    $os = Get-ComputerInfo
    [PSCustomObject]@{
        ProductName   = $os.WindowsProductName
        EditionId     = $os.WindowsEditionId
        OsVersion     = $os.OsVersion
        OsBuildNumber = $os.OsBuildNumber
    }
}

function Assert-SupportedEdition {
    $info = Get-EditionInfo
    Write-Host "Windows: $($info.ProductName) ($($info.EditionId)) build $($info.OsBuildNumber)" -ForegroundColor Cyan

    $edition = ($info.EditionId | Out-String).Trim()
    if ($edition -notmatch 'Professional|Enterprise|Pro') {
        throw "Windows containers on Docker Desktop require Windows Pro or Enterprise. Current edition: $edition"
    }
}

function Enable-FeatureIfNeeded {
    param(
        [Parameter(Mandatory=$true)][string]$FeatureName
    )

    $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop

    if ($feature.State -eq "Enabled") {
        Write-Host "Feature already enabled: $FeatureName" -ForegroundColor DarkGreen
        return $false
    }

    Write-Host "Enabling feature: $FeatureName" -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -All -NoRestart | Out-Null
    return $true
}

function Register-RunOnceResume {
    param(
        [Parameter(Mandatory=$true)][string]$ScriptPath
    )

    if (-not $ScriptPath) {
        throw "Could not determine script path for resume."
    }

    $cmd = "powershell.exe -ExecutionPolicy Bypass -File `"$ScriptPath`" -Resume"
    New-ItemProperty `
        -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
        -Name "DockerWindowsContainersBootstrap" `
        -Value $cmd `
        -PropertyType String `
        -Force | Out-Null

    Write-Host "Registered RunOnce resume." -ForegroundColor Green
}

function Clear-RunOnceResume {
    Remove-ItemProperty `
        -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
        -Name "DockerWindowsContainersBootstrap" `
        -ErrorAction SilentlyContinue
}

function Ensure-WSLInstalled {
    Write-Host "Installing/updating WSL..." -ForegroundColor Cyan
    # Safe to run repeatedly
    & wsl.exe --install --no-distribution
    & wsl.exe --update
    # Prefer WSL 2 by default
    & wsl.exe --set-default-version 2
}

function Install-DockerDesktop {
    Require-Winget
    Write-Host "Installing Docker Desktop..." -ForegroundColor Cyan

    & winget install `
        --id Docker.DockerDesktop `
        -e `
        --accept-package-agreements `
        --accept-source-agreements `
        --silent `
        --disable-interactivity
}

function Start-DockerDesktop {
    $dockerDesktopExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (-not (Test-Path $dockerDesktopExe)) {
        throw "Docker Desktop executable not found at: $dockerDesktopExe"
    }

    Write-Host "Starting Docker Desktop..." -ForegroundColor Cyan
    Start-Process -FilePath $dockerDesktopExe | Out-Null
}

function Wait-ForDockerDesktopCli {
    $timeoutSeconds = 180
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()

    Write-Host "Waiting for Docker Desktop CLI..." -ForegroundColor Cyan
    while ($stopwatch.Elapsed.TotalSeconds -lt $timeoutSeconds) {
        $cmd = Get-Command docker -ErrorAction SilentlyContinue
        if ($cmd) {
            try {
                & docker desktop version *> $null
                return
            } catch {
            }
        }
        Start-Sleep -Seconds 3
    }

    throw "Docker Desktop CLI did not become ready within $timeoutSeconds seconds."
}

function Switch-ToWindowsContainers {
    Write-Host "Switching Docker Desktop to Windows containers..." -ForegroundColor Cyan
    & docker desktop engine use windows
}

function Show-Verification {
    Write-Host ""
    Write-Host "Verification:" -ForegroundColor Cyan

    try { & wsl.exe --status } catch {}
    try { & docker desktop engine ls } catch {}
    try { & docker info } catch {}
    try { & docker version } catch {}

    Write-Host ""
    Write-Host "Useful checks:" -ForegroundColor Cyan
    Write-Host "  docker desktop engine ls"
    Write-Host "  docker info"
    Write-Host "  docker run --isolation=hyperv mcr.microsoft.com/windows/nanoserver:ltsc2022 cmd /c ver"
}

param(
    [switch]$Resume
)

Require-Admin
Assert-SupportedEdition

if (-not $Resume) {
    $rebootNeeded = $false

    $rebootNeeded = (Enable-FeatureIfNeeded -FeatureName "Microsoft-Windows-Subsystem-Linux") -or $rebootNeeded
    $rebootNeeded = (Enable-FeatureIfNeeded -FeatureName "VirtualMachinePlatform") -or $rebootNeeded
    $rebootNeeded = (Enable-FeatureIfNeeded -FeatureName "Microsoft-Hyper-V-All") -or $rebootNeeded
    $rebootNeeded = (Enable-FeatureIfNeeded -FeatureName "Containers") -or $rebootNeeded

    Ensure-WSLInstalled

    if ($rebootNeeded) {
        Write-Host ""
        Write-Host "A reboot is required before Docker Desktop install/config continues." -ForegroundColor Yellow
        Register-RunOnceResume -ScriptPath $ScriptSelf
        Restart-Computer -Force
        exit
    }
}

Clear-RunOnceResume
Install-DockerDesktop
Start-DockerDesktop
Wait-ForDockerDesktopCli
Switch-ToWindowsContainers
Show-Verification

Write-Host ""
Write-Host "Done." -ForegroundColor Green