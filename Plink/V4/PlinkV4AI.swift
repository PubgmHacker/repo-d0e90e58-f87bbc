import SwiftUI
import Observation

@MainActor
@Observable
public final class V4AIViewModel {
    public var messages: [V4ChatMessage] = [.init(id: UUID().uuidString, sender: .plinkAI, text: "Соберу очередь, создам комнату и помогу с безопасностью чата.", isOwn: false, moderation: nil)]
    public var draft = ""
    public var state: V4AIState = .idle
    let adapter: any V4AppAdapter
    init(adapter: any V4AppAdapter) { self.adapter = adapter }

    public func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; draft = ""
        messages.append(.init(id: UUID().uuidString, sender: .user(id: "me", name: "Вы"), text: text, isOwn: true, moderation: nil))
        state = .thinking
        Task {
            do { let reply = try await adapter.sendAI(text); messages.append(.init(id: UUID().uuidString, sender: .plinkAI, text: reply, isOwn: false, moderation: nil)); state = .idle }
            catch { messages.append(.init(id: UUID().uuidString, sender: .system, text: "Не удалось ответить. Попробуйте снова.", isOwn: false, moderation: nil)); state = .failed }
        }
    }
}

public struct V4AIScreen: View {
    @Environment(V4ThemeStore.self) private var themes
    @State private var model: V4AIViewModel
    init(adapter: any V4AppAdapter, themeStore: V4ThemeStore) { _model = State(initialValue: V4AIViewModel(adapter: adapter)) }

    public var body: some View {
        V4SurfaceView(theme: themes.appTheme, surface: .ai) {
            VStack(spacing: 0) {
                HStack { Text("Plink AI").font(.headline); Spacer(); Image(systemName: "ellipsis") }.padding(.horizontal, 18).frame(height: 60)
                V4AIMeshView(state: model.state, theme: themes.appTheme).frame(height: 250)
                ScrollViewReader { proxy in
                    ScrollView { LazyVStack(spacing: 10) { ForEach(model.messages) { V4ChatBubble(message: $0) } }.padding(16) }
                        .onChange(of: model.messages.count) { _, _ in if let id = model.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
                HStack(spacing: 8) {
                    Button { model.state = model.state == .listening ? .idle : .listening } label: { Image(systemName: "mic.fill") }.buttonStyle(V4CircleButtonStyle())
                    TextField("Спроси про фильмы и комнаты", text: $model.draft).padding(.horizontal, 12).frame(minHeight: 44).background(V4Tokens.surface, in: RoundedRectangle(cornerRadius: 14)).onSubmit(model.send)
                    Button(action: model.send) { Image(systemName: "arrow.up") }.buttonStyle(V4CircleButtonStyle())
                }.padding(14)
            }
        }
    }
}

public struct V4AIMeshView: View {
    let state: V4AIState; let theme: V4Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1.0/30.0)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width/2, y: size.height/2)
                for ring in 1...22 {
                    let radius = CGFloat(ring) * min(size.width, size.height) / 52
                    var path = Path()
                    for point in 0...72 {
                        let angle = Double(point)/72 * Double.pi * 2
                        let speed = state == .thinking ? 1.6 : state == .listening ? 2.1 : 0.8
                        let wobble = 1 + 0.12*sin(angle*3 + t*speed) + 0.06*cos(angle*5 - t*0.55)
                        let x = center.x + cos(angle) * Double(radius) * wobble
                        let y = center.y + sin(angle) * Double(radius) * wobble * 0.78
                        point == 0 ? path.move(to: CGPoint(x:x,y:y)) : path.addLine(to: CGPoint(x:x,y:y))
                    }
                    path.closeSubpath()
                    context.stroke(path, with: .linearGradient(Gradient(colors: [theme.secondary.color.opacity(0.85), theme.tertiary.color.opacity(0.78), theme.primary.color.opacity(0.72)]), startPoint: .zero, endPoint: CGPoint(x:size.width,y:size.height)), lineWidth: 0.65)
                }
            }
        }
        .shadow(color: theme.tertiary.color.opacity(0.45), radius: state == .thinking ? 28 : 18)
        .accessibilityHidden(true)
        .overlay(alignment: .bottom) { Text(accessibleState).font(.caption).foregroundStyle(V4Tokens.secondaryText).accessibilityHidden(false) }
    }
    private var accessibleState: String { switch state { case .idle:"Готов помочь"; case .listening:"Слушаю"; case .thinking:"Думаю"; case .speaking:"Отвечаю"; case .moderating:"Проверяю безопасность"; case .offline:"Нет сети"; case .failed:"Ошибка" } }
}

public struct V4ChatBubble: View {
    let message: V4ChatMessage
    public var body: some View {
        VStack(alignment: message.isOwn ? .trailing : .leading, spacing: 4) {
            if message.sender.isVerified { Label(message.sender.displayName, systemImage: "checkmark.seal.fill").font(.caption2.bold()).foregroundStyle(V4Tokens.warning) }
            Text(message.text).font(.subheadline).foregroundStyle(message.isOwn ? Color.black.opacity(0.84) : V4Tokens.text).padding(12).background(background, in: RoundedRectangle(cornerRadius: 17))
        }.frame(maxWidth: .infinity, alignment: message.isOwn ? .trailing : .leading).id(message.id)
    }
    private var background: Color { if message.isOwn { return V4Tokens.accent }; if message.sender.isVerified { return Color(red:0.20,green:0.16,blue:0.06).opacity(0.96) }; return V4Tokens.surface.opacity(0.94) }
}
