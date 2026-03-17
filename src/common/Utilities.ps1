#Requires -Version 7.0
# Copyright (c) 2026 POMINI Long Rolling Mills. Licensed under the MIT License.
<#
.SYNOPSIS
    Shared utility helpers for dev-bootstrap.
#>

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes an operation with exponential backoff retry.
    #>
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
    <#
    .SYNOPSIS
        Imports non-empty key=value pairs from a .env file into Process scope.
    #>
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

        # Do not overwrite active process values with empty .env values.
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        $currentProcessValue = [System.Environment]::GetEnvironmentVariable($key, 'Process')
        if ($currentProcessValue -ne $value) {
            [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
            if ([string]::IsNullOrWhiteSpace($currentProcessValue)) {
                Write-Log -Level Debug -Message "Loaded environment variable from .env: $key"
            }
            else {
                Write-Log -Level Debug -Message "Overrode process environment variable from .env: $key"
            }
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
    <#
    .SYNOPSIS
        Reads an environment variable from Process, User, then Machine scope.
    #>
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
        [Parameter(Mandatory)][string]$DestinationPath,
        [string]$GitHubToken,
        [string]$GitHubUsername = 'git',
        [string]$DevOpsPat
    )

    $safeUrl = $CloneUrl -replace 'https://[^\s:@/]+:[^\s@/]+@', 'https://***:***@'
    $gitAuthConfigArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($GitHubToken) -and $CloneUrl -match '^https://github\.com/') {
        $credentials = "${GitHubUsername}:$GitHubToken"
        $basicAuth = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($credentials))
        $gitAuthConfigArgs = @('-c', "http.https://github.com/.extraheader=AUTHORIZATION: basic $basicAuth")
    }
    elseif (-not [string]::IsNullOrWhiteSpace($DevOpsPat) -and $CloneUrl -match '^https://dev\.azure\.com/') {
        $basicAuth = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$DevOpsPat"))
        $gitAuthConfigArgs = @('-c', "http.https://dev.azure.com/.extraheader=AUTHORIZATION: Basic $basicAuth")
    }

    $previousTerminalPrompt = [System.Environment]::GetEnvironmentVariable('GIT_TERMINAL_PROMPT', 'Process')
    $previousGcmInteractive = [System.Environment]::GetEnvironmentVariable('GCM_INTERACTIVE', 'Process')
    $previousGcmDisabled = [System.Environment]::GetEnvironmentVariable('GCM_DISABLED', 'Process')
    $previousGitAskPass = [System.Environment]::GetEnvironmentVariable('GIT_ASKPASS', 'Process')
    $previousSshAskPass = [System.Environment]::GetEnvironmentVariable('SSH_ASKPASS', 'Process')
    $previousGitConfigNoSystem = [System.Environment]::GetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', 'Process')
    [System.Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', '0', 'Process')
    [System.Environment]::SetEnvironmentVariable('GCM_INTERACTIVE', 'Never', 'Process')
    [System.Environment]::SetEnvironmentVariable('GCM_DISABLED', '1', 'Process')
    [System.Environment]::SetEnvironmentVariable('GIT_ASKPASS', '', 'Process')
    [System.Environment]::SetEnvironmentVariable('SSH_ASKPASS', '', 'Process')
    [System.Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', '1', 'Process')

    try {
        $hasDestination = Test-Path -LiteralPath $DestinationPath
        $isGitRepo = $false
        if ($hasDestination) {
            $isGitRepo = Test-GitRepository -Path $DestinationPath
        }

        if ($hasDestination -and -not $isGitRepo) {
            $children = @(Get-ChildItem -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue)
            if ($children.Count -gt 0) {
                $backupPath = "${DestinationPath}.invalid.$((Get-Date).ToString('yyyyMMdd_HHmmss'))"
                Write-Log -Level Warning -Message "Invalid local repository detected at '$DestinationPath'. Moving existing content to '$backupPath' and recloning."
                Move-Item -LiteralPath $DestinationPath -Destination $backupPath -Force
            }
        }

        if (Test-GitRepository -Path $DestinationPath) {
            Write-Log -Level Debug -Message "Running git pull in: $DestinationPath"
            $startLocation = Get-Location
            try {
                Set-Location -LiteralPath $DestinationPath
                $pullArgs = @(
                    '-c', 'credential.interactive=never'
                    '-c', 'credential.helper='
                    '-c', 'core.askPass='
                )
                if ($gitAuthConfigArgs.Count -gt 0) {
                    $pullArgs += $gitAuthConfigArgs
                }
                $pullArgs += @('pull', '--ff-only')
                $pullOutput = & git @pullArgs 2>&1
                $pullText = $pullOutput -join "`n"
                $summary = Get-GitOutputSummary -Output $pullOutput

                if ($LASTEXITCODE -ne 0) {
                    if ($pullText -match "configuration specifies to merge with the ref 'refs/heads/[^']+'" -or $pullText -match "couldn't find remote ref HEAD") {
                        return @{ Status = 'NONE'; Message = 'Remote repository has no default branch yet (likely empty). Pull skipped.' }
                    }

                    Write-Log -Level Error -Message "git pull failed in ${DestinationPath}: $pullText"
                    return @{ Status = 'ERROR'; Message = "git pull failed. $summary" }
                }

                if ($pullText -match 'Already up to date') {
                    return @{ Status = 'NONE'; Message = 'Already up to date.' }
                }

                return @{ Status = 'UPDATED'; Message = "Updated from remote. $summary" }
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

        $cloneArgs = @(
            '-c', 'credential.interactive=never'
            '-c', 'credential.helper='
            '-c', 'core.askPass='
        )
        if ($gitAuthConfigArgs.Count -gt 0) {
            $cloneArgs += $gitAuthConfigArgs
        }
        $cloneArgs += @('clone', $CloneUrl, $DestinationPath)
        $cloneOutput = & git @cloneArgs 2>&1
        $cloneText = $cloneOutput -join "`n"
        $summary = Get-GitOutputSummary -Output $cloneOutput
        if ($LASTEXITCODE -eq 0) {
            return @{ Status = 'ADDED'; Message = "Repository cloned. $summary" }
        }

        if ($cloneText -match 'already exists and is not an empty directory') {
            return @{ Status = 'ERROR'; Message = 'Destination folder is not empty and is not a valid git repository. Clean it or run again after backup.' }
        }

        Write-Log -Level Error -Message "git clone failed for ${safeUrl}: $($cloneOutput -join "`n")"
        return @{ Status = 'ERROR'; Message = "git clone failed. $summary" }
    }
    finally {
        [System.Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT', $previousTerminalPrompt, 'Process')
        [System.Environment]::SetEnvironmentVariable('GCM_INTERACTIVE', $previousGcmInteractive, 'Process')
        [System.Environment]::SetEnvironmentVariable('GCM_DISABLED', $previousGcmDisabled, 'Process')
        [System.Environment]::SetEnvironmentVariable('GIT_ASKPASS', $previousGitAskPass, 'Process')
        [System.Environment]::SetEnvironmentVariable('SSH_ASKPASS', $previousSshAskPass, 'Process')
        [System.Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', $previousGitConfigNoSystem, 'Process')
    }
}

function Test-GitRepository {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $output = & git -C $Path rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return ([string]$output).Trim().ToLowerInvariant() -eq 'true'
}

function Get-GitOutputSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Output)

    foreach ($line in @($Output)) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $trimmed = $text.Trim()
        if ($trimmed -match '^(remote:|warning:|hint:|From\s+|Cloning into\s+|Already up to date\.)') {
            return $trimmed
        }

        return $trimmed
    }

    return 'No git output available.'
}

function Set-WindowsFolderIcon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [string]$IconFile = 'shell32.dll',
        [int]$IconIndex = 0,
        [string]$ProjectRoot
    )

    if (-not (Test-IsWindows)) {
        Write-Log -Level Warning -Message "Folder icon configuration skipped on $(Get-OSPlatform). Windows only feature."
        return
    }

    try {
        $iconResource = $IconFile
        $isIcoFile = $IconFile.ToLowerInvariant().EndsWith('.ico')
        if ($isIcoFile) {
            $sourceIconPath = Find-WindowsIconPath -IconFile $IconFile -ProjectRoot $ProjectRoot

            if (-not $sourceIconPath) {
                throw "Icon file '$IconFile' not found in repository icon folders."
            }

            $destinationIconPath = Join-Path $FolderPath ([System.IO.Path]::GetFileName($IconFile))
            Copy-Item -LiteralPath $sourceIconPath -Destination $destinationIconPath -Force
            $iconResource = [System.IO.Path]::GetFileName($IconFile)

            $icon = Get-Item -LiteralPath $destinationIconPath -Force
            $icon.Attributes = $icon.Attributes -bor [System.IO.FileAttributes]::Hidden
        }

        $iniPath = Join-Path $FolderPath 'desktop.ini'
        $iniContent = @"
[.ShellClassInfo]
IconResource=$iconResource,$IconIndex
"@

        Set-Content -LiteralPath $iniPath -Value $iniContent -Encoding unicode -Force
        $folder = Get-Item -LiteralPath $FolderPath -Force
        $folder.Attributes = $folder.Attributes -bor [System.IO.FileAttributes]::System
        $ini = Get-Item -LiteralPath $iniPath -Force
        $ini.Attributes = $ini.Attributes -bor [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
    }
    catch {
        Write-Log -Level Warning -Message "Unable to set folder icon for ${FolderPath}: $_"
    }
}

function Find-WindowsIconPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$IconFile,
        [string]$ProjectRoot
    )

    $iconCandidatePaths = [System.Collections.Generic.List[string]]::new()

    if ([System.IO.Path]::IsPathRooted($IconFile)) {
        $iconCandidatePaths.Add($IconFile)
    }
    else {
        if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
            $iconCandidatePaths.Add((Join-Path $ProjectRoot 'config' 'icons' $IconFile))
            $iconCandidatePaths.Add((Join-Path $ProjectRoot 'icons' $IconFile))
        }

        $localRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $iconCandidatePaths.Add((Join-Path $localRoot 'config' 'icons' $IconFile))
        $iconCandidatePaths.Add((Join-Path $localRoot 'icons' $IconFile))
    }

    foreach ($candidate in $iconCandidatePaths) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}
