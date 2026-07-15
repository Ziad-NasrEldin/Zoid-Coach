import Foundation
import Testing
@testable import ZoidCoachApp

private actor TodayLiveRefreshRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

@MainActor
@Test
func todayLiveRefreshRunsOnceForEachTickAndStopsWithoutAnotherRefresh() async {
    let (ticks, continuation) = AsyncStream<Void>.makeStream()
    let recorder = TodayLiveRefreshRecorder()
    let loop = TodayLiveRefreshLoop(makeTicks: { ticks })

    loop.start {
        await recorder.record()
    }
    #expect(loop.isRunning)
    #expect(await recorder.count == 0)

    continuation.yield()
    await waitForRefreshCount(1, recorder: recorder)
    #expect(await recorder.count == 1)

    loop.stop()
    #expect(!loop.isRunning)
    continuation.yield()
    await Task.yield()
    #expect(await recorder.count == 1)
    continuation.finish()
}

@MainActor
@Test
func todayLiveRefreshStartIsIdempotent() async {
    let (ticks, continuation) = AsyncStream<Void>.makeStream()
    let firstRecorder = TodayLiveRefreshRecorder()
    let duplicateRecorder = TodayLiveRefreshRecorder()
    let loop = TodayLiveRefreshLoop(makeTicks: { ticks })

    loop.start {
        await firstRecorder.record()
    }
    loop.start {
        await duplicateRecorder.record()
    }
    continuation.yield()
    await waitForRefreshCount(1, recorder: firstRecorder)

    #expect(await firstRecorder.count == 1)
    #expect(await duplicateRecorder.count == 0)
    loop.stop()
    continuation.finish()
}

private func waitForRefreshCount(
    _ expectedCount: Int,
    recorder: TodayLiveRefreshRecorder
) async {
    for _ in 0..<100 {
        if await recorder.count == expectedCount {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
