// Plink/V4/PlinkV4PixelPerfect.swift — GPT-5.6 Pixel Perfect V4
// Auto-generated from PLINK_V4_PIXEL_PERFECT_FOR_GLM_5_2.md
// This is the SINGLE source of truth for V4 design.

import SwiftUI
import Foundation

import SwiftUI

extension Color {
    /// Exact CSS OKLCH -> linear sRGB -> display sRGB conversion.
    static func oklch(_ l: Double, _ c: Double, _ h: Double, alpha: Double = 1) -> Color {
        let hr = h * .pi / 180
        let a = c * cos(hr)
        let b = c * sin(hr)
        let l1 = l + 0.3963377774 * a + 0.2158037573 * b
        let m1 = l - 0.1055613458 * a - 0.0638541728 * b
        let s1 = l - 0.0894841775 * a - 1.2914855480 * b
        let L = l1 * l1 * l1
        let M = m1 * m1 * m1
        let S = s1 * s1 * s1
        let rLin =  4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
        let gLin = -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
        let bLin = -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
        func gamma(_ x: Double) -> Double {
            let v = x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        return Color(.sRGB, red: gamma(rLin), green: gamma(gLin), blue: gamma(bLin), opacity: alpha)
    }
}

enum V4 {
    static let canvas = Color.oklch(0.06, 0.01, 190)
    static let ink = Color.oklch(0.96, 0.008, 190)
    static let muted = Color.oklch(0.72, 0.018, 190)
    static let line = Color.oklch(0.88, 0.01, 190, alpha: 0.13)
    static let surface = Color.oklch(0.17, 0.018, 190)
    static let raised = Color.oklch(0.22, 0.02, 190)
    static let accent = Color.oklch(0.78, 0.12, 174)
    static let accentInk = Color.oklch(0.17, 0.04, 174)
    static let amber = Color.oklch(0.79, 0.14, 78)
    static let danger = Color.oklch(0.65, 0.18, 25)
    static let roundBG = Color.oklch(0.15, 0.016, 190, alpha: 0.86)
    static let searchBG = Color.oklch(0.14, 0.016, 190, alpha: 0.82)
    static let cardBG = Color.oklch(0.17, 0.02, 190, alpha: 0.82)
    static let navBG = Color.oklch(0.13, 0.015, 190, alpha: 0.94)
    static let botBG = Color.oklch(0.17, 0.018, 190, alpha: 0.94)
    static let composerBG = Color.oklch(0.13, 0.015, 190, alpha: 0.96)
}


// MARK: - Section

enum V4Theme: String, CaseIterable, Identifiable {
    case electric, ember, violet, plink, bloom
    var id: Self { self }
    var name: String { rawValue.capitalized }
    var colors: (Color, Color, Color, Color) {
        switch self {
        case .electric: return (.oklch(0.09,0.02,255), .oklch(0.53,0.17,258), .oklch(0.79,0.12,210), .oklch(0.65,0.17,270))
        case .ember: return (.oklch(0.10,0.025,45), .oklch(0.56,0.19,35), .oklch(0.82,0.15,78), .oklch(0.68,0.18,28))
        case .violet: return (.oklch(0.09,0.025,285), .oklch(0.51,0.19,285), .oklch(0.68,0.20,325), .oklch(0.75,0.13,310))
        case .plink: return (.oklch(0.09,0.02,190), .oklch(0.57,0.13,185), .oklch(0.55,0.17,258), .oklch(0.68,0.14,326))
        case .bloom: return (.oklch(0.10,0.03,320), .oklch(0.54,0.21,330), .oklch(0.68,0.21,15), .oklch(0.74,0.16,350))
        }
    }
}


// MARK: - Section

struct V4Avatar: View {
    let letter: String
    let theme: V4Theme
    var size: CGFloat = 43
    var body: some View {
        let (_, c1, c2, _) = theme.colors
        Text(letter)
            .font(.system(size: size == 43 ? 16 : 14, weight: .black))
            .foregroundStyle(V4.ink)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Circle())
            .overlay(Circle().stroke(V4.line, lineWidth: 1))
    }
}

struct V4RoundButton: View {
    let symbol: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) { Text(symbol).foregroundStyle(V4.ink) }
            .frame(width: 43, height: 43)
            .background(V4.roundBG)
            .clipShape(Circle())
            .overlay(Circle().stroke(V4.line, lineWidth: 1))
    }
}

