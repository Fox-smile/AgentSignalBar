#!/usr/bin/env bash
# ============================================================================
# Agent Signal Bar — Claude Code Hook 适配脚本
# ============================================================================
# 用法：在 Claude Code settings.json 中配置 Hook 调用此脚本。
#
# Claude Code 配置示例 (~/.claude/settings.json 或项目 .claude/settings.local.json):
# {
#   "hooks": {
#     "SessionStart":        [{"matcher": "", "command": "/path/to/agent-signal-claude.sh"}],
#     "PreToolUse":          [{"matcher": "*", "command": "/path/to/agent-signal-claude.sh"}],
#     "PostToolUse":         [{"matcher": "*", "command": "/path/to/agent-signal-claude.sh"}],
#     "PostToolUseFailure":  [{"matcher": "*", "command": "/path/to/agent-signal-claude.sh"}],
#     "Stop":                [{"matcher": "", "command": "/path/to/agent-signal-claude.sh"}],
#     "SubagentStart":       [{"matcher": "", "command": "/path/to/agent-signal-claude.sh"}],
#     "SubagentStop":        [{"matcher": "", "command": "/path/to/agent-signal-claude.sh"}],
#     "PermissionRequest":   [{"matcher": "", "command": "/path/to/agent-signal-claude.sh"}]
#   }
# }
# ============================================================================

set -euo pipefail

# ── 配置 ──────────────────────────────────────────────
AGENT_NAME="${AGENT_SIGNAL_AGENT_NAME:-claude-code}"
SIGNAL_CLI="${AGENT_SIGNAL_CLI:-agent-signal}"
# 如果 agent-signal CLI 不可用，直接写入 status.json
STATE_DIR="${AGENT_SIGNAL_LIGHT_STATE_DIR:-${SIGNAL_LIGHT_STATE_DIR:-/tmp/agent-signal}}"
STATE_FILE="${AGENT_SIGNAL_LIGHT_STATE_FILE:-${STATE_DIR}/status.json}"

# ── 读取 stdin JSON ──────────────────────────────────
INPUT=$(cat)
EVENT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('hook_event_name',''))" 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','global'))" 2>/dev/null || echo "global")
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")

# ── 事件 → 信号映射 ──────────────────────────────────
case "$EVENT" in
    "SessionStart")
        SIGNAL="thinking"
        EVENT_LABEL="SessionStart"
        ;;
    "PreToolUse")
        SIGNAL="working"
        EVENT_LABEL="$TOOL_NAME"
        ;;
    "PostToolUse")
        SIGNAL="tool_done"
        EVENT_LABEL="$TOOL_NAME"
        ;;
    "PostToolUseFailure")
        SIGNAL="blocked"
        EVENT_LABEL="${TOOL_NAME}_failure"
        ;;
    "Stop")
        SIGNAL="done"
        EVENT_LABEL="Stop"
        ;;
    "SubagentStart")
        SIGNAL="subagent_start"
        EVENT_LABEL="SubagentStart"
        ;;
    "SubagentStop")
        SIGNAL="subagent_stop"
        EVENT_LABEL="SubagentStop"
        ;;
    "PermissionRequest")
        SIGNAL="permission"
        EVENT_LABEL="PermissionRequest"
        ;;
    *)
        # 未知事件，不处理
        echo '{"continue": true}'
        exit 0
        ;;
esac

# ── 写入状态 ──────────────────────────────────────────
if command -v "$SIGNAL_CLI" &>/dev/null; then
    # 优先使用 agent-signal CLI（macOS 原项目自带）
    "$SIGNAL_CLI" "$SIGNAL" \
        --agent "$AGENT_NAME" \
        --session "$SESSION_ID" \
        --event "$EVENT_LABEL" \
        >/dev/null 2>&1 || true
else
    # 回退：直接写入 JSON 文件（简化版，适用于无 CLI 的环境）
    python3 -c "
import json, os, time, uuid
from pathlib import Path

state_file = '$STATE_FILE'
os.makedirs(os.path.dirname(state_file), exist_ok=True)

doc = {'schema_version': 1, 'aggregate': '$SIGNAL', 'sessions': {}, 'events': []}
try:
    with open(state_file) as f:
        doc = json.load(f)
except:
    pass

doc['aggregate'] = '$SIGNAL'
doc['updated_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
doc['sessions']['$SESSION_ID'] = {
    'agent': '$AGENT_NAME',
    'signal': '$SIGNAL',
    'last_event': '$EVENT_LABEL',
    'updated_at': doc['updated_at']
}

# 保留最近 20 条事件
events = doc.get('events', [])
events.append({
    'id': str(uuid.uuid4()),
    'session_id': '$SESSION_ID',
    'agent': '$AGENT_NAME',
    'signal': '$SIGNAL',
    'event': '$EVENT_LABEL',
    'updated_at': doc['updated_at']
})
doc['events'] = events[-20:]

with open(state_file, 'w') as f:
    json.dump(doc, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true
fi

# ── 始终返回 continue: true（不阻塞 Agent） ───────────
echo '{"continue": true}'
