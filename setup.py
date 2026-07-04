#!/usr/bin/env python3
"""
Agent Signal Bar — 跨平台一键安装脚本
======================================
支持 Windows / macOS / Linux，自动检测 Agent 并配置 Hook。

用法：
    python3 setup.py
    python3 setup.py --port 8080
    python3 setup.py --no-autostart

Windows 用户也可以用 PowerShell 一键执行：
    Invoke-WebRequest -Uri "<url>/setup.py" | python3 -
"""

import json
import os
import sys
import shutil
import subprocess
import platform
import tempfile
from pathlib import Path
from datetime import datetime

# ── 配置 ──────────────────────────────────────────────

PORT = 9120
INSTALL_DIR = Path.home() / ".agent-signal"
HOOKS_DIR = INSTALL_DIR / "hooks"
SCRIPT_DIR = Path(__file__).resolve().parent
IS_WINDOWS = platform.system() == "Windows"
IS_MACOS = platform.system() == "Darwin"
IS_LINUX = platform.system() == "Linux"

# ── 颜色输出 ──────────────────────────────────────────

class Colors:
    GREEN = "" if IS_WINDOWS else "\033[0;32m"
    YELLOW = "" if IS_WINDOWS else "\033[1;33m"
    CYAN = "" if IS_WINDOWS else "\033[0;36m"
    RED = "" if IS_WINDOWS else "\033[0;31m"
    BOLD = "" if IS_WINDOWS else "\033[1m"
    NC = "" if IS_WINDOWS else "\033[0m"

def ok(msg):
    print(f"  {Colors.GREEN}✓{Colors.NC} {msg}")

def warn(msg):
    print(f"  {Colors.YELLOW}⚠{Colors.NC} {msg}")

def info(msg):
    print(f"  {Colors.CYAN}→{Colors.NC} {msg}")

def err(msg):
    print(f"  {Colors.RED}✗{Colors.NC} {msg}")

# ── Agent 配置路径定义 ────────────────────────────────

def get_agent_configs():
    """返回每个 Agent 的配置路径（跨平台）。"""
    home = Path.home()
    configs = {}

    # Claude Code
    claude_configs = [
        home / ".claude" / "settings.json",                          # macOS/Linux
        Path(os.environ.get("APPDATA", "")) / "Claude" / "settings.json" if IS_WINDOWS else None,
    ]
    for p in claude_configs:
        if p and p.parent.exists():
            configs["claude-code"] = {"settings": p, "type": "claude-code"}
            break
    else:
        if (home / ".claude").exists():
            configs["claude-code"] = {"settings": home / ".claude" / "settings.json", "type": "claude-code"}

    # Codex
    codex_dirs = [
        home / ".codex",
        Path(os.environ.get("APPDATA", "")) / "codex" if IS_WINDOWS else None,
    ]
    for d in codex_dirs:
        if d and d.exists():
            configs["codex"] = {"settings": d / "hooks.json", "type": "codex"}
            break
    else:
        if (home / ".codex").exists() or shutil.which("codex"):
            configs["codex"] = {"settings": home / ".codex" / "hooks.json", "type": "codex"}

    # Trae
    trae_dirs = [
        home / "Library" / "Application Support" / "Trae",           # macOS
        home / ".trae",                                               # Linux
        Path(os.environ.get("APPDATA", "")) / "Trae" if IS_WINDOWS else None,
    ]
    for d in trae_dirs:
        if d and d.exists():
            configs["trae"] = {"settings": d / "hooks.json", "type": "trae"}
            break

    # CodeBuddy
    cb_dirs = [
        home / ".codebuddy",                                         # macOS/Linux
        Path(os.environ.get("USERPROFILE", "")) / ".codebuddy" if IS_WINDOWS else None,
    ]
    for d in cb_dirs:
        if d and d.exists():
            configs["codebuddy"] = {"settings": d / "settings.json", "type": "codebuddy"}
            break
    else:
        if shutil.which("codebuddy"):
            configs["codebuddy"] = {"settings": home / ".codebuddy" / "settings.json", "type": "codebuddy"}

    # WorkBuddy
    if (home / ".workbuddy").exists():
        configs["workbuddy"] = {"settings": home / ".workbuddy" / "hooks.json", "type": "workbuddy"}

    return configs


# ── Hook 配置模板 ─────────────────────────────────────

