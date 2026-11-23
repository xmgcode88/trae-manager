#!/usr/bin/env bash
# Trae2api-hub 一键部署（上游源码 + 本地补丁）
#
# 用法：
#   PANEL_PASSWORD='你的面板密码' ./deploy.sh
#   可选环境变量：
#     PORT=8791              对外端口
#     APP_DIR=/opt/trae-hub  源码与数据目录
#     REF=<git commit>       锁定上游版本（默认见下方 REF）
#     REPO_URL=<git url>     上游仓库
#     IMAGE=trae-hub:latest  本地镜像名
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/shuishuipingan/trae2api-hub.git}"
REF="${REF:-e7eef187800e45ac0e9a32bb18d7bd6e7fbaa4f9}"
APP_DIR="${APP_DIR:-/opt/trae-hub}"
CONTAINER="${CONTAINER:-trae2api-hub}"
PORT="${PORT:-8791}"
IMAGE="${IMAGE:-trae-hub:latest}"
PANEL_PASSWORD="${PANEL_PASSWORD:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$PANEL_PASSWORD" ]; then
  echo "错误：必须设置 PANEL_PASSWORD（面板密码）" >&2
  exit 1
fi

echo "==> 1/5 源码（REF=${REF:0:12}）"
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" fetch --tags --force origin >/dev/null 2>&1 || true
  git -C "$APP_DIR" checkout -f "$REF" >/dev/null
else
  mkdir -p "$(dirname "$APP_DIR")"
  git clone "$REPO_URL" "$APP_DIR"
  git -C "$APP_DIR" checkout -f "$REF" >/dev/null
fi

echo "==> 2/5 应用补丁"
shopt -s nullglob
for patch in "$HERE"/patches/*.patch; do
  name="$(basename "$patch")"
  # 补丁可能在 Windows 上编辑过（CRLF），先归一化成 LF 再应用
  tmp="$(mktemp)"
  tr -d '\r' < "$patch" > "$tmp"
  if git -C "$APP_DIR" apply --check "$tmp" >/dev/null 2>&1; then
    git -C "$APP_DIR" apply "$tmp"
    echo "    + $name"
  elif git -C "$APP_DIR" apply --reverse --check "$tmp" >/dev/null 2>&1; then
    echo "    = $name（已应用）"
  else
    rm -f "$tmp"
    echo "    ! $name 冲突：上游代码可能已变化，请检查补丁" >&2
    exit 1
  fi
  rm -f "$tmp"
done

echo "==> 3/5 数据目录"
mkdir -p "$APP_DIR/accounts" "$APP_DIR/usage"

echo "==> 4/5 构建镜像"
docker build -q -t "$IMAGE" "$APP_DIR" >/dev/null
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --restart unless-stopped \
  -p "${PORT}:${PORT}" \
  -e "PORT=${PORT}" -e TZ=Asia/Shanghai \
  -v "$APP_DIR/accounts:/app/accounts" \
  -v "$APP_DIR/usage:/app/usage" \
  "$IMAGE" python trae_proxy.py --lan --panel-password "$PANEL_PASSWORD" >/dev/null

echo "==> 5/5 健康检查"
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/ping" >/dev/null 2>&1; then
    ok=1; break
  fi
  sleep 2
done
if [ "${ok:-0}" != "1" ]; then
  echo "启动失败，排查：docker logs $CONTAINER" >&2
  exit 1
fi

KEY="$(docker logs "$CONTAINER" 2>&1 | grep -oE 'API Key +: +[^ ]+' | tail -1 | awk '{print $NF}')"
IP="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo '<服务器IP>')"
cat <<EOF

部署完成
  面板      http://${IP}:${PORT}
  面板密码  ${PANEL_PASSWORD}
  API       http://${IP}:${PORT}/v1
  API Key   ${KEY:-（见 docker logs $CONTAINER | grep -i 'api key'）}

  数据目录  ${APP_DIR}/accounts（账号凭据）、${APP_DIR}/usage（用量流水）
  记下 API Key，换服务器时只需再跑本脚本 + 备份目录。
EOF
