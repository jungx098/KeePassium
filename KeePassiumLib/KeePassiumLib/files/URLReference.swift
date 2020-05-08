//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit

/// General info about file URL: file name, timestamps, etc.
public struct FileInfo {
    public var fileName: String
    public var fileSize: Int64?
    public var creationDate: Date?
    public var modificationDate: Date?
}

/// Represents a URL as a URL bookmark. Useful for handling external (cloud-based) files.
public class URLReference: Equatable, Codable, CustomDebugStringConvertible {
    public typealias Descriptor = String

    public enum Result<ReturnType, ErrorType> {
        case success(_ output: ReturnType)
        case failure(_ error: ErrorType)
    }
    
    public enum AccessError: LocalizedError {
        /// Operation timed out
        case timeout
        
        /// Raised when there is an internal inconsistency in the code.
        /// In particular, when both result and error params of a callback are nil.
        case internalError
        
        /// Wrapper for an underlying error
        case accessError(_ originalError: Error?)
        
        public var errorDescription: String? {
            switch self {
            case .timeout:
                return NSLocalizedString(
                    "[URLReference/AccessError/timeout]",
                    bundle: Bundle.framework,
                    value: "Storage provider did not respond in a timely manner",
                    comment: "Error message shown when file access operation has been aborted on timeout.")
            case .internalError:
                return NSLocalizedString(
                    "[URLReference/AccessError/internalError]",
                    bundle: Bundle.framework,
                    value: "Internal KeePassium error, please tell us about it.",
                    comment: "Error message shown when there's internal inconsistency in KeePassium.")
            case .accessError(let originalError):
                return originalError?.localizedDescription
            }
        }
    }
    
    /// Specifies possible storage locations of files.
    public enum Location: Int, Codable, CustomStringConvertible {
        public static let allValues: [Location] =
            [.internalDocuments, .internalBackup, .internalInbox, .external]
        
        public static let allInternal: [Location] =
            [.internalDocuments, .internalBackup, .internalInbox]
        
        /// Files stored in app sandbox/Documents dir.
        case internalDocuments = 0
        /// Files stored in app sandbox/Documents/Backup dir.
        case internalBackup = 1
        /// Files temporarily imported via Documents/Inbox dir.
        case internalInbox = 2
        /// Files stored outside the app sandbox (e.g. in cloud)
        case external = 100
        
        /// True if the location is in app sandbox
        public var isInternal: Bool {
            return self != .external
        }
        
        /// Human-readable description of the location
        public var description: String {
            switch self {
            case .internalDocuments:
                return NSLocalizedString(
                    "[URLReference/Location] Local copy",
                    bundle: Bundle.framework,
                    value: "Local copy",
                    comment: "Human-readable file location: the file is on device, inside the app sandbox. Example: 'File Location: Local copy'")
            case .internalInbox:
                return NSLocalizedString(
                    "[URLReference/Location] Internal inbox",
                    bundle: Bundle.framework,
                    value: "Internal inbox",
                    comment: "Human-readable file location: the file is on device, inside the app sandbox. 'Inbox' is a special directory for files that are being imported. Can be also 'Internal import'. Example: 'File Location: Internal inbox'")
            case .internalBackup:
                return NSLocalizedString(
                    "[URLReference/Location] Internal backup",
                    bundle: Bundle.framework,
                    value: "Internal backup",
                    comment: "Human-readable file location: the file is on device, inside the app sandbox. 'Backup' is a dedicated directory for database backup files. Example: 'File Location: Internal backup'")
            case .external:
                return NSLocalizedString(
                    "[URLReference/Location] Cloud storage / Another app",
                    bundle: Bundle.framework,
                    value: "Cloud storage / Another app",
                    comment: "Human-readable file location. The file is situated either online / in cloud storage, or on the same device, but in some other app. Example: 'File Location: Cloud storage / Another app'")
            }
        }
    }
    
    /// Last encountered error
    public var error: Error?
    public var hasError: Bool { return error != nil}
    
    /// True if the error is an access permission error associated with iOS 13 upgrade.
    /// (iOS 13 cannot access files bookmarked in iOS 12 (GitHub #63):
    /// "The file couldn’t be opened because you don’t have permission to view it.")
    public var hasPermissionError257: Bool {
        guard let nsError = error as NSError? else { return false }
        return (nsError.domain == "NSCocoaErrorDomain") && (nsError.code == 257)
    }
    
