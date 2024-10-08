#################################################
# HelloID-Conn-Prov-Target-OzoVerbindzorg-Update
# PowerShell V2
#################################################

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

function ConvertTo-FlatObject {
    param (
        [Parameter(Mandatory)]
        [PSObject]
        $Object,

        [string]
        $Prefix = ""
    )

    $hashTable = [ordered]@{}
    foreach ($property in $Object.PSObject.Properties) {
        $name = if ($Prefix) { "$Prefix`_$($property.Name)" } else { $property.Name }
        if ($null -ne $property.Value) {
            if ($property.Value -is [PSCustomObject]) {
                $flattenedSubObject = ConvertTo-FlatObject -Object $property.Value -Prefix $name
                foreach ($subProperty in $flattenedSubObject.PSObject.Properties) {
                    $hashTable[$subProperty.Name] = [string]$subProperty.Value
                }
            } elseif ($property.Value -is [array]) {
                for ($i = 0; $i -lt $property.Value.Count; $i++) {
                    if ($null -ne $property.Value[$i]) {
                        $flattenedArrayItem = ConvertTo-FlatObject -Object $property.Value[$i] -Prefix "$name`[$i]"
                        foreach ($subProperty in $flattenedArrayItem.PSObject.Properties) {
                            $hashTable[$subProperty.Name] = $subProperty.Value
                        }
                    }
                }
            } else {
                $hashTable[$name] = [string]$property.Value
            }
        }
    }
    $object = [PSCustomObject]$hashTable
    Write-Output $object
}

function ConvertTo-SCIMPatchOperationObject {
    param (
        [Parameter()]
        [object]
        $Properties
    )

    $patchOperations = @()

    foreach ($property in $Properties) {
        $propertyName = $property.Name
        $propertyValue = $property.Value

        $scimPath = $propertyName -replace '_', '.'

        if ($null -ne $propertyValue) {
            if ($property.Name -eq 'workEmail') {
                $patchOperations += @{
                    op    = 'Replace'
                    path  = "emails[type eq 'work'].value"
                    value = $propertyValue
                }
            } else {
                $patchOperations += @{
                    op    = 'Replace'
                    path  = $scimPath
                    value = $propertyValue
                }
            }
        }
    }

    $scimPatch = [ordered]@{
        schemas    = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
        Operations = $patchOperations
    }

    $scimPatch | ConvertTo-Json -Depth 10
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

    # Filter actionContext.Data and remove null values
    foreach ($property in $actionContext.Data.PSObject.Properties.Name) {
        if ([string]::IsNullOrEmpty($actionContext.Data.$property)) {
            $actionContext.Data.PSObject.Properties.Remove($property)
        }
    }

    Write-Information "Verifying if a OzoVerbindzorg account for [$($personContext.Person.DisplayName)] exists"
    $splatGetParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/scim/v2/Users/$($actionContext.References.Account)"
        Method  = 'GET'
        Headers = $headers
    }
    $correlatedAccount = Invoke-RestMethod @splatGetParams

    # Modify object before assigning it to previousData
    $correlatedAccount.PSObject.Properties.Remove('schemas')
    $correlatedAccount.PSObject.Properties.Remove('groups')
    $correlatedAccount.PSObject.Properties.Remove('meta')
    $correlatedAccount.PSObject.Properties.Remove('active')
    $correlatedAccount.PSObject.Properties.Remove('title')
    $email = $correlatedAccount.emails[0].value
    $correlatedAccount.PSObject.Properties.Remove('emails')

    $flattenedCorrelatedAccount = ConvertTo-FlatObject -Object $correlatedAccount
    $flattenedCorrelatedAccount | Add-Member -MemberType NoteProperty -Name 'workEmail' -Value $email
    $outputContext.PreviousData = $flattenedCorrelatedAccount

    # Always compare the account against the current account in target system
    if ($null -ne $correlatedAccount) {
        $splatCompareProperties = @{
            ReferenceObject  = @($flattenedCorrelatedAccount.PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $action = 'UpdateAccount'
            $dryRunMessage = "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
        } else {
            $action = 'NoChanges'
            $dryRunMessage = 'No changes will be made to the account during enforcement'
        }
    } else {
        $action = 'NotFound'
        $dryRunMessage = "OzoVerbindzorg account for: [$($personContext.Person.DisplayName)] not found. Possibly deleted."
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'UpdateAccount' {
                Write-Information "Updating OzoVerbindzorg account with accountReference: [$($actionContext.References.Account)]"
                $scimPatchJson = ConvertTo-SCIMPatchOperationObject -Properties $propertiesChanged
                $splatUpdateParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/scim/v2/Users/$($actionContext.References.Account)"
                    Method      = 'PATCH'
                    Headers     = $headers
                    ContentType = 'application/json'
                    Body        = $scimPatchJson
                }
                $null = Invoke-RestMethod @splatUpdateParams
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
                break
            }

            'NoChanges' {
                Write-Information "No changes to OzoVerbindzorg account with accountReference: [$($actionContext.References.Account)]"
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
                    IsError = $false
                })
                break
            }

            'NotFound' {
                $outputContext.Success = $false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "OzoVerbindzorg account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                    IsError = $true
                })
                break
            }
        }
    }
} catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-OzoVerbindzorgError -ErrorObject $ex
        $auditMessage = "Could not update OzoVerbindzorg account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update OzoVerbindzorg account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
