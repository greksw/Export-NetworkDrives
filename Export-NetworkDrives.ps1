# Export-MappedDrives.ps1
$outputFile = "C:\Temp\MappedDrives_IP.csv"
$keyFile = "C:\Temp\DriveEncryption.key"

# Создаем ключ шифрования (если его нет)
if (-not (Test-Path $keyFile)) {
    $key = New-Object Byte[] 32
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($key)
    $key | Out-File $keyFile -Force
} else {
    $key = Get-Content $keyFile
}

# Получаем все подключенные диски (включая IP-адреса)
$drives = Get-SmbMapping | Where-Object { $_.RemotePath -match '^\\\\[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\\' }

$exportData = foreach ($drive in $drives) {
    $cred = cmdkey /list:$($drive.RemotePath) 2>$null | Where-Object { $_ -match 'Пользователь:' }
    
    if ($cred) {
        $username = ($cred -split 'Пользователь:')[1].Trim()
        $password = Read-Host "Введите пароль для $($drive.LocalPath) ($username)" -AsSecureString
        
        [PSCustomObject]@{
            DriveLetter = $drive.LocalPath
            RemotePath  = $drive.RemotePath
            Username    = $username
            Password    = ConvertFrom-SecureString -SecureString $password -Key $key
        }
    }
}

$exportData | Export-Csv $outputFile -NoTypeInformation -Encoding UTF8
Write-Host "Данные сохранены в $outputFile. Ключ шифрования: $keyFile"
