//
//  BackEndSetUp.swift
//  Budgetly
//
//  Created by Shakhnoza Mirabzalova on 8/27/25.
//

import Foundation
import Vapor

public func configure(_ app: Application) throws {
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // CORS so the iOS simulator / local tools can call you during dev
    let cors = CORSMiddleware(configuration:
        .init(allowedOrigin: .all,
              allowedMethods: [.GET, .POST, .OPTIONS],
              allowedHeaders: [.accept, .contentType, .origin, .authorization])
    )
    app.middleware.use(cors)

    try routes(app)
}

func routes(_ app: Application) throws {
    let plaid = PlaidClient(app: app)

    // 1) Create link_token for iOS Link flow
    app.post("create_link_token") { req async throws -> CreateLinkTokenResponse in
        let userId = "user-123" // <- your real user id
        return try await plaid.createLinkToken(clientUserId: userId)
    }

    // 2) Exchange public_token => access_token, then fetch last 30 days of transactions
    app.post("exchange_public_token") { req async throws -> TransactionsOut in
        let body = try req.content.decode(ExchangePublicTokenIn.self)
        let accessToken = try await plaid.exchangePublicToken(publicToken: body.public_token)

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end)!
        let tx = try await plaid.transactionsGet(
            accessToken: accessToken,
            startDate: start.plaidDate,
            endDate: end.plaidDate,
            count: 25
        )

        // Return a simplified shape to the app
        let items = tx.transactions.map {
            TransactionOut(name: $0.name,
                           amount: $0.amount,
                           date: $0.date,
                           merchant_name: $0.merchant_name,
                           account_id: $0.account_id)
        }
        return TransactionsOut(transactions: items)
    }
}

// MARK: - Models (only the fields we use)
struct CreateLinkTokenRequest: Content {
    let client_id: String
    let secret: String
    let client_name: String
    let user: [String: String]          // ["client_user_id": "..."]
    let language: String
    let country_codes: [String]
    let products: [String]
    let account_filters: [String: AnyEncodable]? // optional
}

struct CreateLinkTokenResponse: Content {
    let link_token: String
    let expiration: String?
    let request_id: String?
}

struct ItemPublicTokenExchangeRequest: Content {
    let client_id: String
    let secret: String
    let public_token: String
}

struct ItemPublicTokenExchangeResponse: Content {
    let access_token: String
    let item_id: String
    let request_id: String?
}

struct TransactionsGetRequest: Content {
    let client_id: String
    let secret: String
    let access_token: String
    let start_date: String   // "YYYY-MM-DD"
    let end_date: String
    let options: [String: AnyEncodable]?
}

struct PlaidTransaction: Content {
    let name: String
    let amount: Double
    let date: String
    let merchant_name: String?
    let account_id: String
}

struct TransactionsGetResponse: Content {
    let transactions: [PlaidTransaction]
    let request_id: String?
}

// Input/Output payloads for our endpoints
struct ExchangePublicTokenIn: Content { let public_token: String }

struct TransactionOut: Content {
    let name: String
    let amount: Double
    let date: String
    let merchant_name: String?
    let account_id: String
}
struct TransactionsOut: Content { let transactions: [TransactionOut] }

// MARK: - Plaid Client
struct PlaidClient {
    private let app: Application
    private let baseURL: String
    private let clientId: String
    private let secret: String
    private let appName: String

    init(app: Application) {
        self.app = app
        let env = Environment.get("PLAID_ENV") ?? "sandbox"
        self.baseURL = {
            switch env.lowercased() {
            case "sandbox": return "https://sandbox.plaid.com"
            case "development": return "https://development.plaid.com"
            case "production": return "https://production.plaid.com"
            default: return "https://sandbox.plaid.com"
            }
        }()
        self.clientId = Environment.get("PLAID_CLIENT_ID") ?? ""
        self.secret = Environment.get("PLAID_SECRET") ?? ""
        self.appName = Environment.get("PLAID_APP_NAME") ?? "My App"
    }

    // Create link_token
    func createLinkToken(clientUserId: String) async throws -> CreateLinkTokenResponse {
        let url = URI(string: "\(baseURL)/link/token/create")

        // Optional account filter (depository + credit)
        let filters: [String: AnyEncodable] = [
            "depository": AnyEncodable(["account_subtypes": AnyEncodable(["checking","savings"]) ]),
            "credit": AnyEncodable([:]),
        ]

        let payload = CreateLinkTokenRequest(
            client_id: clientId,
            secret: secret,
            client_name: appName,
            user: ["client_user_id": clientUserId],
            language: "en",
            country_codes: ["US"],
            products: ["transactions"],
            account_filters: filters
        )
        return try await post(url, payload, as: CreateLinkTokenResponse.self)
    }

    // Exchange public_token -> access_token
    func exchangePublicToken(publicToken: String) async throws -> String {
        let url = URI(string: "\(baseURL)/item/public_token/exchange")
        let payload = ItemPublicTokenExchangeRequest(
            client_id: clientId,
            secret: secret,
            public_token: publicToken
        )
        let resp = try await post(url, payload, as: ItemPublicTokenExchangeResponse.self)
        // Store resp.access_token per-user in your DB!
        return resp.access_token
    }

    // Fetch transactions
    func transactionsGet(accessToken: String,
                         startDate: String,
                         endDate: String,
                         count: Int = 25) async throws -> TransactionsGetResponse {
        let url = URI(string: "\(baseURL)/transactions/get")
        let payload = TransactionsGetRequest(
            client_id: clientId,
            secret: secret,
            access_token: accessToken,
            start_date: startDate,
            end_date: endDate,
            options: ["count": AnyEncodable(count)]
        )
        return try await post(url, payload, as: TransactionsGetResponse.self)
    }

    // Generic POST
    private func post<T: Content, R: Decodable>(_ url: URI, _ body: T, as: R.Type) async throws -> R {
        var req = ClientRequest(method: .POST, url: url, headers: HTTPHeaders([
            ("Content-Type", "application/json")
        ]))
        req.body = try .init(data: JSONEncoder().encode(body))
        let res = try await app.client.send(req)
        guard (200..<300).contains(res.status.code) else {
            let text = String(buffer: res.body ?? .init())
            app.logger.error("Plaid error: \(res.status) \(text)")
            throw Abort(.badRequest, reason: "Plaid error \(res.status)")
        }
        return try res.content.decode(R.self)
    }
}

// MARK: - Helpers
extension Date {
    var plaidDate: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}

// Type-erased encoder for dynamic JSON
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) { _encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
