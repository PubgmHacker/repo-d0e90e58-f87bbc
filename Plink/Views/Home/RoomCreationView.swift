// Plink/Views/Home/RoomCreationView.swift — simplified, no V4 deps
import SwiftUI

struct RoomCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var apiClient: APIClient
    var friendManager: FriendManager? = nil
    var intent: CreateRoomIntent? = nil
    var onRoomCreated: (Room) -> Void

    @State private var currentStep: CreationStep = .service
    @State private var selectedService: VideoService = .youtube
    @State private var mediaURL = ""
    @State private var mediaTitle = ""
    @State private var roomName = ""
    @State private var maxParticipants = 4
    @State private var privacy: RoomPrivacy = .publicRoom
    @State private var isCreating = false
    @State private var selectedThemeID: String = "electric-blue"

    enum CreationStep: String, CaseIterable {
        case service, details
        var next: CreationStep? { self == .service ? .details : nil }
        var previous: CreationStep? { self == .details ? .service : nil }
    }

    private var isPremium: Bool { PremiumStatusManager.shared.isPremium }

    var body: some View {
        NavigationStack {
            Cinema2026.background.ignoresSafeArea().overlay {
                switch currentStep {
                case .service: serviceStep
                case .details: detailsStep
                }
            }
            .navigationTitle("Новая комната")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
        .onAppear {
            if case .selectedContent(let draft) = intent {
                mediaURL = draft.contentURL
                mediaTitle = draft.title
                currentStep = .details
            }
        }
    }

    private var serviceStep: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("НОВАЯ КОМНАТА").font(.caption2.bold()).tracking(1.1).foregroundStyle(Cinema2026.accent)
                Text("Выберите сервис").font(.largeTitle.bold()).foregroundStyle(Cinema2026.text)

                serviceRow("play.rectangle.fill", "YouTube", "Поиск и выбор видео", true) {
                    selectedService = .youtube; mediaURL = ""; currentStep = .details
                }
                serviceRow("play.tv.fill", "Rutube", "Поиск видео", true) {
                    selectedService = .rutube; currentStep = .details
                }
                serviceRow("safari.fill", "Браузер", "Скоро", false) { }
                serviceRow("link", "Вставить ссылку", "YouTube / Rutube URL", true) {
                    selectedService = .youtube; currentStep = .details
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 32)
        }
    }

    private func serviceRow(_ icon: String, _ title: String, _ subtitle: String, _ available: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: available ? action : {}) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(available ? Cinema2026.accent : Cinema2026.secondary)
                    .frame(width: 44, height: 44).background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(available ? Cinema2026.text : Cinema2026.secondary)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Cinema2026.secondary)
                }
                Spacer()
                if available { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Cinema2026.secondary) }
            }
            .padding(14).background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(!available)
    }

    private var detailsStep: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text("НАСТРОЙКА").font(.caption2.bold()).tracking(1.1).foregroundStyle(Cinema2026.accent)
                Text("Оформите комнату").font(.largeTitle.bold()).foregroundStyle(Cinema2026.text)

                if !mediaTitle.isEmpty {
                    HStack(spacing: 12) {
                        Rectangle().fill(Cinema2026.surface).frame(width: 80, height: 45).clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(mediaTitle).font(.system(size: 14, weight: .medium)).foregroundStyle(Cinema2026.text).lineLimit(2)
                        Spacer()
                    }.padding(12).background(Cinema2026.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Название комнаты").font(.system(size: 14, weight: .semibold)).foregroundStyle(Cinema2026.secondary)
                    TextField("Комната друзей", text: $roomName)
                        .font(.system(size: 16)).foregroundStyle(Cinema2026.text)
                        .padding(.horizontal, 16).frame(height: 52)
                        .background(Cinema2026.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Cinema2026.divider, lineWidth: 0.5))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Приватность").font(.system(size: 14, weight: .semibold)).foregroundStyle(Cinema2026.secondary)
                    HStack(spacing: 10) {
                        privacyChip("Публичная", privacy == .publicRoom) { privacy = .publicRoom }
                        privacyChip("Приватная", privacy == .privateRoom) { privacy = .privateRoom }
                    }
                }

                Text("Оформление комнаты").font(.system(size: 16, weight: .semibold)).foregroundStyle(Cinema2026.text)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(PlinkThemeCatalog.all) { theme in
                            Button { if theme.access == .free || isPremium { selectedThemeID = theme.id } } label: {
                                ZStack(alignment: .bottomLeading) {
                                    LinearGradient(colors: theme.colors.map { $0.color }, startPoint: .topLeading, endPoint: .bottomTrailing)
                                        .frame(width: 112, height: 150).clipShape(RoundedRectangle(cornerRadius: 20))
                                    Text(theme.name).font(.caption.bold()).foregroundStyle(.white).padding(10)
                                }
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(selectedThemeID == theme.id ? .white : .white.opacity(0.12), lineWidth: selectedThemeID == theme.id ? 2 : 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }

                Button { Task { await createRoom() } } label: {
                    HStack { if isCreating { ProgressView().tint(Cinema2026.background) }; Text("Создать комнату") }
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Cinema2026.background)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Cinema2026.accent, in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(roomName.isEmpty || isCreating)
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 32)
        }
    }

    private func privacyChip(_ title: String, _ isSelected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Cinema2026.background : Cinema2026.text)
                .padding(.horizontal, 16).frame(height: 40)
                .background(isSelected ? Cinema2026.accent : Cinema2026.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private func createRoom() async {
        isCreating = true; defer { isCreating = false }
        let mediaItem = MediaItem(id: mediaURL, title: mediaTitle.isEmpty ? "YouTube" : mediaTitle, artist: nil,
                                  thumbnailURL: "https://img.youtube.com/vi/\(mediaURL)/mqdefault.jpg",
                                  streamURL: mediaURL, duration: nil, mediaType: .video, source: .youtube)
        let request = CreateRoomRequest(name: roomName.isEmpty ? "Комната" : roomName, maxParticipants: maxParticipants,
                                        mediaItem: mediaItem, privacy: privacy, password: nil, hostName: nil)
        do {
            let room = try await RoomService(api: apiClient).createRoom(request)
            onRoomCreated(room); dismiss()
        } catch { }
    }
}
