import CryptoKit
import Foundation
import Security

protocol TandemDataSource: Sendable {
    func load(_ request: TandemSyncRequest) async throws -> TandemSyncResponse
}

extension TandemDataSource {
    func validate(_ credentials: TandemCredentials, timeZone: TimeZone = .current) async throws {
        // A successful login alone does not establish access to pump reports.
        _ = try await load(.init(tandem: credentials, minDate: nil, maxDate: nil,
                                 timeZoneIdentifier: timeZone.identifier))
    }
}

enum DirectTandemError: Error, LocalizedError, Equatable {
    case credentialsRejected, rateLimited, accessDenied, invalidResponse, unavailable, invalidWindow, noPump

    var errorDescription: String? {
        switch self {
        case .credentialsRejected: "Tandem did not accept this sign-in. Check your region and account details."
        case .rateLimited: "Tandem is limiting requests. Try again later."
        case .accessDenied: "Tandem did not grant access to pump reports for this account."
        case .invalidResponse: "Tandem returned an unexpected response. Try again later."
        case .unavailable: "PumpSync could not reach Tandem. Check your connection and try again."
        case .invalidWindow: "The requested pump data range is unavailable."
        case .noPump: "Tandem returned no pump for this account."
        }
    }
}

struct DirectTandemDataSource: TandemDataSource {
    private let configuration: @Sendable () -> URLSessionConfiguration
    private let now: @Sendable () -> Date

    init(configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration
        self.now = now
    }

    func load(_ request: TandemSyncRequest) async throws -> TandemSyncResponse {
        guard let region = TandemRegion(rawValue: request.tandem.region),
              !request.tandem.username.isEmpty, !request.tandem.password.isEmpty else {
            throw DirectTandemError.credentialsRejected
        }
        let now = now()
        let end = min(now, request.maxDate ?? now)
        let start = max(request.minDate ?? end.addingTimeInterval(-2 * 86400), now.addingTimeInterval(-14 * 86400))
        guard start <= end, let zone = TimeZone(identifier: request.timeZoneIdentifier ?? "UTC") else {
            throw DirectTandemError.invalidWindow
        }
        let endpoints = TandemEndpoints(region)
        do {
            for attempt in 0...1 {
                let settings = configuration()
                settings.httpShouldSetCookies = false
                settings.httpCookieStorage = nil
                settings.urlCredentialStorage = nil
                settings.urlCache = nil
                settings.requestCachePolicy = .reloadIgnoringLocalCacheData
                settings.timeoutIntervalForRequest = 30
                let session = URLSession(configuration: settings, delegate: StopTandemRedirects(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let connection = TandemConnection(endpoints: endpoints, session: session)
                let identity = try await connection.signIn(request.tandem)
                do {
                    let pumpData = try await connection.report("pumper", id: identity.pumperId, token: identity.token)
                    let pump = try TandemPumpReports.selectedPump(pumpData, zone: zone)
                    // The report query uses pump-local calendar days in a fixed wire format.
                    let pumpDay = Date.ISO8601FormatStyle(timeZone: zone).year().month().day()
                    let query = [
                        URLQueryItem(name: "pumperId", value: identity.pumperId),
                        URLQueryItem(name: "startDate", value: pumpDay.format(start) + "T00:00:00Z"),
                        URLQueryItem(name: "endDate", value: pumpDay.format(end) + "T23:59:59Z"),
                        URLQueryItem(name: "eventCodes", value: "3,20,21,64,65,66,279")
                    ]
                    let logs = try await connection.report("pump-logs", id: pump, token: identity.token, query: query)
                    let samples = try TandemPumpReports.samples(logs, pump: pump, zone: zone, window: start...end)
                    try Task.checkCancellation()
                    return .init(samples: samples, effectiveMinDate: start, effectiveMaxDate: end, dataSourceMode: .tandemSource)
                } catch TandemReportError.expiredToken where attempt == 0 {
                    continue
                }
            }
            throw DirectTandemError.accessDenied
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
            // URLError.userInfo can include a patient-bearing URL.
            throw DirectTandemError.unavailable
        } catch let error as DirectTandemError {
            throw error
        } catch TandemReportError.expiredToken {
            throw DirectTandemError.accessDenied
        } catch {
            throw DirectTandemError.invalidResponse
        }
    }
}

// The authorization redirect is inspected before any request follows it. Passwords,
// PKCE verifiers and bearer tokens can never be replayed across an HTTP redirect.
private final class StopTandemRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct TandemEndpoints {
    let accounts: URL
    let source: URL
    let callback: URL
    let clientID: String

    init(_ region: TandemRegion) {
        switch region {
        case .us:
            accounts = URL(string: "https://tdcservices.tandemdiabetes.com/accounts/api/")!
            source = URL(string: "https://source.tandemdiabetes.com/")!
            callback = URL(string: "https://sso.tandemdiabetes.com/auth/callback")!
            clientID = "0oa4wnbvtladeyVZX4h7"
        case .eu:
            accounts = URL(string: "https://tdcservices.eu.tandemdiabetes.com/accounts/api/")!
            source = URL(string: "https://source.eu.tandemdiabetes.com/")!
            callback = URL(string: "https://source.eu.tandemdiabetes.com/authorize/callback")!
            clientID = "1519e414-eeec-492e-8c5e-97bea4815a10"
        }
    }
}

private enum TandemReportError: Error { case expiredToken }

private struct TandemConnection {
    let endpoints: TandemEndpoints
    let session: URLSession

    func signIn(_ credentials: TandemCredentials) async throws -> (token: String, pumperId: String) {
        var login = URLRequest(url: endpoints.accounts.appending(path: "login"))
        login.httpMethod = "POST"
        login.setValue("application/json", forHTTPHeaderField: "Content-Type")
        login.httpBody = try JSONEncoder().encode(["username": credentials.username, "password": credentials.password])
        let (_, loginResponse) = try await send(login)
        try check(loginResponse, signingIn: true)
        // One private cookie jar for this authorization only. Capture Set-Cookie
        // explicitly before following a redirect. A URLProtocol transport or an
        // intercepted redirect may not populate the URLSession cookie jar.
        guard let cookies = URLSessionConfiguration.ephemeral.httpCookieStorage else { throw DirectTandemError.unavailable }
        storeCookies(from: loginResponse, in: cookies)

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw DirectTandemError.unavailable
        }
        let verifier = base64URL(Data(bytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let authorization = endpoints.accounts.appending(path: "connect/authorize").appending(queryItems: [
            .init(name: "client_id", value: endpoints.clientID), .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid profile email"), .init(name: "redirect_uri", value: endpoints.callback.absoluteString),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256")
        ])
        let code = try await authorizationCode(from: authorization, cookies: cookies)
        var tokenRequest = URLRequest(url: endpoints.accounts.appending(path: "connect/token"))
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let parameters = [
            "grant_type": "authorization_code", "client_id": endpoints.clientID, "code": code,
            "redirect_uri": endpoints.callback.absoluteString, "code_verifier": verifier
        ]
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let pairs = parameters.map { key, value in key + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }
        tokenRequest.httpBody = Data(pairs.joined(separator: "&").utf8)
        let (data, response) = try await send(tokenRequest)
        try check(response, signingIn: false)
        struct Tokens: Decodable { let access_token: String; let id_token: String }
        let tokens = try JSONDecoder().decode(Tokens.self, from: data)
        let parts = tokens.id_token.split(separator: ".", omittingEmptySubsequences: false)
        guard !tokens.access_token.isEmpty, parts.count == 3 else { throw DirectTandemError.invalidResponse }
        var encoded = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let claimsData = Data(base64Encoded: encoded),
              let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              let claim = claims.first(where: { ["pumperid", "pumper_id"].contains($0.key.lowercased()) }),
              let pumperId = claim.value as? String ?? (claim.value as? NSNumber)?.stringValue,
              !pumperId.isEmpty else { throw DirectTandemError.invalidResponse }
        return (tokens.access_token, pumperId)
    }

    private func storeCookies(from response: HTTPURLResponse, in storage: HTTPCookieStorage) {
        guard let url = response.url, let fields = response.allHeaderFields as? [String: String] else { return }
        let received = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        storage.setCookies(received, for: url, mainDocumentURL: url)
    }

    private func authorizationCode(from start: URL, cookies: HTTPCookieStorage) async throws -> String {
        var current = start
        for _ in 0..<6 {
            var request = URLRequest(url: current)
            request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: cookies.cookies(for: current) ?? [])
            let (_, response) = try await send(request)
            storeCookies(from: response, in: cookies)
            if !(300..<400).contains(response.statusCode) { try check(response, signingIn: false) }
            guard (300..<400).contains(response.statusCode), let location = response.value(forHTTPHeaderField: "Location"),
                  let target = URL(string: location, relativeTo: current)?.absoluteURL,
                  target.scheme == "https", target.port == nil || target.port == 443,
                  target.user == nil, target.password == nil else { throw DirectTandemError.invalidResponse }
            if target.host == endpoints.callback.host && target.path == endpoints.callback.path {
                let codes = URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "code" }
                guard codes?.count == 1, let code = codes?.first?.value, !code.isEmpty else {
                    throw DirectTandemError.accessDenied
                }
                return code
            }
            guard target.host == endpoints.accounts.host || target.host == endpoints.callback.host else {
                throw DirectTandemError.invalidResponse
            }
            current = target
        }
        throw DirectTandemError.invalidResponse
    }

