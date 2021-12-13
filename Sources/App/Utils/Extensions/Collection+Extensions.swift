import Foundation

extension Collection {
    var selfIfNotEmpty: Self? {
        guard !isEmpty else {
            return nil
        }
        return self
    }
}
