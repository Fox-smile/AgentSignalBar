#!/usr/bin/env bash
# ============================================================================
# Agent Signal Bar — 一键安装 & 自动配置
# ============================================================================
# 一条命令完成所有电脑端配置：
#   curl -fsSL <url>/install.sh | bash
#   或
#   chmod +x setup.sh && ./setup.sh
#
# 自动完成：
#   1. 安装适配脚本到 ~/.agent-signal/hooks/
#   2. 自动检测 Claude Code / Codex / Trae / CodeBuddy / WorkBuddy
#   3. 自动修改各 Agent 的 Hook 配置文件（备份原文件）
#   4. 生成 launchd systemd 自启动配置
#   5. 立即启动 HTTP Server
# ============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="${HOME}/.agent-signal"
HOOKS_DIR="${INSTALL_DIR}/hooks"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${AGENT_SIGNAL_PORT:-9120}"

echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     🚦 Agent Signal Bar — 一键安装      ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ─────────────────────────────────────────────────────
# 1. 安装适配脚本
# ─────────────────────────────────────────────────────
echo -e "${BOLD}[1/5]${NC} 安装适配脚本..."
mkdir -p "$HOOKS_DIR"

cp -f "$SCRIPT_DIR/scripts/hooks/agent-signal-claude.sh"     "$HOOKS_DIR/"
cp -f "$SCRIPT_DIR/scripts/hooks/agent-signal-codex.sh"      "$HOOKS_DIR/"
cp -f "$SCRIPT_DIR/scripts/hooks/agent-signal-trae.sh"       "$HOOKS_DIR/"
cp -f "$SCRIPT_DIR/scripts/hooks/agent-signal-codebuddy.sh"  "$HOOKS_DIR/"
cp -f "$SCRIPT_DIR/scripts/hooks/agent-signal-workbuddy.sh"  "$HOOKS_DIR/"
cp -f "$SCRIPT_DIR/server/agent_signal_server.py"            "$INSTALL_DIR/"

