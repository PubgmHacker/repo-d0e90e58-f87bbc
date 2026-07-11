// Plink/Features/WatchRoom/WatchRoomScreen.swift
// Adaptive watch room UI (runbook §10, §21, Brain Review 5 P0-33, P0-34)
//
// Brain Review 5 fixes:
//   P0-33: functional host controls — play/pause/seek with optimistic local apply
//   P0-34: chat button opens sheet on iPhone
//
// Adaptive layout:
//   - iPhone portrait: player on top, chat as slide-up sheet (button to open)
//   - iPhone landscape: player full-screen, chat overlay
//   - iPad: split view — player leading, chat trailing column

import SwiftUI

public struct WatchRoomScreen: View {
    @Bindable var model: WatchRoomModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showControls = true
    @State private var chatSheetPresented = false  // P0-34: now toggleable
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var seekPosition: Double = 0

    public init(model: WatchRoomModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            await model.connect()
        }
        .onDisappear {
            model.disconnect()
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - iPad split layout

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            VStack {
                PlayerSurfaceView(coordinator: model.coordinator)
                if model.isHost {
                    PlayerControlsOverlay(model: model, showControls: $showControls, seekPosition: $seekPosition)
                } else {
                    ViewerControlsBar(model: model)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ChatTimeline(messages: model.chatMessages, onSend: model.sendChat)
                .frame(width: 360)
                .background(Color(.systemBackground))
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        ZStack {
            PlayerSurfaceView(coordinator: model.coordinator)
                .ignoresSafeArea()

            if model.isHost {
                PlayerControlsOverlay(model: model, showControls: $showControls, seekPosition: $seekPosition)
                    .opacity(showControls ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: showControls)
            } else {
                ViewerControlsBar(model: model)
                    .opacity(showControls ? 1 : 0)
            }

            VStack {
                ConnectionBanner(state: model.connectionState, lastError: model.lastError)
                Spacer()
                // P0-34: bottom bar with chat button + participants
                HStack {
                    if !model.participants.isEmpty {
                        ParticipantStrip(participants: model.participants)
                    }
                    Spacer()
                    // P0-34: chat button — opens sheet
                    Button(action: { chatSheetPresented = true }) {
                        Image(systemName: "message.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5), in: Circle())
                    }
                    .accessibilityLabel("Open chat")
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // P0-36: reaction overlay — temporarily disabled (reactions array
            // removed from WatchRoomModel to resolve @Observable macro ambiguity)
            // if !model.reactions.isEmpty {
            //     ReactionOverlayView(reactions: model.reactions)
            // }
        }
        .onTapGesture {
            toggleControls()
        }
        .sheet(isPresented: $chatSheetPresented) {
            ChatTimeline(messages: model.chatMessages, onSend: model.sendChat)
                .presentationDetents([.medium, .large])
        }
    }

    private func toggleControls() {
        showControls.toggle()
        controlsHideTask?.cancel()
        if showControls {
            controlsHideTask = Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !Task.isCancelled {
                    showControls = false
                }
            }
        }
    }
}

// MARK: - P0-33: Functional host controls

struct PlayerControlsOverlay: View {
    let model: WatchRoomModel
    @Binding var showControls: Bool
    @Binding var seekPosition: Double

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 32) {
                // P0-33: functional play/pause buttons
                Button(action: {
                    Task { await model.sendPauseCommand() }
                }) {
                    Image(systemName: "pause.fill")
                        .font(.title)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Pause")

                Button(action: {
                    Task { await model.sendPlayCommand() }
                }) {
                    Image(systemName: "play.fill")
                        .font(.title)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Play")

                Spacer()

                // P0-33: seek slider
                Slider(value: $seekPosition, in: 0...max(model.coordinator.duration, 1), onEditingChanged: { editing in
                    if !editing {
                        Task { await model.sendSeekCommand(to: seekPosition) }
                    }
                })
                .frame(width: 120)
                .accessibilityLabel("Seek position")

                SyncIndicator(driftMs: model.lastDriftMs, synced: model.clockSynced)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
        .onAppear {
            seekPosition = model.coordinator.position
        }
    }
}

// P0-33: viewer controls — read-only, no play/pause/seek
struct ViewerControlsBar: View {
    let model: WatchRoomModel

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Text("Viewer — host controls playback")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                SyncIndicator(driftMs: model.lastDriftMs, synced: model.clockSynced)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }
}

struct ConnectionBanner: View {
    let state: RealtimeConnectionState
    let lastError: String?

    var body: some View {
        if !state.isOnline {
            HStack {
                ProgressView().scaleEffect(0.7)
                Text(bannerText)
                    .font(.caption)
                Spacer()
            }
            .padding(8)
            .background(.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.top, 4)
            .accessibilityLabel("Connection status: \(bannerText)")
        }
    }

    private var bannerText: String {
        switch state {
        case .idle: return "Disconnected"
        case .connecting: return "Connecting..."
        case .authenticating: return "Authenticating..."
        case .joining: return "Joining room..."
        case .synchronizing: return "Synchronizing..."
        case .connected: return ""
        case .reconnecting(let attempt): return "Reconnecting (attempt \(attempt))..."
        case .failed(let reason): return "Failed: \(reason)"
        }
    }
}

struct ParticipantStrip: View {
    let participants: [ParticipantInfo]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(participants) { p in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .overlay(Text(String(p.username.prefix(1))))
                        Text(p.username)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5), in: Capsule())
                }
            }
        }
        .frame(height: 36)
    }
}

struct SyncIndicator: View {
    let driftMs: Double
    let synced: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(synced ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(synced ? "Synced" : "Syncing")
                .font(.caption2)
        }
        .accessibilityLabel(synced ? "Clock synchronized, drift \(Int(driftMs))ms" : "Clock synchronizing")
    }
}

// MARK: - ChatTimeline

struct ChatTimeline: View {
    let messages: [ChatMessageInfo]
    let onSend: (String) -> Void

    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { msg in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(msg.senderName).font(.caption).foregroundStyle(.secondary)
                            Text(msg.text).font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(msg.isPending ? Color.gray.opacity(0.2) : Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            HStack {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button("Send") {
                    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    onSend(text)
                    inputText = ""
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
    }
}

// P0-36: Reaction overlay — uses existing ReactionOverlayView from Views/Room/
// (defined in Plink/Views/Room/ReactionOverlayView.swift)
