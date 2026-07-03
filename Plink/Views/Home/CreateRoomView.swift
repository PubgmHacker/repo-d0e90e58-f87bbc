import SwiftUI

// MARK: - Create Room View
/// Sheet for creating a new room with name, max participants, and optional media.
/// YouTube links are extracted server-side via MediaService → backend (yt-dlp),
/// producing a direct .mp4/.m3u8 URL that AVPlayer can play directly.
struct CreateRoomView: View {
    @State private var roomName = ""
    @State private var maxParticipants = 10
    @State private var mediaURL = ""
    @State private var mediaTitle = ""
    @State private var isLoading = false
    @State private var isExtracting = false
    @State private var errorMessage: String?
    @State private var extractedMedia: ExtractedMedia?
    @State private var resolvedMediaItem: MediaItem?
    @Environment(\.dismiss) private var dismiss

    /// Injected from parent (PlinkApp). Carries the JWT for authenticated calls.
    var mediaService: MediaService?
    var onRoomCreated: (Room) -> Void

    private var hasYouTubeLink: Bool {
        mediaURL.lowercased().contains("youtube.com") || mediaURL.lowercased().contains("youtu.be")
    }

    private var hasDirectLink: Bool {
        guard let url = URL(string: mediaURL) else { return false }
        return [".mp4", ".m3u8", ".mp3", ".webm"].contains { url.pathExtension.lowercased() == $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        // Room Name
                        VStack(alignment: .leading, spacing: 8) {
                            label("Room Name")
                            TextField("e.g., Movie Night 🍿", text: $roomName)
                                .textFieldStyle(RaveTextFieldStyle())
                        }

                        // Max Participants
                        VStack(alignment: .leading, spacing: 8) {
                            label("Max Participants")

                            HStack(spacing: 16) {
                                Slider(value: Binding(
                                    get: { Double(maxParticipants) },
                                    set: { maxParticipants = Int($0) }
                                ), in: 2...20, step: 1) {
                                    EmptyView()
                                } minimumValueLabel: {
                                    Text("2")
                                        .font(.caption)
                                        .foregroundColor(.raveTextSecondary)
                                } maximumValueLabel: {
                                    Text("20")
                                        .font(.caption)
                                        .foregroundColor(.raveTextSecondary)
                                }
                                .tint(.ravePrimary)

                                Text("\(maxParticipants)")
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundColor(.ravePrimary)
                                    .frame(width: 40)
                            }
                        }

                        Divider()
                            .background(Color.raveSurface)
                            .padding(.vertical, 8)

                        // ─── Media Section ─────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                label("Add Media (Optional)")
                                Spacer()
                                Text("You can add media later")
                                    .font(.caption2)
                                    .foregroundColor(.raveTextSecondary)
                            }

                            TextField("YouTube link or direct .mp4/.m3u8 URL",
                                      text: $mediaURL,
                                      axis: .vertical)
                                .textFieldStyle(RaveTextFieldStyle())
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: mediaURL) { _, _ in
                                    // Reset previous extraction if the URL changed
                                    if extractedMedia != nil {
                                        extractedMedia = nil
                                        resolvedMediaItem = nil
                                    }
                                }

