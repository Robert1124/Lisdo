import Foundation

struct LisdoMacVersionInfo: Equatable {
    var shortVersion: String
    var buildVersion: String
    var appcastURL: URL
    var updatesPageURL: URL

    static var current: LisdoMacVersionInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildVersion = info["CFBundleVersion"] as? String ?? "Unknown"
        let appcastURL = (info["SUFeedURL"] as? String)
            .flatMap(URL.init(string:))
            ?? URL(string: "https://lisdo.robertw.me/appcast.xml")!
        let updatesPageURL = URL(string: "https://lisdo.robertw.me/updates.html")!

        return LisdoMacVersionInfo(
            shortVersion: shortVersion,
            buildVersion: buildVersion,
            appcastURL: appcastURL,
            updatesPageURL: updatesPageURL
        )
    }
}

struct LisdoMacAppcastRelease: Equatable {
    var title: String?
    var shortVersion: String?
    var buildVersion: String?
    var link: URL?

    var displayVersion: String {
        switch (shortVersion, buildVersion) {
        case let (.some(shortVersion), .some(buildVersion)):
            return "\(shortVersion) (\(buildVersion))"
        case let (.some(shortVersion), .none):
            return shortVersion
        case let (.none, .some(buildVersion)):
            return "build \(buildVersion)"
        case (.none, .none):
            return title ?? "latest release"
        }
    }
}

enum LisdoMacUpdateCheckResult: Equatable {
    case upToDate(remote: LisdoMacAppcastRelease?)
    case updateAvailable(LisdoMacAppcastRelease)
    case noPublishedUpdates
}

enum LisdoMacUpdateChecker {
    static func check(currentVersion: LisdoMacVersionInfo = .current) async throws -> LisdoMacUpdateCheckResult {
        let (data, _) = try await URLSession.shared.data(from: currentVersion.appcastURL)
        let parser = LisdoMacAppcastParser()
        let releases = try parser.parse(data: data)

        guard let latest = releases.first else {
            return .noPublishedUpdates
        }

        if isRelease(latest, newerThan: currentVersion) {
            return .updateAvailable(latest)
        }
        return .upToDate(remote: latest)
    }

    private static func isRelease(_ release: LisdoMacAppcastRelease, newerThan currentVersion: LisdoMacVersionInfo) -> Bool {
        if let remoteBuild = release.buildVersion,
           let remoteBuildInt = Int(remoteBuild),
           let currentBuildInt = Int(currentVersion.buildVersion) {
            return remoteBuildInt > currentBuildInt
        }

        guard let remoteShortVersion = release.shortVersion else {
            return false
        }

        return compareVersion(remoteShortVersion, to: currentVersion.shortVersion) == .orderedDescending
    }

    private static func compareVersion(_ lhs: String, to rhs: String) -> ComparisonResult {
        let lhsParts = versionParts(lhs)
        let rhsParts = versionParts(rhs)
        let maxCount = max(lhsParts.count, rhsParts.count)

        for index in 0..<maxCount {
            let lhsPart = index < lhsParts.count ? lhsParts[index] : 0
            let rhsPart = index < rhsParts.count ? rhsParts[index] : 0
            if lhsPart > rhsPart {
                return .orderedDescending
            }
            if lhsPart < rhsPart {
                return .orderedAscending
            }
        }

        return .orderedSame
    }

    private static func versionParts(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { part in
                Int(part.filter(\.isNumber)) ?? 0
            }
    }
}

private final class LisdoMacAppcastParser: NSObject, XMLParserDelegate {
    private var releases: [LisdoMacAppcastRelease] = []
    private var currentRelease: LisdoMacAppcastRelease?
    private var currentElement = ""
    private var currentText = ""
    private var parseError: Error?

    func parse(data: Data) throws -> [LisdoMacAppcastRelease] {
        releases = []
        currentRelease = nil
        currentElement = ""
        currentText = ""
        parseError = nil

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? parseError ?? CocoaError(.fileReadCorruptFile)
        }
        return releases
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = qName ?? elementName
        currentText = ""

        guard currentElement == "item" else {
            if currentRelease != nil, currentElement == "enclosure" {
                currentRelease?.shortVersion = attributeValue(attributeDict, "sparkle:shortVersionString")
                    ?? attributeValue(attributeDict, "shortVersionString")
                currentRelease?.buildVersion = attributeValue(attributeDict, "sparkle:version")
                    ?? attributeValue(attributeDict, "version")
            }
            return
        }

        currentRelease = LisdoMacAppcastRelease()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = qName ?? elementName
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if element == "item" {
            if let currentRelease {
                releases.append(currentRelease)
            }
            currentRelease = nil
            currentText = ""
            currentElement = ""
            return
        }

        guard currentRelease != nil, !text.isEmpty else {
            currentText = ""
            currentElement = ""
            return
        }

        switch element {
        case "title":
            currentRelease?.title = text
        case "link":
            currentRelease?.link = URL(string: text)
        case "sparkle:shortVersionString", "shortVersionString":
            currentRelease?.shortVersion = text
        case "sparkle:version", "version":
            currentRelease?.buildVersion = text
        default:
            break
        }

        currentText = ""
        currentElement = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    private func attributeValue(_ attributes: [String: String], _ key: String) -> String? {
        attributes[key]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
