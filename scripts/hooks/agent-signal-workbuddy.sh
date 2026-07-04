#!/usr/bin/env bash
# ============================================================================
# Agent Signal Bar — WorkBuddy Hook 适配脚本
# ============================================================================
# WorkBuddy 通过 WorkBuddy Harness 的 Hook Runner 引擎实现 Hook 功能。
# 此脚本桥接 WorkBuddy Harness 事件到 Agent Signal Bar。
#
# 用法：
#   1. 安装 WorkBuddy Harness: https://github.com/zhuang-HE/workbuddy-harness
#   2. 在 WorkBuddy Harness hooks.json 中配置此脚本
#   3. 或使用 harness CLI 手动触发：
#      node engine/index.js hook trigger session_start session_id=test
#
# WorkBuddy Harness hooks.json 示例：
# {
#   "session_start": [{
#     "command": "/path/to/agent-signal-workbuddy.sh",
#     "args": ["session_start"]
#   }],
#   "tool_start": [{
#     "command": "/path/to/agent-signal-workbuddy.sh",
#     "args": ["tool_start"]
#   }],
#   "tool_end": [{
#     "command": "/path/to/agent-signal-workbuddy.sh",
#     "args": ["tool_end"]
#   }]
# }
# ============================================================================

set -euo pipefail

AGENT_NAME="${AGENT_SIGNAL_AGENT_NAME:-workbuddy}"
SIGNAL_CLI="${AGENT_SIGNAL_CLI:-agent-signal}"
STATE_DIR="${AGENT_SIGNAL_LIGHT_STATE_DIR:-${SIGNAL_LIGHT_STATE_DIR:-/tmp/agent-signal}}"
STATE_FILE="${AGENT_SIGNAL_LIGHT_STATE_FILE:-${STATE_DIR}/status.json}"

# 从参数或 stdin 获取事件类型
EVENT="${1:-}"

# 尝试从 stdin JSON 解析更多信息
SESSION_ID="global"
if [ -p /dev/stdin ] || [ ! -t 0 ]; then
    INPUT=$(cat 2>/dev/null || echo "{}")
    SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','global'))" 2>/dev/null || echo "global")
    # 如果参数为空，尝试从 stdin 获取事件
    if [ -z "$EVENT" ]; then
        EVENT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('event', d.get('action', d.get('hook_event_name',''))))" 2>/dev/null || echo "")
    fi
fi

case "$EVENT" in
    "session_start"|"SessionStart")
        SIGNAL="thinking"
        EVENT_LABEL="SessionStart"
        ;;
    "tool_start"|"PreToolUse"|"pre_tool_use")
        SIGNAL="working"
        EVENT_LABEL="ToolStart"
        ;;
    "tool_end"|"PostToolUse"|"post_tool_use")
        SIGNAL="tool_done"
        EVENT_LABEL="ToolEnd"
        ;;
    "tool_error"|"error"|"blocked")
        SIGNAL="blocked"
        EVENT_LABEL="Error"
        ;;
    "session_end"|"Stop"|"done"|"completed")
        SIGNAL="done"
        EVENT_LABEL="SessionEnd"
        ;;
    *)
        # 未知事件，跳过
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