struct V4Heading: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow)
                .font(.system(size: 10.88, weight: .heavy))
                .tracking(1.1968)
                .foregroundStyle(V4.accent)
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .tracking(-1.6)
                .lineSpacing(1.28)
                .foregroundStyle(V4.ink)
            if let subtitle { Text(subtitle).font(.system(size: 13.12)).foregroundStyle(V4.muted) }
        }
    }
}

struct V4MediaCard: View {
    let title: String
    let meta: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer()
            Text(title).font(.system(size: 13.92, weight: .bold)).foregroundStyle(V4.ink)
            Text(meta).font(.system(size: 11.52)).foregroundStyle(V4.muted)
        }
        .padding(14)
        .frame(width: 222, height: 132, alignment: .leading)
        .background(V4.cardBG)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(V4.line, lineWidth: 1))
    }
}

struct V4Hero: View {
    let title: String
    let meta: String
    let button: String
    let height: CGFloat
    let theme: V4Theme
    let action: () -> Void
    var body: some View {
        let (_, c1, c2, _) = theme.colors
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [c1, Color.oklch(0.10,0.02,190)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [c2, .clear], center: UnitPoint(x: 0.72, y: 0.22), startRadius: 0, endRadius: height * 0.42)
            LinearGradient(colors: [.clear, Color.oklch(0.06,0.01,190,alpha:0.95)], startPoint: UnitPoint(x:0.5,y:0.28), endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 26.4, weight: .bold)).foregroundStyle(V4.ink)
                Text(meta).font(.system(size: 13.12)).foregroundStyle(V4.muted)
                Button(action: action) {
                    Text(button).font(.system(size: 14, weight: .heavy)).foregroundStyle(V4.accentInk)
                        .padding(.horizontal, 16).frame(height: 46).background(V4.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
            }.padding(.horizontal, 19).padding(.bottom, 18)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
        .shadow(color: .black.opacity(0.40), radius: 27, y: 25)
    }
}


// MARK: - Section

struct V4LivingBackground: View {
    let theme: V4Theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        GeometryReader { g in
            let (c0, c1, c2, c3) = theme.colors
            ZStack {
                c0
                blob(c1, g, x: -0.35, y: -0.15, dx: 0.44, dy: 0.30, scale: 1.14, rotation: 7, duration: 14)
                blob(c2, g, x:  0.45, y:  0.28, dx: -0.39, dy: -0.21, scale: 0.92, rotation: -6, duration: 16)
                blob(c3, g, x:  0.12, y:  0.70, dx: 0.10, dy: -0.30, scale: 1.12, rotation: 0, duration: 13)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.10),
                    .init(color: Color.oklch(0.06,0.01,190,alpha:0.10), location: 0.36),
                    .init(color: Color.oklch(0.06,0.01,190,alpha:0.86), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: g.size.width * 1.3, height: g.size.height * 1.3)
            .offset(x: -g.size.width * 0.15, y: -g.size.height * 0.15)
            .clipped()
            .onAppear { if !reduceMotion { phase = true } }
        }.ignoresSafeArea()
    }

    private func blob(_ color: Color, _ g: GeometryProxy, x: CGFloat, y: CGFloat,
                      dx: CGFloat, dy: CGFloat, scale: CGFloat, rotation: Double, duration: Double) -> some View {
        let side = g.size.width * 1.17
        return RoundedRectangle(cornerRadius: side * 0.48, style: .continuous)
            .fill(color).frame(width: side, height: side)
            .blur(radius: 55).opacity(0.52)
            .position(x: g.size.width * (x + 0.45), y: g.size.height * (y + 0.45))
            .offset(x: phase ? g.size.width * dx : 0, y: phase ? g.size.height * dy : 0)
            .scaleEffect(phase ? scale : 1).rotationEffect(.degrees(phase ? rotation : 0))
            .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: duration).repeatForever(autoreverses: true), value: phase)
    }
}


// MARK: - Section

