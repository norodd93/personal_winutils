# Execute the configured scripts through the real tweak orchestrator. All service
# operations are mocked so these tests never change the machine's indexer.
# Get-Service/Stop-Service/Start-Service do not exist off Windows, so plain
# stand-in functions are defined for Pester to mock.
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'functions/private/Invoke-WinUtilTweaks.ps1')
    $script:searchTweaks = Get-Content (Join-Path $repoRoot 'config/tweaks.json') -Raw | ConvertFrom-Json

    function Write-WinUtilHost { param($Object) }
    function Write-WinUtilLog { param($Level, $Component, $Message) }
    function Set-WinUtilService { param($Name, $StartupType) }
    function Invoke-WinUtilScript { param($Name, [scriptblock]$ScriptBlock) }
    function Get-Service { param($Name) }
    function Stop-Service { param($Name, [switch]$Force) }
    function Start-Service { param($Name) }
}

Describe 'Windows Search indexing apply and undo' {
    BeforeEach {
        $script:sync = @{ configs = @{ tweaks = $script:searchTweaks } }
        $script:searchService = [pscustomobject]@{ StartType = 'Automatic'; Status = 'Running' }
        $script:hostMessages = [System.Collections.Generic.List[string]]::new()
        $script:logMessages = [System.Collections.Generic.List[object]]::new()

        Mock Get-Service { $script:searchService } -ParameterFilter { $Name -eq 'WSearch' }
        Mock Set-WinUtilService { $script:searchService.StartType = $StartupType }
        Mock Invoke-WinUtilScript { & $ScriptBlock }
        Mock Stop-Service { $script:searchService.Status = 'Stopped' }
        Mock Start-Service { $script:searchService.Status = 'Running' }
        Mock Write-WinUtilHost { param($Object) $script:hostMessages.Add([string]$Object) }
        Mock Write-WinUtilLog {
            param($Level, $Component, $Message)
            $script:logMessages.Add([pscustomobject]@{ Level = $Level; Component = $Component; Message = [string]$Message })
        }
        Mock Write-Warning { }
    }

    AfterEach {
        Remove-Variable sync -Scope Script -ErrorAction SilentlyContinue
    }

    function script:Get-TestHostMatches([string]$Pattern) {
        @($script:hostMessages | Where-Object { $_ -match $Pattern })
    }

    function script:Get-TestLogMatches([string]$Pattern) {
        @($script:logMessages | Where-Object { $_.Message -match $Pattern })
    }

    It 'disables and stops an automatic indexer, then restores and starts it' {
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableSearchIndexing'
        $script:searchService.StartType | Should -Be 'Disabled'
        $script:searchService.Status | Should -Be 'Stopped'
        Should -Invoke Set-WinUtilService -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'WSearch' -and $StartupType -eq 'Disabled'
        }
        Should -Invoke Stop-Service -Times 1 -Exactly -ParameterFilter { $Name -eq 'WSearch' }
        (Get-TestHostMatches 'has been stopped').Count | Should -Be 1

        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableSearchIndexing' -undo $true
        $script:searchService.StartType | Should -Be 'Automatic'
        $script:searchService.Status | Should -Be 'Running'
        Should -Invoke Set-WinUtilService -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'WSearch' -and $StartupType -eq 'Automatic'
        }
        Should -Invoke Start-Service -Times 1 -Exactly -ParameterFilter { $Name -eq 'WSearch' }
        (Get-TestHostMatches 'started and enabled').Count | Should -Be 1
    }

    It 'preserves a Manual running service on apply and undo without touching it' {
        $script:searchService.StartType = 'Manual'
        $script:searchService.Status = 'Running'
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableSearchIndexing'
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableSearchIndexing' -undo $true
        $script:searchService.StartType | Should -Be 'Manual'
        $script:searchService.Status | Should -Be 'Running'
        Should -Invoke Set-WinUtilService -Times 0 -Exactly
        Should -Invoke Stop-Service -Times 0 -Exactly
        Should -Invoke Start-Service -Times 0 -Exactly
        Should -Invoke Write-Warning -Times 2 -Exactly -ParameterFilter { $Message -match 'WSearch.*Manual' }
        (Get-TestHostMatches 'still enabled \(Manual\); no stop was attempted').Count | Should -Be 1
        (Get-TestHostMatches 'already running').Count | Should -Be 1
    }

    It 'reports an already-stopped Manual service instead of stopping it' {
        $script:searchService.StartType = 'Manual'
        $script:searchService.Status = 'Stopped'
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableSearchIndexing'
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableSearchIndexing' -undo $true
        $script:searchService.StartType | Should -Be 'Manual'
        $script:searchService.Status | Should -Be 'Stopped'
        Should -Invoke Set-WinUtilService -Times 0 -Exactly
        Should -Invoke Stop-Service -Times 0 -Exactly
        Should -Invoke Start-Service -Times 0 -Exactly
        Should -Invoke Write-Warning -Times 2 -Exactly -ParameterFilter { $Message -match 'WSearch.*Manual' }
        (Get-TestHostMatches 'already stopped').Count | Should -Be 1
        (Get-TestHostMatches 'startup type is Manual; no start was attempted').Count | Should -Be 1
    }

    It 'does not stop a service that is still enabled and reports why' {
        $script:searchService.StartType = 'Automatic'
        $script:searchService.Status = 'Running'
        Mock Set-WinUtilService { }

        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableSearchIndexing'

        Should -Invoke Stop-Service -Times 0 -Exactly
        $script:searchService.Status | Should -Be 'Running'
        (Get-TestHostMatches 'still enabled \(Automatic\)').Count | Should -Be 1
        (Get-TestLogMatches 'WSearch service still enabled \(Automatic\)').Count | Should -Be 1
        @(Get-TestLogMatches 'WSearch service still enabled \(Automatic\)' | Where-Object { $_.Level -eq 'WARN' }).Count | Should -Be 1
    }

    It 'does not stop the indexer when setting Disabled fails' {
        Mock Set-WinUtilService { }
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableSearchIndexing'
        Should -Invoke Stop-Service -Times 0 -Exactly
        $script:searchService.Status | Should -Be 'Running'
    }

    It 'does not start the indexer when restoring Automatic fails' {
        $script:searchService.StartType = 'Disabled'
        $script:searchService.Status = 'Stopped'
        Mock Set-WinUtilService { }
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableSearchIndexing' -undo $true
        Should -Invoke Start-Service -Times 0 -Exactly
    }

    It 'does not repeat stop or start operations after reaching the desired state' {
        $script:searchService.StartType = 'Disabled'
        $script:searchService.Status = 'Stopped'
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableSearchIndexing'
        Should -Invoke Stop-Service -Times 0 -Exactly
        (Get-TestHostMatches 'already stopped').Count | Should -Be 1
        $script:searchService.StartType = 'Automatic'
        $script:searchService.Status = 'Running'
        Invoke-WinUtilTweaks -CheckBox 'WPFTweaksDisableSearchIndexing' -undo $true
        Should -Invoke Start-Service -Times 0 -Exactly
        (Get-TestHostMatches 'already running').Count | Should -Be 1
    }

    It 'skips absent WSearch in both configured scripts' {
        Mock Get-Service { $null } -ParameterFilter { $Name -eq 'WSearch' }
        & ([scriptblock]::Create($script:searchTweaks.WPFTweaksDisableSearchIndexing.InvokeScript -join "`n"))
        & ([scriptblock]::Create($script:searchTweaks.WPFTweaksDisableSearchIndexing.UndoScript -join "`n"))
        Should -Invoke Stop-Service -Times 0 -Exactly
        Should -Invoke Start-Service -Times 0 -Exactly
        (Get-TestHostMatches 'not present').Count | Should -Be 2
        @(Get-TestLogMatches 'WSearch service not present' | Where-Object { $_.Level -eq 'WARN' }).Count | Should -Be 2
    }

    It 'propagates stop and start failures from the configured scripts' {
        $script:searchService.StartType = 'Disabled'
        Mock Stop-Service { throw 'Indexer stop failed' }
        { & ([scriptblock]::Create($script:searchTweaks.WPFTweaksDisableSearchIndexing.InvokeScript -join "`n")) } | Should -Throw '*Indexer stop failed*'
        $script:searchService.StartType = 'Automatic'
        $script:searchService.Status = 'Stopped'
        Mock Start-Service { throw 'Indexer start failed' }
        { & ([scriptblock]::Create($script:searchTweaks.WPFTweaksDisableSearchIndexing.UndoScript -join "`n")) } | Should -Throw '*Indexer start failed*'
    }
}
