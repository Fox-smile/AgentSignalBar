package com.agentsignal.bar.ui

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.agentsignal.bar.model.DisplayState
import com.agentsignal.bar.overlay.SignalOverlayView
import com.agentsignal.bar.repository.StatusRepository
import com.agentsignal.bar.service.SignalService
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    repository: StatusRepository,
    overlayView: SignalOverlayView
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    // 配置状态
    var host by remember { mutableStateOf("") }
    var port by remember { mutableStateOf("") }
    var isOverlayEnabled by remember { mutableStateOf(false) }
    var isNotificationEnabled by remember { mutableStateOf(true) }
    var connectionStatus by remember { mutableStateOf<String?>(null) }

    // 当前状态
    val snapshot by repository.snapshot.collectAsState()
    val isRunning by repository.isRunning.collectAsState()

    // 加载保存的配置
    LaunchedEffect(Unit) {
        host = repository.hostFlow.first()
        port = repository.portFlow.first().toString()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        // --- 标题 ---
        Text(
            text = "Agent Signal Bar",
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(Modifier.height(4.dp))
        Text(
            text = "远程 Agent 状态监控面板",
            fontSize = 14.sp,
            color = Color.Gray
        )
        Spacer(Modifier.height(24.dp))

        // --- 当前状态卡片 ---
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(
                containerColor = when (snapshot.displayState) {
                    DisplayState.READY -> Color(0xFFE8F5E9)
                    DisplayState.ACTIVE -> Color(0xFFFFF3E0)
                    DisplayState.BLOCKED -> Color(0xFFFFEBEE)
                    else -> Color(0xFFF5F5F5)
                }
            )
        ) {
            Column(
                modifier = Modifier.padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // 状态圆点
                Box(
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .background(
                            when (snapshot.displayState) {
                                DisplayState.READY -> Color(0xFF4CAF50)
                                DisplayState.ACTIVE -> Color(0xFFFF9800)
                                DisplayState.BLOCKED -> Color(0xFFF44336)
                                else -> Color(0xFF9E9E9E)
                            }
                        )
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    text = snapshot.displayName,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.SemiBold
                )
                snapshot.updatedAt?.let {
                    Text(
                        text = "最后更新: $it",
                        fontSize = 12.sp,
                        color = Color.Gray
                    )
                }
                // 活跃 Agent 列表
                if (snapshot.activeSessions.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    snapshot.activeSessions.forEach { session ->
                        Text(
                            text = "${session.agent}: ${session.signal}",
                            fontSize = 12.sp,
                            color = Color.DarkGray
                        )
                    }
                }
            }
        }

        Spacer(Modifier.height(24.dp))

        // --- 服务器配置 ---
        Text(
            text = "服务器配置",
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(Modifier.height(12.dp))

        OutlinedTextField(
            value = host,
            onValueChange = { host = it },
            label = { Text("电脑 IP 地址") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )
        Spacer(Modifier.height(8.dp))

        OutlinedTextField(
            value = port,
            onValueChange = { port = it },
            label = { Text("端口") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )

        Spacer(Modifier.height(12.dp))

        // 测试连接按钮
        Button(
            onClick = {
                scope.launch {
                    val p = port.toIntOrNull() ?: 9120
                    repository.saveServerConfig(host, p)
                    val ok = repository.run {
                        val client = com.agentsignal.bar.network.StatusClient()
                        client.testConnection(host, p)
                    }
                    connectionStatus = if (ok) "连接成功 ✅" else "连接失败 ❌"
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("测试连接")
        }

        connectionStatus?.let {
            Spacer(Modifier.height(8.dp))
            Text(text = it, fontSize = 14.sp)
        }

        Spacer(Modifier.height(24.dp))

        // --- 功能开关 ---
        Text(
            text = "功能设置",
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(Modifier.height(12.dp))

        // 悬浮窗开关
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("桌面悬浮窗")
            Switch(
                checked = isOverlayEnabled,
                onCheckedChange = { enabled ->
                    isOverlayEnabled = enabled
                    if (enabled) {
                        // 检查权限
                        if (!Settings.canDrawOverlays(context)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:${context.packageName}")
                            )
                            context.startActivity(intent)
                        } else {
                            overlayView.show()
                        }
                    } else {
                        overlayView.hide()
                    }
                }
            )
        }

        // 通知开关
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("状态栏通知")
            Switch(
                checked = isNotificationEnabled,
                onCheckedChange = { enabled ->
                    isNotificationEnabled = enabled
                }
            )
        }

        Spacer(Modifier.height(24.dp))

        // --- 启动/停止按钮 ---
        Button(
            onClick = {
                val p = port.toIntOrNull() ?: 9120
                scope.launch {
                    repository.saveServerConfig(host, p)
                }
                if (isRunning) {
                    SignalService.stop(context)
                } else {
                    SignalService.start(context)
                }
            },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = if (isRunning)
                    Color(0xFFF44336)
                else
                    Color(0xFF4CAF50)
            )
        ) {
            Text(
                text = if (isRunning) "停止监控" else "启动监控",
                fontSize = 16.sp
            )
        }

        Spacer(Modifier.height(32.dp))

        // --- 使用说明 ---
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            colors = CardDefaults.cardColors(containerColor = Color(0xFFF5F5F5))
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = "使用说明",
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 16.sp
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    text = """
                        1. 在电脑上启动 HTTP Server：
                           python3 agent_signal_server.py
                        
                        2. 在手机上输入电脑的局域网 IP 地址
                        
                        3. 点击"测试连接"确认网络可达
                        
                        4. 点击"启动监控"开始实时监控
                        
                        5. 状态说明：
                           🟢 空闲 — Agent 无任务
                           🟡 忙碌 — Agent 工作中
                           🔴 卡住 — 需要你处理
                    """.trimIndent(),
                    fontSize = 13.sp,
                    color = Color.DarkGray,
                    lineHeight = 20.sp
                )
            }
        }
    }
}
