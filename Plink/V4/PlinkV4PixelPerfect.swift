// Plink/V4/PlinkV4PixelPerfect.swift — GPT-5.6 Pixel Perfect V4
// Auto-generated from PLINK_V4_PIXEL_PERFECT_FOR_GLM_5_2.md
// This is the SINGLE source of truth for V4 design.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

// MARK: - KeyboardObserver
@Observable
final class KeyboardObserver {
    @MainActor private(set) var isVisible: Bool = false
    private var showToken: NSObjectProtocol?
    private var hideToken: NSObjectProtocol?

    init() {
        let nc = NotificationCenter.default
        showToken = nc.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isVisible = true }
        }
        hideToken = nc.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isVisible = false }
        }
    }

    deinit {
        if let s = showToken { NotificationCenter.default.removeObserver(s) }
        if let h = hideToken { NotificationCenter.default.removeObserver(h) }
    }
}

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
        case .electric: return (.oklch(0.09,0.02,255), .oklch(0.60,0.22,258), .oklch(0.72,0.18,210), .oklch(0.62,0.20,270))
        case .ember: return (.oklch(0.10,0.025,45), .oklch(0.63,0.24,35), .oklch(0.75,0.20,78), .oklch(0.65,0.22,28))
        case .violet: return (.oklch(0.09,0.025,285), .oklch(0.58,0.24,285), .oklch(0.62,0.25,325), .oklch(0.72,0.18,310))
        case .plink: return (.oklch(0.09,0.02,190), .oklch(0.64,0.18,185), .oklch(0.50,0.22,258), .oklch(0.65,0.18,326))
        case .bloom: return (.oklch(0.10,0.03,320), .oklch(0.61,0.26,330), .oklch(0.62,0.26,15), .oklch(0.71,0.20,350))
        }
    }
    /// Primary accent color — used by AI orb glow, buttons, etc.
    var accentColor: Color { colors.1 }
    /// Secondary accent color.
    var secondaryAccent: Color { colors.3 }
    /// Button text color — black for light accents (ember), white for dark.
    var buttonTextColor: Color {
        switch self {
        case .ember: return .black
        default: return .white
        }
    }
}

// MARK: - Plink+ Live Themes
enum PlinkPlusLiveTheme: Int, CaseIterable, Identifiable {
    case aurora = 1, cosmos = 2, verdant = 3, magma = 4
    var id: Int { rawValue }
    var name: String { ["Aurora","Cosmos","Verdant","Magma"][rawValue-1] }
    var videoFileName: String? { "live_theme_\(name.lowercased())" }
    var colors: (Color, Color, Color, Color) {
        switch self {
        case .aurora: return (Color(red:40/255,green:15/255,blue:33/255), Color(red:252/255,green:99/255,blue:152/255), Color(red:224/255,green:72/255,blue:114/255), Color(red:182/255,green:48/255,blue:84/255))
        case .cosmos: return (Color(red:0,green:0,blue:0), Color(red:1/255,green:44/255,blue:237/255), Color(red:8/255,green:82/255,blue:242/255), Color(red:19/255,green:112/255,blue:252/255))
        case .verdant: return (Color(red:14/255,green:16/255,blue:11/255), Color(red:158/255,green:244/255,blue:89/255), Color(red:126/255,green:226/255,blue:99/255), Color(red:164/255,green:255/255,blue:131/255))
        case .magma: return (Color(red:0,green:0,blue:0), Color(red:174/255,green:0,blue:0), Color(red:142/255,green:0,blue:0), Color(red:105/255,green:0,blue:3/255))
        }
    }
    var accentColor: Color { colors.1 }
    var secondaryAccent: Color { colors.3 }
    var buttonTextColor: Color {
        switch self {
        case .verdant, .aurora: return .black
        default: return .white
        }
    }
    var closestStandardTheme: V4Theme {
        switch self { case .aurora: return .bloom; case .cosmos: return .electric; case .verdant: return .plink; case .magma: return .ember }
    }
    static func resolve(_ index: Int) -> PlinkPlusLiveTheme? { guard index >= 1, index <= 4 else { return nil }; return PlinkPlusLiveTheme(rawValue: index) }
}

struct PlinkPlusStaticGradient: View {
    let theme: PlinkPlusLiveTheme
    var body: some View {
        let (bg, c1, c2, c3) = theme.colors
        ZStack { bg; LinearGradient(colors:[c1.opacity(0.35),c2.opacity(0.25),c3.opacity(0.15)],startPoint:.topLeading,endPoint:.bottomTrailing); RadialGradient(colors:[.clear,bg.opacity(0.6)],center:.center,startRadius:0,endRadius:600) }.ignoresSafeArea().allowsHitTesting(false)
    }
}


// MARK: - Section

