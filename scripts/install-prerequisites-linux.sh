#!/usr/bin/env bash
set -euo pipefail

echo "Checking minimum prerequisites for dev-bootstrap..."

if command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell 7 is already installed: $(command -v pwsh)"
  exit 0
fi

echo "PowerShell 7 not found. Installing..."

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y powershell || {
    echo "Unable to install powershell from current apt sources."
    echo "Add Microsoft package repository and retry:"
    echo "https://learn.microsoft.com/powershell/scripting/install/install-debian"
    exit 1
  }
elif command -v dnf >/dev/null 2>&1; then
  sudo dnf install -y powershell || {
    echo "Unable to install powershell from current dnf sources."
    echo "Add Microsoft package repository and retry:"
    echo "https://learn.microsoft.com/powershell/scripting/install/install-rhel"
    exit 1
  }
elif command -v yum >/dev/null 2>&1; then
  sudo yum install -y powershell || {
    echo "Unable to install powershell from current yum sources."
    echo "Add Microsoft package repository and retry:"
    echo "https://learn.microsoft.com/powershell/scripting/install/install-rhel"
    exit 1
  }
elif command -v zypper >/dev/null 2>&1; then
  sudo zypper install -y powershell || {
    echo "Unable to install powershell from current zypper sources."
    echo "Add Microsoft package repository and retry:"
    echo "https://learn.microsoft.com/powershell/scripting/install/install-suse"
    exit 1
  }
else
  echo "No supported package manager found (apt-get, dnf, yum, zypper)."
  exit 1
fi

echo
echo "Prerequisite setup completed."
echo "Next step: run dev-bootstrap with pwsh:"
echo "  pwsh ./dev-bootstrap.ps1 -RunMode full -NoConfirm"
