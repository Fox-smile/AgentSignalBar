#!/usr/bin/env bash
# ============================================================================
# Agent Signal Bar — Codex (OpenAI) Hook 适配脚本
# ============================================================================
# 用法：在 Codex hooks.json 中配置 Hook 调用此脚本。
#
# Codex 配置示例 (~/.codex/hooks.json):
# {
#   "hooks": {
#     "SessionStart":       [{"matcher": "", "command": "/path/to/agent-signal-codex.sh"}],
#     "UserPromptSubmit":   [{"matcher": "", "command": "/path/to/agent-signal-codex.sh"}],
#     "PreToolUse":         [{"matcher": "*", "command": "/path/to/agent-signal-codex.sh"}],
#     "PostToolUse":        [{"matcher": "*", "command": "/path/to/agent-signal-codex.sh"}],
#     "Stop":               [{"matcher": "", "command": "/path/to/agent-signal-codex.sh"}]
#   }
# }
# ============================================================================

set -euo pipefail

AGENT_NAME="${AGENT_SIGNAL_AGENT_NAME:-codex}"
SIGNAL_CLI="${AGENT_SIGNAL_CLI:-agent-signal}"
STATE_DIR="${AGENT_SIGNAL_LIGHT_STATE_DIR:-${SIGNAL_LIGHT_STATE_DIR:-/tmp/agent-signal}}"
STATE_FILE="${AGENT_SIGNAL_LIGHT_STATE_FILE:-${STATE_DIR}/status.json}"

INPUT=$(cat)
EVENT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('hook_event_name',''))" 2>/dev/null || echo "")
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','global'))" 2>/dev/null || echo "global")
TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name','Bash'))" 2>/dev/null || echo "Bash")

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
        # 检查工具执行结果
        EXIT_CODE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('tool_response',{}); print(r.get('exit_code','0'))" 2>/dev/null || echo "0")
        if [ "$EXIT_CODE" != "0" ]; then
            SIGNAL="blocked"
            EVENT_LABEL="${TOOL_NAME}_exit_${EXIT_CODE}"
        else
            SIGNAL="tool_done"
            EVENT_LABEL="$TOOL_NAME"
        fi
        ;;
    "Stop")
        SIGNAL="done"
        EVENT_LABEL="Stop"
        ;;
    *)
        echo '{"continue": true}'
        exit 0
        ;;
esac

# 写入状态（与 Claude 脚本相同逻辑）
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
