import Foundation
import Combine
import SwiftUI

final class DownloadStore: ObservableObject {

    @Published var jobs: [DownloadJob] = []

    @discardableResult
    func add(urlString: String, name: String? = nil, connections: Int = 8) -> DownloadJob? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else {
            return nil
        }
        let job = DownloadJob(url: url, name: name, connections: connections)
        jobs.insert(job, at: 0)
        job.start()
        return job
    }

    func remove(_ job: DownloadJob) {
        job.cancel()
        jobs.removeAll { $0.id == job.id }
    }

    func remove(at offsets: IndexSet) {
        for index in offsets {
            let job = jobs[index]
            job.cancel()
        }
        jobs.remove(atOffsets: offsets)
    }

    func clearCompleted() {
        jobs.removeAll { $0.state == .completed }
    }
}
