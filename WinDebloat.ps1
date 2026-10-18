#requires -RunAsAdministrator

param()

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'tweaks.ps1')
. (Join-Path $here 'backup.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:Backup = $null

function New-LogPane {
    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.ReadOnly = $true
    $rtb.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $rtb.ForeColor = [System.Drawing.Color]::White
    $rtb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $rtb.Dock = 'Fill'
    return $rtb
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $colors = @{ INFO = 'White'; OK = 'LightGreen'; WARN = 'Yellow'; ERROR = 'Red' }
    $script:LogPane.SelectionStart = $script:LogPane.TextLength
    $script:LogPane.SelectionLength = 0
    $script:LogPane.SelectionColor = [System.Drawing.Color]::$($colors[$Level])
    $script:LogPane.AppendText("[{0}] {1}`n" -f (Get-Date -Format 'HH:mm:ss'), $Message)
    $script:LogPane.ScrollToCaret()
}

function Invoke-Tweak {
    param($Tweak)
    try {
        Write-Log "Applying: $($Tweak.Name)" 'INFO'
        Backup-SetValue $Tweak
        & $Tweak.Apply
        Write-Log "Done: $($Tweak.Name)" 'OK'
    } catch {
        Write-Log "Failed: $($Tweak.Name) - $_" 'ERROR'
    }
}

function Restore-FromBackup {
    if (-not $script:Backup) { $script:Backup = Get-LatestBackup }
    if (-not $script:Backup) {
        Write-Log 'No backup to restore.' 'WARN'
        return
    }
    try {
        Write-Log 'Restoring original values...' 'INFO'
        Restore-Backup $script:Backup
        Write-Log 'Restore complete.' 'OK'
    } catch {
        Write-Log "Restore failed: $_" 'ERROR'
    }
}

function New-Checkbox {
    param($Tweak)
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $Tweak.Name
    $cb.Tag = $Tweak
    $cb.AutoSize = $true
    return $cb
}

function Main {
    $script:Backup = Get-LatestBackup

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Untitled Windows Optimization'
    $form.Size = New-Object System.Drawing.Size(760, 640)
    $form.MinimumSize = New-Object System.Drawing.Size(760, 640)
    $form.StartPosition = 'CenterScreen'

    $tab = New-Object System.Windows.Forms.TabControl
    $tab.Dock = 'Top'
    $tab.Height = 360

    $categories = @('debloat', 'privacy', 'performance')
    $tabs = @{}
    $checkboxes = @{}
    foreach ($cat in $categories) {
        $page = New-Object System.Windows.Forms.TabPage
        $page.Text = $cat
        $page.AutoScroll = $true
        $flow = New-Object System.Windows.Forms.FlowLayoutPanel
        $flow.Dock = 'Fill'
        $flow.FlowDirection = 'TopDown'
        $flow.WrapContents = $false
        $flow.AutoScroll = $true
        foreach ($t in Get-Tweaks -Category $cat) {
            $cb = New-Checkbox $t
            $flow.Controls.Add($cb)
            $checkboxes[$t.Id] = $cb
        }
        $page.Controls.Add($flow)
        $tab.TabPages.Add($page)
        $tabs[$cat] = $page
    }
    $form.Controls.Add($tab)

    $presetPanel = New-Object System.Windows.Forms.Panel
    $presetPanel.Dock = 'Top'
    $presetPanel.Height = 60
    $presetPanel.Top = $tab.Height

    $btnRecommended = New-Object System.Windows.Forms.Button
    $btnRecommended.Text = 'Recommended'
    $btnRecommended.Location = New-Object System.Drawing.Point(10, 15)
    $btnRecommended.Width = 110

    $btnAggressive = New-Object System.Windows.Forms.Button
    $btnAggressive.Text = 'Aggressive'
    $btnAggressive.Location = New-Object System.Drawing.Point(130, 15)
    $btnAggressive.Width = 110

    $btnNone = New-Object System.Windows.Forms.Button
    $btnNone.Text = 'Clear'
    $btnNone.Location = New-Object System.Drawing.Point(250, 15)
    $btnNone.Width = 70

    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text = 'Presets toggle the checkboxes. Review and edit before applying.'
    $lblHint.Location = New-Object System.Drawing.Point(10, 45)
    $lblHint.AutoSize = $true

    $presetPanel.Controls.AddRange(@($btnRecommended, $btnAggressive, $btnNone, $lblHint))
    $form.Controls.Add($presetPanel)

    $script:LogPane = New-LogPane
    $logPanel = New-Object System.Windows.Forms.Panel
    $logPanel.Dock = 'Fill'
    $logPanel.Top = $presetPanel.Top + $presetPanel.Height
    $logPanel.Height = 200
    $logPanel.Controls.Add($script:LogPane)
    $form.Controls.Add($logPanel)

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = 'Apply Selected'
    $btnApply.Dock = 'Bottom'
    $btnApply.Height = 45

    $btnRestore = New-Object System.Windows.Forms.Button
    $btnRestore.Text = 'Restore Backup'
    $btnRestore.Dock = 'Bottom'
    $btnRestore.Height = 45

    $form.Controls.Add($btnApply)
    $form.Controls.Add($btnRestore)

    function Set-Preset {
        param([string]$Preset)
        foreach ($id in $checkboxes.Keys) {
            $t = $checkboxes[$id].Tag
            $checkboxes[$id].Checked = ($Preset -in $t.Presets)
        }
    }

    $btnRecommended.Add_Click({ Set-Preset 'recommended' })
    $btnAggressive.Add_Click({ Set-Preset 'aggressive' })
    $btnNone.Add_Click({ Set-Preset '' })

    $btnApply.Add_Click({
        $selected = @($checkboxes.Values | Where-Object { $_.Checked })
        if ($selected.Count -eq 0) {
            Write-Log 'No tweaks selected.' 'WARN'
            return
        }
        Write-Log 'Creating System Restore point...' 'INFO'
        try {
            Checkpoint-Computer -Description 'Untitled Windows Optimization' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        } catch {
            Write-Log 'System Restore point failed (System Restore may be disabled). Continuing with local backup.' 'WARN'
        }
        $script:Backup = New-Backup
        foreach ($cb in $selected) { Invoke-Tweak $cb.Tag }
        Save-Backup $script:Backup
        Write-Log 'All selected tweaks processed.' 'OK'
    })

    $btnRestore.Add_Click({ Restore-FromBackup })

    $form.ShowDialog() | Out-Null
}

# ponytail: self-elevate then relaunch
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Main
