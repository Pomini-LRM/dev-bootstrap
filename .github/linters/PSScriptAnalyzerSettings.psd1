# PSScriptAnalyzer settings for dev-bootstrap CI pipeline.
# Canonical location: .github/linters/PSScriptAnalyzerSettings.psd1
# Docs: https://github.com/PowerShell/PSScriptAnalyzer/blob/master/docs/Cmdlets/Invoke-ScriptAnalyzer.md
@{
    # Report Error and Warning severity. Information is omitted to reduce CI noise.
    Severity     = @('Error', 'Warning')
    IncludeRules = @('*')
    ExcludeRules = @(
        # Functions like Set-*, Remove-* trigger this even without system-state changes.
        # This project orchestrates CLI tools (az, docker, git) via process invocation;
        # ShouldProcess adds complexity without safety benefit in this context.
        'PSUseShouldProcessForStateChangingFunctions'

        # Write-Host is used intentionally in user-facing CLI output for colored text
        # that must not be captured by the pipeline.
        'PSAvoidUsingWriteHost'
    )

    Rules = @{
        # ── Compatibility ───────────────────────────────────────────────────
        PSUseCompatibleSyntax            = @{
            Enable         = $true
            TargetVersions = @('7.0')
        }

        # ── Best-practice rules ─────────────────────────────────────────────
        PSAvoidUsingCmdletAliases        = @{ Enable = $true }
        PSAvoidUsingPositionalParameters = @{ Enable = $true }
        PSUseApprovedVerbs               = @{ Enable = $true }

        # ── Brace placement (K&R / OTBS style) ─────────────────────────────
        PSPlaceOpenBrace                 = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace                = @{
            Enable             = $true
            # true = require newline after } (matches the codebase's standard PS style).
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }

        # ── Indentation ────────────────────────────────────────────────────
        PSUseConsistentIndentation       = @{
            Enable              = $true
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }

        # ── Whitespace ─────────────────────────────────────────────────────
        PSUseConsistentWhitespace        = @{
            Enable                          = $true
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $true
            CheckPipe                       = $true
            # Redundant-whitespace check triggers noise on alignment-heavy hashtables.
            CheckPipeForRedundantWhitespace = $false
            CheckSeparator                  = $true
            # CheckParameter generates false positives on splatting patterns used throughout.
            CheckParameter                  = $false
        }

        # ── Assignment alignment ───────────────────────────────────────────
        PSAlignAssignmentStatement       = @{
            Enable         = $true
            # Hashtable alignment is handled by project convention, not the linter.
            CheckHashtable = $false
        }
    }
}
