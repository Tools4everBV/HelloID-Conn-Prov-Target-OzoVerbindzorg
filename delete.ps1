##################################################
# HelloID-Conn-Prov-Target-OzoVerbindzorg-Delete
# PowerShell V2
##################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-OzoVerbindzorgError {
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
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    # Setting authentication header
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add("Authorization", "Bearer $($actionContext.Configuration.Secret)")

    Write-Information "Verifying if a OzoVerbindzorg account for [$($personContext.Person.DisplayName)] exists"
    # Verify if a user must be either [created ] or just [correlated]
    $splatGetParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/scim/v2/Users/$($actionContext.References.Account)"
        Method  = 'GET'
        Headers = $headers
    }
    $correlatedAccount = Invoke-RestMethod @splatGetParams
    $outputContext.PreviousData = $correlatedAccount

    if ($null -ne $correlatedAccount) {
        $action = 'DeleteAccount'
        $dryRunMessage = "Delete OzoVerbindzorg account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] will be executed during enforcement"
    } else {
        $action = 'NotFound'
        $dryRunMessage = "OzoVerbindzorg account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'DeleteAccount' {
                Write-Information "Deleting OzoVerbindzorg account with accountReference: [$($actionContext.References.Account)]"
                $splatParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/scim/v2/Users/$($actionContext.References.Account)"
                    Method      = 'PATCH'
                    ContentType = 'application/json'
                    Body        =  @{
                        schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                        Operations = @(@{
                            op = "replace"
                            path = "active"
                            value = $false
                        })
                    } | ConvertTo-Json
                    Headers     = $headers
                }
                $null = Invoke-RestMethod @splatParams
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Delete account was successful'
                    IsError = $false
                })
                break
            }

            'NotFound' {
                $outputContext.Success  = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "OzoVerbindzorg account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                    IsError = $false
                })
                break
            }
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-OzoVerbindzorgError -ErrorObject $ex
        $auditMessage = "Could not delete OzoVerbindzorg account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not delete OzoVerbindzorg account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
        Message = $auditMessage
        IsError = $true
    })
}