def get_hook_config(agent_type, hook_script_path):
    """返回每个 Agent 的 Hook 配置。"""
    if agent_type == "claude-code":
        return {
            "SessionStart":       [{"matcher": "", "command": hook_script_path}],
            "PreToolUse":         [{"matcher": "*", "command": hook_script_path}],
            "PostToolUse":        [{"matcher": "*", "command": hook_script_path}],
            "PostToolUseFailure": [{"matcher": "*", "command": hook_script_path}],
            "Stop":               [{"matcher": "", "command": hook_script_path}],
            "SubagentStart":      [{"matcher": "", "command": hook_script_path}],
            "SubagentStop":       [{"matcher": "", "command": hook_script_path}],
            "PermissionRequest":  [{"matcher": "", "command": hook_script_path}],
        }
    elif agent_type == "codex":
        return {
            "hooks": {
                "SessionStart":     [{"matcher": "", "command": hook_script_path}],
                "UserPromptSubmit": [{"matcher": "", "command": hook_script_path}],
                "PreToolUse":       [{"matcher": "*", "command": hook_script_path}],
                "PostToolUse":      [{"matcher": "*", "command": hook_script_path}],
                "Stop":             [{"matcher": "", "command": hook_script_path}],
            }
        }
    elif agent_type == "trae":
        return [{
            "events": ["SessionStart", "UserPromptSubmit", "PreToolUse",
                       "PostToolUse", "Stop", "Notification"],
            "command": hook_script_path
        }]
    elif agent_type == "codebuddy":
        return {
            "SessionStart":       [{"matcher": "", "command": hook_script_path}],
            "PreToolUse":         [{"matcher": "*", "command": hook_script_path}],
            "PostToolUse":        [{"matcher": "*", "command": hook_script_path}],
            "PostToolUseFailure": [{"matcher": "*", "command": hook_script_path}],
            "Stop":               [{"matcher": "", "command": hook_script_path}],
            "SubagentStop":       [{"matcher": "", "command": hook_script_path}],
        }
    elif agent_type == "workbuddy":
        return {"hooks": {"agent_signal": {"command": hook_script_path}}}
    return {}


def apply_hook_config(settings_file, agent_type, hook_script_path, is_windows):
    """修改配置文件，注入 Hook 配置。返回是否成功。"""
    try:
        settings_file.parent.mkdir(parents=True, exist_ok=True)

        # 备份原文件
        if settings_file.exists():
            backup = settings_file.with_suffix(f".backup-{datetime.now().strftime('%Y%m%d%H%M%S')}")
            shutil.copy2(settings_file, backup)
            ok(f"已备份: {backup}")

        # 读取现有配置
        existing = {}
        if settings_file.exists():
            try:
                with open(settings_file) as f:
                    existing = json.load(f)
            except json.JSONDecodeError:
                existing = {}

        # 获取新 Hook 配置
        new_hooks = get_hook_config(agent_type, hook_script_path)

        # 合并 hooks（保留用户已有的其他 hooks）
        if agent_type == "codex":
            existing_hooks = existing.get("hooks", {})
            for event, handlers in new_hooks.get("hooks", {}).items():
                e = existing_hooks.get(event, [])
                if not any("agent-signal" in str(h.get("command", "")) for h in e):
                    e.extend(handlers)
                existing_hooks[event] = e
            existing["hooks"] = existing_hooks
        elif agent_type == "trae":
            # Trae 是数组格式
            if not isinstance(existing, list):
                existing = []
            if not any("agent-signal-trae" in str(h.get("command", "")) for h in existing):
                existing.extend(new_hooks)
        elif agent_type == "workbuddy":
            existing_hooks = existing.get("hooks", {})
            existing_hooks.update(new_hooks.get("hooks", {}))
            existing["hooks"] = existing_hooks
        else:
            # Claude Code / CodeBuddy: hooks 在顶层
            existing_hooks = existing.get("hooks", {})
            for event, handlers in new_hooks.items():
                e = existing_hooks.get(event, [])
                if not any("agent-signal" in str(h.get("command", "")) for h in e):
                    e.extend(handlers)
                existing_hooks[event] = e
            existing["hooks"] = existing_hooks

        # 写入
        with open(settings_file, "w") as f:
            json.dump(existing, f, indent=2, ensure_ascii=False)

        ok(f"{agent_type} Hook 已配置 → {settings_file}")
        return True

    except Exception as e:
        err(f"{agent_type} 配置失败: {e}")
        return False


# ── 自启动配置 ────────────────────────────────────────

