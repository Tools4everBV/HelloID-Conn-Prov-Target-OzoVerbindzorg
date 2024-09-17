#########################################################
# HelloID-Conn-Prov-Target-OzoVerbindzorg-SubPermissions
# PowerShell V2
#########################################################

# Contract permission mapping
$objectKey = 'CostCenter'
$externalIdKey = 'ExternalId'
$nameKey = 'Name'

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
    # Setting authentication header
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add("Authorization", "Bearer $($actionContext.Configuration.Secret)")

    # Collect all permissions from OzoVerbindzorg
    $availablePermissions = [System.Collections.Generic.List[object]]::new()
    $startIndex = 1
    $count = 100
    $totalResults = 0
    do {
        $requestUrl = "$($actionContext.Configuration.BaseUrl)/scim/v2/Groups?startIndex=$startIndex&count=$count"
        $response = Invoke-RestMethod -Uri $requestUrl -Method 'GET' -Headers $headers
        if ($totalResults -eq 0) {
            $totalResults = $response.totalResults
        }

        foreach ($resource in $response.Resources) {
            $availablePermissions.Add($resource)
        }
        $startIndex += $count
    } while ($startIndex -le $totalResults)

    # Collect current permissions
    $currentPermissions = @{}
    foreach ($permission in $actionContext.CurrentPermissions) {
        $currentPermissions[$permission.Reference.Id] = $permission.DisplayName
    }

    # Collect desired permissions
    $desiredPermissions = @{}
    if (-Not($actionContext.Operation -eq "revoke")) {
        foreach ($contract in $personContext.Person.Contracts) {
            if ($contract.Context.InConditions) {
                $desiredPermissions[$contract.$objectKey.$externalIdKey] = $contract.$objectKey.$nameKey
            }
        }
    }

    # Collect newCurrent permissions
    $newCurrentPermissions = @{}

    # Process current permissions to revoke
    foreach ($permission in $currentPermissions.GetEnumerator()) {
        if (-Not $desiredPermissions.ContainsValue($permission.Value)) {
            if (-Not($actionContext.DryRun -eq $true)) {
                $patchBody = @{
                    schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                    Operations = @(
                        @{
                            op    = 'Remove'
                            path  = 'members'
                            value = @(
                                @{
                                    value = $actionContext.References.Account
                                }
                            )
                        }
                    )
                } | ConvertTo-Json -Depth 10

                $splatPatchParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/scim/v2/Groups/$($permission.Key)"
                    Method      = 'PATCH'
                    Headers     = $headers
                    Body        = $patchBody
                    ContentType = 'application/json'
                }
                $null = Invoke-RestMethod @splatPatchParams
            }

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "RevokePermission"
                Message = "Revoked access to team: [$($permission.Value)]"
                IsError = $false
            })
        } else {
            $newCurrentPermissions[$permission.Name] = $permission.Value
        }
    }

    # Process desired permissions to grant
    foreach ($permission in $desiredPermissions.GetEnumerator()) {
        $permissionToGrant = $availablePermissions | Where-Object {$_.displayName -eq $permission.Value}
        $outputContext.SubPermissions.Add([PSCustomObject]@{
            DisplayName = $permission.Value
            Reference   = [PSCustomObject]@{
                Id = $permissionToGrant.id
            }
        })

        if (-Not $currentPermissions.ContainsValue($permission.Value)) {
            if (-not($actionContext.DryRun -eq $true)) {
                $patchBody = @{
                    schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                    Operations = @(
                        @{
                            op    = 'Add'
                            path  = 'members'
                            value = @(
                                @{
                                    value = $actionContext.References.Account
                                }
                            )
                        }
                    )
                } | ConvertTo-Json -Depth 10

                $splatPatchParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/scim/v2/Groups/$($permissionToGrant.id)"
                    Method      = 'PATCH'
                    Headers     = $headers
                    Body        = $patchBody
                    ContentType = 'application/json'
                }
                $null = Invoke-RestMethod @splatPatchParams
            }

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "GrantPermission"
                Message = "Granted access to team: [$($permission.Value)]"
                IsError = $false
            })
        }
    }

    # Process permissions to update
    if ($actionContext.Operation -eq "update") {
        foreach ($permission in $newCurrentPermissions.GetEnumerator()) {
            if (-Not($actionContext.DryRun -eq $true)) {
                $patchBody = @{
                    schemas = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
                    Operations = @(
                        @{
                            op    = 'Add'
                            path  = 'members'
                            value = @(
                                @{
                                    value = $actionContext.References.Account
                                }
                            )
                        }
                    )
                } | ConvertTo-Json -Depth 10

                $splatPatchParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/scim/v2/Groups/$($permission.Key)"
                    Method      = 'PATCH'
                    Headers     = $headers
                    Body        = $patchBody
                    ContentType = 'application/json'
                }
                $null = Invoke-RestMethod @splatPatchParams
            }

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "UpdatePermission"
                Message = "Updated access to team: [$($permission.Value)]"
                IsError = $false
            })
        }
    }

    $outputContext.Success = $true
} catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-OzoVerbindzorgError -ErrorObject $ex
        $auditMessage = "Could not manage OzoVerbindzorg permissions. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not manage OzoVerbindzorg permissions. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
        Message = $auditMessage
        IsError = $true
    })
}