struct V4HomeView: View {
    let theme: V4Theme
    let openRoom: () -> Void
    @State private var query = ""
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack { V4Avatar(letter: "П", theme: theme); Spacer(); V4RoundButton(symbol: "○") }
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                V4Heading(eyebrow: "СУББОТНИЙ ВЕЧЕР", title: "С кем смотрим?")
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.bottom,18)
                HStack(spacing:9) {
                    Image(systemName:"magnifyingglass")
                    TextField("Видео, сервис или комната", text:$query).foregroundStyle(V4.ink)
                }.font(.system(size:13)).foregroundStyle(V4.muted).padding(.horizontal,13).frame(height:48)
                 .background(V4.searchBG).clipShape(RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(V4.line))
                 .padding(.horizontal,19).padding(.bottom,18)
                V4Hero(title:"Afterglow", meta:"5 друзей уже смотрят. Подключайся сразу.", button:"▶ Смотреть вместе", height:300, theme:theme, action:openRoom)
                    .padding(.horizontal,13).padding(.bottom,28)
                HStack { Text("Сейчас вместе").font(.system(size:18.24,weight:.bold)); Spacer(); Text("Все").font(.system(size:12.16)).foregroundStyle(V4.accent) }
                    .padding(.horizontal,19).padding(.bottom,12)
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:11) {
                    V4MediaCard(title:"Кино без спойлеров",meta:"5 друзей · LIVE")
                    V4MediaCard(title:"Смешное на YouTube",meta:"3 друга · 12 мин")
                }.padding(.horizontal,19) }
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
    }
}


// MARK: - Section

struct V4RoomsView: View {
    let theme: V4Theme
    let openRoom: () -> Void
    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                HStack(alignment:.top) {
                    V4Heading(eyebrow:"ОБЗОР",title:"Комнаты")
                    Spacer(); V4RoundButton(symbol:"⌕")
                }.padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                V4Hero(title:"Ночной клуб",meta:"12 зрителей · открытая комната",button:"Войти",height:235,theme:theme,action:openRoom)
                    .padding(.horizontal,13).padding(.bottom,28)
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:11) {
                    V4MediaCard(title:"Музыкальные открытия",meta:"8 участников")
                    V4MediaCard(title:"Научпоп без скуки",meta:"6 участников")
                }.padding(.horizontal,19) }
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
    }
}


// MARK: - Section

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
                var inner = p.applying(CGAffineTransform(translationX:canvas.width*0.18,y:canvas.height*0.18).scaledBy(x:0.64,y:0.64).rotated(by:.pi/7.2))
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


// MARK: - Section

struct V4FriendsView: View {
    let theme: V4Theme
    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                HStack(alignment:.top) { V4Heading(eyebrow:"ВМЕСТЕ ЛУЧШЕ",title:"Друзья"); Spacer(); V4RoundButton(symbol:"＋") }
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                VStack(spacing:0) {
                    friend("А","Алина","смотрит Afterglow","Войти")
                    friend("М","Миша","готов смотреть","Позвать")
                }.padding(.horizontal,19)
                HStack { Text("Недавно вместе").font(.system(size:18.24,weight:.bold)); Spacer() }
                    .padding(.horizontal,19).padding(.top,26).padding(.bottom,12)
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:11) {
                    V4MediaCard(title:"Ночной рейс",meta:"с Алиной · вчера")
                    V4MediaCard(title:"Первый контакт",meta:"с командой")
                }.padding(.horizontal,19) }
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
    }
    private func friend(_ letter:String,_ name:String,_ status:String,_ action:String)->some View {
        HStack(spacing:11) {
            V4Avatar(letter:letter,theme:theme,size:39)
            VStack(alignment:.leading,spacing:2) { Text(name).font(.system(size:13.6,weight:.bold)); Text(status).font(.system(size:11.52)).foregroundStyle(V4.muted) }
            Spacer()
            Button(action){}.font(.system(size:11.52)).foregroundStyle(V4.ink).padding(.horizontal,10).frame(height:35)
                .background(V4.surface).clipShape(RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).stroke(V4.line))
        }.frame(minHeight:61).overlay(alignment:.bottom){ Rectangle().fill(V4.line).frame(height:1) }
    }
}


// MARK: - Section