                            // Extract button (YouTube only)
                            if hasYouTubeLink && extractedMedia == nil {
                                Button(action: extractYouTube) {
                                    HStack(spacing: 6) {
                                        if isExtracting {
                                            ProgressView()
                                                .tint(.ravePrimary)
                                        } else {
                                            Image(systemName: "arrow.down.circle")
                                        }
                                        Text(isExtracting ? "Extracting…" : "Get direct stream URL")
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundColor(.ravePrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.ravePrimary.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled(isExtracting || mediaURL.isEmpty)
                                .transition(.opacity)
                            }

                            // Optional title override
                            if extractedMedia == nil && !mediaURL.isEmpty {
                                TextField("Title (optional)", text: $mediaTitle)
                                    .textFieldStyle(RaveTextFieldStyle())
                                    .transition(.opacity)
                            }
                        }

                        // ─── Extraction Preview ────────────────────────
                        if let extracted = extractedMedia {
                            extractionPreview(extracted)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // ─── Info Box ──────────────────────────────────
                        infoBox

                        // Error
                        if let error = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.raveDanger)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.raveDanger)
                            }
                            .padding(.horizontal, 4)
                            .transition(.opacity)
                        }

                        // Create button
                        Button(action: createRoom) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isLoading ? "Creating…" : "Create Room")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .raveButtonStyle()
                        .disabled(roomName.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .animation(.easeInOut(duration: 0.25), value: extractedMedia != nil)
                    .animation(.easeInOut(duration: 0.2), value: errorMessage != nil)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Create Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.ravePrimary)
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Extraction Preview

    @ViewBuilder
    private func extractionPreview(_ media: ExtractedMedia) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.raveSurface)
                    if let thumb = media.thumbnailURL {
                        AsyncImage(url: thumb) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundColor(.ravePrimary)
                            }
                        }
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(.ravePrimary)
                    }
                }
                .frame(width: 90, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(media.title)
                        .font(.subheadline.bold())
                        .foregroundColor(.raveTextPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Label(media.quality, systemImage: "sparkles.tv")
                        if let dur = media.duration {
                            Text(formatDuration(dur))
                        }
                        if media.isLive {
                            Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                                .foregroundColor(.raveDanger)
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.raveTextSecondary)

                    Text(".\(media.format) stream ready")
                        .font(.caption2)
                        .foregroundColor(.raveGreen)
                }
                Spacer()
            }

            Button(role: .destructive) {
                withAnimation {
                    extractedMedia = nil
                    resolvedMediaItem = nil
                    mediaURL = ""
                }
            } label: {
                Label("Remove media", systemImage: "trash")
                    .font(.caption)
                    .foregroundColor(.raveDanger)
            }
        }
        .padding(14)
        .background(Color.raveCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.raveGreen.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func extractYouTube() {
        guard let mediaService else {
            errorMessage = "Media service unavailable"
            return
        }
        Task {
            isExtracting = true
            errorMessage = nil
            do {
                let extracted = try await mediaService.extract(youTubeURL: mediaURL)
                resolvedMediaItem = mediaService.makeMediaItem(from: extracted)
                withAnimation { extractedMedia = extracted }
            } catch let MediaError.videoUnavailable(detail) {
                errorMessage = detail
            } catch MediaError.rateLimited {
                errorMessage = "Rate limited. Wait a few seconds and try again."
            } catch MediaError.invalidURL {
                errorMessage = "That doesn't look like a valid YouTube link."
            } catch MediaError.unauthorized {
                errorMessage = "Session expired. Please sign in again."
            } catch {
                errorMessage = "Couldn't extract this video. It may be private, age-restricted, or region-locked."
            }
            isExtracting = false
        }
    }

    private func createRoom() {
        guard !roomName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        errorMessage = nil

        // Resolve final MediaItem:
        // - YouTube link → already extracted into resolvedMediaItem
        // - Direct .mp4/.m3u8 → wrap directly (no extraction needed)
        // - Empty → nil (media can be added later in-room)
        let finalMediaItem: MediaItem?
        if let resolved = resolvedMediaItem {
            finalMediaItem = resolved
        } else if hasDirectLink {
            finalMediaItem = MediaItem(
                id: UUID().uuidString,
                title: mediaTitle.isEmpty ? mediaURL : mediaTitle,
                artist: nil,
                thumbnailURL: nil,
                streamURL: mediaURL,
                duration: nil,
                mediaType: .video,
                source: .url
            )
        } else {
            finalMediaItem = nil
        }

        let newRoom = Room(
            id: UUID().uuidString,
            name: roomName.trimmingCharacters(in: .whitespaces),
            hostID: "current_user",          // set by API on the server
            hostName: "You",
            code: generateRoomCode(),
            participants: [],
            mediaItem: finalMediaItem,
            isActive: true,
            maxParticipants: maxParticipants,
            hostIsPremium: false,
            createdAt: Date()
        )

        isLoading = false
        onRoomCreated(newRoom)
    }

    // MARK: - Components

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundColor(.raveTextPrimary)
    }

    private var infoBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundColor(.raveWarning)
                Text("Supported sources")
                    .font(.caption.bold())
                    .foregroundColor(.raveTextPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("• YouTube links (auto-extracted to .mp4)")
                Text("• Direct .mp4 / .m3u8 / .mp3 URLs")
                Text("• Plex / Jellyfin servers")
            }
            .font(.caption2)
            .foregroundColor(.raveTextSecondary)
        }
        .padding(14)
        .background(Color.raveSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func generateRoomCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Preview
#Preview {
    CreateRoomView(mediaService: nil) { _ in }
}
