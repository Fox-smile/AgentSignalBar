package com.agentsignal.bar.repository

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.agentsignal.bar.model.DisplayState
import com.agentsignal.bar.model.SessionInfo
import com.agentsignal.bar.model.SignalSnapshot
import com.agentsignal.bar.network.StatusClient
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "agent_signal_settings")

/**
 * 核心状态仓库。
 * 管理 HTTP 轮询、状态解析、配置持久化。
 */
class StatusRepository(private val context: Context) {

    private val client = StatusClient()

    // --- 配置 ---
    companion object {
        val KEY_HOST = stringPreferencesKey("server_host")
        val KEY_PORT = intPreferencesKey("server_port")
        const val DEFAULT_HOST = "192.168.1.100"
        const val DEFAULT_PORT = 9120
        const val POLL_INTERVAL_MS = 2000L
    }

    /** 服务器配置 Flow */
    val hostFlow: Flow<String> = context.dataStore.data.map { prefs ->
        prefs[KEY_HOST] ?: DEFAULT_HOST
    }

    val portFlow: Flow<Int> = context.dataStore.data.map { prefs ->
        prefs[KEY_PORT] ?: DEFAULT_PORT
    }

    suspend fun saveServerConfig(host: String, port: Int) {
        context.dataStore.edit { prefs ->
            prefs[KEY_HOST] = host
            prefs[KEY_PORT] = port
        }
    }

    // --- 状态 ---
    private val _snapshot = MutableStateFlow(
        SignalSnapshot(
            displayState = DisplayState.DISCONNECTED,
            aggregate = "unknown",
            displayName = "等待连接",
            updatedAt = null,
            activeSessions = emptyList()
        )
    )
    val snapshot: StateFlow<SignalSnapshot> = _snapshot.asStateFlow()

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

    /**
     * 开始轮询。在协程中持续运行直到被取消。
     */
    suspend fun startPolling(host: String, port: Int) {
        _isRunning.value = true
        var consecutiveFailures = 0

        while (_isRunning.value) {
            val doc = client.fetchStatus(host, port)

            if (doc != null) {
                consecutiveFailures = 0
                val displayState = DisplayState.fromAggregate(doc.aggregate)
                val displayName = when (displayState) {
                    DisplayState.READY -> "空闲"
                    DisplayState.ACTIVE -> "忙碌"
                    DisplayState.BLOCKED -> "卡住"
                    DisplayState.PAUSED -> "已暂停"
                    DisplayState.DISCONNECTED -> "断开连接"
                }

                val sessions = doc.sessions.map { (id, record) ->
                    SessionInfo(
                        sessionId = id,
                        agent = record.agent ?: "unknown",
                        signal = record.signal,
                        lastEvent = record.lastEvent
                    )
                }

                _snapshot.value = SignalSnapshot(
                    displayState = displayState,
                    aggregate = doc.aggregate ?: "idle",
                    displayName = displayName,
                    updatedAt = doc.updatedAt,
                    activeSessions = sessions
                )
            } else {
                consecutiveFailures++
                // 连续失败 3 次才显示断开，避免网络抖动
                if (consecutiveFailures >= 3) {
                    _snapshot.value = _snapshot.value.copy(
                        displayState = DisplayState.DISCONNECTED,
                        displayName = "断开连接"
                    )
                }
            }

            delay(POLL_INTERVAL_MS)
        }
    }

    fun stopPolling() {
        _isRunning.value = false
    }
}
