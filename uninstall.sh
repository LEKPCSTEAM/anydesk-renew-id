#!/usr/bin/env bash
# ถอน Renew AnyDesk ID (ถ้าติดตั้งด้วย sudo ต้องถอนด้วย sudo)
set -euo pipefail
exec bash "$(dirname "$(readlink -f "$0")")/renew-anydesk-id.sh" --uninstall
