
//
//  MainTabView.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            VideoLibraryView()
                .tabItem {
                    Label("图库", systemImage: "photo.stack")
                }
            
            SearchView()
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
            
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    MainTabView()
}
