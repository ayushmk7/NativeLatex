import Foundation

/// The Drive operations Virgule needs: export a Doc as DOCX, create a *new* Doc
/// from an uploaded file. No update-in-place: Drive conversion on update replaces
/// the whole document.
///
/// No live implementation ships yet (no OAuth client, no Keychain token storage).
/// Tests use a fake. A live transport must use the `drive.file` scope.
public protocol GoogleDriveTransport: Sendable {
    func exportDocx(documentID: String) async throws -> Data
    /// Returns the new Google Doc's ID.
    func createGoogleDoc(name: String, docxFile: URL) async throws -> String
}

public enum GoogleDocsStatus: Equatable, Sendable {
    /// The user has not turned the integration on.
    case disabled
    /// Turned on, but no live Google sign-in exists in this build.
    case liveNotConfigured
    case ready
}

public enum GoogleDocsError: Error, LocalizedError, Equatable {
    case disabled
    case liveNotConfigured
    case invalidDocumentID(String)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "Google Docs is turned off in Virgule. Export a DOCX copy and upload it yourself, or turn the integration on."
        case .liveNotConfigured:
            return "Google sign-in is not available in this Virgule build yet. Export a DOCX copy and upload it to Google Docs yourself."
        case let .invalidDocumentID(id):
            return "\"\(id)\" is not a Google Docs document ID."
        }
    }
}

public struct GoogleDocsIntegration: Sendable {
    public let enabled: Bool
    let transport: (any GoogleDriveTransport)?
    let converter: LocalConverter

    public init(enabled: Bool, transport: (any GoogleDriveTransport)? = nil, converter: LocalConverter = LocalConverter()) {
        self.enabled = enabled
        self.transport = transport
        self.converter = converter
    }

    public var status: GoogleDocsStatus {
        !enabled ? .disabled : (transport == nil ? .liveNotConfigured : .ready)
    }

    /// Downloads a Doc as DOCX and converts it into a new local copy.
    public func importDocument(id: String, as format: DocumentFormat, into directory: URL) async throws -> ConversionResult {
        let transport = try readyTransport()
        guard id.range(of: "^[A-Za-z0-9_-]{10,200}$", options: .regularExpression) != nil else {
            throw GoogleDocsError.invalidDocumentID(id)
        }
        let data = try await transport.exportDocx(documentID: id)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("nativelatex-gdocs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let docx = work.appendingPathComponent("google-doc-\(id).docx")
        try data.write(to: docx)
        return try converter.convert(docx, to: format, in: directory)
    }

    /// Converts a local file to DOCX and uploads it as a new Google Doc.
    /// The temporary DOCX is deleted afterwards; review notes describe its losses.
    public func exportCopy(of source: URL) async throws -> (documentID: String, reviewNotes: [String]) {
        let transport = try readyTransport()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("nativelatex-gdocs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let conversion = try converter.convert(source, to: .docx, in: work)
        let name = source.deletingPathExtension().lastPathComponent
        let id = try await transport.createGoogleDoc(name: name, docxFile: conversion.outputURL)
        return (id, conversion.reviewNotes)
    }

    private func readyTransport() throws -> any GoogleDriveTransport {
        guard enabled else { throw GoogleDocsError.disabled }
        guard let transport else { throw GoogleDocsError.liveNotConfigured }
        return transport
    }
}
