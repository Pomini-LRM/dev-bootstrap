# GitHub Classic Token Setup

This guide explains how to create a GitHub Personal Access Token (classic) for dev-bootstrap.

## Create Token

1. Open GitHub Settings.
2. Go to Developer settings > Personal access tokens > Tokens (classic).
3. Click Generate new token (classic).
4. Set an expiration date.
5. Select scopes required by your repositories.

Recommended minimum scopes:
- repo (private repositories)
- read:org (organization membership)

## Store Token

Set the token in your environment or in .env:

```dotenv
GITHUB_TOKEN=ghp_xxx
```

## Validate

Run:

```powershell
pwsh ./dev-bootstrap.ps1 -RunMode github -NoConfirm -Debug
```

If permissions are missing, the run report will contain repository-level errors.
