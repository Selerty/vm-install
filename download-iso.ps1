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

function Format-TimeSpan {
    param([TimeSpan]$ts)
    return "{0:D2}:{1:D2}:{2:D2}" -f $ts.Hours, $ts.Minutes, $ts.Seconds
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
    Write-Host "Сохраняю в: $outputPath`n"

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastUpdate = [DateTime]::Now

    function Update-Timer {
        $currentTime = [DateTime]::Now
        if (($currentTime - $lastUpdate).TotalSeconds -ge 1) {
            Write-Host "Прошло времени: $(Format-TimeSpan $stopwatch.Elapsed)" -NoNewline
            Write-Host "`r" -NoNewline
            $lastUpdate = $currentTime
        }
    }

    $job = Start-Job -ScriptBlock {
        param($url, $outputPath)
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
    } -ArgumentList $url, $outputPath

    while ($job.State -eq 'Running') {
        Update-Timer
        Start-Sleep -Milliseconds 200
    }

    $result = Receive-Job -Job $job
    Remove-Job -Job $job

    $stopwatch.Stop()
    Write-Host "`nЗагрузка завершена!" -ForegroundColor Green
    Write-Host "Файл сохранен: $outputPath" -ForegroundColor Cyan
    Write-Host "Общее время загрузки: $(Format-TimeSpan $stopwatch.Elapsed)"

    if (Test-Path $outputPath) {
        $fileSize = (Get-Item $outputPath).Length / 1MB
        Write-Host "Размер файла: $([math]::Round($fileSize, 2)) MB"
    }

    explorer $downloadFolder
}
catch {
    Write-Error "Ошибка: $_"
    if (Test-Path $outputPath) { Remove-Item $outputPath -Force }
    exit 1
}
