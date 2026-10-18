# zen-gate Docker · 部署到 1Panel / 局域网详解

本 fork 的镜像支持**普通桥接 + 端口映射**直接跑在 1Panel，无需 host 网络、无需任何反向代理容器。

## 为什么原版需要反代、这个镜像不用

| | 原版 zen-gate | 本 fork 镜像 |
| --- | --- | --- |
| 面板来源限制 | 只接受 `127.0.0.1`，桥接容器访问会 403 | `allowLanAdmin` 补丁已放行局域网 |
| 面板认证 | 无（或靠反代的 Basic Auth） | 内置 **Web 登录页**（HMAC 会话 cookie，7 天） |
| 局域网 Base URL | 自动探测显示容器 IP（`172.17.0.x`，不可达） | `ZEN_GATE_LAN_BASE_URL` 覆盖为你的真实 IP |
| 复制按钮 | 明文 HTTP 下 `navigator.clipboard` 失效 | `execCommand` 兜底，任意上下文可复制 |

## 1Panel 部署步骤

1. **拉镜像**：容器 → 创建 → 镜像填 `ghcr.io/zhangye151/zen-gate:latest`
2. **网络**：选**普通（桥接）**，端口映射 `8787 → 8787`
3. **环境变量**：
   - `ZEN_GATE_KEY` = 你的网关主密钥（`ofm-xxxx`）
   - `ZEN_GATE_ADMIN_PASSWORD` = 面板登录密码
   - `ZEN_GATE_LAN_BASE_URL` = `http://你的主机IP:8787/v1`
4. **数据卷**：挂载一个持久化目录到 `/data`（配置/日志不会丢）
5. **防火墙**：若 1Panel 自带防火墙默认 DROP，需放行 `8787` 端口

> 已运行过、之后要更新：1Panel UI 对容器点"更新/重建"，镜像改 `ghcr.io/zhangye151/zen-gate:latest`，网络保持桥接 + `8787:8787` 即可，不会再报错。

## 访问

| 入口 | 地址 |
| --- | --- |
| 管理面板 | `http://<主机IP>:8787/`（Web 登录页，密码 = `ZEN_GATE_ADMIN_PASSWORD`） |
| OpenAI API | `http://<主机IP>:8787/v1`（`/v1/models`、`/v1/chat/completions`） |
| Anthropic API | `http://<主机IP>:8787/v1/messages` |

## 本机 / 容器内智能体接入

同一局域网（或同一台机器的容器）直接用 API 地址即可：

```
BASE_URL = http://<主机IP>:8787/v1
API_KEY  = ZEN_GATE_KEY（ofm-xxxx）
MODEL    = beam-free / deep 等（免费模型名，可在面板"模型档位"查看）
```

## 验证

```bash
# API 是否通
curl http://<主机IP>:8787/v1/models -H "Authorization: Bearer <你的密钥>"

# 面板是否返回登录页（200）
curl -I http://<主机IP>:8787/admin/login
```
