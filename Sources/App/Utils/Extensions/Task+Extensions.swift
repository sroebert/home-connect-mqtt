import Foundation
import NIOCore

extension Task where Success == Never, Failure == Never {
    public static func sleep(for timeAmount: TimeAmount) async {
        guard timeAmount.nanoseconds >= 0 else {
            fatalError("Cannot sleep a negative amount")
        }
        
        await sleep(UInt64(timeAmount.nanoseconds))
    }
}
