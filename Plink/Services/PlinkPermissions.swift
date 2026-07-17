// Plink/Services/PlinkPermissions.swift
// Central iOS permission prompts — photo library (avatar) + microphone (voice).
// System dialogs appear once per permission; we only call when the feature is used.

import Foundation
import Photos
import AVFoundation
import UIKit

@MainActor
enum PlinkPermissions {

    private enum Keys {
        static let didPromptPhotos = "plink.perm.photos.prompted"
        static let didPromptMic = "plink.perm.mic.prompted"
        static let postAuthPhotosNudge = "plink.perm.photos.postAuthNudge"
    }

    // MARK: - Photos (avatar / gallery)

    /// Current authorization for reading the photo library.
    static var photosStatus: PHAuthorizationStatus {
        if #available(iOS 14, *) {
            return PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
        return PHPhotoLibrary.authorizationStatus()
    }

    static var isPhotosAuthorized: Bool {
        let s = photosStatus
        if #available(iOS 14, *) {
            return s == .authorized || s == .limited
        }
        return s == .authorized
    }

    /// Request gallery access once — call when user taps «Выбрать из галереи» / change avatar.
    /// Returns true if app may present PhotosPicker.
    @discardableResult
    static func requestPhotosIfNeeded() async -> Bool {
        if isPhotosAuthorized { return true }

        UserDefaults.standard.set(true, forKey: Keys.didPromptPhotos)

        let status: PHAuthorizationStatus
        if #available(iOS 14, *) {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            status = await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization { cont.resume(returning: $0) }
            }
        }

        if #available(iOS 14, *) {
            return status == .authorized || status == .limited
        }
        return status == .authorized
    }

    /// After first successful login/registration — soft flag only.
    /// Actual system dialog still fires on first avatar gallery action (Apple HIG).
    static func markPostAuthSession() {
        // No auto system prompt here (would be rejected as unrelated to the moment).
        // Avatar sheet will request when user picks gallery.
        UserDefaults.standard.set(true, forKey: Keys.postAuthPhotosNudge)
    }

    static var shouldExplainPhotos: Bool {
        UserDefaults.standard.bool(forKey: Keys.postAuthPhotosNudge)
            && !isPhotosAuthorized
            && photosStatus == .notDetermined
    }

    // MARK: - Microphone (voice notes / room voice)

    static var isMicAuthorized: Bool {
        if #available(iOS 17.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }
        return AVAudioSession.sharedInstance().recordPermission == .granted
    }

    /// Request mic once — first voice note or room voice toggle.
    @discardableResult
    static func requestMicrophoneIfNeeded() async -> Bool {
        if isMicAuthorized { return true }

        UserDefaults.standard.set(true, forKey: Keys.didPromptMic)

        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    /// Open Settings when user previously denied.
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
