# Экспорт ВСЕХ постоянных сетевых дисков (из реестра)
$outputFile = "C:\Temp\AllUsersMappedDrives.csv"

# Создаем папку, если ее нет
if (-not (Test-Path -Path (Split-Path -Path $outputFile -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path -Path $outputFile -Parent) | Out-Null
}

# Получаем диски всех пользователей из реестра
$allDrives = @()

# Текущий пользователь
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$allDrives += Get-ItemProperty "HKCU:\Network\*" | Select-Object @{n="User";e={$currentUser}}, 
    @{n="DriveLetter";e={$_.PSChildName}}, 
    @{n="RemotePath";e={$_.RemotePath}}

# Все пользователи системы (требует админских прав)
if ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $users = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" | ForEach-Object {
        (Get-ItemProperty $_.PSPath).ProfileImagePath
    }
    
    foreach ($user in $users) {
        $sid = (New-Object System.Security.Principal.NTAccount($user.Split('\')[-1])).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $regPath = "Registry::HKEY_USERS\$sid\Network"
        if (Test-Path $regPath) {
            $drives = Get-ItemProperty "$regPath\*" -ErrorAction SilentlyContinue
            foreach ($drive in $drives) {
                $allDrives += [PSCustomObject]@{
                    User = $user
                    DriveLetter = $drive.PSChildName
                    RemotePath = $drive.RemotePath
                }
            }
        }
    }
}

# Экспорт в CSV
$allDrives | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Host "Экспорт завершен. Данные сохранены в $outputFile"