struct V4ProfileView: View {
    let theme: V4Theme
    @Binding var showAppearance: Bool
    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                HStack { V4Avatar(letter:"П",theme:theme); Spacer(); V4RoundButton(symbol:"✎") }
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                V4Heading(eyebrow:"ПРОФИЛЬ",title:"пымым",subtitle:"Plink+ активен до 12 августа")
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.bottom,18)
                groupTitle("Аккаунт")
                group([("person","Личные данные",nil), ("diamond","Приватность и безопасность",nil)])
                groupTitle("Приложение")
                VStack(spacing:0) {
                    setting("circle.lefthalf.filled","Оформление","Electric ›"){showAppearance=true}
                    setting("circle.fill","Уведомления","›"){}
                    setting("play.fill","Воспроизведение","›"){}
                    setting("questionmark","Помощь","›"){}
                }.groupStyle()
                groupTitle("Безопасность")
                VStack(spacing:0) {
                    setting("nosign","Заблокированные","›"){}
                    setting("xmark","Удалить аккаунт","›",danger:true){}
                }.groupStyle()
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
    }
    private func groupTitle(_ s:String)->some View { Text(s.uppercased()).font(.system(size:10.56,weight:.heavy)).tracking(1.1616).foregroundStyle(V4.muted).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.vertical,9) }
    private func group(_ rows:[(String,String,String?)])->some View { VStack(spacing:0){ ForEach(Array(rows.enumerated()),id:\.offset){_,r in setting(r.0,r.1,r.2 ?? "›"){} } }.groupStyle() }
    private func setting(_ icon:String,_ title:String,_ trailing:String,danger:Bool=false,action:@escaping()->Void)->some View {
        Button(action:action){ HStack(spacing:11){ Image(systemName:icon).frame(width:30); Text(title).font(.system(size:13.6,weight:.bold)); Spacer(); Text(trailing).font(.system(size:11.52)).foregroundStyle(V4.muted) }.foregroundStyle(danger ? V4.danger : V4.ink).frame(minHeight:54).overlay(alignment:.bottom){Rectangle().fill(V4.line).frame(height:1)} }
    }
}
extension View { func groupStyle()->some View { self.padding(.horizontal,13).background(V4.searchBG).clipShape(RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(V4.line)).padding(.horizontal,19).padding(.bottom,18) } }

struct V4AppearanceView: View {
    @Binding var theme: V4Theme
    @Binding var presented: Bool
    var body: some View {
        ZStack { V4LivingBackground(theme:theme)
            ScrollView(showsIndicators:false) { VStack(spacing:0) {
                HStack { V4RoundButton(symbol:"‹"){presented=false}; Spacer(); Text("Оформление").font(.system(size:16,weight:.bold)); Spacer(); Color.clear.frame(width:43,height:43) }.padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                V4Heading(eyebrow:"PLINK+",title:"Живая тема",subtitle:"Одна палитра, разные композиции во всём приложении.")
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.bottom,18)
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:10){ ForEach(V4Theme.allCases){ item in themeCard(item) } }.padding(.horizontal,19).padding(.bottom,15) }
                VStack(spacing:0) {
                    toggleRow("Живое движение","Следует системным настройкам",true)
                    toggleRow("Больше контраста","Усиливает подложки текста",false)
                    toggleRow("Темы комнат","Сохранённые пресеты",false)
                }.groupStyle()
            }}.foregroundStyle(V4.ink)
        }
    }
    private func themeCard(_ item:V4Theme)->some View { let(c0,c1,c2,_)=item.colors; return Button(action:{theme=item}){ ZStack(alignment:.bottomLeading){ c0; RadialGradient(colors:[c1,.clear],center:UnitPoint(x:0.25,y:0.22),startRadius:0,endRadius:75); RadialGradient(colors:[c2,.clear],center:UnitPoint(x:0.78,y:0.75),startRadius:0,endRadius:80); Text(item.name).font(.system(size:10.72,weight:.heavy)).padding(9) }.frame(width:112,height:150).clipShape(RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(theme == item ? V4.ink : V4.line,lineWidth:theme == item ? 2:1)) } }
    private func toggleRow(_ title:String,_ detail:String,_ on:Bool)->some View { HStack { VStack(alignment:.leading){Text(title).font(.system(size:13.6,weight:.bold));Text(detail).font(.system(size:11.2)).foregroundStyle(V4.muted)};Spacer(); if on { Capsule().fill(V4.accent).frame(width:48,height:29).overlay(Circle().fill(V4.ink).frame(width:23,height:23).offset(x:9.5)) } else { Text("›") } }.frame(minHeight:58).overlay(alignment:.bottom){Rectangle().fill(V4.line).frame(height:1)} }
}


