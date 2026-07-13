import AppKit
import Foundation

struct ReleaseVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first?.lowercased() == "v" { value.removeFirst() }
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count),
              pieces.allSatisfy({ !$0.isEmpty && $0.count <= 9 && $0.allSatisfy(\.isNumber) }),
              pieces.allSatisfy({ Int($0) != nil }) else {
            return nil
        }
        components = pieces.map { Int($0)! }
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct GitHubRelease: Decodable, Equatable {
    let tagName: String
    let htmlURL: URL
    let name: String?
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name
        case publishedAt = "published_at"
    }

    var trustedURL: URL? {
        guard htmlURL.scheme?.lowercased() == "https",
              htmlURL.host?.lowercased() == "github.com",
              htmlURL.path.hasPrefix("/SaiBarathR/drag-timer/releases/") else {
            return nil
        }
        return htmlURL
    }
}

protocol UpdateTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionUpdateTransport: UpdateTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
}

final class UpdateChecker: ObservableObject {
    enum ResultState: Equatable {
        case idle
        case checking
        case current
        case available(GitHubRelease)
        case failed(String)
    }

    static let releasesPageURL = URL(string: "https://github.com/SaiBarathR/drag-timer/releases")!
    static let endpoint = URL(string: "https://api.github.com/repos/SaiBarathR/drag-timer/releases/latest")!

    @Published private(set) var state: ResultState = .idle

    private let settings: AppSettings
    private let transport: UpdateTransport
    private let currentVersion: ReleaseVersion
    private let now: () -> Date
    private let checkInterval: TimeInterval = 24 * 60 * 60

    init(
        settings: AppSettings,
        transport: UpdateTransport = URLSessionUpdateTransport(),
        currentVersionString: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
        now: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.transport = transport
        currentVersion = ReleaseVersion(currentVersionString) ?? ReleaseVersion("0.0.0")!
        self.now = now
        restoreCachedResult()
    }

    var availableRelease: GitHubRelease? {
        let release: GitHubRelease?
        if case let .available(value) = state {
            release = value
        } else {
            release = cachedAvailableRelease()
        }
        guard release?.tagName != settings.dismissedReleaseTag else { return nil }
        return release
    }

    func checkIfNeeded() async {
        guard settings.automaticallyChecksForUpdates else { return }
        if let lastCheck = settings.lastUpdateCheckAt,
           now().timeIntervalSince(lastCheck) < checkInterval {
            return
        }
        await check(manual: false)
    }

    func check(manual: Bool) async {
        guard state != .checking else { return }
        let previousState = state
        state = .checking
        settings.lastUpdateCheckAt = now()
        do {
            var request = URLRequest(url: Self.endpoint)
            request.timeoutInterval = 12
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            let (data, response) = try await transport.data(for: request)
            guard response.statusCode == 200 else { throw URLError(.badServerResponse) }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let release = try decoder.decode(GitHubRelease.self, from: data)
            guard release.trustedURL != nil,
                  let latestVersion = ReleaseVersion(release.tagName) else {
                throw URLError(.cannotParseResponse)
            }

            settings.cachedUpdateTag = release.tagName
            settings.cachedUpdateURLString = release.htmlURL.absoluteString
            if latestVersion > currentVersion {
                state = .available(release)
            } else {
                state = .current
            }
        } catch {
            state = manual ? .failed("Could not check for updates.") : previousState
        }
    }

    func dismissAvailableRelease() {
        guard let release = availableRelease else { return }
        settings.dismissedReleaseTag = release.tagName
        objectWillChange.send()
    }

    func openRelease(_ release: GitHubRelease? = nil) {
        NSWorkspace.shared.open(release?.trustedURL ?? availableRelease?.trustedURL ?? Self.releasesPageURL)
    }

    private func restoreCachedResult() {
        if let release = cachedAvailableRelease() {
            state = .available(release)
        }
    }

    private func cachedAvailableRelease() -> GitHubRelease? {
        guard let tag = settings.cachedUpdateTag,
              let version = ReleaseVersion(tag),
              version > currentVersion,
              let rawURL = settings.cachedUpdateURLString,
              let url = URL(string: rawURL) else { return nil }
        let release = GitHubRelease(tagName: tag, htmlURL: url, name: nil, publishedAt: nil)
        return release.trustedURL == nil ? nil : release
    }
}
