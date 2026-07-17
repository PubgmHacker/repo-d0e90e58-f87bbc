// Plink/V4/V4Components.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

struct V4Avatar: View {
    let letter: String
    let theme: V4Theme
    var size: CGFloat = 43
    var isPremium: Bool = false
    var isAdmin: Bool = false
    /// Optional remote photo — falls back to letter gradient when missing/failed.
    var imageURL: URL? = nil
    @State private var ringRotation: Double = 0
    var body: some View {
        let (_, c1, c2, _) = theme.colors
        ZStack {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        letterFallback(c1: c1, c2: c2)
                    }
                }
            } else {
                letterFallback(c1: c1, c2: c2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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

    private func letterFallback(c1: Color, c2: Color) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(letter)
                .font(.system(size: size == 43 ? 16 : 14, weight: .black))
                .foregroundStyle(V4.ink)
        }
    }
}

/// Resolves avatar URL from stored field or always-available `/users/:id/avatar` endpoint.
enum PlinkAvatarURL {
    static let apiBase = "https://plink-backend-production-ef31.up.railway.app"

    /// Bumped when friends list / profiles reload so AsyncImage refetches immediately.
    static var sessionBust: Int {
        get { UserDefaults.standard.integer(forKey: "plink.avatarSessionBust") }
        set { UserDefaults.standard.set(newValue, forKey: "plink.avatarSessionBust") }
    }

    static func bumpSessionBust() {
        sessionBust &+= 1
        NotificationCenter.default.post(name: .plinkAvatarsDidChange, object: sessionBust)
    }

    /// Always bind avatar to a concrete userId so one person's photo/letter
    /// never leaks onto another friend's row or chat bubble.
    static func resolve(userId: String?, stored: String?, cacheBust: Bool = true) -> URL? {
        var raw = ""
        if let userId, !userId.isEmpty {
            // Prefer canonical per-user endpoint (authoritative).
            raw = "\(apiBase)/api/users/\(userId)/avatar"
        } else {
            raw = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.hasPrefix("/") {
                raw = apiBase + raw
            }
        }
        guard !raw.isEmpty, var components = URLComponents(string: raw) else { return nil }
        if cacheBust {
            // Session bust only (NOT a 10s time bucket) — avoids avatar URL
            // changing every few seconds and flashing letter placeholders.
            var items = components.queryItems ?? []
            items.removeAll { $0.name == "v" || $0.name == "b" }
            items.append(URLQueryItem(name: "b", value: "\(sessionBust)"))
            components.queryItems = items
        }
        return components.url
    }

    /// Stable URL for chat bubbles / headers — never auto-bust.
    static func stable(userId: String?, stored: String?) -> URL? {
        resolve(userId: userId, stored: stored, cacheBust: false)
    }

    /// Letter for placeholder: strip @, use first unicode scalar uppercased.
    static func letter(from name: String?) -> String {
        var t = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("@") { t = String(t.dropFirst()) }
        guard let ch = t.first else { return "?" }
        return String(ch).uppercased()
    }
}

extension Notification.Name {
    static let plinkAvatarsDidChange = Notification.Name("plink.avatarsDidChange")
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



