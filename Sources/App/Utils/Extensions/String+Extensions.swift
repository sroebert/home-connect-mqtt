extension String {
    var homeConnectKeyValueParsed: String {
        let lastComponent = split(separator: ".").last ?? Substring(self)
        return lastComponent.prefix(1).lowercased() + lastComponent.dropFirst()
    }
}
