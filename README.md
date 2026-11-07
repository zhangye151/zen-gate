# zen-gate · Docker 增强版

[zen-gate](https://github.com/LAGcomcom/zen-gate)（OpenCode Zen 免费模型网关，OpenAI / Anthropic 兼容）的 **自包含单镜像容器版**。

> 一句话：把上游的免费模型网关，打包成一个能跑在任意 Docker / 1Panel 上的镜像，局域网直接开面板维护模型接口，无需任何反向代理容器。

当前锁定上游 **v1.10.0**（commit `52e1e62ff7b6817f02bb8a30541c5009c91c0515`）。

---

## 这个 fork 比上游多了什么

原版 zen-gate 是桌面托盘程序，管理面板只接受 `127.0.0.1` 来源，局域网访问必须靠反代容器伪装来源，且镜像不自带容器化。本 fork 只做 **容器化增强**，不改动上游的网关逻辑：

| 增强 | 说明 |
| --- | --- |
| **Docker 化** | 多阶段构建，无界面（`--no-tray`）运行，含 systray 所需的 GTK/appindicator 依赖 |
| **局域网面板** | `allowLanAdmin` 补丁：拆掉面板"仅回环来源"的限制，**普通桥接 + 端口映射**即可在局域网直接开面板（原版桥接会 403） |
| **Web 登录页** | 不再弹浏览器 Basic Auth 弹窗，改为**内嵌登录页**（输密码 → HMAC 会话 cookie，7 天免登录，HttpOnly + SameSite=Lax） |
| **局域网 Base URL** | `lanBaseURL` 覆盖：面板显示的"局域网 Base URL"填你的真实 IP，而不是容器桥接 IP（`172.17.0.x`，局域网不可达） |
| **复制按钮修复** | 明文 HTTP 下 `navigator.clipboard` 不可用，加了 `execCommand` 兜底，主 Key / Base URL / 完整接入配置都能复制 |
| **去掉窗口按钮** | 网页版用不到的最小化 / 最大化 / 关闭按钮（及对应事件绑定）一并删除 |

所有增强集中在 `docker/patches/lan-admin.patch`，构建时用 `git apply` 打到上游源码上 —— 所以**上游怎么更新都不会覆盖我们的增强**。

> ⚠️ 行尾陷阱：上游 `internal/gateway/*.go`、`internal/store/store.go` 是 **CRLF**，而补丁以 LF 保存。Dockerfile 在打补丁前会先把 `*.go` / `*.html` 统一成 LF，否则 `git apply` 会因为每行差一个 `\r` 而整文件冲突（表现为 `@@ -1,2050 +1,2187 @@` 这种全文 hunk）。

---

## 直接拿镜像（GitHub Actions 自动构建 → GHCR）

镜像在 `ghcr.io/zhangye151/zen-gate`，由 `.github/workflows/docker-build.yml` 自动构建推送。Tag：

| Tag | 含义 |
| --- | --- |
| `ghcr.io/zhangye151/zen-gate:latest` | 最新（推荐） |
| `ghcr.io/zhangye151/zen-gate:1.10.0` | 对应上游 release 版本（从 `docker/Dockerfile` 的 `ZEN_GATE_VERSION` 取） |
| `ghcr.io/zhangye151/zen-gate:<commit sha>` | 精确到某次提交 |

> fork 仓库未同步上游 git tag 时，工作流自动回退到读 `docker/Dockerfile` 里的 `ZEN_GATE_VERSION`，不会退化成 `latest` 当版本号。

### Docker 一键跑

```bash
docker run -d --name zen-gate --restart unless-stopped -p 8787:8787 \
  -e ZEN_GATE_HOME=/data \
  -e ZEN_GATE_PORT=8787 \
  -e ZEN_GATE_KEY=你的网关主密钥（ofm-xxxx） \
  -e ZEN_GATE_ADMIN_PASSWORD=你的面板密码 \
  -e ZEN_GATE_LAN_BASE_URL=http://你的主机IP:8787/v1 \
  -v ./zen-gate-data:/data \
  ghcr.io/zhangye151/zen-gate:latest
```

### docker compose / 1Panel

直接导入 [`docker/docker-compose.yml`](docker/docker-compose.yml)（普通桥接 + `8787:8787`，1Panel UI 更新/重建正常）。

### 访问

| 入口 | 地址 |
| --- | --- |
| 管理面板 | `http://<主机IP>:8787/` → 打开是 **Web 登录页**，输 `ZEN_GATE_ADMIN_PASSWORD` 进入 |
| OpenAI 兼容 API | `http://<主机IP>:8787/v1`（`/v1/chat/completions`、`/v1/responses`） |
| Anthropic 兼容 API | `http://<主机IP>:8787/v1/messages` |
| 登出 | `http://<主机IP>:8787/admin/logout` |

### 环境变量

| 变量 | 必填 | 说明 |
| --- | --- | --- |
| `ZEN_GATE_KEY` | ✅ | 网关主密钥（`ofm-xxxx`），首次启动预置进 config.json |
| `ZEN_GATE_ADMIN_PASSWORD` | 面板密码 | 设置后开启局域网面板（`allowLanAdmin=true`）+ Web 登录；留空则面板不可从局域网开 |
| `ZEN_GATE_LAN_BASE_URL` | 建议 | 覆盖面板"局域网 Base URL"，填你主机真实 IP，如 `http://192.168.123.8:8787/v1` |
| `ZEN_GATE_HOME` | 数据目录 | 默认 `/data` |
| `ZEN_GATE_PORT` | 监听端口 | 默认 `8787` |

> 首次启动才会预置 config.json；之后以数据卷里的配置为准（改配置直接改 `zen-gate-data/config.json` 后重启容器）。
> 如果你把宿主端口改成了 `8788`，别忘了同步改 config.json 里的 `lanBaseURL`，面板上展示的地址才是对外可用的那个。

---

## 上游更新后如何同步（重点）

这是真实 fork（`zhangye151/zen-gate ← LAGcomcom/zen-gate`），所以同步走 GitHub 官方机制，**不会覆盖你的任何东西**：

1. **合入上游更新**：在你的 fork 首页点 **Sync fork**（GitHub 会把上游新提交合入你 fork 的 `master`）。因为 docker 打包文件在 `docker/` 和 `.github/`，上游根本没有这些文件，合并永远不会动它们；你的补丁在 `docker/patches/lan-admin.patch`，也不受影响。
2. **自动重建新镜像**：合并推送到 `master` 后，`build-zen-gate-image` 工作流自动触发，用"新上游源码 + 补丁"构建并推 `latest`。也可以：
   - 手动：Actions → `build-zen-gate-image` → **Run workflow**
   - 每周自动重建：工作流带 `schedule`，每周一 03:00 跑一次
3. **拉新镜像**：1Panel / 服务器把容器镜像改成 `ghcr.io/zhangye151/zen-gate:latest` 重新创建即可。

### 万一上游改了补丁涉及的文件（会怎样）

如果上游更新恰好改了 `admin.go` / `server.go` / `web/index.html` / `store.go` 之一，导致补丁打不上，**构建会在 `git apply` 这一步直接失败**，日志里是标准报错：

```
error: patch failed: internal/gateway/admin.go:224
error: internal/gateway/admin.go: patch does not apply
```

这时只需要重做补丁（锚点改了，改锚点重跑即可）：

```bash
# 1. 拿一份干净的上游源码，检出目标版本
git clone https://github.com/LAGcomcom/zen-gate /tmp/zg && cd /tmp/zg
git checkout v1.10.0            # 换成新版本

# 2. 对着 docker/patches/lan-admin.patch 的内容逐处重新应用（或直接修锚点后重跑重放脚本）
#    注意顺序：改文本必须按脚本精确替换，不要手改，容易改动 1 个字符就 apply 不了

# 3. 导出补丁（必须保持 LF，且不要丢掉尾随空格以外的内容）
git diff > docker/patches/lan-admin.patch

# 4. 把新版本号写回 Dockerfile 的 ZEN_GATE_COMMIT / ZEN_GATE_VERSION，提交推送 → 自动重建
git add -A && git commit -m "chore: refresh patch for upstream vX.Y.Z" && git push
```

> 更省事的做法：本地维护一个重放脚本（按“old → new”文本对逐处替换，每处校验命中次数必须恰好为 1），换版本时只改锚点，一键导出补丁并自检 `git apply --check`。这个仓库只存最终补丁，脚本不进来。

---

## 本地 / 服务器自己构建（可选）

不需要 GitHub 也可以本地构建（例如没有外网权限的内网服务器）：

```bash
git clone https://github.com/zhangye151/zen-gate && cd zen-gate
docker build -t zen-gate:latest -f docker/Dockerfile .
docker run -d --name zen-gate -p 8787:8787 \
  -e ZEN_GATE_KEY=你的密钥 -e ZEN_GATE_ADMIN_PASSWORD=你的密码 \
  -e ZEN_GATE_LAN_BASE_URL=http://你的IP:8787/v1 \
  -v ./zen-gate-data:/data zen-gate:latest
```

> 本地构建时 build context 是仓库根目录，Dockerfile 里的 `COPY docker/patches/...` 路径可以直接用。

---

## 结构说明

```
docker/
├── Dockerfile                # 多阶段构建（上下文 = 仓库根目录）
├── entrypoint.sh             # 首次预置 config.json + 启动
├── patches/lan-admin.patch   # 全部增强补丁（唯一需要维护的文件）
├── docker-compose.yml        # 1Panel 可直接导入
└── README-deploy.md          # 详细部署/访问/防火墙说明
.github/workflows/
└── docker-build.yml          # 自动构建 → GHCR
```

> 上游源码保持原样（干净），增强全在补丁文件里 —— 这是"永远不被上游覆盖"的关键设计。