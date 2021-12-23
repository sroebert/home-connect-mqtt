import Vapor

extension HTTPMediaType {
    static let homeConnectJSONAPI = HTTPMediaType(
        type: "application",
        subType: "vnd.bsh.sdk.v1+json",
        parameters: ["charset": "utf-8"]
    )
}
