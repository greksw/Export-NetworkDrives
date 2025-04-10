# Скрипт для экспорта списка подключенных сетевых дисков
$outputFile = "C:\Temp\MappedDrives.csv"

# Создаем папку, если она не существует
if (-not (Test-Path -Path (Split-Path -Path $outputFile -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path -Path $outputFile -Parent) | Out-Null
}

# Получаем все подключенные сетевые диски
$mappedDrives = Get-WmiObject -Class Win32_MappedLogicalDisk | Select-Object DeviceID, ProviderName, SessionID

# Экспортируем в CSV файл
$mappedDrives | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "Список сетевых дисков экспортирован в $outputFile"
