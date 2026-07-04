package com.agentsignal.bar.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.lifecycle.lifecycleScope
import com.agentsignal.bar.MainActivity
import com.agentsignal.bar.R
import com.agentsignal.bar.model.DisplayState
import com.agentsignal.bar.repository.StatusRepository
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first

/**
 * 前台服务：持续轮询 Agent 状态并更新通知栏图标。
 */
class SignalService : Service() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var repository: StatusRepository

    companion object {
        const val CHANNEL_ID = "agent_signal_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_STOP = "com.agentsignal.bar.STOP"

        fun start(context: Context) {
            val intent = Intent(context, SignalService::class.java)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, SignalService::class.java)
            context.stopService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        repository = StatusRepository(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildNotification(DisplayState.DISCONNECTED, "正在连接...")
        startForeground(NOTIFICATION_ID, notification)

        // 开始轮询
        serviceScope.launch {
            val host = repository.hostFlow.first()
            val port = repository.portFlow.first()
            repository.startPolling(host, port)
        }

        // 监听状态变化并更新通知
        serviceScope.launch {
            repository.snapshot.collect { snapshot ->
                val notification = buildNotification(
                    snapshot.displayState,
                    snapshot.displayName
                )
                val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(NOTIFICATION_ID, notification)
            }
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        repository.stopPolling()
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = getString(R.string.channel_description)
            setShowBadge(false)
        }
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(state: DisplayState, statusText: String): Notification {
        val icon = when (state) {
            DisplayState.READY -> R.drawable.ic_signal_green
            DisplayState.ACTIVE -> R.drawable.ic_signal_yellow
            DisplayState.BLOCKED -> R.drawable.ic_signal_red
            DisplayState.PAUSED -> R.drawable.ic_signal_gray
            DisplayState.DISCONNECTED -> R.drawable.ic_signal_gray
        }

        val title = when (state) {
            DisplayState.READY -> "Agent: 空闲"
            DisplayState.ACTIVE -> "Agent: 忙碌中"
            DisplayState.BLOCKED -> "Agent: 卡住了!"
            DisplayState.PAUSED -> "Agent: 已暂停"
            DisplayState.DISCONNECTED -> "Agent: 断开连接"
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setContentText(statusText)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }
}
