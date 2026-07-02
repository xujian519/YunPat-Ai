import XCTest
import YunPatCore

final class EventBusTests: XCTestCase {

    // MARK: - 基本 pub/sub

    func test_publish_receive() async throws {
        let bus = EventBus()
        let exp = expectation(description: "Received")

        let subId: UUID = await bus.subscribe { event in
            if case .taskStarted(let prompt) = event {
                XCTAssertEqual(prompt, "test")
                exp.fulfill()
            }
        }

        await bus.publish(.taskStarted(prompt: "test"))
        await fulfillment(of: [exp], timeout: 1.0)
        await bus.unsubscribe(subId)
    }

    // MARK: - 多订阅者

    func test_multipleSubscribers_allReceive() async {
        let bus = EventBus()
        let counter = TestCounter()

        _ = await bus.subscribe { _ in await counter.increment() }
        _ = await bus.subscribe { _ in await counter.increment() }
        _ = await bus.subscribe { _ in await counter.increment() }

        await bus.publish(.taskStarted(prompt: ""))
        let multiCount: Int = await counter.value
        XCTAssertEqual(multiCount, 3)
    }

    // MARK: - unsubscribe

    func test_unsubscribe_stopsReceiving() async {
        let bus = EventBus()
        let counter = TestCounter()

        let unsubId: UUID = await bus.subscribe { _ in await counter.increment() }
        await bus.publish(.taskStarted(prompt: ""))
        var afterSub: Int = await counter.value
        XCTAssertEqual(afterSub, 1)

        await bus.unsubscribe(unsubId)
        await bus.publish(.taskStarted(prompt: ""))
        afterSub = await counter.value
        XCTAssertEqual(afterSub, 1)
    }

    // MARK: - unsubscribeAll

    func test_unsubscribeAll() async {
        let bus = EventBus()
        let counter = TestCounter()

        _ = await bus.subscribe { _ in await counter.increment() }
        _ = await bus.subscribe { _ in await counter.increment() }

        await bus.unsubscribeAll()
        await bus.publish(.taskStarted(prompt: ""))
        let allCount: Int = await counter.value
        XCTAssertEqual(allCount, 0)
    }

    // MARK: - subscriberCount

    func test_subscriberCount() async {
        let bus = EventBus()
        var subCount: Int = await bus.subscriberCount
        XCTAssertEqual(subCount, 0)

        let id1: UUID = await bus.subscribe { _ in }
        subCount = await bus.subscriberCount
        XCTAssertEqual(subCount, 1)

        let id2: UUID = await bus.subscribe { _ in }
        subCount = await bus.subscriberCount
        XCTAssertEqual(subCount, 2)

        await bus.unsubscribe(id1)
        subCount = await bus.subscriberCount
        XCTAssertEqual(subCount, 1)
        await bus.unsubscribe(id2)
        subCount = await bus.subscriberCount
        XCTAssertEqual(subCount, 0)
    }

    // MARK: - 所有事件类型

    func test_allEventTypes_delivered() async {
        let bus = EventBus()
        let counter = TestCounter()

        _ = await bus.subscribe { _ in await counter.increment() }

        await bus.publish(.toolPreExecute(toolName: "read_file", callId: "1"))
        await bus.publish(.toolDenied(toolName: "write_file", reason: "权限不足"))
        await bus.publish(.toolPostExecute(toolName: "read_file", success: true))
        await bus.publish(.taskStarted(prompt: "hi"))
        await bus.publish(.taskCompleted(summary: "done"))
        await bus.publish(.budgetExceeded(limit: 200_000, actual: 250_000))
        await bus.publish(.errorOccurred(message: "crashed"))

        let typesCount: Int = await counter.value
        XCTAssertEqual(typesCount, 7)
    }
}

private actor TestCounter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}
