/// 固定長のリングバッファ。容量を超えると古い値から捨てる。
public struct RingBuffer<Element: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [Element] = []
    private var start = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[start] = element
            start = (start + 1) % capacity
        }
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        start = 0
    }

    /// 古い順。
    public var elements: [Element] {
        Array(storage[start...] + storage[..<start])
    }
}