struct V4Avatar: View {
    let letter: String
    let theme: V4Theme
    var size: CGFloat = 43
    var isPremium: Bool = false
    var isAdmin: Bool = false
    @State private var ringRotation: Double = 0
    var body: some View {
        let (_, c1, c2, _) = theme.colors
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
            Text(letter)
                .font(.system(size: size == 43 ? 16 : 14, weight: .black))
                .foregroundStyle(V4.ink)
        }
        .frame(width: size, height: size)
        .overlay {
            if isAdmin {
                // Admin: rotating crimson ring — tight on the circle edge
                Circle()
                    .stroke(
                        AngularGradient(colors: [Color(red: 1, green: 0.2, blue: 0.3), Color(red: 0.9, green: 0.1, blue: 0.2), Color(red: 1, green: 0.3, blue: 0.4), Color(red: 1, green: 0.2, blue: 0.3)], center: .center),
                        lineWidth: 2.5
                    )
                    .rotationEffect(.degrees(ringRotation))
                    .onAppear {
                        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { ringRotation = 360 }
                    }
            } else if isPremium {
                // Premium: rotating theme gradient ring
                Circle()
                    .stroke(
                        AngularGradient(colors: [theme.accentColor, theme.secondaryAccent, theme.accentColor], center: .center),
                        lineWidth: 2.5
                    )
                    .rotationEffect(.degrees(ringRotation))
                    .onAppear {
                        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { ringRotation = 360 }
                    }
            }
            // No ring for regular users — clean circle
        }
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
    var liveThemeIndex: Int = 0
    var body: some View {
        let (_, c1, c2, _) = theme.colors
        // Use Plink+ colors if active
        let btnAccent = PlinkPlusLiveTheme.resolve(liveThemeIndex)?.accentColor ?? theme.accentColor
        let btnSecondary = PlinkPlusLiveTheme.resolve(liveThemeIndex)?.secondaryAccent ?? theme.secondaryAccent
        let btnText = PlinkPlusLiveTheme.resolve(liveThemeIndex)?.buttonTextColor ?? theme.buttonTextColor
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [c1, Color.oklch(0.10,0.02,190)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [c2, .clear], center: UnitPoint(x: 0.72, y: 0.22), startRadius: 0, endRadius: height * 0.42)
            LinearGradient(colors: [.clear, Color.oklch(0.06,0.01,190,alpha:0.95)], startPoint: UnitPoint(x:0.5,y:0.28), endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 26.4, weight: .bold)).foregroundStyle(V4.ink)
                Text(meta).font(.system(size: 13.12)).foregroundStyle(V4.muted)
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                        Text(button).font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundStyle(btnText)
                    .padding(.horizontal, 18).frame(height: 46)
                    .background(
                        ZStack {
                            LinearGradient(colors: [btnAccent.opacity(0.9), btnSecondary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: .center)
                        }
                    )
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: btnAccent.opacity(0.3), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
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
    // 3 orbs × 3 independent phases each (offset, scale, rotation) = chaotic
    @State private var p1a = false
    @State private var p1b = false
    @State private var p1c = false
    @State private var p2a = false
    @State private var p2b = false
    @State private var p2c = false
    @State private var p3a = false
    @State private var p3b = false
    @State private var p3c = false

    var body: some View {
        GeometryReader { g in
            let (c0, c1, c2, c3) = theme.colors
            ZStack {
                c0
                blob(c1, g, x: -0.35, y: -0.15, size: 0.85, blur: 36, opacity: 0.52,
                     dxA: 0.44, dyA: 0.30, scaleA: 1.14, rotA: 7,
                     pA: p1a, pB: p1b, pC: p1c)
                blob(c2, g, x:  0.45, y:  0.28, size: 0.68, blur: 34, opacity: 0.45,
                     dxA: -0.39, dyA: -0.21, scaleA: 0.92, rotA: -6,
                     pA: p2a, pB: p2b, pC: p2c)
                blob(c3, g, x:  0.12, y:  0.70, size: 0.82, blur: 34, opacity: 0.45,
                     dxA: 0.10, dyA: -0.30, scaleA: 1.12, rotA: 0,
                     pA: p3a, pB: p3b, pC: p3c)
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.10),
                    .init(color: Color.oklch(0.06,0.01,190,alpha:0.10), location: 0.36),
                    .init(color: Color.oklch(0.06,0.01,190,alpha:0.86), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: g.size.width * 1.3, height: g.size.height * 1.3)
            .offset(x: -g.size.width * 0.15, y: -g.size.height * 0.15)
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                // Each orb has 3 independent animations with different durations → chaotic
                // Orb 1: offset 5s, scale 7s, rotation 3s
                withAnimation(.timingCurve(0.4, 0, 0.6, 1, duration: 5).repeatForever(autoreverses: true)) { p1a = true }
                withAnimation(.timingCurve(0.3, 0, 0.7, 1, duration: 7).repeatForever(autoreverses: true)) { p1b = true }
                withAnimation(.timingCurve(0.5, 0, 0.5, 1, duration: 3).repeatForever(autoreverses: true)) { p1c = true }
                // Orb 2: offset 6s, scale 4s, rotation 8s (staggered start)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    withAnimation(.timingCurve(0.4, 0, 0.6, 1, duration: 6).repeatForever(autoreverses: true)) { p2a = true }
                    withAnimation(.timingCurve(0.3, 0, 0.7, 1, duration: 4).repeatForever(autoreverses: true)) { p2b = true }
                    withAnimation(.timingCurve(0.5, 0, 0.5, 1, duration: 8).repeatForever(autoreverses: true)) { p2c = true }
                }
                // Orb 3: offset 4s, scale 9s, rotation 5s (staggered start)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    withAnimation(.timingCurve(0.4, 0, 0.6, 1, duration: 4).repeatForever(autoreverses: true)) { p3a = true }
                    withAnimation(.timingCurve(0.3, 0, 0.7, 1, duration: 9).repeatForever(autoreverses: true)) { p3b = true }
                    withAnimation(.timingCurve(0.5, 0, 0.5, 1, duration: 5).repeatForever(autoreverses: true)) { p3c = true }
                }
            }
        }.ignoresSafeArea()
    }

    private func blob(_ color: Color, _ g: GeometryProxy, x: CGFloat, y: CGFloat,
                      size: CGFloat, blur: CGFloat, opacity: Double,
                      dxA: CGFloat, dyA: CGFloat, scaleA: CGFloat, rotA: Double,
                      pA: Bool, pB: Bool, pC: Bool) -> some View {
        let side = g.size.width * size
        return RoundedRectangle(cornerRadius: side * 0.48, style: .continuous)
            .fill(color).frame(width: side, height: side)
            .blur(radius: blur).opacity(opacity)
            .position(x: g.size.width * (x + 0.45), y: g.size.height * (y + 0.45))
            // 3 independent animations → position, scale, rotation never sync
            .offset(x: pA ? g.size.width * dxA : 0, y: pA ? g.size.height * dyA : 0)
            .scaleEffect(pB ? scaleA : 0.92)  // scale breathes independently
            .rotationEffect(.degrees(pC ? rotA : -rotA * 0.5))  // rotation oscillates independently
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
                V4Hero(title:"Afterglow", meta:"5 друзей уже смотрят. Подключайся сразу.", button:"Смотреть вместе", height:300, theme:theme, action:openRoom)
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

// V4ProfileView removed — use V4ProfileViewLive instead (wired to real screens)
extension View { func groupStyle()->some View { self.padding(.horizontal,13).background(V4.searchBG).clipShape(RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(V4.line)).padding(.horizontal,19).padding(.bottom,18) } }

struct V4AppearanceView: View {
    @Binding var theme: V4Theme
    @Binding var presented: Bool
    @State private var selectedLiveTheme: Int? = {
        let idx = UserDefaults.standard.integer(forKey: "plink.liveTheme")
        return idx > 0 ? idx : nil
    }()
    @State private var liveThemeIndex: Int = UserDefaults.standard.integer(forKey: "plink.liveTheme")
    private var plinkPlusActive: Bool { liveThemeIndex > 0 }

    var body: some View {
        ZStack {
            // Mirror root background logic
            if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) {
                if let vn = live.videoFileName {
                    MetalVideoBackground(videoName: vn, opacity: 0.45, overlayColor: .black, overlayOpacity: 0.55)
                } else { PlinkPlusStaticGradient(theme: live) }
            } else { V4LivingBackground(theme:theme) }
            ScrollView(showsIndicators:false) { VStack(spacing:0) {
                HStack { V4RoundButton(symbol:"‹"){presented=false}; Spacer(); Text("Оформление").font(.system(size:16,weight:.bold)); Spacer(); Color.clear.frame(width:43,height:43) }.padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                V4Heading(eyebrow:"СТАНДАРТНЫЕ",title:"Живая тема",subtitle:"Одна палитра, разные композиции во всём приложении.")
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.bottom,18)
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:10){ ForEach(V4Theme.allCases){ item in themeCard(item) } }.padding(.horizontal,19).padding(.bottom,15) }

                // Plink+ animated themes
                V4Heading(eyebrow:"PLINK+",title:"Анимированные темы",subtitle:"Живые видео-фоны. Только для Plink+.")
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.top,20).padding(.bottom,18)
                ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:10) {
                    ForEach(PlinkPlusLiveTheme.allCases) { live in liveThemeCard(live) }
                }.padding(.horizontal,19).padding(.bottom,15) }

                VStack(spacing:0) {
                    toggleRow("Живое движение","Следует системным настройкам",true)
                    toggleRow("Больше контраста","Усиливает подложки текста",false)
                    toggleRow("Темы комнат","Сохранённые пресеты",false)
                }.groupStyle()
            }}.foregroundStyle(V4.ink)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkLiveThemeChanged)) { n in
            if let i = n.object as? Int { liveThemeIndex = i; selectedLiveTheme = i > 0 ? i : nil }
        }
    }
    private func themeCard(_ item:V4Theme)->some View {
        let(c0,c1,c2,_)=item.colors
        let isSelected = (theme == item) && !plinkPlusActive
        return Button(action:{
            theme=item
            UserDefaults.standard.set(0, forKey: "plink.liveTheme")
            selectedLiveTheme = nil
            NotificationCenter.default.post(name: .plinkLiveThemeChanged, object: 0)
        }){
            ZStack(alignment:.bottomLeading){
                c0; RadialGradient(colors:[c1,.clear],center:UnitPoint(x:0.25,y:0.22),startRadius:0,endRadius:75); RadialGradient(colors:[c2,.clear],center:UnitPoint(x:0.78,y:0.75),startRadius:0,endRadius:80); Text(item.name).font(.system(size:10.72,weight:.heavy)).padding(9)
            }.frame(width:112,height:150).clipShape(RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(isSelected ? V4.ink : V4.line,lineWidth:isSelected ? 2:1))
        }
    }
    private func liveThemeCard(_ live: PlinkPlusLiveTheme) -> some View {
        let index = live.rawValue
        let (bg, c1, c2, c3) = live.colors
        return Button {
            selectedLiveTheme = index
            HapticManager.selection()
            UserDefaults.standard.set(index, forKey: "plink.liveTheme")
            theme = live.closestStandardTheme
            NotificationCenter.default.post(name: .plinkLiveThemeChanged, object: index)
        } label: {
            ZStack(alignment:.bottomLeading) {
                if let vn = live.videoFileName,
                   let url = Bundle.main.url(forResource: "\(vn)_preview", withExtension: "png", subdirectory: "LiveThemes"),
                   let data = try? Data(contentsOf: url),
                   let preview = UIImage(data: data) {
                    Image(uiImage: preview).resizable().scaledToFill()
                } else {
                    ZStack { bg; RadialGradient(colors:[c1,.clear],center:UnitPoint(x:0.25,y:0.22),startRadius:0,endRadius:75); RadialGradient(colors:[c2,.clear],center:UnitPoint(x:0.78,y:0.75),startRadius:0,endRadius:80); RadialGradient(colors:[c3,.clear],center:UnitPoint(x:0.5,y:0.5),startRadius:0,endRadius:60) }
                }
                Text(live.name).font(.system(size:10.72,weight:.heavy)).foregroundStyle(.white).padding(9)
                VStack {
                    HStack(spacing:2) { Image(systemName:"lock.fill").font(.system(size:8,weight:.bold)); Text("Plink+").font(.system(size:8,weight:.heavy)) }
                        .foregroundStyle(.yellow).padding(.horizontal,5).padding(.vertical,2).background(.black.opacity(0.5),in:Capsule()).padding(6)
                    Spacer()
                }
            }.frame(width:112,height:150).clipShape(RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(selectedLiveTheme == index ? V4.ink : V4.line,lineWidth:selectedLiveTheme == index ? 2:1))
        }
    }
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
    @State private var liveThemeIndex: Int = UserDefaults.standard.integer(forKey: "plink.liveTheme")

    // P0.2b: Unified WatchRoom presentation — single coordinator, single fullScreenCover
    @State private var roomCoordinator = RoomPresentationCoordinator()
    @State private var roomToPresent: Room?

    // P0: Real backend stores
    @State private var roomsStore: V4RoomsStore?
    @State private var searchStore = V4SearchStore()
    @State private var friendsStore: V4FriendsStore?
    @State private var aiStore = V4AIStore()
    @State private var profileStore: V4ProfileStore?
    @State private var showCreateRoom = false
    @State private var showJoinByCode = false

    var body: some View {
        ZStack(alignment:.bottom){
            // Plink+ video bg OR standard Canvas — mutually exclusive
            // .id() forces SwiftUI to recreate the view when theme changes
            if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) {
                if let vn = live.videoFileName {
                    MetalVideoBackground(videoName: vn, opacity: 0.55, overlayColor: .black, overlayOpacity: 0.45)
                        .id("bg-\(liveThemeIndex)")
                } else { PlinkPlusStaticGradient(theme: live) }
            } else {
                V4LivingBackground(theme:theme)
                    .id("bg-standard")
            }
            Group {
                // ZStack with opacity — keeps all tabs alive, no recreation lag
                V4HomeViewLive(theme:theme, searchStore:searchStore, roomsStore:roomsStore, openRoom:{ openFirstRoom() }, liveThemeIndex:liveThemeIndex)
                    .opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0)
                V4RoomsViewLive(theme:theme, roomsStore:roomsStore, openRoom:{ openFirstRoom() }, createRoom:{showCreateRoom=true}, joinByCode:{showJoinByCode=true})
                    .opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1)
                V4AIViewLive(theme:theme, store:aiStore)
                    .opacity(tab == 2 ? 1 : 0).allowsHitTesting(tab == 2)
                V4FriendsViewLive(theme:theme, store:friendsStore)
                    .opacity(tab == 3 ? 1 : 0).allowsHitTesting(tab == 3)
                V4ProfileViewLive(theme:theme, store:profileStore, showAppearance:$appearance)
                    .opacity(tab == 4 ? 1 : 0).allowsHitTesting(tab == 4)
            }
            .animation(.easeInOut(duration: 0.15), value: tab)
            PlinkLiquidTabBar(selection:$tab, theme:theme)
            if appearance { V4AppearanceView(theme:$theme,presented:$appearance).zIndex(25).transition(.opacity) }
        }.preferredColorScheme(.dark).tint(V4.accent)
        .task {
            if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { theme = live.closestStandardTheme }
            await bootstrap()
        }
        .onReceive(NotificationCenter.default.publisher(for: .plinkLiveThemeChanged)) { n in
            if let i = n.object as? Int { liveThemeIndex = i; if let l = PlinkPlusLiveTheme.resolve(i) { theme = l.closestStandardTheme } }
        }
        .sheet(isPresented: $showCreateRoom) {
            RoomCreationView(
                onRoomCreated: { newRoom in
                    showCreateRoom = false
                    HapticManager.roomJoined()
                    // Copy room code to clipboard for easy sharing
                    UIPasteboard.general.string = "Код комнаты Plink: \(newRoom.code)"
                    // P0.2b: room created → present WatchRoom directly
                    roomToPresent = newRoom
                    Task { await roomsStore?.load() }
                }
            )
            .environmentObject(APIClient.shared)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showJoinByCode) {
            JoinRoomSheet(
                onJoined: { room in
                    showJoinByCode = false
                    roomToPresent = room
                }
            )
            .environmentObject(APIClient.shared)
            .preferredColorScheme(.dark)
        }
        // P0.2b: single fullScreenCover for WatchRoom — handles both join and create
        .fullScreenCover(item: $roomToPresent) { room in
            WatchRoomContainer(room: room)
        }
    }

    /// Open the first available room from the rooms store (used by Home/Rooms tab).
    private func openFirstRoom() {
        guard let rs = roomsStore else { return }
        if let hero = rs.heroRoom {
            roomToPresent = hero
        } else if let first = rs.railRooms.first {
            roomToPresent = first
        }
    }

    /// Quick Room — one-tap create from first trending video.
    private func quickCreateRoom() async {
        guard let trending = searchStore.trending.first else { return }
        guard KeychainHelper.read(for: "rave_auth_token") != nil else { return }
        let videoId = trending.id
        let mediaItem = MediaItem(
            id: "https://www.youtube.com/embed/\(videoId)",
            title: trending.title,
            artist: nil,
            thumbnailURL: trending.artworkURL?.absoluteString,
            streamURL: "https://www.youtube.com/embed/\(videoId)",
            duration: nil,
            mediaType: .video,
            source: .youtube,
            videoId: videoId
        )
        let request = CreateRoomRequest(
            name: "\(trending.title)",
            maxParticipants: 4,
            mediaItem: mediaItem,
            privacy: .publicRoom,
            password: nil,
            hostName: AuthService.shared.currentUserValue?.username
        )
        do {
            let api = APIClient(baseURL: "https://plink-backend-production-ef31.up.railway.app/api")
            let room = try await RoomService(api: api).createRoom(request)
            await MainActor.run {
                HapticManager.roomJoined()
                PlinkAppDelegate.requestNotificationPermission()
                UIPasteboard.general.string = "Код комнаты Plink: \(room.code)"
                roomToPresent = room
                Task { await roomsStore?.load() }
            }
        } catch {}
    }

    /// Create room from a specific trending video.
    private func createRoomFromTrending(_ item: V4SearchResult) async {
        guard KeychainHelper.read(for: "rave_auth_token") != nil else { return }
        let videoId = item.id
        let mediaItem = MediaItem(
            id: "https://www.youtube.com/embed/\(videoId)",
            title: item.title,
            artist: nil,
            thumbnailURL: item.artworkURL?.absoluteString,
            streamURL: "https://www.youtube.com/embed/\(videoId)",
            duration: nil,
            mediaType: .video,
            source: .youtube,
            videoId: videoId
        )
        let request = CreateRoomRequest(
            name: item.title,
            maxParticipants: 4,
            mediaItem: mediaItem,
            privacy: .publicRoom,
            password: nil,
            hostName: AuthService.shared.currentUserValue?.username
        )
        do {
            let api = APIClient(baseURL: "https://plink-backend-production-ef31.up.railway.app/api")
            let room = try await RoomService(api: api).createRoom(request)
            await MainActor.run {
                HapticManager.roomJoined()
                PlinkAppDelegate.requestNotificationPermission()
                UIPasteboard.general.string = "Код комнаты Plink: \(room.code)"
                NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
            }
        } catch {}
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
    var theme: V4Theme = .electric
    @Namespace private var selectionNS
    private var activeSecondary: Color { let (_, c1, _, _) = theme.colors; return c1 }

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
                    HapticManager.selection()
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
                    .foregroundStyle(selection == index ? activeSecondary : V4.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if selection == index {
                            Capsule(style: .continuous)
                                .fill(activeSecondary.opacity(0.15))
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
                .frame(width: 43, height: 43)
                .background(V4.roundBG)
                .clipShape(Circle())
                .overlay(
                    Circle()
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

// MARK: - AutoScrollCarousel — continuous slow auto-scrolling horizontal carousel
struct AutoScrollCarousel<T: Identifiable, Content: View>: View {
    let items: [T]
    let cardWidth: CGFloat
    @ViewBuilder let content: (T) -> Content

    @State private var offset: CGFloat = 0
    @State private var displayLink: Timer?
    @State private var userDragging = false
    @State private var pauseUntil: Date = .distantPast
    @State private var dragStartOffset: CGFloat = 0
    @State private var lastTick: Date = .distantPast

    private let spacing: CGFloat = 11
    private let sidePadding: CGFloat = 19
    private let speed: CGFloat = 22
    private let pauseAfterUserDrag: TimeInterval = 4.0

    private var contentWidth: CGFloat {
        CGFloat(items.count) * cardWidth + CGFloat(max(0, items.count - 1)) * spacing + sidePadding * 2
    }

    var body: some View {
        GeometryReader { geo in
            let w = contentWidth
            HStack(spacing: spacing) {
                Color.clear.frame(width: sidePadding, height: 1)
                ForEach(items) { item in content(item).id(item.id) }
                Color.clear.frame(width: sidePadding, height: 1)
            }
            .frame(width: w, alignment: .leading)
            .offset(x: offset)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        userDragging = true
                        offset = dragStartOffset + value.translation.width
                        pauseUntil = Date().addingTimeInterval(pauseAfterUserDrag)
                    }
                    .onEnded { _ in
                        userDragging = false
                        if w > 0 { while offset <= -w { offset += w }; while offset > 0 { offset -= w } }
                        dragStartOffset = offset
                        pauseUntil = Date().addingTimeInterval(pauseAfterUserDrag)
                    }
            )
            .frame(width: geo.size.width, height: nil, alignment: .leading)
            .clipped()
        }
        .frame(height: 200)
        .onAppear { startAutoScroll() }
        .onDisappear { displayLink?.invalidate() }
    }

    private func startAutoScroll() {
        displayLink?.invalidate()
        lastTick = Date()
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            guard !userDragging else { lastTick = Date(); return }
            guard Date() > pauseUntil else { lastTick = Date(); return }
            let now = Date()
            let dt = CGFloat(now.timeIntervalSince(lastTick))
            lastTick = now
            offset -= speed * dt
            let w = contentWidth
            if w > 0 { while offset <= -w { offset += w }; while offset > 0 { offset -= w } }
            dragStartOffset = offset
        }
    }
}

// MARK: - Live Screen Variants (P0: Real backend data)

struct V4HomeViewLive: View {
    let theme: V4Theme
    @Bindable var searchStore: V4SearchStore
    var roomsStore: V4RoomsStore?
    let openRoom: () -> Void
    var liveThemeIndex: Int = 0
    @State private var query = ""
    @State private var showUnifiedSearch = false
    @State private var showNotificationsSoon = false

    // Theme-aware colors — use Plink+ theme colors if active, else standard
    private var activeAccent: Color {
        if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { return live.accentColor }
        return theme.accentColor
    }
    private var activeSecondary: Color {
        if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { return live.secondaryAccent }
        return theme.secondaryAccent
    }
    private var activeBtnText: Color {
        if let live = PlinkPlusLiveTheme.resolve(liveThemeIndex) { return live.buttonTextColor }
        return theme.buttonTextColor
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                HStack { V4Avatar(letter: "П", theme: theme, isPremium: PremiumStatusManager.shared.isPremium); Spacer(); NotificationInboxButton(unreadCount: 0, action: { showNotificationsSoon = true }) }
                    .padding(.horizontal,18).padding(.top,10).padding(.bottom,16)
                .alert("Уведомления", isPresented: $showNotificationsSoon) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Inbox будет доступен в следующем обновлении")
                }
                V4Heading(eyebrow: "СУББОТНИЙ ВЕЧЕР", title: "С кем смотрим?")
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.bottom,18)

                // Tappable search bar
                Button {
                    showUnifiedSearch = true
                } label: {
                    HStack(spacing:9) {
                        Image(systemName:"magnifyingglass")
                        Text("Видео, сервис или комната")
                            .foregroundStyle(V4.muted)
                        Spacer()
                    }
                    .font(.system(size:13))
                    .padding(.horizontal,13)
                    .frame(height:48)
                    .background(V4.searchBG)
                    .clipShape(RoundedRectangle(cornerRadius:16))
                    .overlay(RoundedRectangle(cornerRadius:16).stroke(V4.line))
                }
                .buttonStyle(.plain)
                .padding(.horizontal,19)
                .padding(.bottom,18)

                // Hero carousel — 3-5 trending videos as swipeable hero cards
                if !searchStore.trending.isEmpty {
                    TabView {
                        ForEach(searchStore.trending.prefix(5)) { item in
                            V4Hero(
                                title: item.title,
                                meta: "YouTube · \(item.subtitle)",
                                button: "Смотреть вместе",
                                height: 260,
                                theme: theme,
                                action: {
                                    HapticManager.impact(.medium)
                                    Task { await createRoomFromTrending(item) }
                                },
                                liveThemeIndex: liveThemeIndex
                            )
                            .padding(.horizontal, 13)
                        }
                        // Promotional banners
                        promoBanner(
                            title: "Смотрите вместе",
                            subtitle: "Создай комнату и пригласи друзей смотреть кино синхронно",
                            icon: "person.2.fill",
                            action: { NotificationCenter.default.post(name: .plinkRoomCreated, object: nil) }
                        )
                        .padding(.horizontal, 13)
                        promoBanner(
                            title: "Plink+ премиум",
                            subtitle: "Живые темы, анимированные эмодзи и эксклюзивные функции",
                            icon: "crown.fill",
                            isPremium: true,
                            action: { /* TODO: open paywall */ }
                        )
                        .padding(.horizontal, 13)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .frame(height: 280)
                    .padding(.bottom, 20)
                } else {
                    RoundedRectangle(cornerRadius: 26).fill(V4.cardBG).frame(height: 260).padding(.horizontal,13).padding(.bottom,20)
                        .overlay { ProgressView().tint(V4.accent) }
                }

                // "Популярное" — auto-scrolling carousel, bigger posters
                if !searchStore.trending.isEmpty {
                    HStack { Text("Популярное").font(.system(size:24,weight:.heavy)).foregroundStyle(V4.ink); Spacer() }
                        .padding(.horizontal,19).padding(.bottom,14)
                    AutoScrollCarousel(items: Array(searchStore.trending.prefix(10)), cardWidth: 250) { item in
                        trendingCard(item)
                    }
                    .padding(.bottom, 22)
                }

                // AUDIT: Quick Room — premium liquid glass button
                if !searchStore.trending.isEmpty {
                    Button {
                        HapticManager.impact(.medium)
                        if let first = searchStore.trending.first {
                            Task { await createRoomFromTrending(first) }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Быстрая комната")
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(activeBtnText)
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                        .background(
                            ZStack {
                                LinearGradient(
                                    colors: [activeAccent.opacity(0.9), activeSecondary.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .shadow(color: activeAccent.opacity(0.3), radius: 12, y: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 19)
                    .padding(.bottom, 18)
                }

                // Рекомендации — bigger cards, more prominent
                if searchStore.trending.count > 5 {
                    HStack { Text("Рекомендации").font(.system(size:22,weight:.heavy)).foregroundStyle(V4.ink); Spacer() }
                        .padding(.horizontal,19).padding(.bottom,12)
                    ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:12) {
                        ForEach(searchStore.trending.suffix(8)) { item in
                            recommendationCard(item)
                        }
                    }.padding(.horizontal,19) }
                    .padding(.bottom, 8)
                }

                // "Смотрят сейчас" — poster-based cards: video thumbnail + viewer count + host
                HStack(spacing:8) {
                    Circle().fill(V4.danger).frame(width:8,height:8)
                        .shadow(color: V4.danger.opacity(0.6), radius: 4)
                    Text("СМОТРЯТ СЕЙЧАС")
                        .font(.system(size:13,weight:.heavy))
                        .tracking(1.4)
                    Spacer()
                }
                .foregroundStyle(V4.danger)
                .padding(.horizontal,19).padding(.top,32).padding(.bottom,14)

                VStack(spacing:10) {
                    if let rs = roomsStore, case .loaded = rs.state, !rs.rooms.isEmpty {
                        ForEach(rs.rooms.prefix(5)) { room in
                            watchingNowCard(room)
                        }
                    } else {
                        // Placeholder cards — show even when no active rooms
                        ForEach(0..<2, id: \.self) { _ in
                            HStack(spacing:12) {
                                RoundedRectangle(cornerRadius:8)
                                    .fill(V4.cardBG)
                                    .frame(width:108,height:64)
                                    .overlay(
                                        Image(systemName:"film")
                                            .font(.system(size:18))
                                            .foregroundStyle(V4.muted)
                                    )
                                VStack(alignment:.leading,spacing:4) {
                                    RoundedRectangle(cornerRadius:4).fill(V4.cardBG).frame(width:160,height:13)
                                    RoundedRectangle(cornerRadius:3).fill(V4.cardBG.opacity(0.6)).frame(width:90,height:10)
                                    RoundedRectangle(cornerRadius:3).fill(V4.cardBG.opacity(0.4)).frame(width:60,height:9)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .frame(minHeight:88)
                            .background(V4.cardBG.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius:14,style:.continuous))
                        }
                    }
                }
                .padding(.horizontal,19)
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
        .sheet(isPresented: $showUnifiedSearch) {
            UnifiedSearchView(searchStore: searchStore, roomsStore: roomsStore, openRoom: {
                showUnifiedSearch = false
                openRoom()
            })
            .preferredColorScheme(.dark)
        }
    }

    /// Create room from a specific trending video — used by hero + quick room.
    @ViewBuilder
    private func watchingNowCard(_ room: Room) -> some View {
        Button {
            HapticManager.impact(.light)
            NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
        } label: {
            HStack(spacing: 12) {
                // Poster thumbnail — 16:9 with rounded corners + LIVE badge
                ZStack(alignment: .bottomLeading) {
                    if let thumbStr = room.mediaItem?.thumbnailURL, let url = URL(string: thumbStr) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                ZStack {
                                    Rectangle().fill(theme.accentColor.opacity(0.15))
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(theme.accentColor.opacity(0.7))
                                }
                            }
                        }
                    } else {
                        ZStack {
                            Rectangle().fill(theme.accentColor.opacity(0.15))
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(theme.accentColor.opacity(0.7))
                        }
                    }
                    if room.isActive {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(V4.danger, in: Capsule())
                            .padding(6)
                    }
                }
                .frame(width: 108, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(V4.line, lineWidth: 0.5)
                )

                // Room info column
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(V4.ink)
                        .lineLimit(2)
                    Text("Хост: \(room.hostName)")
                        .font(.system(size: 11))
                        .foregroundStyle(V4.muted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(room.participantCount)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(theme.buttonTextColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.accentColor.opacity(0.85), in: Capsule())
                        Text("\(room.participantCount)/\(room.maxParticipants)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(V4.muted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(V4.muted)
            }
            .padding(12)
            .frame(minHeight: 88)
            .background(V4.cardBG.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(room.isActive ? V4.danger.opacity(0.25) : V4.accent.opacity(0.08),
                            lineWidth: room.isActive ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// Promotional banner for hero carousel
    private func promoBanner(title: String, subtitle: String, icon: String, isPremium: Bool = false, action: @escaping () -> Void) -> some View {
        let bannerAccent = isPremium ? Color(hex: "#A855F7") : activeAccent
        let bannerSecondary = isPremium ? Color(hex: "#EC4899") : activeSecondary
        return Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Background gradient
                LinearGradient(
                    colors: [bannerAccent.opacity(0.3), Color.oklch(0.06, 0.01, 190)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // Glow accent
                RadialGradient(colors: [bannerSecondary.opacity(0.4), .clear], center: UnitPoint(x: 0.75, y: 0.25), startRadius: 0, endRadius: 180)
                // Dark fade at bottom for text readability
                LinearGradient(colors: [.clear, Color.oklch(0.06, 0.01, 190, alpha: 0.9)], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)

                VStack(alignment: .leading, spacing: 10) {
                    // Icon badge
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(bannerAccent.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                        if isPremium {
                            Text("Plink+")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "#A855F7"), in: Capsule())
                        }
                    }
                    Text(title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                    // CTA button
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                        Text(isPremium ? "Оформить" : "Создать")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .foregroundStyle(activeBtnText)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(
                        ZStack {
                            LinearGradient(colors: [bannerAccent.opacity(0.9), bannerSecondary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: .center)
                        }
                    )
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .shadow(color: bannerAccent.opacity(0.3), radius: 10, y: 4)
                }
                .padding(.horizontal, 19)
                .padding(.bottom, 18)
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
            .shadow(color: .black.opacity(0.40), radius: 27, y: 25)
        }
        .buttonStyle(.plain)
    }

    /// Trending card with thumbnail + title
    private func trendingCard(_ item: V4SearchResult) -> some View {
        let (_, _, _, accent) = theme.colors
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let url = item.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 14).fill(V4.cardBG)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 14).fill(V4.cardBG)
                }
                RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.05))
                Text("YouTube")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(8)
            }
            .frame(width: 250, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(V4.ink)
                .lineLimit(2)
                .frame(width: 250, alignment: .leading)
        }
    }

    /// Smaller card for Рекомендации
    private func recommendationCard(_ item: V4SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                if let url = item.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(V4.cardBG)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(V4.cardBG)
                }
                RoundedRectangle(cornerRadius: 10).fill(theme.accentColor.opacity(0.03))
            }
            .frame(width: 170, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(V4.ink)
                .lineLimit(2)
                .frame(width: 170, alignment: .leading)
        }
    }

    /// Create room from a trending video — posts .plinkRoomCreated so
    /// PlinkApprovedV4Root picks it up and presents WatchRoom.
    private func createRoomFromTrending(_ item: V4SearchResult) async {
        guard KeychainHelper.read(for: "rave_auth_token") != nil else { return }
        let videoId = item.id
        let mediaItem = MediaItem(
            id: "https://www.youtube.com/embed/\(videoId)",
            title: item.title, artist: nil,
            thumbnailURL: item.artworkURL?.absoluteString,
            streamURL: "https://www.youtube.com/embed/\(videoId)",
            duration: nil, mediaType: .video, source: .youtube, videoId: videoId
        )
        let request = CreateRoomRequest(
            name: item.title, maxParticipants: 4, mediaItem: mediaItem,
            privacy: .publicRoom, password: nil,
            hostName: AuthService.shared.currentUserValue?.username
        )
        do {
            let api = APIClient(baseURL: "https://plink-backend-production-ef31.up.railway.app/api")
            let room = try await RoomService(api: api).createRoom(request)
            await MainActor.run {
                HapticManager.roomJoined()
                PlinkAppDelegate.requestNotificationPermission()
                UIPasteboard.general.string = "Код комнаты Plink: \(room.code)"
                NotificationCenter.default.post(name: .plinkRoomCreated, object: room)
            }
        } catch {}
    }
}

struct V4RoomsViewLive: View {
    let theme: V4Theme
    var roomsStore: V4RoomsStore?
    let openRoom: () -> Void
    var createRoom: (() -> Void)? = nil
    var joinByCode: (() -> Void)? = nil

    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                HStack(alignment:.top) {
                    V4Heading(eyebrow:"ОБЗОР",title:"Комнаты")
                    Spacer()
                    Button {
                        HapticManager.selection()
                        joinByCode?()
                    } label: {
                        Image(systemName:"person.badge.plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(V4.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Войти по коду")
                    .padding(.trailing, 8)
                    Button {
                        HapticManager.selection()
                        createRoom?()
                    } label: {
                        Image(systemName:"plus.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(V4.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Создать комнату")
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
                        VStack(spacing:16) {
                            Image(systemName:"plus.app.fill")
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundStyle(V4.accent)
                            Text("Нет активных комнат").font(.headline)
                            Text("Создай свою комнату и пригласи друзей смотреть вместе").font(.subheadline).foregroundStyle(V4.muted)
                                .multilineTextAlignment(.center)
                            Button {
                                createRoom?()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                    Text("Создать комнату")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(V4.accent)
                                .clipShape(Capsule())
                            }
                        }.padding(.top,60).padding(.horizontal,24)
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

struct V4FriendsViewLive: View {
    let theme: V4Theme
    var store: V4FriendsStore?

    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                HStack(alignment:.top) { V4Heading(eyebrow:"ВМЕСТЕ ЛУЧШЕ",title:"Друзья"); Spacer(); V4RoundButton(symbol:"＋"){
                    HapticManager.impact(.light)
                    let username = AuthService.shared.currentUserValue?.username ?? ""
                    UIPasteboard.general.string = "Добавь меня в Plink! Мой ник: \(username)"
                } }
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
                                    Button{
                                        HapticManager.impact(.light)
                                        UIPasteboard.general.string = "Присоединяйся к Plink! Мой код: \(friend.username)"
                                    } label:{
                                        Text("Позвать").font(.system(size:11.52)).foregroundStyle(V4.ink).padding(.horizontal,10).frame(height:35)
                                    }
                                    .buttonStyle(.plain)
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
    @State private var currentAvatarURL: URL?

    @State private var showPersonalData = false
    @State private var showPrivacy = false
    @State private var showNotifications = false
    @State private var showPlayback = false
    @State private var showHelp = false
    @State private var showBlocked = false
    @State private var showDeleteAccount = false
    @State private var showAdminPanel = false
    @State private var showAvatarPicker = false
    @State private var showPremium = false

    private var isAdmin: Bool { store?.isAdmin == true }
    private var avatarURL: URL? { currentAvatarURL ?? store?.avatarURL }

    var body: some View {
        ScrollView(showsIndicators:false) {
            VStack(spacing:0) {
                // ── Header: avatar + name + username + badges ──
                HStack(spacing: 12) {
                    Button { showAvatarPicker = true } label: {
                        if let avatarURL {
                            AsyncImage(url: avatarURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                V4Avatar(letter: String((store?.displayName.prefix(1) ?? "П")), theme: theme, size: 64, isPremium: store?.isPremium == true, isAdmin: isAdmin)
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                        } else {
                            V4Avatar(letter: String((store?.displayName.prefix(1) ?? "П")), theme: theme, size: 64, isPremium: store?.isPremium == true, isAdmin: isAdmin)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Сменить аватар")

                    VStack(alignment: .leading, spacing: 3) {
                        // Name — admin gets red color
                        Text(store?.displayName ?? "Загрузка…")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(isAdmin ? Color(red:1,green:0.3,blue:0.4) : V4.ink)

                        if let username = store?.username, !username.isEmpty {
                            Text("@\(username)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(V4.muted)
                        }
                        // Email — show below username
                        if let email = store?.email, !email.isEmpty {
                            Text(email)
                                .font(.system(size: 12))
                                .foregroundStyle(V4.muted.opacity(0.7))
                        }

                        // Badges row
                        HStack(spacing: 6) {
                            if isAdmin {
                                Text("АДМИН")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(red:0.9,green:0.1,blue:0.2), in: Capsule())
                            }
                            if store?.isPremium == true {
                                Text("PLINK+")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: "#A855F7"), in: Capsule())
                            }
                        }
                        .padding(.top, 2)
                    }

                    Spacer()

                    Button {
                        showPersonalData = true
                    } label: {
                        Image(systemName:"pencil.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(V4.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Редактировать профиль")
                }
                .padding(.horizontal, 18)
                .padding(.top, 80)
                .padding(.bottom, 20)

                groupTitle("Аккаунт")
                VStack(spacing:0) {
                    setting("person","Личные данные","›"){showPersonalData = true}
                    setting("lock.shield","Приватность и безопасность","›"){showPrivacy = true}
                }.groupStyle()

                groupTitle("Подписка Плинк+")
                VStack(spacing:0) {
                    setting("crown.fill","Плинк+ премиум", store?.isPremium == true ? "Активен ›" : "Оформить ›"){showPremium = true}
                }.groupStyle()

                groupTitle("Приложение")
                VStack(spacing:0) {
                    let themeDisplayName = PlinkPlusLiveTheme.resolve(UserDefaults.standard.integer(forKey: "plink.liveTheme"))?.name ?? theme.name
                    setting("circle.lefthalf.filled","Оформление", themeDisplayName + " ›"){showAppearance=true}
                    setting("bell","Уведомления","›"){showNotifications = true}
                    setting("play.fill","Воспроизведение","›"){showPlayback = true}
                    setting("questionmark","Помощь","›"){showHelp = true}
                }.groupStyle()

                if isAdmin {
                    groupTitle("Администрирование")
                    VStack(spacing:0) {
                        setting("shield.lefthalf.filled","Админ-панель","›"){showAdminPanel = true}
                    }.groupStyle()
                }

                groupTitle("Безопасность")
                VStack(spacing:0) {
                    setting("nosign","Заблокированные","›"){showBlocked = true}
                    setting("xmark","Удалить аккаунт","›",danger:true){showDeleteAccount = true}
                    // Выйти — synchronous, guaranteed
                    Button {
                        AuthService.shared.signOutLocally()
                    } label: {
                        HStack(spacing:11) {
                            Image(systemName: "arrow.right.square.fill").frame(width:30)
                            Text("Выйти").font(.system(size:13.6,weight:.bold))
                            Spacer()
                            Text("›").font(.system(size:11.52)).foregroundStyle(V4.muted)
                        }
                        .foregroundStyle(V4.danger)
                        .frame(minHeight:48)
                        .overlay(alignment:.bottom){Rectangle().fill(V4.line).frame(height:1)}
                    }
                    .buttonStyle(.plain)
                }.groupStyle()
            }.padding(.bottom,92)
        }.foregroundStyle(V4.ink)
        .sheet(isPresented: $showPersonalData) {
            NavigationStack { PersonalDataView() }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack { PrivacySecurityView() }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showNotifications) {
            NavigationStack { NotificationsView() }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPlayback) {
            NavigationStack { PlaybackSettingsView() }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showHelp) {
            NavigationStack { HelpView() }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showBlocked) {
            NavigationStack { BlockedUsersView() }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showDeleteAccount) {
            NavigationStack { DeleteAccountView() }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAdminPanel) {
            AdminRootView().preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAvatarPicker) {
            AvatarPickerSheet(store: store, onAvatarChanged: { url in
                currentAvatarURL = url
            }).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showPremium) {
            PaywallView(onPurchase: { showPremium = false }, onRestore: { showPremium = false }, onDismiss: { showPremium = false })
                .preferredColorScheme(.dark)
        }
    }
    private func groupTitle(_ s:String)->some View { Text(s.uppercased()).font(.system(size:10.56,weight:.heavy)).tracking(1.1616).foregroundStyle(V4.muted).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,19).padding(.vertical,9) }
    private func setting(_ icon:String,_ title:String,_ trailing:String,danger:Bool=false,action:@escaping()->Void)->some View {
        Button(action:action){ HStack(spacing:11){ Image(systemName:icon).frame(width:30); Text(title).font(.system(size:13.6,weight:.bold)); Spacer(); Text(trailing).font(.system(size:11.52)).foregroundStyle(V4.muted) }.foregroundStyle(danger ? V4.danger : V4.ink).frame(minHeight:48).overlay(alignment:.bottom){Rectangle().fill(V4.line).frame(height:1)} }
    }
}

// MARK: - AvatarPickerSheet (P0.5: PhotosUI + color avatars)

struct AvatarPickerSheet: View {
    var store: V4ProfileStore?
    var onAvatarChanged: ((URL) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var uploading = false
    @State private var uploadError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var selectedDefault: String? = nil

    private let defaultAvatars = ["avatar_default", "avatar_blue", "avatar_purple"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable().scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Cinema2026.accent, lineWidth: 3))
                } else if let avatarURL = store?.avatarURL {
                    AsyncImage(url: avatarURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(V4.surface).frame(width: 120, height: 120)
                            .overlay(Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(V4.muted))
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Cinema2026.accent, lineWidth: 3))
                } else {
                    Circle().fill(V4.surface).frame(width: 120, height: 120)
                        .overlay(Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(V4.muted))
                        .overlay(Circle().stroke(Cinema2026.accent, lineWidth: 3))
                }

                // Default avatars — 3 JPG presets
                Text("Стандартные").font(.system(size: 13, weight: .bold)).foregroundStyle(V4.muted)
                HStack(spacing: 16) {
                    ForEach(defaultAvatars, id: \.self) { name in
                        Button {
                            selectedDefault = name
                            if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Avatars") ?? Bundle.main.url(forResource: name, withExtension: "jpg"),
                               let data = try? Data(contentsOf: url),
                               let img = UIImage(data: data) {
                                previewImage = img
                                Task { try? await uploadAvatar(img) }
                            }
                        } label: {
                            if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Avatars") ?? Bundle.main.url(forResource: name, withExtension: "jpg"),
                               let data = try? Data(contentsOf: url),
                               let img = UIImage(data: data) {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(selectedDefault == name ? Cinema2026.accent : V4.line, lineWidth: selectedDefault == name ? 3 : 1))
                            } else {
                                Circle()
                                    .fill(V4.surface)
                                    .frame(width: 64, height: 64)
                                    .overlay(Image(systemName: "person.fill").font(.system(size: 20)).foregroundStyle(V4.muted))
                                    .overlay(Circle().stroke(selectedDefault == name ? Cinema2026.accent : V4.line, lineWidth: selectedDefault == name ? 3 : 1))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Divider
                Rectangle().fill(V4.line).frame(height: 0.5).padding(.horizontal, 24)

                // PhotosPicker — gallery
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 8) {
                        if uploading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "photo.on.rectangle")
                        }
                        Text(uploading ? "Загрузка…" : "Выбрать из галереи")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Cinema2026.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)
                .disabled(uploading)
                .onChange(of: photoItem) { _, newItem in
                    Task { await loadPhoto(newItem) }
                }

                if let err = uploadError {
                    Text(err).font(.caption).foregroundStyle(Cinema2026.danger).padding(.horizontal, 24)
                }

                Spacer()

                Button("Готово") { dismiss() }
                    .font(.subheadline.bold())
                    .foregroundStyle(Cinema2026.accent)
                    .padding(.bottom, 24)
            }
            .padding(.top, 32)
            .background(Cinema2026.background.ignoresSafeArea())
            .navigationTitle("Аватар")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        uploading = true
        uploadError = nil
        defer { uploading = false }
        selectedDefault = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                uploadError = "Не удалось загрузить фото"
                return
            }
            guard let image = UIImage(data: data) else {
                uploadError = "Неверный формат изображения"
                return
            }
            let resized = resizeToSquare(image, size: 512)
            previewImage = resized
            try await uploadAvatar(resized)
        } catch {
            uploadError = "Ошибка: \(error.localizedDescription)"
        }
    }

    private func resizeToSquare(_ image: UIImage, size: CGFloat) -> UIImage {
        let originalSize = image.size
        let shortest = min(originalSize.width, originalSize.height)
        let offsetX = (originalSize.width - shortest) / 2
        let offsetY = (originalSize.height - shortest) / 2
        let cropRect = CGRect(x: offsetX, y: offsetY, width: shortest, height: shortest)
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else { return image }
        let cropped = UIImage(cgImage: cgImage)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            cropped.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    private func uploadAvatar(_ image: UIImage) async throws {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw URLError(.cannotDecodeContentData)
        }
        if jpegData.count > 2 * 1024 * 1024 {
            uploadError = "Изображение слишком большое (макс 2MB)"
            return
        }
        let base64 = jpegData.base64EncodedString()
        guard let url = URL(string: "https://plink-backend-production-ef31.up.railway.app/api/users/me/avatar") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.read(for: "rave_auth_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            uploadError = "Не авторизован. Войдите заново."
            return
        }
        // Use image/jpeg (not image/jpg) — backend regex accepts both
        let body: [String: Any] = ["avatar": "data:image/jpeg;base64,\(base64)"]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
            if let respBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let avatarURLString = respBody["avatarURL"] as? String,
               let avatarURL = URL(string: avatarURLString) {
                await MainActor.run {
                    store?.updateAvatarURL(avatarURL)
                    onAvatarChanged?(avatarURL)
                }
            }
        } else if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            uploadError = "Сессия истекла. Войдите заново."
        } else if let http = response as? HTTPURLResponse, http.statusCode == 500 {
            // Try to parse error message from backend
            if let respBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errMsg = respBody["error"] as? String {
                uploadError = "Ошибка: \(errMsg)"
            } else {
                uploadError = "Ошибка сервера (500). Попробуйте позже."
            }
        } else {
            uploadError = "Ошибка (\((response as? HTTPURLResponse)?.statusCode ?? 0))"
        }
    }
}

// MARK: - Missing types for V4 compatibility

// AI Orb State (used by V4 AI section)
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
extension PlinkAppDelegate {
    static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
}

// plinkLiveThemeChanged notification
extension Notification.Name {
    static let plinkLiveThemeChanged = Notification.Name("plinkLiveThemeChanged")
}
