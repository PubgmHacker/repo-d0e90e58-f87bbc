// Plink/Features/Rooms/RoomsHubView.swift — Rooms hub
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §4

import SwiftUI

struct RoomsHubView: View {
    enum Filter: String, CaseIterable { case live = "Сейчас", mine = "Мои", history = "История" }

    @State private var filter: Filter = .live
    @State private var search = ""
    @State private var model: RoomsHubViewModel

    init(dependencies: AppDependencies) {
        _model = State(initialValue: RoomsHubViewModel(roomService: dependencies.roomService))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            filterPicker

            let filtered = model.filteredRooms(filter: filter, query: search)
            if filtered.isEmpty {
                RoomEmptyState(filter: filter)
            } else {
                List {
                    ForEach(filtered) { room in
                        RoomListRow(room: room)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Cinema2026.divider)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(text: $search, prompt: "Найти комнату")
        .background(Cinema2026.background)
        .task { await model.load() }
    }

    private var header: some View {
        HStack {
            Text("Комнаты")
                .font(.system(size: 30, weight: .bold))
                .tracking(-1)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var filterPicker: some View {
        Picker("Фильтр комнат", selection: $filter) {
            ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

@MainActor
@Observable
final class RoomsHubViewModel {
    private(set) var liveRooms: [Room] = []
    private(set) var myRooms: [Room] = []
    private(set) var history: [Room] = []
    var createPresented = false

    private let roomService: RoomService

    init(roomService: RoomService) {
        self.roomService = roomService
    }

    func load() async {
        do {
            async let live = roomService.fetchActiveRooms()
            async let mine = roomService.fetchMyRooms()
            (liveRooms, myRooms) = try await (live, mine)
        } catch {
            // Silently fail — UI shows empty state.
        }
    }

    func filteredRooms(filter: RoomsHubView.Filter, query: String) -> [Room] {
        let rooms: [Room]
        switch filter {
        case .live: rooms = liveRooms
        case .mine: rooms = myRooms
        case .history: rooms = history
        }
        if query.isEmpty { return rooms }
        return rooms.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func canDelete(_ room: Room) -> Bool {
        // TODO: wire to current user id
        false
    }

    func share(_ room: Room) {
        // TODO: share sheet
    }

    func end(_ room: Room) async {
        try? await roomService.deleteRoom(roomID: room.id)
        await load()
    }
}

// MARK: - Room list row

struct RoomListRow: View {
    let room: Room

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                PosterImage(url: room.mediaItem?.thumbnailURL)
                    .frame(width: 78, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if room.isActive {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Cinema2026.danger, in: Capsule())
                        .padding(6)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(room.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Cinema2026.text)
                    .lineLimit(1)

                Text(room.mediaItem?.title ?? "Без видео")
                    .font(.caption)
                    .foregroundStyle(Cinema2026.secondary)
                    .lineLimit(1)

                ParticipantAvatarStack(participants: room.participants)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(Cinema2026.tertiary)
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Empty state

struct RoomEmptyState: View {
    let filter: RoomsHubView.Filter

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(Cinema2026.tertiary)

            Text(emptyTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Cinema2026.text)

            Text(emptySubtitle)
                .font(.system(size: 14))
                .foregroundStyle(Cinema2026.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch filter {
        case .live: return "Нет активных комнат"
        case .mine: return "У вас пока нет комнат"
        case .history: return "История пуста"
        }
    }

    private var emptySubtitle: String {
        switch filter {
        case .live: return "Создайте комнату и пригласите друзей"
        case .mine: return "Создайте свою первую комнату"
        case .history: return "Здесь появятся просмотренные комнаты"
        }
    }
}
