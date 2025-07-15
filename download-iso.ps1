$url = "https://download.cs2farm.ru/WIN11-PRO-23H2-U9-X64-WPE.ISO"
$fileName = [System.IO.Path]::GetFileName($url)

function Get-AvailableDrives {
    Get-PSDrive -PSProvider FileSystem | 
        Where-Object { $_.Used -and $_.Free } |
        Select-Object Name, Root, 
            @{Name="TotalGB"; Expression={[math]::Round($_.Used/1GB + $_.Free/1GB, 1)}},
            @{Name="FreeGB"; Expression={[math]::Round($_.Free/1GB, 1)}}
}

function Show-DriveMenu {
    $drives = Get-AvailableDrives

    if (-not $drives) {
        Write-Error "Не найдено доступных дисков!"
        exit 1
    }

    Write-Host "`nДоступные диски:`n" -ForegroundColor Cyan
    Write-Host "№ | Диск | Всего места | Свободно"
    Write-Host "--------------------------------"
    
    for ($i = 0; $i -lt $drives.Count; $i++) {
        Write-Host "$($i+1) | $($drives[$i].Name): | $($drives[$i].TotalGB) GB | $($drives[$i].FreeGB) GB"
    }

    do {
        $choice = Read-Host "`nВыберите номер диска (1-$($drives.Count))"
    } until ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $drives.Count)

    return $drives[$choice-1].Root
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $response = $request.GetResponse()
        $responseStream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($OutputPath)
        
        $buffer = New-Object byte[] 1MB
        $totalBytes = $response.ContentLength
        $bytesRead = 0
        $lastPercent = -1
        
        while (($read = $responseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $bytesRead += $read
            
            $percent = [int](($bytesRead / $totalBytes) * 100)
            if ($percent -ne $lastPercent -and ($percent % 1 -eq 0 -or $bytesRead -eq $totalBytes)) {
                Write-Progress -Activity "Скачивание $fileName" `
                              -Status "$percent% завершено ($([math]::Round($bytesRead/1MB,1)) MB из $([math]::Round($totalBytes/1MB,1)) MB)" `
                              -PercentComplete $percent
                $lastPercent = $percent
            }
        }
        
        return $true
    }
    catch {
        Write-Error "Ошибка загрузки: $_"
        return $false
    }
    finally {
        if ($fileStream) { $fileStream.Close() }
        if ($responseStream) { $responseStream.Close() }
        if ($response) { $response.Close() }
    }
}

try {
    $selectedDrive = Show-DriveMenu
    
    $downloadFolder = Join-Path -Path $selectedDrive -ChildPath "vm-iso"
    if (-not (Test-Path $downloadFolder)) {
        New-Item -Path $downloadFolder -ItemType Directory | Out-Null
        Write-Host "Создана папка $downloadFolder" -ForegroundColor Green
    }

    $outputPath = Join-Path -Path $downloadFolder -ChildPath $fileName

    Write-Host "`nНачинаю загрузку $fileName..." -ForegroundColor Cyan
    Write-Host "Сохраняю в: $outputPath"
    
    $success = Download-File -Url $url -OutputPath $outputPath
    
    if ($success) {
        Write-Host "`nЗагрузка завершена успешно!" -ForegroundColor Green
        Write-Host "Файл сохранен: $outputPath" -ForegroundColor Cyan
        
        # Открываем папку с файлом
        explorer $downloadFolder
    }
    else {
        Write-Host "Загрузка не удалась." -ForegroundColor Red
        if (Test-Path $outputPath) { Remove-Item $outputPath -Force }
    }
}
catch {
    Write-Error "Ошибка: $_"
    if (Test-Path $outputPath) { Remove-Item $outputPath -Force }
    exit 1
}
