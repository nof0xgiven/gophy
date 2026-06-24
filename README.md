# Gophy Desktop

AI-powered call assistant for macOS. Gophy records meetings, transcribes microphone and system audio, surfaces contextual suggestions, answers live questions, prepares meeting briefings, and keeps prior meetings searchable through local RAG.

## Requirements

- macOS 14.4+ for ProcessTap system audio capture
- Apple Silicon (M1+) for on-device MLX inference
- Xcode with the Metal toolchain installed
- About 12GB disk space for the default local models

## Build & Run

Build the macOS app bundle with the repo script:

```bash
./build.sh
open .build/debug/Gophy.app
```

The script uses `xcodebuild` so MLX Metal shaders are compiled, creates `.build/debug/Gophy.app`, copies `Info.plist`, embeds the MLX Metal library bundle, injects local Google OAuth values from `Secrets.xcconfig` when present, and signs the app.

For local Google Calendar OAuth, copy the example config and fill in your credentials:

```bash
cp Secrets.xcconfig.example Secrets.xcconfig
```

`Secrets.xcconfig` is gitignored and must stay local.

For a fast compile check without an app bundle:

```bash
swift build
```

Run tests with:

```bash
swift test
```

## Architecture

Gophy is a Swift 6 macOS app with strict concurrency, actor-backed meeting services, a local SQLite database, and a hybrid AI provider layer. Local MLX models handle on-device inference by default. Cloud providers can take over individual capabilities such as text generation, embeddings, speech-to-text, or vision/OCR.

### Engines

| Engine | Purpose | Default Model |
|--------|---------|---------------|
| TranscriptionEngine | Speech-to-text | WhisperKit large-v3-turbo (1.5GB) |
| TextGenerationEngine | Summaries, suggestions, tool calling | Qwen2.5 7B / Qwen3 8B 4-bit |
| OCREngine | Image and PDF text extraction | Qwen2.5-VL 7B 4-bit (5.3GB) |
| EmbeddingEngine | Semantic search vectors | Multilingual E5 Small (0.47GB) |
| TTSEngine | Read suggestions aloud | MLX Audio TTS |

### Runtime State

- `MeetingSessionController` owns capture, transcription, persistence, and meeting lifecycle events.
- `MeetingEventBroadcaster` publishes transcript, status, suggestion, playback, automation, and error events.
- `MeetingStateTracker` mirrors the current recording status, title, meeting id, duration, and last transcript for the menu bar and overlay.
- SwiftUI view models subscribe to those events instead of polling individual services wherever possible.

## Features

### Real-Time Meeting Transcription

- Concurrent microphone and system audio capture
- Per-speaker transcription with diarization
- Voice activity detection with configurable sensitivity
- System audio via ProcessTap, without Screen Recording permission
- Language detection and configurable language hints
- Pause, resume, and stop lifecycle with persisted meeting records

### Menu Bar and Compact Overlay

- Menu bar extra with current recording status, meeting title, elapsed duration, upcoming meetings, and the latest meeting summary
- One-click instant meeting start from the menu bar
- Upcoming calendar event start controls from the menu bar
- Floating compact overlay toggled with `Command-Shift-G`
- Overlay preview for live status, duration, recent transcript segments, and the latest AI suggestion
- Overlay position persists across app launches
- Auto-show overlay while a meeting is active, controlled by the `autoShowOverlay` user default

### Contextual Suggestions

- Auto-generated suggestions during active meetings
- Manual refresh for a new suggestion on demand
- Streaming token display with an in-progress cursor
- Suggestions use recent transcript plus RAG context from documents and past meetings
- Empty provider responses are dropped before display, notification, and broadcast
- Suggestions can be copied, collapsed, dismissed, rated helpful, or rated not relevant
- Dismissal and feedback state persists in the database
- Suggestions can be read aloud through local TTS playback
- Desktop notifications announce completed suggestions

### Quick Actions

- Quick Ask answers ad hoc questions against the recent live transcript
- Copy the latest suggestion to the pasteboard
- Mark important moments during a meeting
- Pause or resume automatic suggestions without stopping recording
- Quick Ask responses stay visible after streaming completes

### Meeting Briefings

- Upcoming meetings include a briefing button
- Briefings show meeting time, location, attendees, related past meetings, linked documents, previous summary text, and RAG context
- Calendar matching uses Google event ids when available and local EventKit ids otherwise
- Related meetings keep newest-first order when multiple historical meetings match
- Briefing errors render in the sheet instead of crashing the app
- Briefings can open the meeting link or start recording

### Document Management and RAG

