// Plink/V4/V4AppearanceView.swift — split from PlinkV4PixelPerfect (move-only, no logic change)
// Source of truth: V4 design module. Do not change visuals.

import SwiftUI
import PhotosUI
import UIKit
import Foundation

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



