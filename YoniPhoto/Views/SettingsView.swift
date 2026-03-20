
//
//  SettingsView.swift
//  YoniPhoto
//
//  Created by 刘畅 on 2026/3/21.
//

import SwiftUI

struct SettingsView: View {
    @State private var apiKey = UserDefaults.standard.string(forKey: "qwen_api_key") ?? ""
    @State private var showClearConfirm = false
    @State private var showSavedToast = false
    
    var body: some View {
        NavigationStack {
            Form {
                // API 配置
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("通义千问 API Key", systemImage: "key.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        SecureField("sk-...", text: $apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                        
                        Button("保存") {
                            UserDefaults.standard.set(apiKey, forKey: "qwen_api_key")
                            showSavedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showSavedToast = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKey.isEmpty)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("AI 分析配置")
                } footer: {
                    Text("使用通义千问 VL Max 分析视频内容，价格便宜。API Key 仅存储在本地设备，不会上传到任何服务器。")
                }
                
                // 分析说明
                Section("分析说明") {
                    InfoRow(icon: "1.circle.fill", color: .blue, text: "从视频中提取3帧关键画面")
                    InfoRow(icon: "2.circle.fill", color: .blue, text: "发送给通义千问 VL Max 进行内容理解")
                    InfoRow(icon: "3.circle.fill", color: .blue, text: "生成标题、摘要、标签、关键词等")
                    InfoRow(icon: "4.circle.fill", color: .blue, text: "结果保存到本地，下次无需重复分析")
                }
                
                // 数据管理
                Section("数据管理") {
                    let analyzedCount = StorageService.shared.getAllAnalyzedItems().count
                    HStack {
                        Label("已分析视频", systemImage: "checkmark.circle")
                        Spacer()
                        Text("\(analyzedCount) 个")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("清除所有分析数据", systemImage: "trash")
                    }
                }
                
                // 关于
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("模型")
                        Spacer()
                        Text("Qwen VL Max")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .alert("确认清除", isPresented: $showClearConfirm) {
                Button("清除", role: .destructive) {
                    StorageService.shared.clearAll()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除所有视频分析结果，此操作不可撤销")
            }
            .overlay(alignment: .top) {
                if showSavedToast {
                    ToastView(message: "✅ API Key 已保存", type: .success)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(), value: showSavedToast)
        }
    }
}

struct InfoRow: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}
