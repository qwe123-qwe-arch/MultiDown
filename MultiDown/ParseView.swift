import SwiftUI
import WebKit

struct PanAccount: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
}

enum PanAccounts {
    static let all: [PanAccount] = [
        PanAccount(id: "quark", name: "夸克网盘", url: "https://pan.quark.cn/"),
        PanAccount(id: "uc", name: "UC网盘", url: "https://drive.uc.cn/"),
        PanAccount(id: "baidu", name: "百度网盘", url: "https://pan.baidu.com/"),
        PanAccount(id: "pan123", name: "123网盘", url: "https://www.123pan.com/"),
        PanAccount(id: "lanzou", name: "蓝奏云", url: "https://www.lanzou.com/")
    ]
}

struct WebLoginView: UIViewRepresentable {

    let urlString: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: PanAccount = PanAccounts.all[0]
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PanAccounts.all) { account in
                            Button {
                                selected = account
                            } label: {
                                Text(account.name)
                                    .font(.footnote)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selected.id == account.id ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                WebLoginView(urlString: selected.url)
                    .id(selected.id)
            }
            .navigationTitle("网盘登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

struct ParseView: View {

    @EnvironmentObject private var store: DownloadStore
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var loading = false
    @State private var output: ResolveOutput?
    @State private var errorMessage: String?
    @State private var selected: Set<UUID> = []
    @State private var showLogin = false
    @State private var connections = 8

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $input)
                        .frame(minHeight: 96)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        if let text = UIPasteboard.general.string { input = text }
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    }
                } header: {
                    Text("分享链接 / 直链")
                } footer: {
                    Text("整段分享文本直接粘进来，提取码会自动识别。支持抖音、快手、B站、微博、小红书、Pixiv、夸克、UC、百度、蓝奏云。")
                }

                Section {
                    Stepper(value: $connections, in: 1...512) {
                        HStack {
                            Text("下载线程")
                            Spacer()
                            Text("\(connections)").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("下载设置")
                }

                if loading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("正在解析…").foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }

                if let output = output {
                    Section {
                        ForEach(output.items) { item in
                            Button {
                                if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(item.id) ? Color.accentColor : Color.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).font(.subheadline).lineLimit(2)
                                        Text(item.url.host ?? "").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("\(output.platform) · \(output.items.count) 个文件")
                    } footer: {
                        if let note = output.note {
                            Text(note)
                        }
                    }

                    Section {
                        Button {
                            download(output)
                        } label: {
                            HStack {
                                Spacer()
                                Label("加入下载（\(selected.count)）", systemImage: "arrow.down.circle.fill")
                                Spacer()
                            }
                        }
                        .disabled(selected.isEmpty)
                    }
                }
            }
            .navigationTitle("解析下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("网盘登录") { showLogin = true }
                        Button("开始解析") { Task { await parse() } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showLogin) { LoginSheet() }
        }
    }

    private func parse() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        loading = true
        errorMessage = nil
        output = nil
        selected = []
        do {
            let result = try await LinkResolver.resolve(text)
            output = result
            selected = Set(result.items.map { $0.id })
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func download(_ result: ResolveOutput) {
        for item in result.items where selected.contains(item.id) {
            store.add(media: item, connections: connections)
        }
        dismiss()
    }
}
