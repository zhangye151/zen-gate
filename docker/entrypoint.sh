#!/bin/sh
# ---------------------------------------------------------------------------
# zen-gate 容器启动脚本
#  - 首次启动时预置一份合法 config.json（mainKey 非空），否则 store.Open 会
#    用默认配置覆盖（allowLan=false，网关只绑 127.0.0.1，容器外不可达）。
#  - allowLan=true → 网关绑 0.0.0.0，配合 docker 端口映射即可被局域网访问。
#  - allowLanAdmin=true（配合 ZEN_GATE_ADMIN_PASSWORD）→ 放行局域网访问管理
#    面板，并用内置 Basic Auth 保护，无需再挂反代容器。
#  - 之后以 --no-tray 控制台模式运行，日志走 stdout（1Panel 可直接看）。
# ---------------------------------------------------------------------------
set -eu

: "${ZEN_GATE_HOME:=/data}"
: "${ZEN_GATE_PORT:=8787}"
: "${ZEN_GATE_KEY:?需要设置 ZEN_GATE_KEY（形如 ofm-xxxx 的网关主密钥）}"
# 可选：设置后开启局域网面板（allowLanAdmin=true）并用该密码做 Basic Auth
: "${ZEN_GATE_ADMIN_PASSWORD:=}"
# 可选：覆盖面板"局域网 Base URL"（桥接容器自动检测会显示容器 IP，不可达）。
# 填宿主机真实局域网地址，如 http://192.168.123.8:8787/v1
: "${ZEN_GATE_LAN_BASE_URL:=}"

mkdir -p "$ZEN_GATE_HOME"
config="$ZEN_GATE_HOME/config.json"

if [ ! -f "$config" ]; then
  # 只写必填字段即可：缺失字段 store.Open 会补默认值。
  # port / mainKey / agentKeys / allowLan / exposeRegion 是决定行为的核心。
  cat > "$config" <<EOF
{
  "port": $ZEN_GATE_PORT,
  "allowLan": true,
  "allowLanAdmin": ${ZEN_GATE_ADMIN_PASSWORD:+true}${ZEN_GATE_ADMIN_PASSWORD:-false},
  "adminPassword": "$ZEN_GATE_ADMIN_PASSWORD",
  "lanBaseURL": "$ZEN_GATE_LAN_BASE_URL",
  "mainKey": "$ZEN_GATE_KEY",
  "agentKeys": {},
  "defaultMaxTokens": 32768,
  "probeIntervalMinutes": 15,
  "exposeRegion": true,
  "enabledAgents": {}
}
EOF
  chmod 600 "$config"
  echo "[entrypoint] seeded $config (allowLan=true, allowLanAdmin=${ZEN_GATE_ADMIN_PASSWORD:+true}, port=$ZEN_GATE_PORT)"
fi

echo "[entrypoint] starting zen-gate --no-tray on 0.0.0.0:$ZEN_GATE_PORT"
exec /usr/local/bin/zen-gate --no-tray --port "$ZEN_GATE_PORT"
