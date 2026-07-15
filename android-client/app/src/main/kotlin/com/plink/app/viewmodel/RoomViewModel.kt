package com.plink.app.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.plink.app.data.api.PlinkApi
import com.plink.app.data.models.ChatMessage
import com.plink.app.data.models.JoinRoomRequest
import com.plink.app.data.models.Participant
import com.plink.app.data.models.Room
import com.plink.app.data.ws.PlinkRealtimeClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class RoomUiState(
    val room: Room,
    val messages: List<ChatMessage> = emptyList(),
    val participants: List<Participant> = emptyList(),
    val connected: Boolean = false,
    val draft: String = "",
    val error: String? = null,
    val loading: Boolean = true,
)

class RoomViewModel(
    private val api: PlinkApi,
    private val realtimeClient: PlinkRealtimeClient,
    initialRoom: Room,
) : ViewModel() {

    private val _state = MutableStateFlow(RoomUiState(room = initialRoom))
    val state: StateFlow<RoomUiState> = _state.asStateFlow()

    init {
        connect()
        observeRealtime()
    }

    private fun observeRealtime() {
        viewModelScope.launch {
            realtimeClient.connected.collect { connected ->
                _state.update { it.copy(connected = connected) }
            }
        }
        viewModelScope.launch {
            realtimeClient.messages.collect { message ->
                _state.update { it.copy(messages = it.messages + message) }
            }
        }
        viewModelScope.launch {
            realtimeClient.errors.collect { error ->
                _state.update { it.copy(error = error) }
            }
        }
    }

    private fun connect() {
        val room = _state.value.room
        viewModelScope.launch {
            _state.update { it.copy(loading = true, error = null) }
            try {
                if (!room.code.isNullOrBlank()) {
                    runCatching { api.joinRoom(JoinRoomRequest(room.code)) }
                }
                val history = api.getMessages(room.id)
                val parts = api.getParticipants(room.id)
                _state.update {
                    it.copy(
                        messages = history.messages,
                        participants = parts.participants,
                        loading = false,
                    )
                }
                realtimeClient.connect(room.id)
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        loading = false,
                        error = e.message ?: "Room connect failed",
                    )
                }
            }
        }
    }

    fun setDraft(text: String) {
        _state.update { it.copy(draft = text) }
    }

    fun sendMessage() {
        val text = _state.value.draft.trim()
        if (text.isBlank()) return
        realtimeClient.sendChat(text)
        _state.update { it.copy(draft = "") }
    }

    fun leave() {
        viewModelScope.launch {
            runCatching { api.leaveRoom(_state.value.room.id) }
            realtimeClient.disconnect()
        }
    }

    override fun onCleared() {
        realtimeClient.disconnect()
        super.onCleared()
    }
}