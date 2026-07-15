package com.plink.app.ui.room

import android.annotation.SuppressLint
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.plink.app.viewmodel.RoomViewModel

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun RoomScreen(
    viewModel: RoomViewModel,
    userId: String,
    onLeave: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    val listState = rememberLazyListState()

    BackHandler { onLeave() }

    LaunchedEffect(state.messages.size) {
        if (state.messages.isNotEmpty()) {
            listState.animateScrollToItem(state.messages.lastIndex)
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Button(onClick = onLeave) { Text("← Назад") }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(state.room.name, style = MaterialTheme.typography.titleSmall)
                Text("Код: ${state.room.code}", style = MaterialTheme.typography.bodySmall)
            }
            Text(
                if (state.connected) "Online" else "Offline",
                color = if (state.connected) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                },
            )
        }

        state.error?.let {
            Text(
                it,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(horizontal = 12.dp),
            )
        }

        val videoId = state.room.mediaItem?.videoId
        val embedUrl = when {
            !videoId.isNullOrBlank() -> "https://www.youtube.com/embed/$videoId?autoplay=1"
            !state.room.mediaItem?.streamURL.isNullOrBlank() -> state.room.mediaItem?.streamURL
            else -> null
        }

        if (embedUrl != null) {
            AndroidView(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(220.dp),
                factory = { context ->
                    WebView(context).apply {
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.mediaPlaybackRequiresUserGesture = false
                        webChromeClient = WebChromeClient()
                        webViewClient = WebViewClient()
                        loadUrl(embedUrl)
                    }
                },
                update = { webView ->
                    if (webView.url != embedUrl) {
                        webView.loadUrl(embedUrl)
                    }
                },
            )
        } else {
            Text(
                "Видео не выбрано",
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
            )
        }

        if (state.participants.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                state.participants.forEach { participant ->
                    Text(participant.username, style = MaterialTheme.typography.labelSmall)
                }
            }
        }

        Text(
            "Чат",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
        )

        LazyColumn(
            state = listState,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            items(state.messages, key = { it.id }) { message ->
                val mine = message.senderID == userId
                Text(
                    text = message.text,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(8.dp),
                    color = if (mine) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                )
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            OutlinedTextField(
                value = state.draft,
                onValueChange = viewModel::setDraft,
                placeholder = { Text("Сообщение...") },
                modifier = Modifier.weight(1f),
                singleLine = true,
            )
            Button(onClick = viewModel::sendMessage) { Text("→") }
        }
    }
}