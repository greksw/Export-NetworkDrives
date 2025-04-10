# Export-AllUserDrives.ps1
$outputFile = "C:\Temp\AllUserMappedDrives.csv"

# Создаем папку, если её нет
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
}

# Получаем список всех профилей пользователей
$userProfiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"

$results = foreach ($profile in $userProfiles) {
    $sid = $profile.PSChildName
    $profilePath = (Get-ItemProperty $profile.PSPath).ProfileImagePath
    $username = $profilePath.Split('\')[-1]
    
    # Проверяем ветку реестра пользователя
    $regPath = "Registry::HKEY_USERS\$sid\Network"
    
    if (Test-Path $regPath) {
        $driveLetters = Get-ChildItem $regPath
        
        foreach ($drive in $driveLetters) {
            $driveLetter = $drive.PSChildName
            $remotePath = (Get-ItemProperty $drive.PSPath).RemotePath
            
            [PSCustomObject]@{
                UserName = $username
                DriveLetter = "$driveLetter`:"  # Добавляем двоеточие
                RemotePath = $remotePath
                SID = $sid
                ProfilePath = $profilePath
            }
        }
    }
}

# Экспортируем в CSV
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "Экспорт завершен. Результаты сохранены в $outputFile"
Write-Host "Найдено сетевых дисков: $($results.Count)"