    /// Bookmark data
    private let data: Data
    /// sha256 hash describing this reference (URL or bookmark)
    lazy private(set) var hash: ByteArray = getHash()
    /// Location type of the original URL
    public let location: Location
    /// Cached original URL (nil if needs resolving)
    private var url: URL?
    /// Cached result of the last refreshInfo() call
    private var cachedInfo: FileInfo?
    
    fileprivate static let fileCoordinator = NSFileCoordinator()
    
    /// Dispatch queue for asynchronous URLReference operations
    fileprivate static let queue = DispatchQueue(
        label: "com.keepassium.URLReference",
        qos: .background,
        attributes: [.concurrent])
    
    /// Queue for coordinated reads
    fileprivate static let operationQueue = OperationQueue()
    
    private enum CodingKeys: String, CodingKey {
        case data = "data"
        case location = "location"
        case url = "url"
    }
    
    // MARK: -
    
    public init(from url: URL, location: Location) throws {
        let isAccessed = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        self.url = url
        self.location = location
        if location.isInternal {
            data = Data() // for backward compatibility
            hash = ByteArray(data: url.dataRepresentation).sha256
        } else {
            data = try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil) // throws an internal system error
            hash = ByteArray(data: data).sha256
        }
    }

    public static func == (lhs: URLReference, rhs: URLReference) -> Bool {
        guard lhs.location == rhs.location else { return false }
        if lhs.location.isInternal {
            // For internal files, URL references are generated dynamically
            // and same URL can have different refs. So we compare by URL.
            guard let leftURL = try? lhs.resolveSync(),
                let rightURL = try? rhs.resolveSync() else { return false }
            return leftURL == rightURL
        } else {
            // For external files, URL references are stored, so same refs
            // will have same hash.
            return !lhs.hash.isEmpty && (lhs.hash == rhs.hash)
        }
    }
    
    public func serialize() -> Data {
        return try! JSONEncoder().encode(self)
    }
    public static func deserialize(from data: Data) -> URLReference? {
        guard let ref = try? JSONDecoder().decode(URLReference.self, from: data) else {
            return nil
        }
        if ref.hash.isEmpty {
            // legacy stored refs don't have stored hash, so we set it
            ref.hash = ref.getHash()
        }
        return ref
    }
    
    public var debugDescription: String {
        return " ‣ Location: \(location)\n" +
            " ‣ URL: \(url?.relativeString ?? "nil")\n" +
            " ‣ data: \(data.count) bytes"
    }
    
    // MARK: - Async creation
    
    /// One of the parameters is guaranteed to be non-nil
    public typealias CreateCallback = (Result<URLReference, AccessError>) -> ()
        
    /// Creates a reference for the given URL, asynchronously.
    /// Takes several stages (attempts):
    ///  - startAccessingSecurityScopedResource / stopAccessingSecurityScopedResource
    ///  - access the file (but don't open)
    ///  - open UIDocument
    ///
    /// - Parameters:
    ///   - url: target URL
    ///   - location: location of the target URL
    ///   - completion: called once the process has finished (either successfully or with an error)
    public static func create(
        for url: URL,
        location: URLReference.Location,
        completion callback: @escaping CreateCallback)
    {
        let isAccessed = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Stage 1: try to simply create
        if tryCreate(for: url, location: location, callbackOnError: false, callback: callback) {
            print("URL bookmarked on stage 1")
            return
        }
        
        // Stage 2: try to create after accessing the document
        let readingIntentOptions: NSFileCoordinator.ReadingOptions = [
            .withoutChanges, // don't force other processes to save the file first
            .resolvesSymbolicLink, // if sym link, resolve the real target URL first
            .immediatelyAvailableMetadataOnly] // don't download, use as-is immediately
                                               // N.B.: Shouldn't actually read the contents
        fileCoordinator.coordinate(
            with: [.readingIntent(with: url, options: readingIntentOptions)],
            queue: operationQueue)
        {
            // Note: don't attempt to read the contents,
            // it won't work due to .immediatelyAvailableMetadataOnly above
            (error) in
            guard error == nil else {
                callback(.failure(.accessError(error!)))
                return
            }
            // calls the callback in any case
            tryCreate(for: url, location: location, callbackOnError: true, callback: callback)
        }
    }
    
    /// Tries to create a URLReference for the given URL
    /// - Parameters:
    ///   - url: target URL
    ///   - location: target URL location
    ///   - callbackOnError: whether to return error via callback before returning `false`
    ///   - callback: called once reference created (or failed, if callbackOnError is true)
    /// - Returns: true if successful, false otherwise
    @discardableResult
    private static func tryCreate(
        for url: URL,
        location: URLReference.Location,
        callbackOnError: Bool = false,
        callback: @escaping CreateCallback
    ) -> Bool {
        do {
            let urlRef = try URLReference(from: url, location: location)
            callback(.success(urlRef))
            return true
        } catch {
            if callbackOnError {
                callback(.failure(.accessError(error)))
            }
            return false
        }
    }
    
    // MARK: - Async resolving
    
    /// One of the parameters is guaranteed to be non-nil
    public typealias ResolveCallback = (Result<URL, AccessError>) -> ()
    
    /// Resolves the reference asynchronously.
    /// - Parameters:
    ///   - timeout: time to wait for resolving to finish
    ///   - callback: called when resolving either finishes or terminates by timeout. Is called on the main queue.
    public func resolveAsync(timeout: TimeInterval = -1, callback: @escaping ResolveCallback) {
        URLReference.queue.async { // strong self
            self.resolveAsyncInternal(timeout: timeout, completion: callback)
        }
    }
    
    private func resolveAsyncInternal(
        timeout: TimeInterval,
        completion callback: @escaping ResolveCallback)
    {
        assert(!Thread.isMainThread)
        
        let waitSemaphore = DispatchSemaphore(value: 0)
        var hasTimedOut = false
        // do slow resolving as a concurrent task
        URLReference.queue.async { // strong self
            var _url: URL?
            var _error: Error?
            do {
                _url = try self.resolveSync()
            } catch {
                _error = error
            }
            waitSemaphore.signal()
            guard !hasTimedOut else { return }
            DispatchQueue.main.async { // strong self
                assert(_url != nil || _error != nil)
                guard _error == nil else {
                    self.error = AccessError.accessError(_error)
                    callback(.failure(.accessError(_error)))
                    return
                }
                guard let url = _url else { // should not happen
                    assertionFailure()
                    Diag.error("Internal error")
                    self.error = AccessError.internalError
                    callback(.failure(.internalError))
                    return
                }
                self.error = nil
                callback(.success(url))
            }
        }
        
        // wait for a while to finish resolving
        let waitUntil = (timeout < 0) ? DispatchTime.distantFuture : DispatchTime.now() + timeout
        guard waitSemaphore.wait(timeout: waitUntil) != .timedOut else {
            hasTimedOut = true
            DispatchQueue.main.async {
                self.error = AccessError.timeout
                callback(.failure(AccessError.timeout))
            }
            return
        }
    }
    
    // MARK: - Async info
    
    /// One of the parameters is guaranteed to be non-nil
    public typealias InfoCallback = (Result<FileInfo, AccessError>) -> ()
    
    /// Retruns the last known info about the target file.
    /// If no previous info available, fetches it.
    /// - Parameter callback: called on the main queue once the operation is complete (with info or with an error)
    public func getCachedInfo(completion callback: @escaping InfoCallback) {
        if let info = cachedInfo {
            DispatchQueue.main.async {
                // don't change `error`, simply return cached info
                callback(.success(info))
            }
        } else {
            refreshInfo(completion: callback)
        }
    }
    
    /// Fetches information about target file, asynchronously.
    /// - Parameters:
    ///   - timeout: timeout to resolve the reference
    ///   - callback: called on the main queue once the operation completes (either with info or an error)
    public func refreshInfo(
        timeout: TimeInterval = -1,
        completion callback: @escaping InfoCallback)
    {
        resolveAsync(timeout: timeout) { // strong self
            (result) in
            switch result {
            case .success(let url):
                URLReference.queue.async { // strong self
                    self.refreshInfo(for: url, completion: callback)
                }
            case .failure(let error):
                // propagate the resolving error
                DispatchQueue.main.async {
                    self.error = error
                    callback(.failure(error))
                }
            }
        }
    }
    
    /// Should be called in a background queue.
    private func refreshInfo(for url: URL, completion callback: @escaping InfoCallback) {
        assert(!Thread.isMainThread)

        // without secruity scoping, won't get file attributes
        let isAccessed = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Access the document to ensure we fetch the latest metadata
        let readingIntentOptions: NSFileCoordinator.ReadingOptions = [
            // ensure any pending saves are completed first --> so, no .withoutChanges
            // OK to download the latest metadata --> so, no .immediatelyAvailableMetadataOnly
            .resolvesSymbolicLink // if sym link, resolve the real target URL first
        ]
        URLReference.fileCoordinator.coordinate(
            with: [.readingIntent(with: url, options: readingIntentOptions)],
            queue: URLReference.operationQueue)
        {
            (error) in // strong self

            guard error == nil else {
                DispatchQueue.main.async { // strong self
                    self.error = AccessError.accessError(error!)
                    callback(.failure(.accessError(error!)))
                }
                return
            }
            let latestInfo = FileInfo(
                fileName: url.lastPathComponent,
                fileSize: url.fileSize,
                creationDate: url.fileCreationDate,
                modificationDate: url.fileModificationDate)
            self.cachedInfo = latestInfo
            DispatchQueue.main.async {
                self.error = nil
                callback(.success(latestInfo))
            }
        }
    }
    
    // MARK: - Synchronous operations
    
    /// Returns a sha256 hash of the URL (if internal) or bookmark (if external)
    private func getHash() -> ByteArray {
        guard location.isInternal else {
            // external location: sha256(bookmark data)
            return ByteArray(data: data).sha256
        }

        // internal location
        // URL might be deserialized as nil, resolving might fail
        do {
            let _url = try resolveSync()
            return ByteArray(data: _url.dataRepresentation).sha256
        } catch {
            Diag.warning("Failed to resolve the URL: \(error.localizedDescription)")
            return ByteArray() // empty hash as a sign of error
        }
    }
    
    public func resolveSync() throws -> URL {
        if let url = url, location.isInternal {
            return url
        }
        
        var isStale = false
        let resolvedUrl = try URL(
            resolvingBookmarkData: data,
            options: [URL.BookmarkResolutionOptions.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
        self.url = resolvedUrl
        return resolvedUrl
    }
    
//    /// Identifies this reference among others.
//    /// Currently returns file name if available.
//    /// If the reference is not resolvable, returns nil.
//    public func getDescriptor() -> Descriptor? {
//        guard !info.hasError else {
//            //TODO: lookup file name by hash, in some persistent table
//            return nil
//        }
//        return info.fileName
//    }
    
    /// Returns information about resolved URL (also updates the `info` property).
    /// Might be slow, as it needs to resolve the URL.
    /// In case of trouble, only `hasError` and `errorMessage` fields are valid.
    public func getInfo() -> FileInfo {
        refreshInfoSync()
        return cachedInfo!
    }
    
    /// Re-aquires information about resolved URL and updates the `info` field.
    public func refreshInfoSync() {
        do {
            let url = try resolveSync()
            // without secruity scoping, won't get file attributes
            let isAccessed = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            cachedInfo = FileInfo(
                fileName: url.lastPathComponent,
                fileSize: url.fileSize,
                creationDate: url.fileCreationDate,
                modificationDate: url.fileModificationDate)
        } catch {
            self.error = error
            cachedInfo = nil
        }
    }
    
    /// Finds the same reference in the given list.
    /// If no exact match found, and `fallbackToNamesake` is `true`,
    /// looks also for references with the same file name.
    ///
    /// - Parameters:
    ///   - refs: list of references to search in
    ///   - fallbackToNamesake: if `true`, repeat search with relaxed conditions
    ///       (same file name instead of exact match).
    /// - Returns: suitable reference from `refs`, if any.
    public func find(in refs: [URLReference], fallbackToNamesake: Bool=false) -> URLReference? {
        if let exactMatchIndex = refs.firstIndex(of: self) {
            return refs[exactMatchIndex]
        }
        
        if fallbackToNamesake {
            guard let fileName = self.cachedInfo?.fileName else {
                return nil
            }
            return refs.first(where: { $0.cachedInfo?.fileName == fileName })
        }
        return nil
    }
}
