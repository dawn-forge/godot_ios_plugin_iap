import Foundation

public protocol DeferredTransactionHandle: Sendable {
    var id: UInt64 { get }
    var productID: String { get }
    var productType: String { get }
    var purchasedQuantity: Int { get }
    func finish() async throws
}

public struct DeferredPurchaseResponse: Equatable, Sendable {
    public let transactionID: String
    public let productID: String
    public let productType: String
    public let purchasedQuantity: Int
    public let verified: Bool
    public let jwsRepresentation: String?
    public let verificationError: String?

    public init(
        transactionID: String,
        productID: String,
        productType: String,
        purchasedQuantity: Int,
        verified: Bool,
        jwsRepresentation: String? = nil,
        verificationError: String? = nil
    ) {
        self.transactionID = transactionID
        self.productID = productID
        self.productType = productType
        self.purchasedQuantity = purchasedQuantity
        self.verified = verified
        self.jwsRepresentation = jwsRepresentation
        self.verificationError = verificationError
    }
}

public enum DeferredFinishEvent: Equatable, Sendable {
    case purchase(DeferredPurchaseResponse)
    case finishSucceeded(transactionID: String)
    case finishFailed(transactionID: String, error: String)
}

@available(iOS 15.0, macOS 10.15, *)
public actor DeferredFinishCoordinator {
    public typealias UnfinishedProvider = @Sendable () async -> [any DeferredTransactionHandle]

    private var pendingByID: [String: any DeferredTransactionHandle] = [:]
    private let unfinishedProvider: UnfinishedProvider
    private let unfinishedLookupTimeoutNanoseconds: UInt64

    public init(
        unfinished: @escaping UnfinishedProvider = { [] },
        unfinishedLookupTimeoutNanoseconds: UInt64 = 2_000_000_000
    ) {
        unfinishedProvider = unfinished
        self.unfinishedLookupTimeoutNanoseconds = unfinishedLookupTimeoutNanoseconds
    }

    public func receiveVerified(
        _ handle: any DeferredTransactionHandle,
        jwsRepresentation: String?
    ) -> [DeferredFinishEvent] {
        let transactionID = String(handle.id)
        pendingByID[transactionID] = handle
        return [
            .purchase(
                DeferredPurchaseResponse(
                    transactionID: transactionID,
                    productID: handle.productID,
                    productType: handle.productType,
                    purchasedQuantity: handle.purchasedQuantity,
                    verified: true,
                    jwsRepresentation: jwsRepresentation
                )
            )
        ]
    }

    public func receiveUnverified(
        _ handle: any DeferredTransactionHandle,
        error: String
    ) -> [DeferredFinishEvent] {
        [
            .purchase(
                DeferredPurchaseResponse(
                    transactionID: String(handle.id),
                    productID: handle.productID,
                    productType: handle.productType,
                    purchasedQuantity: handle.purchasedQuantity,
                    verified: false,
                    verificationError: error
                )
            )
        ]
    }

    public func finishTransaction(_ transactionID: String) async -> [DeferredFinishEvent] {
        guard let numericID = UInt64(transactionID), String(numericID) == transactionID else {
            return [.finishFailed(transactionID: transactionID, error: "invalid transactionID")]
        }

        if pendingByID[transactionID] == nil {
            let provider = unfinishedProvider
            let timeout = unfinishedLookupTimeoutNanoseconds
            let unfinishedHandles = await withTaskGroup(of: [any DeferredTransactionHandle]?.self) { group in
                group.addTask {
                    await provider()
                }
                group.addTask {
                    do {
                        try await Task.sleep(nanoseconds: timeout)
                    } catch {
                        return nil
                    }
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            for handle in unfinishedHandles ?? [] where String(handle.id) == transactionID {
                pendingByID[transactionID] = handle
                break
            }
        }

        guard let handle = pendingByID[transactionID] else {
            return [.finishFailed(transactionID: transactionID, error: "unknown transactionID")]
        }

        do {
            try await handle.finish()
            pendingByID.removeValue(forKey: transactionID)
            return [.finishSucceeded(transactionID: transactionID)]
        } catch {
            return [.finishFailed(transactionID: transactionID, error: error.localizedDescription)]
        }
    }
}
