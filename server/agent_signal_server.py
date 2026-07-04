#!/usr/bin/env python3
"""
Agent Signal Bar — HTTP Server
================================
轻量级 HTTP 服务器，将 macOS/Linux/Windows 电脑上的 Agent 状态暴露给 Android 手机。

用法：
    python3 agent_signal_server.py              # 默认端口 9120
    python3 agent_signal_server.py --port 8080   # 自定义端口

端点：
    GET /api/status   — 返回状态 JSON
    GET /status.json  — 同上（兼容路径）
    GET /health       — 健康检查
    GET /             — 状态面板页面

依赖：Python 3.6+，仅使用标准库，零 pip 依赖。
"""

import json
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

DEFAULT_PORT = 9120

# 根据系统自动选择默认状态文件目录
_default_state_dir = os.environ.get(
    "AGENT_SIGNAL_LIGHT_STATE_DIR",
    os.environ.get("SIGNAL_LIGHT_STATE_DIR", None)
)
if _default_state_dir is None:
    if os.name == "nt":  # Windows
        _default_state_dir = os.path.join(os.environ.get("USERPROFILE", "C:\\"), ".agent-signal")
    else:
        _default_state_dir = "/tmp/agent-signal"

STATE_FILE = os.environ.get(
    "AGENT_SIGNAL_LIGHT_STATE_FILE",
    os.path.join(_default_state_dir, "status.json")
)

STATUS_PAGE_HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Agent Signal Bar</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: #1a1a2e; color: #eee; min-height: 100vh;
            display: flex; justify-content: center; align-items: center;
        }
        .card {
            background: #16213e; border-radius: 20px; padding: 40px;
            text-align: center; max-width: 360px; width: 90%;
            box-shadow: 0 20px 60px rgba(0,0,0,0.5);
        }
        .dot {
            width: 80px; height: 80px; border-radius: 50%; margin: 0 auto 20px;
            transition: background 0.3s;
        }
        .dot.ready   { background: #4CAF50; box-shadow: 0 0 30px rgba(76,175,80,0.5); }
        .dot.active  { background: #FF9800; box-shadow: 0 0 30px rgba(255,152,0,0.5); animation: pulse 1s infinite; }
        .dot.blocked { background: #F44336; box-shadow: 0 0 30px rgba(244,67,54,0.5); animation: blink 0.5s infinite; }
        .dot.paused { background: #9E9E9E; box-shadow: 0 0 30px rgba(158,158,158,0.3); }
        .dot.unknown { background: #607D8B; }
        @keyframes pulse { 0%,100% { transform: scale(1); } 50% { transform: scale(1.1); } }
        @keyframes blink { 0%,100% { opacity: 1; } 50% { opacity: 0.3; } }
        h1 { font-size: 28px; margin-bottom: 8px; }
        .subtitle { color: #aaa; font-size: 14px; margin-bottom: 16px; }
        .info { background: #0f3460; border-radius: 12px; padding: 16px; margin-top: 20px; text-align: left; }
        .info .label { color: #aaa; font-size: 12px; text-transform: uppercase; }
        .info .value { font-size: 14px; margin-bottom: 8px; word-break: break-all; }
        .sessions { margin-top: 8px; }
        .session { background: rgba(255,255,255,0.05); border-radius: 8px; padding: 8px 12px; margin-bottom: 6px; font-size: 12px; }
    </style>
</head>
<body>
    <div class="card">
        <div class="dot {css_class}"></div>
        <h1>{display_name}</h1>
        <p class="subtitle">{summary}</p>
        <div class="info">
            <div class="label">状态文件</div>
            <div class="value">{state_file}</div>
            <div class="label">最后更新</div>
            <div class="value">{updated_at}</div>
            <div class="sessions">{sessions_html}</div>
        </div>
    </div>
    <script>setTimeout(() => location.reload(), 3000);</script>
</body>
</html>"""

def get_display_name(aggregate):
    if aggregate is None: return "未知"
    return {
        "idle":"空闲","ready":"空闲","thinking":"思考中","working":"工作中",
        "tool_done":"步骤完成","subagent_start":"子Agent运行中","active":"工作中",
        "done":"已完成","completed":"已完成","attention":"需要查看",
        "permission":"等待授权","permission_request":"等待授权",
        "blocked":"阻塞/失败","failure":"失败","error":"错误",
        "off":"已关闭","pause":"已暂停","paused":"已暂停",
    }.get(aggregate, aggregate)

def get_css_class(aggregate):
    if aggregate is None: return "unknown"
    if aggregate in ("idle","ready","done","completed","session_start","session_end","turn_end"): return "ready"
    if aggregate in ("thinking","working","tool_done","subagent_start","subagent_stop","active"): return "active"
    if aggregate in ("blocked","failure","error","exception","max_tokens","stale","permission","permission_request"): return "blocked"
    if aggregate in ("off","pause","paused"): return "paused"
    return "unknown"

def read_status():
    try:
        path = Path(STATE_FILE)
        if not path.exists(): return None
        with open(path, "r") as f: return json.load(f)
    except: return None

class SignalHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print(f"[{self.client_address[0]}] {args[0]}")

    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))

    def _send_html(self, html, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(html.encode("utf-8"))

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

    def do_GET(self):
        path = self.path.split("?")[0]

        if path in ("/api/status", "/status.json"):
            doc = read_status()
            if doc is None:
                self._send_json({"schema_version":1,"aggregate":"idle","updated_at":None,"sessions":{},"events":[]})
            else:
                self._send_json(doc)

        elif path == "/health":
            doc = read_status()
            self._send_json({"status":"ok","state_file":STATE_FILE,"state_file_exists":doc is not None,"aggregate":doc.get("aggregate") if doc else None})

        elif path == "/":
            doc = read_status()
            aggregate = doc.get("aggregate") if doc else None
            sessions = doc.get("sessions",{}) if doc else {}
            updated_at = doc.get("updated_at","N/A") if doc else "N/A"
            sessions_html = ""
            for sid, rec in sessions.items():
                sessions_html += f'<div class="session"><strong>{rec.get("agent","?")}</strong>: {rec.get("signal","?")}</div>'
            if not sessions_html:
                sessions_html = '<div style="color:#aaa;font-size:12px;">无活跃会话</div>'
            html = STATUS_PAGE_HTML.format(
                css_class=get_css_class(aggregate),
                display_name=get_display_name(aggregate),
                summary=f"状态文件: {STATE_FILE}",
                state_file=STATE_FILE,
                updated_at=str(updated_at),
                sessions_html=sessions_html
            )
            self._send_html(html)

        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")

def main():
    port = int(sys.argv[2]) if len(sys.argv)>2 and sys.argv[1]=="--port" else DEFAULT_PORT
    server = HTTPServer(("0.0.0.0", port), SignalHandler)
    print("=" * 56)
    print("  🚦 Agent Signal Bar — HTTP Server")
    print("=" * 56)
    print(f"  监听地址:  http://0.0.0.0:{port}")
    print(f"  状态文件:  {STATE_FILE}")
    print(f"  状态接口:  http://<你的IP>:{port}/api/status")
    print(f"  健康检查:  http://<你的IP>:{port}/health")
    print(f"  状态面板:  http://<你的IP>:{port}/")
    print("  按 Ctrl+C 停止服务器。")
    print("=" * 56)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n服务器已停止。")

if __name__ == "__main__":
    main()
