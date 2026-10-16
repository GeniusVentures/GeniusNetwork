# install-docker-windows-containers.ps1
# Run from an elevated PowerShell window.

param(
    [switch]$Resume
)

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

function Test-DockerUsersToken {
    # Returns $true only if the CURRENT logon token contains docker-users.
    # Group membership granted mid-session does NOT appear in the running token -
    # that is what produces "checking group membership: user is not a member of
    # the group" and Docker Desktop exiting shortly after startup.
    try {
        $groupSid = (Get-LocalGroup -Name 'docker-users' -ErrorAction Stop).SID.Value
        foreach ($g in [Security.Principal.WindowsIdentity]::GetCurrent().Groups) {
            try {
                if ($g.Translate([Security.Principal.SecurityIdentifier]).Value -eq $groupSid) {
                    return $true
                }
            } catch {}
        }
    } catch {}
    return $false
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
    Write-Host "Installing Docker Desktop (all-users, Windows containers enabled)..." -ForegroundColor Cyan

    $installerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
    $installerPath = Join-Path $env:TEMP "Docker Desktop Installer.exe"
    $alreadyInstalled = Test-Path "C:\Program Files\Docker\Docker\Docker Desktop.exe"

    if (-not (Test-Path $installerPath)) {
        Write-Host "Downloading Docker Desktop Installer (~560 MB)..." -ForegroundColor Cyan
        # PS 5.1 renders a progress-bar update per chunk, throttling Invoke-WebRequest
        # by 10-50x. Disable progress display for the download. Download to a .partial
        # file first so an interrupted run isn't mistaken for a complete installer.
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $installerUrl -OutFile "$installerPath.partial" -UseBasicParsing
            Move-Item "$installerPath.partial" $installerPath -Force
        } finally {
            $ProgressPreference = 'Continue'
        }
    }

    # All-users install (per-user installs do NOT support Windows containers).
    # --always-run-service: com.docker.service is required by the Windows containers engine.
    if (-not $alreadyInstalled) {
        $process = Start-Process -FilePath $installerPath -Wait -PassThru -ArgumentList `
            'install',
            '--accept-license',
            '--quiet',
            '--always-run-service',
            '--backend=wsl-2'
        if ($process.ExitCode -ne 0) {
            throw "Docker Desktop installer exited with code $($process.ExitCode)."
        }
    }

    # Windows containers (all-users install) require the invoking user to be in
    # the docker-users group. The INTERACTIVE installer adds the installing user
    # silently; silent installs do NOT - so do it explicitly, verifying by SID.
    $accountSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $accountName = "$env:USERDOMAIN\$env:USERNAME"
    $group = Get-LocalGroup -Name 'docker-users' -ErrorAction Stop
    $isMember = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue |
        Where-Object { $_.SID.Value -eq $accountSid }
    if (-not $isMember) {
        Add-LocalGroupMember -Group $group -Member $accountName -ErrorAction Stop
        Write-Host "Added '$accountName' to docker-users." -ForegroundColor Green
    } else {
        Write-Host "'$accountName' is already in docker-users." -ForegroundColor DarkGreen
    }
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
    $timeoutSeconds = 600
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()

    # The Docker installer updates the machine PATH, but this process inherited its
    # environment before the install, so refresh PATH before probing for docker.
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"

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

    # The command above only initiates the switch and can report
    # "starting engine: starting vm: context canceled" while the first boot
    # of the Windows engine is still in progress. Poll until the daemon
    # actually reports OSType=windows (first start can take several minutes).
    $timeoutSeconds = 600
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    Write-Host "Waiting for the Windows engine to become ready (first start can take several minutes)..." -ForegroundColor Cyan
    while ($stopwatch.Elapsed.TotalSeconds -lt $timeoutSeconds) {
        $osType = & docker info --format '{{.OSType}}' 2>$null
        if ($LASTEXITCODE -eq 0 -and "$osType" -match 'windows') {
            Write-Host "Windows engine is ready." -ForegroundColor Green
            return
        }
        Start-Sleep -Seconds 5
    }
    Write-Warning "Windows engine did not report ready within $timeoutSeconds seconds. Check the Docker Desktop GUI."
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

if (-not (Test-DockerUsersToken)) {
    Write-Host ""
    Write-Host "SIGN-OUT REQUIRED: the current logon session predates the docker-users" -ForegroundColor Yellow
    Write-Host "group membership, and Windows only applies group membership to NEW logon" -ForegroundColor Yellow
    Write-Host "sessions. Docker Desktop would fail its startup group check and exit." -ForegroundColor Yellow
    Write-Host "Sign out and sign back in - this script resumes automatically at logon." -ForegroundColor Yellow
    Register-RunOnceResume -ScriptPath $ScriptSelf
    exit
}

Start-DockerDesktop
Wait-ForDockerDesktopCli
Switch-ToWindowsContainers
Show-Verification

Write-Host ""
Write-Host "Done." -ForegroundColor Green