    func report(_ name: String, id: String, token: String, query: [URLQueryItem] = []) async throws -> Data {
        guard !id.isEmpty, id != ".", id != "..", !id.contains("/") else { throw DirectTandemError.invalidResponse }
        let url = endpoints.source.appending(path: "api/reports/bff").appending(component: name).appending(component: id)
        var request = URLRequest(url: url.appending(queryItems: query))
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(String(endpoints.source.absoluteString.dropLast()), forHTTPHeaderField: "Origin")
        request.setValue(endpoints.source.absoluteString, forHTTPHeaderField: "Referer")
        for attempt in 0...2 {
            let (data, response) = try await send(request)
            if response.statusCode == 401 { throw TandemReportError.expiredToken }
            if attempt < 2 && [500, 502, 503, 504].contains(response.statusCode) {
                try await Task.sleep(for: .milliseconds(250 * (attempt + 1)))
                continue
            }
            if attempt < 2, response.statusCode == 429,
               let value = response.value(forHTTPHeaderField: "Retry-After"), let delay = Int(value), (0...10).contains(delay) {
                try await Task.sleep(for: .seconds(delay))
                continue
            }
            try check(response, signingIn: false)
            return data
        }
        throw DirectTandemError.unavailable
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw DirectTandemError.invalidResponse }
        return (data, response)
    }

    private func check(_ response: HTTPURLResponse, signingIn: Bool) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401, 403: throw signingIn ? DirectTandemError.credentialsRejected : DirectTandemError.accessDenied
        case 429: throw DirectTandemError.rateLimited
        case 500...599: throw DirectTandemError.unavailable
        default: throw DirectTandemError.invalidResponse
        }
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }
}
