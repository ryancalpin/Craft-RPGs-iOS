import Foundation

public enum ToolValidationError: Error, Equatable, Sendable {
    case unknownTool
    case malformedArguments
    case argumentsTooLarge(maximumBytes: Int, actualBytes: Int)
    case missingArgument
    case missingRollID
    case unknownArgument
    case wrongArgumentType
    case unsafeArgument
    case invalidIdentifier
    case campaignOwnershipMismatch
    case recordNotFound
    case schemaNotFound
    case fieldNotFound
    case invalidFieldValue
    case invalidRelationshipTarget
    case invalidRollExpression
    case invalidBounds
    case assetNotFound
    case invalidAssetReference
}

public typealias GMToolValidationError = ToolValidationError

public struct ToolValidator: Sendable {
    public static let maximumArgumentBytes = ProviderToolArguments.maximumEncodedBytes

    private static let maximumArgumentFields = 16
    private static let maximumPatchFields = 32
    private static let maximumStringBytes = 4_096
    private static let maximumIdentifierBytes = 128
    private static let maximumJSONDepth = 8
    private static let maximumJSONNodes = 1_024
    private static let maximumPercentDecodingPasses = 8
    private static let maximumClockValue = 10_000
    private static let maximumResultBytes = 1_000_000
    private static let maximumSearchResults = 50
    private static let fixedLocale = Locale(identifier: "en_US_POSIX")
    private static let identifierArgumentNames: Set<String> = [
        "recordID", "sceneRecordID", "clockRecordID", "characterRecordID",
        "assetID", "targetRecordID", "fieldID"
    ]
    private static let executableCommandNames: Set<String> = [
        "awk", "bash", "cat", "chmod", "cmd", "cp", "curl", "echo", "env", "fish",
        "find", "git", "grep", "id", "java", "ls", "node", "osascript", "perl", "php",
        "mv", "powershell", "pwd", "pwsh", "python", "python2", "python3", "rm", "ruby", "sed",
        "sh", "uname", "wget", "whoami", "zsh"
    ]
    private static let sensitiveTerms = [
        "secret", "private", "draft", "credential", "password", "passwd",
        "token", "authorization", "apikey", "cookie", "internal"
    ]
    private static let executableExtensions: Set<String> = [
        "app", "asp", "aspx", "bat", "bash", "bin", "cgi", "cmd", "com",
        "command", "csh", "dylib", "elf", "exe", "fish", "hta", "jar", "js",
        "jsp", "ksh", "lua", "mjs", "msi", "php", "pl", "ps1", "psm1", "py",
        "rb", "sh", "so", "tcl", "vbs", "wasm", "wsf", "zsh"
    ]
    private static let supportedFieldTypes: Set<String> = [
        "string", "text", "richtext", "integer", "int", "number", "double", "float",
        "boolean", "bool", "array", "list", "string[]", "recordid[]", "reference[]",
        "relationship[]", "records", "recordids", "references", "relationshipids", "object",
        "map", "json", "any", "value", "record", "recordid", "reference", "relationship",
        "assetid", "asset", "assetreference", "image", "assetids", "assets", "assetreferences",
        "images", "assetid[]", "asset[]", "assetreference[]", "image[]"
    ]

    public init() {}

    public func validate(
        tool: GMTool,
        arguments: ProviderToolArguments,
        context: GMToolValidationContext,
        rollID: UUID? = nil
    ) throws -> ToolProposal {
        try validate(
            toolName: tool.rawValue,
            arguments: arguments,
            context: context,
            rollID: rollID
        )
    }

