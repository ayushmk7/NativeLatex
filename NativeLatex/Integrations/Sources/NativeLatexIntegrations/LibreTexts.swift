import Foundation

/// Public, key-free import of one LibreTexts page through its read-only Deki API
/// (`https://<library>.libretexts.org/@api/deki/pages/=<path>`). Import only:
/// publishing to LibreTexts needs platform permission and is not offered.
public struct LibreTextsPage: Sendable, Equatable {
    public let title: String
    public let pageURL: URL
    /// The page's `license:` tag, e.g. `ccby`, `ccbyncsa`, `ck12`. Nil if untagged.
    public let license: String?
    public let authors: [String]
    public let html: String
}

public enum LibreTextsError: Error, LocalizedError, Equatable {
    case notLibreTextsURL(String)
    case httpStatus(Int, URL)
    case unexpectedResponse(URL)
    case licenseNotReusable(String?)

    public var errorDescription: String? {
        switch self {
        case let .notLibreTextsURL(s):
            return "Virgule imports only https://*.libretexts.org page links; \"\(s)\" is not one."
        case let .httpStatus(code, url):
            return "LibreTexts returned HTTP \(code) for \(url.absoluteString). Check the page link or try again later."
        case let .unexpectedResponse(url):
            return "LibreTexts sent a response Virgule could not read from \(url.absoluteString)."
        case let .licenseNotReusable(license):
            return "This LibreTexts page is \(license.map { "licensed \"\($0)\"" } ?? "missing a license tag"), so Virgule will not copy it. Choose openly licensed content."
        }
    }
}

public struct LibreTextsClient: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    let fetch: Fetch

    public init(fetch: @escaping Fetch = LibreTextsClient.urlSessionFetch) {
        self.fetch = fetch
    }

    public static let urlSessionFetch: Fetch = { url in
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Virgule/0.1 (local import)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Deki addresses pages by their path, URL-encoded twice.
    public static func apiURL(for pageURL: URL) throws -> URL {
        guard pageURL.scheme == "https", let host = pageURL.host?.lowercased(),
              host.hasSuffix(".libretexts.org"), !pageURL.path.trimmingCharacters(in: ["/"]).isEmpty
        else { throw LibreTextsError.notLibreTextsURL(pageURL.absoluteString) }
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        let path = pageURL.path.trimmingCharacters(in: ["/"])
        let once = path.addingPercentEncoding(withAllowedCharacters: unreserved)!
        let twice = once.addingPercentEncoding(withAllowedCharacters: unreserved)!
        return URL(string: "https://\(host)/@api/deki/pages/=\(twice)")!
    }

    public func fetchPage(_ pageURL: URL) async throws -> LibreTextsPage {
        let base = try Self.apiURL(for: pageURL)
        let info = try await json(base)
        let tagsJSON = try await json(base.appendingPathComponent("tags"))
        let contents = try await json(base.appendingPathComponent("contents"))

        // Deki collapses one-element arrays to a bare value.
        func list(_ v: Any?) -> [Any] { (v as? [Any]) ?? (v.map { [$0] } ?? []) }
        let tags = list(tagsJSON["tag"]).compactMap { ($0 as? [String: Any])?["@value"] as? String }
        guard let title = info["title"] as? String,
              let html = list(contents["body"]).first as? String
        else { throw LibreTextsError.unexpectedResponse(base) }
        let canonical = (info["uri.ui"] as? String).flatMap(URL.init(string:)) ?? pageURL
        return LibreTextsPage(
            title: title, pageURL: canonical,
            license: tags.first { $0.hasPrefix("license:") }.map { String($0.dropFirst("license:".count)) },
            authors: tags.filter { $0.hasPrefix("author@") }.map { String($0.dropFirst("author@".count)) },
            html: html
        )
    }

    /// Fetches a page and converts it into a new local copy with an attribution line.
    public func importPage(_ pageURL: URL, as format: DocumentFormat, into directory: URL, converter: LocalConverter = LocalConverter()) async throws -> (page: LibreTextsPage, conversion: ConversionResult) {
        let page = try await fetchPage(pageURL)
        guard let license = page.license, !["arr", "notset", "none"].contains(license.lowercased()) else {
            throw LibreTextsError.licenseNotReusable(page.license)
        }
        let esc = { (s: String) in
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let by = page.authors.isEmpty ? "" : " by \(esc(page.authors.joined(separator: ", ")))"
        let doc = """
        <!doctype html><html><head><meta charset="utf-8"><title>\(esc(page.title))</title></head><body>
        <p><em>Source: <a href="\(esc(page.pageURL.absoluteString))">\(esc(page.title))</a>\(by), LibreTexts, license \(esc(license)). Keep this attribution.</em></p>
        \(page.html)
        </body></html>
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("nativelatex-libretexts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let safeStem = page.title.components(separatedBy: CharacterSet(charactersIn: "/:\\\0").union(.newlines)).joined(separator: "-")
        let html = work.appendingPathComponent("\(safeStem.isEmpty ? "libretexts-page" : String(safeStem.prefix(120))).html")
        try doc.write(to: html, atomically: true, encoding: .utf8)
        var conversion = try converter.convert(html, to: format, in: directory)
        if page.html.contains("\\PageIndex") || page.html.contains("\\ce{") {
            conversion = ConversionResult(
                outputURL: conversion.outputURL, mediaDirectory: conversion.mediaDirectory, tool: conversion.tool,
                reviewNotes: conversion.reviewNotes + ["LibreTexts math uses site macros (\\PageIndex, \\ce from mhchem); define them or add \\usepackage{mhchem} before compiling."],
                log: conversion.log
            )
        }
        return (page, conversion)
    }

    private func json(_ url: URL) async throws -> [String: Any] {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        parts.percentEncodedQuery = "dream.out.format=json"
        let request = parts.url!
        let (data, status) = try await fetch(request)
        guard status == 200 else { throw LibreTextsError.httpStatus(status, request) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LibreTextsError.unexpectedResponse(request)
        }
        return object
    }
}
