import Vapor

enum APIError: Error {
    case notAuthorized
    case connectionError(Error)
    case apiError(HTTPStatus)
}