    public func validate(
        toolName: String,
        arguments: ProviderToolArguments,
        context: GMToolValidationContext,
        // The turn engine supplies a request/call-derived ID for requestRoll;
        // validation never creates an ID implicitly.
        rollID: UUID? = nil
    ) throws -> ToolProposal {
        guard let tool = GMToolRegistry.all.resolve(toolName) else {
            throw ToolValidationError.unknownTool
        }
        try validateContext(context)
        try validateArgumentShape(arguments.values, for: tool)

        switch tool {
        case .readRecord:
            let recordID = try identifier(arguments.values["recordID"])
            let record = try record(in: context, id: recordID)
            return ToolProposal(
                tool: tool,
                status: "Record read.",
                result: .recordRead(
                    GMToolRecordResult(
                        recordID: record.id,
                        fields: try safeFields(for: record, in: context)
                    )
                )
            )

        case .searchRecords:
            let query = try text(arguments.values["query"], maximumBytes: 256)
            let normalizedQuery = deterministicLowercased(query)
            let matches = context.project.records.compactMap { record -> GMToolRecordMatch? in
                guard let validated = try? validatedSearchRecord(record, in: context) else {
                    return nil
                }
                let fieldText = validated.fields.keys.sorted().compactMap { fieldID in
                    guard case .string(let value) = validated.fields[fieldID] else { return nil }
                    return deterministicLowercased(value)
                }
                let matchesID = deterministicLowercased(record.id).contains(normalizedQuery)
                let matchesField = fieldText.contains { $0.contains(normalizedQuery) }
                guard matchesID || matchesField else { return nil }
                return GMToolRecordMatch(
                    recordID: record.id,
                    recordKind: validated.schema.recordKind
                )
            }
            .sorted { $0.recordID < $1.recordID }
            .prefix(Self.maximumSearchResults)
            .reduce(into: [GMToolRecordMatch]()) { result, match in
                let candidate = result + [match]
                guard serializedBytes(candidate) <= Self.maximumResultBytes else { return }
                result.append(match)
            }
            return ToolProposal(
                tool: tool,
                status: "Records searched.",
                result: .recordsFound(Array(matches))
            )

        case .patchRecord:
            let recordID = try identifier(arguments.values["recordID"])
            let record = try record(in: context, id: recordID)
            let fields = try patchFields(arguments.values["fieldsJSON"], record: record, context: context)
            return ToolProposal(
                tool: tool,
                status: "Record patch proposed.",
                result: .proposedEvent(
                    .recordPatch(recordID: recordID, fields: fields)
                )
            )

        case .requestRoll:
            let expression = try rollExpression(arguments.values["expression"])
            let prompt = try text(arguments.values["prompt"], maximumBytes: 512)
            guard let rollID else { throw ToolValidationError.missingRollID }
            return ToolProposal(
                tool: tool,
                status: "Roll requested.",
                result: .proposedEvent(
                    .rollRequest(
                        rollID: rollID,
                        expression: expression,
                        prompt: prompt
                    )
                )
            )

        case .updateScene:
            let sceneID = try identifier(arguments.values["sceneRecordID"])
            let record = try record(in: context, id: sceneID)
            guard try schema(for: record, in: context).recordKind == "scene" else {
                throw ToolValidationError.invalidRelationshipTarget
            }
            let title = try text(arguments.values["title"], maximumBytes: 256)
            let summary = try optionalText(arguments.values["summary"], maximumBytes: 2_000)
            return ToolProposal(
                tool: tool,
                status: "Scene update proposed.",
                result: .proposedEvent(
                    .sceneChange(sceneRecordID: sceneID, title: title, summary: summary)
                )
            )

        case .updateClock:
            let clockID = try identifier(arguments.values["clockRecordID"])
            let record = try record(in: context, id: clockID)
            guard try schema(for: record, in: context).recordKind == "clock" else {
                throw ToolValidationError.invalidRelationshipTarget
            }
            let current = try integer(arguments.values["current"])
            let maximum = try integer(arguments.values["maximum"])
            guard current >= 0, maximum > 0, current <= maximum,
                  maximum <= Self.maximumClockValue else {
                throw ToolValidationError.invalidBounds
            }
            return ToolProposal(
                tool: tool,
                status: "Clock update proposed.",
                result: .proposedEvent(
                    .clockUpdate(clockRecordID: clockID, current: current, maximum: maximum)
                )
            )

        case .suggestVoice:
            let characterID = try identifier(arguments.values["characterRecordID"])
            let character = try record(in: context, id: characterID)
            let kind = try schema(for: character, in: context).recordKind
            guard kind == "character" || (kind == "record" && context.project.characters.contains(where: {
                $0.recordID == characterID || $0.id == characterID
            })) else {
                throw ToolValidationError.invalidRelationshipTarget
            }
            let style = try text(arguments.values["styleDescription"], maximumBytes: 240)
            return ToolProposal(
                tool: tool,
                status: "Voice suggestion proposed.",
                result: .proposedEvent(
                    .voiceSuggestion(
                        characterRecordID: characterID,
                        styleDescription: style
                    )
                )
            )

        case .attachAsset:
            let assetID = try identifier(arguments.values["assetID"])
            try assetReference(in: context, id: assetID)
            let targetID = try identifier(arguments.values["targetRecordID"])
            let target = try record(in: context, id: targetID)
            let fieldID = try identifier(arguments.values["fieldID"])
            guard let descriptor = try schema(for: target, in: context).fields.first(where: {
                $0.id == fieldID
            }) else {
                throw ToolValidationError.fieldNotFound
            }
            guard isAssetCompatibleType(descriptor.valueType) else {
                throw ToolValidationError.invalidFieldValue
            }
            if let allowedValues = try enumValues(for: descriptor),
               allowedValues.contains(assetID) == false {
                throw ToolValidationError.invalidFieldValue
            }
            return ToolProposal(
                tool: tool,
                status: "Asset attachment proposed.",
                result: .proposedEvent(
                    .assetAttachment(
                        assetID: assetID,
                        targetRecordID: targetID,
                        fieldID: fieldID
                    )
                )
            )
        }
    }

    public func validate(
        toolName: String,
        encodedArguments: Data,
        context: GMToolValidationContext,
        rollID: UUID? = nil
    ) throws -> ToolProposal {
        try validateEncodedArgumentCap(toolName: toolName, encodedArguments: encodedArguments)
        try preflightJSON(encodedArguments)
        let values: [String: JSONValue]
        do {
            values = try JSONDecoder().decode([String: JSONValue].self, from: encodedArguments)
        } catch {
            throw ToolValidationError.malformedArguments
        }
        let arguments: ProviderToolArguments
        do {
            arguments = try ProviderToolArguments(values: values)
        } catch let error as ProviderToolArguments.ValidationError {
            if case .payloadTooLarge(let maximum, let actual) = error {
                throw ToolValidationError.argumentsTooLarge(
                    maximumBytes: maximum,
                    actualBytes: actual
                )
            }
            throw ToolValidationError.malformedArguments
        } catch {
            throw ToolValidationError.malformedArguments
        }
        return try validate(
            toolName: toolName,
            arguments: arguments,
            context: context,
            rollID: rollID
        )
    }

    /// Validates only the known-tool and encoded-payload boundary. It intentionally
    /// does not parse the payload, so the cap can be tested independently of the
    /// smaller per-field limits enforced by normal tool validation.
    public func validateEncodedArgumentCap(
        toolName: String,
        encodedArguments: Data
    ) throws {
        guard GMToolRegistry.all.resolve(toolName) != nil else {
            throw ToolValidationError.unknownTool
        }
        guard encodedArguments.count <= Self.maximumArgumentBytes else {
            throw ToolValidationError.argumentsTooLarge(
                maximumBytes: Self.maximumArgumentBytes,
                actualBytes: encodedArguments.count
            )
        }
    }

    public func validate(
        toolName: String,
        encodedArguments: String,
        context: GMToolValidationContext,
        rollID: UUID? = nil
    ) throws -> ToolProposal {
        guard let data = encodedArguments.data(using: .utf8) else {
            throw ToolValidationError.malformedArguments
        }
        return try validate(
            toolName: toolName,
            encodedArguments: data,
            context: context,
            rollID: rollID
        )
    }

    private func validateContext(_ context: GMToolValidationContext) throws {
        guard context.projection.campaignID == context.campaignID else {
            throw ToolValidationError.campaignOwnershipMismatch
        }
        if let importedProjectID = context.projection.importedProjectID,
           importedProjectID != context.project.id {
            throw ToolValidationError.campaignOwnershipMismatch
        }
        guard Set(context.project.records.map(\.id)).count == context.project.records.count,
              context.project.records.allSatisfy({ isValidIdentifier($0.id) }),
              context.project.records.allSatisfy({ record in
                  isValidIdentifier(record.fileTypeID)
                      && context.project.schemas.contains(where: { $0.id == record.fileTypeID })
                      && Set(record.fields.map(\.id)).count == record.fields.count
                      && record.fields.allSatisfy { isValidIdentifier($0.id) }
              }),
              Set(context.project.schemas.map(\.id)).count == context.project.schemas.count,
              context.project.schemas.allSatisfy({
                  isValidIdentifier($0.id) && isSafeRecordKind($0.recordKind)
              }),
              context.project.schemas.allSatisfy({ schema in
                  Set(schema.fields.map(\.id)).count == schema.fields.count
                      && schema.fields.allSatisfy { isValidIdentifier($0.id) }
              }) else {
            throw ToolValidationError.invalidIdentifier
        }
        let recordIDs = Set(context.project.records.map(\.id))
        for relationship in context.project.relationships {
            guard isValidIdentifier(relationship.id),
                  isValidIdentifier(relationship.kind),
                  recordIDs.contains(relationship.sourceRecordID),
                  relationship.targetRecordIDs.allSatisfy({
                      recordIDs.contains($0) && isValidIdentifier($0)
                  }) else {
                throw ToolValidationError.invalidRelationshipTarget
            }
        }
        guard Set(context.project.assets.map(\.id)).count == context.project.assets.count,
              context.project.assets.allSatisfy({
                  isValidIdentifier($0.id)
                      && canonicalRelativePath($0.relativePath) == $0.relativePath
              }) else {
            throw ToolValidationError.invalidAssetReference
        }
        try validateImportedAssets(context)
        try validateAssetReferences(context)
    }