// MARK: - Section

struct V4TabBar: View {
    @Binding var selection: Int
    let items=[("house","Главная"),("circle.circle","Комнаты"),("sparkles","ИИ"),("person","Друзья"),("person.crop.circle","Профиль")]
    var body: some View {
        HStack(spacing:0){ ForEach(items.indices,id:\.self){ i in Button(action:{selection=i}){VStack(spacing:2){Image(systemName:items[i].0).font(.system(size:17.28));Text(items[i].1).font(.system(size:9.44))}.frame(maxWidth:.infinity,maxHeight:.infinity).foregroundStyle(selection==i ? V4.accent:V4.muted).background(selection==i ? V4.accent.opacity(0.08):.clear).clipShape(RoundedRectangle(cornerRadius:15))} } }
        .padding(6).frame(height:69).background(.ultraThinMaterial).background(V4.navBG).clipShape(RoundedRectangle(cornerRadius:23)).overlay(RoundedRectangle(cornerRadius:23).stroke(V4.line)).padding(.horizontal,13).padding(.bottom,10)
    }
}


// MARK: - Section

struct PlinkApprovedV4Root: View {
    @State private var tab=0
    @State private var theme:V4Theme = .electric
    @State private var appearance=false
    @State private var room=false

    // P0: Real backend stores
    @State private var roomsStore: V4RoomsStore?
    @State private var searchStore = V4SearchStore()
    @State private var friendsStore: V4FriendsStore?
    @State private var aiStore = V4AIStore()
    @State private var profileStore: V4ProfileStore?

    var body: some View {
        ZStack(alignment:.bottom){
            V4LivingBackground(theme:theme)
            Group {
                switch tab {
                case 0: V4HomeViewLive(theme:theme, searchStore:searchStore, roomsStore:roomsStore, openRoom:{room=true})
                case 1: V4RoomsViewLive(theme:theme, roomsStore:roomsStore, openRoom:{room=true})
                case 2: V4AIViewLive(theme:theme, store:aiStore)
                case 3: V4FriendsViewLive(theme:theme, store:friendsStore)
                default: V4ProfileViewLive(theme:theme, store:profileStore, showAppearance:$appearance)
                }
            }
            .transition(.offset(y:8).combined(with:.opacity))
            .animation(.timingCurve(0.16,1,0.3,1,duration:0.32),value:tab)
            PlinkLiquidTabBar(selection:$tab)
            if appearance { V4AppearanceView(theme:$theme,presented:$appearance).zIndex(25).transition(.opacity) }
        }.preferredColorScheme(.dark).tint(V4.accent)
        .task {
            await bootstrap()
        }
    }

    private func bootstrap() async {
        let api = APIClient(baseURL: "https://plink-backend-production-ef31.up.railway.app/api")
        let rs = RoomService(api: api)
        let fm = FriendManager(api: api)
        let as_ = AuthService(api: api)
        roomsStore = V4RoomsStore(roomService: rs)
        friendsStore = V4FriendsStore(friendManager: fm)
        profileStore = V4ProfileStore(authService: as_)

        await roomsStore?.load()
        await searchStore.loadTrending()
        await friendsStore?.load()
        await profileStore?.load()
    }
}

// MARK: - Liquid Glass Tab Bar (GPT-5.6 Post-V4)

struct PlinkLiquidTabBar: View {
    @Binding var selection: Int
    @Namespace private var selectionNS

    private let items: [(String, String)] = [
        ("house.fill", "Главная"),
        ("circle.grid.2x2.fill", "Комнаты"),
        ("sparkles", "ИИ"),
        ("person.2.fill", "Друзья"),
        ("person.crop.circle.fill", "Профиль")
    ]

    var body: some View {
        content
            .padding(6)
            .background(.ultraThinMaterial)
            .background(V4.navBG.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(V4.line, lineWidth: 0.75)
            )
            .frame(height: 72)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityElement(children: .contain)
    }

