#===========================================================================
# Tests - BitLocker Disable Tweak InvokeScript
#===========================================================================
# Covers WPFTweaksDisableBitLocker (config/tweaks.json): the apply script must
# query Get-BitLockerVolume and skip Disable-BitLocker when VolumeStatus is
# FullyDecrypted. ProtectionStatus Off alone is not sufficient: an encrypted
# volume with suspended protection must still be disabled. Query and disable
# failures must propagate instead of being swallowed. The undo script must not
# re-enable BitLocker automatically; it reports that manual action is required.

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:tweakName = "WPFTweaksDisableBitLocker"
    $tweaks = Get-Content -Path (Join-Path $script:repoRoot "config\tweaks.json") -Raw | ConvertFrom-Json
    $script:invokeText = @($tweaks.$script:tweakName.InvokeScript) -join "`n"
    $script:invokeBlock = [scriptblock]::Create($script:invokeText)
    $script:undoText = @($tweaks.$script:tweakName.UndoScript) -join "`n"
    $script:undoBlock = [scriptblock]::Create($script:undoText)

    function Get-BitLockerVolume {
        [CmdletBinding()]
        param($MountPoint)
        throw "Get-BitLockerVolume must be mocked for $MountPoint."
    }
    function Disable-BitLocker {
        [CmdletBinding()]
        param($MountPoint)
        throw "Disable-BitLocker must be mocked for $MountPoint."
    }
    function Enable-BitLocker {
        [CmdletBinding()]
        param($MountPoint)
        throw "Enable-BitLocker must not be called: $MountPoint"
    }
    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Write-WinUtilHost {
        param($Object)
    }
}

Describe "WPFTweaksDisableBitLocker InvokeScript" {
    BeforeEach {
        Mock Get-BitLockerVolume { }
        Mock Disable-BitLocker { }
        Mock Write-WinUtilLog { }
        Mock Write-WinUtilHost { }
    }

    It "skips Disable-BitLocker and reports already-off when FullyDecrypted" {
        Mock Get-BitLockerVolume {
            [pscustomobject]@{
                MountPoint           = $Env:SystemDrive
                VolumeStatus         = "FullyDecrypted"
                ProtectionStatus     = "Off"
                EncryptionPercentage = 0
            }
        }

        & $script:invokeBlock

        Should -Invoke -CommandName Get-BitLockerVolume -Times 1 -Exactly -ParameterFilter {
            $MountPoint -eq $Env:SystemDrive
        }
        Should -Invoke -CommandName Disable-BitLocker -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilHost -Times 1 -Exactly -ParameterFilter {
            $Object -match "already disabled"
        }
    }

    It "still disables an encrypted volume with ProtectionStatus Off" {
        Mock Get-BitLockerVolume {
            [pscustomobject]@{
                MountPoint           = $Env:SystemDrive
                VolumeStatus         = "FullyEncrypted"
                ProtectionStatus     = "Off"
                EncryptionPercentage = 100
            }
        }

        & $script:invokeBlock

        Should -Invoke -CommandName Disable-BitLocker -Times 1 -Exactly -ParameterFilter {
            $MountPoint -eq $Env:SystemDrive
        }
    }

    It "disables an encrypted volume with ProtectionStatus On" {
        Mock Get-BitLockerVolume {
            [pscustomobject]@{
                MountPoint           = $Env:SystemDrive
                VolumeStatus         = "FullyEncrypted"
                ProtectionStatus     = "On"
                EncryptionPercentage = 100
            }
        }

        & $script:invokeBlock

        Should -Invoke -CommandName Disable-BitLocker -Times 1 -Exactly -ParameterFilter {
            $MountPoint -eq $Env:SystemDrive
        }
    }

    It "propagates Get-BitLockerVolume failures without calling Disable-BitLocker" {
        Mock Get-BitLockerVolume { throw "simulated BitLocker query failure" }

        { & $script:invokeBlock } | Should -Throw -ExpectedMessage "*simulated BitLocker query failure*"
        Should -Invoke -CommandName Get-BitLockerVolume -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
        Should -Invoke -CommandName Disable-BitLocker -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilLog -Times 1 -Exactly -ParameterFilter { $Level -eq 'ERROR' }
    }

    It "propagates Disable-BitLocker failures" {
        Mock Get-BitLockerVolume {
            [pscustomobject]@{
                MountPoint           = $Env:SystemDrive
                VolumeStatus         = "FullyEncrypted"
                ProtectionStatus     = "On"
                EncryptionPercentage = 100
            }
        }
        Mock Disable-BitLocker { throw "simulated BitLocker disable failure" }

        { & $script:invokeBlock } | Should -Throw -ExpectedMessage "*simulated BitLocker disable failure*"
    }

    It "makes a non-terminating disable error stop the script" {
        Mock Get-BitLockerVolume { [pscustomobject]@{ VolumeStatus = 'FullyEncrypted' } }
        Mock Disable-BitLocker { Write-Error 'simulated non-terminating disable failure' }
        { & $script:invokeBlock } | Should -Throw '*simulated non-terminating disable failure*'
        Should -Invoke Disable-BitLocker -Times 1 -Exactly -ParameterFilter { $ErrorAction -eq 'Stop' }
    }

    It "warns and returns when the BitLocker cmdlets are unavailable" {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-BitLockerVolume' }

        & $script:invokeBlock

        Should -Invoke -CommandName Get-BitLockerVolume -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilHost -Times 1 -Exactly -ParameterFilter {
            $Object -match 'not available'
        }
    }
}

Describe "WPFTweaksDisableBitLocker UndoScript" {
    BeforeEach {
        Mock Write-WinUtilLog { }
        Mock Write-WinUtilHost { }
        Mock Enable-BitLocker { }
    }

    It "does not re-enable BitLocker automatically and explains manual action" {
        Mock Get-BitLockerVolume {
            [pscustomobject]@{ MountPoint = $Env:SystemDrive; ProtectionStatus = 'Off'; VolumeStatus = 'FullyDecrypted' }
        }

        & $script:undoBlock

        Should -Invoke -CommandName Enable-BitLocker -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilHost -ParameterFilter { $Object -match 'manually' }
    }

    It "reports when BitLocker is already protected" {
        Mock Get-BitLockerVolume {
            [pscustomobject]@{ MountPoint = $Env:SystemDrive; ProtectionStatus = 'On'; VolumeStatus = 'FullyEncrypted' }
        }

        & $script:undoBlock

        Should -Invoke -CommandName Enable-BitLocker -Times 0 -Exactly
        Should -Invoke -CommandName Write-WinUtilHost -ParameterFilter { $Object -match 'already' }
    }

    It "keeps the undo script free of an automatic Enable-BitLocker call" {
        $script:undoText | Should -Not -Match 'Enable-BitLocker\s+-MountPoint'
    }
}
