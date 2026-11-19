import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var store: DownloadStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if store.jobs.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.jobs) { job in
                            DownloadRowView(job: job)
                        }
                        .onDelete(perform: store.remove)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("多线程下载")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("清理已完成") { store.clearCompleted() }
                        .disabled(store.jobs.allSatisfy { $0.state != .completed })
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddDownloadView()
                    .environmentObject(store)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
            Text("还没有下载任务")
                .font(.title3.weight(.semibold))
            Text("点右上角 + 添加链接，最多 16 个连接分片下载")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showAdd = true
            } label: {
                Label("添加下载", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

struct DownloadRowView: View {

    @ObservedObject var job: DownloadJob
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(job.url.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(job.state.title)
                    .font(.caption)
                    .foregroundStyle(color)
            }

            if job.total > 0 {
                ProgressView(value: job.progress)
                    .tint(color)
            } else {
                ProgressView()
                    .tint(color)
            }

            HStack(spacing: 12) {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                actionButtons
            }
        }
        .padding(.vertical, 8)
    }

    private var color: Color {
        switch job.state {
        case .completed: return .green
        case .failed: return .red
        case .paused: return .orange
        default: return .accentColor
        }
    }

    private var detailText: String {
        if job.total > 0 {
            let progress = "\(Formatters.bytes(job.received)) / \(Formatters.bytes(job.total))"
            if job.state == .running, job.speed > 0 {
                return progress + " · " + Formatters.speed(job.speed)
            }
            return progress
        }
        return Formatters.bytes(job.received)
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch job.state {
        case .running, .preparing:
            Button { job.pause() } label: {
                Image(systemName: "pause.circle")
            }
            .buttonStyle(.borderless)
        case .paused:
            Button { job.resume() } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
        case .completed:
            ShareLink(item: job.fileURL) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
        default:
            EmptyView()
        }

        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .confirmationDialog("删除这个任务？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除并移除文件", role: .destructive) {
                job.cancel()
                try? FileManager.default.removeItem(at: job.fileURL)
            }
        }
    }
}

enum Formatters {
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: max(0, value))
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        let value = formatter.string(fromByteCount: Int64(max(0, bytesPerSecond)))
        return value + "/s"
    }
}

#Preview {
    ContentView()
        .environmentObject(DownloadStore())
}
