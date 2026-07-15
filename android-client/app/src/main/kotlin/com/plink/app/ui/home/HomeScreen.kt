package com.plink.app.ui.home

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.plink.app.data.models.Room
import com.plink.app.data.models.TrendingVideo
import com.plink.app.viewmodel.HomeViewModel

@Composable
fun HomeScreen(
    viewModel: HomeViewModel,
    onOpenRoom: (Room) -> Unit,
    onOpenProfile: () -> Unit,
) {
    val state by viewModel.state.collectAsState()

    if (state.loading) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            CircularProgressIndicator()
            Text("Загрузка...")
        }
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Plink", style = MaterialTheme.typography.headlineMedium)
                TextButton(onClick = onOpenProfile) { Text("Профиль") }
            }
        }

        state.error?.let { error ->
            item {
                Text(error, color = MaterialTheme.colorScheme.error)
            }
        }

        item {
            Text("Популярное", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(state.trending) { video ->
                    TrendingCard(
                        video = video,
                        enabled = !state.actionLoading,
                        onClick = { viewModel.createFromVideo(video, onOpenRoom) },
                    )
                }
            }
        }

        item {
            Text("Войти по коду", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = state.joinCode,
                    onValueChange = viewModel::setJoinCode,
                    placeholder = { Text("ABCD12") },
                    modifier = Modifier.weight(1f),
                    singleLine = true,
                )
                Button(
                    onClick = { viewModel.joinByCode(onOpenRoom) },
                    enabled = !state.actionLoading,
                ) {
                    Text("Войти")
                }
            }
        }

        item {
            Text("Активные комнаты", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            if (state.rooms.isEmpty()) {
                Text("Нет активных комнат", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }

        items(state.rooms) { room ->
            RoomCard(room = room, onClick = { onOpenRoom(room) })
        }
    }
}

@Composable
private fun TrendingCard(
    video: TrendingVideo,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Card(
        modifier = Modifier
            .size(width = 160.dp, height = 180.dp)
            .clickable(enabled = enabled, onClick = onClick),
    ) {
        Column {
            AsyncImage(
                model = video.thumbnailURL,
                contentDescription = video.title,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(100.dp),
                contentScale = ContentScale.Crop,
            )
            Text(
                text = video.title,
                modifier = Modifier.padding(8.dp),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

@Composable
private fun RoomCard(
    room: Room,
    onClick: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(room.name, style = MaterialTheme.typography.titleSmall)
            Text("Код: ${room.code}", style = MaterialTheme.typography.bodySmall)
            Text(room.hostName, style = MaterialTheme.typography.bodySmall)
        }
    }
}