    private func validateArgumentShape(
        _ values: [String: JSONValue],
        for tool: GMTool
    ) throws {
        let definition = GMToolRegistry.all.definition(for: tool)
        guard values.count <= Self.maximumArgumentFields else {
            throw ToolValidationError.unknownArgument
        }
        guard Set(values.keys).isSubset(of: definition.allowedArguments) else {
            throw ToolValidationError.unknownArgument
        }
        guard definition.requiredArguments.isSubset(of: values.keys) else {
            throw ToolValidationError.missingArgument
        }
        var nodeCount = 0
        for (argumentName, argumentValue) in values {
            if tool == .patchRecord, argumentName == "fieldsJSON" {
                try validatePatchJSONArgument(argumentValue)
            } else if Self.identifierArgumentNames.contains(argumentName) {
                _ = try identifier(argumentValue)
            } else {
                try validateJSONValue(argumentValue, depth: 0, nodeCount: &nodeCount)
            }
        }
    }

    private func validatePatchJSONArgument(_ value: JSONValue) throws {
        guard case .string(let encodedFields) = value,
              encodedFields.utf8.count <= Self.maximumArgumentBytes,
              encodedFields.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0.value == 0x09 }),
              let data = encodedFields.data(using: .utf8) else {
            throw ToolValidationError.malformedArguments
        }
        try preflightJSON(data)
        guard let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw ToolValidationError.malformedArguments
        }
        var nodeCount = 0
        try validateJSONValue(decoded, depth: 0, nodeCount: &nodeCount)
    }

    private func validateJSONValue(
        _ jsonValue: JSONValue,
        depth: Int,
        nodeCount: inout Int
    ) throws {
        nodeCount += 1
        guard nodeCount <= Self.maximumJSONNodes, depth <= Self.maximumJSONDepth else {
            throw ToolValidationError.unsafeArgument
        }
        switch jsonValue {
        case .string(let stringValue):
            try safeText(stringValue, maximumBytes: Self.maximumStringBytes)
        case .array(let jsonValues):
            guard jsonValues.count <= Self.maximumJSONNodes else {
                throw ToolValidationError.unsafeArgument
            }
            for jsonValue in jsonValues {
                try validateJSONValue(jsonValue, depth: depth + 1, nodeCount: &nodeCount)
            }
        case .object(let objectValues):
            guard objectValues.count <= Self.maximumJSONNodes else {
                throw ToolValidationError.unsafeArgument
            }
            for (key, jsonValue) in objectValues {
                guard key.utf8.count <= Self.maximumIdentifierBytes,
                      isUnsafeFieldName(key) == false,
                      containsUnsafePayload(key) == false else {
                    throw ToolValidationError.unsafeArgument
                }
                try safeText(key, maximumBytes: Self.maximumIdentifierBytes)
                try validateJSONValue(jsonValue, depth: depth + 1, nodeCount: &nodeCount)
            }
        case .integer, .number, .bool, .null:
            break
        }
    }

    private func record(
        in context: GMToolValidationContext,
        id: String
    ) throws -> NormalizedRecord {
        guard let record = context.project.records.first(where: { $0.id == id }) else {
            throw ToolValidationError.recordNotFound
        }
        _ = try schema(for: record, in: context)
        return record
    }

    private func schema(
        for record: NormalizedRecord,
        in context: GMToolValidationContext
    ) throws -> NormalizedSchemaDescriptor {
        guard let schema = context.project.schemas.first(where: {
            $0.id == record.fileTypeID
        }) else {
            throw ToolValidationError.schemaNotFound
        }
        try validateSchema(schema)
        return schema
    }

    private func validatedSearchRecord(
        _ record: NormalizedRecord,
        in context: GMToolValidationContext
    ) throws -> (schema: NormalizedSchemaDescriptor, fields: [String: JSONValue]) {
        guard isValidIdentifier(record.id),
              containsUnsafePayload(record.id) == false else {
            throw ToolValidationError.invalidIdentifier
        }
        let schema = try schema(for: record, in: context)
        guard isSafeRecordKind(schema.recordKind) else {
            throw ToolValidationError.invalidFieldValue
        }
        let descriptors = Dictionary(uniqueKeysWithValues: schema.fields.map { ($0.id, $0) })
        guard Set(record.fields.map(\.id)).count == record.fields.count else {
            throw ToolValidationError.invalidFieldValue
        }
        try validateSearchFields(
            record.fields.reduce(into: [String: JSONValue]()) { values, field in
                values[field.id] = field.value
            },
            descriptors: descriptors,
            sourceRecordID: record.id,
            in: context
        )

        let projectionFields = context.projection.records[record.id]
        if let projectionFields {
            try validateSearchFields(
                projectionFields,
                descriptors: descriptors,
                sourceRecordID: record.id,
                in: context
            )
        }

        var fields = record.fields.reduce(into: [String: JSONValue]()) { values, field in
            values[field.id] = field.value
        }
        if let projectionFields {
            for (fieldID, value) in projectionFields {
                fields[fieldID] = value
            }
        }
        return (schema, fields)
    }

    private func validateSearchFields(
        _ fields: [String: JSONValue],
        descriptors: [String: NormalizedFieldDescriptor],
        sourceRecordID: String,
        in context: GMToolValidationContext
    ) throws {
        guard fields.keys.allSatisfy({
            isValidIdentifier($0)
                && containsUnsafePayload($0) == false
                && descriptors[$0] != nil
        }) else {
            throw ToolValidationError.invalidFieldValue
        }
        for fieldID in fields.keys.sorted() {
            guard let descriptor = descriptors[fieldID],
                  isSafeRecordValue(fields[fieldID]!) else {
                throw ToolValidationError.invalidFieldValue
            }
            guard try valueMatchesType(
                fields[fieldID]!,
                matches: descriptor.valueType,
                descriptor: descriptor,
                sourceRecordID: sourceRecordID,
                in: context
            ) else {
                throw ToolValidationError.invalidFieldValue
            }
        }
    }

    private func validateSchema(_ schema: NormalizedSchemaDescriptor) throws {
        guard isValidIdentifier(schema.id),
              containsUnsafePayload(schema.id) == false,
              isSafeRecordKind(schema.recordKind),
              schema.fields.count <= Self.maximumJSONNodes,
              Set(schema.fields.map(\.id)).count == schema.fields.count else {
            throw ToolValidationError.invalidFieldValue
        }

        var schemaNodeCount = 0
        try validateJSONValue(
            .object(schema.extensionPayload),
            depth: 0,
            nodeCount: &schemaNodeCount
        )

        for field in schema.fields {
            guard isValidIdentifier(field.id),
                  containsUnsafePayload(field.id) == false,
                  field.name.isEmpty == false else {
                throw ToolValidationError.invalidFieldValue
            }
            try safeText(field.name, maximumBytes: Self.maximumStringBytes)
            try safeText(field.valueType, maximumBytes: Self.maximumIdentifierBytes)
            var fieldNodeCount = 0
            try validateJSONValue(
                .object(field.extensionPayload),
                depth: 0,
                nodeCount: &fieldNodeCount
            )
            let type = deterministicLowercased(
                field.valueType.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard Self.supportedFieldTypes.contains(type) else {
                throw ToolValidationError.invalidFieldValue
            }
            if type == "array" || type == "list" {
                guard let elementType = try arrayElementType(for: field),
                      Self.supportedFieldTypes.contains(
                          deterministicLowercased(
                              elementType.trimmingCharacters(in: .whitespacesAndNewlines)
                          )
                      ) else {
                    throw ToolValidationError.invalidFieldValue
                }
            }
            _ = try enumValues(for: field)
            if ["record", "recordid", "reference", "relationship"].contains(type) {
                _ = try relationshipKinds(for: field)
            }
        }
    }

    private func patchFields(
        _ value: JSONValue?,
        record: NormalizedRecord,
        context: GMToolValidationContext
    ) throws -> [String: JSONValue] {
        guard case .string(let encodedFields) = value,
              encodedFields.utf8.count <= Self.maximumArgumentBytes,
              encodedFields.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0.value == 0x09 }) else {
            throw ToolValidationError.wrongArgumentType
        }
        guard let data = encodedFields.data(using: .utf8) else {
            throw ToolValidationError.malformedArguments
        }
        try preflightJSON(data)
        guard let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
              case .object(let fields) = decoded,
              fields.isEmpty == false,
              fields.count <= Self.maximumPatchFields else {
            throw ToolValidationError.malformedArguments
        }
        var result: [String: JSONValue] = [:]
        var nodeCount = 0
        try validateJSONValue(decoded, depth: 0, nodeCount: &nodeCount)
        let schema = try schema(for: record, in: context)
        for (fieldID, fieldValue) in fields {
            guard let descriptor = schema.fields.first(where: { $0.id == fieldID }) else {
                throw ToolValidationError.fieldNotFound
            }
            if descriptor.isRequired, case .null = fieldValue {
                throw ToolValidationError.invalidFieldValue
            }
            guard try valueMatchesType(
                fieldValue,
                matches: descriptor.valueType,
                descriptor: descriptor,
                sourceRecordID: record.id,
                in: context
            ) else {
                throw ToolValidationError.invalidFieldValue
            }
            result[fieldID] = fieldValue
        }
        return result
    }

    private func valueMatchesType(
        _ candidate: JSONValue,
        matches valueType: String,
        descriptor: NormalizedFieldDescriptor,
        sourceRecordID: String,
        in context: GMToolValidationContext
    ) throws -> Bool {
        let type = deterministicLowercased(
            valueType.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let allowedValues = try enumValues(for: descriptor) {
            guard case .string(let actual) = candidate, allowedValues.contains(actual) else {
                return false
            }
        }
        switch type {
        case "string", "text", "richtext":
            guard case .string = candidate else { return false }
            return true
        case "integer", "int":
            if case .integer = candidate { return true }
            return false
        case "number", "double", "float":
            switch candidate {
            case .integer, .number: return true
            default: return false
            }
        case "boolean", "bool":
            if case .bool = candidate { return true }
            return false
        case "array", "list":
            guard case .array(let values) = candidate else { return false }
            guard let elementType = try arrayElementType(for: descriptor) else {
                return false
            }
            for element in values {
                guard try valueMatchesType(
                    element,
                    matches: elementType,
                    descriptor: descriptor,
                    sourceRecordID: sourceRecordID,
                    in: context
                ) else { return false }
            }
            return true
        case "string[]", "recordid[]", "reference[]", "relationship[]", "records", "recordids",
             "references", "relationshipids":
            guard case .array(let values) = candidate else { return false }
            let elementType: String
            if type == "string[]" {
                elementType = "string"
            } else if type == "recordids" || type == "references" || type == "relationshipids" {
                elementType = "recordID"
            } else {
                elementType = String(type.dropLast(2))
            }
            for element in values {
                guard try valueMatchesType(
                    element,
                    matches: elementType,
                    descriptor: descriptor,
                    sourceRecordID: sourceRecordID,
                    in: context
                ) else { return false }
            }
            return true
        case "object", "map":
            if case .object = candidate { return true }
            return false
        case "json", "any", "value":
            return true
        case "record", "recordid", "reference", "relationship":
            guard case .string(let id) = candidate else { return false }
            try validateRecordTarget(
                id,
                sourceRecordID: sourceRecordID,
                descriptor: descriptor,
                in: context
            )
            return true
        case "assetid", "asset", "assetreference", "image":
            guard case .string(let id) = candidate else { return false }
            _ = try assetReference(in: context, id: id)
            return true
        case "assetids", "assets", "assetreferences", "images",
             "assetid[]", "asset[]", "assetreference[]", "image[]":
            guard case .array(let values) = candidate else { return false }
            for candidate in values {
                guard case .string(let id) = candidate else { return false }
                _ = try assetReference(in: context, id: id)
            }
            return true
        default:
            throw ToolValidationError.invalidFieldValue
        }
    }

    private func validateRecordTarget(
        _ id: String,
        sourceRecordID: String,
        descriptor: NormalizedFieldDescriptor,
        in context: GMToolValidationContext
    ) throws {
        let targetID = try identifier(.string(id))
        guard context.project.records.contains(where: { $0.id == targetID }) else {
            throw ToolValidationError.invalidRelationshipTarget
        }
        let kinds = try relationshipKinds(for: descriptor)
        let matchingRelationships = context.project.relationships.filter {
            $0.sourceRecordID == sourceRecordID && kinds.contains($0.kind)
        }
        guard matchingRelationships.isEmpty == false,
              matchingRelationships.contains(where: { $0.targetRecordIDs.contains(targetID) }) else {
            throw ToolValidationError.invalidRelationshipTarget
        }
    }

    private func assetReference(
        in context: GMToolValidationContext,
        id: String
    ) throws -> String {
        if let asset = context.importedAssets.first(where: { $0.assetID == id }) {
            guard let declaredAsset = context.project.assets.first(where: { $0.id == asset.assetID }),
                  isValidIdentifier(asset.assetID),
                  isSHA256(asset.sha256),
                  importedAssetRelativePath(
                      asset.appRelativeURL,
                      campaignID: context.campaignID
                  ) == declaredAsset.relativePath else {
                throw ToolValidationError.invalidAssetReference
            }
            return asset.sha256
        }
        if let reference = context.assetReferences.first(where: { $0.assetID == id }) {
            guard isValidIdentifier(reference.assetID),
                  isSHA256(reference.sha256),
                  reference.campaignID == context.campaignID,
                  reference.campaignID != nil,
                  reference.origin.map({ ["generated", "reference"].contains($0) && isSafeMetadata($0) }) ?? false,
                  reference.path.map({ canonicalRelativePath($0) == $0 }) ?? false else {
                throw ToolValidationError.invalidAssetReference
            }
            return reference.sha256
        }
        throw ToolValidationError.assetNotFound
    }

    private func safeFields(
        for record: NormalizedRecord,
        in context: GMToolValidationContext
    ) throws -> [String: JSONValue] {
        let schema = try schema(for: record, in: context)
        let declaredFields = Dictionary(uniqueKeysWithValues: schema.fields.map { ($0.id, $0) })
        let projectionFields = context.projection.records[record.id]
        var source = projectionFields ?? [:]
        if projectionFields == nil {
            for field in record.fields where source[field.id] == nil {
                source[field.id] = field.value
            }
        }
        var result: [String: JSONValue] = [:]
        var nodeCount = 0
        for key in source.keys.sorted() {
            guard let descriptor = declaredFields[key],
                  isUnsafeFieldName(key) == false,
                  containsUnsafePayload(key) == false,
                  let sourceValue = source[key] else { continue }
            guard let value = sanitizedOutputValue(
                sourceValue,
                depth: 0,
                nodeCount: &nodeCount
            ) else { continue }
            guard (try? valueMatchesType(
                value,
                matches: descriptor.valueType,
                descriptor: descriptor,
                sourceRecordID: record.id,
                in: context
            )) == true else { continue }
            var candidate = result
            candidate[key] = value
            guard serializedBytes(
                GMToolRecordResult(recordID: record.id, fields: candidate)
            ) <= Self.maximumResultBytes else { break }
            result[key] = value
        }
        return result
    }

    private func sanitizedOutputValue(
        _ value: JSONValue,
        depth: Int,
        nodeCount: inout Int
    ) -> JSONValue? {
        nodeCount += 1
        guard nodeCount <= Self.maximumJSONNodes,
              depth <= Self.maximumJSONDepth else { return nil }

        switch value {
        case .string(let value):
            guard value.utf8.count <= Self.maximumStringBytes,
                  containsUnsafePayload(value) == false else { return nil }
            return .string(value)
        case .array(let values):
            var result: [JSONValue] = []
            for value in values {
                if let sanitized = sanitizedOutputValue(
                    value,
                    depth: depth + 1,
                    nodeCount: &nodeCount
                ) {
                    result.append(sanitized)
                }
            }
            return .array(result)
        case .object(let values):
            var result: [String: JSONValue] = [:]
            for key in values.keys.sorted() {
                guard key.utf8.count <= Self.maximumIdentifierBytes,
                      isUnsafeFieldName(key) == false,
                      containsUnsafePayload(key) == false,
                      key.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0.value == 0x09 }),
                      let value = sanitizedOutputValue(
                          values[key]!,
                          depth: depth + 1,
                          nodeCount: &nodeCount
                      ) else { continue }
                result[key] = value
            }
            return .object(result)
        case .number(let value):
            return value.isFinite ? value : nil
        default:
            return value
        }
    }

    private func isSafeRecordValue(_ value: JSONValue) -> Bool {
        var nodeCount = 0
        return isSafeRecordValue(value, depth: 0, nodeCount: &nodeCount)
    }

    private func isSafeRecordValue(
        _ value: JSONValue,
        depth: Int,
        nodeCount: inout Int
    ) -> Bool {
        nodeCount += 1
        guard nodeCount <= Self.maximumJSONNodes,
              depth <= Self.maximumJSONDepth else { return false }
        switch value {
        case .string(let value):
            return value.utf8.count <= Self.maximumStringBytes
                && containsUnsafePayload(value) == false
        case .array(let values):
            for value in values {
                guard isSafeRecordValue(value, depth: depth + 1, nodeCount: &nodeCount) else {
                    return false
                }
            }
            return true
        case .object(let values):
            for (key, value) in values {
                guard key.utf8.count <= Self.maximumIdentifierBytes,
                      isUnsafeFieldName(key) == false,
                      containsUnsafePayload(key) == false,
                      key.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0.value == 0x09 }),
                      isSafeRecordValue(value, depth: depth + 1, nodeCount: &nodeCount) else {
                    return false
                }
            }
            return true
        case .number(let value):
            return value.isFinite
        default:
            return true
        }
    }

    private func serializedBytes<T: Encodable>(_ value: T) -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value).count) ?? (Self.maximumResultBytes + 1)
    }

    private func preflightJSON(_ data: Data) throws {
        var preflight = try RawJSONPreflight(
            data: data,
            maximumDepth: Self.maximumJSONDepth,
            maximumNodes: Self.maximumJSONNodes
        )
        try preflight.validate()
    }

    private func identifier(_ value: JSONValue?) throws -> String {
        guard case .string(let value) = value else {
            throw ToolValidationError.wrongArgumentType
        }
        guard isValidIdentifier(value),
              containsUnsafePayload(value) == false else {
            throw ToolValidationError.invalidIdentifier
        }
        return value
    }

    private func integer(_ value: JSONValue?) throws -> Int {
        guard case .integer(let value) = value,
              let converted = Int(exactly: value) else {
            throw ToolValidationError.wrongArgumentType
        }
        return converted
    }

    private func text(
        _ value: JSONValue?,
        maximumBytes: Int
    ) throws -> String {
        guard case .string(let value) = value else {
            throw ToolValidationError.wrongArgumentType
        }
        try safeText(value, maximumBytes: maximumBytes)
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw ToolValidationError.invalidFieldValue
        }
        return value
    }

    private func optionalText(
        _ value: JSONValue?,
        maximumBytes: Int
    ) throws -> String? {
        guard let value else { throw ToolValidationError.missingArgument }
        if case .null = value { return nil }
        return try text(value, maximumBytes: maximumBytes)
    }

    private func safeText(_ value: String, maximumBytes: Int) throws {
        guard value.utf8.count <= maximumBytes,
              value.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0.value == 0x09 }) else {
            throw ToolValidationError.unsafeArgument
        }
        guard containsUnsafePayload(value) == false else {
            throw ToolValidationError.unsafeArgument
        }
    }

    private func rollExpression(_ value: JSONValue?) throws -> String {
        let expression = try text(value, maximumBytes: 64)
        guard let parsed = try? DiceExpression(expression) else {
            throw ToolValidationError.invalidRollExpression
        }
        return parsed.canonicalNotation
    }

    private func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private func isUnsafeFieldName(_ value: String) -> Bool {
        containsSensitiveTerm(in: value)
    }

    private func containsUnsafePayload(_ value: String) -> Bool {
        var current = value
        for _ in 0...Self.maximumPercentDecodingPasses {
            guard containsUnsafePayloadWithoutDecoding(current) == false else {
                return true
            }
            guard current.contains("%") else { return false }
            guard let decoded = current.removingPercentEncoding,
                  decoded != current else {
                return true
            }
            current = decoded
        }
        return true
    }

    private func containsUnsafePayloadWithoutDecoding(_ value: String) -> Bool {
        let lowercased = deterministicLowercased(value)
        let hasProviderToken = lowercased.contains("sk-") || lowercased.contains("aiza")
        guard hasProviderToken == false,
              containsSensitiveTerm(in: value) == false else {
            return true
        }
        guard value.range(
            of: #"(^|[^A-Za-z0-9+.-])([A-Za-z][A-Za-z0-9+.-]*):"#,
            options: .regularExpression
        ) == nil else {
            return true
        }
        guard value.contains("\\") == false else {
            return true
        }
        let commandForm = lowercased.replacingOccurrences(
            of: #"\s+"#, with: " ", options: .regularExpression
        )
        let blockedSubstrings = [
            "://", "file:", "data:", "javascript:", "#!/", "$(", "`",
            "&&", "||", "|", ";", "../", "..\\", "<script", ".exe", ".app", ".dylib", ".wasm",
            ".sh", "powershell", "pwsh", "osascript", "chmod ", "curl ", "wget ",
            "bash ", "sh -c", "cmd /c", "cmd /k", "python ", "python -c", "python3 -c", "rm -"
        ]
        guard blockedSubstrings.contains(where: { commandForm.contains($0) }) == false else {
            return true
        }
        guard isStandaloneOrPathLikeExecutable(value) == false,
              isCommandLikePayload(value) == false else {
            return true
        }
        if value.range(of: "(^|[\\s])(/|~/|[A-Za-z]:[\\\\/])", options: .regularExpression) != nil
            || isPathLikePayload(value) {
            return true
        }
        return false
    }

    private func isStandaloneOrPathLikeExecutable(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.range(of: #"^[A-Za-z0-9._~/-]+$"#, options: .regularExpression) != nil else {
            return false
        }
        let lastComponent = trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? trimmed
        let extensionValue = lastComponent
            .split(separator: ".", omittingEmptySubsequences: false)
            .last
            .map(String.init)
            .map(deterministicLowercased)
        return extensionValue.map(Self.executableExtensions.contains) ?? false
    }

    private func isCommandLikePayload(_ value: String) -> Bool {
        let tokens = value.split(whereSeparator: { $0.isWhitespace })
        for token in tokens {
            let words = token.split(whereSeparator: { character in
                character.isLetter == false && character.isNumber == false
            })
            guard words.contains(where: { Self.executableCommandNames.contains(String($0)) }) else {
                continue
            }
            // A command token on its own is still rejected. When it is followed
            // by whitespace, any argument makes the whole phrase command-like;
            // this intentionally does not inspect the argument's vocabulary.
            return true
        }
        return false
    }

    private func normalizedAlphanumeric(_ value: String) -> String {
        deterministicLowercased(value).unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private func containsSensitiveTerm(in value: String) -> Bool {
        let normalized = normalizedAlphanumeric(value)
        return Self.sensitiveTerms.contains { normalized.contains($0) }
    }

    private func isPathLikePayload(_ value: String) -> Bool {
        guard value.contains("/") || value.contains("\\") else { return false }
        let lowercased = deterministicLowercased(value)
        if value.range(of: #"\s"#, options: .regularExpression) != nil {
            return true
        }
        if lowercased.contains("/"),
           lowercased.range(of: #"(^|\s)([a-z0-9._-]+/)+[a-z0-9._-]+(\s|$)"#, options: .regularExpression) != nil {
            return true
        }
        let lastComponent = value.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? value
        let extensionValue = lastComponent
            .split(separator: ".", omittingEmptySubsequences: false)
            .last
            .map(String.init)
            .map(deterministicLowercased)
        return extensionValue.map(Self.executableExtensions.contains) ?? false
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        value.utf8.count <= Self.maximumIdentifierBytes
            && value.range(of: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$", options: .regularExpression) != nil
    }

    private func isSafeRecordKind(_ value: String) -> Bool {
        guard isValidIdentifier(value), containsUnsafePayload(value) == false else {
            return false
        }
        switch deterministicLowercased(value) {
        case "record", "scene", "clock", "character", "map":
            return value == deterministicLowercased(value)
        default:
            return true
        }
    }

    private func isAssetCompatibleType(_ valueType: String) -> Bool {
        // Array fields use the plural forms and receive one validated attachment at a time.
        switch deterministicLowercased(valueType.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case "assetid", "asset", "assetreference", "image",
             "assetids", "assets", "assetreferences", "images",
             "assetid[]", "asset[]", "assetreference[]", "image[]":
            return true
        default:
            return false
        }
    }

    private func enumValues(
        for descriptor: NormalizedFieldDescriptor
    ) throws -> [String]? {
        for key in ["enum", "enumValues", "allowedValues"] {
            guard let value = descriptor.extensionPayload[key] else { continue }
            guard case .array(let values) = value,
                  values.allSatisfy({
                      if case .string = $0 { return true }
                      return false
                  }) else {
                throw ToolValidationError.invalidFieldValue
            }
            let strings = values.compactMap { value in
                guard case .string(let string) = value else { return nil }
                return string
            }
            guard strings.allSatisfy({ containsUnsafePayload($0) == false }) else {
                throw ToolValidationError.invalidFieldValue
            }
            return strings
        }
        return nil
    }

    private func arrayElementType(
        for descriptor: NormalizedFieldDescriptor
    ) throws -> String? {
        for key in ["elementType", "itemType", "elementValueType", "arrayElementType"] {
            guard let value = descriptor.extensionPayload[key] else { continue }
            guard case .string(let elementType) = value,
                  elementType.isEmpty == false else {
                throw ToolValidationError.invalidFieldValue
            }
            return elementType
        }
        return nil
    }

    private func relationshipKinds(
        for descriptor: NormalizedFieldDescriptor
    ) throws -> Set<String> {
        var kinds = Set([descriptor.id, descriptor.name, descriptor.valueType])
        for key in ["relationshipKind", "relationshipKindID", "kind", "relationship"] {
            guard let value = descriptor.extensionPayload[key] else { continue }
            guard case .string(let kind) = value, kind.isEmpty == false else {
                throw ToolValidationError.invalidFieldValue
            }
            kinds.insert(kind)
        }
        return kinds
    }

    private func validateImportedAssets(_ context: GMToolValidationContext) throws {
        let projectAssets = Dictionary(uniqueKeysWithValues: context.project.assets.map { ($0.id, $0) })
        var assetIDs = Set<String>()
        for asset in context.importedAssets {
            guard let declaredAsset = projectAssets[asset.assetID],
                  assetIDs.insert(asset.assetID).inserted,
                  isValidIdentifier(asset.assetID),
                  isSHA256(asset.sha256),
                  importedAssetRelativePath(
                      asset.appRelativeURL,
                      campaignID: context.campaignID
                  ) == declaredAsset.relativePath else {
                throw ToolValidationError.invalidAssetReference
            }
        }
    }

    private func validateAssetReferences(_ context: GMToolValidationContext) throws {
        var assetIDs = Set(context.importedAssets.map(\.assetID))
        for reference in context.assetReferences {
            guard assetIDs.insert(reference.assetID).inserted,
                  isValidIdentifier(reference.assetID),
                  isSHA256(reference.sha256) else {
                throw ToolValidationError.invalidAssetReference
            }
            guard let campaignID = reference.campaignID,
                  campaignID == context.campaignID else {
                if reference.campaignID != nil {
                    throw ToolValidationError.campaignOwnershipMismatch
                }
                throw ToolValidationError.invalidAssetReference
            }
            guard let origin = reference.origin,
                  ["generated", "reference"].contains(origin),
                  let path = reference.path,
                  canonicalRelativePath(path) == path,
                  isSafeMetadata(origin) else {
                throw ToolValidationError.invalidAssetReference
            }
        }
    }

    private func isSafeMetadata(_ value: String) -> Bool {
        value.isEmpty == false
            && value.utf8.count <= 128
            && containsUnsafePayload(value) == false
    }

    private func canonicalRelativePath(_ value: String) -> String? {
        guard value.isEmpty == false,
              value.utf8.count <= Self.maximumStringBytes,
              value.contains("\0") == false,
              value.contains("\\") == false,
              value.contains("%") == false,
              value.range(of: #"[\x00-\x1F\x7F]"#, options: .regularExpression) == nil,
              value.hasPrefix("/") == false,
              value.hasPrefix("//") == false,
              let decoded = value.removingPercentEncoding,
              decoded == value,
              value.range(
                  of: #"(^|[^A-Za-z0-9+.-])([A-Za-z][A-Za-z0-9+.-]*):"#,
                  options: .regularExpression
              ) == nil,
              let url = URL(string: value),
              url.scheme == nil,
              url.host == nil,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.fragment == nil else {
            return nil
        }
        guard containsUnsafePathCharacters(decoded) == false,
              containsSensitiveTerm(in: decoded) == false,
              decoded.range(of: #"\s"#, options: .regularExpression) == nil else { return nil }
        guard let canonical = try? CanonicalPath(decoded, maximumDepth: 32),
              canonical.string == decoded else {
            return nil
        }
        let extensionValue: String?
        if let lastComponent = decoded.split(separator: "/").last {
            extensionValue = lastComponent
                .split(separator: ".", omittingEmptySubsequences: false)
                .last
                .map { deterministicLowercased(String($0)) }
        } else {
            extensionValue = nil
        }
        guard extensionValue.map(Self.executableExtensions.contains) != true else {
            return nil
        }
        return canonical.string
    }

    private func importedAssetRelativePath(
        _ url: URL,
        campaignID: UUID
    ) -> String? {
        guard isSafeAppRelativeURL(url) else { return nil }
        let components = url.relativeString.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        let expectedCampaignComponent = campaignID.uuidString.lowercased()
        guard components.count >= 3,
              components[0] == "Campaigns",
              components[1] == expectedCampaignComponent else {
            return nil
        }
        let relativePath = components.dropFirst(2).joined(separator: "/")
        guard let canonical = canonicalRelativePath(relativePath),
              canonical == relativePath else {
            return nil
        }
        return canonical
    }

    private func containsUnsafePathCharacters(_ value: String) -> Bool {
        let lowercased = deterministicLowercased(value)
        return [";", "|", "&", "$", "`", "(", ")", "<", ">", "*", "?", "[", "]"]
            .contains { value.contains($0) }
            || lowercased.contains("#!")
            || lowercased.contains("../")
            || lowercased.contains("..\\")
    }

    private func isSafeAppRelativeURL(_ url: URL) -> Bool {
        guard url.isFileURL == false,
              url.relativeString.removingPercentEncoding == url.relativeString,
              url.scheme == nil,
              url.host == nil,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.fragment == nil,
              let path = canonicalRelativePath(url.path.isEmpty ? url.relativeString : url.path) else {
            return false
        }
        return path == url.path
    }

    private func deterministicLowercased(_ value: String) -> String {
        value.lowercased(with: Self.fixedLocale)
    }
}

public typealias GMToolValidator = ToolValidator

private struct RawJSONPreflight {
    private let bytes: [UInt8]
    private let maximumDepth: Int
    private let maximumNodes: Int
    private var index = 0
    private var nodeCount = 0

    init(data: Data, maximumDepth: Int, maximumNodes: Int) throws {
        guard String(data: data, encoding: .utf8) != nil else {
            throw ToolValidationError.malformedArguments
        }
        self.bytes = Array(data)
        self.maximumDepth = maximumDepth
        self.maximumNodes = maximumNodes
    }

    mutating func validate() throws {
        skipWhitespace()
        guard index < bytes.count else {
            throw ToolValidationError.malformedArguments
        }
        try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else {
            throw ToolValidationError.malformedArguments
        }
    }

    private mutating func parseValue(depth: Int) throws {
        nodeCount += 1
        guard nodeCount <= maximumNodes else {
            throw ToolValidationError.unsafeArgument
        }
        guard depth <= maximumDepth, index < bytes.count else {
            throw ToolValidationError.unsafeArgument
        }

        switch bytes[index] {
        case 0x22:
            _ = try parseString()
        case 0x7B:
            try parseObject(depth: depth)
        case 0x5B:
            try parseArray(depth: depth)
        case 0x74:
            try parseLiteral(Array("true".utf8))
        case 0x66:
            try parseLiteral(Array("false".utf8))
        case 0x6E:
            try parseLiteral(Array("null".utf8))
        case 0x2D, 0x30...0x39:
            try parseNumber()
        default:
            throw ToolValidationError.malformedArguments
        }
    }

    private mutating func parseObject(depth: Int) throws {
        index += 1
        skipWhitespace()
        if consume(0x7D) {
            return
        }

        var keys = Set<String>()
        while true {
            guard index < bytes.count, bytes[index] == 0x22 else {
                throw ToolValidationError.malformedArguments
            }
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw ToolValidationError.malformedArguments
            }
            skipWhitespace()
            guard consume(0x3A) else {
                throw ToolValidationError.malformedArguments
            }
            skipWhitespace()
            try parseValue(depth: depth + 1)
            skipWhitespace()
            if consume(0x7D) {
                return
            }
            guard consume(0x2C) else {
                throw ToolValidationError.malformedArguments
            }
            skipWhitespace()
        }
    }

    private mutating func parseArray(depth: Int) throws {
        index += 1
        skipWhitespace()
        if consume(0x5D) {
            return
        }

        while true {
            try parseValue(depth: depth + 1)
            skipWhitespace()
            if consume(0x5D) {
                return
            }
            guard consume(0x2C) else {
                throw ToolValidationError.malformedArguments
            }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        guard consume(0x22) else {
            throw ToolValidationError.malformedArguments
        }

        var stringBytes: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case 0x22:
                return String(decoding: stringBytes, as: UTF8.self)
            case 0x5C:
                try parseEscape(into: &stringBytes)
            case 0x00...0x1F:
                throw ToolValidationError.malformedArguments
            default:
                stringBytes.append(byte)
            }
        }
        throw ToolValidationError.malformedArguments
    }

    private mutating func parseEscape(into stringBytes: inout [UInt8]) throws {
        guard index < bytes.count else {
            throw ToolValidationError.malformedArguments
        }
        let escaped = bytes[index]
        index += 1
        switch escaped {
        case 0x22, 0x2F, 0x5C:
            stringBytes.append(escaped)
        case 0x62:
            stringBytes.append(0x08)
        case 0x66:
            stringBytes.append(0x0C)
        case 0x6E:
            stringBytes.append(0x0A)
        case 0x72:
            stringBytes.append(0x0D)
        case 0x74:
            stringBytes.append(0x09)
        case 0x75:
            let codeUnit = try parseUnicodeCodeUnit()
            if (0xD800...0xDBFF).contains(codeUnit) {
                guard index + 5 < bytes.count,
                      bytes[index] == 0x5C,
                      bytes[index + 1] == 0x75 else {
                    throw ToolValidationError.malformedArguments
                }
                index += 2
                let lowCodeUnit = try parseUnicodeCodeUnit()
                guard (0xDC00...0xDFFF).contains(lowCodeUnit) else {
                    throw ToolValidationError.malformedArguments
                }
                let scalarValue = 0x1_0000
                    + ((UInt32(codeUnit) - 0xD800) << 10)
                    + (UInt32(lowCodeUnit) - 0xDC00)
                guard let scalar = UnicodeScalar(scalarValue) else {
                    throw ToolValidationError.malformedArguments
                }
                stringBytes.append(contentsOf: String(scalar).utf8)
            } else {
                guard (0xDC00...0xDFFF).contains(codeUnit) == false,
                      let scalar = UnicodeScalar(UInt32(codeUnit)) else {
                    throw ToolValidationError.malformedArguments
                }
                stringBytes.append(contentsOf: String(scalar).utf8)
            }
        default:
            throw ToolValidationError.malformedArguments
        }
    }

    private mutating func parseUnicodeCodeUnit() throws -> UInt16 {
        guard index + 4 <= bytes.count else {
            throw ToolValidationError.malformedArguments
        }
        var value: UInt16 = 0
        for _ in 0..<4 {
            guard let digit = hexValue(bytes[index]) else {
                throw ToolValidationError.malformedArguments
            }
            value = (value << 4) | UInt16(digit)
            index += 1
        }
        return value
    }

    private mutating func parseLiteral(_ literal: [UInt8]) throws {
        guard bytes[index..<min(index + literal.count, bytes.count)].elementsEqual(literal) else {
            throw ToolValidationError.malformedArguments
        }
        index += literal.count
    }

    private mutating func parseNumber() throws {
        if consume(0x2D) && index >= bytes.count {
            throw ToolValidationError.malformedArguments
        }

        if consume(0x30) {
            if index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                throw ToolValidationError.malformedArguments
            }
        } else {
            guard index < bytes.count, bytes[index] >= 0x31, bytes[index] <= 0x39 else {
                throw ToolValidationError.malformedArguments
            }
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                index += 1
            }
        }

        if consume(0x2E) {
            guard index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 else {
                throw ToolValidationError.malformedArguments
            }
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                index += 1
            }
        }

        if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
            index += 1
            if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D {
                index += 1
            }
            guard index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 else {
                throw ToolValidationError.malformedArguments
            }
            while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 {
                index += 1
            }
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else {
            return false
        }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D:
                index += 1
            default:
                return
            }
        }
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x41 + 10
        case 0x61...0x66: return byte - 0x61 + 10
        default: return nil
        }
    }
}
