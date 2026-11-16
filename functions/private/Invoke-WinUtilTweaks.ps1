function Invoke-WinUtilTweaks {
    <#

    .SYNOPSIS
        Invokes the function associated with each provided checkbox

    .PARAMETER CheckBox
        The checkbox to invoke

    .PARAMETER undo
        Indicates whether to undo the operation contained in the checkbox

    .PARAMETER KeepServiceStartup
        Indicates whether to override the startup of a service with the one given from WinUtil,
        or to keep the startup of said service, if it was changed by the user, or another program, from its default value.
    #>

    param(
        $CheckBox,
        $undo = $false,
        $KeepServiceStartup = $true
    )

    $action = if ($undo) { "Undo" } else { "Apply" }
    Write-WinUtilLog -Component "Tweaks" -Message "$action tweak: $CheckBox"
    # The next status read must hit the registry, not a value cached before this change
    if ($sync.ToggleStatusCache) {
        $sync.ToggleStatusCache.Remove($CheckBox)
    }
    # The counter lives in this runspace, so an error a concurrent job logs from its own
    # runspace cannot be charged to a toggle flipped on the UI thread
    $errorsBefore = [int]$global:WinUtilJobErrorCount

    # Windows 10 best-effort support: skip tweaks that are not applicable as a whole.
    $osInfo = if (Get-Command Get-WinUtilOSInfo -ErrorAction SilentlyContinue) { Get-WinUtilOSInfo } else { $null }
    $isWin10 = $osInfo -and $osInfo.IsWindows10
    if ($isWin10) {
        # This relies on a Windows 11-only Start menu feature override with no safe/useful Windows 10 equivalent.
        $win11OnlyTweaks = @("WPFTweaksRevertStartMenu")
        if ($win11OnlyTweaks -contains $CheckBox) {
            $msg = "Tweak $CheckBox is not applicable on Windows 10 (build $($osInfo.BuildNumber)); skipping."
            Write-Warning $msg
            Write-WinUtilLog -Level "WARN" -Component "Tweaks" -Message $msg
            return
        }
    }

    # Prevent conflicting IPv6 mode tweaks from clobbering each other.
    $ipv6ModeTweaks = @{
        "WPFTweaksIPv46" = "32"
        "WPFTweaksTeredo" = "1"
        "WPFTweaksDisableIPv6" = "255"
    }
    if ($ipv6ModeTweaks.ContainsKey($CheckBox)) {
        $ipv6Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
        $currentIPv6 = $null
        try { $currentIPv6 = (Get-ItemProperty -Path $ipv6Path -Name "DisabledComponents" -ErrorAction Stop).DisabledComponents } catch { $currentIPv6 = $null }
        $targetValue = $ipv6ModeTweaks[$CheckBox]
        $otherActive = @($ipv6ModeTweaks.Keys | Where-Object { $_ -ne $CheckBox -and [string]$currentIPv6 -eq [string]$ipv6ModeTweaks[$_] })
        if (-not $undo -and $otherActive.Count -gt 0 -and [string]$currentIPv6 -ne [string]$targetValue) {
            $msg = "Cannot apply $CheckBox because another IPv6 mode tweak appears active ($($otherActive -join ', '), DisabledComponents=$currentIPv6). Undo the conflicting tweak first."
            Write-Warning $msg
            Write-WinUtilLog -Level "WARN" -Component "Tweaks" -Message $msg
            throw $msg
        }
        if ($undo -and $null -ne $currentIPv6 -and [string]$currentIPv6 -ne [string]$targetValue) {
            $msg = "Skipping undo for $CheckBox because DisabledComponents is '$currentIPv6' (expected '$targetValue'); another IPv6 configuration may be active."
            Write-Warning $msg
            Write-WinUtilLog -Level "WARN" -Component "Tweaks" -Message $msg
            return
        }
    }

    if ($undo) {
        $Values = @{
            Registry = "OriginalValue"
            Service = "OriginalType"
            ScriptType = "UndoScript"
        }

    } else {
        $Values = @{
            Registry = "Value"
            Service = "StartupType"
            OriginalService = "OriginalType"
            ScriptType = "InvokeScript"
        }
    }
    if ($sync.configs.tweaks.$CheckBox.service) {
        foreach ($item in $sync.configs.tweaks.$CheckBox.service) {
            $changeservice = $true

            # KeepServiceStartup protects a service the user (or another tool) changed away from
            # the value this tweak expects. Undo uses the same rule in reverse: only restore
            # OriginalType when the service still sits at the StartupType this tweak applies.
            # This compares current state, not history: a service already at StartupType
            # before apply is indistinguishable from one changed by this tweak.
            $expectedType = if ($undo) { $item.StartupType } else { $item.$($values.OriginalService) }
            if ($KeepServiceStartup) {
                $serviceName = $item.Name
                try {
                    # Check if the service exists
                    $service = Get-Service -Name $serviceName -ErrorAction Stop
                    if(!($service.StartType.ToString() -eq $expectedType)) {
                        $changeservice = $false
                        # Say so, or the log reads as if the tweak changed a service it left alone
                        $skipMessage = "Service $serviceName startup type is $($service.StartType), not $expectedType as this tweak expects; leaving it unchanged."
                        Write-Warning $skipMessage
                        Write-WinUtilLog -Level "WARN" -Component "Service" -Message $skipMessage
                    }
                } catch {
                    if ($_.FullyQualifiedErrorId -like "NoServiceFoundForGivenName,*") {
                        $changeservice = $false
                        Write-Warning "Service $serviceName was not found."
                        Write-WinUtilLog -Level "WARN" -Component "Service" -Message "Service $serviceName was not found."
                    } else {
                        throw
                    }
                }
            }

            if ($changeservice) {
                Set-WinUtilService -Name $item.Name -StartupType $item.$($values.Service)
            }
        }
    }
    if ($sync.configs.tweaks.$CheckBox.registry) {
        foreach ($reg in $sync.configs.tweaks.$CheckBox.registry) {
            if ($reg.Values) { continue }
            Set-WinUtilRegistry -Name $reg.Name -Path $reg.Path -Type $reg.Type -Value $reg.$($values.registry)
        }
    }
    if ($sync.configs.tweaks.$CheckBox.$($values.ScriptType)) {
        foreach ($scr in $sync.configs.tweaks.$CheckBox.$($values.ScriptType)) {
            $Scriptblock = [scriptblock]::Create($scr)
            try {
                Invoke-WinUtilScript -ScriptBlock $scriptblock -Name $CheckBox
            } catch {
                # Invoke-WinUtilScript already logged the error and incremented the
                # per-runspace error counter. Swallow it here so the remaining tweak
                # steps still run and the error is reported in the summary below.
            }
        }
    }

    if (!$undo -and $sync.configs.tweaks.$CheckBox.appx) {
        foreach ($pkg in $sync.configs.tweaks.$CheckBox.appx) {
            Remove-WinUtilAPPX -Name $pkg
        }
        Remove-WinUtilProvisionedAPPX -PackageList $sync.configs.tweaks.$CheckBox.appx
    }
    $errorCount = [int]$global:WinUtilJobErrorCount - $errorsBefore
    if ($errorCount -gt 0) {
        Write-WinUtilLog -Level "WARN" -Component "Tweaks" -Message "$action tweak finished with $errorCount error(s): $CheckBox"
    } else {
        Write-WinUtilLog -Component "Tweaks" -Message "$action tweak completed: $CheckBox"
    }
}
