function Invoke-WPFFixesNTPPool {
    <#
    .SYNOPSIS
        Configures Windows to use pool.ntp.org for NTP synchronization

    .DESCRIPTION
        Replaces the default Windows NTP server (time.windows.com) with
        pool.ntp.org for improved time synchronization accuracy and reliability.
    #>

    try {
        Write-WinUtilLog -Component "Fixes" -Message "Configuring Windows Time service to use pool.ntp.org."
        if (Get-Service -Name w32time -ErrorAction SilentlyContinue) {
            Start-Service w32time -ErrorAction SilentlyContinue
        }
        w32tm /config /update /manualpeerlist:"pool.ntp.org,0x8" /syncfromflags:MANUAL 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "w32tm /config failed with exit code $LASTEXITCODE" }

        if (Get-Service -Name w32time -ErrorAction SilentlyContinue) {
            Restart-Service w32time -ErrorAction Stop
        }
        w32tm /resync 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-WinUtilLog -Level "WARN" -Component "Fixes" -Message "w32tm /resync returned exit code $LASTEXITCODE. Time source was configured but immediate resync may require network connectivity."
            Write-Warning "Time source was configured, but immediate resync did not complete (exit code $LASTEXITCODE)."
        } else {
            Write-WinUtilLog -Component "Fixes" -Message "Windows Time service configured and resynced with pool.ntp.org."
        }
    } catch {
        Write-WinUtilLog -Level "ERROR" -Component "Fixes" -Message "Failed to configure NTP pool: $($_.Exception.Message)"
        throw
    }
}
