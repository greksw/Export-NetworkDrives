# Windows Network Drive Migration

A small PowerShell toolkit for exporting persistent SMB drive mappings from Windows user profiles and recreating them safely in another Windows user session.

The repository started as two ad-hoc scripts for copying mapped drives between profiles. Version 2 keeps the useful operational idea while removing password exposure, validating input, supporting offline profile inspection, and making destructive replacement explicit.

## What it does

- exports persistent mapped-drive metadata from loaded Windows profiles;
- optionally inspects offline profiles by temporarily loading their `NTUSER.DAT` hive;
- records source SID, account name, drive letter, and UNC path in a versioned CSV schema;
- imports mappings for one selected source identity into the current Windows user session;
- uses `New-PSDrive -Persist -Scope Global` rather than constructing `cmd.exe /c net use` command lines;
- never exports or writes SMB passwords to CSV;
- accepts an optional `PSCredential` object or prompts interactively when alternate SMB credentials are required;
- validates drive letters and UNC paths before changing the system;
- refuses ambiguous multi-user imports unless a source SID or source account is selected;
- refuses duplicate drive letters in the selected migration set;
- skips occupied letters by default and only replaces them with explicit `-ReplaceExisting` approval;
- supports PowerShell common `-WhatIf` / `-Confirm` semantics on import.

## Requirements

- Windows 10/11 or Windows Server with Windows PowerShell 5.1 or newer;
- access to the source profile registry data;
- elevation only when `-IncludeOfflineProfiles` is used;
- SMB connectivity and permissions to the destination shares when importing.

The import is intentionally run in the **target user's session**. Persistent mapped drives are user-context state; an administrator should not create them in a different logon context and assume they belong to the target user.

## Export

Export mappings from currently loaded user hives:

```powershell
.\Export-NetworkDrives.ps1 -OutputPath C:\Temp\network-drive-mappings.csv
```

Include offline profiles as well:

```powershell
# Run from an elevated PowerShell session.
.\Export-NetworkDrives.ps1 `
    -OutputPath C:\Temp\network-drive-mappings.csv `
    -IncludeOfflineProfiles
```

When offline inspection is enabled, the script loads `NTUSER.DAT` into a temporary `HKEY_USERS` hive and unloads it in a `finally` block. Profiles whose hive cannot be loaded are reported as warnings and are not silently fabricated.

## CSV schema

The current schema version is `1`.

```text
SchemaVersion,SourceComputer,SourceSid,AccountName,ProfileName,ProfileLoadedAtExport,DriveLetter,RemotePath
```

Example data is available in [`examples/network-drive-mappings.example.csv`](examples/network-drive-mappings.example.csv). It contains documentation-only values and no credentials.

## Import

### Preview first

```powershell
.\Import-NetworkDrives.ps1 `
    -InputPath C:\Temp\network-drive-mappings.csv `
    -SourceAccountName 'CONTOSO\alice' `
    -WhatIf
```

### Use the current Windows credentials

```powershell
.\Import-NetworkDrives.ps1 `
    -InputPath C:\Temp\network-drive-mappings.csv `
    -SourceAccountName 'CONTOSO\alice'
```

### Prompt for alternate SMB credentials

```powershell
.\Import-NetworkDrives.ps1 `
    -InputPath C:\Temp\network-drive-mappings.csv `
    -SourceSid 'S-1-5-21-111111111-222222222-333333333-1001' `
    -PromptForCredential
```

### Pass a `PSCredential` explicitly

```powershell
$cred = Get-Credential

.\Import-NetworkDrives.ps1 `
    -InputPath C:\Temp\network-drive-mappings.csv `
    -SourceAccountName 'CONTOSO\alice' `
    -Credential $cred
```

The toolkit does not call `GetNetworkCredential().Password`, does not interpolate the password into a command line, and does not persist the credential in its own files. Windows SMB authentication/session behavior remains governed by the operating system and site policy.

## Existing drive letters

If a requested letter is already mapped to the same UNC path, the script skips it.

If the letter is occupied by something else, the default behavior is also to skip it. Replacement requires an explicit switch:

```powershell
.\Import-NetworkDrives.ps1 `
    -InputPath C:\Temp\network-drive-mappings.csv `
    -SourceAccountName 'CONTOSO\alice' `
    -ReplaceExisting
```

Because import supports `ShouldProcess`, `-WhatIf` and `-Confirm` can be used before any replacement.

## Security model

Version 2 intentionally separates **mapping metadata** from **authentication material**.

The CSV may contain workstation name, user SID, account name, drive letters, and UNC paths. Treat it as infrastructure metadata and protect it accordingly, but it contains no passwords. If alternate credentials are required, supply them at execution time through `PSCredential`.

The scripts do not modify firewall settings, SMB server policy, Windows Credential Manager, Active Directory, or share ACLs.

## Limitations

- Registry export covers traditional persistent drive mappings stored under the user's `Network` key. GPO drive maps, DFS configuration, application-specific mounts, or transient SMB sessions may require separate handling.
- Offline profile hives can be locked by another process and may not be loadable.
- A successful mapping proves that Windows accepted the drive connection in the current user context; it does not validate application-level access to every file or folder below the share.
- This toolkit is intended for controlled workstation/profile migrations, not as a replacement for Group Policy Preferences or enterprise endpoint-management tooling.

## Quality checks

GitHub Actions runs on Windows and performs:

- PowerShell parser validation for both scripts;
- PSScriptAnalyzer checks with warning/error findings treated as CI failures.

Before using the toolkit at scale, test export and import on a disposable workstation or test profile with representative SMB shares.

## Repository history

The current repository name reflects its broader migration scope while preserving the history of the original `Export-NetworkDrives` scripts.

## License

No license has been selected yet.
