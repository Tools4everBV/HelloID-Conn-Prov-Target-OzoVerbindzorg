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
#endregion

try {
    # Setting authentication header
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add("Authorization", "Bearer $($actionContext.Configuration.Secret)")

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $action Ozo account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
    }

        $splatTestParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/scim/v2/Groups"
            Method      = 'GET'
            ContentType = 'application/json'
            Headers     = $headers
        }

        $result = Invoke-RestMethod @splatTestParams

        foreach ($r in $result.Resources)
        {
            $outputContext.Permissions.Add(
                @{
                    DisplayName    = "$($r.displayName)"
                    Identification = @{
                        Reference   = $r.id
                        DisplayName = "$($r.displayName)"
                    }
                }
            )
        }
}
catch {
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
}