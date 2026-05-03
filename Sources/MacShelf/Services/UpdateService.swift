import AppKit
import Foundation

@MainActor
enum UpdateService {
    private static let repository = "burakboduroglu/macshelf"
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/\(repository)/releases/latest")!
    private static let fallbackVersion = "0.1.0"

    static func checkForUpdates() async {
        do {
            let release = try await fetchLatestRelease()
            let current = currentVersion
            if isVersion(release.version, newerThan: current) {
                let shouldInstall = showUpdateAvailable(latest: release, current: current)
                if shouldInstall {
                    await downloadAndOpenInstaller(for: release)
                }
            } else {
                showMessage(
                    title: "MacShelf is up to date",
                    message: "You are running version \(current)."
                )
            }
        } catch {
            showMessage(
                title: "Could not check for updates",
                message: "MacShelf could not reach the GitHub releases feed. Try again later."
            )
        }
    }

    private static var currentVersion: String {
        let bundleCandidates = [Bundle.main, Bundle(for: UpdateServiceAnchor.self)]
        for bundle in bundleCandidates {
            if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
               !version.isEmpty {
                return version
            }
        }
        return fallbackVersion
    }

    private static func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacShelf", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        let version = payload.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let dmgAsset = payload.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        return GitHubRelease(
            version: version,
            htmlURL: payload.htmlURL,
            installerURL: dmgAsset?.browserDownloadURL,
            installerName: dmgAsset?.name ?? "MacShelf-\(version).dmg"
        )
    }

    private static func downloadAndOpenInstaller(for release: GitHubRelease) async {
        guard let installerURL = release.installerURL else {
            NSWorkspace.shared.open(release.htmlURL ?? releasesPage)
            return
        }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: installerURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let destination = downloadsDirectory
                .appendingPathComponent(safeFileName(release.installerName))
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            NSWorkspace.shared.open(destination)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not download the update"
            alert.informativeText = "MacShelf could not download the DMG installer. You can open the release page instead."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Release")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL ?? releasesPage)
            }
        }
    }

    private static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        return name.components(separatedBy: invalid).joined(separator: "-")
    }

    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = versionParts(lhs)
        let right = versionParts(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func versionParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }

    private static func showUpdateAvailable(latest: GitHubRelease, current: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "A new MacShelf update is available"
        alert.informativeText = "Version \(latest.version) is available. You are running version \(current)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: latest.installerURL == nil ? "Open Release" : "Download Update")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if latest.installerURL == nil {
                NSWorkspace.shared.open(latest.htmlURL ?? releasesPage)
                return false
            }
            return true
        }
        return false
    }

    private static func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

}

private final class UpdateServiceAnchor {}

private struct GitHubRelease {
    let version: String
    let htmlURL: URL?
    let installerURL: URL?
    let installerName: String
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: URL?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
