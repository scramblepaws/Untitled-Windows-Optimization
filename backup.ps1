# Registry subtrees the tweaks touch. `reg export`/`reg import` gives full
# original-state snapshot + restore for these, no per-value bookkeeping.
$script:BackupRegistryPaths = @(
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection',
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search',
    'HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects',
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'
)

$script:BackupServices = @(
    'DiagTrack', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc'
)

function Get-BackupRoot {
    Join-Path $env:ProgramData 'UntitledOptimization\backups'
}

function New-Backup {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path (Get-BackupRoot) $ts
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $regDir = Join-Path $dir 'registry'
    New-Item -ItemType Directory -Path $regDir -Force | Out-Null
    $regFiles = @()
    foreach ($p in $script:BackupRegistryPaths) {
        $file = Join-Path $regDir ("{0}.reg" -f ($p -replace '[\\:]', '_'))
        $args = "export `"$p`" `"$file`" /y"
        Start-Process -FilePath 'reg.exe' -ArgumentList $args -Wait -NoNewWindow
        if (Test-Path $file) { $regFiles += $file }
    }

    $services = foreach ($name in $script:BackupServices) {
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($svc) {
            [PSCustomObject]@{ Name = $name; StartType = $svc.StartType.ToString(); Status = $svc.Status.ToString() }
        }
    }

    $appx = @(Get-AppxPackage -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PackageFullName)
    $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PackageName)

    $manifest = [PSCustomObject]@{
        Created   = $ts
        Registry  = $regFiles
        Services  = @($services)
        Appx      = @($appx)
        Provisioned = @($prov)
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $dir 'manifest.json')

    return $manifest
}

function Get-LatestBackup {
    $root = Get-BackupRoot
    if (-not (Test-Path $root)) { return $null }
    $manifests = Get-ChildItem -Path $root -Filter 'manifest.json' -Recurse -ErrorAction SilentlyContinue
    if (-not $manifests) { return $null }
    $latest = $manifests | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return Get-Content $latest.FullName -Raw | ConvertFrom-Json
}

function Save-Backup {
    param($Backup)
    # snapshot already persisted during New-Backup; kept as a no-op seam
    Write-Output "Backup saved to $(Get-BackupRoot)"
}

function Restore-Backup {
    param($Backup)
    foreach ($f in $Backup.Registry) {
        if (Test-Path $f) {
            Start-Process -FilePath 'reg.exe' -ArgumentList "import `"$f`"" -Wait -NoNewWindow
        }
    }
    foreach ($s in $Backup.Services) {
        Set-Service -Name $s.Name -StartupType $s.StartType -ErrorAction SilentlyContinue
        if ($s.Status -eq 'Running') { Start-Service -Name $s.Name -ErrorAction SilentlyContinue }
    }
    # ponytail: appx removals are not reliably re-provisionable; registry + services cover
    # the reversible surface. Re-adding removed store apps needs a network re-download.
}
