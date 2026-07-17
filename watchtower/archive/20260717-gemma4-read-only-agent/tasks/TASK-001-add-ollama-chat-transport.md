# TASK-001 Add Ollama Chat Transport

Group: A (standalone transport foundation)

## Brief

Goal: Add a native Swift transport for streamed `gemma4:cloud` chat and tool-call responses.

Change: No Ollama client -> cancellable actor-backed chat transport with typed models and errors.

How:

- Add exact request and response models for Ollama chat messages, tools, calls, and streamed chunks.
- Send requests to `http://localhost:11434/api/chat` with `gemma4:cloud` and streaming enabled.
- Decode newline-delimited response chunks without buffering the complete response.
- Surface connection, HTTP, decoding, and incomplete-stream failures as typed errors.
- Make one task own each active request and cancel it deterministically.
- Keep raw prompts and response content out of unified logs.
- Add deterministic decoder and cancellation tests without requiring a live cloud account.

Files:

- [app/Atelier/Sources/Atelier/Agent/Ollama/OllamaModels.swift](app/Atelier/Sources/Atelier/Agent/Ollama/OllamaModels.swift) (add request, response, tool, and error models)
- [app/Atelier/Sources/Atelier/Agent/Ollama/OllamaCloudClient.swift](app/Atelier/Sources/Atelier/Agent/Ollama/OllamaCloudClient.swift) (add streaming network transport and cancellation)
- [app/Atelier/Tests/AtelierTests/OllamaCloudClientTests.swift](app/Atelier/Tests/AtelierTests/OllamaCloudClientTests.swift) (cover decoding, status failures, malformed chunks, and cancellation)

Expected result:

- Atelier can stream text and structured tool calls from the local Ollama endpoint.
- Invalid or interrupted streams fail with useful errors and no leaked task.
- Tests run without Ollama credentials or network access.

## Verify

- `swift test --package-path app/Atelier --filter OllamaCloudClientTests` -> all transport tests pass.
- `swift build --package-path app/Atelier` -> the strict-concurrency build passes without warnings.
- Review logs during tests -> no prompt or response content is written.
