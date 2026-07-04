#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Agent Signal Bar — CodeBuddy Hook 适配脚本 (Python 版，跨平台)
====================================================================
此脚本是 agent-signal-codebuddy.sh 的 Python 实现，无需 bash，可在
Windows / macOS / Linux 上直接运行。

用法：在 CodeBuddy settings.json hooks 配置中直接指向此 .py 文件即可。
CodeBuddy 会将 Hook 事件 JSON 写入 stdin，此脚本读取后更新 status.json。

CodeBuddy settings.json 配置示例：
{
  "hooks": {
    "SessionStart":       [{"matcher": "", "command": "C:\\Users\\QL\\.agent-signal\\hooks\\agent-signal-codebuddy.py"}],
    "PreToolUse":         [{"matcher": "*", "command": "C:\\Users\\QL\\.agent-signal\\hooks\\agent-signal-codebuddy.py"}],
    "PostToolUse":        [{"matcher": "*", "command": "C:\\Users\\QL\\.agent-signal\\hooks\\agent-signal-codebuddy.py"}],
    "PostToolUseFailure": [{"matcher": "*", "command": "C:\\Users\\QL\\.agent-signal\\hooks\\agent-signal-codebuddy.py"}],
    "Stop":               [{"matcher": "", "command": "C:\\Users\\QL\\.agent-signal\\hooks\\agent-signal-codebuddy.py"}],
    "SubagentStop":       [{"matcher": "", "command": "C:\\Users\\QL\\.agent-signal\\hooks\\agent-signal-codebuddy.py"}]
  }
}
"""

import json
import os
import sys
import time
import uuid
from pathlib import Path

# ── 配置 ──────────────────────────────────────────────

AGENT_NAME = os.environ.get("AGENT_SIGNAL_AGENT_NAME", "codebuddy")

# 状态文件路径（与 agent_signal_server.py 一致）
_state_dir = os.environ.get("AGENT_SIGNAL_LIGHT_STATE_DIR",
                           os.environ.get("SIGNAL_LIGHT_STATE_DIR", None))
if _state_dir is None:
    if os.name == "nt":  # Windows
        _state_dir = os.path.join(os.environ.get("USERPROFILE", "C:\\"), ".agent-signal")
    else:
        _state_dir = "/tmp/agent-signal"

STATE_FILE = os.environ.get(
    "AGENT_SIGNAL_LIGHT_STATE_FILE",
    os.path.join(_state_dir, "status.json")
)

# ── 事件 → 信号映射 ──────────────────────────────────

EVENT_SIGNAL_MAP = {
    "SessionStart":       "thinking",
    "UserPromptSubmit":   "thinking",
    "PreToolUse":         "working",
    "PostToolUse":        "tool_done",
    "PostToolUseFailure": "blocked",
    "Stop":               "done",
    "SubagentStop":       "subagent_stop",
    "Notification":       None,   # 特殊：直接放行
}


def read_status() -> dict:
    """读取现有 status.json，失败则返回空结构。"""
    empty = {
        "schema_version": "1.0",
        "aggregate": "idle",
        "updated_at": None,
        "sessions": {},
        "events": [],
    }
    try:
        p = Path(STATE_FILE)
        if p.exists():
            with open(p, "r", encoding="utf-8") as f:
                doc = json.load(f)
                # 确保所有字段存在
                for k, v in empty.items():
                    doc.setdefault(k, v)
                return doc
    except Exception:
        pass
    return dict(empty)


def write_status(doc: dict):
    """将 doc 写回 status.json。"""
    Path(STATE_FILE).parent.mkdir(parents=True, exist_ok=True)
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)


def main():
    # 读取 CodeBuddy 传入的 Hook 事件 JSON（通过 stdin）
    try:
        raw = sys.stdin.read()
        data = json.loads(raw) if raw.strip() else {}
    except Exception:
        data = {}

    event = data.get("hook_event_name", "")
    session_id = data.get("session_id", "global")
    tool_name = data.get("tool_name", "")

    signal = EVENT_SIGNAL_MAP.get(event)

    # Notification 事件：直接放行，不修改状态
    if signal is None and event == "Notification":
        print(json.dumps({"continue": True}))
        sys.exit(0)

    # 未知事件：放行
    if signal is None:
        print(json.dumps({"continue": True}))
        sys.exit(0)

    # 事件标签（用于 sessions 详情）
    if event in ("PreToolUse", "PostToolUse", "PostToolUseFailure"):
        event_label = tool_name or event
    else:
        event_label = event

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    doc = read_status()
    doc["aggregate"] = signal
    doc["updated_at"] = now

    # 更新 session 记录
    sess = doc.get("sessions", {})
    sess[session_id] = {
        "agent": AGENT_NAME,
        "signal": signal,
        "last_event": event_label,
        "updated_at": now,
    }
    doc["sessions"] = sess

    # 追加事件记录（最多保留 20 条）
    evts = doc.get("events", [])
    evts.append({
        "id": str(uuid.uuid4()),
        "session_id": session_id,
        "agent": AGENT_NAME,
        "signal": signal,
        "event": event_label,
        "updated_at": now,
    })
    doc["events"] = evts[-20:]

    write_status(doc)

    # 输出 continue 信号给 CodeBuddy
    print(json.dumps({"continue": True}))


if __name__ == "__main__":
    main()
