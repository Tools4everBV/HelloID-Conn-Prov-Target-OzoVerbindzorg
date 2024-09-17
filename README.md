
# HelloID-Conn-Prov-Target-OzoVerbindzorg

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://www.ozoverbindzorg.nl/wp-content/themes/template_child/assets/images/logo-ozoverbindzorg.svg">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-OzoVerbindzorg](#helloid-conn-prov-target-ozoverbindzorg)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
    - [_OzoVerbindzorg_ account are linked to the customers SCIM service](#ozoverbindzorg-account-are-linked-to-the-customers-scim-service)
    - [The `title` field can __only__ be updated](#the-title-field-can-only-be-updated)
    - [SubPermissions](#subpermissions)
    - [Additional mapping in the _update_ lifecycle action](#additional-mapping-in-the-update-lifecycle-action)
  - [Setup the connector](#setup-the-connector)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-OzoVerbindzorg_ is a _target_ connector. _OzoVerbindzorg_ provides a set of REST API's that allow you to programmatically interact with its data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint | Description             |
| -------- | ----------------------- |
| /Users   | User related API calls  |
| /Groups  | Group related API calls |

The following lifecycle actions are available:

| Action                                | Description                                  |
| ------------------------------------- | -------------------------------------------- |
| create.ps1                            | PowerShell _create_ lifecycle action         |
| delete.ps1                            | PowerShell _delete_ lifecycle action         |
| disable.ps1                           | PowerShell _disable_ lifecycle action        |
| enable.ps1                            | PowerShell _enable_ lifecycle action         |
| update.ps1                            | PowerShell _update_ lifecycle action         |
| permissions/groups/subPermissions.ps1 | PowerShell _subPermissions_ lifecycle action |
| configuration.json                    | Default _configuration.json_                 |
| fieldMapping.json                     | Default _fieldMapping.json_                  |

## Getting started

### Provisioning PowerShell V2 connector

#### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Connection settings

The following settings are required to connect to the API.

| Setting | Description                      | Mandatory |
| ------- | -------------------------------- | --------- |
| BaseUrl | The URL to the API               | Yes       |
| Secret  | The secret to connect to the API | Yes       |

### Prerequisites

### Remarks

### _OzoVerbindzorg_ accounts are linked to the customers SCIM service

User accounts within Ozo are integrated with customers' SCIM services, with all accounts managed through a single endpoint. Internally, these accounts are linked to a specific customer's SCIM service, ensuring that you can only access and retrieve the accounts you are authorized to upon authentication. However, users that already exist within Ozo are not connected to your SCIM service, making it impossible to retrieve existing users. As a result, it is not possible to verify if a specific user account already exists, and therefore, account correlation is unavailable.

Upon creation, if a user account is found with a matching `userName`, the user account will be linked to the customers SCIM service and returned by the API allowing you use the `id` as the `accountReference`.

> [!WARNING]
> If you execute the create action a second time (after the initial linking), a __409-Conflict__ error will be returned.

### The `title` field can __only__ be updated

The `title` field can only be updated. Therefore, within the _update_ lifecycle action, we have a separate process in place that checks if `$actionContext.Correlated` is set to `$true`. If so, the `title` field will be updated using a _PATCH_ call. We chose not to implement this within the _create_ lifecycle action to maintain clarity in each process.

However, its worth noting that the `title` field isn't being returned using a _GET_ call. Therefore, within the comparison between the `$correlatedAccount` and `$actionContext.Data` this property is removed.

### SubPermissions

This connector uses _subPermissions_ in order to grant/revoke a team. For our initial version we made the assumption that the _CostCenter_ matches with the name of team in _OzoVerbindzorg_. This can be configured within the _subPermissions.ps1_ file on line _6_.

```powershell
# Contract permission mapping
$objectKey = 'CostCenter'
$externalIdKey = 'ExternalId'
$nameKey = 'Name'
```

### Additional mapping in the _update_ lifecycle action

For certain user properties specified in the fieldmapping, additional mapping is necessary in both the _create_ and _update_ lifecycle actions to generate the final SCIM JSON payload. That also means that the __field mapping cannot be modified without making changes to the code__.

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
