package com.plink.app.data.ws

import com.plink.app.data.ApiConfig
import com.plink.app.data.api.PlinkApi
import com.plink.app.data.models.ChatMessage
import com.plink.app.data.models.RealtimeTicketRequest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.TimeUnit

class PlinkRealtimeClient(
    private val api: PlinkApi,
    private val okHttpClient: OkHttpClient,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var webSocket: WebSocket? = null
    private var roomId: String? = null

    private val _connected = MutableStateFlow(false)
    val connected: StateFlow<Boolean> = _connected.asStateFlow()

    private val _messages = MutableSharedFlow<ChatMessage>(extraBufferCapacity = 64)
    val messages: SharedFlow<ChatMessage> = _messages.asSharedFlow()

    private val _errors = MutableSharedFlow<String>(extraBufferCapacity = 8)
    val errors: SharedFlow<String> = _errors.asSharedFlow()

    suspend fun connect(roomId: String) = withContext(Dispatchers.IO) {
        disconnect()
        this@PlinkRealtimeClient.roomId = roomId

        val ticketResponse = api.getRealtimeTicket(RealtimeTicketRequest(roomId))
        val protocols = ticketResponse.protocol.ifEmpty {
            listOf("plink.v2", "plink.ticket.${ticketResponse.ticket}")
        }

        val url = "${ApiConfig.WS_URL}/ws/room/$roomId"
        val request = Request.Builder()
            .url(url)
            .header("Sec-WebSocket-Protocol", protocols.joinToString(", "))
            .build()

        webSocket = okHttpClient.newWebSocket(request, listener)
    }

    fun disconnect() {
        webSocket?.close(1000, "Client disconnect")
        webSocket = null
        roomId = null
        _connected.value = false
    }

    fun sendChat(text: String) {
        val socket = webSocket ?: return
        val currentRoomId = roomId ?: return
        val payload = JSONObject().apply {
            put("type", "chat.send")
            put("protocolVersion", 2)
            put("roomId", currentRoomId)
            put("clientMessageId", UUID.randomUUID().toString())
            put("text", text)
        }
        socket.send(payload.toString())
    }

    private val listener = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            _connected.value = true
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            scope.launch {
                try {
                    handleServerMessage(JSONObject(text))
                } catch (_: Exception) {
                    _errors.emit("Invalid WebSocket message")
                }
            }
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            _connected.value = false
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            _connected.value = false
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            _connected.value = false
            scope.launch {
                _errors.emit(t.message ?: "WebSocket connection failed")
            }
        }
    }

    private suspend fun handleServerMessage(data: JSONObject) {
        when (data.optString("type")) {
            "chat.broadcast" -> {
                val message = ChatMessage(
                    id = data.optString("messageId"),
                    senderID = data.optString("senderId").ifBlank {
                        data.optString("senderID")
                    },
                    text = data.optString("text"),
                    createdAt = formatIsoTimestamp(data.optLong("timestampMs", System.currentTimeMillis())),
                    clientMessageId = data.optString("clientMessageId").ifBlank { null },
                )
                _messages.emit(message)
            }
            "error" -> {
                val error = data.optString("message").ifBlank {
                    data.optString("code", "Realtime error")
                }
                _errors.emit(error)
            }
        }
    }

    companion object {
        fun createOkHttpClient(): OkHttpClient {
            return OkHttpClient.Builder()
                .pingInterval(30, TimeUnit.SECONDS)
                .build()
        }

        private fun formatIsoTimestamp(timestampMs: Long): String {
            return java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US)
                .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
                .format(java.util.Date(timestampMs))
        }
    }
}