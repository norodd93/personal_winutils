#===========================================================================
# Tests - OneDrive Removal Tweak InvokeScript
#===========================================================================
# Covers WPFTweaksRemoveOneDrive (config/tweaks.json) on a platform-agnostic
# basis: the ACL object is a plain stand-in (DirectorySecurity is Windows-only).
# The script must never delete the OneDrive folder when enumeration fails,
# must preserve files it cannot confirm are empty, must restore the captured
# ACL in a finally block, and must continue best-effort through per-step
# failures rather than throwing.

BeforeAll {
    $tweaks = Get-Content (Join-Path $PSScriptRoot '..\config\tweaks.json') -Raw | ConvertFrom-Json
    $invokeText = @($tweaks.WPFTweaksRemoveOneDrive.InvokeScript) -join "`n"
    # Intercept the persistent environment write; filesystem fixtures stay in TestDrive.
    $invokeText = $invokeText.Replace("[Environment]::SetEnvironmentVariable('OneDrive', `$null, 'User')", 'Clear-TestOneDriveEnvironment')
    $script:removeOneDrive = [scriptblock]::Create($invokeText)

    # Windows-only / external commands are stand-ins so they can be mocked here.
    function Write-WinUtilLog { param($Message, $Level, $Component) }
    function Write-WinUtilHost { param($Object) }
    function icacls { param($Target, $Operation, $Principal) }
    function Get-Acl { param($LiteralPath) }
    function Set-Acl { param($LiteralPath, $AclObject) }
    function Get-Process { param($Name) }
    function Stop-Process { param($InputObject, [switch]$Force) }
    function Set-Service { param($Name, $StartupType) }
    function Get-Command { param($Name) }
    function Start-Process { param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru, [switch]$NoNewWindow) }
    function Clear-TestOneDriveEnvironment { }
}

