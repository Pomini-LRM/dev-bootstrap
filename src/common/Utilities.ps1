#Requires -Version 7.0
<#
.SYNOPSIS
    Shared utility helpers for dev-bootstrap.
#>

function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$BaseDelaySeconds = 5,
        [string]$OperationName = 'operation'
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return (& $ScriptBlock)
        }
        catch {
            if ($attempt -gt $MaxRetries) {
                Write-Log -Level Error -Message "[$OperationName] Failed after $MaxRetries retries: $_"
                throw
            }

            $delay = [int]($BaseDelaySeconds * [Math]::Pow(2, $attempt - 1))
            Write-Log -Level Warning -Message "[$OperationName] Attempt $attempt/$MaxRetries failed. Retrying in ${delay}s."
            Start-Sleep -Seconds $delay
        }
    }
}

function Import-EnvFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log -Level Debug -Message ".env file not found: $Path"
        return
    }

    $lines = Get-Content -LiteralPath $Path -Encoding utf8
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }

        $separator = $trimmed.IndexOf('=')
        if ($separator -le 0) {
            continue
        }

        $key = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()

        if (-not [System.Environment]::GetEnvironmentVariable($key, 'Process')) {
            [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
            Write-Log -Level Debug -Message "Loaded environment variable from .env: $key"
        }
    }
}

function Get-EnvFileVariableState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return 'MissingFile'
    }

    $pattern = "^\s*$([regex]::Escape($Name))\s*=\s*(.*)$"
    $lines = Get-Content -LiteralPath $Path -Encoding utf8

    foreach ($line in $lines) {
        $trimmed = [string]$line
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        $trimmed = $trimmed.Trim()
        if ($trimmed.StartsWith('#')) {
            continue
        }

        if ($trimmed -match $pattern) {
            $value = [string]$Matches[1]
            if ([string]::IsNullOrWhiteSpace($value)) {
                return 'DefinedEmpty'
            }

            return 'DefinedValue'
        }
    }

    return 'NotDefined'
}

function Get-SecureEnvVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$DefaultValue = ''
    )

    $value = [System.Environment]::GetEnvironmentVariable($Name, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [System.Environment]::GetEnvironmentVariable($Name, 'User')
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [System.Environment]::GetEnvironmentVariable($Name, 'Machine')
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $(if ($DefaultValue) { $DefaultValue } else { $null })
    }

    return $value
}

function Resolve-ConfiguredPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $resolvedPath = $Path.Trim()
    if ($resolvedPath.StartsWith('~')) {
        $resolvedPath = Join-Path $HOME $resolvedPath.Substring(1).TrimStart('/', '\\')
    }

    return [System.IO.Path]::GetFullPath($resolvedPath)
}

function Invoke-GitCloneOrPull {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CloneUrl,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    $safeUrl = $CloneUrl -replace 'https://[^\s:@/]+:[^\s@/]+@', 'https://***:***@'

    if (Test-Path (Join-Path $DestinationPath '.git')) {
        Write-Log -Level Debug -Message "Running git pull in: $DestinationPath"
        $startLocation = Get-Location
        try {
            Set-Location -LiteralPath $DestinationPath
            $pullOutput = & git pull --ff-only 2>&1
            $pullText = $pullOutput -join "`n"

            if ($LASTEXITCODE -ne 0) {
                Write-Log -Level Error -Message "git pull failed in ${DestinationPath}: $pullText"
                return 'ERROR'
            }

            if ($pullText -match 'Already up to date') {
                return 'NONE'
            }

            return 'UPDATED'
        }
        finally {
            Set-Location -LiteralPath $startLocation
        }
    }

    Write-Log -Level Debug -Message "Running git clone: $safeUrl -> $DestinationPath"
    $parentDirectory = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $parentDirectory)) {
        New-Item -Path $parentDirectory -ItemType Directory -Force | Out-Null
    }

    $cloneOutput = & git clone $CloneUrl $DestinationPath 2>&1
    if ($LASTEXITCODE -eq 0) {
        return 'ADDED'
    }

    Write-Log -Level Error -Message "git clone failed for ${safeUrl}: $($cloneOutput -join "`n")"
    return 'ERROR'
}

function Set-WindowsFolderIcon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [string]$IconFile = 'shell32.dll',
        [int]$IconIndex = 0
    )

    if (-not (Test-IsWindows)) {
        Write-Log -Level Warning -Message "Folder icon configuration skipped on $(Get-OSPlatform). Windows only feature."
        return
    }

    try {
        $iniPath = Join-Path $FolderPath 'desktop.ini'
        $iniContent = @"
[.ShellClassInfo]
IconResource=$IconFile,$IconIndex
"@

        Set-Content -LiteralPath $iniPath -Value $iniContent -Encoding utf8 -Force
        $folder = Get-Item -LiteralPath $FolderPath -Force
        $folder.Attributes = $folder.Attributes -bor [System.IO.FileAttributes]::System
        $ini = Get-Item -LiteralPath $iniPath -Force
        $ini.Attributes = $ini.Attributes -bor [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
    }
    catch {
        Write-Log -Level Warning -Message "Unable to set folder icon for ${FolderPath}: $_"
    }
}
