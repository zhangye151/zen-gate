# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# zen-gate headless container（fork 增强版）
#   OpenCode Zen 免费模型网关：把免费车道封装成 OpenAI/Anthropic 兼容 API。
#   在容器里以无界面（--no-tray）模式运行，只跑网关，不带桌面托盘。
#
# 这个 Dockerfile 与上游用法不同：**构建上下文 = 本仓库根目录**（fork 源码），
# 而不是自己再拉一份固定 commit。这样做的目的是：
#   - 你的 fork 只要「Sync fork」合入上游更新，构建出的镜像就会自动是最新上游 +
#     容器补丁，无需改任何配置；
#   - 补丁单独放在 docker/patches/lan-admin.patch，构建时用 patch -p1 打到源码上，
#     因此上游改动永远不会覆盖掉我们的增强（只可能让补丁失效，构建会明确报错）。
#
# 为什么需要这些构建依赖：
#   - 上游是 Go 桌面托盘程序，Linux 编译会引入 getlantern/systray（GTK3 +
#     appindicator，cgo），构建期需要 C 头文件，运行期需要 .so 库；
#    即便 --no-tray 不调用 GTK，二进制仍 DT_NEEDED 这两份库，运行镜像须带上。
#
# 构建：docker build -t zen-gate:latest -f docker/Dockerfile .
#   （GitHub Actions 已在 .github/workflows/docker-build.yml 里自动做这件事并
#     推送到 GHCR：ghcr.io/zhangye151/zen-gate）
# ---------------------------------------------------------------------------

# ---------- 构建阶段 ----------
FROM golang:1.26-bookworm AS builder

# 国内网络直连 proxy.golang.org 不稳定（实测 EOF），改用 goproxy.cn
ENV GOPROXY=https://goproxy.cn,direct

ARG ZEN_GATE_VERSION=dev

RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc libc6-dev pkg-config git ca-certificates \
      libgtk-3-dev libayatana-appindicator3-dev patch \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
# 构建上下文 = 仓库根目录：上游源码（已同步的最新版）+ docker/ 打包文件
COPY . .

# 容器补丁：allowLanAdmin / adminPassword / lanBaseURL（局域网直连面板 + Web 登录
# 页），以及面板复制按钮在明文 HTTP 下的 execCommand 兜底。
# 用 patch -p1 而不是 git apply（构建上下文不携带 .git）。
RUN patch -p1 < docker/patches/lan-admin.patch \
    || { echo '[zen-gate] 补丁应用失败：上游源码与本 fork 的补丁冲突。'; \
         echo '[zen-gate] 请参照 README「上游更新后如何同步」刷新 docker/patches/lan-admin.patch。'; \
         exit 1; }

# CGO_ENABLED=1：systray(linux) 需要 cgo 链接 GTK/appindicator。
# 模块下载可能被网络波动打断，构建做 3 次重试。
RUN attempts=0; until CGO_ENABLED=1 go build -trimpath \
      -ldflags "-X zen-gate/internal/gateway.Version=$ZEN_GATE_VERSION -X zen-gate/internal/update.Current=$ZEN_GATE_VERSION" \
      -o /out/zen-gate ./cmd/zen-gate; do \
        attempts=$((attempts+1)); \
        if [ "$attempts" -ge 3 ]; then echo "go build failed 3 times"; exit 1; fi; \
        echo "go build attempt $attempts failed, retrying"; sleep 5; \
      done

# ---------- 运行阶段 ----------
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      libgtk-3-0 libayatana-appindicator3-1 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /data && chown -R 1000:1000 /data

COPY --from=builder /out/zen-gate /usr/local/bin/zen-gate
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV ZEN_GATE_HOME=/data \
    ZEN_GATE_PORT=8787 \
    ZEN_GATE_ALLOW_LAN=1 \
    ZEN_GATE_KEY= \
    ZEN_GATE_ADMIN_PASSWORD=

VOLUME ["/data"]
EXPOSE 8787

# 非 root 运行；/data 已在上面授权给 uid 1000
USER 1000:1000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
