#################################################
# HelloID-Conn-Prov-Target-OzoVerbindzorg-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-OzoError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )

    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }

        if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException')) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails
            $errorDetailsObject = ($ErrorObject.ErrorDetails | ConvertFrom-Json)
            $httpErrorObj.FriendlyMessage = $errorDetailsObject.detail
        }

        elseif ($($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                    $errorDetailsObject = ($streamReaderResponse | ConvertFrom-Json)
                    $httpErrorObj.FriendlyMessage = $errorDetailsObject.detail
                }
            }
        }

        Write-Output $httpErrorObj
    }
}

function Convert-ToSCIMObject {
    param (
        [Parameter()]
        [PSCustomObject]
        $Account
    )

    $scimObject = @{
        schemas = @(
            "urn:ietf:params:scim:schemas:core:2.0:User",
            "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User"
        )
    }

    if ($Account.displayName) {
        $scimObject.displayName = $Account.displayName
    }
    if ($Account.userName) {
        $scimObject.userName = $Account.userName
    }
    if ($Account.userType) {
        $scimObject.userType = $Account.userType
    }
    if ($Account.nickName) {
        $scimObject.nickName = $Account.nickName
    }

    $nameObject = @{}
    if ($Account.name_familyName) {
        $nameObject.familyName = $Account.name_familyName
    }
    if ($Account.name_givenName) {
        $nameObject.givenName = $Account.name_givenName
    }
    if ($Account.name_middleName) {
        $nameObject.middleName = $Account.name_middleName
    }
    if ($Account.name_formatted) {
        $nameObject.formatted = $Account.name_formatted
    }
    if ($nameObject.Count -gt 0) {
        $scimObject.name = $nameObject
    }

    if ($Account.workEmail) {
        $scimObject.emails = @(
            @{
                primary = $true
                type    = 'work'
                value   = $Account.workEmail
            }
        )
    }

    Write-Output $scimObject
}

function Set-OzoVerbindzorgTitle {
    [CmdletBinding()]
    param (
        [Parameter()]
        $Id,

        [Parameter()]
        [string]
        $Title,

        [Parameter()]
        [string]
        $Secret

    )

    try {
        Write-Information "Updating title to: [$Title]"

        $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
        $headers.Add("Authorization", "Bearer $Secret")
        $splatUpdateTitleParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/scim/v2/Users/$Id)"
            Method      = 'PATCH'
            ContentType = 'application/json'
            Body        =  @{
                schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                Operations = @(@{
                    op = 'Replace'
                    path = 'Title'
                    value = $actionContext.Data.title
                })
            } | ConvertTo-Json
            Headers = $headers
        }
        $null = Invoke-RestMethod @splatUpdateTitleParams
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Setting authentication header
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add("Authorization", "Bearer $($actionContext.Configuration.Secret)")

    if ($actionContext.CorrelationConfiguration.Enabled) {
            $correlationField = $actionContext.CorrelationConfiguration.accountField
            $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

            if ([string]::IsNullOrEmpty($correlationField)) {
                Write-Warning "Correlation is enabled but not configured correctly."
                Throw "Correlation is enabled but not configured correctly."
            }

            if ([string]::IsNullOrEmpty($correlationValue)) {
                Write-Warning "The correlation value for [$correlationField] is empty. This is likely a scripting issue."
                Throw "The correlation value for [$correlationField] is empty. This is likely a scripting issue."
            }

        $splatTestParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/scim/v2/Users"
            Method      = 'GET'
            ContentType = 'application/json'
            Headers     = $headers
        }

        $users = Invoke-RestMethod @splatTestParams

        $currentUser = $users.Resources | Where-Object $actionContext.CorrelationConfiguration.AccountField -eq "$($actionContext.CorrelationConfiguration.AccountFieldValue)"

        $currentUser = $currentUser[0]

    }

    if (-Not([string]::IsNullOrEmpty($currentUser))) {
        $action = 'Correlate'
    }    
    else {
        $action = 'Create' 
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $action Ozo account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
    }        

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch($action)
        {
            'Create' {
                Write-Information 'Creating and correlating Ozo account'
                $accountToCreate = Convert-ToSCIMObject -Account $actionContext.Data
                $splatCreateParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/scim/v2/Users"
                    Method      = 'POST'
                    ContentType = 'application/json'
                    Body        = $accountToCreate | ConvertTo-Json
                    Headers     = $headers
                }

                $createdAccount = Invoke-RestMethod @splatCreateParams

                Write-Warning "$($createdAccount.id)"

                $null = Set-OzoVerbindzorgTitle -Id $createdAccount.id -Title $actionContext.Data.title -Secret $actionContext.Configuration.Secret
                $outputContext.Data = $createdAccount
                $outputContext.AccountReference = $createdAccount.id
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = $action
                    Message = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)"
                    IsError = $false
                })
                break

                $outputContext.success = $true
            }
            'Correlate' {
                #region correlate
                Write-Information "Account with id [$($currentUser.id)] and userName [($($currentUser.userName))] successfully correlated on field [$($correlationField)] with value [$($correlationValue)]"

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CorrelateAccount"
                        Message = "Account with id [$($currentUser.id)] and userName [($($currentUser.userName))] successfully correlated on field [$($correlationField)] with value [$($correlationValue)]"
                        IsError = $false
                    })

                $outputContext.AccountReference = $currentUser.id
                $outputContext.AccountCorrelated = $true
                $outputContext.Data = $currentUser
                $outputContext.success = $true
                
                break
                #endregion correlate
            }

        }
        
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-OzoError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Ozo account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not create or correlate Ozo account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}