def configure_autostart(server_script, port):
    """配置开机自启。"""
    if IS_MACOS:
        plist = Path.home() / "Library" / "LaunchAgents" / "com.agentsignal.bar.plist"
        plist.parent.mkdir(parents=True, exist_ok=True)

        python_path = shutil.which("python3") or shutil.which("python") or "/usr/bin/python3"
        plist_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.agentsignal.bar</string>
    <key>ProgramArguments</key>
    <array>
        <string>{python_path}</string>
        <string>{server_script}</string>
        <string>--port</string>
        <string>{port}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>{INSTALL_DIR}/server.log</string>
    <key>StandardErrorPath</key>
    <string>{INSTALL_DIR}/server.log</string>
</dict>
</plist>"""
        with open(plist, "w") as f:
            f.write(plist_content)
        subprocess.run(["launchctl", "unload", str(plist)], capture_output=True)
        subprocess.run(["launchctl", "load", str(plist)], capture_output=True)
        ok("macOS 开机自启已配置 (launchd)")

    elif IS_LINUX:
        service_dir = Path.home() / ".config" / "systemd" / "user"
        service_dir.mkdir(parents=True, exist_ok=True)
        service_file = service_dir / "agent-signal-bar.service"

        python_path = shutil.which("python3") or shutil.which("python") or "/usr/bin/python3"
        service_content = f"""[Unit]
Description=Agent Signal Bar HTTP Server
After=network.target

[Service]
Type=simple
ExecStart={python_path} {server_script} --port {port}
Restart=always
RestartSec=5
StandardOutput=append:{INSTALL_DIR}/server.log
StandardError=append:{INSTALL_DIR}/server.log

