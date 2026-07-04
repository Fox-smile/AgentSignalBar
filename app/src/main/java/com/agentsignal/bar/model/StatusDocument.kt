package com.agentsignal.bar.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * status.json 的完整数据模型。
 * 与 macOS Agent-Signal-Bar 的 SignalStateDocument 格式完全兼容。
 */
@Serializable
data class StatusDocument(
    @SerialName("schema_version")
    val schemaVersion: Int = 1,

    val aggregate: String? = null,

    @SerialName("updated_at")
    val updatedAt: String? = null,

    val sessions: Map<String, SessionRecord> = emptyMap(),

    val events: List<SignalEventRecord> = emptyList()
)

@Serializable
data class SessionRecord(
    val agent: String? = null,
    val signal: String,
    @SerialName("last_event")
    val lastEvent: String? = null,
    @SerialName("updated_at")
    val updatedAt: String
)

@Serializable
data class SignalEventRecord(
    val id: String,
    @SerialName("session_id")
    val sessionId: String,
    val agent: String? = null,
    val signal: String,
    val event: String? = null,
    @SerialName("updated_at")
    val updatedAt: String
)

/**
 * 从 status.json 解析后的简化快照，供 UI 层消费。
 */
data class SignalSnapshot(
    val displayState: DisplayState,
    val aggregate: String,
    val displayName: String,
    val updatedAt: String?,
    val activeSessions: List<SessionInfo>
)

data class SessionInfo(
    val sessionId: String,
    val agent: String,
    val signal: String,
    val lastEvent: String?
)
