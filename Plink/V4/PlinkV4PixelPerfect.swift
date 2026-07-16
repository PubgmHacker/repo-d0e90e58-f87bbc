// Plink/V4/PlinkV4PixelPerfect.swift — GPT-5.6 Pixel Perfect V4
// Module split: types live in sibling V4*.swift files (move-only refactor).
// This file keeps shared palette + Color helpers only.

import SwiftUI
import Foundation
import UserNotifications
import UIKit

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

