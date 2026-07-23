import Foundation
import AuthenticationServices
import CryptoKit
import Security

/// WHOOP OAuth 2.0 (authorization code + PKCE). Rotating refresh token'ı Keychain'de saklar.
@MainActor
final class WhoopAuth: NSObject, ObservableObject {
    static let shared = WhoopAuth()

    // WHOOP v2 uçları (developer.whoop.com)
    private let authURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    private let tokenURL = "https://api.prod.whoop.com/oauth/oauth2/token"
    private let scopes = "read:recovery read:cycles read:sleep read:workout read:profile read:body_measurement offline"

    // Secrets.swift'ten (kopyala: Secrets.example.swift). Kişisel kullanımda Keychain'de tutmak daha iyi.
    private var clientID: String { WhoopSecrets.clientID }
    private var clientSecret: String { WhoopSecrets.clientSecret }
    private var redirectURI: String { WhoopSecrets.redirectURI }   // ör. bearing://whoop-callback

    @Published var isConnected = false
    @Published var authError: String?

    private var codeVerifier: String = ""
    private let keychainKey = "whoop_token"

    override init() {
        super.init()
        isConnected = (loadToken() != nil)
    }

    // MARK: Bağlan (kullanıcı akışı)
    func connect() {
        codeVerifier = Self.randomString(64)
        let challenge = Self.codeChallenge(for: codeVerifier)
        var comp = URLComponents(string: authURL)!
        comp.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scopes),
            .init(name: "state", value: Self.randomString(16)),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = comp.url,
              let scheme = URL(string: redirectURI)?.scheme else { return }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
            guard let self else { return }
            if let error = error { Task { @MainActor in self.authError = error.localizedDescription }; return }
            guard let callback = callback,
                  let code = URLComponents(string: callback.absoluteString)?
                    .queryItems?.first(where: { $0.name == "code" })?.value else { return }
            Task { await self.exchangeCode(code) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    func disconnect() {
        deleteToken()
        isConnected = false
    }

    // MARK: Token değişimi
    private func exchangeCode(_ code: String) async {
        var req = URLRequest(url: URL(string: tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(redirectURI)",
            "client_id=\(clientID)",
            "client_secret=\(clientSecret)",
            "code_verifier=\(codeVerifier)",
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        await performTokenRequest(req)
    }

    /// Geçerli access token'ı döndürür; süresi geçtiyse refresh eder (rotating refresh token).
    /// Refresh BAŞARISIZSA eski (geçersiz) token'ı döndürmez — nil döner ki hata görünür olsun.
    func validAccessToken() async -> String? {
        guard let token = loadToken() else { isConnected = false; return nil }
        if token.isValid { return token.accessToken }
        guard let refresh = token.refreshToken else {
            authError = "Oturum süresi doldu — Whoop'a yeniden bağlan."
            isConnected = false
            return nil
        }
        var req = URLRequest(url: URL(string: tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refresh)",
            "client_id=\(clientID)",
            "client_secret=\(clientSecret)",
            "scope=offline",
        ].joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        switch await performTokenRequest(req) {
        case .ok:
            return loadToken()?.accessToken
        case .httpError(let code):
            // 400/401 → rotating refresh token artık geçersiz (kullanılmış/iptal); yeniden bağlanmak şart
            if code == 400 || code == 401 {
                authError = "Whoop oturumu yenilenemedi (HTTP \(code)) — yeniden bağlan."
                isConnected = false
            } else {
                authError = "Whoop token isteği başarısız (HTTP \(code))."
            }
            return nil
        case .network(let msg):
            authError = "Ağ hatası: \(msg)"
            return nil
        }
    }

    private enum TokenRequestResult { case ok, httpError(Int), network(String) }

    @discardableResult
    private func performTokenRequest(_ req: URLRequest) async -> TokenRequestResult {
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .network("HTTP yanıtı alınamadı") }
            guard (200..<300).contains(http.statusCode) else {
                authError = "Token isteği başarısız (HTTP \(http.statusCode))."
                return .httpError(http.statusCode)
            }
            struct TokenResp: Codable {
                let access_token: String
                let refresh_token: String?
                let expires_in: Double
            }
            let t = try JSONDecoder().decode(TokenResp.self, from: data)
            let token = WhoopToken(accessToken: t.access_token,
                                   refreshToken: t.refresh_token,
                                   expiresAt: Date().addingTimeInterval(t.expires_in))
            saveToken(token)
            isConnected = true
            authError = nil
            return .ok
        } catch {
            authError = "Token çözümleme hatası: \(error.localizedDescription)"
            return .network(error.localizedDescription)
        }
    }

    // MARK: PKCE yardımcıları
    private static func randomString(_ length: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }
    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: Keychain
    private func saveToken(_ token: WhoopToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
    private func loadToken() -> WhoopToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let token = try? JSONDecoder().decode(WhoopToken.self, from: data) else { return nil }
        return token
    }
    private func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension WhoopAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
