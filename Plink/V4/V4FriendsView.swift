// Plink/V4/V4FriendsView.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

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



struct V4FriendsViewLive: View {
    let theme: V4Theme
    var store: V4FriendsStore?
    @State private var dmFriend: Friend?
    @State private var profileFriend: Friend?
    @State private var showCreateRoom = false
    @State private var watchWithFriend: Friend?

    var body: some View {
        NavigationStack {
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
                                        Button {
                                            profileFriend = friend
                                        } label: {
                                            V4Avatar(letter:String(friend.username.prefix(1)),theme:theme,size:39)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Профиль \(friend.username)")

                                        Button {
                                            dmFriend = friend
                                        } label: {
                                            VStack(alignment:.leading,spacing:2) {
                                                Text(friend.username).font(.system(size:13.6,weight:.bold)).foregroundStyle(V4.ink)
                                                Text(friend.isOnline ? "В сети · написать" : "Не в сети · написать")
                                                    .font(.system(size:11.52)).foregroundStyle(V4.muted)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Чат с \(friend.username)")

                                        Spacer()
                                        Button{
                                            HapticManager.impact(.light)
                                            watchWithFriend = friend
                                            showCreateRoom = true
                                        } label:{
                                            Text("Смотреть").font(.system(size:11.52)).foregroundStyle(V4.ink).padding(.horizontal,10).frame(height:35)
                                        }
                                        .buttonStyle(.plain)
                                        .background(V4.surface).clipShape(RoundedRectangle(cornerRadius:11)).overlay(RoundedRectangle(cornerRadius:11).stroke(V4.line))
                                        .accessibilityLabel("Смотреть вместе с \(friend.username)")
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
            .navigationDestination(item: $dmFriend) { friend in
                DMChatView(friend: friend)
                    .environmentObject(DMChatService(api: APIClient.shared))
            }
            .navigationDestination(item: $profileFriend) { friend in
                FriendProfileView(userId: friend.id, usernameHint: friend.username) {
                    watchWithFriend = friend
                    showCreateRoom = true
                }
            }
            .sheet(isPresented: $showCreateRoom) {
                RoomCreationView { _ in
                    showCreateRoom = false
                }
                .environmentObject(APIClient.shared)
            }
        }
    }
}


