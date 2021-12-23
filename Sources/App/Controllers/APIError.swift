import Vapor

enum APIError: Error {
    case notAuthorized
    case encodingError(Error)
    case connectionError(Error)
    case apiError(HTTPStatus)
}
