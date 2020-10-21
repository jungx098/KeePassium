//  KeePassium Password Manager
//  Copyright © 2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

public class EntryFieldReference {
    public enum Status {
        case parsed
        case resolved
        case targetMissing
        case tooDeep
    }
    public enum ResolveStatus {
        case noReferences
        case hasReferences
        case brokenReferences
        case tooDeepReferences
        
        public var isError: Bool {
            switch self {
            case .noReferences,
                 .hasReferences:
                return false
            case .brokenReferences,
                 .tooDeepReferences:
                return true
            }
        }
    }
    
    private(set) public var status: Status
    
    enum FieldType {
        case uuid
        case named(_ name: String)
        case otherNamed
        
        public static func fromCode(_ code: Character) -> Self? {
            switch code {
            case "T": return .named(EntryField.title)
            case "U": return .named(EntryField.userName)
            case "P": return .named(EntryField.password)
            case "A": return .named(EntryField.url)
            case "N": return .named(EntryField.notes)
            case "I": return .uuid
            case "O": return .otherNamed
            default:
                return nil
            }
        }
    }
    
    private static let refPrefix = "{REF:"
    private static let regexp = try! NSRegularExpression(
        pattern: #"\{REF:([TUPANI])@([TUPANIO]):(.+?)\}"#,
        options: []
    )
    
    /// Range of this reference in the source string
    private var range: Range<String.Index>
    private var targetFieldType: FieldType
    private var searchFieldType: FieldType
    private var searchValue: Substring
    
    private init(
        range: Range<String.Index>,
        targetFieldType: FieldType,
        searchFieldType: FieldType,
        searchValue: Substring)
    {
        self.range = range
        self.targetFieldType = targetFieldType
        self.searchFieldType = searchFieldType
        self.searchValue = searchValue
        self.status = .parsed
    }
    
    // MARK: Public interface
    
    /// Parses the `value`, identifies any references, resolves them using `entries` and returns the resolved value.
    /// If there are no references, simply returns `value`.
    /// - Parameters:
    ///   - value: raw field value with possible references to other fields.
    ///   - entries: all entries of the database.
    ///   - maxDepth: maximum allowed depth of chained references
    ///   - resolvedValue: inout parameter returns `value` with any references replaced by their respective values.
    /// - Returns: status indicating whether `value` was successfully resolved
    public static func resolveReferences<T>(
        in value: String,
        entries: T,
        maxDepth: Int,
        resolvedValue: inout String
        ) -> ResolveStatus
        where T: Collection, T.Element: Entry
    {
        guard maxDepth > 0 else {
            Diag.warning("Too many chained references")
            // keep resolvedValue unchanged
            return .tooDeepReferences
        }
        
        let refs = EntryFieldReference.parse(value)
        if refs.isEmpty { // there are no references
            resolvedValue = value
            return .noReferences
        }
        
        var status = ResolveStatus.hasReferences
        var outputValue = value
        refs.reversed().forEach { ref in
            let resolvedRefValue = ref.getResolvedValue(entries: entries, maxDepth: maxDepth - 1)
            switch ref.status {
            case .parsed:
                assertionFailure("Should be resolved")
            case .targetMissing:
                status = .brokenReferences
                // leave the broken ref as it is, keep replacing others
            case .tooDeep:
                status = .tooDeepReferences
                // leave the broken ref as it is, keep replacing others
            case .resolved:
                outputValue.replaceSubrange(ref.range, with: resolvedRefValue)
            }
        }
        resolvedValue = outputValue
        return status
    }
    
    // MARK: Parsing
    
