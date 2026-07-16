// Plink/V4/V4AIView.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

struct V4MorphOrb: View {
    let theme: V4Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 150
    var glow: CGFloat = 42
    var body: some View {
        let (c0,c1,c2,c3) = theme.colors
        TimelineView(.animation(minimumInterval: 1/30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let morph = reduceMotion ? 0 : (sin(t * .pi / 6) + 1) / 2
            let rotation = reduceMotion ? 0 : t.truncatingRemainder(dividingBy:18) / 18 * 360
            Canvas { context, canvas in
                let r = CGRect(origin:.zero,size:canvas).insetBy(dx:2,dy:2)
                let k = CGFloat(morph)
                var p = Path()
                p.move(to: CGPoint(x:r.midX,y:r.minY))
                p.addCurve(to:CGPoint(x:r.maxX,y:r.midY),control1:CGPoint(x:r.maxX*(0.70+0.12*k),y:r.minY),control2:CGPoint(x:r.maxX,y:r.maxY*(0.24+0.10*k)))
                p.addCurve(to:CGPoint(x:r.midX,y:r.maxY),control1:CGPoint(x:r.maxX,y:r.maxY*(0.76-0.12*k)),control2:CGPoint(x:r.maxX*(0.72-0.10*k),y:r.maxY))
                p.addCurve(to:CGPoint(x:r.minX,y:r.midY),control1:CGPoint(x:r.maxX*(0.30-0.08*k),y:r.maxY),control2:CGPoint(x:r.minX,y:r.maxY*(0.78+0.08*k)))
                p.addCurve(to:CGPoint(x:r.midX,y:r.minY),control1:CGPoint(x:r.minX,y:r.maxY*(0.28-0.08*k)),control2:CGPoint(x:r.maxX*(0.28+0.10*k),y:r.minY))
                p.closeSubpath()
                context.fill(p, with:.radialGradient(Gradient(stops:[
                    .init(color:Color.white.opacity(0.6),location:0), .init(color:c3,location:0.25),
                    .init(color:c2,location:0.53), .init(color:c1,location:0.70), .init(color:c0,location:0.77)
                ]),center:CGPoint(x:canvas.width*0.34,y:canvas.height*0.24),startRadius:0,endRadius:canvas.width*0.72))
                let inner = p.applying(CGAffineTransform(translationX:canvas.width*0.18,y:canvas.height*0.18).scaledBy(x:0.64,y:0.64).rotated(by:.pi/7.2))
                context.stroke(inner,with:.color(.white.opacity(0.47)),lineWidth:1)
            }.rotationEffect(.degrees(rotation))
        }.frame(width:size,height:size).shadow(color:c2,radius:glow)
    }
}

struct V4AIView: View {
    let theme: V4Theme
    @State private var input=""
    @State private var state="Готов помочь"
    var body: some View {
        ZStack(alignment:.bottom) {
            VStack(spacing:0) {
                HStack {
                    V4MorphOrb(theme:theme,size:41,glow:24)
                    VStack(alignment:.leading,spacing:2) {
                        Text("Plink AI").font(.system(size:16,weight:.bold))
                        Text("Кинокомпаньон").font(.system(size:11.04)).foregroundStyle(V4.muted)
                    }
                    Spacer(); V4RoundButton(symbol:"•••")
                }.frame(height:61).padding(.horizontal,17)
                ZStack(alignment:.bottom) {
                    V4MorphOrb(theme:theme)
                    VStack(spacing:3) {
                        Text("Что смотрим сегодня?").font(.system(size:16,weight:.bold))
                        Text(state).font(.system(size:11.52)).foregroundStyle(V4.muted)
                    }.padding(.bottom,13)
                }.frame(height:270)
                ScrollView(showsIndicators:false) {
                    VStack(alignment:.leading,spacing:8) {
                        VStack(alignment:.leading,spacing:3) {
                            Text("PLINK AI").font(.system(size:13.28,weight:.bold))
                            Text("Соберу очередь, создам комнату, позову друзей после подтверждения.")
                                .font(.system(size:13.28)).lineSpacing(5.31)
                        }.padding(.vertical,11).padding(.horizontal,13).background(V4.botBG)
                         .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                        HStack(spacing:7) {
                            chip("Очередь","Собери очередь"); chip("У друзей","Что смотрят друзья?"); chip("Комната","Создай комнату")
                        }
                    }.padding(.horizontal,16).padding(.top,8).padding(.bottom,92)
                }.background(LinearGradient(colors:[.clear,Color.oklch(0.06,0.01,190,alpha:0.76)],startPoint:UnitPoint(x:0.5,y:0.16),endPoint:.bottom))
            }.foregroundStyle(V4.ink)
            HStack(spacing:6) {
                Button("🎙") { state="Слушаю…" }.frame(width:42,height:42).background(V4.raised).clipShape(RoundedRectangle(cornerRadius:14))
                TextField("Спроси про фильмы и комнаты",text:$input).foregroundStyle(V4.ink)
                Button("➤") { state="Думаю…"; input="" }.frame(width:42,height:42).background(V4.accent).foregroundStyle(V4.accentInk).clipShape(RoundedRectangle(cornerRadius:14))
            }.padding(8).frame(minHeight:62).background(V4.composerBG).clipShape(RoundedRectangle(cornerRadius:22))
             .overlay(RoundedRectangle(cornerRadius:22).stroke(V4.line)).padding(.horizontal,13).padding(.bottom,10)
        }
    }
    private func chip(_ label:String,_ prompt:String)->some View {
        Button(label){ input=prompt }.font(.system(size:11.52)).foregroundStyle(V4.ink).padding(.horizontal,11).frame(height:36)
            .background(V4.surface).clipShape(RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(V4.line))
    }
}



struct V4AIViewLive: View {
    let theme: V4Theme
    @Bindable var store: V4AIStore
    @State private var input = ""
    @State private var showManualCreate = false
    @State private var confirmingAction: AIProposedAction?
    @State private var presentedRoom: Room?
    @State private var speakingPulseUntil: Date = .distantPast
    @State private var keyboard = KeyboardObserver()

