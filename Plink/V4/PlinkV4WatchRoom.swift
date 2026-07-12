import SwiftUI

public struct V4WatchRoomBridge: View {
    let roomID: String
    @Bindable var themeStore: V4ThemeStore
    let adapter: any V4AppAdapter
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [V4ChatMessage] = [
        .init(id:"1", sender:.user(id:"a",name:"Алина"), text:"Вот это поворот 😳", isOwn:false, moderation:nil),
        .init(id:"2", sender:.plinkAI, text:"После серии могу добавить похожий ролик. Добавить в очередь?", isOwn:false, moderation:nil)
    ]
    @State private var draft = ""
    @State private var aiEnabled = true

    public var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                HStack(spacing: 0) { neutralPlayer.frame(width: proxy.size.width*0.68); socialRegion }
            } else {
                VStack(spacing: 0) { neutralPlayer.frame(height: proxy.size.height*0.52); socialRegion }
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    private var neutralPlayer: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            // GLM: replace this rectangle with the EXISTING stable PlayerStage/PlaybackCoordinator view.
            Rectangle().fill(Color.black).overlay(Text("Existing PlayerStage").foregroundStyle(.white.opacity(0.22)))
            Button { dismiss() } label: { Image(systemName:"xmark") }.buttonStyle(V4CircleButtonStyle()).padding(16)
        }.clipped()
    }

    private var socialRegion: some View {
        ZStack {
            V4LivingBackground(theme: themeStore.roomTheme, surface: .roomChat)
            themeStore.roomTheme.chatScrim.color
            VStack(spacing: 0) {
                HStack { Text("5 участников").font(.caption.bold()); Spacer(); Toggle("Plink AI", isOn:$aiEnabled).labelsHidden() }.padding(14)
                if aiEnabled { Text("Plink AI помогает с очередью и безопасностью").font(.caption).foregroundStyle(V4Tokens.warning).padding(.horizontal,14).padding(.bottom,8) }
                ScrollViewReader { proxy in ScrollView { LazyVStack(spacing:10) { ForEach(messages) { V4ChatBubble(message:$0) } }.padding(14) }.onChange(of:messages.count){_,_ in if let id=messages.last?.id{proxy.scrollTo(id,anchor:.bottom)}} }
                HStack { TextField("Сообщение комнате или @plink",text:$draft).padding(.horizontal,12).frame(minHeight:44).background(V4Tokens.surface,in:RoundedRectangle(cornerRadius:14)); Button { send() } label:{Image(systemName:"arrow.up")}.buttonStyle(V4CircleButtonStyle()) }.padding(12)
            }
        }.clipped()
    }

    private func send() {
        let text=draft.trimmingCharacters(in:.whitespacesAndNewlines);guard !text.isEmpty else{return};draft="";messages.append(.init(id:UUID().uuidString,sender:.user(id:"me",name:"Вы"),text:text,isOwn:true,moderation:nil));if aiEnabled && text.lowercased().contains("@plink"){messages.append(.init(id:UUID().uuidString,sender:.plinkAI,text:"Добавлю контент только после подтверждения хоста.",isOwn:false,moderation:nil))}
    }
}
