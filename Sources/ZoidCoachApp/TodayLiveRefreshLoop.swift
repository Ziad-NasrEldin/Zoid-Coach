import Foundation

@MainActor
final class TodayLiveRefreshLoop {
    typealias TickStreamFactory = @Sendable () -> AsyncStream<Void>

    private let makeTicks: TickStreamFactory
    private var refreshTask: Task<Void, Never>?

    var isRunning: Bool {
        refreshTask != nil
    }

    init(
        interval: Duration = .seconds(15),
        makeTicks: TickStreamFactory? = nil
    ) {
        self.makeTicks = makeTicks ?? {
            Self.periodicTicks(every: interval)
        }
    }

    func start(refresh: @escaping @MainActor @Sendable () async -> Void) {
        guard refreshTask == nil else { return }
        let ticks = makeTicks()
        refreshTask = Task {
            for await _ in ticks {
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    deinit {
        refreshTask?.cancel()
    }

    nonisolated private static func periodicTicks(
        every interval: Duration
    ) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let producer = Task {
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(for: interval)
                        guard !Task.isCancelled else { break }
                        continuation.yield()
                    }
                } catch is CancellationError {
                    // Cancellation is the normal stop path.
                } catch {
                    assertionFailure("Unexpected Today refresh timer failure: \(error)")
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                producer.cancel()
            }
        }
    }
}
