import SwiftUI
import UIKit

struct AddDownloadView: View {

    @EnvironmentObject private var store: DownloadStore
    @Environment(\.dismiss) private var dismiss

    @State private var urlString = ""
    @State private var fileName = ""
    @State private var connections = 8
    @State private var showsError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/file.zip", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        if let text = UIPasteboard.general.string {
                            urlString = text
                        }
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("下载链接")
                }

                Section {
                    Stepper(value: $connections, in: 1...16) {
                        HStack {
                            Text("连接数")
                            Spacer()
                            Text("\(connections)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("留空则使用服务器文件名", text: $fileName)
                        .autocorrectionDisabled()
                } header: {
                    Text("分片")
                } footer: {
                    Text("连接数越多越快，但部分服务器限制单 IP 并发，建议 4–8。不支持 Range 的服务器会自动退化为单连接。")
                }

                Section {
                    Button {
                        add()
                    } label: {
                        HStack {
                            Spacer()
                            Label("开始下载", systemImage: "arrow.down.circle.fill")
                            Spacer()
                        }
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("新建下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("链接无效", isPresented: $showsError) {
                Button("好", role: .cancel) {}
            } message: {
                Text("请填写以 http:// 或 https:// 开头的完整地址。")
            }
        }
    }

    private func add() {
        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.add(urlString: urlString, name: name.isEmpty ? nil : name, connections: connections) != nil {
            dismiss()
        } else {
            showsError = true
        }
    }
}

#Preview {
    AddDownloadView()
        .environmentObject(DownloadStore())
}
