# trae-manager · Trae 账号池（trae2api-hub 二次维护版）

Trae CN 账号池网关：把多个 Trae 账号做成一个 OpenAI 兼容 API，并带 Web 面板管理、每个 API Key 的模型白名单与日配额。

本仓库 = **上游 `shuishuipingan/trae2api-hub` 完整源码 + 本地改动**，可以直接改代码、部署、升级。

## 与上游的差异

在 `e7eef18`（v1.7.1）基础上做了两处改动：

1. **支持 `chuanye-account` 格式的账号 JSON 导入**
   这类导出把凭据放在 `oauth`、设备身份放在 `identity`，顶层没有 token，上游会判成「不是账号文档」。新增 `_row_from_chuanye_doc()` 做转换（含丢弃无效的本机代理地址）。
2. **面板「账号测试」对新模型走 SOLO 通道**
   上游测试固定走 IDE 通道，测 `GLM-5.3` / `Kimi-K3` 这类模型必报 `4023 model is unknown`，与真实调用结论相反。

查看差异：

```bash
git diff upstream/main -- trae_accounts.py trae_proxy.py
```

## 部署（新服务器）

需要 docker、git、curl。

```bash
git clone git@github.com:xmgcode88/trae-manager.git /opt/trae-manager
cd /opt/trae-manager
PANEL_PASSWORD='换成强密码' ./deploy.sh
```

脚本会：建数据目录 → 构建镜像 → 启动容器（`--lan` 自动生成 API Key）→ 健康检查 → 打印面板地址、API 地址和 Key。

| 变量 | 默认 | 说明 |
|---|---|---|
| `PANEL_PASSWORD` | 必填 | 面板登录密码（PBKDF2 存储） |
| `PORT` | `8791` | 对外端口（记得放行防火墙） |
| `APP_DIR` | 本仓库目录 | 代码与数据目录 |
| `CONTAINER` / `IMAGE` | `trae2api-hub` / `trae2api-hub:latest` | 容器 / 镜像名 |

## 账号管理

账号凭据在 `accounts/`（每个账号一个 JSON + `settings.json`），用量在 `usage/`。**这两个目录就是全部状态**，容器可随时重建。

- 加账号：面板「添加账号」走浏览器 OAuth；或导入 `chuanye` 格式 JSON
- 迁移/备份：`./backup.sh` 打包，`./backup.sh restore 包.tar.gz` 恢复（包内含 token，等同密码）
- 面板地址：`http://<IP>:8791`；API：`http://<IP>:8791/v1`

## 改代码与升级

```bash
# 改代码
vim trae_proxy.py
git commit -am "fix: 说明" && git push

# 其它服务器同步
cd /opt/trae-manager && git pull && PANEL_PASSWORD='...' ./deploy.sh

# 跟上上游新版本
git fetch upstream main
git merge upstream/main      # 冲突一般只在 trae_accounts.py / trae_proxy.py 的改动附近
PANEL_PASSWORD='...' ./deploy.sh
```

上游镜像已配置：`upstream` → `git@github.com:shuishuipingan/trae2api-hub.git`。

## 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| 新模型返回 `4023 model is unknown` | 请求被送到 IDE 通道。`/v1/chat/completions` 会自动把 SOLO 组模型路由到 SOLO 通道；直接调 `trae_client.open_chat` 调试则会报此错 |
| `503 no CN account available` | 账号被冷却（约 5 分钟）。改 `accounts/<uid>.json` 的 `cooldown_until` / `breaker_until` / `fails` 后 `docker restart trae2api-hub` |
| 面板 `/admin/*` 返回 401 | 正常鉴权。`POST /panel/login` 拿 `X-Panel-Token` |
| 导入提示「不是账号文档」 | 检查文件是扁平行（顶层有 token）还是 `chuanye` 结构（`oauth` 里有 token） |
| SSH 报 `Error reading SSH protocol banner` | 频繁连接触发 sshd 保护，等几分钟 |

## 安全约定

- `accounts/` 里是账号 token，等同账号密码：不要提交、不要外发备份包。
- 面板密码不要用默认值（脚本强制传 `PANEL_PASSWORD`）。
- hub 本身建议只对内网或上层网关（如 NewAPI）暴露，必要时用防火墙限制来源 IP。

上游项目文档见 [UPSTREAM.md](UPSTREAM.md)，协议细节见 `docs/`。