    /// Tries parsing the given string.
    /// - Parameter string: string to parse. Valid references should have format
    ///     `{REF:<WantedField>@<SearchIn>:<Text>}`.
    ///     The string can contain serveral references.
    /// - Returns: Initialized references with a suitable status
    private static func parse(_ string: String) -> [EntryFieldReference] {
        guard string.contains(refPrefix) else {
            // fast check: there are no refs
            return []
        }
        
        var references = [EntryFieldReference]()
        let fullRange = NSRange(string.startIndex..<string.endIndex, in: string)
        let matches = regexp.matches(in: string, options: [], range: fullRange)
        for match in matches {
            guard match.numberOfRanges == 4,
                  let range = Range(match.range, in: string),
                  let targetFieldCodeRange = Range(match.range(at: 1), in: string),
                  let searchFieldCodeRange = Range(match.range(at: 2), in: string),
                  let searchValueRange =  Range(match.range(at: 3), in: string) else
            {
                // malformed reference, go to the next one
                continue
            }
            
            guard let targetFieldCode = string[targetFieldCodeRange].first,
                  let targetFieldType = FieldType.fromCode(targetFieldCode) else
            {
                // failed to parse this ref, go to the next one
                Diag.debug("Unrecognized target field")
                continue
            }
            
            guard let searchFieldCode = string[searchFieldCodeRange].first,
                  let searchFieldType = FieldType.fromCode(searchFieldCode) else
            {
                // failed to parse this ref, go to the next one
                Diag.debug("Unrecognized search field")
                continue
            }
            
            let searchValue = string[searchValueRange]
            guard !searchValue.isEmpty else {
                // failed to parse this ref, go to the next one
                Diag.debug("Empty search criterion")
                continue
            }
            let ref = EntryFieldReference(
                range: range,
                targetFieldType: targetFieldType,
                searchFieldType: searchFieldType,
                searchValue: searchValue)
            references.append(ref)
        }
        return references
    }
    
    // MARK: Resolving
    
    private func getResolvedValue<T>(entries: T, maxDepth: Int) -> String
        where T: Collection, T.Element: Entry
    {
        guard let entry = findEntry(in: entries, field: searchFieldType, value: searchValue) else {
            status = .targetMissing
            return ""
        }
        
        switch targetFieldType {
        case .uuid:
            // UUID is not an EntryField, which makes it rather difficult to reference.
            return entry.uuid.data.asHexString
        case .named(let name):
            if let targetField = entry.getField(with: name) {
                let resolvedValue = targetField.resolveReferences(entries: entries, maxDepth: maxDepth - 1)
                switch targetField.resolveStatus {
                case .noReferences,
                     .hasReferences:
                    status = .resolved
                    return resolvedValue
                case .brokenReferences:
                    // failed to resolve the field, just return the original value
                    status = .targetMissing
                    return targetField.value
                case .tooDeepReferences:
                    // failed to resolve the field, just return the original value
                    status = .tooDeep
                    return targetField.value
                }

            } else {
                status = .targetMissing
                return ""
            }
        case .otherNamed:
            if let targetField = entry.getField(with: searchValue) {
                let resolvedValue = targetField.resolveReferences(entries: entries, maxDepth: maxDepth - 1)
                switch targetField.resolveStatus {
                case .noReferences,
                     .hasReferences:
                    status = .resolved
                    return resolvedValue
                case .brokenReferences:
                    // failed to resolve the field, just return the original value
                    status = .targetMissing
                    return targetField.value
                case .tooDeepReferences:
                    // failed to resolve the field, just return the original value
                    status = .tooDeep
                    return targetField.value
                }
            } else {
                status = .targetMissing
                return ""
            }
        }
    }
    
    private func findEntry<T>(in entries: T, field: FieldType, value: Substring) -> Entry?
        where T: Collection, T.Element: Entry
    {
        let result: Entry?
        switch field {
        case .uuid:
            // The UUID string can be a simple hex string (most likely)
            // or a formatted UUID string with dashes.
            let _uuid: UUID?
            if let uuidBytes = ByteArray(hexString: value) {
                _uuid = UUID(data: uuidBytes)
            } else {
                _uuid = UUID(uuidString: String(value)) // this constructor accepts only String
            }
            guard let uuid = _uuid else {
                Diag.debug("Malformed UUID: \(value)")
                return nil
            }
            result = entries.first(where: { $0.uuid == uuid })
        case .named(let name):
            result = entries.first(where: { entry in
                let field = entry.getField(with: name)
                return field?.value.compare(value) == .some(.orderedSame)
            })
        case .otherNamed:
            // For custom fields, KeePass searches by field name
            result = entries.first(where: { entry in
                let field = entry.getField(with: value)
                return field != nil
            })
        }
        return result
    }
}
