function Get-EnvironmentVariableSafe($name) {
    $value = [System.Environment]::GetEnvironmentVariable($name, "User")
    if ([string]::IsNullOrEmpty($value)) {
        throw "Не найдена переменная среды: $name"
    }
    return $value
}

foreach ($var in $requiredVars) {
    if (-not (Test-Path env:$var)) {
        throw "Не определена переменная: $var"
    }
}

$vmSwitch = Get-EnvironmentVariableSafe "SELERTY_VM_COMMUTATOR_NAME"
$isoPath = Get-EnvironmentVariableSafe "SELERTY_VM_ISO_PATH"
$driveLetter = Get-EnvironmentVariableSafe "SELERTY_VM_ISO_DRIVE"
$memory = 8GB
$cpu = 2
$diskSize = 120GB
$generation = 2
$vmNumber = 1

while (Get-VM -Name "VM-$vmNumber" -ErrorAction SilentlyContinue) {
    $vmNumber++
}
$vmName = "VM-$vmNumber"

$vmPath = "${driveLetter}:\Hyper-V\VMs\$vmName"
$vhdPath = "$vmPath\$vmName.vhdx"

if (-not (Test-Path $vmPath)) {
    New-Item -ItemType Directory -Path $vmPath -Force | Out-Null
}

try {
    Write-Host "Создание VM $vmName ($memory RAM)..." -ForegroundColor Cyan
    
    New-VM -Name $vmName `
           -Generation $generation `
           -MemoryStartupBytes $memory `
           -SwitchName $vmSwitch `
           -Path $vmPath | Out-Null

    Set-VMMemory -VMName $vmName `
                 -DynamicMemoryEnabled $false `
                 -StartupBytes $memory | Out-Null

    New-VHD -Path $vhdPath -SizeBytes $diskSize -Dynamic | Out-Null
    Add-VMHardDiskDrive -VMName $vmName -Path $vhdPath | Out-Null

    if (Test-Path $isoPath) {
        Add-VMDvdDrive -VMName $vmName -Path $isoPath | Out-Null
        Set-VMFirmware -VMName $vmName -FirstBootDevice (Get-VMDvdDrive -VMName $vmName)
        Write-Host "ISO подключен: $isoPath" -ForegroundColor Green
    } else {
        Write-Warning "ISO не найден: $isoPath"
    }


    Set-VMProcessor -VMName $vmName -Count $cpu | Out-Null
    Write-Host "Успешно создана VM: $vmName" -ForegroundColor Green
    Write-Host "Ядер: $cpu CPU" -ForegroundColor Yellow
    Write-Host "Память: $memory" -ForegroundColor Yellow
    Write-Host "Диск: $vhdPath ($diskSize)" -ForegroundColor Yellow

} catch {
    Write-Host "Ошибка: $_" -ForegroundColor Red
    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
        Remove-VM -Name $vmName -Force
    }
    if (Test-Path $vhdPath) {
        Remove-Item $vhdPath -Force
    }
    throw
}
