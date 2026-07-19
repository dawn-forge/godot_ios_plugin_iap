import XCTest
#if SWIFT_PACKAGE
@testable import DeferredFinishCore
#endif

final class DeferredFinishCoordinatorTests: XCTestCase {
    func test_verified_response_is_emitted_before_explicit_finish() async {
        let handle = FakeTransactionHandle(id: 42, productID: "coin_pack_3")
        let coordinator = DeferredFinishCoordinator()

        let events = await coordinator.receiveVerified(handle, jwsRepresentation: "signed")

        XCTAssertEqual(events, [.purchase(.init(transactionID: "42", productID: "coin_pack_3", productType: "Consumable", purchasedQuantity: 1, verified: true, jwsRepresentation: "signed"))])
        XCTAssertEqual(handle.finishCount, 0)

        let finishEvents = await coordinator.finishTransaction("42")

        XCTAssertEqual(finishEvents, [.finishSucceeded(transactionID: "42")])
        XCTAssertEqual(handle.finishCount, 1)
    }

    func test_unverified_transaction_is_not_cached_or_finished() async {
        let handle = FakeTransactionHandle(id: 43, productID: "coin_pack_3")
        let coordinator = DeferredFinishCoordinator()

        let events = await coordinator.receiveUnverified(handle, error: "signature invalid")

        XCTAssertEqual(events, [.purchase(.init(transactionID: "43", productID: "coin_pack_3", productType: "Consumable", purchasedQuantity: 1, verified: false, jwsRepresentation: nil, verificationError: "signature invalid"))])
        let finishEvents = await coordinator.finishTransaction("43")
        XCTAssertEqual(finishEvents, [.finishFailed(transactionID: "43", error: "unknown transactionID")])
        XCTAssertEqual(handle.finishCount, 0)
    }

    func test_finish_failure_keeps_id_keyed_cache_for_retry() async {
        let handle = FakeTransactionHandle(id: 44, productID: "coin_pack_10", finishErrors: ["network", nil])
        let coordinator = DeferredFinishCoordinator()
        _ = await coordinator.receiveVerified(handle, jwsRepresentation: "signed")

        let firstFinishEvents = await coordinator.finishTransaction("44")
        XCTAssertEqual(firstFinishEvents, [.finishFailed(transactionID: "44", error: "network")])
        let retryEvents = await coordinator.finishTransaction("44")
        XCTAssertEqual(retryEvents, [.finishSucceeded(transactionID: "44")])
        XCTAssertEqual(handle.finishCount, 2)
    }

    func test_cold_relaunch_scans_unfinished_by_transaction_id() async {
        let handle = FakeTransactionHandle(id: 45, productID: "coin_pack_30")
        let coordinator = DeferredFinishCoordinator(unfinished: { [handle] in [handle] })

        let finishEvents = await coordinator.finishTransaction("45")
        XCTAssertEqual(finishEvents, [.finishSucceeded(transactionID: "45")])
        XCTAssertEqual(handle.finishCount, 1)
    }

    func test_unmatched_and_malformed_ids_fail_closed() async {
        let handle = FakeTransactionHandle(id: 46, productID: "coin_pack_90")
        let coordinator = DeferredFinishCoordinator(unfinished: { [handle] in [handle] })

        let emptyIDEvents = await coordinator.finishTransaction("")
        XCTAssertEqual(emptyIDEvents, [.finishFailed(transactionID: "", error: "invalid transactionID")])
        let malformedIDEvents = await coordinator.finishTransaction("not-a-decimal-id")
        XCTAssertEqual(malformedIDEvents, [.finishFailed(transactionID: "not-a-decimal-id", error: "invalid transactionID")])
        let unknownIDEvents = await coordinator.finishTransaction("999")
        XCTAssertEqual(unknownIDEvents, [.finishFailed(transactionID: "999", error: "unknown transactionID")])
        XCTAssertEqual(handle.finishCount, 0)
    }

    func test_value_transaction_handle_conforms_to_finish_contract() async throws {
        let handle: any DeferredTransactionHandle = ValueTransactionHandle(id: 47, productID: "coin_pack_3")

        XCTAssertEqual(handle.id, 47)
        XCTAssertEqual(handle.productID, "coin_pack_3")
        try await handle.finish()
    }
}

private struct ValueTransactionHandle: DeferredTransactionHandle, Sendable {
    let id: UInt64
    let productID: String
    let productType = "Consumable"
    let purchasedQuantity = 1

    func finish() async throws {}
}

private final class FakeTransactionHandle: DeferredTransactionHandle, @unchecked Sendable {
    let id: UInt64
    let productID: String
    let productType = "Consumable"
    let purchasedQuantity = 1
    private var finishErrors: [String?]
    private(set) var finishCount = 0

    init(id: UInt64, productID: String, finishErrors: [String?] = []) {
        self.id = id
        self.productID = productID
        self.finishErrors = finishErrors
    }

    func finish() async throws {
        finishCount += 1
        if !finishErrors.isEmpty, let error = finishErrors.removeFirst() {
            throw NSError(domain: "StoreKit", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
        }
    }
}
