#===========================================================================
# Tests - Work button routing

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    . (Join-Path $script:repoRoot "functions\public\Invoke-WPFButton.ps1")

    function Start-WinUtilJob {
        param([string]$Name, [scriptblock]$ScriptBlock, [hashtable]$Parameters)
    }
    function Step-WinUtilJob {
        param([string]$Status, [int]$Percent, [string]$State, [string]$Overlay, [switch]$Hide)
    }
    function Write-WinUtilLog {
        param($Message, $Level, $Component)
    }
    function Write-WinUtilErrorRecord {
        param($ErrorRecord, $Component, $Context)
    }
    function Invoke-WPFFeatureInstall { }
}

Describe "Work button preflight" {
    BeforeEach {
        $script:sync = [Hashtable]::Synchronized(@{
            ActiveJob = $null
            configs = @{
                feature = @{
                    WPFFeatureInstall = [pscustomobject]@{
                        Content = "Install Features"
                        function = "Invoke-WPFFeatureInstall"
                    }
                }
            }
        })
        Mock Step-WinUtilJob { }
        Mock Write-WinUtilLog { }
        Mock Write-WinUtilErrorRecord { }
        Mock Invoke-WPFFeatureInstall { }
        Mock Start-WinUtilJob {
            $script:capturedJob = [pscustomobject]@{
                Name = $Name
                ScriptBlock = $ScriptBlock
                Parameters = $Parameters
            }
        }
    }

    AfterEach {
        Remove-Variable -Name sync -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name capturedJob -Scope Script -ErrorAction SilentlyContinue
    }

    It "lets feature installation validate its selection before starting a job" {
        Invoke-WPFButton -Button "WPFFeatureInstall"

        Should -Invoke Invoke-WPFFeatureInstall -Times 1 -Exactly
        Should -Invoke Start-WinUtilJob -Times 0 -Exactly
    }
}