chmod +x "$HOOKS_DIR"/*.sh "$INSTALL_DIR/agent_signal_server.py"
echo -e "  ${GREEN}✓${NC} 脚本已安装到 ${HOOKS_DIR}/"

# ─────────────────────────────────────────────────────
# 2. 检测已安装的 Agent
# ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2/5]${NC} 检测 Agent..."

declare -A AGENT_DETECTED
CONFIGURED_COUNT=0

# Claude Code
if command -v claude &>/dev/null || [ -d "$HOME/.claude" ]; then
    AGENT_DETECTED["claude-code"]=1
    echo -e "  ${GREEN}✓${NC} Claude Code"
fi

# Codex
if command -v codex &>/dev/null || [ -d "$HOME/.codex" ]; then
    AGENT_DETECTED["codex"]=1
    echo -e "  ${GREEN}✓${NC} Codex"
fi

# Trae
if [ -d "$HOME/Library/Application Support/Trae" ] || [ -d "$HOME/.trae" ]; then
    AGENT_DETECTED["trae"]=1
    echo -e "  ${GREEN}✓${NC} Trae IDE"
fi

# CodeBuddy
if command -v codebuddy &>/dev/null || [ -d "$HOME/.codebuddy" ]; then
    AGENT_DETECTED["codebuddy"]=1
    echo -e "  ${GREEN}✓${NC} CodeBuddy"
fi

# WorkBuddy
if [ -d "$HOME/.workbuddy" ] || [ -f "package.json" ] && grep -q "workbuddy-harness" package.json 2>/dev/null; then
    AGENT_DETECTED["workbuddy"]=1
    echo -e "  ${GREEN}✓${NC} WorkBuddy"
fi

if [ ${#AGENT_DETECTED[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}未检测到已知 Agent，将仅安装 HTTP Server${NC}"
fi

# ─────────────────────────────────────────────────────
# 3. 自动配置每个 Agent 的 Hook
# ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[3/5]${NC} 自动配置 Agent Hook..."

HOOK_CLAUDE_SH="$HOOKS_DIR/agent-signal-claude.sh"
HOOK_CODEX_SH="$HOOKS_DIR/agent-signal-codex.sh"
HOOK_TRAE_SH="$HOOKS_DIR/agent-signal-trae.sh"
HOOK_CB_SH="$HOOKS_DIR/agent-signal-codebuddy.sh"
HOOK_WB_SH="$HOOKS_DIR/agent-signal-workbuddy.sh"

# ── Claude Code ─────────────────────────────────────
configure_claude_code() {
    local settings_file="$HOME/.claude/settings.json"
    local backup="${settings_file}.backup-$(date +%Y%m%d%H%M%S)"

    # 确保目录存在
    mkdir -p "$HOME/.claude"

    # 备份
    if [ -f "$settings_file" ]; then
        cp "$settings_file" "$backup"
        echo -e "  ${GREEN}✓${NC} 已备份: $backup"
    fi

    # 读取现有配置或创建新配置
    python3 -c "
import json, os

hooks_config = {
    'SessionStart':       [{'matcher': '', 'command': '$HOOK_CLAUDE_SH'}],
    'PreToolUse':         [{'matcher': '*', 'command': '$HOOK_CLAUDE_SH'}],
    'PostToolUse':        [{'matcher': '*', 'command': '$HOOK_CLAUDE_SH'}],
    'PostToolUseFailure': [{'matcher': '*', 'command': '$HOOK_CLAUDE_SH'}],
    'Stop':               [{'matcher': '', 'command': '$HOOK_CLAUDE_SH'}],
    'SubagentStart':      [{'matcher': '', 'command': '$HOOK_CLAUDE_SH'}],
    'SubagentStop':       [{'matcher': '', 'command': '$HOOK_CLAUDE_SH'}],
    'PermissionRequest':  [{'matcher': '', 'command': '$HOOK_CLAUDE_SH'}],
}

settings = {}
if os.path.exists('$settings_file'):
    try:
        with open('$settings_file') as f:
            settings = json.load(f)
    except:
        pass

# 合并 hooks（保留用户已有的其他 hooks）
existing_hooks = settings.get('hooks', {})
for event, handlers in hooks_config.items():
    existing = existing_hooks.get(event, [])
    # 检查是否已配置了 agent-signal
    already_configured = any(
        'agent-signal-claude' in h.get('command', '') or
        'agent-signal' in h.get('command', '')
        for h in existing
    )
    if not already_configured:
        existing.extend(handlers)
    existing_hooks[event] = existing

settings['hooks'] = existing_hooks

with open('$settings_file', 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
"
    echo -e "  ${GREEN}✓${NC} Claude Code Hook 已配置 → ${settings_file}"
}

# ── Codex ───────────────────────────────────────────
configure_codex() {
    local hooks_file="$HOME/.codex/hooks.json"
    local backup="${hooks_file}.backup-$(date +%Y%m%d%H%M%S)"

    mkdir -p "$HOME/.codex"

    if [ -f "$hooks_file" ]; then
        cp "$hooks_file" "$backup"
        echo -e "  ${GREEN}✓${NC} 已备份: $backup"
    fi

    python3 -c "
import json, os

hooks_config = {
    'hooks': {
        'SessionStart':     [{'matcher': '', 'command': '$HOOK_CODEX_SH'}],
        'UserPromptSubmit': [{'matcher': '', 'command': '$HOOK_CODEX_SH'}],
        'PreToolUse':       [{'matcher': '*', 'command': '$HOOK_CODEX_SH'}],
        'PostToolUse':      [{'matcher': '*', 'command': '$HOOK_CODEX_SH'}],
        'Stop':             [{'matcher': '', 'command': '$HOOK_CODEX_SH'}],
    }
}

existing = {}
if os.path.exists('$hooks_file'):
    try:
        with open('$hooks_file') as f:
            existing = json.load(f)
    except:
        pass

# 合并
existing_hooks = existing.get('hooks', {})
for event, handlers in hooks_config['hooks'].items():
    e = existing_hooks.get(event, [])
    if not any('agent-signal-codex' in h.get('command','') for h in e):
        e.extend(handlers)
    existing_hooks[event] = e

existing['hooks'] = existing_hooks

with open('$hooks_file', 'w') as f:
    json.dump(existing, f, indent=2, ensure_ascii=False)
"
    echo -e "  ${GREEN}✓${NC} Codex Hook 已配置 → ${hooks_file}"
}

# ── Trae ────────────────────────────────────────────
configure_trae() {
    local trae_config_dir=""
    if [ -d "$HOME/Library/Application Support/Trae" ]; then
        trae_config_dir="$HOME/Library/Application Support/Trae"
    elif [ -d "$HOME/.trae" ]; then
        trae_config_dir="$HOME/.trae"
    fi

    if [ -z "$trae_config_dir" ]; then
        echo -e "  ${YELLOW}⚠${NC} 未找到 Trae 配置目录，请手动在 Trae 设置 > Hooks 中配置"
        echo -e "       Command: ${HOOK_TRAE_SH}"
        return
    fi

    local hooks_file="${trae_config_dir}/hooks.json"
    local backup="${hooks_file}.backup-$(date +%Y%m%d%H%M%S)"

    if [ -f "$hooks_file" ]; then
        cp "$hooks_file" "$backup"
    fi

    python3 -c "
import json, os

hook_entry = {
    'events': ['SessionStart', 'UserPromptSubmit', 'PreToolUse',
               'PostToolUse', 'Stop', 'Notification'],
    'command': '$HOOK_TRAE_SH'
}

config = []
if os.path.exists('$hooks_file'):
    try:
        with open('$hooks_file') as f:
            config = json.load(f)
    except:
        pass

# 检查是否已配置
if not any('agent-signal-trae' in h.get('command','') for h in config):
    config.append(hook_entry)

with open('$hooks_file', 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
"
    echo -e "  ${GREEN}✓${NC} Trae Hook 已配置 → ${hooks_file}"
}

# ── CodeBuddy ───────────────────────────────────────
configure_codebuddy() {
    local settings_file="$HOME/.codebuddy/settings.json"
    local backup="${settings_file}.backup-$(date +%Y%m%d%H%M%S)"

    mkdir -p "$HOME/.codebuddy"

    if [ -f "$settings_file" ]; then
        cp "$settings_file" "$backup"
        echo -e "  ${GREEN}✓${NC} 已备份: $backup"
    fi

    python3 -c "
import json, os

hooks_config = {
    'SessionStart':       [{'matcher': '', 'command': '$HOOK_CB_SH'}],
    'PreToolUse':         [{'matcher': '*', 'command': '$HOOK_CB_SH'}],
    'PostToolUse':        [{'matcher': '*', 'command': '$HOOK_CB_SH'}],
    'PostToolUseFailure': [{'matcher': '*', 'command': '$HOOK_CB_SH'}],
    'Stop':               [{'matcher': '', 'command': '$HOOK_CB_SH'}],
    'SubagentStop':       [{'matcher': '', 'command': '$HOOK_CB_SH'}],
}

settings = {}
if os.path.exists('$settings_file'):
    try:
        with open('$settings_file') as f:
            settings = json.load(f)
    except:
        pass

existing_hooks = settings.get('hooks', {})
for event, handlers in hooks_config.items():
    e = existing_hooks.get(event, [])
    if not any('agent-signal-codebuddy' in h.get('command','') for h in e):
        e.extend(handlers)
    existing_hooks[event] = e

settings['hooks'] = existing_hooks

with open('$settings_file', 'w') as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
"
    echo -e "  ${GREEN}✓${NC} CodeBuddy Hook 已配置 → ${settings_file}"
}

# ── WorkBuddy ───────────────────────────────────────
configure_workbuddy() {
    echo -e "  ${YELLOW}⚠${NC} WorkBuddy 请使用 WorkBuddy Harness 配置"
    echo -e "       Hook command: ${HOOK_WB_SH}"
}

# 执行配置
for agent in "${!AGENT_DETECTED[@]}"; do
    case "$agent" in
        "claude-code") configure_claude_code; CONFIGURED_COUNT=$((CONFIGURED_COUNT+1)) ;;
        "codex")       configure_codex;      CONFIGURED_COUNT=$((CONFIGURED_COUNT+1)) ;;
        "trae")        configure_trae;       CONFIGURED_COUNT=$((CONFIGURED_COUNT+1)) ;;
        "codebuddy")   configure_codebuddy;  CONFIGURED_COUNT=$((CONFIGURED_COUNT+1)) ;;
        "workbuddy")   configure_workbuddy;  CONFIGURED_COUNT=$((CONFIGURED_COUNT+1)) ;;
    esac
done

# ─────────────────────────────────────────────────────
# 4. 生成自启动配置
# ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[4/5]${NC} 配置开机自启..."

SERVER_SCRIPT="$INSTALL_DIR/agent_signal_server.py"

# macOS: launchd
if [[ "$(uname)" == "Darwin" ]]; then
    plist="$HOME/Library/LaunchAgents/com.agentsignal.bar.plist"
    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$plist" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.agentsignal.bar</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which python3)</string>
        <string>${SERVER_SCRIPT}</string>
        <string>--port</string>
        <string>${PORT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${INSTALL_DIR}/server.log</string>
    <key>StandardErrorPath</key>
    <string>${INSTALL_DIR}/server.log</string>
</dict>
</plist>
PLIST_EOF

    launchctl unload "$plist" 2>/dev/null || true
    launchctl load "$plist" 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} macOS 开机自启已配置 (launchd)"

# Linux: systemd
elif command -v systemctl &>/dev/null; then
    service_file="$HOME/.config/systemd/user/agent-signal-bar.service"
    mkdir -p "$HOME/.config/systemd/user"

    cat > "$service_file" << SERVICE_EOF
[Unit]
Description=Agent Signal Bar HTTP Server
After=network.target

[Service]
Type=simple
ExecStart=$(which python3) ${SERVER_SCRIPT} --port ${PORT}
Restart=always
RestartSec=5
StandardOutput=append:${INSTALL_DIR}/server.log
StandardError=append:${INSTALL_DIR}/server.log

[Install]
WantedBy=default.target
SERVICE_EOF

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable agent-signal-bar 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} Linux 开机自启已配置 (systemd)"
fi

# ─────────────────────────────────────────────────────
# 5. 启动服务
# ─────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[5/5]${NC} 启动 HTTP Server..."

# 杀掉旧进程
pkill -f "agent_signal_server.py" 2>/dev/null || true
sleep 1

# 启动
nohup python3 "$SERVER_SCRIPT" --port "$PORT" > "$INSTALL_DIR/server.log" 2>&1 &
SERVER_PID=$!
sleep 2

# 验证
if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} HTTP Server 已启动 (PID: $SERVER_PID, 端口: $PORT)"
else
    echo -e "  ${RED}✗${NC} 启动失败，请查看日志: ${INSTALL_DIR}/server.log"
    exit 1
fi

# ─────────────────────────────────────────────────────
# 完成信息
# ─────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════╗"
echo -e "  ║          ✅ 安装完成！                    ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}已配置的 Agent:${NC} ${CONFIGURED_COUNT} 个"
echo -e "  ${BOLD}HTTP Server:${NC}    http://0.0.0.0:${PORT}"
echo ""

# 获取本机 IP
if command -v ifconfig &>/dev/null; then
    LOCAL_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
elif command -v ip &>/dev/null; then
    LOCAL_IP=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -1)
else
    LOCAL_IP="<你的IP>"
fi

echo -e "  ${BOLD}📱 Android App 配置:${NC}"
echo -e "     IP:   ${GREEN}${LOCAL_IP}${NC}"
echo -e "     端口: ${GREEN}${PORT}${NC}"
echo ""
echo -e "  ${BOLD}🧪 验证:${NC}"
echo -e "     curl http://${LOCAL_IP}:${PORT}/health"
echo ""
echo -e "  ${YELLOW}配置文件已自动备份（.backup-*），可随时恢复${NC}"
