// Plink/V4/V4RoomsViewLive.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

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
                        // Join-by-code — NOT person.badge.plus (that’s “add friend”)
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(V4.accent)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Войти по коду комнаты")
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


