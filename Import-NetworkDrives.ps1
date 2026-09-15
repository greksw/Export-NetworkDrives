#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath = (Join-Path -Path (Get-Location) -ChildPath 'network-drive-mappings.csv'),

    [Parameter()]
    [string]$SourceSid,

    [Parameter()]
    [string]$SourceAccountName,

    [Parameter()]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter()]
    [switch]$PromptForCredential,

    [Parameter()]
    [switch]$ReplaceExisting
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-ValidMapping {
    param(
        [Parameter(Mandatory)]
        [psobject]$Mapping
    )

    if ([string]$Mapping.SchemaVersion -ne '1') {
        throw "Unsupported schema version '$($Mapping.SchemaVersion)'."
    }

    $driveLetter = ([string]$Mapping.DriveLetter).Trim().ToUpperInvariant()
    if ($driveLetter -notmatch '^[A-Z]:$') {
        throw "Invalid drive letter '$driveLetter'."
    }

    $remotePath = ([string]$Mapping.RemotePath).Trim()
    if ($remotePath -notmatch '^\\\\[^\\]+\\[^\\]+') {
        throw "Invalid UNC path '$remotePath'."
    }

    return [PSCustomObject]@{
        DriveLetter = $driveLetter
        DriveName = $driveLetter.Substring(0, 1)
        RemotePath = $remotePath
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'This script requires Windows.'
}

if ($PromptForCredential -and $null -ne $Credential) {
    throw 'Use either -Credential or -PromptForCredential, not both.'
}

if ($SourceSid -and $SourceAccountName) {
    throw 'Use either -SourceSid or -SourceAccountName, not both.'
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Input file not found: $InputPath"
}

$rows = @(Import-Csv -LiteralPath $InputPath)
if ($rows.Count -eq 0) {
    throw 'The input CSV does not contain any mappings.'
}

$requiredColumns = @('SchemaVersion', 'SourceSid', 'AccountName', 'DriveLetter', 'RemotePath')
foreach ($column in $requiredColumns) {
    if (-not ($rows[0].PSObject.Properties.Name -contains $column)) {
        throw "Required CSV column is missing: $column"
    }
}

if ($SourceSid) {
    $selectedRows = @($rows | Where-Object { $_.SourceSid -eq $SourceSid })
}
elseif ($SourceAccountName) {
    $selectedRows = @($rows | Where-Object { $_.AccountName -eq $SourceAccountName })
}
else {
    $identities = @($rows | Select-Object SourceSid, AccountName -Unique)
    if ($identities.Count -ne 1) {
        $available = ($identities | ForEach-Object { "$($_.AccountName) [$($_.SourceSid)]" }) -join ', '
        throw "The CSV contains mappings for multiple source users. Specify -SourceSid or -SourceAccountName. Available: $available"
    }
    $selectedRows = $rows
}

if ($selectedRows.Count -eq 0) {
    throw 'No mappings matched the selected source user.'
}

$validatedMappings = @(
    foreach ($row in $selectedRows) {
        $mapping = Assert-ValidMapping -Mapping $row
        [PSCustomObject]@{
            SourceRow = $row
            DriveLetter = $mapping.DriveLetter
            DriveName = $mapping.DriveName
            RemotePath = $mapping.RemotePath
        }
    }
)

$duplicateLetters = @(
    $validatedMappings |
        Group-Object DriveLetter |
        Where-Object Count -gt 1
)
if ($duplicateLetters.Count -gt 0) {
    $duplicates = ($duplicateLetters | ForEach-Object Name) -join ', '
    throw "The selected mappings contain duplicate drive letters: $duplicates"
}

if ($PromptForCredential) {
    $Credential = Get-Credential -Message 'Enter SMB credentials for the network drive mappings.'
}

$stats = [ordered]@{
    Total = $validatedMappings.Count
    Created = 0
    Replaced = 0
    Skipped = 0
    Failed = 0
}

foreach ($mapping in $validatedMappings) {
    try {
        $existing = Get-PSDrive -Name $mapping.DriveName -ErrorAction SilentlyContinue

        if ($null -ne $existing) {
            $existingRoot = [string]$existing.Root
            if ($existing.Provider.Name -eq 'FileSystem' -and $existingRoot -eq $mapping.RemotePath) {
                Write-Verbose "$($mapping.DriveLetter) is already mapped to $($mapping.RemotePath)."
                $stats.Skipped++
                continue
            }

            if (-not $ReplaceExisting) {
                Write-Warning "$($mapping.DriveLetter) is already in use by '$existingRoot'; skipping. Use -ReplaceExisting to replace it explicitly."
                $stats.Skipped++
                continue
            }

            if ($PSCmdlet.ShouldProcess($mapping.DriveLetter, "Remove existing drive '$existingRoot'")) {
                Remove-PSDrive -Name $mapping.DriveName -Force -ErrorAction Stop
                $stats.Replaced++
            }
            else {
                $stats.Skipped++
                continue
            }
        }

        if ($PSCmdlet.ShouldProcess($mapping.DriveLetter, "Map to $($mapping.RemotePath)")) {
            $parameters = @{
                Name = $mapping.DriveName
                PSProvider = 'FileSystem'
                Root = $mapping.RemotePath
                Persist = $true
                Scope = 'Global'
                ErrorAction = 'Stop'
            }
            if ($null -ne $Credential) {
                $parameters.Credential = $Credential
            }

            New-PSDrive @parameters | Out-Null
            $stats.Created++
            Write-Verbose "Mapped $($mapping.DriveLetter) to $($mapping.RemotePath)."
        }
        else {
            $stats.Skipped++
        }
    }
    catch {
        $stats.Failed++
        Write-Error "Failed to process mapping '$($mapping.DriveLetter)' -> '$($mapping.RemotePath)': $($_.Exception.Message)" -ErrorAction Continue
    }
}

[PSCustomObject]$stats

if ($stats.Failed -gt 0) {
    throw "$($stats.Failed) network drive mapping(s) failed."
}
