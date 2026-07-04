package com.agentsignal.bar.network

import com.agentsignal.bar.model.StatusDocument
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * HTTP 客户端，负责从电脑端 HTTP Server 拉取 status.json。
 */
class StatusClient {

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(3, TimeUnit.SECONDS)
        .readTimeout(3, TimeUnit.SECONDS)
        .build()

    /**
     * 获取当前状态。
     * @param host 电脑 IP 地址
     * @param port 端口号
     * @return StatusDocument 或 null（连接失败）
     */
    suspend fun fetchStatus(host: String, port: Int): StatusDocument? {
        return withContext(Dispatchers.IO) {
            try {
                val url = "http://$host:$port/api/status"
                val request = Request.Builder()
                    .url(url)
                    .get()
                    .build()

                val response = client.newCall(request).execute()
                if (!response.isSuccessful) return@withContext null

                val body = response.body?.string() ?: return@withContext null
                json.decodeFromString<StatusDocument>(body)
            } catch (e: Exception) {
                null
            }
        }
    }

    /**
     * 测试连接是否可达。
     */
    suspend fun testConnection(host: String, port: Int): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val url = "http://$host:$port/health"
                val request = Request.Builder()
                    .url(url)
                    .get()
                    .build()

                val response = client.newCall(request).execute()
                response.isSuccessful
            } catch (e: Exception) {
                false
            }
        }
    }
}
