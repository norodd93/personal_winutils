function Invoke-WPFUltimatePerformance ([switch]$Enable) {
    <#

    .SYNOPSIS
        Adds or removes the Ultimate Performance power plan

    #>

    if ($Enable) {
        Step-WinUtilJob -Status "Adding the Ultimate Performance power plan" -State "Indeterminate"
        Write-WinUtilLog -Component "Power" -Message "Attempting to enable the Ultimate Performance power plan."

        $duplicated = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
        if ($LASTEXITCODE -ne 0) {
            $detail = ($duplicated | Out-String).Trim()
            $msg = "Ultimate Performance power plan is not available on this system/edition (powercfg exit code $LASTEXITCODE). $detail"
            Write-Warning $msg
            Write-WinUtilLog -Level "WARN" -Component "Power" -Message $msg
            return
        }

        $guid = ($duplicated | Select-String -Pattern '[A-Fa-f0-9-]{36}').Matches.Value
        if (-not $guid) {
            $msg = "powercfg did not report a scheme GUID to activate. Ultimate Performance may not be available on this Windows version/edition."
            Write-Warning $msg
            Write-WinUtilLog -Level "WARN" -Component "Power" -Message $msg
            return
        }

        powercfg /setactive $guid 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $msg = "powercfg could not activate the Ultimate Performance scheme (exit code $LASTEXITCODE)."
            Write-Warning $msg
            Write-WinUtilLog -Level "WARN" -Component "Power" -Message $msg
            return
        }

        Write-WinUtilLog -Component "Power" -Message "Ultimate Performance power plan installed and activated."
    } else {
        Step-WinUtilJob -Status "Restoring the default power plans" -State "Indeterminate"
        Write-WinUtilLog -Component "Power" -Message "Restoring the default power schemes."

        powercfg /restoredefaultschemes 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $msg = "powercfg could not restore the default power schemes (exit code $LASTEXITCODE)."
            Write-Warning $msg
            Write-WinUtilLog -Level "WARN" -Component "Power" -Message $msg
            return
        }

        Write-WinUtilLog -Component "Power" -Message "Power plans were reset to defaults."
    }
}
