@{
    Severity     = @('Error', 'Warning')
    IncludeRules = @('*')
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions'
        'PSAvoidUsingWriteHost'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.0')
        }
        PSAvoidUsingCmdletAliases = @{ Enable = $true }
        PSAvoidUsingPositionalParameters = @{ Enable = $true }
        PSUseApprovedVerbs = @{ Enable = $true }
        PSUseConsistentIndentation = @{
            Enable              = $true
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }
        PSUseConsistentWhitespace = @{
            Enable                          = $true
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $true
            CheckPipe                       = $true
            CheckPipeForRedundantWhitespace = $false
            CheckSeparator                  = $true
            CheckParameter                  = $false
        }
    }
}