Describe 'OneDrive removal' {
    BeforeEach {
        $script:savedOneDrive = $Env:OneDrive
        $script:savedLocalAppData = $Env:LocalAppData
        $script:savedProgramData = $Env:ProgramData
        $script:savedExitCode = $global:LASTEXITCODE
        $script:savedSystemRoot = $Env:SystemRoot
        $script:fixtureRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $script:oneDrivePath = Join-Path $script:fixtureRoot 'OneDrive'
        $Env:OneDrive = $script:oneDrivePath
        $Env:LocalAppData = Join-Path $script:fixtureRoot 'LocalAppData'
        $Env:ProgramData = Join-Path $script:fixtureRoot 'ProgramData'
        $Env:SystemRoot = $script:fixtureRoot
        $script:aclOperations = [System.Collections.Generic.List[string]]::new()
        $script:processNames = [System.Collections.Generic.List[string]]::new()
        $script:stopCount = 0
        $script:originalAcl = [pscustomobject]@{ Kind = 'DirectorySecurity stand-in' }

        Mock Write-WinUtilLog { }
        Mock Write-WinUtilHost { }
        Mock Test-Path { $false }
        Mock Get-Acl { $script:originalAcl }
        Mock Set-Acl { $script:aclOperations.Add('restore') }
        Mock icacls {
            $script:aclOperations.Add($Operation)
            $global:LASTEXITCODE = 0
        }
        Mock Start-Process { }
        Mock Get-Process { }
        Mock Stop-Process { }
        Mock Set-Service { }
        Mock Get-Command { }
        Mock Clear-TestOneDriveEnvironment { }
    }

    AfterEach {
        $Env:OneDrive = $script:savedOneDrive
        $Env:LocalAppData = $script:savedLocalAppData
        $Env:ProgramData = $script:savedProgramData
        $Env:SystemRoot = $script:savedSystemRoot
        $global:LASTEXITCODE = $script:savedExitCode
    }

    It 'skips ACL work and folder removal when the folder is absent' {
        $Env:OneDrive = Join-Path $script:fixtureRoot 'does-not-exist'
        & $script:removeOneDrive

        Should -Invoke Get-Acl -Times 0 -Exactly
        Should -Invoke icacls -Times 0 -Exactly
        Should -Invoke Set-Acl -Times 0 -Exactly
        Should -Invoke Clear-TestOneDriveEnvironment -Times 0 -Exactly
        Should -Invoke Write-WinUtilHost -ParameterFilter { $Object -match 'not present for this profile' }
    }

    It 'still disables the OneSyncSvc template when it is present' {
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq 'HKLM:\SYSTEM\CurrentControlSet\Services\OneSyncSvc' }

        & $script:removeOneDrive

        Should -Invoke Set-Service -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'OneSyncSvc' -and $StartupType -eq 'Disabled'
        }
    }

    It 'stops the related OneDrive processes best-effort' {
        Mock Get-Process {
            $script:processNames.Add([string]$Name)
            [pscustomobject]@{ ProcessName = $Name }
        } -ParameterFilter { $Name }
        Mock Stop-Process { $script:stopCount++ }

        & $script:removeOneDrive

        $script:processNames | Should -Contain 'OneDrive'
        $script:processNames | Should -Contain 'FileCoAuth'
        $script:processNames | Should -Contain 'OneDriveStandaloneUpdater'
        $script:stopCount | Should -Be 3
    }

    It 'captures ACL, denies write, restores it, and deletes an empty folder' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $script:oneDrivePath }

        & $script:removeOneDrive

        $script:aclOperations.ToArray() | Should -Be @('/deny', 'restore')
        Should -Invoke Set-Acl -Times 1 -Exactly -ParameterFilter {
            $LiteralPath -eq $script:oneDrivePath -and $AclObject -eq $script:originalAcl
        }
        Should -Invoke Clear-TestOneDriveEnvironment -Times 1 -Exactly
        [System.IO.Directory]::Exists($script:oneDrivePath) | Should -BeFalse
    }

    It 'preserves a folder that is not empty' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        $file = New-Item -ItemType File -Path (Join-Path $script:oneDrivePath 'notes.txt')
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $script:oneDrivePath }

        & $script:removeOneDrive

        [System.IO.File]::Exists($file.FullName) | Should -BeTrue
        Should -Invoke Clear-TestOneDriveEnvironment -Times 0 -Exactly
        Should -Invoke Write-WinUtilLog -ParameterFilter { $Message -match 'not removed because it is not empty' }
    }

    It 'does not delete the folder or clear the variable when enumeration fails' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $script:oneDrivePath }
        Mock Get-ChildItem { throw 'Enumeration access denied' } -ParameterFilter { $LiteralPath -eq $script:oneDrivePath }

        { & $script:removeOneDrive } | Should -Not -Throw

        [System.IO.Directory]::Exists($script:oneDrivePath) | Should -BeTrue
        Should -Invoke Clear-TestOneDriveEnvironment -Times 0 -Exactly
        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'WARN' -and $Message -match 'folder was not removed' -and $Message -match 'Enumeration access denied'
        }
    }

    It 'continues best-effort when the ACL cannot be captured' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $script:oneDrivePath }
        Mock Get-Acl { throw 'ACL read denied' }

        { & $script:removeOneDrive } | Should -Not -Throw

        Should -Invoke Set-Acl -Times 0 -Exactly
        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'WARN' -and $Message -match 'Failed to capture OneDrive ACL'
        }
    }

    It 'continues when protecting the folder fails but still restores later' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $script:oneDrivePath }
        Mock icacls { throw 'deny failed' }

        { & $script:removeOneDrive } | Should -Not -Throw

        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'WARN' -and $Message -match 'Unable to protect OneDrive folder'
        }
        # The captured ACL is still restored in the finally block.
        $script:aclOperations.ToArray() | Should -Be @('restore')
    }

    It 'reports an unconfirmed uninstall and preserves a non-empty folder' {
        New-Item -ItemType Directory -Path $script:oneDrivePath -Force | Out-Null
        $file = New-Item -ItemType File -Path (Join-Path $script:oneDrivePath 'notes.txt')
        $setup32 = "$Env:SystemRoot\System32\OneDriveSetup.exe"
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $script:oneDrivePath }
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $setup32 }
        Mock Start-Process { throw 'Uninstaller failed' }

        { & $script:removeOneDrive } | Should -Not -Throw

        [System.IO.File]::Exists($file.FullName) | Should -BeTrue
        Should -Invoke Write-WinUtilLog -Times 1 -Exactly -ParameterFilter {
            $Level -eq 'WARN' -and $Message -match 'OneDrive setup uninstall failed' -and $Message -match 'Uninstaller failed'
        }
        Should -Invoke Write-WinUtilHost -ParameterFilter { $Object -match 'could not be fully confirmed' }
        $script:aclOperations.ToArray() | Should -Be @('/deny', 'restore')
    }

    It 'cleans up leftover directories that exist' {
        $leftoverPath = Join-Path $Env:LocalAppData 'Microsoft\OneDrive'
        New-Item -ItemType Directory -Path $leftoverPath -Force | Out-Null
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $leftoverPath }

        & $script:removeOneDrive

        [System.IO.Directory]::Exists($leftoverPath) | Should -BeFalse
    }
}
