# ACR Authentication (dev-bootstrap)

This document contains only the ACR authentication requirements used by this project.

## Required Variable

Set only this variable in `.env`:

```dotenv
AZURE_TENANT_ID=<tenant-id>
```

How to get it:

- Ask your IT Admin for the Azure tenant id to use with this project.

## Prerequisite

- The target ACR must be open/reachable before running the script.
- If your organization uses an open/close process (for example a temporary network rule or pipeline), ensure the ACR is opened first.

## Runtime Behavior

- No client id/secret is required by this project.
- The application uses interactive Azure login for ACR operations.
- If your session is missing or expired, the application will request login when needed.

## Run ACR Module

```powershell
pwsh ./dev-bootstrap.ps1 -RunMode acr
```

## Troubleshooting

- Login prompt appears: expected when a valid Azure session is not available.
- Wrong tenant: verify `AZURE_TENANT_ID` with IT Admin.
- ACR access denied: ask IT Admin to verify your RBAC permissions (for example `AcrPull`).
- Registry not reachable: verify the ACR is open and reachable on network before rerunning.
