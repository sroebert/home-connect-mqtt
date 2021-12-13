import Foundation

extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool {
        switch self {
        case .none:
            return true
        case .some(let collection):
            return collection.isEmpty
        }
    }

    var selfIfNotNilOrEmpty: Wrapped? {
        switch self {
        case .none:
            return nil
        case .some(let collection):
            return collection.isEmpty ? nil : collection
        }
    }
}
