// Plink/AppShell/PlinkAppShell.swift — Unified iOS/iPad/macOS shell
//
// PLINK_UNIFIED_IOS_MAC_CINEMATIC_PATCH §2: Unified shell

import SwiftUI

struct PlinkAppShell: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: AppSection = .home
    @State private var createPresented = false

    let dependencies: AppDependencies

    var body: some View {
        Group {
            #if os(macOS)
            PlinkSidebarShell(
                selection: $selection,
                createPresented: $createPresented,
                dependencies: dependencies
            )
            #else
            if horizontalSizeClass == .regular {
                PlinkSidebarShell(
                    selection: $selection,
                    createPresented: $createPresented,
                    dependencies: dependencies
                )
            } else {
                PlinkPhoneTabShell(
                    selection: $selection,
                    createPresented: $createPresented,
                    dependencies: dependencies
                )
            }
            #endif
        }
        .sheet(isPresented: $createPresented) {
            CreateRoomView()
        }
    }
}