    private var content: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                Button {
                    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.26)) {
                        selection = index
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[index].0)
                            .font(.system(size: 18, weight: .semibold))
                        Text(items[index].1)
                            .font(.system(size: 9.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == index ? V4.accent : V4.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if selection == index {
                            Capsule(style: .continuous)
                                .fill(V4.accent.opacity(0.11))
                                .matchedGeometryEffect(id: "selected-tab", in: selectionNS)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(items[index].1)
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
    }
}

// MARK: - Notification Bell (GPT-5.6 Post-V4)

struct NotificationInboxButton: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: unreadCount > 0 ? "bell.fill" : "bell")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(V4.ink)
                .frame(width: 46, height: 40)
                .background(V4.roundBG)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(V4.line, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(V4.accentInk)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(V4.accent)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Уведомления")
        .accessibilityValue(unreadCount == 0 ? "Нет новых" : "Новых: \(unreadCount)")
    }
}

// MARK: - Live Screen Variants (P0: Real backend data)

struct V4HomeViewLive: View {
    let theme: V4Theme
    @Bindable var searchStore: V4SearchStore
    var roomsStore: V4RoomsStore?
    let openRoom: () -> Void
    @State private var query = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack { V4Avatar(letter: "П", theme: theme); Spacer(); NotificationInboxButton(unreadCount: 0, action: {}) }
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                V4Heading(eyebrow: "СУББОТНИЙ ВЕЧЕР", title: "С кем смотрим?")
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.bottom,18)
                HStack(spacing:9) {
                    Image(systemName:"magnifyingglass")
                    TextField("Видео, сервис или комната", text:$query).foregroundStyle(V4.ink)
                        .onChange(of: query) { _, new in searchStore.search(new) }
                }.font(.system(size:13)).foregroundStyle(V4.muted).padding(.horizontal,13).frame(height:48)
                 .background(V4.searchBG).clipShape(RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(V4.line))
                 .padding(.horizontal,19).padding(.bottom,18)

                // Hero: first trending video
                if let hero = searchStore.trending.first {
                    V4Hero(title: hero.title, meta: "YouTube · \(hero.subtitle)", button: "▶ Смотреть вместе", height: 300, theme: theme, action: openRoom)
                        .padding(.horizontal,13).padding(.bottom,28)
                } else {
                    RoundedRectangle(cornerRadius: 29).fill(V4.cardBG).frame(height: 300).padding(.horizontal,13).padding(.bottom,28)
                        .overlay { ProgressView().tint(V4.accent) }
                }

                // Live rooms rail
                if let rs = roomsStore, !rs.rooms.isEmpty {
                    HStack { Text("Сейчас вместе").font(.system(size:18.24,weight:.bold)); Spacer(); Text("Все").font(.system(size:12.16)).foregroundStyle(V4.accent) }
                        .padding(.horizontal,19).padding(.bottom,12)
                    ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:11) {
                        ForEach(rs.rooms.prefix(6)) { room in
                            V4MediaCard(title: room.name, meta: "\(room.participantCount) участников\(room.isActive ? " · LIVE" : "")")
                        }
                    }.padding(.horizontal,19) }
                }

                // Trending rail
                if !searchStore.trending.isEmpty {
                    HStack { Text("Популярное на YouTube").font(.system(size:18.24,weight:.bold)); Spacer() }
                        .padding(.horizontal,19).padding(.top,28).padding(.bottom,12)
                    ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:11) {
                        ForEach(searchStore.trending.prefix(8)) { item in
                            V4MediaCard(title: item.title, meta: "\(item.subtitle)\(item.duration.map { " · \($0)" } ?? "")")
                        }
                    }.padding(.horizontal,19) }
                }
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
    }
}

struct V4RoomsViewLive: View {
    let theme: V4Theme
    var roomsStore: V4RoomsStore?
    let openRoom: () -> Void

    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                HStack(alignment:.top) {
                    V4Heading(eyebrow:"ОБЗОР",title:"Комнаты")
                    Spacer(); V4RoundButton(symbol:"⌕")
                }.padding(.horizontal,18).padding(.top,10).padding(.bottom,16)

