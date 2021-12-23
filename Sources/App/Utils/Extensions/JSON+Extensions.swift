extension JSON {
    var homeConnectParsed: JSON {
        switch self {
        case .string(let string):
            return .string(string.homeConnectKeyValueParsed)
            
        default:
            return self
        }
    }
}
