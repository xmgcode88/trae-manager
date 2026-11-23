# Trae 账号池部署包（trae2api-hub + 本地补丁）

把 Trae CN 账号池做成可复刻的部署单元：换任何一台服务器，跑一条命令就能重建同样的服务。

## 为什么需要这个包

上游 `shuishuipingan/trae2api-hub` 没有我们需要的两个能力，我们在服务器上直接改了源码：

1. **支持 `chuanye-account` 格式的账号 JSON 导入**（token 包在 `oauth` 里、设备身份在 `identity` 里）
2. **面板「账号测试」对新模型走 SOLO 通道**（否则测 `GLM-5.3` 这类模型必报 `4023`，与真实调用结论相反）

改动只存在于那台机器的文件里，`git pull` 就会被覆盖、换服务器就完全丢失。所以把它固化成 `patches/*.patch`，部署时自动打上。

## 一条命令部署

```bash
# 目标服务器需有：docker、git、curl
scp -r deploy/trae-hub root@新服务器:/opt/
ssh root@新服务器
cd /opt/trae-hub
PANEL_PASSWORD='换成强密码' ./deploy.sh
```

脚本做的事：拉上游源码（**锁定 commit**）→ 打补丁（幂等）→ 构建镜像 → 起容器 → 健康检查 → 打印面板地址、API 地址和自动生成的 API Key。

常用参数（环境变量）：

| 变量 | 默认 | 说明 |
|---|---|---|
| `PANEL_PASSWORD` | 必填 | 面板登录密码（PBKDF2 存储） |
| `PORT` | `8791` | 对外端口（记得放行防火墙） |
| `APP_DIR` | `/opt/trae-hub` | 源码 + 数据目录 |
| `REF` | 锁定 commit `e7eef18` | 升级时改这里 |
| `CONTAINER` / `IMAGE` | `trae2api-hub` / `trae-hub:latest` | 容器/镜像名 |

## 账号怎么迁移

账号凭据在 `APP_DIR/accounts/`（每个账号一个 JSON + `settings.json`），用量在 `APP_DIR/usage/`。**这两个目录就是全部状态**，容器可以随时删了重建。

```bash
./backup.sh                      # 打包 accounts + usage
./backup.sh restore 包.tar.gz     # 目标机恢复后 docker restart trae2api-hub
```

导入新账号：面板「添加账号」走浏览器 OAuth，或把 `chuanye` 格式 JSON 交给面板「导入」（补丁已支持）。

## 升级上游

```bash
cd deploy/trae-hub
REF=origin/main ./deploy.sh      # 或指定新的 commit
```

补丁冲突时脚本会中止并提示（`patch 冲突：上游代码可能已变化`）。这时只有两种选择：

- 上游已合并同样的能力 → 删掉对应补丁；
- 上游改了相关代码 → 手动在 `APP_DIR` 里重做改动，`git diff > patches/000X-xxx.patch` 更新补丁。

## 代码怎么长期管理（三种方式，按需要选）

| 方式 | 做法 | 适合 |
|---|---|---|
| **A. 部署包（当前）** | 本目录进你自己的 git 仓库，补丁跟着版本走 | 少量服务器、只自己用（推荐先这样） |
| **B. 自建 fork** | fork 上游，把补丁提交成一个分支，部署直接 `git clone` 你的 fork | 服务器多、要 CI 自动构建镜像 |
| **C. 提 PR** | 把补丁整理后提给上游作者 | 想少维护，但要等作者接受 |

方式 A 与 B 可以叠加：先用 A 跑通，等服务器多了再转 B。

## 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| 调用新模型返回 `4023 model is unknown` | 模型被送到 IDE 通道了。`/v1/chat/completions` 会自动把 SOLO 组模型路由到 SOLO 通道；直连 `trae_client.open_chat` 调试则会报这个 |
| `503 no CN account available` | 账号被冷却（约 5 分钟）。改 `accounts/<uid>.json` 的 `cooldown_until`/`breaker_until`/`fails` 后重启容器 |
| 面板 `/admin/*` 返回 401 | 正常的鉴权；登录 `/panel/login` 拿 `X-Panel-Token`，密码在 `settings.json` 里以哈希保存 |
| 导入提示「不是账号文档」 | 补丁没打上，或文件既不是扁平行也不是 `chuanye` 结构 |
| SSH 连不上（`Error reading SSH protocol banner`） | 频繁连接触发 sshd 保护，等几分钟；脚本部署不受影响 |

## 安全约定

- 面板密码必须改掉默认值（脚本强制传 `PANEL_PASSWORD`）。
- `accounts/` 里是账号 token，等同账号密码：备份包不要进公开仓库、不要放共享盘。
- 对外暴露的应是 NewAPI 之类的上层网关；hub 本身最好只监听内网或被防火墙限制来源 IP。
