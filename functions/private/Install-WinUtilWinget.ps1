function Install-WinUtilWinget {
    <#

    .SYNOPSIS
        Installs WinGet if not already installed.

    .DESCRIPTION
        installs winGet if needed
    #>
    param(
        [switch]$Force
    )

    # The repair action needs Repair-WinGetPackageManager to run even when winget is detected,
    # which is the case a broken installation presents
    if (-not $Force -and (Test-WinUtilPackageManager -winget) -eq "installed") {
        return
    }

    if ($Force) {
        Write-Host "Repairing the WinGet installation..." -ForegroundColor Yellow
        Write-WinUtilLog -Component "Winget" -Message "Attempting WinGet repair."
    } else {
        Write-Host "WinGet is not installed. Installing now..." -ForegroundColor Red
        Write-WinUtilLog -Component "Winget" -Message "Attempting WinGet installation."
    }

    try {
        if (Get-Command Install-PackageProvider -ErrorAction SilentlyContinue) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue | Out-Null
        }
        if (Get-Command Install-Module -ErrorAction SilentlyContinue) {
            $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
            if ($psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
                try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}
            }
            Install-Module -Name Microsoft.WinGet.Client -Force -Scope AllUsers -ErrorAction Stop | Out-Null
        } else {
            throw "Install-Module is not available on this system."
        }

        if (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue) {
            Repair-WinGetPackageManager -AllUsers -Force -ErrorAction Stop
        } elseif (Get-Command Assert-WinGetPackageManager -ErrorAction SilentlyContinue) {
            Assert-WinGetPackageManager -ErrorAction Stop | Out-Null
        } else {
            throw "Neither Repair-WinGetPackageManager nor Assert-WinGetPackageManager is available from Microsoft.WinGet.Client. WinGet repair may not be supported on this Windows version."
        }

        Write-WinUtilLog -Component "Winget" -Message "WinGet install/repair step completed."
    } catch {
        $msg = "WinGet install/repair failed: $($_.Exception.Message)"
        Write-Warning $msg
        Write-WinUtilLog -Level "ERROR" -Component "Winget" -Message $msg
        throw
    }
}
