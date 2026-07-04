#!/usr/bin/env bash
# ============================================================================
# Agent Signal Bar — Trae IDE Hook 适配脚本
# ============================================================================
# Trae 支持六类 Hook 事件：SessionStart, UserPromptSubmit, PreToolUse,
# PostToolUse, Stop, Notification。
#
# 用法：在 Trae 设置 > Hooks 中创建 Hook 配置文件，调用此脚本。
#
# Trae hooks.json 示例：
# [
#   {
#     "events": ["SessionStart", "UserPromptSubmit", "PreToolUse",
#                "PostToolUse", "Stop", "Notification"],
#     "command": "/path/to/agent-signal-trae.sh"
#   }
# ]
# ============================================================================

set -euo pipefail

AGENT_NAME="${AGENT_SIGNAL_AGENT_NAME:-trae}"
SIGNAL_CLI="${AGENT_SIGNAL_CLI:-agent-signal}"
STATE_DIR="${AGENT_SIGNAL_LIGHT_STATE_DIR:-${SIGNAL_LIGHT_STATE_DIR:-/tmp/agent-signal}}"
STATE_FILE="${AGENT_SIGNAL_LIGHT_STATE_FILE:-${STATE_DIR}/status.json}"

INPUT=$(cat)
EVENT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('hook_event_name',''))" 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','global'))" 2>/dev/null || echo "global")
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name',''))" 2>/dev/null || echo "")

case "$EVENT" in
    "SessionStart")
        SIGNAL="thinking"
        EVENT_LABEL="SessionStart"
        ;;
    "UserPromptSubmit")
        SIGNAL="thinking"
        EVENT_LABEL="UserPrompt"
        ;;
    "PreToolUse")
        SIGNAL="working"
        EVENT_LABEL="$TOOL_NAME"
        ;;
    "PostToolUse")
        SIGNAL="tool_done"
        EVENT_LABEL="$TOOL_NAME"
        ;;
    "Stop")
        SIGNAL="done"
        EVENT_LABEL="Stop"
        ;;
    "Notification")
        # Notification 是异步事件，不改变核心状态，只记录
        echo '{"continue": true}'
        exit 0
        ;;
    *)
        echo '{"continue": true}'
        exit 0
        ;;
esac

if command -v "$SIGNAL_CLI" &>/dev/null; then
    "$SIGNAL_CLI" "$SIGNAL" \
        --agent "$AGENT_NAME" \
        --session "$SESSION_ID" \
        --event "$EVENT_LABEL" \
        >/dev/null 2>&1 || true
else
    python3 -c "
import json, os, time, uuid
os.makedirs(os.path.dirname('$STATE_FILE'), exist_ok=True)
doc = {'schema_version': 1, 'aggregate': '$SIGNAL', 'sessions': {}, 'events': []}
try:
    with open('$STATE_FILE') as f:
        doc = json.load(f)
except: pass
doc['aggregate'] = '$SIGNAL'
doc['updated_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
doc['sessions']['$SESSION_ID'] = {
    'agent': '$AGENT_NAME', 'signal': '$SIGNAL',
    'last_event': '$EVENT_LABEL', 'updated_at': doc['updated_at']
}
events = doc.get('events', [])
events.append({
    'id': str(uuid.uuid4()), 'session_id': '$SESSION_ID',
    'agent': '$AGENT_NAME', 'signal': '$SIGNAL',
    'event': '$EVENT_LABEL', 'updated_at': doc['updated_at']
})
doc['events'] = events[-20:]
with open('$STATE_FILE', 'w') as f:
    json.dump(doc, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true
fi

echo '{"continue": true}'
