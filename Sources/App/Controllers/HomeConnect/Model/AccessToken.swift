import Foundation

struct AccessToken {
    var token: String
    var expires: Date
    
    var needsRefresh: Bool {
        return Date() >= expires - 60 * 5
    }
}
