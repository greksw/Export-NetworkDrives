# Import-Drives_CrossAuth.ps1
param(
    [string]$inputFile = "C:\Temp\AllUserMappedDrives_Simplified.csv",
    [string]$localCredFile = "C:\Temp\LocalStorageCred.xml"
)

# Проверка файла с дисками
if (-not (Test-Path $inputFile)) {
    Write-Host "Файл $inputFile не найден!" -ForegroundColor Red
    exit 1
}

# Проверка/создание файла учетных данных
if (-not (Test-Path $localCredFile)) {
    Write-Host "Файл учетных данных не найден. Создаем новый..." -ForegroundColor Yellow
    $cred = Get-Credential -Message "Введите учетные данные для доступа к файловому хранилищу (рабочая группа)"
    $cred | Export-Clixml -Path $localCredFile -Force
    Write-Host "Учетные данные сохранены в $localCredFile" -ForegroundColor Green
}

# Загрузка данных
$drivesToMap = Import-Csv -Path $inputFile
$storageCred = Import-Clixml -Path $localCredFile

# Статистика
$stats = @{
    Total = $drivesToMap.Count
    Success = 0
    Skipped = 0
    Errors = 0
}

foreach ($drive in $drivesToMap) {
    try {
        # Форматируем букву диска
        $driveLetter = $drive.DriveLetter.Trim()
        if (-not $driveLetter.EndsWith(':')) { $driveLetter += ':' }

        # Проверяем существование диска
        if (Test-Path "${driveLetter}\") {
            Write-Host "[SKIP] $driveLetter уже подключен" -ForegroundColor Yellow
            $stats.Skipped++
            continue
        }

        # Подключаем диск с отдельными учетными данными
        $netUseCmd = "net use $driveLetter $($drive.RemotePath) /persistent:yes " +
                    "/user:$($storageCred.UserName) " +
                    """$($storageCred.GetNetworkCredential().Password)"""
        
        $result = cmd /c $netUseCmd 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] $driveLetter → $($drive.RemotePath)" -ForegroundColor Green
            $stats.Success++
        } else {
            Write-Host "[ERROR] $driveLetter: $result" -ForegroundColor Red
            $stats.Errors++
        }
    } catch {
        Write-Host "[FATAL] $($drive.DriveLetter): $_" -ForegroundColor Red
        $stats.Errors++
    }
}

# Вывод статистики
Write-Host "`nИтоги выполнения:" -ForegroundColor Cyan
Write-Host "Всего дисков: $($stats.Total)"
Write-Host "Успешно: $($stats.Success)"
Write-Host "Пропущено: $($stats.Skipped)"
Write-Host "Ошибок: $($stats.Errors)"

# Дополнительная проверка
if ($stats.Errors -gt 0) {
    Write-Host "`nРекомендации:" -ForegroundColor Yellow
    Write-Host "1. Проверьте правильность учетных данных в $localCredFile"
    Write-Host "2. Убедитесь, что хранилище доступно по всем указанным путям"
    Write-Host "3. Для пересоздания файла учетных данных удалите $localCredFile"
}
