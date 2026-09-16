import Foundation

/// A background agent with no window needs somewhere to explain itself when a
/// meeting does not raise an alert. One capped file in the usual place.
///
/// Not the unified log: `NSLog` interpolations come out as `<private>` there,
/// which makes it useless for exactly the question people ask.
enum Log {
    static let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("Logs/MeetingNudge.log")

    private static let stamp: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt
    }()

    private static let queue = DispatchQueue(label: "meetingnudge.log")

    static func write(_ message: String) {
        guard let url else { return }
        let line = "\(stamp.string(from: Date()))  \(message)\n"
        queue.async {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 128_000 {
                try? Data().write(to: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