                if let rs = roomsStore {
                    switch rs.state {
                    case .loading:
                        RoundedRectangle(cornerRadius: 29).fill(V4.cardBG).frame(height: 235).padding(.horizontal,13).padding(.bottom,28)
                            .overlay { ProgressView().tint(V4.accent) }
                    case .loaded:
                        if let hero = rs.heroRoom {
                            V4Hero(title: hero.name, meta: "\(hero.participantCount) зрителей · открытая комната", button:"Войти",height:235,theme:theme,action:openRoom)
                                .padding(.horizontal,13).padding(.bottom,28)
                        }
                        ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:11) {
                            ForEach(rs.railRooms) { room in
                                V4MediaCard(title: room.name, meta: "\(room.participantCount) участников")
                            }
                        }.padding(.horizontal,19) }
                    case .empty:
                        VStack(spacing:12) {
                            Image(systemName:"sparkles").font(.largeTitle).foregroundStyle(V4.accent)
                            Text("Нет активных комнат").font(.headline)
                            Text("Попросите ИИ подобрать или создать комнату").font(.subheadline).foregroundStyle(V4.muted)
                        }.padding(.top,60)
                    case .failed(let error):
                        VStack(spacing:12) {
                            Image(systemName:"exclamationmark.triangle").font(.largeTitle).foregroundStyle(V4.amber)
                            Text(error).font(.subheadline).foregroundStyle(V4.muted)
                            Button("Повторить") { Task { await roomsStore?.load() } }.foregroundStyle(V4.accent)
                        }.padding(.top,60)
                    case .idle:
                        Color.clear.frame(height:100)
                    }
                } else {
                    ProgressView().tint(V4.accent).padding(.top,60)
                }
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
    }
}

struct V4AIViewLive: View {
    let theme: V4Theme
    @Bindable var store: V4AIStore
    @State private var input = ""

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
                        Text(store.state).font(.system(size:11.52)).foregroundStyle(V4.muted)
                    }.padding(.bottom,13)
                }.frame(height:270)
                ScrollView(showsIndicators:false) {
                    VStack(alignment:.leading,spacing:8) {
                        ForEach(store.messages) { msg in
                            if msg.isBot {
                                VStack(alignment:.leading,spacing:3) {
                                    Text("PLINK AI").font(.system(size:13.28,weight:.bold))
                                    Text(msg.text).font(.system(size:13.28)).lineSpacing(5.31)
                                }.padding(.vertical,11).padding(.horizontal,13).background(V4.botBG)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                            } else {
                                Text(msg.text).font(.system(size:13.28)).padding(.vertical,11).padding(.horizontal,13)
                                    .background(V4.accent.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                    .frame(maxWidth: 280, alignment: .trailing)
                            }
                        }
                        HStack(spacing:7) {
                            chip("Очередь","Собери очередь"); chip("У друзей","Что смотрят друзья?"); chip("Комната","Создай комнату")
                        }
                    }.padding(.horizontal,16).padding(.top,8).padding(.bottom,92)
                }.background(LinearGradient(colors:[.clear,Color.oklch(0.06,0.01,190,alpha:0.76)],startPoint:UnitPoint(x:0.5,y:0.16),endPoint:.bottom))
            }.foregroundStyle(V4.ink)
            HStack(spacing:6) {
                Button("🎙") { }.frame(width:42,height:42).background(V4.raised).clipShape(RoundedRectangle(cornerRadius:14))
                TextField("Спроси про фильмы и комнаты",text:$input).foregroundStyle(V4.ink)
                Button("➤") {
                    Task { await store.send(input); input = "" }
                }.frame(width:42,height:42).background(V4.accent).foregroundStyle(V4.accentInk).clipShape(RoundedRectangle(cornerRadius:14))
            }.padding(8).frame(minHeight:62).background(V4.composerBG).clipShape(RoundedRectangle(cornerRadius:22))
             .overlay(RoundedRectangle(cornerRadius:22).stroke(V4.line)).padding(.horizontal,13).padding(.bottom,10)
        }
    }
    private func chip(_ label:String,_ prompt:String)->some View {
        Button(label){ input=prompt }.font(.system(size:11.52)).foregroundStyle(V4.ink).padding(.horizontal,11).frame(height:36)
            .background(V4.surface).clipShape(RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(V4.line))
    }
}

