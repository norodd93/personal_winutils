function Remove-WinUtilAPPX {
    <#

    .SYNOPSIS
        Removes all APPX packages that match the given name

    .PARAMETER Name
        The name of the APPX package to remove

    .EXAMPLE
        Remove-WinUtilAPPX -Name "Microsoft.Microsoft3DViewer"

    #>
    param (
        $Name
    )

    Write-Host "Removing $Name"
    Write-WinUtilLog -Component "AppX" -Message "Removing AppX package pattern: $Name"

    # The Appx module cannot load in PowerShell 7 on Windows 10: Get-AppxPackage fails with
    # "Operation is not supported on this platform" (0x80131539) before any package is queried.
    # Query and remove in Windows PowerShell 5.1 like Remove-WinUtilProvisionedAPPX and
    # Get-WinUtilInstalledAPPX do. We loop through the packages instead of using the pipeline
    # because PowerShell 7 pipeline binding for Remove-AppxPackage fails silently, and
    # Get-AppxPackage -AllUsers returns duplicate objects for each user profile.
    $ps5Command = {
        $ErrorActionPreference = 'Stop'
        $packageName = $args[0]
        $pkgs = Get-AppxPackage "*$packageName*" -AllUsers | Sort-Object -Property PackageFullName -Unique
        $failures = [System.Collections.Generic.List[string]]::new()

        if ($null -ne $pkgs) {
            foreach ($pkg in $pkgs) {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                }
                catch {
                    # Windows 10 can fail a cross-user removal with 0x80070002 even though the
                    # package is healthy; removing it for the calling user still works.
                    $allUsersError = $_.Exception.Message
                    try {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                        Write-Output "Removed $($pkg.PackageFullName) for the current user only; -AllUsers failed: $allUsersError"
                    }
                    catch {
                        $failures.Add("Failed to remove AppX package $($pkg.PackageFullName): $($_.Exception.Message) (all users: $allUsersError)")
                    }
                }
            }
        }

        if ($failures.Count -gt 0) {
            throw ($failures -join [Environment]::NewLine)
        }
    }

    $removalOutput = powershell.exe -NoProfile -NonInteractive -Command $ps5Command -args $Name 2>&1
    if ($LASTEXITCODE -ne 0) {
        $failureDetails = ($removalOutput | Out-String).Trim()
        Write-WinUtilLog -Level "ERROR" -Component "AppX" -Message "Failed to remove AppX packages matching $Name`: $failureDetails"
    }
    else {
        foreach ($outputLine in @($removalOutput)) {
            $note = ($outputLine | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($note)) {
                Write-WinUtilLog -Level "WARN" -Component "AppX" -Message $note
            }
        }
    }

    Write-WinUtilLog -Component "AppX" -Message "AppX removal completed for package pattern: $Name"
}
