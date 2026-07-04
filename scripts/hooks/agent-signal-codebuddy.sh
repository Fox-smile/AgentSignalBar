#!/usr/bin/env bash
# ============================================================================
# Agent Signal Bar — CodeBuddy (腾讯) Hook 适配脚本
# ============================================================================
# CodeBuddy 支持 9+ Hook 事件：SessionStart, UserPromptSubmit, PreToolUse,
# PostToolUse, PostToolUseFailure, Stop, SubagentStop, PreCompact, Notification 等。
#
# 用法：在 CodeBuddy settings.json 或 SDK hooks 配置中调用此脚本。
#
# CodeBuddy 配置示例：
# {
#   "hooks": {
#     "SessionStart":        [{"matcher": "", "command": "/path/to/agent-signal-codebuddy.sh"}],
#     "PreToolUse":          [{"matcher": "*", "command": "/path/to/agent-signal-codebuddy.sh"}],
#     "PostToolUse":         [{"matcher": "*", "command": "/path/to/agent-signal-codebuddy.sh"}],
#     "PostToolUseFailure":  [{"matcher": "*", "command": "/path/to/agent-signal-codebuddy.sh"}],
#     "Stop":                [{"matcher": "", "command": "/path/to/agent-signal-codebuddy.sh"}],
#     "SubagentStop":        [{"matcher": "", "command": "/path/to/agent-signal-codebuddy.sh"}],
#     "Notification":        [{"matcher": "", "command": "/path/to/agent-signal-codebuddy.sh"}]
#   }
# }
# ============================================================================

set -euo pipefail

# Windows Git Bash 里 python3 可能不存在，用 python 代替
if ! command -v python3 &>/dev/null; then
    alias python3=python
fi

AGENT_NAME="${AGENT_SIGNAL_AGENT_NAME:-codebuddy}"
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
    "PostToolUseFailure")
        SIGNAL="blocked"
        EVENT_LABEL="${TOOL_NAME}_failure"
        ;;
    "Stop")
        SIGNAL="done"
        EVENT_LABEL="Stop"
        ;;
    "SubagentStop")
        SIGNAL="subagent_stop"
        EVENT_LABEL="SubagentStop"
        ;;
    "Notification")
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
