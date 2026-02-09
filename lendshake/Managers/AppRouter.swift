import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Route: Equatable {
        case loan(loanID: UUID, paymentID: UUID?)
    }

    private(set) var pendingRoute: Route?

    private init() {}

    func enqueue(route: Route) {
        pendingRoute = route
    }

    func consumeRoute() -> Route? {
        defer { pendingRoute = nil }
        return pendingRoute
    }

    func handle(url: URL) {
        guard let route = Self.parse(url: url) else { return }
        enqueue(route: route)
    }

    static func parse(url: URL) -> Route? {
        guard let scheme = url.scheme?.lowercased(), scheme == "lendshake" else {
            return nil
        }

        // Supports:
        // lendshake://loan/<loan_id>?payment_id=<payment_id>
        // lendshake://loan?loan_id=<loan_id>&payment_id=<payment_id>
        if url.host?.lowercased() == "loan" {
            let pathLoanID = url.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let queryLoanID = components?.queryItems?.first(where: { $0.name == "loan_id" })?.value
            let rawLoanID = pathLoanID.isEmpty ? queryLoanID : pathLoanID

            guard let rawLoanID, let loanID = UUID(uuidString: rawLoanID) else { return nil }
            let paymentID = components?.queryItems?
                .first(where: { $0.name == "payment_id" })?
                .value
                .flatMap(UUID.init(uuidString:))

            return .loan(loanID: loanID, paymentID: paymentID)
        }

        return nil
    }
}
