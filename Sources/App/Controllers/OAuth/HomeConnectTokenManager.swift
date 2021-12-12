actor HomeConnectTokenManager {
    
    // MARK: - Private Vars
    
    private var accessToken: AccessToken?
    private var refreshTokenTask: Task<AccessToken, Error>? = nil
    
    // MARK: - Public
    
    func invalidate() {
        accessToken = nil
    }
    
    func setAccessToken(_ accessToken: AccessToken) {
        self.accessToken = accessToken
    }
    
    func getAccessToken(refresh: @escaping () async throws -> AccessToken) async throws -> AccessToken {
        if let accessToken = accessToken, !accessToken.needsRefresh {
            return accessToken
        }

        let task = refreshTokenTask ?? Task {
            try await refresh()
        }
        self.refreshTokenTask = task
        return try await task.value
    }
}
