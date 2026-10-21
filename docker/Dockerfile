# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# zen-gate headless container
#   OpenCode Zen 免费模型网关：把免费车道封装成 OpenAI/Anthropic 兼容 API。
#   在容器里以无界面（--no-tray）模式运行，只跑网关，不带桌面托盘。
#
# 为什么是这个构建方式：
#  - 上游是 Go 桌面托盘程序，Linux 编译会引入 getlantern/systray（GTK3 +
#    appindicator，cgo），所以构建期需要对应 C 头文件，运行期需要 .so 库。
#   即便 --no-tray 不调用 GTK，二进制仍 DT_NEEDED 这两份库，运行镜像须带上。
#  - 源码在构建器内按固定 commit 拉取，镜像可在任意有 Docker 的机器/1Panel
#    上直接构建，无需把源码传到服务器。
#  - 版本号通过 ldflags 注入（与上游 make 脚本一致，不剥符号，方便 crash 栈）。
#
# 构建：docker build -t zen-gate:1.8.2 .
# ---------------------------------------------------------------------------

# ---------- 构建阶段 ----------
FROM golang:1.26-bookworm AS builder

# 国内网络直连 proxy.golang.org 不稳定（实测 EOF），改用 goproxy.cn
ENV GOPROXY=https://goproxy.cn,direct

ARG ZEN_GATE_REPO=https://github.com/LAGcomcom/zen-gate.git
# 固定到本次分析过的 HEAD 提交，保证可复现（v1.8.2）
ARG ZEN_GATE_COMMIT=f7b390431d59124e4136247ee346fa485c47f948
ARG ZEN_GATE_VERSION=1.8.2

RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc libc6-dev pkg-config git ca-certificates \
      libgtk-3-dev libayatana-appindicator3-dev \
    && rm -rf /var/lib/apt/lists/*

# 按固定 commit 浅拉取（任意 SHA 无法直接用 clone --branch，改用 init+fetch）。
# 服务器到 github.com 网络不稳定（实测偶发 EOF），fetch 做 3 次重试。
RUN git init /src \
    && cd /src \
    && git remote add origin "$ZEN_GATE_REPO" \
    && for i in 1 2 3; do git fetch --depth 1 origin "$ZEN_GATE_COMMIT" && break || { echo "fetch attempt $i failed, retrying"; sleep 5; }; done \
    && git checkout FETCH_HEAD

# 容器补丁：allowLanAdmin / adminPassword（局域网直接访问面板 + Web 登录），
# 让面板无需反代容器即可从局域网打开；另删网页用不到的最小化/最大化/关闭按钮。
COPY patches/lan-admin.patch /src/patches/lan-admin.patch
RUN cd /src && git apply /src/patches/lan-admin.patch

WORKDIR /src
# CGO_ENABLED=1：systray(linux) 需要 cgo 链接 GTK/appindicator。
# 模块下载同样可能被网络波动打断，构建做 3 次重试。
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
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
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
