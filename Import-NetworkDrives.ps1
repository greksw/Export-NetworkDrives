# Import-MappedDrives_NoAuth.ps1
param(
    [string]$inputFile = "C:\Temp\AllUserMappedDrives_Simplified.csv"
)

# Проверяем существование файла
if (-not (Test-Path $inputFile)) {
    Write-Host "Файл $inputFile не найден!" -ForegroundColor Red
    exit 1
}

# Импортируем данные
$drivesToMap = Import-Csv -Path $inputFile

# Статистика
$total = $drivesToMap.Count
$success = 0
$skipped = 0
$errors = 0

foreach ($drive in $drivesToMap) {
    try {
        # Проверяем формат буквы диска (добавляем : если нужно)
        $driveLetter = $drive.DriveLetter
        if (-not $driveLetter.EndsWith(':')) {
            $driveLetter += ':'
        }
        
        # Проверяем, не подключен ли уже диск
        if (Test-Path "$driveLetter\") {
            Write-Host "[SKIP] Диск $driveLetter уже подключен ($($drive.RemotePath))" -ForegroundColor Yellow
            $skipped++
            continue
        }
        
        # Подключаем диск с текущими учетными данными пользователя
        $result = net use $driveLetter $drive.RemotePath /persistent:yes 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Успешно подключен $driveLetter → $($drive.RemotePath)" -ForegroundColor Green
            $success++
        } else {
            Write-Host "[ERROR] Ошибка подключения $driveLetter: $result" -ForegroundColor Red
            $errors++
        }
    } catch {
        Write-Host "[FATAL] Ошибка при обработке $($drive.DriveLetter): $_" -ForegroundColor Red
        $errors++
    }
}

# Выводим статистику
Write-Host "`nИтоги:" -ForegroundColor Cyan
Write-Host "Всего дисков в файле: $total"
Write-Host "Успешно подключено: $success"
Write-Host "Пропущено (уже подключены): $skipped"
Write-Host "Ошибок подключения: $errors"
