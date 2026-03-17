# ACR Authentication (No App Registration Required)

This guide describes the supported ACR authentication flow for `dev-bootstrap` without app registrations or client secrets.

## How It Works

The `acr` module uses interactive user authentication.

For interactive mode, the flow is:

1. Check current Azure CLI session (`az account show`).
2. If already logged in on the target tenant, reuse the session.
3. Otherwise run `az login --tenant <tenantId> --allow-no-subscriptions`.
4. Run `az acr login --name <registry>` and then pull images.

This matches the legacy behavior while avoiding repeated login prompts when an Azure CLI session is already active.

## Minimal Setup

Set only tenant and registry/image configuration. No client secret is required.

```dotenv
AZURE_TENANT_ID=<tenant-id>
```

## Run

```powershell
pwsh ./dev-bootstrap.ps1 -RunMode acr
```

If no valid Azure CLI session exists for the configured tenant, a login popup/device flow is expected.

## Optional: Keep Login Prompt on Every Run

If you want to force a fresh login every execution, clear the Azure CLI account cache before running:

```powershell
az account clear
pwsh ./dev-bootstrap.ps1 -RunMode acr
```

## Required Permissions

The signed-in user must have permission on the target ACR (for example `AcrPull`).

## Troubleshooting

- Wrong tenant selected: set `AZURE_TENANT_ID` to the required tenant.
- ACR access denied: verify RBAC on the registry for your user.
- Docker errors: ensure Docker Desktop/daemon is running.
