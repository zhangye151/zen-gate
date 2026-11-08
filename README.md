# zen-gate · Docker 增强版

[zen-gate](https://github.com/LAGcomcom/zen-gate)（OpenCode Zen 免费模型网关，OpenAI / Anthropic 兼容）的 **自包含单镜像容器版**。

> 一句话：把上游的免费模型网关，打包成一个能跑在任意 Docker / 1Panel 上的镜像，局域网直接开面板维护模型接口，无需任何反向代理容器。

当前锁定上游 **v1.10.0**（commit `52e1e62ff7b6817f02bb8a30541c5009c91c0515`）。

---

## 这个仓库比上游多了什么

原版 zen-gate 是桌面托盘程序，管理面板只接受 `127.0.0.1` 来源，局域网访问必须靠反代容器伪装来源，且镜像不自带容器化。本仓库只做 **容器化增强**，不改动上游的网关逻辑：

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

## 上游更新后如何跟进（重点）

**本仓库不是上游源码的镜像，只保留容器打包文件。** 上游源码在构建时由 `docker/Dockerfile` 直接 `git fetch` 指定 commit 拉取 —— 这就是仓库里没有 `internal/`、`cmd/`、`assets/` 的原因，刻意为之（267 个文件 / 3.2 MB 精简到 10 个文件 / 90 KB）。

**不要用 Sync fork。** 仓库里已无上游源码，Sync 只会产生成片的 `modify/delete` 冲突，还得逐个手工 resolve。

跟进新版本只有一个动作 —— 改 `docker/Dockerfile` 顶部两行：

```dockerfile
ARG ZEN_GATE_COMMIT=<上游新 commit>
ARG ZEN_GATE_VERSION=<新版本号（不带 v）>
```

推送到 `master` 后，`.github/workflows/docker-build.yml` 自动构建并推送新镜像。

### 具体步骤

```bash
# 1. 查上游最新 tag 及对应 commit
git ls-remote --tags https://github.com/LAGcomcom/zen-gate | tail -5

# 2. 改 docker/Dockerfile 的两个 ARG
#    注意 ZEN_GATE_COMMIT 必须写完整 40 位 commit，不能写 tag 名

# 3. 推送 → CI 自动构建
git commit -am "chore: bump to upstream vX.Y.Z" && git push
```

也可以在 GitHub 网页上直接编辑 `docker/Dockerfile` 这两行，提交后同样触发构建。

### 构建产物与触发方式

| 触发 | 产物 |
| --- | --- |
| push 到 `master` | `:latest` + `:<版本号>` + `:<commit sha>` |
| 手动 | Actions → `build-zen-gate-image` → Run workflow |
| 每周一 03:00 | 定时重建（跟随上游最新状态） |

### 如果补丁打不上

上游改了 `internal/gateway/admin.go` / `server.go` / `web/index.html` / `internal/store/store.go` 之一时，构建会在 `git apply` 这一步失败，日志是标准报错：

```
error: patch failed: internal/gateway/admin.go:224
error: internal/gateway/admin.go: patch does not apply
```

这时重做补丁（锚点变了，改锚点重跑重放脚本即可）：

```bash
git clone https://github.com/LAGcomcom/zen-gate /tmp/zg && cd /tmp/zg
git checkout vX.Y.Z

# 用本地维护的重放脚本重放 13 处文本替换（每处命中次数必须恰好为 1）
python3 regenerate_patch.py

# 脚本会导出新的 docker/patches/lan-admin.patch 并自检，再提交推送
```

> 重放脚本按 "old → new" 文本对逐处替换，每处 `replace_once` 校验命中次数，失败即整体退出、不产出补丁 —— 保证补丁永远是干净可 apply 的。

---

## 本地 / 服务器自己构建（可选）

不需要 GitHub 也可以本地构建（例如没有外网权限的内网服务器）。Dockerfile 会在构建器内 `git fetch` 上游源码，不依赖仓库里的源码：

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

## 仓库结构

```
.
├── docker/
│   ├── Dockerfile                # 多阶段构建；顶部两个 ARG 决定拉哪个上游版本
│   ├── entrypoint.sh             # 首次预置 config.json + 启动
│   ├── patches/lan-admin.patch   # 全部增强补丁（唯一需要维护的文件）
│   ├── docker-compose.yml        # 1Panel 可直接导入
│   └── README-deploy.md          # 详细部署/访问/防火墙说明
├── .github/workflows/
│   └── docker-build.yml          # 自动构建 → GHCR
├── .dockerignore
├── .gitignore
├── LICENSE
└── README.md
```

> 上游源码**有意不放进仓库**：只在构建时 `git fetch` 拉取，仓库保持极简（约 90 KB）。代价是放弃 Sync fork，换来"改两个 ARG 就能跟进任何上游版本"，且不会再被上游的内部重构（`internal/` 目录经常整块重排）干扰。
