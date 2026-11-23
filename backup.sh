#!/usr/bin/env bash
# 备份 / 恢复 hub 的账号凭据与用量流水
#
#   备份：./backup.sh                     -> ./trae-hub-YYYYmmdd-HHMM.tar.gz
#   恢复：./backup.sh restore <包.tar.gz>
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/trae-hub}"
MODE="${1:-backup}"

if [ "$MODE" = "restore" ]; then
  ARCHIVE="${2:?用法: ./backup.sh restore <包.tar.gz>}"
  mkdir -p "$APP_DIR"
  tar -xzf "$ARCHIVE" -C "$APP_DIR"
  echo "已恢复到 $APP_DIR，重启容器生效：docker restart trae2api-hub"
  exit 0
fi

OUT="./trae-hub-$(date +%Y%m%d-%H%M).tar.gz"
tar -czf "$OUT" -C "$APP_DIR" accounts usage
echo "已备份到 $OUT"
echo "注意：包内含账号 access/refresh token，等同账号密码，请勿外泄。"
