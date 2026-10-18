$script:RegistryTweaks = @(
    @{
        Id = 'disable-telemetry'
        Name = 'Disable Telemetry'
        Category = 'privacy'
        Presets = @('recommended', 'aggressive')
        Apply = {
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0 -Type DWord -Force
        }
    },
    @{
        Id = 'disable-compat-telemetry'
        Name = 'Disable Compatibility Telemetry (DiagTrack)'
        Category = 'privacy'
        Presets = @('aggressive')
        Apply = {
            Stop-Service -Name 'DiagTrack' -Force -ErrorAction SilentlyContinue
            Set-Service -Name 'DiagTrack' -StartupType Disabled -ErrorAction SilentlyContinue
        }
    },
    @{
        Id = 'disable-cortana'
        Name = 'Disable Cortana'
        Category = 'debloat'
        Presets = @('recommended', 'aggressive')
        Apply = {
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'AllowCortana' -Value 0 -Type DWord -Force
        }
    },
    @{
        Id = 'remove-copilot'
        Name = 'Remove Copilot'
        Category = 'debloat'
        Presets = @('recommended', 'aggressive')
        Apply = {
            winget uninstall --id 9NHT9RB2F4HD --silent --accept-source-agreements
            New-Item -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Force | Out-Null
            Set-ItemProperty -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1 -Type DWord -Force
        }
    },
    @{
        Id = 'remove-onedrive'
        Name = 'Remove OneDrive'
        Category = 'debloat'
        Presets = @('aggressive')
        Apply = {
            $os = [System.Environment]::OSVersion.Version.Build
            $uninstall = "$env:WINDIR\SysWOW64\OneDriveSetup.exe"
            if (Test-Path $uninstall) { & $uninstall /uninstall }
            Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive' -ErrorAction SilentlyContinue
        }
    },
    @{
        Id = 'disable-tips'
        Name = 'Disable Tips & Suggestions'
        Category = 'privacy'
        Presets = @('recommended', 'aggressive')
        Apply = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-338389Enabled' -Value 0 -Type DWord -Force
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-338393Enabled' -Value 0 -Type DWord -Force
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SoftLandingEnabled' -Value 0 -Type DWord -Force
        }
    },
    @{
        Id = 'disable-ads'
        Name = 'Disable Ads / Suggested Content'
        Category = 'privacy'
        Presets = @('recommended', 'aggressive')
        Apply = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Value 0 -Type DWord -Force
        }
    },
    @{
        Id = 'disable-xbox-services'
        Name = 'Disable Xbox Services'
        Category = 'debloat'
        Presets = @('aggressive')
        Apply = {
            'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc' | ForEach-Object {
                Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue
                Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Id = 'remove-xbox-apps'
        Name = 'Remove Xbox Apps'
        Category = 'debloat'
        Presets = @('aggressive')
        Apply = {
            $apps = Get-AppxPackage -Name '*xbox*' -ErrorAction SilentlyContinue
            if ($apps) { $apps | Remove-AppxPackage -ErrorAction SilentlyContinue }
        }
    },
    @{
        Id = 'disable-startup-delay'
        Name = 'Disable Startup Apps Delay'
        Category = 'performance'
        Presets = @('aggressive')
        Apply = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Name 'StartupDelayInMSec' -Value 0 -Type DWord -Force
        }
    },
    @{
        Id = 'visual-effects-performance'
        Name = 'Set Visual Effects for Performance'
        Category = 'performance'
        Presets = @('aggressive')
        Apply = {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 -Type DWord -Force
        }
    },
    @{
        Id = 'high-performance-power'
        Name = 'Set High Performance Power Plan'
        Category = 'performance'
        Presets = @('aggressive')
        Apply = {
            powercfg /setactive '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        }
    },
    @{
        Id = 'disable-hibernate'
        Name = 'Disable Hibernation'
        Category = 'performance'
        Presets = @('aggressive')
        Apply = {
            powercfg /hibernate off
        }
    },
    @{
        Id = 'disable-preinstalled-apps'
        Name = 'Remove Preinstalled Bloatware'
        Category = 'debloat'
        Presets = @('recommended', 'aggressive')
        Apply = {
            $bloat = @(
                'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.GamingApp',
                'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People', 'Microsoft.Todos',
                'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub',
                'Microsoft.MixedReality.Portal', 'Microsoft.SkypeApp', 'Microsoft.ZuneMusic',
                'Microsoft.ZuneVideo', 'Microsoft.WindowsMaps', 'Microsoft.YourPhone'
            )
            foreach ($p in $bloat) {
                Get-AppxPackage -Name $p -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
                Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $p } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
            }
        }
    }
)

function Get-Tweaks {
    param([string]$Category)
    if ($Category) { return @($script:RegistryTweaks | Where-Object { $_.Category -eq $Category }) }
    return $script:RegistryTweaks
}
