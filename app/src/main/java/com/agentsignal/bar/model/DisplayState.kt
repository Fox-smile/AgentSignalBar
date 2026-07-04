package com.agentsignal.bar.model

/**
 * 信号灯的三种核心显示状态。
 * 这是从原始 AgentSignal 简化后的版本，只保留用户关心的三种语义。
 */
enum class DisplayState(
    val priority: Int,
    val chineseName: String,
    val description: String
) {
    /** 空闲 — Agent 没有在处理任务 */
    READY(0, "空闲", "Agent 空闲中，无需关注"),

    /** 忙碌 — Agent 正在思考或执行工具 */
    ACTIVE(50, "忙碌", "Agent 正在工作中"),

    /** 卡住 — Agent 遇到错误、阻塞或需要审批 */
    BLOCKED(90, "卡住", "Agent 遇到问题，需要处理"),

    /** 暂停 — 监控已暂停 */
    PAUSED(100, "已暂停", "监控已暂停"),

    /** 断开 — 无法连接到电脑 */
    DISCONNECTED(-1, "断开连接", "无法连接到电脑端服务");

    companion object {
        /**
         * 从原始 AgentSignal 的 aggregate 字符串映射到 DisplayState。
         * 兼容 Agent-Signal-Bar macOS 版的 status.json 格式。
         */
        fun fromAggregate(aggregate: String?): DisplayState {
            if (aggregate == null) return READY
            return when (aggregate.lowercase()) {
                "idle", "done", "ready", "session_start", "session_end",
                "turn_end", "completed" -> READY

                "thinking", "working", "tool_done", "tool_use",
                "subagent_start", "subagent_stop", "active" -> ACTIVE

                "blocked", "failure", "error", "exception",
                "max_tokens", "stale", "permission",
                "permission_request", "needs_review" -> BLOCKED

                "off", "pause", "paused" -> PAUSED

                else -> READY
            }
        }
    }
}