    private var orbState: AIOrbState {
        if store.state == "Думаю…" { return .thinking }
        if keyboard.isVisible && !input.trimmingCharacters(in: .whitespaces).isEmpty { return .listening }
        if Date() < speakingPulseUntil { return .speaking }
        return .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                AICompanionModel(theme: theme, size: 41, glow: 18, state: orbState)
                VStack(alignment:.leading,spacing:2) {
                    Text("Plink AI").font(.system(size:16,weight:.bold))
                    Text("Кинокомпаньон").font(.system(size:11.04)).foregroundStyle(V4.muted)
                }
                Spacer()
                Button {
                    showManualCreate = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Комната")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(V4.accentInk)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(V4.accent)
                    .clipShape(Capsule())
                }
                .accessibilityLabel("Создать комнату вручную")
            }
            .frame(height:61)
            .padding(.horizontal,17)

            // AI orb zone — collapses ONLY when keyboard is visible
            ZStack(alignment:.bottom) {
                AICompanionModel(theme: theme, size: 220, glow: 60, state: orbState)
                VStack(spacing:3) {
                    Text("Что смотрим сегодня?").font(.system(size:16,weight:.bold))
                    Text(store.state).font(.system(size:11.52)).foregroundStyle(V4.muted)
                }.padding(.bottom,13)
            }
            .frame(maxWidth: .infinity)
            .frame(height: keyboard.isVisible ? 0 : 270)
            .clipped()
            .animation(.easeInOut(duration: 0.3), value: keyboard.isVisible)

