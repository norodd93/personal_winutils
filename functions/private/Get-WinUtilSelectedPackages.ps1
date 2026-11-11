function Get-WinUtilSelectedPackages {

     param(
         [Parameter(Mandatory = $true)]
         [object] $PackageList,

         [Parameter(Mandatory = $true)]
         [string] $Preference,

         [ValidateSet("Install", "Uninstall")]
         [string] $Action = "Install"
     )

    # A single package has no meaningful percentage to show
    if ($PackageList.count -eq 1) {
        Step-WinUtilJob -State "Indeterminate"
    }

    $packagesWinget = [System.Collections.ArrayList]::new()
    $packagesChoco = [System.Collections.ArrayList]::new()
    $packages = @{
        Winget = $packagesWinget
        Choco = $packagesChoco
    }

    function Add-PackageId {
        param(
            [System.Collections.ArrayList]$Target,
            $PackageId
        )

        # A config field may hold several IDs separated by ";" (e.g. a dependency;the package).
        # Detection splits the same way, so install and detection agree on what gets installed.
        $ids = [string]$PackageId -split ";"
        if ($Action -eq "Uninstall") {
            # Detection identifies the last ID as the app; preceding IDs are dependencies.
            $ids = @($ids[-1])
        }
        foreach ($id in $ids) {
            $id = $id.Trim()
            if ([string]::IsNullOrWhiteSpace($id) -or $id -eq "na") {
                continue
            }

            if (-not $Target.Contains($id)) {
                $null = $Target.Add($id)
            }
        }
    }

    foreach ($package in $PackageList) {
        $wingetId = [string]$package.winget
        $chocoId = [string]$package.choco
        $content = if ($package.PSObject.Properties.Name -contains "content" -and -not [string]::IsNullOrWhiteSpace([string]$package.content)) { [string]$package.content } else { $wingetId }

        switch ($Preference) {
            "Choco" {
                if ([string]::IsNullOrWhiteSpace($chocoId) -or $chocoId -eq "na") {
                    if ([string]::IsNullOrWhiteSpace($wingetId) -or $wingetId -eq "na") {
                        Write-Warning "No package ID available for '$content'; skipping."
                        Write-WinUtilLog -Level "WARN" -Component "Packages" -Message "No package ID available for '$content'; skipping $Action."
                    } else {
                        Add-PackageId -Target $packagesWinget -PackageId $wingetId
                    }
                } else {
                    Add-PackageId -Target $packagesChoco -PackageId $chocoId
                }
            }
            "Winget" {
                if ([string]::IsNullOrWhiteSpace($wingetId) -or $wingetId -eq "na") {
                    if ([string]::IsNullOrWhiteSpace($chocoId) -or $chocoId -eq "na") {
                        Write-Warning "No package ID available for '$content'; skipping."
                        Write-WinUtilLog -Level "WARN" -Component "Packages" -Message "No package ID available for '$content'; skipping $Action."
                    } else {
                        Write-WinUtilLog -Level "WARN" -Component "Packages" -Message "Winget ID unavailable for '$content'; falling back to Chocolatey."
                        Add-PackageId -Target $packagesChoco -PackageId $chocoId
                    }
                } else {
                    Add-PackageId -Target $packagesWinget -PackageId $wingetId
                }
            }
        }
    }

    return $packages
}
