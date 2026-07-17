import Foundation

nonisolated enum OllamaRole: String, Codable, Sendable {
    case system
    case user
    case assistant
    case tool
}

nonisolated struct OllamaChatMessage: Codable, Equatable, Sendable {
    let role: OllamaRole
    let content: String
    let toolCalls: [OllamaToolCall]?
    let toolName: String?

    init(
        role: OllamaRole,
        content: String,
        toolCalls: [OllamaToolCall]? = nil,
        toolName: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolName = toolName
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolName = "tool_name"
    }
}

nonisolated struct OllamaToolCall: Codable, Equatable, Sendable {
    let function: OllamaFunctionCall
}

nonisolated struct OllamaFunctionCall: Codable, Equatable, Sendable {
    let name: String
    let arguments: [String: OllamaJSONValue]
}

nonisolated indirect enum OllamaJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: OllamaJSONValue])
    case array([OllamaJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: OllamaJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([OllamaJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

nonisolated struct OllamaToolDefinition: Codable, Equatable, Sendable {
    let type: String
    let function: OllamaFunctionDefinition

    init(function: OllamaFunctionDefinition) {
        type = "function"
        self.function = function
    }
}

nonisolated struct OllamaFunctionDefinition: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let parameters: OllamaToolParameters
}

nonisolated struct OllamaToolParameters: Codable, Equatable, Sendable {
    let type: String
    let properties: [String: OllamaToolProperty]
    let required: [String]

    init(properties: [String: OllamaToolProperty], required: [String]) {
        type = "object"
        self.properties = properties
        self.required = required
    }
}

nonisolated struct OllamaToolProperty: Codable, Equatable, Sendable {
    let type: String
    let description: String
}

nonisolated struct OllamaChatRequest: Codable, Equatable, Sendable {
    let model: String
    let messages: [OllamaChatMessage]
    let tools: [OllamaToolDefinition]
    let stream: Bool

    init(
        messages: [OllamaChatMessage],
        tools: [OllamaToolDefinition],
        model: String = "gemma4:cloud"
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        stream = true
    }
}

nonisolated struct OllamaChatChunk: Codable, Equatable, Sendable {
    let model: String?
    let message: OllamaChatMessage?
    let done: Bool?
    let error: String?

    init(
        model: String? = nil,
        message: OllamaChatMessage? = nil,
        done: Bool? = nil,
        error: String? = nil
    ) {
        self.model = model
        self.message = message
        self.done = done
        self.error = error
    }
}

nonisolated enum OllamaCloudError: LocalizedError, Equatable, Sendable {
    case connection(String)
    case invalidResponse
    case httpStatus(Int, String)
    case decoding(String)
    case remote(String)
    case incompleteStream
    case cancelled

    var errorDescription: String? {
        switch self {
        case .connection:
            return "Could not connect to Ollama."
        case .invalidResponse:
            return "Ollama returned an invalid response."
        case .httpStatus(let status, let message):
            return "Ollama request failed (HTTP \(status)): \(message)"
        case .decoding:
            return "Ollama returned an unreadable streamed response."
        case .remote(let message):
            return "Ollama error: \(message)"
        case .incompleteStream:
            return "Ollama ended the response before completion."
        case .cancelled:
            return "Ollama request cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .connection:
            return "Start Ollama, then try again."
        case .httpStatus(let status, let message):
            return Self.recoverySuggestion(status: status, message: message)
        case .remote(let message):
            return Self.recoverySuggestion(status: nil, message: message)
        case .invalidResponse, .decoding, .incompleteStream, .cancelled:
            return nil
        }
    }

    private static func recoverySuggestion(status: Int?, message: String) -> String? {
        let message = message.lowercased()
        if status == 401 || status == 403 ||
            message.contains("unauthorized") ||
            message.contains("authentication required") ||
            message.contains("not signed in") {
            return "Run `ollama signin`, then try again."
        }
        if message.contains("model") && (
            message.contains("not found") ||
            message.contains("unavailable") ||
            message.contains("does not exist") ||
            message.contains("pull")
        ) {
            return "Run `ollama pull gemma4:cloud`, then try again."
        }
        return nil
    }
}
