import Fluent
import Vapor

struct OAuthController: RouteCollection {
    
    // MARK: - RouteCollection
    
    func boot(routes: RoutesBuilder) throws {
        routes.get("authorize") { request -> Response in
            let url = try request.homeConnectTokenAPI.authorizationURL
            return request.redirect(to: url.string)
        }
        
        routes.get("callback") { request -> View in
            guard
                request.query["grant_type"] == "authorization_code",
                let code: String = request.query["code"]
            else {
                return try await request.view.render("authorization-failed", [
                    "message": "Missing code"
                ])
            }
            
            try await request.homeConnectTokenAPI.processAuthorizationCode(code)
            return try await request.view.render("authorization-succeeded")
        }
    }
}
