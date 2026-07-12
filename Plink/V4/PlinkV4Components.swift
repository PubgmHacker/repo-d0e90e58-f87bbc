import SwiftUI

public struct V4ScreenHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String?

    public init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.eyebrow = eyebrow; self.title = title; self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow).font(.caption2.bold()).tracking(1.1).foregroundStyle(V4Tokens.accent)
            Text(title).font(.largeTitle.bold()).tracking(-1.1)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(V4Tokens.secondaryText) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct V4CircleButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 44, height: 44)
            .background(V4Tokens.surface.opacity(configuration.isPressed ? 0.96 : 0.86), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.12)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public struct V4PrimaryButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.black.opacity(0.84))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(V4Tokens.accent.opacity(configuration.isPressed ? 0.80 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

public struct V4SecondaryButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(V4Tokens.text)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(V4Tokens.surface.opacity(configuration.isPressed ? 1 : 0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
    }
}

public struct V4SearchField: View {
    @Binding var text: String
    let prompt: String

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(V4Tokens.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
    }
}

public struct V4HeroBanner: View {
    let item: V4MediaCard
    let action: () -> Void

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: item.artworkURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: LinearGradient(colors: [.blue.opacity(0.65), .orange.opacity(0.45), .black], startPoint: .topTrailing, endPoint: .bottomLeading)
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.96)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title).font(.title.bold()).tracking(-0.7)
                Text(item.subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.78)).lineLimit(2)
                Button("Смотреть вместе", systemImage: "play.fill", action: action)
                    .buttonStyle(V4PrimaryButtonStyle())
                    .frame(maxWidth: 210)
            }
            .padding(20)
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: V4Tokens.cornerLarge, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

public struct V4SectionTitle: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    public var body: some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            if let actionTitle, let action { Button(actionTitle, action: action).font(.subheadline).foregroundStyle(V4Tokens.accent) }
        }
    }
}

public struct V4RoomCard: View {
    let room: V4Room
    let action: () -> Void

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                AsyncImage(url: room.artworkURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: LinearGradient(colors: [.blue.opacity(0.4), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(width: 222, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text(room.title).font(.subheadline.bold()).lineLimit(1)
                Text("\(room.participantCount) участников" + (room.isLive ? " · LIVE" : ""))
                    .font(.caption).foregroundStyle(V4Tokens.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

public struct V4Avatar: View {
    let user: V4User
    var size: CGFloat = 42

    public var body: some View {
        AsyncImage(url: user.avatarURL) { phase in
            if case .success(let image) = phase { image.resizable().scaledToFill() }
            else { Text(String(user.displayName.prefix(1))).font(.headline).background(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)) }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
    }
}

public struct V4EmptyState: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(V4Tokens.accent)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(V4Tokens.secondaryText).multilineTextAlignment(.center)
            if let actionTitle, let action { Button(actionTitle, action: action).buttonStyle(V4PrimaryButtonStyle()) }
        }
        .padding(24)
    }
}