struct V4FriendsViewLive: View {
    let theme: V4Theme
    var store: V4FriendsStore?

    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                HStack(alignment:.top) { V4Heading(eyebrow:"ВМЕСТЕ ЛУЧШЕ",title:"Друзья"); Spacer(); V4RoundButton(symbol:"＋") }
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,16)

                if let s = store {
                    switch s.state {
                    case .loading:
                        ProgressView().tint(V4.accent).padding(.top,60)
                    case .loaded:
                        VStack(spacing:0) {
                            ForEach(s.friends) { friend in
                                HStack(spacing:11) {
                                    V4Avatar(letter:String(friend.username.prefix(1)),theme:theme,size:39)
                                    VStack(alignment:.leading,spacing:2) {
                                        Text(friend.username).font(.system(size:13.6,weight:.bold))
                                        Text(friend.isOnline ? "В сети" : "Не в сети").font(.system(size:11.52)).foregroundStyle(V4.muted)
                                    }
                                    Spacer()
                                    Button("Позвать"){}.font(.system(size:11.52)).foregroundStyle(V4.ink).padding(.horizontal,10).frame(height:35)
                                        .background(V4.surface).clipShape(RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).stroke(V4.line))
                                }.frame(minHeight:61).overlay(alignment:.bottom){ Rectangle().fill(V4.line).frame(height:1) }
                            }
                        }.padding(.horizontal,19)
                    case .empty:
                        VStack(spacing:12) {
                            Image(systemName:"person.2").font(.largeTitle).foregroundStyle(V4.accent)
                            Text("Друзей пока нет").font(.headline)
                            Text("Пригласите друзей, чтобы смотреть вместе").font(.subheadline).foregroundStyle(V4.muted)
                        }.padding(.top,60)
                    case .failed(let error):
                        Text(error).font(.subheadline).foregroundStyle(V4.muted).padding(.top,60)
                    case .idle:
                        Color.clear.frame(height:100)
                    }
                } else {
                    ProgressView().tint(V4.accent).padding(.top,60)
                }

                HStack { Text("Недавно вместе").font(.system(size:18.24,weight:.bold)); Spacer() }
                    .padding(.horizontal,19).padding(.top,26).padding(.bottom,12)
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:11) {
                    V4MediaCard(title:"Ночной рейс",meta:"вчера")
                    V4MediaCard(title:"Первый контакт",meta:"на неделе")
                }.padding(.horizontal,19) }
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
    }
}

struct V4ProfileViewLive: View {
    let theme: V4Theme
    var store: V4ProfileStore?
    @Binding var showAppearance: Bool

    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                HStack { V4Avatar(letter: String((store?.displayName.prefix(1) ?? "П")), theme: theme); Spacer(); V4RoundButton(symbol:"✎") }
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                V4Heading(eyebrow:"ПРОФИЛЬ",title: store?.displayName ?? "Загрузка…", subtitle: store?.isPremium == true ? "Plink+ активен" : nil)
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.bottom,18)
                groupTitle("Аккаунт")
                group([("person","Личные данные"), ("diamond","Приватность и безопасность")])
                groupTitle("Приложение")
                VStack(spacing:0) {
                    setting("circle.lefthalf.filled","Оформление", theme.name + " ›"){showAppearance=true}
                    setting("bell","Уведомления","›"){}
                    setting("play.fill","Воспроизведение","›"){}
                    setting("questionmark","Помощь","›"){}
                }.groupStyle()
                groupTitle("Безопасность")
                VStack(spacing:0) {
                    setting("nosign","Заблокированные","›"){}
                    setting("xmark","Удалить аккаунт","›",danger:true){}
                }.groupStyle()
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
    }
    private func groupTitle(_ s:String)->some View { Text(s.uppercased()).font(.system(size:10.56,weight:.heavy)).tracking(1.1616).foregroundStyle(V4.muted).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.vertical,9) }
    private func group(_ rows:[(String,String)])->some View { VStack(spacing:0){ ForEach(Array(rows.enumerated()),id:\.offset){_,r in setting(r.0,r.1,"›"){} } }.groupStyle() }
    private func setting(_ icon:String,_ title:String,_ trailing:String,danger:Bool=false,action:@escaping()->Void)->some View {
        Button(action:action){ HStack(spacing:11){ Image(systemName:icon).frame(width:30); Text(title).font(.system(size:13.6,weight:.bold)); Spacer(); Text(trailing).font(.system(size:11.52)).foregroundStyle(V4.muted) }.foregroundStyle(danger ? V4.danger : V4.ink).frame(minHeight:54).overlay(alignment:.bottom){Rectangle().fill(V4.line).frame(height:1)} }
    }
}