- Supported formats: PDF, TXT, Markdown, PNG, JPG
- OCR for scanned PDFs and images via vision language models
- Automatic chunking with configurable size and overlap
- Embedding indexing for documents and meeting transcript segments
- Vector similarity search via sqlite-vec
- Scoped chat queries across all content, meetings only, documents only, or specific records

### Meeting Recording and Playback

- Full session lifecycle across idle, starting, active, paused, stopping, and completed states
- Transcript-synchronized playback
- Speaker diarization overlay during playback
- Export transcripts with speaker labels and timestamps
- Import audio files or transcripts for processing
- Playback suggestions preserve dismissal and feedback state

### Calendar Integration

- Google Calendar OAuth 2.0 with secure Keychain storage
- Incremental Google Calendar sync with sync tokens
- EventKit fallback for local calendars
- Upcoming meeting list with meeting links, proximity indicators, briefing access, and start-recording controls
- Auto-start recording when calendar meetings begin
- Meeting summaries can be written back to calendar event descriptions
- Attendee metadata includes email, display name, response status, and self marker

### Automations

- Voice commands with regex-based pattern detection and cooldowns
- System-level keyboard shortcut triggers per meeting
- Tool-calling pipeline for multi-turn LLM orchestration
- Action tiers for allow, confirm, and review workflows
- Undo stack for meeting-scoped tool execution history
- Built-in tools: remember, take_note, search_knowledge, generate_summary

### Chat

- RAG-powered Q&A across meetings and documents
- Scoped context for a meeting, document, or all content
- Conversation history per meeting or chat
- Streaming responses
- OpenAI-compatible providers can supply text generation, embeddings, and STT
- OpenRouter model catalog support fetches live model and embedding lists when configured

### Model Management

- Dynamic model registry combines curated defaults with MLXLLM, MLXVLM, and MLXEmbedders registries
- Per-task model selection for STT, text generation, OCR, embedding, and TTS
- Download progress tracking with disk space validation
- Browse, download, delete, and switch models from the UI
- Local model readiness checks support Hugging Face cache layouts and app-managed model storage

## Cloud Providers

| Provider | Capabilities |
|----------|--------------|
| Anthropic (Claude) | Text generation, vision/OCR |
| OpenAI-compatible | Text generation, embeddings, STT |
| OpenRouter | Text generation, vision/OCR, embeddings through live catalog discovery |

API keys are stored in macOS Keychain. Each capability can use local models or a configured cloud provider.

## Data Storage

- Database: SQLite via GRDB with migrations
- Vector search: sqlite-vec extension for dense embeddings
- Models: `~/Library/Application Support/Gophy/models/`
- Recordings: `~/Library/Application Support/Gophy/recordings/`
- Logs: `~/Library/Application Support/Gophy/logs/`
- Suggestion state: `chat_messages.dismissed` and `chat_messages.feedback`

## Dependencies

| Package | Purpose |
|---------|---------|
| mlx-swift-lm (vendored) | LLM, VLM, and embedding inference |
| mlx-audio-swift (vendored) | Local TTS/STT audio models |
| WhisperKit | Speech-to-text |
| GRDB.swift | SQLite database |
| GTMAppAuth / AppAuth | Google OAuth |
| MacPaw/OpenAI | OpenAI-compatible API client |
| SwiftAnthropic | Anthropic API client |
| sqlite-vec | Local vector search extension |

## Project Structure

```
.
├── Package.swift
├── build.sh
├── Sources/
│   ├── CSQLiteVec/     # Static sqlite-vec extension
│   └── Gophy/
│       ├── Audio/      # Mic capture, system audio, VAD, mixer, diarization
│       ├── Automations/# Voice commands, keyboard triggers, tool calling
│       ├── Calendar/   # Google Calendar sync, EventKit, writeback
│       ├── Data/       # Database, repositories, vector search, document processor
│       ├── Engines/    # STT, OCR, text generation, embedding, TTS
│       ├── Meeting/    # Session controllers, events, state tracker, suggestions
│       ├── Models/     # Model registry, definitions, download manager
│       ├── Providers/  # Provider abstractions and cloud implementations
│       ├── RAG/        # Retrieval augmented generation pipeline
│       ├── Services/   # Storage, crash reporter, keychain, downloaders
│       └── Views/      # SwiftUI app, meetings, playback, overlay, settings
├── Tests/GophyTests/
└── vendor/
    ├── mlx-swift-lm/
    └── mlx-audio-swift/
```

## Fork

This project is a fork of [gophy-ai/desktop](https://github.com/gophy-ai/desktop).
