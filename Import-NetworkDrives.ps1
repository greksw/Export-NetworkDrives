# Import-Drives_ManualAuth.ps1
param(
    [string]$inputFile = "C:\Temp\AllUserMappedDrives_Simplified.csv"
)

# Проверка файла с дисками
if (-not (Test-Path $inputFile)) {
    Write-Host "Файл $inputFile не найден!" -ForegroundColor Red
    exit 1
}

# Запрос учетных данных
$cred = Get-Credential -Message "Введите учетные данные для подключения сетевых дисков (формат: ЛОГИН или ДОМЕН\ЛОГИН)"

# Загрузка списка дисков
$drivesToMap = Import-Csv -Path $inputFile

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
            Write-Host "[SKIP] $driveLetter уже подключен ($($drive.RemotePath))" -ForegroundColor Yellow
            $stats.Skipped++
            continue
        }

        # Формируем команду подключения
        $username = $cred.UserName
        $password = $cred.GetNetworkCredential().Password
        
        $netUseCmd = @"
net use $driveLetter "$($drive.RemotePath)" /persistent:yes /user:"$username" "$password"
"@
        
        # Выполняем подключение
        $result = cmd /c $netUseCmd 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Успешно: $driveLetter → $($drive.RemotePath)" -ForegroundColor Green
            $stats.Success++
        } else {
            Write-Host "[ERROR] $driveLetter: $result" -ForegroundColor Red
            $stats.Errors++
        }
    } catch {
        Write-Host "[FATAL] Ошибка при обработке $($drive.DriveLetter): $_" -ForegroundColor Red
        $stats.Errors++
    }
}

# Итоговая статистика
Write-Host "`nРезультаты:" -ForegroundColor Cyan
Write-Host "• Всего дисков: $($stats.Total)"
Write-Host "• Успешно: $($stats.Success) (зеленый)"
Write-Host "• Пропущено: $($stats.Skipped) (желтый)"
Write-Host "• Ошибок: $($stats.Errors) (красный)"

if ($stats.Errors -gt 0) {
    Write-Host "`nСоветы по устранению ошибок:" -ForegroundColor Yellow
    Write-Host "1. Проверьте правильность введенных учетных данных"
    Write-Host "2. Убедитесь, что сетевой путь доступен: Test-NetConnection <IP> -Port 445"
    Write-Host "3. Проверьте, не занята ли буква диска"
}
