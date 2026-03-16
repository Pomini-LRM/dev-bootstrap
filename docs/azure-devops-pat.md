# Azure DevOps PAT Setup

This guide explains how to create an Azure DevOps Personal Access Token (PAT) for dev-bootstrap.

## Create PAT

1. Sign in to Azure DevOps.
2. Open User settings > Personal access tokens.
3. Click New Token.
4. Set Organization, Name, and Expiration.
5. Set scope to Custom defined and enable:
   - Code: Read
   - Project and Team: Read (recommended for project discovery)

## Store Token

Set the token in your environment or in .env:

```dotenv
AZURE_DEVOPS_PAT=xxxxxxxxxxxxxxxx
AZURE_DEVOPS_ORGS=my-org
```

Multiple organizations are supported as a comma-separated list:

```dotenv
AZURE_DEVOPS_ORGS=org-one,org-two
```

## Validate

Run:

```powershell
pwsh ./dev-bootstrap.ps1 -RunMode devops -NoConfirm -Debug
```

If permissions are missing, the run report will contain repository-level errors.
