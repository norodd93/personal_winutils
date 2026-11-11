function Get-WinUtilOSInfo {
    <#
    .SYNOPSIS
        Returns basic Windows version information for feature/tweak gating.
    #>
    if ($null -ne $script:WinUtilOSInfo) {
        return $script:WinUtilOSInfo
    }

    $build = 0
    $caption = $null
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $caption = [string]$os.Caption
        [int]::TryParse([string]$os.BuildNumber, [ref]$build) | Out-Null
    } catch {
        try {
            $build = [int][Environment]::OSVersion.Version.Build
        } catch {
            $build = 0
        }
    }

    $script:WinUtilOSInfo = [pscustomobject]@{
        Caption     = $caption
        BuildNumber = $build
        IsWindows11 = ($build -ge 22000)
        IsWindows10 = ($build -gt 0 -and $build -lt 22000)
    }

    return $script:WinUtilOSInfo
}

function Test-WinUtilWindows11 {
    return (Get-WinUtilOSInfo).IsWindows11
}

function Test-WinUtilWindows10 {
    return (Get-WinUtilOSInfo).IsWindows10
}
