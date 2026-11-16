BeforeAll {
    $tweaks = Get-Content (Join-Path $PSScriptRoot '..\config\tweaks.json') -Raw | ConvertFrom-Json
    $script:removeEdge = [scriptblock]::Create($tweaks.WPFTweaksRemoveEdge.InvokeScript -join "`n")
    $script:edgeDirectory = "$Env:ProgramFiles (x86)\Microsoft\Edge\Application"
    $script:setupPath = Join-Path $script:edgeDirectory '123\Installer\setup.exe'
    $script:systemAppsPath = "$Env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"

    # Stand-ins for cmdlets that only exist on Windows so the config script can
    # run against mocks on any platform.
    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Write-WinUtilHost {
        param($Object)
    }
    function Get-AppxPackage {
        param($Name, [switch]$AllUsers)
    }
    function Remove-AppxPackage {
        param($Package, [switch]$AllUsers)
    }
    function Get-AppxProvisionedPackage {
        param([switch]$Online)
    }
    function Remove-AppxProvisionedPackage {
        param([switch]$Online, $PackageName)
    }
}

Describe 'Edge removal' {
    BeforeEach {
        Mock Write-WinUtilLog { }
        Mock Write-WinUtilHost { }
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        Mock Get-AppxPackage { }
        Mock Remove-AppxPackage { }
        Mock Get-AppxProvisionedPackage { }
        Mock Remove-AppxProvisionedPackage { }
        # Installer glob lookup and SystemApps directory lookup are separate calls.
        Mock Get-ChildItem { } -ParameterFilter { $Filter -eq 'Microsoft.MicrosoftEdge_*' }
        Mock Get-ChildItem { } -ParameterFilter { -not $Filter }
        Mock Get-Command { } -ParameterFilter { $Name -eq 'winget' }
    }

    It 'uninstalls through winget when it is available' {
        Mock Get-Command { [pscustomobject]@{ Name = 'winget' } } -ParameterFilter { $Name -eq 'winget' }
        Mock Test-Path { $false }

        & $script:removeEdge

        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'winget' -and $Wait -and
            $ArgumentList -eq 'uninstall --id Microsoft.Edge --silent --accept-source-agreements --disable-interactivity'
        }
        Should -Invoke Write-WinUtilHost -ParameterFilter { $Object -match 'completed where supported' }
    }

    It 'uses the newest legacy installer when one is present' {
        Mock Get-ChildItem {
            [pscustomobject]@{ FullName = (Join-Path $script:edgeDirectory '100\Installer\setup.exe') }
            [pscustomobject]@{ FullName = $script:setupPath }
        } -ParameterFilter { -not $Filter }
        Mock Get-ChildItem {
            [pscustomobject]@{ FullName = $script:systemAppsPath }
        } -ParameterFilter { $Filter -eq 'Microsoft.MicrosoftEdge_*' }

        & $script:removeEdge

        Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter {
            $Path -eq (Join-Path $script:systemAppsPath 'MicrosoftEdge.exe') -and $Force
        }
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq $script:setupPath -and $Wait -and
            $ArgumentList -eq '--uninstall --system-level --force-uninstall'
        }
    }

    It 'removes Edge AppX and provisioned packages but leaves WebView2 alone' {
        Mock Get-AppxPackage {
            [pscustomobject]@{ Name = 'Microsoft.MicrosoftEdge'; PackageFullName = 'Edge' }
            [pscustomobject]@{ Name = 'Microsoft.EdgeWebView2Runtime'; PackageFullName = 'WebView2' }
        }
        Mock Get-AppxProvisionedPackage {
            [pscustomobject]@{ DisplayName = 'Microsoft.MicrosoftEdge'; PackageName = 'ProvEdge' }
        }
        Mock Test-Path { $false }

        & $script:removeEdge

        Should -Invoke Remove-AppxPackage -Times 1 -Exactly -ParameterFilter { $Package -eq 'Edge' }
        Should -Invoke Remove-AppxProvisionedPackage -Times 1 -Exactly -ParameterFilter { $PackageName -eq 'ProvEdge' }
    }

    It 'keeps going and reports a best-effort failure when no method works' {
        Mock Get-AppxPackage { }
        Mock Get-AppxProvisionedPackage { }
        Mock Test-Path { $false }

        { & $script:removeEdge } | Should -Not -Throw

        Should -Invoke Write-WinUtilHost -ParameterFilter { $Object -match 'could not be removed' }
        Should -Invoke Write-WinUtilHost -Times 0 -Exactly -ParameterFilter { $Object -match 'completed where supported' }
    }

    It 'does not throw when the legacy uninstaller cannot be launched' {
        Mock Get-ChildItem {
            [pscustomobject]@{ FullName = $script:setupPath }
        } -ParameterFilter { -not $Filter }
        Mock Get-ChildItem {
            [pscustomobject]@{ FullName = $script:systemAppsPath }
        } -ParameterFilter { $Filter -eq 'Microsoft.MicrosoftEdge_*' }
        Mock Start-Process { throw 'Uninstaller launch failed' }

        { & $script:removeEdge } | Should -Not -Throw

        Should -Invoke Write-WinUtilLog -ParameterFilter { $Message -match 'legacy-setup:error=Uninstaller launch failed' }
    }

    It 'logs a single summary of the attempted removal methods' {
        Mock Get-Command { [pscustomobject]@{ Name = 'winget' } } -ParameterFilter { $Name -eq 'winget' }
        Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }

        & $script:removeEdge

        Should -Invoke Write-WinUtilLog -ParameterFilter { $Message -match 'Edge removal attempts: winget-uninstall:exit=1' }
    }
}