[Install]
WantedBy=default.target"""
        with open(service_file, "w") as f:
            f.write(service_content)
        subprocess.run(["systemctl", "--user", "daemon-reload"], capture_output=True)
        subprocess.run(["systemctl", "--user", "enable", "agent-signal-bar"], capture_output=True)
        ok("Linux 开机自启已配置 (systemd)")

    elif IS_WINDOWS:
        # Windows: 创建启动文件夹快捷方式或计划任务
        startup_dir = Path(os.environ.get("APPDATA", "")) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Startup"
        startup_dir.mkdir(parents=True, exist_ok=True)

        python_path = shutil.which("python") or shutil.which("python3") or "python"
        vbs_path = startup_dir / "AgentSignalBar.vbs"
        vbs_content = f'''Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "{python_path} {server_script} --port {port}", 0, False'''
        with open(vbs_path, "w") as f:
            f.write(vbs_content)
        ok(f"Windows 开机自启已配置 (启动文件夹 VBS)")

        # 备用：注册表 Run 键
        try:
            import winreg
            key = winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                r"Software\Microsoft\Windows\CurrentVersion\Run",
                0, winreg.KEY_SET_VALUE
            )
            winreg.SetValueEx(key, "AgentSignalBar", 0, winreg.REG_SZ,
                            f'"{python_path}" "{server_script}" --port {port}')
            winreg.CloseKey(key)
            ok("Windows 注册表自启已配置")
        except Exception:
            pass


# ── 启动服务 ──────────────────────────────────────────

def start_server(server_script, port):
    """启动 HTTP Server。"""
    # 杀掉旧进程
    if IS_WINDOWS:
        subprocess.run(["taskkill", "/F", "/IM", "python.exe", "/FI",
                       "WINDOWTITLE eq AgentSignalBar"], capture_output=True)
    else:
        subprocess.run(["pkill", "-f", "agent_signal_server.py"], capture_output=True)

    log_file = INSTALL_DIR / "server.log"
    python_path = shutil.which("python3") or shutil.which("python") or "python"

    if IS_WINDOWS:
        # Windows: 使用 pythonw 无窗口运行
        pythonw = python_path.replace("python.exe", "pythonw.exe")
        if os.path.exists(pythonw):
            python_path = pythonw
        subprocess.Popen(
            [python_path, str(server_script), "--port", str(port)],
            creationflags=subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0,
            stdout=open(log_file, "a"), stderr=subprocess.STDOUT
        )
    else:
        subprocess.Popen(
            [python_path, str(server_script), "--port", str(port)],
            stdout=open(log_file, "a"), stderr=subprocess.STDOUT,
            start_new_session=True
        )

    ok(f"HTTP Server 已启动 (端口: {port})")


# ── 主流程 ────────────────────────────────────────────

def main():
    global PORT

    # 解析参数
    args = sys.argv[1:]
    skip_autostart = "--no-autostart" in args
    for i, arg in enumerate(args):
        if arg == "--port" and i + 1 < len(args):
            PORT = int(args[i + 1])

    print(f"\n{Colors.CYAN}{Colors.BOLD}")
    print("  ╔══════════════════════════════════════════╗")
    print("  ║     🚦 Agent Signal Bar — 一键安装      ║")
    print("  ╚══════════════════════════════════════════╝")
    print(f"{Colors.NC}")
    print(f"  平台: {platform.system()} {platform.release()}")
    print(f"  端口: {PORT}")
    print()

    # ── Step 1: 安装文件 ──
    print(f"{Colors.BOLD}[1/5]{Colors.NC} 安装适配脚本...")
    HOOKS_DIR.mkdir(parents=True, exist_ok=True)

    hook_scripts = {
        "claude-code": "agent-signal-claude.sh",
        "codex": "agent-signal-codex.sh",
        "trae": "agent-signal-trae.sh",
        "codebuddy": "agent-signal-codebuddy.sh",
        "workbuddy": "agent-signal-workbuddy.sh",
    }

    for name, filename in hook_scripts.items():
        src = SCRIPT_DIR / "scripts" / "hooks" / filename
        dst = HOOKS_DIR / filename
        if src.exists():
            shutil.copy2(src, dst)
            if not IS_WINDOWS:
                dst.chmod(0o755)

    server_src = SCRIPT_DIR / "server" / "agent_signal_server.py"
    server_dst = INSTALL_DIR / "agent_signal_server.py"
    shutil.copy2(server_src, server_dst)
    ok(f"脚本已安装到 {HOOKS_DIR}")

    # ── Step 2: 检测 Agent ──
    print(f"\n{Colors.BOLD}[2/5]{Colors.NC} 检测 Agent...")
    agent_configs = get_agent_configs()

    if not agent_configs:
        warn("未检测到已知 Agent")
        # 仍然检测常见目录
        for name in ["claude-code", "codebuddy"]:
            agent_configs[name] = {"settings": Path.home() / f".{name.replace('-','')}" / "settings.json",
                                   "type": name}
    else:
        for name in agent_configs:
            ok(f"{name}")

    # ── Step 3: 配置 Hook ──
    print(f"\n{Colors.BOLD}[3/5]{Colors.NC} 自动配置 Agent Hook...")
    configured = 0

    for name, cfg in agent_configs.items():
        hook_file = hook_scripts.get(name)
        if not hook_file:
            continue
        hook_path = HOOKS_DIR / hook_file
        if apply_hook_config(cfg["settings"], name, str(hook_path), IS_WINDOWS):
            configured += 1

    # ── Step 4: 自启动 ──
    print(f"\n{Colors.BOLD}[4/5]{Colors.NC} 配置开机自启...")
    if skip_autostart:
        warn("已跳过（--no-autostart）")
    else:
        configure_autostart(server_dst, PORT)

    # ── Step 5: 启动 ──
    print(f"\n{Colors.BOLD}[5/5]{Colors.NC} 启动 HTTP Server...")
    start_server(server_dst, PORT)

    # ── 完成 ──
    print(f"\n{Colors.CYAN}{Colors.BOLD}")
    print("  ╔══════════════════════════════════════════╗")
    print("  ║          ✅ 安装完成！                    ║")
    print("  ╚══════════════════════════════════════════╝")
    print(f"{Colors.NC}")
    print(f"  已配置 Agent: {configured} 个")
    print(f"  HTTP Server:  http://0.0.0.0:{PORT}")
    print(f"  日志文件:     {INSTALL_DIR}/server.log")
    print()
    print(f"  📱 Android App 中填入:")
    print(f"     IP:   {Colors.GREEN}<你的电脑IP>{Colors.NC}")
    print(f"     端口: {Colors.GREEN}{PORT}{Colors.NC}")
    print()
    print(f"  🧪 验证: curl http://localhost:{PORT}/health")
    print()

    # 获取本机 IP
    try:
        import socket
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        print(f"  本机 IP: {Colors.GREEN}{local_ip}{Colors.NC}")
    except Exception:
        pass

    print(f"\n  {Colors.YELLOW}配置文件已自动备份（.backup-*），可随时恢复{Colors.NC}")


if __name__ == "__main__":
    main()
