#!/usr/bin/env bash
# Trae 账号池一键部署（源码即本仓库，已内含本地改动）
#
# 用法：
#   PANEL_PASSWORD='你的面板密码' ./deploy.sh
# 可选环境变量：
#   PORT=8791              对外端口
#   APP_DIR=<仓库路径>      代码与数据目录（默认=本脚本所在目录）
#   CONTAINER / IMAGE      容器名 / 镜像名
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${APP_DIR:-$HERE}"
CONTAINER="${CONTAINER:-trae2api-hub}"
PORT="${PORT:-8791}"
IMAGE="${IMAGE:-trae2api-hub:latest}"
PANEL_PASSWORD="${PANEL_PASSWORD:-}"

if [ -z "$PANEL_PASSWORD" ]; then
  echo "错误：必须设置 PANEL_PASSWORD（面板密码）" >&2
  exit 1
fi

cd "$APP_DIR"
if [ ! -f trae_proxy.py ] || [ ! -f Dockerfile ]; then
  echo "错误：$APP_DIR 不是 hub 源码目录（缺少 trae_proxy.py / Dockerfile）" >&2
  exit 1
fi

echo "==> 1/4 准备数据目录"
mkdir -p "$APP_DIR/accounts" "$APP_DIR/usage"

echo "==> 2/4 构建镜像"
docker build -q -t "$IMAGE" "$APP_DIR" >/dev/null

echo "==> 3/4 启动容器"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --restart unless-stopped \
  -p "${PORT}:${PORT}" \
  -e "PORT=${PORT}" -e TZ=Asia/Shanghai \
  -v "$APP_DIR/accounts:/app/accounts" \
  -v "$APP_DIR/usage:/app/usage" \
  "$IMAGE" python trae_proxy.py --lan --panel-password "$PANEL_PASSWORD" >/dev/null

echo "==> 4/4 健康检查"
ok=0
for _ in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/ping" >/dev/null 2>&1; then
    ok=1; break
  fi
  sleep 2
done
if [ "$ok" != "1" ]; then
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

  代码与数据  ${APP_DIR}
    accounts/  账号凭据（含 token，勿提交、勿外发）
    usage/     用量流水
EOF
