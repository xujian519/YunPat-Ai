import Foundation

public protocol KnowledgeEventObserver: Sendable {
    func vaultChanged(_ path: URL)
    func indexChanged(_ module: WikiModule)
}

public final class VaultObserver: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let vaultPath: URL
    private let observer: KnowledgeEventObserver
    private let queue = DispatchQueue(label: "yunpat.vault-observer")

    public init(vaultPath: URL, observer: KnowledgeEventObserver) {
        self.vaultPath = vaultPath; self.observer = observer
    }

    public func start() {
        let paths = [vaultPath.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, numEvents, eventPaths, _, _) in
                guard let info = info else { return }
                let myself = Unmanaged<VaultObserver>.fromOpaque(info).takeUnretainedValue()
                myself.handleEvents(numEvents: numEvents, eventPaths: eventPaths)
            },
            &context, paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )
        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    public func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handleEvents(numEvents: Int, eventPaths: UnsafeMutableRawPointer) {
        let ptr = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
        var paths: [String] = []
        for i in 0..<numEvents {
            if let cString = ptr[i] { paths.append(String(cString: cString)) }
        }
        if !paths.isEmpty { observer.vaultChanged(vaultPath) }
    }

    deinit { stop() }
}
