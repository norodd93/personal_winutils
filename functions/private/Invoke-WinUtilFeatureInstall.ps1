function Invoke-WinUtilFeatureInstall ($CheckBox) {
    Write-WinUtilLog -Component "Feature" -Message "Applying feature action: $CheckBox"

    $featureFailed = $false
    $enabledCount = 0
    $totalFeatures = @($sync.configs.feature.$CheckBox.feature).Count

    if ($sync.configs.feature.$CheckBox.feature) {
        foreach ($feature in $sync.configs.feature.$CheckBox.feature) {
            Write-Host "Installing $feature"
            Write-WinUtilLog -Component "Feature" -Message "Enabling Windows optional feature: $feature"
            try {
                Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction Stop
                $enabledCount++
                Write-WinUtilLog -Component "Feature" -Message "Enabled Windows optional feature: $feature"
            } catch {
                $featureFailed = $true
                # A feature missing on this edition (e.g. Windows Sandbox on Home) must not
                # abort the remaining selected features
                Write-Warning "Unable to enable feature $feature`: $($_.Exception.Message)"
                Write-WinUtilLog -Level "ERROR" -Component "Feature" -Message "Unable to enable feature $feature`: $($_.Exception.Message)"
            }
        }
    }

    $scriptFailed = $false
    if ($featureFailed -and $totalFeatures -gt 0) {
        Write-WinUtilLog -Level "WARN" -Component "Feature" -Message "Skipping dependent scripts after an optional feature failed: $CheckBox ($enabledCount/$totalFeatures enabled)"
    } elseif ($sync.configs.feature.$CheckBox.InvokeScript) {
        foreach ($script in $sync.configs.feature.$CheckBox.InvokeScript) {
            Write-Host "Running Script for $CheckBox"
            Write-WinUtilLog -Component "Feature" -Message "Running feature script for: $CheckBox"
            try {
                Invoke-Command -ScriptBlock ([scriptblock]::Create($script)) -ErrorAction Stop
                Write-WinUtilLog -Component "Feature" -Message "Completed feature script for: $CheckBox"
            } catch {
                $scriptFailed = $true
                Write-Warning "Feature script for $CheckBox failed: $($_.Exception.Message)"
                Write-WinUtilLog -Level "ERROR" -Component "Feature" -Message "Feature script for $CheckBox failed: $($_.Exception.Message)"
            }
        }
    }

    if ($featureFailed -or $scriptFailed) {
        $detail = if ($featureFailed) { "$enabledCount/$totalFeatures optional feature(s) enabled" } else { "one or more scripts failed" }
        Write-WinUtilLog -Level "ERROR" -Component "Feature" -Message "Feature action failed or partially applied: $CheckBox ($detail)"
        throw "Feature action failed or partially applied for $CheckBox."
    }

    Write-WinUtilLog -Component "Feature" -Message "Feature action completed: $CheckBox"
}