            // Chat messages
            ScrollViewReader { proxy in
                ScrollView(showsIndicators:false) {
                    VStack(alignment:.leading,spacing:8) {
                        ForEach(store.messages) { msg in
                            if msg.isBot {
                                VStack(alignment:.leading,spacing:3) {
                                    Text("PLINK AI").font(.system(size:13.28,weight:.bold))
                                    Text(msg.text).font(.system(size:13.28)).lineSpacing(5.31)

                                    // P0.4: show confirm button if proposedAction exists
                                    if let action = msg.proposedAction {
                                        AIActionButton(action: action, store: store, presentedRoom: $presentedRoom, confirmingAction: $confirmingAction)
                                    }
                                }
                                .padding(.vertical,11).padding(.horizontal,13)
                                .background(V4.botBG)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .id(msg.id)
                            } else {
                                HStack {
                                    Spacer()
                                    Text(msg.text)
                                        .font(.system(size:13.28))
                                        .padding(.vertical,11).padding(.horizontal,13)
                                        .background(V4.accent.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                        .id(msg.id)
                                }
                            }
                        }
                        // Chips — AI prompts only (manual create is via header +)
                        HStack(spacing:7) {
                            chip("Очередь","Собери очередь на вечер")
                            chip("У друзей","Что смотрят друзья?")
                            chip("Через AI","Создай комнату с Inception")
                        }
                    }
                    .padding(.horizontal,16)
                    .padding(.top,8)
                    .padding(.bottom,100)
                }
                .onChange(of: store.messages.count) { _, _ in
                    if let last = store.messages.last, last.isBot {
                        speakingPulseUntil = Date().addingTimeInterval(2.5)
                    }
                    if let lastID = store.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }

            // Composer — full width, no side gaps
            HStack(spacing:6) {
                Button {
                    // mic toggle
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(V4.ink)
                }
                .frame(width:42,height:42)
                .background(V4.raised)
                .clipShape(RoundedRectangle(cornerRadius:14))

                TextField("Спроси про фильмы и комнаты", text:$input)
                    .foregroundStyle(V4.ink)
                    .font(.system(size: 14))

                Button {
                    let text = input
                    input = ""
                    HapticManager.impact(.light)
                    Task { await store.send(text) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(V4.accentInk)
                }
                .frame(width:42,height:42)
                .background(V4.accent)
                .clipShape(RoundedRectangle(cornerRadius:14))
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8)
            .frame(minHeight:62)
            .background(V4.composerBG)
            .clipShape(RoundedRectangle(cornerRadius:22))
            .overlay(RoundedRectangle(cornerRadius:22).stroke(V4.line))
            .padding(.horizontal,13)
            .padding(.bottom,90) // above tab bar
        }
        .foregroundStyle(V4.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity) // full screen
        .sheet(isPresented: $showManualCreate) {
            RoomCreationView(
                onRoomCreated: { _ in showManualCreate = false }
            )
            .environmentObject(APIClient.shared)
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $presentedRoom) { room in
            WatchRoomContainer(room: room)
        }
    }

    private func chip(_ label:String,_ prompt:String)->some View {
        Button {
            input = prompt
        } label: {
            Text(label)
                .font(.system(size:11.52))
                .foregroundStyle(V4.ink)
                .padding(.horizontal,11)
                .frame(height:36)
        }
        .background(V4.surface)
        .clipShape(RoundedRectangle(cornerRadius:12))
        .overlay(RoundedRectangle(cornerRadius:12).stroke(V4.line))
        .buttonStyle(.plain)
    }
}

// MARK: - AIActionButton (P0.4)

struct AIActionButton: View {
    let action: AIProposedAction
    let store: V4AIStore
    @Binding var presentedRoom: Room?
    @Binding var confirmingAction: AIProposedAction?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Preview
            if let preview = action.payloadPreview {
                VStack(alignment: .leading, spacing: 4) {
                    if let title = preview.title {
                        Text("📝 \(title)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(V4.ink)
                    }
                    if let privacy = preview.privacy {
                        Text("🔒 \(privacy)")
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                    }
                    if let count = preview.queueCount {
                        Text("📋 \(count) в очереди")
                            .font(.system(size: 12))
                            .foregroundStyle(V4.muted)
                    }
                }
                .padding(10)
                .background(V4.surface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 8) {
                Button {
                    Task { await confirm() }
                } label: {
                    HStack(spacing: 4) {
                        if loading {
                            ProgressView().tint(V4.accentInk)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        Text("Создать комнату")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.accentInk)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(V4.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(loading)

                Button {
                    confirmingAction = nil
                } label: {
                    Text("Отмена")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(V4.muted)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(V4.surface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if let err = error {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(V4.danger)
            }
        }
        .padding(.top, 6)
    }

    private func confirm() async {
        loading = true
        error = nil
        if let room = await store.confirmAction(action) {
            HapticManager.roomJoined()
            presentedRoom = room
        } else {
            HapticManager.errorOccurred()
            error = "Не удалось создать комнату"
        }
        loading = false
    }
}


enum AIOrbState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

// AI Companion Model (Canvas-based, matches V4 init signature)
struct AICompanionModel: View {
    let theme: V4Theme
    let size: CGFloat
    let glow: CGFloat
    let state: AIOrbState

    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let baseRadius = min(canvasSize.width, canvasSize.height) * 0.35
                let speed: Double
                switch state {
                case .idle: speed = 0.8
                case .listening: speed = 2.0
                case .thinking: speed = 4.0
                case .speaking: speed = 3.0
                }
                let pulseRadius = baseRadius * (1.0 + sin(t * speed) * 0.12)
                let accentColor = theme.accentColor
                let gradient = Gradient(colors: [accentColor.opacity(0.8), accentColor.opacity(0.2), Color.clear])
                ctx.fill(
                    Path(ellipseIn: CGRect(x: center.x - pulseRadius, y: center.y - pulseRadius,
                                            width: pulseRadius * 2, height: pulseRadius * 2)),
                    with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: pulseRadius)
                )
            }
        }
        .frame(width: size, height: size)
        .shadow(color: theme.accentColor.opacity(0.3), radius: glow)
    }
}

// PlinkAppDelegate extension for notification permission

