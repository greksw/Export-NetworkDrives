[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path -Path (Get-Location) -ChildPath 'network-drive-mappings.csv'),

    [Parameter()]
    [switch]$IncludeOfflineProfiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-AccountName {
    param(
        [Parameter(Mandatory)]
        [string]$Sid,

        [Parameter(Mandatory)]
        [string]$ProfilePath
    )

    try {
        $securityIdentifier = New-Object System.Security.Principal.SecurityIdentifier($Sid)
        return $securityIdentifier.Translate([System.Security.Principal.NTAccount]).Value
    }
    catch {
        return [System.IO.Path]::GetFileName($ProfilePath.TrimEnd('\'))
    }
}

function Get-NetworkDriveMappingsFromHive {
    param(
        [Parameter(Mandatory)]
        [string]$HiveRoot,

        [Parameter(Mandatory)]
        [string]$Sid,

        [Parameter(Mandatory)]
        [string]$AccountName,

        [Parameter(Mandatory)]
        [string]$ProfileName,

        [Parameter(Mandatory)]
        [bool]$ProfileLoaded
    )

    $networkPath = Join-Path -Path $HiveRoot -ChildPath 'Network'
    if (-not (Test-Path -LiteralPath $networkPath)) {
        return
    }

    foreach ($driveKey in Get-ChildItem -LiteralPath $networkPath -ErrorAction Stop) {
        $driveLetter = $driveKey.PSChildName.ToUpperInvariant()
        if ($driveLetter -notmatch '^[A-Z]$') {
            Write-Warning "Ignoring invalid drive key '$driveLetter' for $AccountName."
            continue
        }

        $properties = Get-ItemProperty -LiteralPath $driveKey.PSPath -ErrorAction Stop
        $remotePath = [string]$properties.RemotePath
        if ([string]::IsNullOrWhiteSpace($remotePath) -or $remotePath -notmatch '^\\\\[^\\]+\\[^\\]+') {
            Write-Warning "Ignoring invalid UNC path for $AccountName $driveLetter`: $remotePath"
            continue
        }

        [PSCustomObject][ordered]@{
            SchemaVersion         = 1
            SourceComputer        = $env:COMPUTERNAME
            SourceSid             = $Sid
            AccountName           = $AccountName
            ProfileName           = $ProfileName
            ProfileLoadedAtExport = $ProfileLoaded
            DriveLetter           = "$driveLetter`:"
            RemotePath            = $remotePath
        }
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'This script requires Windows.'
}

if ($IncludeOfflineProfiles -and -not (Test-IsAdministrator)) {
    throw '-IncludeOfflineProfiles requires an elevated PowerShell session.'
}

$outputDirectory = Split-Path -Path $OutputPath -Parent
if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
    $outputDirectory = (Get-Location).Path
}
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$profileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$results = @()

foreach ($profileKey in Get-ChildItem -LiteralPath $profileListPath) {
    $sid = $profileKey.PSChildName
    if ($sid -notmatch '^S-1-5-21-(\d+-){3}\d+$') {
        continue
    }

    $profileProperties = Get-ItemProperty -LiteralPath $profileKey.PSPath
    $profilePath = [Environment]::ExpandEnvironmentVariables([string]$profileProperties.ProfileImagePath)
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        continue
    }

    $profileName = [System.IO.Path]::GetFileName($profilePath.TrimEnd('\'))
    $accountName = Resolve-AccountName -Sid $sid -ProfilePath $profilePath
    $loadedHive = "Registry::HKEY_USERS\$sid"

    if (Test-Path -LiteralPath $loadedHive) {
        $results += @(Get-NetworkDriveMappingsFromHive -HiveRoot $loadedHive -Sid $sid -AccountName $accountName -ProfileName $profileName -ProfileLoaded $true)
        continue
    }

    if (-not $IncludeOfflineProfiles) {
        continue
    }

    $ntUserDat = Join-Path -Path $profilePath -ChildPath 'NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $ntUserDat -PathType Leaf)) {
        Write-Warning "Skipping $accountName because NTUSER.DAT was not found."
        continue
    }

    $mountName = 'NDM_' + ($sid -replace '[^A-Za-z0-9]', '_')
    $mounted = $false
    try {
        & reg.exe load "HKU\$mountName" $ntUserDat | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "reg.exe load failed with exit code $LASTEXITCODE"
        }
        $mounted = $true
        $mountedHive = "Registry::HKEY_USERS\$mountName"
        $results += @(Get-NetworkDriveMappingsFromHive -HiveRoot $mountedHive -Sid $sid -AccountName $accountName -ProfileName $profileName -ProfileLoaded $false)
    }
    catch {
        Write-Warning "Unable to inspect offline profile $accountName: $($_.Exception.Message)"
    }
    finally {
        if ($mounted) {
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            & reg.exe unload "HKU\$mountName" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Unable to unload temporary registry hive HKU\$mountName."
            }
        }
    }
}

$results = @($results | Sort-Object AccountName, DriveLetter, RemotePath -Unique)
$results | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

Write-Output ([PSCustomObject]@{
    OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    MappingCount = $results.Count
    OfflineProfilesIncluded = [bool]$IncludeOfflineProfiles
})
