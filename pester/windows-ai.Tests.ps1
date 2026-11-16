#===========================================================================
# Tests - Windows AI Tweak InvokeScript
#===========================================================================
# Covers WPFTweaksWindowsAI (config/tweaks.json): Windows 10 builds skip the
# package/feature removal steps, Windows 11 removes the AI AppX packages and
# disables WSAIFabricSvc, and the Recall feature is disabled through a
# noninteractive Windows PowerShell child process. A failing Recall step warns
# and continues; an unexpected error is logged as ERROR and rethrown.

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $tweaks = Get-Content -Path (Join-Path $script:repoRoot "config\tweaks.json") -Raw | ConvertFrom-Json
    $script:windowsAI = [scriptblock]::Create(@($tweaks.WPFTweaksWindowsAI.InvokeScript) -join "`n")

    function Write-WinUtilLog { param($Message, $Level, $Component) }
    function Write-WinUtilHost { param($Object) }
    function Get-AppxPackage { param($Name, [switch]$AllUsers) }
    function Remove-AppxPackage { param($Package, [switch]$AllUsers) }
    function Get-LocalUser { param($Name) }
    function Get-Service { param($Name) }
    function Set-Service { param($Name, $StartupType) }
    function Get-CimInstance { param($ClassName) }
    function Get-Command { param($Name) }
    function powershell.exe {
        param([switch]$NoProfile, [switch]$NonInteractive, [scriptblock]$Command)
    }
}

Describe "WPFTweaksWindowsAI InvokeScript" {
    BeforeEach {
        $script:savedExitCode = $global:LASTEXITCODE

        Mock Get-CimInstance { [pscustomobject]@{ BuildNumber = '22631' } }
        Mock Get-AppxPackage { }
        Mock Remove-AppxPackage { }
        Mock Get-LocalUser { [pscustomobject]@{ Sid = [pscustomobject]@{ Value = 'S-1-5-21-1234' } } }
        Mock Get-Service { [pscustomobject]@{ Name = 'WSAIFabricSvc' } }
        Mock Set-Service { }
        Mock Get-Command { }
        Mock powershell.exe { $global:LASTEXITCODE = 0; 'Recall disabled' }
        Mock New-Item { }
        Mock Start-Process { }
        Mock Write-Host { }
        Mock Write-WinUtilHost { }
        Mock Write-WinUtilLog { }
    }

    AfterEach { $global:LASTEXITCODE = $script:savedExitCode }

    It "skips package and feature removal on Windows 10 but keeps the policy note" {
        Mock Get-CimInstance { [pscustomobject]@{ BuildNumber = '19045' } }

        & $script:windowsAI

        Should -Invoke -CommandName Remove-AppxPackage -Times 0 -Exactly
        Should -Invoke -CommandName powershell.exe -Times 0 -Exactly
        Should -Invoke -CommandName Set-Service -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilHost -Times 1 -Exactly -ParameterFilter {
            $Object -match 'not applicable on Windows 10'
        }
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'INFO' -and $Message -match 'Windows 10 build 19045'
        }
    }

    It "falls back to the OS version when the build query fails" {
        Mock Get-CimInstance { throw 'CIM unavailable' }

        { & $script:windowsAI } | Should -Not -Throw

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'INFO' -and $Message -match 'Windows 10 build ' -or $Message -match 'Skipped inapplicable Windows AI'
        }
    }

    It "removes Copilot, Office Hub, and CoreAI and disables the AI fabric service" {
        Mock Get-AppxPackage {
            [pscustomobject]@{ Name = 'Copilot'; PackageFullName = 'Copilot_1' }
        } -ParameterFilter { $Name -eq '*Copilot*' }
        Mock Get-AppxPackage {
            [pscustomobject]@{ Name = 'Microsoft.MicrosoftOfficeHub'; PackageFullName = 'OfficeHub_1' }
        } -ParameterFilter { $Name -eq 'Microsoft.MicrosoftOfficeHub' }
        Mock Get-AppxPackage {
            [pscustomobject]@{ Name = 'MicrosoftWindows.Client.CoreAI'; PackageFullName = 'CoreAI_1' }
        } -ParameterFilter { $Name -eq 'MicrosoftWindows.Client.CoreAI' }

        & $script:windowsAI

        Should -Invoke -CommandName Remove-AppxPackage -Times 3 -Exactly
        Should -Invoke -CommandName New-Item -Times 1 -Exactly -ParameterFilter {
            $Path -like '*AppxAllUserStore\EndOfLife\S-1-5-21-1234\CoreAI_1' -and $Force
        }
        Should -Invoke -CommandName Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'WSAIFabricSvc' -and $StartupType -eq 'Disabled'
        }
        Should -Invoke -CommandName Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match 'completed where applicable'
        }
    }

    It "does not touch Set-Service when the AI fabric service is absent" {
        Mock Get-Service { }

        & $script:windowsAI

        Should -Invoke -CommandName Set-Service -Times 0 -Exactly
    }

    It "runs Recall through a noninteractive Windows PowerShell process" {
        & $script:windowsAI

        Should -Invoke -CommandName powershell.exe -Times 1 -Exactly -ParameterFilter {
            $NoProfile -and $NonInteractive -and $Command -is [scriptblock]
        }
        Should -Invoke -CommandName Write-WinUtilHost -Times 1 -Exactly -ParameterFilter {
            $Object -eq 'Recall disabled'
        }
    }

    It "warns and continues when the Recall child exits nonzero" {
        Mock powershell.exe { $global:LASTEXITCODE = 1; 'Class not registered' }

        { & $script:windowsAI } | Should -Not -Throw

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'WARN' -and $Message -match 'Recall disable step did not complete' -and $Message -match 'Class not registered'
        }
        Should -Invoke -CommandName Write-WinUtilHost -Times 1 -Exactly -ParameterFilter {
            $Object -match 'Recall feature could not be disabled'
        }
        Should -Invoke -CommandName Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match 'completed where applicable'
        }
    }

    It "logs an ERROR and rethrows an unexpected failure" {
        Mock Get-AppxPackage { throw 'simulated AppX enumeration failure' } -ParameterFilter { $Name -eq '*Copilot*' }

        { & $script:windowsAI } | Should -Throw '*simulated AppX enumeration failure*'

        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'ERROR' -and $Message -match 'encountered an error' -and $Message -match 'simulated AppX enumeration failure'
        }
        Should -Invoke -CommandName Write-Host -Times 0 -Exactly
    }

    It "keeps a per-package removal failure at WARN without aborting" {
        Mock Get-AppxPackage {
            [pscustomobject]@{ Name = 'Copilot'; PackageFullName = 'Copilot_1' }
        } -ParameterFilter { $Name -eq '*Copilot*' }
        Mock Remove-AppxPackage { throw 'package is in use' }

        { & $script:windowsAI } | Should -Not -Throw

        Should -Invoke -CommandName Write-WinUtilLog -ParameterFilter {
            $Level -eq 'WARN' -and $Message -match 'Unable to remove AppX package Copilot' -and $Message -match 'package is in use'
        }
    }
}
