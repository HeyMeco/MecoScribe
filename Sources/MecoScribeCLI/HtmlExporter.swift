import Foundation

enum HtmlExporter {
    static func export(
        _ result: ScribeResult,
        audioPath: String,
        htmlPath: String,
        speakerNames: [String: String]
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let utterancesJSON = String(data: try encoder.encode(result.utterances), encoding: .utf8) ?? "[]"
        let speakerIdsJSON = String(data: try encoder.encode(result.speakerIds), encoding: .utf8) ?? "[]"
        let speakerNamesJSON = String(data: try encoder.encode(speakerNames), encoding: .utf8) ?? "{}"

        let audioFileName = URL(fileURLWithPath: audioPath).lastPathComponent
        let htmlDirectory = URL(fileURLWithPath: htmlPath).deletingLastPathComponent().path
        let audioSourcePath = relativePath(from: htmlDirectory, to: URL(fileURLWithPath: audioPath).path)

        let txtBaseName = URL(fileURLWithPath: htmlPath).deletingPathExtension().lastPathComponent + ".txt"
        let timingsBaseName = URL(fileURLWithPath: htmlPath).deletingPathExtension().lastPathComponent + ".mecoscribe.json"

        let html = template
            .replacingOccurrences(of: "{{TITLE}}", with: escapeHTML(audioFileName))
            .replacingOccurrences(of: "{{TXT_BASENAME}}", with: escapeHTML(txtBaseName))
            .replacingOccurrences(of: "{{TIMINGS_BASENAME}}", with: escapeHTML(timingsBaseName))
            .replacingOccurrences(of: "{{AUDIO_SRC}}", with: escapeHTML(audioSourcePath))
            .replacingOccurrences(of: "{{SOURCE_FILE}}", with: escapeHTML(result.audioFile))
            .replacingOccurrences(of: "{{DURATION}}", with: escapeHTML(formatDuration(result.durationSeconds)))
            .replacingOccurrences(of: "{{DURATION_SECONDS}}", with: "\(result.durationSeconds)")
            .replacingOccurrences(of: "{{SPEAKER_COUNT}}", with: "\(result.speakerCount)")
            .replacingOccurrences(of: "{{UTTERANCES_JSON}}", with: utterancesJSON)
            .replacingOccurrences(of: "{{SPEAKER_IDS_JSON}}", with: speakerIdsJSON)
            .replacingOccurrences(of: "{{SPEAKER_NAMES_JSON}}", with: speakerNamesJSON)

        try html.write(toFile: htmlPath, atomically: true, encoding: .utf8)
    }

    private static func relativePath(from directory: String, to target: String) -> String {
        let dirURL = URL(fileURLWithPath: directory).standardizedFileURL
        let targetURL = URL(fileURLWithPath: target).standardizedFileURL
        return targetURL.path.replacingOccurrences(of: dirURL.path + "/", with: "")
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let template = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <meta name="mecoscribe-txt-file" content="{{TXT_BASENAME}}">
      <meta name="mecoscribe-timings-file" content="{{TIMINGS_BASENAME}}">
      <title>{{TITLE}} — MecoScribe</title>
      <style>
        :root {
          color-scheme: light dark;
          --bg: #0f1117;
          --panel: #171a22;
          --text: #e8eaed;
          --muted: #9aa0a6;
          --accent: #6ea8fe;
          --border: #2a2f3a;
        }
        @media (prefers-color-scheme: light) {
          :root {
            --bg: #f6f7fb;
            --panel: #ffffff;
            --text: #1f2937;
            --muted: #6b7280;
            --accent: #2563eb;
            --border: #e5e7eb;
          }
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          font-family: "SF Pro Text", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          background: var(--bg);
          color: var(--text);
          line-height: 1.5;
        }
        .layout {
          max-width: 960px;
          margin: 0 auto;
          padding: 24px 20px 48px;
        }
        header {
          margin-bottom: 24px;
        }
        h1 {
          font-size: 1.5rem;
          margin: 0 0 8px;
        }
        .meta {
          color: var(--muted);
          font-size: 0.9rem;
        }
        .hint {
          color: var(--muted);
          font-size: 0.82rem;
          margin-bottom: 16px;
        }
        .hint kbd {
          display: inline-block;
          padding: 1px 6px;
          border-radius: 4px;
          border: 1px solid var(--border);
          background: var(--panel);
          font-size: 0.78rem;
        }
        .player-panel {
          position: sticky;
          top: 0;
          z-index: 10;
          background: color-mix(in srgb, var(--bg) 92%, transparent);
          backdrop-filter: blur(8px);
          border: 1px solid var(--border);
          border-radius: 14px;
          padding: 16px;
          margin-bottom: 20px;
        }
        audio {
          width: 100%;
          margin-top: 8px;
        }
        .time-display {
          font-variant-numeric: tabular-nums;
          font-size: 0.85rem;
          color: var(--muted);
          margin-top: 6px;
        }
        .speakers-panel {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
          margin-bottom: 20px;
        }
        .speaker-chip {
          display: inline-flex;
          align-items: center;
          gap: 8px;
          padding: 6px 10px;
          border-radius: 999px;
          border: 1px solid var(--border);
          background: var(--panel);
          font-size: 0.85rem;
        }
        .speaker-dot {
          width: 10px;
          height: 10px;
          border-radius: 50%;
          flex-shrink: 0;
        }
        .speaker-chip button {
          border: none;
          background: transparent;
          color: var(--accent);
          cursor: pointer;
          font-size: 0.8rem;
          padding: 0;
        }
        .transcript {
          display: flex;
          flex-direction: column;
          gap: 12px;
        }
        .utterance {
          border: 1px solid var(--border);
          border-left-width: 4px;
          border-radius: 12px;
          background: var(--panel);
          padding: 14px 16px;
          transition: background 0.15s ease, box-shadow 0.15s ease;
        }
        .utterance:hover {
          box-shadow: 0 4px 16px rgba(0, 0, 0, 0.08);
        }
        .utterance.active {
          outline: 2px solid var(--accent);
          outline-offset: 1px;
        }
        .utterance-header {
          display: flex;
          justify-content: space-between;
          gap: 12px;
          margin-bottom: 8px;
          font-size: 0.85rem;
          color: var(--muted);
        }
        .speaker-label {
          font-weight: 600;
        }
        .words {
          font-size: 1.02rem;
          line-height: 1.65;
        }
        .word {
          border-radius: 4px;
          padding: 1px 3px;
          cursor: text;
          border: 1px solid transparent;
        }
        .word:hover {
          border-color: color-mix(in srgb, var(--accent) 35%, transparent);
        }
        .word.active {
          background: color-mix(in srgb, var(--accent) 35%, transparent);
        }
        .word.editing {
          outline: 2px solid var(--accent);
          outline-offset: 1px;
          background: var(--bg);
        }
        .word[draggable="true"] {
          cursor: grab;
        }
        .word[draggable="true"]:active {
          cursor: grabbing;
        }
        .word.dragging {
          opacity: 0.45;
        }
        .word.drop-before {
          box-shadow: -2px 0 0 0 var(--accent);
        }
        .word.drop-after {
          box-shadow: 2px 0 0 0 var(--accent);
        }
        .word-insert-gap {
          display: inline-block;
          width: 10px;
          height: 1.2em;
          vertical-align: text-bottom;
          cursor: pointer;
          border-radius: 2px;
        }
        .word-insert-gap:hover {
          background: color-mix(in srgb, var(--accent) 20%, transparent);
        }
        .word-insert-gap.drop-active {
          box-shadow: inset 0 0 0 2px var(--accent);
        }
        .utterance-boundary-gap {
          height: 12px;
          border-radius: 4px;
        }
        .utterance-boundary-gap.drop-active {
          background: color-mix(in srgb, var(--accent) 20%, transparent);
          box-shadow: inset 0 0 0 2px var(--accent);
        }
        .utterance-editor {
          min-height: 1.5em;
          padding: 8px 10px;
          border-radius: 8px;
          border: 2px solid var(--accent);
          background: var(--bg);
          outline: none;
          cursor: text;
        }
        dialog {
          border: 1px solid var(--border);
          border-radius: 12px;
          padding: 20px;
          background: var(--panel);
          color: var(--text);
          max-width: 420px;
        }
        dialog::backdrop {
          background: rgba(0, 0, 0, 0.45);
        }
        dialog label {
          display: block;
          margin-bottom: 8px;
          font-size: 0.9rem;
        }
        dialog input {
          width: 100%;
          padding: 10px 12px;
          border-radius: 8px;
          border: 1px solid var(--border);
          background: var(--bg);
          color: var(--text);
          margin-bottom: 16px;
        }
        .dialog-actions {
          display: flex;
          justify-content: flex-end;
          gap: 8px;
        }
        .dialog-actions button {
          border-radius: 8px;
          border: 1px solid var(--border);
          background: var(--bg);
          color: var(--text);
          padding: 8px 14px;
          cursor: pointer;
        }
        .dialog-actions button.primary {
          background: var(--accent);
          border-color: var(--accent);
          color: white;
        }
        .toolbar {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 10px;
          margin-bottom: 20px;
          padding: 12px 14px;
          border: 1px solid var(--border);
          border-radius: 12px;
          background: var(--panel);
        }
        .toolbar-actions {
          display: flex;
          flex-wrap: wrap;
          gap: 8px;
        }
        .toolbar button {
          border-radius: 8px;
          border: 1px solid var(--border);
          background: var(--bg);
          color: var(--text);
          padding: 8px 14px;
          cursor: pointer;
          font-size: 0.9rem;
        }
        .toolbar button.primary {
          background: var(--accent);
          border-color: var(--accent);
          color: white;
        }
        .toolbar button:disabled {
          opacity: 0.55;
          cursor: not-allowed;
        }
        .mode-toolbar {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: 12px;
        }
        .player-panel .mode-toolbar {
          margin-top: 14px;
          padding-top: 14px;
          border-top: 1px solid var(--border);
        }
        .mode-toolbar-label {
          font-size: 0.88rem;
          font-weight: 600;
          color: var(--muted);
        }
        .mode-toggle {
          display: inline-flex;
          border: 1px solid var(--border);
          border-radius: 10px;
          overflow: hidden;
          background: var(--bg);
        }
        .mode-toggle button {
          border: none;
          background: transparent;
          color: var(--muted);
          padding: 8px 14px;
          cursor: pointer;
          font-size: 0.88rem;
          font-weight: 500;
          transition: background 0.15s ease, color 0.15s ease;
        }
        .mode-toggle button + button {
          border-left: 1px solid var(--border);
        }
        .mode-toggle button:hover {
          color: var(--text);
          background: color-mix(in srgb, var(--accent) 8%, var(--bg));
        }
        .mode-toggle button.active {
          background: var(--accent);
          color: white;
        }
        .mode-hint {
          flex: 1 1 240px;
          font-size: 0.82rem;
          color: var(--muted);
        }
        .save-status {
          flex: 1 1 220px;
          font-size: 0.85rem;
          color: var(--muted);
        }
        .save-status.dirty {
          color: #fbbf24;
        }
        .save-status.saved {
          color: #34d399;
        }
        .restore-banner {
          margin-bottom: 16px;
          padding: 10px 14px;
          border-radius: 10px;
          border: 1px solid color-mix(in srgb, var(--accent) 45%, var(--border));
          background: color-mix(in srgb, var(--accent) 12%, var(--panel));
          font-size: 0.88rem;
        }
        .restore-banner button {
          margin-left: 10px;
          border-radius: 6px;
          border: 1px solid var(--border);
          background: var(--bg);
          color: var(--text);
          padding: 4px 10px;
          cursor: pointer;
          font-size: 0.82rem;
        }
        .speaker-assign-menu {
          position: fixed;
          z-index: 30;
          display: flex;
          flex-direction: column;
          gap: 8px;
          min-width: 180px;
          max-width: 280px;
          padding: 10px 12px;
          border-radius: 10px;
          border: 1px solid var(--border);
          background: var(--panel);
          box-shadow: 0 10px 30px rgba(0, 0, 0, 0.18);
        }
        .speaker-assign-menu[hidden] {
          display: none;
        }
        .speaker-assign-label {
          font-size: 0.78rem;
          font-weight: 600;
          color: var(--muted);
          text-transform: uppercase;
          letter-spacing: 0.04em;
        }
        .speaker-assign-options {
          display: flex;
          flex-direction: column;
          gap: 4px;
        }
        .speaker-assign-option {
          display: flex;
          align-items: center;
          gap: 8px;
          width: 100%;
          border: 1px solid transparent;
          border-radius: 8px;
          background: transparent;
          color: var(--text);
          padding: 7px 8px;
          cursor: pointer;
          font-size: 0.88rem;
          text-align: left;
        }
        .speaker-assign-option:hover,
        .speaker-assign-option:focus-visible {
          border-color: color-mix(in srgb, var(--accent) 35%, var(--border));
          background: color-mix(in srgb, var(--accent) 10%, var(--panel));
          outline: none;
        }
        .speaker-assign-option.current {
          opacity: 0.55;
          cursor: default;
        }
        .speaker-assign-divider {
          height: 1px;
          margin: 4px 0;
          background: var(--border);
        }
        .speaker-assign-option.add-speaker {
          color: var(--accent);
          font-weight: 500;
        }
        ::selection {
          background: color-mix(in srgb, var(--accent) 35%, transparent);
        }
      </style>
    </head>
    <body>
      <div class="layout">
        <header>
          <h1>{{TITLE}}</h1>
          <div class="meta">
            Source: {{SOURCE_FILE}} · Duration: {{DURATION}} · Speakers: {{SPEAKER_COUNT}}
          </div>
          <p class="hint">
            <kbd>Left-click</kbd> a word to edit ·
            <kbd>Right-click</kbd> to play from here ·
            Click the space before or after a word to add one ·
            Double-click a segment to edit the full line ·
            <kbd>Esc</kbd> cancels edit ·
            <strong>Link folder</strong> once — edits save to disk automatically
            (Chrome/Edge; select the folder containing this HTML and transcript)
          </p>
        </header>

        <div id="linkPromptBanner" class="restore-banner" hidden>
          <span id="linkPromptText">Link the project folder so edits save automatically.</span>
          <button type="button" id="linkSiblingBtn">Link folder</button>
        </div>

        <div id="fileConflictBanner" class="restore-banner" hidden></div>

        <section class="toolbar">
          <div class="toolbar-actions">
            <button type="button" id="linkFileBtn">Link folder</button>
            <button type="button" id="unlinkFileBtn" hidden>Unlink folder</button>
            <button type="button" id="saveBtn" class="primary">Sync now</button>
            <button type="button" id="downloadBtn">Download .txt</button>
            <button type="button" id="discardBtn">Discard edits</button>
          </div>
          <div class="save-status" id="saveStatus">Link the project folder — edits save automatically once linked</div>
        </section>

        <section class="player-panel">
          <strong>Audio playback</strong>
          <audio id="audio" controls preload="metadata" src="{{AUDIO_SRC}}"></audio>
          <div class="time-display" id="timeDisplay">00:00 / {{DURATION}}</div>
          <div class="mode-toolbar">
            <span class="mode-toolbar-label">Edit mode</span>
            <div class="mode-toggle" role="group" aria-label="Edit mode">
              <button type="button" class="mode-btn active" data-mode="assign" id="modeAssignBtn">Assign speaker</button>
              <button type="button" class="mode-btn" data-mode="drag" id="modeDragBtn">Move words</button>
            </div>
            <span class="mode-hint" id="modeHint">Select text to reassign speaker.</span>
          </div>
        </section>

        <section class="speakers-panel" id="speakersPanel"></section>
        <section class="transcript" id="transcript"></section>
      </div>

      <div id="speakerAssignMenu" class="speaker-assign-menu" hidden>
        <span class="speaker-assign-label">Assign to speaker</span>
        <div class="speaker-assign-options" id="speakerAssignOptions"></div>
      </div>

      <dialog id="renameDialog">
        <form method="dialog" id="renameForm">
          <h3>Rename speaker</h3>
          <label for="speakerNameInput">Display name</label>
          <input id="speakerNameInput" type="text" required autocomplete="off">
          <div class="dialog-actions">
            <button type="button" id="cancelRename">Cancel</button>
            <button type="submit" class="primary">Save</button>
          </div>
        </form>
      </dialog>

      <script>
        let utterances = {{UTTERANCES_JSON}};
        let originalUtterances = JSON.parse(JSON.stringify(utterances));
        let speakerIds = {{SPEAKER_IDS_JSON}};
        const sourceFile = "{{SOURCE_FILE}}";
        const downloadBaseName = "{{TITLE}}";
        const transcriptFileName = "{{TXT_BASENAME}}";
        const timingsFileName = "{{TIMINGS_BASENAME}}";
        const durationLabel = "{{DURATION}}";
        const durationSeconds = {{DURATION_SECONDS}};
        const speakerCount = {{SPEAKER_COUNT}};
        const fileHandleKey = "transcript-handle-" + encodeURIComponent(sourceFile);
        const ROOT_DIR_HANDLE_KEY = fileHandleKey + "-root";
        let speakerNames = Object.assign({}, {{SPEAKER_NAMES_JSON}});
        let renamingSpeakerId = null;
        let addingNewSpeaker = false;
        let assignRefsAfterNewSpeaker = null;
        let activeEditor = null;
        let isDirty = false;
        let lastSavedAt = null;
        let filePollTimer = null;
        let rootDirHandle = null;
        let linkedFolderName = null;
        let pendingRootDirHandle = null;
        let lastWrittenContent = null;
        let lastSeenFileModified = null;
        let suppressNextFilePoll = false;
        let writeDebounceTimer = null;
        let isWriting = false;
        let lastWriteAt = 0;
        const WRITE_DEBOUNCE_MS = 400;
        const POLL_GRACE_MS = 8000;

        const palette = [
          "#6ea8fe", "#f472b6", "#34d399", "#fbbf24", "#a78bfa",
          "#fb7185", "#22d3ee", "#84cc16", "#f97316", "#818cf8"
        ];

        const audio = document.getElementById("audio");
        const transcriptEl = document.getElementById("transcript");
        const speakersPanel = document.getElementById("speakersPanel");
        const timeDisplay = document.getElementById("timeDisplay");
        const renameDialog = document.getElementById("renameDialog");
        const speakerNameInput = document.getElementById("speakerNameInput");
        const renameForm = document.getElementById("renameForm");
        const cancelRename = document.getElementById("cancelRename");
        const saveBtn = document.getElementById("saveBtn");
        const downloadBtn = document.getElementById("downloadBtn");
        const discardBtn = document.getElementById("discardBtn");
        const linkFileBtn = document.getElementById("linkFileBtn");
        const unlinkFileBtn = document.getElementById("unlinkFileBtn");
        const saveStatus = document.getElementById("saveStatus");
        const fileConflictBanner = document.getElementById("fileConflictBanner");
        const linkPromptBanner = document.getElementById("linkPromptBanner");
        const linkPromptText = document.getElementById("linkPromptText");
        const linkSiblingBtn = document.getElementById("linkSiblingBtn");
        const speakerAssignMenu = document.getElementById("speakerAssignMenu");
        const speakerAssignOptions = document.getElementById("speakerAssignOptions");
        let pendingSpeakerAssignRefs = [];
        let canonicalWordBank = null;
        let wordDragState = null;
        let suppressNextWordClick = false;
        let editMode = "assign";
        const UTTERANCE_GAP_SECONDS = 1.5;
        const MODE_HINTS = {
          assign: "Select text to reassign speaker.",
          drag: "Drag words to move them — timings stay attached.",
        };

        const modeAssignBtn = document.getElementById("modeAssignBtn");
        const modeDragBtn = document.getElementById("modeDragBtn");
        const modeHint = document.getElementById("modeHint");

        function defaultSpeakerName(id) {
          const match = id.match(/speaker_(\\d+)/);
          if (match) return `Speaker ${parseInt(match[1], 10) + 1}`;
          return id;
        }

        function nextSpeakerId() {
          let maxIndex = -1;
          speakerIds.forEach((id) => {
            const match = id.match(/speaker_(\\d+)/);
            if (match) maxIndex = Math.max(maxIndex, parseInt(match[1], 10));
          });
          return `speaker_${maxIndex + 1}`;
        }

        function nextDefaultSpeakerName() {
          return defaultSpeakerName(nextSpeakerId());
        }

        function speakerName(id) {
          return speakerNames[id] || defaultSpeakerName(id);
        }

        function speakerColor(id) {
          const index = Math.max(0, speakerIds.indexOf(id));
          return palette[index % palette.length];
        }

        function formatTime(seconds) {
          const total = Math.floor(seconds);
          const h = Math.floor(total / 3600);
          const m = Math.floor((total % 3600) / 60);
          const s = total % 60;
          if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
          return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
        }

        function wordTooltip(startTime, dragMode = false) {
          const actions = dragMode
            ? "Left-click to edit · Right-click to play · Drag to move"
            : "Left-click to edit · Right-click to play · Select to reassign speaker";
          return `${formatTime(startTime)} · ${actions}`;
        }

        function updateSaveStatus() {
          if (rootDirHandle && linkedFolderName) {
            if (isWriting) {
              saveStatus.textContent = `Linked to ${linkedFolderName} · saving…`;
              saveStatus.className = "save-status dirty";
            } else if (writeDebounceTimer) {
              saveStatus.textContent = `Linked to ${linkedFolderName} · saving soon…`;
              saveStatus.className = "save-status dirty";
            } else if (isDirty) {
              saveStatus.textContent = `Linked to ${linkedFolderName} · unsaved changes`;
              saveStatus.className = "save-status dirty";
            } else if (lastSavedAt) {
              saveStatus.textContent = `Linked to ${linkedFolderName} · saved ${formatSavedTime(lastSavedAt)}`;
              saveStatus.className = "save-status saved";
            } else {
              saveStatus.textContent = `Linked to ${linkedFolderName} · live editing`;
              saveStatus.className = "save-status saved";
            }
          } else if (isDirty) {
            saveStatus.textContent = "Unsaved changes · link the project folder to save to disk";
            saveStatus.className = "save-status dirty";
          } else {
            saveStatus.textContent = "Link the project folder — edits save automatically once linked";
            saveStatus.className = "save-status";
          }
          saveBtn.disabled = !rootDirHandle || isWriting;
          unlinkFileBtn.hidden = !rootDirHandle;
        }

        function updateLinkPromptVisibility() {
          if (!rootDirHandle) {
            showLinkPrompt(!!pendingRootDirHandle);
          } else {
            hideLinkPrompt();
          }
        }

        function markDirty() {
          isDirty = true;
          updateSaveStatus();
        }

        function scheduleWriteToLinkedFile() {
          if (!rootDirHandle) return;
          if (writeDebounceTimer) clearTimeout(writeDebounceTimer);
          writeDebounceTimer = setTimeout(async () => {
            writeDebounceTimer = null;
            if (activeEditor) {
              scheduleWriteToLinkedFile();
              return;
            }
            await writeLinkedFile(true);
          }, WRITE_DEBOUNCE_MS);
          updateSaveStatus();
        }

        function formatSavedTime(isoString) {
          try {
            return new Date(isoString).toLocaleString();
          } catch (_) {
            return isoString;
          }
        }

        function supportsFileSystemAccess() {
          return typeof window.showDirectoryPicker === "function";
        }

        function isFileProtocol() {
          return window.location.protocol === "file:";
        }

        function showLinkPrompt(reconnect = false) {
          linkPromptBanner.hidden = false;
          if (reconnect) {
            linkPromptText.textContent =
              `Click Link folder to reconnect (browser permission required).`;
          } else if (isFileProtocol()) {
            linkPromptText.innerHTML =
              `Opened from disk — click <strong>Link folder</strong> and select the folder containing <strong>${transcriptFileName}</strong>.`;
          } else {
            linkPromptText.innerHTML =
              `Link the project folder containing <strong>${transcriptFileName}</strong> to enable auto-save.`;
          }
        }

        function hideLinkPrompt() {
          linkPromptBanner.hidden = true;
        }

        function openHandleDb() {
          return new Promise((resolve, reject) => {
            const request = indexedDB.open("mecoscribe", 1);
            request.onupgradeneeded = () => {
              if (!request.result.objectStoreNames.contains("file-handles")) {
                request.result.createObjectStore("file-handles");
              }
            };
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
          });
        }

        async function readHandleFromDb(key) {
          const db = await openHandleDb();
          return new Promise((resolve, reject) => {
            const tx = db.transaction("file-handles", "readonly");
            const request = tx.objectStore("file-handles").get(key);
            request.onsuccess = () => resolve(request.result || null);
            request.onerror = () => reject(request.error);
          });
        }

        async function writeHandleToDb(key, handle) {
          const db = await openHandleDb();
          await new Promise((resolve, reject) => {
            const tx = db.transaction("file-handles", "readwrite");
            tx.objectStore("file-handles").put(handle, key);
            tx.oncomplete = () => resolve();
            tx.onerror = () => reject(tx.error);
          });
        }

        async function deleteHandleFromDb(key) {
          const db = await openHandleDb();
          await new Promise((resolve, reject) => {
            const tx = db.transaction("file-handles", "readwrite");
            tx.objectStore("file-handles").delete(key);
            tx.oncomplete = () => resolve();
            tx.onerror = () => reject(tx.error);
          });
        }

        async function storeRootDirHandle(handle) {
          await writeHandleToDb(ROOT_DIR_HANDLE_KEY, handle);
          await deleteHandleFromDb(fileHandleKey);
          await deleteHandleFromDb(fileHandleKey + "-timings");
        }

        async function clearStoredRootDirHandle() {
          await deleteHandleFromDb(ROOT_DIR_HANDLE_KEY);
          await deleteHandleFromDb(fileHandleKey);
          await deleteHandleFromDb(fileHandleKey + "-timings");
        }

        async function validateProjectFolder(handle) {
          await handle.getFileHandle(transcriptFileName);
        }

        async function getRootDirHandle({ forceReload = false, showPicker = true } = {}) {
          if (!supportsFileSystemAccess()) {
            throw new Error("unsupported");
          }

          let handle = forceReload ? null : await readHandleFromDb(ROOT_DIR_HANDLE_KEY);

          if (handle) {
            if ((await handle.requestPermission({ mode: "readwrite" })) !== "granted") {
              handle = null;
            } else {
              try {
                await handle.entries().next();
              } catch (_) {
                handle = null;
              }
            }
          }

          if (!handle && showPicker) {
            handle = await window.showDirectoryPicker();
            await validateProjectFolder(handle);
            await storeRootDirHandle(handle);
          }

          return handle;
        }

        async function getFileHandleByPath(relativePath, create = false) {
          const parts = relativePath.split("/").filter(Boolean);
          let dir = rootDirHandle;
          for (let index = 0; index < parts.length - 1; index++) {
            dir = await dir.getDirectoryHandle(parts[index]);
          }
          return dir.getFileHandle(parts[parts.length - 1], { create });
        }

        async function readFileAtPath(relativePath) {
          if (!rootDirHandle) return null;
          try {
            const fileHandle = await getFileHandleByPath(relativePath, false);
            const file = await fileHandle.getFile();
            return { text: await file.text(), lastModified: file.lastModified };
          } catch (_) {
            return null;
          }
        }

        async function writeFileAtPath(relativePath, content) {
          const fileHandle = await getFileHandleByPath(relativePath, true);
          const writable = await fileHandle.createWritable();
          await writable.write(content);
          await writable.close();
          const file = await fileHandle.getFile();
          return file.lastModified;
        }

        async function readLinkedFile() {
          return readFileAtPath(transcriptFileName);
        }

        async function readLinkedTimingsFile() {
          const payload = await readFileAtPath(timingsFileName);
          if (!payload) return null;
          try {
            return JSON.parse(payload.text);
          } catch (_) {
            return null;
          }
        }

        async function writeLinkedTimingsFile() {
          if (!rootDirHandle) return false;
          try {
            await writeFileAtPath(timingsFileName, buildTimingsSidecar());
            return true;
          } catch (_) {
            return false;
          }
        }

        function flattenWordBank(source = utterances) {
          if (Array.isArray(source) && source.length && source[0]?.startTime != null && source[0]?.word != null) {
            return source.slice().sort((a, b) => a.startTime - b.startTime);
          }
          return source
            .flatMap((utterance) => utterance.words.map((word) => ({ ...word })))
            .sort((a, b) => a.startTime - b.startTime);
        }

        function syncWordBankFromUtterances() {
          canonicalWordBank = flattenWordBank(utterances);
        }

        function buildTimingsSidecar() {
          syncWordBankFromUtterances();
          return JSON.stringify({
            version: 1,
            audioFile: sourceFile,
            durationSeconds,
            speakerCount: speakerIds.length,
            speakerIds,
            speakerNames,
            utterances,
            words: canonicalWordBank,
          }, null, 2);
        }

        function applyTimingsSidecar(payload) {
          if (!payload?.utterances?.length) return false;
          utterances = payload.utterances;
          if (payload.speakerIds?.length) {
            speakerIds.splice(0, speakerIds.length, ...payload.speakerIds);
          }
          if (payload.speakerNames) {
            speakerNames = Object.assign({}, payload.speakerNames);
          }
          canonicalWordBank = payload.words?.length
            ? flattenWordBank(payload.words)
            : flattenWordBank(utterances);
          originalUtterances = JSON.parse(JSON.stringify(utterances));
          return true;
        }

        async function writeLinkedFile(markSaved = true) {
          if (!rootDirHandle || activeEditor) return false;
          if (writeDebounceTimer) {
            clearTimeout(writeDebounceTimer);
            writeDebounceTimer = null;
          }
          isWriting = true;
          updateSaveStatus();
          try {
            const content = buildTranscriptText();
            lastSeenFileModified = await writeFileAtPath(transcriptFileName, content);
            lastWrittenContent = content;
            suppressNextFilePoll = true;
            lastWriteAt = Date.now();
            if (markSaved) {
              isDirty = false;
              lastSavedAt = new Date().toISOString();
            }
            await writeLinkedTimingsFile();
            return true;
          } catch (error) {
            saveStatus.textContent = `Could not write ${transcriptFileName}: ${error.message}`;
            saveStatus.className = "save-status dirty";
            return false;
          } finally {
            isWriting = false;
            updateSaveStatus();
          }
        }

        function parseTimestamp(value) {
          const parts = value.split(":").map((part) => parseInt(part, 10));
          if (parts.length === 2) return parts[0] * 60 + parts[1];
          if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
          return null;
        }

        function parseHeaderLine(line) {
          const match = line.match(/^\\[((?:\\d+:)?\\d{2}:\\d{2})\\]\\s*(.+):\\s*$/);
          if (!match) return null;
          const startTime = parseTimestamp(match[1]);
          if (startTime == null) return null;
          return { startTime, speakerLabel: match[2] };
        }

        function speakerIdForLabel(label) {
          for (const [id, name] of Object.entries(speakerNames)) {
            if (name === label) return id;
          }
          for (const id of speakerIds) {
            if (defaultSpeakerName(id) === label) return id;
          }
          return speakerIds[0] || "speaker_0";
        }

        function rememberSpeakerLabel(speakerId, label) {
          const trimmed = label.trim();
          if (!trimmed) return;
          if (defaultSpeakerName(speakerId) !== trimmed) {
            speakerNames[speakerId] = trimmed;
          }
        }

        function normalizeTranscriptText(text) {
          return text.replace(/\\r\\n/g, "\\n").trimEnd();
        }

        function transcriptsEquivalent(a, b) {
          return normalizeTranscriptText(a) === normalizeTranscriptText(b);
        }

        function syncBaselineFromDisplay() {
          lastWrittenContent = buildTranscriptText();
          originalUtterances = JSON.parse(JSON.stringify(utterances));
          isDirty = false;
          lastSavedAt = null;
          fileConflictBanner.hidden = true;
        }

        function normalizeWordToken(value) {
          return value.toLowerCase().replace(/[^\\w']/g, "");
        }

        function timingForInsertedWord(prevWord, nextTemplate, startTime, endTime) {
          const gapStart = prevWord ? prevWord.endTime : (nextTemplate?.startTime ?? startTime);
          const gapEnd = nextTemplate ? nextTemplate.startTime : (prevWord?.endTime ?? endTime);
          const duration = Math.max(gapEnd - gapStart, 0.01);
          const midpoint = gapStart + duration / 2;
          const half = Math.min(duration / 2, 0.15);
          return {
            startTime: Math.max(gapStart, midpoint - half),
            endTime: Math.min(gapEnd, midpoint + half),
          };
        }

        function reconcileWordsFromText(text, speakerId, templateWords, startTime, endTime) {
          const tokens = text.split(/\\s+/).filter(Boolean);
          if (!tokens.length) return { words: [], templateConsumed: 0 };

          if (!templateWords?.length) {
            const duration = Math.max(endTime - startTime, 0.01);
            const step = duration / tokens.length;
            return {
              words: tokens.map((token, index) => ({
                word: token,
                startTime: startTime + step * index,
                endTime: index === tokens.length - 1 ? endTime : startTime + step * (index + 1),
                confidence: 1,
                speakerId,
              })),
              templateConsumed: 0,
            };
          }

          if (tokens.length === templateWords.length) {
            return {
              words: tokens.map((token, index) => ({
                word: token,
                startTime: templateWords[index].startTime,
                endTime: templateWords[index].endTime,
                confidence: templateWords[index].confidence,
                speakerId,
              })),
              templateConsumed: templateWords.length,
            };
          }

          const aligned = [];
          let templateIndex = 0;

          for (let tokenIndex = 0; tokenIndex < tokens.length; tokenIndex++) {
            const token = tokens[tokenIndex];
            let matchedIndex = -1;

            for (let index = templateIndex; index < templateWords.length; index++) {
              if (normalizeWordToken(token) === normalizeWordToken(templateWords[index].word)) {
                matchedIndex = index;
                break;
              }
            }

            if (matchedIndex >= 0) {
              const template = templateWords[matchedIndex];
              aligned.push({
                word: token,
                startTime: template.startTime,
                endTime: template.endTime,
                confidence: template.confidence,
                speakerId,
              });
              templateIndex = matchedIndex + 1;
              continue;
            }

            const nextToken = tokens[tokenIndex + 1];
            const nextTemplate = templateWords[templateIndex];
            const nextTokenMatchesCurrentTemplate =
              nextToken &&
              nextTemplate &&
              normalizeWordToken(nextToken) === normalizeWordToken(nextTemplate.word);

            if (!nextTokenMatchesCurrentTemplate && nextTemplate) {
              aligned.push({
                word: token,
                startTime: nextTemplate.startTime,
                endTime: nextTemplate.endTime,
                confidence: nextTemplate.confidence,
                speakerId,
              });
              templateIndex += 1;
              continue;
            }

            const timing = timingForInsertedWord(aligned[aligned.length - 1], nextTemplate, startTime, endTime);
            aligned.push({
              word: token,
              startTime: timing.startTime,
              endTime: timing.endTime,
              confidence: nextTemplate?.confidence ?? aligned[aligned.length - 1]?.confidence ?? 1,
              speakerId,
            });
          }

          return { words: aligned, templateConsumed: templateIndex };
        }

        function buildWordsFromText(text, speakerId, startTime, endTime, templateWords) {
          return reconcileWordsFromText(text, speakerId, templateWords, startTime, endTime).words;
        }

        function parseTranscriptText(text) {
          const lines = text.split(/\\r?\\n/);
          let index = 0;
          while (index < lines.length) {
            if ((lines[index].match(/-/g) || []).length >= 20) {
              index += 1;
              break;
            }
            index += 1;
          }

          const segments = [];
          while (index < lines.length) {
            while (index < lines.length && !lines[index].trim()) index += 1;
            if (index >= lines.length) break;

            const header = parseHeaderLine(lines[index]);
            if (!header) {
              index += 1;
              continue;
            }
            index += 1;

            const bodyLines = [];
            while (index < lines.length) {
              const line = lines[index];
              if (!line.trim()) break;
              if (parseHeaderLine(line)) break;
              bodyLines.push(line);
              index += 1;
            }

            const body = bodyLines.join(" ").trim();
            if (body) segments.push({ ...header, text: body });
          }
          return segments;
        }

        function applyParsedTranscript(text, wordBank = null) {
          if (activeEditor) return false;
          if (transcriptsEquivalent(text, buildTranscriptText())) {
            syncWordBankFromUtterances();
            return true;
          }

          const segments = parseTranscriptText(text);
          if (!segments.length) return false;

          const bank = wordBank || canonicalWordBank || flattenWordBank(utterances);
          let bankCursor = 0;

          utterances = segments.map((segment, index) => {
            const speakerId = speakerIdForLabel(segment.speakerLabel);
            rememberSpeakerLabel(speakerId, segment.speakerLabel);
            const templateSlice = bank.slice(bankCursor);
            const fallbackStart = segment.startTime;
            const fallbackEnd =
              index + 1 < segments.length
                ? segments[index + 1].startTime
                : templateSlice[templateSlice.length - 1]?.endTime ?? Math.max(fallbackStart + 1, durationSeconds);
            const startTime = templateSlice[0]?.startTime ?? fallbackStart;
            const endTime = templateSlice[templateSlice.length - 1]?.endTime ?? fallbackEnd;
            const reconciled = reconcileWordsFromText(
              segment.text,
              speakerId,
              templateSlice,
              startTime,
              endTime
            );
            bankCursor += reconciled.templateConsumed;

            return {
              speakerId,
              startTime: reconciled.words[0]?.startTime ?? startTime,
              endTime: reconciled.words[reconciled.words.length - 1]?.endTime ?? endTime,
              text: segment.text,
              words: reconciled.words,
            };
          });

          syncWordBankFromUtterances();
          renderSpeakers();
          renderTranscript();
          return true;
        }

        function buildTranscriptText() {
          const lines = [
            "MecoScribe Transcript",
            `Source: ${sourceFile}`,
            `Duration: ${durationLabel}`,
            `Speakers: ${speakerIds.length}`,
            "------------------------------------------------------------",
            "",
          ];
          utterances.forEach((utterance) => {
            lines.push(`[${formatTime(utterance.startTime)}] ${speakerName(utterance.speakerId)}:`);
            lines.push(utterance.text);
            lines.push("");
          });
          return lines.join("\\n");
        }

        function showFileConflictBanner(text) {
          fileConflictBanner.hidden = false;
          fileConflictBanner.innerHTML =
            "The linked .txt file changed in another app. " +
            `<button type="button" id="reloadFromFileBtn">Reload from file</button>` +
            `<button type="button" id="keepLocalEditsBtn">Keep my edits</button>`;
          document.getElementById("reloadFromFileBtn")?.addEventListener("click", async () => {
            const timingsPayload = await readLinkedTimingsFile();
            const wordBank = timingsPayload?.words?.length
              ? flattenWordBank(timingsPayload.words)
              : (timingsPayload ? flattenWordBank(timingsPayload.utterances) : canonicalWordBank);
            if (timingsPayload) {
              applyTimingsSidecar(timingsPayload);
            }
            applyParsedTranscript(text, wordBank);
            syncBaselineFromDisplay();
            updateSaveStatus();
          });
          document.getElementById("keepLocalEditsBtn")?.addEventListener("click", () => {
            lastWrittenContent = buildTranscriptText();
            fileConflictBanner.hidden = true;
          });
        }

        async function pollLinkedFile() {
          if (!rootDirHandle || activeEditor || isWriting || writeDebounceTimer) return;
          if (isDirty || Date.now() - lastWriteAt < POLL_GRACE_MS) return;
          if (suppressNextFilePoll) {
            suppressNextFilePoll = false;
            return;
          }
          try {
            const payload = await readLinkedFile();
            if (!payload) return;
            if (lastSeenFileModified != null && payload.lastModified === lastSeenFileModified) return;

            const localCanonical = buildTranscriptText();
            if (transcriptsEquivalent(payload.text, lastWrittenContent)) {
              lastSeenFileModified = payload.lastModified;
              return;
            }
            if (transcriptsEquivalent(payload.text, localCanonical)) {
              lastWrittenContent = payload.text;
              lastSeenFileModified = payload.lastModified;
              return;
            }

            lastSeenFileModified = payload.lastModified;
            showFileConflictBanner(payload.text);
          } catch (_) {}
        }

        async function activateLocalFolder(handle, loadFromFile = true) {
          rootDirHandle = handle;
          linkedFolderName = handle.name;
          pendingRootDirHandle = null;
          await storeRootDirHandle(handle);
          linkFileBtn.textContent = "Linked: " + handle.name;

          try {
            const payload = await readLinkedFile();
            if (payload) {
              if (loadFromFile) {
                const timingsPayload = await readLinkedTimingsFile();
                let loadedTimings = false;
                if (timingsPayload) {
                  loadedTimings = applyTimingsSidecar(timingsPayload);
                }
                if (!loadedTimings || !transcriptsEquivalent(payload.text, buildTranscriptText())) {
                  applyParsedTranscript(payload.text, canonicalWordBank);
                }
              }
              syncBaselineFromDisplay();
              lastSeenFileModified = payload.lastModified;
              if (!transcriptsEquivalent(payload.text, lastWrittenContent)) {
                await writeLinkedFile(true);
              }
            }
          } catch (_) {}

          if (filePollTimer) clearInterval(filePollTimer);
          filePollTimer = setInterval(pollLinkedFile, 2000);
          hideLinkPrompt();
          updateSaveStatus();
          updateLinkPromptVisibility();
        }

        async function linkLocalFolder() {
          if (!supportsFileSystemAccess()) {
            alert("Live sync needs Chrome or Edge (File System Access API). Use Download .txt otherwise.");
            return;
          }
          try {
            if (pendingRootDirHandle) {
              if ((await pendingRootDirHandle.requestPermission({ mode: "readwrite" })) === "granted") {
                await activateLocalFolder(pendingRootDirHandle, true);
              } else {
                saveStatus.textContent = "Click Link folder to grant access";
                saveStatus.className = "save-status dirty";
                showLinkPrompt(true);
              }
              return;
            }
            const handle = await getRootDirHandle({ showPicker: true });
            if (handle) {
              await activateLocalFolder(handle, true);
            }
          } catch (error) {
            if (error?.name === "NotFoundError") {
              saveStatus.textContent = `Selected folder must contain ${transcriptFileName}`;
              saveStatus.className = "save-status dirty";
            } else if (error?.name !== "AbortError") {
              saveStatus.textContent = `Could not link folder: ${error.message}`;
              saveStatus.className = "save-status dirty";
            }
          }
        }

        async function unlinkLocalFolder() {
          rootDirHandle = null;
          linkedFolderName = null;
          pendingRootDirHandle = null;
          lastWrittenContent = null;
          lastSeenFileModified = null;
          if (filePollTimer) clearInterval(filePollTimer);
          filePollTimer = null;
          await clearStoredRootDirHandle();
          linkFileBtn.textContent = "Link folder";
          fileConflictBanner.hidden = true;
          updateSaveStatus();
          updateLinkPromptVisibility();
        }

        async function restoreLinkedFileOnLoad() {
          if (!supportsFileSystemAccess()) {
            showLinkPrompt(false);
            updateLinkPromptVisibility();
            return;
          }
          try {
            const handle = await getRootDirHandle({ showPicker: false });
            if (handle) {
              await activateLocalFolder(handle, true);
              return;
            }
            const stored = await readHandleFromDb(ROOT_DIR_HANDLE_KEY);
            if (stored) {
              pendingRootDirHandle = stored;
              showLinkPrompt(true);
              saveStatus.textContent = "Click Link folder to reconnect";
              saveStatus.className = "save-status";
            } else {
              showLinkPrompt(false);
            }
            updateLinkPromptVisibility();
          } catch (_) {
            showLinkPrompt(false);
            updateLinkPromptVisibility();
          }
        }

        function downloadTranscript() {
          closeActiveEditor(true);
          const blob = new Blob([buildTranscriptText()], { type: "text/plain;charset=utf-8" });
          const link = document.createElement("a");
          link.href = URL.createObjectURL(blob);
          link.download = transcriptFileName;
          link.click();
          URL.revokeObjectURL(link.href);
        }

        async function saveTranscriptExplicit() {
          if (!rootDirHandle) {
            saveStatus.textContent = "Link the project folder first";
            saveStatus.className = "save-status dirty";
            return;
          }
          closeActiveEditor(true);
          const saved = await writeLinkedFile(true);
          if (saved) {
            fileConflictBanner.hidden = true;
          }
        }

        function discardEdits() {
          if (!confirm("Discard all edits and restore the original transcript?")) return;
          closeActiveEditor(false);
          utterances = JSON.parse(JSON.stringify(originalUtterances));
          speakerNames = Object.assign({}, {{SPEAKER_NAMES_JSON}});
          syncBaselineFromDisplay();
          renderSpeakers();
          renderTranscript();
          updateSaveStatus();
        }

        saveBtn.addEventListener("click", () => { saveTranscriptExplicit(); });
        downloadBtn.addEventListener("click", downloadTranscript);
        discardBtn.addEventListener("click", discardEdits);
        linkFileBtn.addEventListener("click", () => { linkLocalFolder(); });
        linkSiblingBtn.addEventListener("click", () => { linkLocalFolder(); });
        unlinkFileBtn.addEventListener("click", () => { unlinkLocalFolder(); });

        function rebuildUtteranceText(index) {
          const utterance = utterances[index];
          utterance.text = utterance.words.map((word) => word.word).join(" ");
        }

        function playFrom(seconds) {
          audio.currentTime = seconds;
          audio.play();
        }

        function hideSpeakerAssignMenu() {
          speakerAssignMenu.hidden = true;
          pendingSpeakerAssignRefs = [];
        }

        function isDragMode() {
          return editMode === "drag";
        }

        function isAssignMode() {
          return editMode === "assign";
        }

        function updateEditModeUI() {
          modeAssignBtn.classList.toggle("active", isAssignMode());
          modeDragBtn.classList.toggle("active", isDragMode());
          modeHint.textContent = MODE_HINTS[editMode] || "";
          document.body.dataset.editMode = editMode;
        }

        function mergeAdjacentSameSpeakerUtterances() {
          const allWords = flattenUtterancesToWordsInOrder().map((item) => ({ ...item.word }));
          if (!allWords.length) return false;
          const merged = regroupUtterancesFromWords(allWords, { respectTimeGaps: false });
          if (merged.length === utterances.length) return false;
          utterances = merged;
          syncWordBankFromUtterances();
          return true;
        }

        function finalizeDragModeUtterances(options = {}) {
          if (!isDragMode() || !mergeAdjacentSameSpeakerUtterances()) return false;
          markDirty();
          scheduleWriteToLinkedFile();
          renderTranscript(options);
          return true;
        }

        function setEditMode(mode) {
          if (mode !== "assign" && mode !== "drag") return;
          if (editMode === mode) return;
          editMode = mode;
          hideSpeakerAssignMenu();
          clearWordDropIndicators();
          wordDragState = null;
          window.getSelection()?.removeAllRanges();
          updateEditModeUI();
          if (isDragMode() && mergeAdjacentSameSpeakerUtterances()) {
            markDirty();
            scheduleWriteToLinkedFile();
          }
          renderTranscript();
        }

        function makeUtteranceFromWords(speakerId, words) {
          return {
            speakerId,
            startTime: words[0].startTime,
            endTime: words[words.length - 1].endTime,
            text: words.map((word) => word.word).join(" "),
            words,
          };
        }

        function regroupUtterancesFromWords(allWords, options = {}) {
          if (!allWords.length) return [];
          const respectTimeGaps = options.respectTimeGaps !== false;
          const grouped = [];
          let currentSpeaker = allWords[0].speakerId;
          let currentWords = [allWords[0]];

          for (let index = 1; index < allWords.length; index++) {
            const word = allWords[index];
            const gap = word.startTime - currentWords[currentWords.length - 1].endTime;
            if (
              word.speakerId !== currentSpeaker ||
              (respectTimeGaps && gap > UTTERANCE_GAP_SECONDS)
            ) {
              grouped.push(makeUtteranceFromWords(currentSpeaker, currentWords));
              currentSpeaker = word.speakerId;
              currentWords = [word];
            } else {
              currentWords.push(word);
            }
          }

          grouped.push(makeUtteranceFromWords(currentSpeaker, currentWords));
          return grouped;
        }

        function flattenUtterancesToWordsInOrder() {
          const items = [];
          utterances.forEach((utterance, utteranceIndex) => {
            utterance.words.forEach((word, wordIndex) => {
              items.push({
                utteranceIndex,
                wordIndex,
                word: {
                  ...word,
                  speakerId: word.speakerId ?? utterance.speakerId,
                },
              });
            });
          });
          return items;
        }

        function flatIndexForWordRef(utteranceIndex, wordIndex) {
          let index = 0;
          for (let u = 0; u < utteranceIndex; u++) {
            index += utterances[u].words.length;
          }
          return index + wordIndex;
        }

        function moveWordRefsToFlatIndex(refs, targetFlatIndex, targetSpeakerId) {
          if (!refs.length) return false;

          const items = flattenUtterancesToWordsInOrder();
          const sourceIndices = refs
            .map((ref) => flatIndexForWordRef(ref.utteranceIndex, ref.wordIndex))
            .filter((index, position, all) => all.indexOf(index) === position)
            .sort((a, b) => a - b);

          if (!sourceIndices.length) return false;

          const minSource = sourceIndices[0];
          const maxSource = sourceIndices[sourceIndices.length - 1];
          const movingSpeakerIds = new Set(
            sourceIndices.map((index) => items[index].word.speakerId)
          );
          const changesSpeaker =
            movingSpeakerIds.size !== 1 || !movingSpeakerIds.has(targetSpeakerId);
          if (
            !changesSpeaker &&
            targetFlatIndex >= minSource &&
            targetFlatIndex <= maxSource + 1
          ) {
            return false;
          }

          let adjustedTarget = targetFlatIndex;
          for (const sourceIndex of sourceIndices) {
            if (sourceIndex < targetFlatIndex) adjustedTarget--;
          }

          const movingSet = new Set(sourceIndices);
          const movingWords = sourceIndices.map((index) => ({ ...items[index].word }));
          const remaining = items
            .filter((_, index) => !movingSet.has(index))
            .map((item) => ({ ...item.word }));

          remaining.splice(
            adjustedTarget,
            0,
            ...movingWords.map((word) => ({
              ...word,
              speakerId: targetSpeakerId,
            }))
          );

          utterances = regroupUtterancesFromWords(remaining, { respectTimeGaps: false });
          syncWordBankFromUtterances();
          return true;
        }

        function refsForWordDrag(utteranceIndex, wordIndex) {
          const selected = getSelectedWordRefs();
          const key = `${utteranceIndex}:${wordIndex}`;
          if (selected.some((ref) => `${ref.utteranceIndex}:${ref.wordIndex}` === key)) {
            return selected.slice().sort((a, b) => {
              return (
                flatIndexForWordRef(a.utteranceIndex, a.wordIndex) -
                flatIndexForWordRef(b.utteranceIndex, b.wordIndex)
              );
            });
          }
          return [{ utteranceIndex, wordIndex }];
        }

        function clearWordDropIndicators() {
          transcriptEl
            .querySelectorAll(
              ".word.drop-before, .word.drop-after, .word-insert-gap.drop-active, .utterance-boundary-gap.drop-active"
            )
            .forEach((node) => {
              node.classList.remove("drop-before", "drop-after", "drop-active");
            });
        }

        function wordDropTargetFromEvent(event, utteranceIndex, wordIndex) {
          const rect = event.currentTarget.getBoundingClientRect();
          const insertAfter = event.clientX >= rect.left + rect.width / 2;
          return {
            flatIndex: flatIndexForWordRef(utteranceIndex, wordIndex) + (insertAfter ? 1 : 0),
            speakerId: utterances[utteranceIndex].speakerId,
            insertAfter,
          };
        }

        function insertWordAt(utteranceIndex, insertIndex) {
          closeActiveEditor(true);
          hideSpeakerAssignMenu();
          const utterance = utterances[utteranceIndex];

          if (!utterance.words.length) {
            const newWord = {
              word: "",
              startTime: utterance.startTime,
              endTime: Math.max(utterance.endTime, utterance.startTime + 0.01),
              confidence: 1,
              speakerId: utterance.speakerId,
            };
            utterance.words.push(newWord);
            rebuildUtteranceText(utteranceIndex);
            syncWordBankFromUtterances();
            markDirty();
            scheduleWriteToLinkedFile();
            renderTranscript();
            const span = transcriptEl.querySelector(
              `.word[data-utterance-index="${utteranceIndex}"][data-word-index="0"]`
            );
            if (span) startWordEdit(span, utteranceIndex, 0);
            return;
          }

          const refIndex = insertIndex < utterance.words.length
            ? insertIndex
            : utterance.words.length - 1;
          const referenceWord = utterance.words[refIndex];
          const newWord = {
            word: "",
            startTime: referenceWord.startTime,
            endTime: referenceWord.endTime,
            confidence: referenceWord.confidence ?? 1,
            speakerId: referenceWord.speakerId ?? utterance.speakerId,
          };

          utterance.words.splice(insertIndex, 0, newWord);

          rebuildUtteranceText(utteranceIndex);
          syncWordBankFromUtterances();
          markDirty();
          scheduleWriteToLinkedFile();
          renderTranscript();

          const span = transcriptEl.querySelector(
            `.word[data-utterance-index="${utteranceIndex}"][data-word-index="${insertIndex}"]`
          );
          if (span) startWordEdit(span, utteranceIndex, insertIndex);
        }

        function handleInsertGapDragOver(event) {
          if (!isDragMode() || !wordDragState || activeEditor) return;
          event.preventDefault();
          event.stopPropagation();
          event.dataTransfer.dropEffect = "move";
          clearWordDropIndicators();
          event.currentTarget.classList.add("drop-active");
        }

        function handleInsertGapDrop(event, utteranceIndex, insertIndex) {
          if (!isDragMode() || !wordDragState || activeEditor) return;
          event.preventDefault();
          event.stopPropagation();
          clearWordDropIndicators();
          const words = utterances[utteranceIndex].words;
          const anchorStart =
            words[insertIndex]?.startTime ?? words[insertIndex - 1]?.startTime;
          const targetFlatIndex = flatIndexForWordRef(utteranceIndex, insertIndex);
          const targetSpeakerId = utterances[utteranceIndex].speakerId;
          const moved = moveWordRefsToFlatIndex(wordDragState.refs, targetFlatIndex, targetSpeakerId);
          wordDragState = null;
          if (moved) {
            window.getSelection()?.removeAllRanges();
            markDirty();
            scheduleWriteToLinkedFile();
            renderTranscript({ anchorStartTime: anchorStart });
          } else {
            finalizeDragModeUtterances({ anchorStartTime: anchorStart });
          }
        }

        function createWordInsertGap(utteranceIndex, insertIndex) {
          const gap = document.createElement("span");
          gap.className = "word-insert-gap";
          gap.title = isDragMode()
            ? "Click to add a word · Drop to move here"
            : "Click to add a word";
          gap.addEventListener("click", (event) => {
            event.stopPropagation();
            if (activeEditor || wordDragState) return;
            insertWordAt(utteranceIndex, insertIndex);
          });
          if (isDragMode()) {
            gap.addEventListener("dragover", handleInsertGapDragOver);
            gap.addEventListener("dragleave", () => {
              gap.classList.remove("drop-active");
            });
            gap.addEventListener("drop", (event) => {
              handleInsertGapDrop(event, utteranceIndex, insertIndex);
            });
          }
          return gap;
        }

        function createUtteranceBoundaryGap(utteranceIndex) {
          const gap = document.createElement("div");
          gap.className = "utterance-boundary-gap";
          gap.title = "Drop to move here";
          gap.addEventListener("dragover", handleInsertGapDragOver);
          gap.addEventListener("dragleave", () => {
            gap.classList.remove("drop-active");
          });
          gap.addEventListener("drop", (event) => {
            handleInsertGapDrop(event, utteranceIndex, 0);
          });
          return gap;
        }

        function handleWordDragStart(event, utteranceIndex, wordIndex) {
          if (!isDragMode() || activeEditor) {
            event.preventDefault();
            return;
          }
          hideSpeakerAssignMenu();
          const refs = refsForWordDrag(utteranceIndex, wordIndex);
          wordDragState = { refs };
          event.dataTransfer.effectAllowed = "move";
          event.dataTransfer.setData(
            "text/plain",
            refs.map((ref) => `${ref.utteranceIndex}:${ref.wordIndex}`).join(",")
          );
          event.currentTarget.classList.add("dragging");
        }

        function handleWordDragEnd(event) {
          event.currentTarget.classList.remove("dragging");
          clearWordDropIndicators();
          wordDragState = null;
          suppressNextWordClick = true;
        }

        function handleWordDragOver(event, utteranceIndex, wordIndex) {
          if (!isDragMode() || !wordDragState || activeEditor) return;
          event.preventDefault();
          event.stopPropagation();
          event.dataTransfer.dropEffect = "move";
          clearWordDropIndicators();
          const target = wordDropTargetFromEvent(event, utteranceIndex, wordIndex);
          event.currentTarget.classList.add(target.insertAfter ? "drop-after" : "drop-before");
        }

        function handleWordDrop(event, utteranceIndex, wordIndex) {
          if (!isDragMode() || !wordDragState || activeEditor) return;
          event.preventDefault();
          event.stopPropagation();
          clearWordDropIndicators();
          const anchorStart = utterances[utteranceIndex].words[wordIndex]?.startTime;
          const target = wordDropTargetFromEvent(event, utteranceIndex, wordIndex);
          const moved = moveWordRefsToFlatIndex(
            wordDragState.refs,
            target.flatIndex,
            target.speakerId
          );
          wordDragState = null;
          if (moved) {
            window.getSelection()?.removeAllRanges();
            markDirty();
            scheduleWriteToLinkedFile();
            renderTranscript({ anchorStartTime: anchorStart });
          } else {
            finalizeDragModeUtterances({ anchorStartTime: anchorStart });
          }
        }

        function getSelectedWordRefs() {
          const selection = window.getSelection();
          if (!selection || selection.isCollapsed || !selection.rangeCount) return [];

          const range = selection.getRangeAt(0);
          if (!transcriptEl.contains(range.commonAncestorContainer)) return [];
          const container = range.commonAncestorContainer;
          const containerElement =
            container.nodeType === Node.ELEMENT_NODE ? container : container.parentElement;
          if (containerElement?.closest(".utterance-editor, .word.editing")) return [];

          const refs = [];
          const seen = new Set();
          transcriptEl.querySelectorAll(".word").forEach((span) => {
            if (!selection.containsNode(span, true)) return;
            const utteranceIndex = Number(span.dataset.utteranceIndex);
            const wordIndex = Number(span.dataset.wordIndex);
            const key = `${utteranceIndex}:${wordIndex}`;
            if (seen.has(key)) return;
            seen.add(key);
            refs.push({ utteranceIndex, wordIndex });
          });
          return refs;
        }

        function selectedWordsAlreadySpeaker(refs, speakerId) {
          return refs.every((ref) => {
            const word = utterances[ref.utteranceIndex]?.words[ref.wordIndex];
            return word?.speakerId === speakerId;
          });
        }

        function showSpeakerAssignMenu(refs, anchorRect) {
          pendingSpeakerAssignRefs = refs;
          speakerAssignOptions.innerHTML = "";

          speakerIds.forEach((speakerId) => {
            const button = document.createElement("button");
            button.type = "button";
            button.className = "speaker-assign-option";
            if (selectedWordsAlreadySpeaker(refs, speakerId)) {
              button.classList.add("current");
              button.disabled = true;
            }
            button.innerHTML = `
              <span class="speaker-dot" style="background:${speakerColor(speakerId)}"></span>
              <span>${speakerName(speakerId)}</span>
            `;
            button.addEventListener("mousedown", (event) => event.preventDefault());
            button.addEventListener("click", () => {
              assignSelectedWordsToSpeaker(pendingSpeakerAssignRefs, speakerId);
            });
            speakerAssignOptions.appendChild(button);
          });

          const divider = document.createElement("div");
          divider.className = "speaker-assign-divider";
          speakerAssignOptions.appendChild(divider);

          const addButton = document.createElement("button");
          addButton.type = "button";
          addButton.className = "speaker-assign-option add-speaker";
          addButton.textContent = "+ Add speaker…";
          addButton.addEventListener("mousedown", (event) => event.preventDefault());
          addButton.addEventListener("click", () => {
            assignRefsAfterNewSpeaker = pendingSpeakerAssignRefs.slice();
            hideSpeakerAssignMenu();
            openAddSpeakerDialog();
          });
          speakerAssignOptions.appendChild(addButton);

          speakerAssignMenu.hidden = false;
          const menuRect = speakerAssignMenu.getBoundingClientRect();
          let left = anchorRect.left;
          let top = anchorRect.bottom + 8;
          const maxLeft = window.innerWidth - menuRect.width - 12;
          const maxTop = window.innerHeight - menuRect.height - 12;
          left = Math.max(12, Math.min(left, maxLeft));
          top = Math.max(12, Math.min(top, maxTop));
          speakerAssignMenu.style.left = `${left}px`;
          speakerAssignMenu.style.top = `${top}px`;
        }

        function assignSelectedWordsToSpeaker(refs, newSpeakerId) {
          if (!refs.length || selectedWordsAlreadySpeaker(refs, newSpeakerId)) {
            hideSpeakerAssignMenu();
            return;
          }

          const refSet = new Set(refs.map((ref) => `${ref.utteranceIndex}:${ref.wordIndex}`));
          const allWords = [];

          utterances.forEach((utterance, utteranceIndex) => {
            utterance.words.forEach((word, wordIndex) => {
              const nextWord = { ...word };
              if (refSet.has(`${utteranceIndex}:${wordIndex}`)) {
                nextWord.speakerId = newSpeakerId;
              }
              allWords.push(nextWord);
            });
          });

          allWords.sort((a, b) => a.startTime - b.startTime);
          utterances = regroupUtterancesFromWords(allWords, { respectTimeGaps: false });
          syncWordBankFromUtterances();
          window.getSelection()?.removeAllRanges();
          hideSpeakerAssignMenu();
          markDirty();
          scheduleWriteToLinkedFile();
          renderSpeakers();
          renderTranscript();
        }

        function handleTranscriptSelection() {
          if (!isAssignMode() || activeEditor) return;
          const refs = getSelectedWordRefs();
          if (!refs.length) {
            hideSpeakerAssignMenu();
            return;
          }

          const selection = window.getSelection();
          const range = selection.getRangeAt(0);
          let rect = range.getBoundingClientRect();
          if (!rect.width && !rect.height) {
            const firstRef = refs[0];
            const anchorWord = transcriptEl.querySelector(
              `.word[data-utterance-index="${firstRef.utteranceIndex}"][data-word-index="${firstRef.wordIndex}"]`
            );
            if (anchorWord) {
              rect = anchorWord.getBoundingClientRect();
            } else {
              hideSpeakerAssignMenu();
              return;
            }
          }
          showSpeakerAssignMenu(refs, rect);
        }

        function closeActiveEditor(shouldCommit = true) {
          hideSpeakerAssignMenu();
          if (!activeEditor) return;
          if (shouldCommit) {
            activeEditor.commit();
          } else {
            activeEditor.cancel();
          }
          activeEditor = null;
        }

        function startWordEdit(span, utteranceIndex, wordIndex) {
          closeActiveEditor(true);
          const utterance = utterances[utteranceIndex];
          const original = utterance.words[wordIndex].word;

          span.contentEditable = "true";
          span.classList.add("editing");
          span.textContent = original;
          span.focus();

          const selection = window.getSelection();
          const range = document.createRange();
          range.selectNodeContents(span);
          selection.removeAllRanges();
          selection.addRange(range);

          function detachListeners() {
            span.removeEventListener("blur", onBlur);
            span.removeEventListener("keydown", onKeyDown);
            span.removeEventListener("input", onInput);
          }

          function finishEditing() {
            span.contentEditable = "false";
            span.classList.remove("editing");
            detachListeners();
            if (activeEditor && activeEditor.span === span) {
              activeEditor = null;
            }
            updateSaveStatus();
          }

          function commit() {
            const next = span.textContent.trim();
            if (next) {
              utterance.words[wordIndex].word = next;
              rebuildUtteranceText(utteranceIndex);
              span.textContent = next;
              markDirty();
              scheduleWriteToLinkedFile();
              finishEditing();
            } else {
              utterance.words.splice(wordIndex, 1);
              rebuildUtteranceText(utteranceIndex);
              markDirty();
              scheduleWriteToLinkedFile();
              finishEditing();
              renderTranscript();
            }
          }

          function cancel() {
            span.textContent = original;
            finishEditing();
          }

          function onInput() {
            isDirty = true;
            updateSaveStatus();
          }

          function onBlur() {
            commit();
          }

          function onKeyDown(event) {
            if (event.key === "Enter") {
              event.preventDefault();
              detachListeners();
              commit();
            } else if (event.key === "Escape") {
              event.preventDefault();
              detachListeners();
              cancel();
            }
          }

          span.addEventListener("blur", onBlur);
          span.addEventListener("keydown", onKeyDown);
          span.addEventListener("input", onInput);
          activeEditor = { span, commit, cancel };
        }

        function startUtteranceEdit(wordsEl, utteranceIndex) {
          closeActiveEditor(true);
          const utterance = utterances[utteranceIndex];
          const original = utterance.text;

          const editor = document.createElement("div");
          editor.className = "utterance-editor";
          editor.contentEditable = "true";
          editor.textContent = original;
          wordsEl.replaceChildren(editor);
          editor.focus();

          const selection = window.getSelection();
          const range = document.createRange();
          range.selectNodeContents(editor);
          selection.removeAllRanges();
          selection.addRange(range);

          function detachListeners() {
            editor.removeEventListener("blur", onBlur);
            editor.removeEventListener("keydown", onKeyDown);
            editor.removeEventListener("input", onInput);
          }

          function commit() {
            const next = editor.textContent.trim();
            utterance.text = next;
            utterance.words = reconcileWordsFromText(
              next,
              utterance.speakerId,
              utterance.words,
              utterance.startTime,
              utterance.endTime
            ).words;
            syncWordBankFromUtterances();
            markDirty();
            scheduleWriteToLinkedFile();
            detachListeners();
            activeEditor = null;
            renderTranscript();
            updateSaveStatus();
          }

          function cancel() {
            utterance.text = original;
            detachListeners();
            activeEditor = null;
            renderTranscript();
            updateSaveStatus();
          }

          function onInput() {
            markDirty();
          }

          function onBlur() {
            commit();
          }

          function onKeyDown(event) {
            if (event.key === "Escape") {
              event.preventDefault();
              cancel();
            } else if (event.key === "Enter" && !event.shiftKey) {
              event.preventDefault();
              detachListeners();
              commit();
            }
          }

          editor.addEventListener("blur", onBlur);
          editor.addEventListener("keydown", onKeyDown);
          editor.addEventListener("input", onInput);
          activeEditor = { editor, commit, cancel };
        }

        function renderSpeakers() {
          speakersPanel.innerHTML = "";
          speakerIds.forEach((id) => {
            const chip = document.createElement("div");
            chip.className = "speaker-chip";
            chip.innerHTML = `
              <span class="speaker-dot" style="background:${speakerColor(id)}"></span>
              <span>${speakerName(id)}</span>
              <button type="button" data-speaker="${id}">Rename</button>
            `;
            chip.querySelector("button").addEventListener("click", () => openRenameDialog(id));
            speakersPanel.appendChild(chip);
          });
        }

        function stickyHeaderOffset() {
          const panel = document.querySelector(".player-panel");
          return panel ? panel.getBoundingClientRect().bottom : 0;
        }

        function captureScrollAnchor(options = {}) {
          if (options.anchorStartTime != null) {
            const el = transcriptEl.querySelector(
              `.word[data-start="${options.anchorStartTime}"]`
            );
            if (el) {
              return {
                startTime: options.anchorStartTime,
                top: el.getBoundingClientRect().top,
              };
            }
          }

          const minTop = stickyHeaderOffset();
          for (const word of transcriptEl.querySelectorAll(".word")) {
            const top = word.getBoundingClientRect().top;
            if (top >= minTop) {
              return {
                startTime: Number(word.dataset.start),
                top,
              };
            }
          }
          return null;
        }

        function restoreScrollAnchor(anchor) {
          if (!anchor) return;
          const el = transcriptEl.querySelector(`.word[data-start="${anchor.startTime}"]`);
          if (!el) return;
          const delta = el.getBoundingClientRect().top - anchor.top;
          if (Math.abs(delta) > 0.5) {
            window.scrollBy(0, delta);
          }
        }

        function renderTranscript(options = {}) {
          if (activeEditor) return;
          const anchor = captureScrollAnchor(options);
          transcriptEl.innerHTML = "";
          utterances.forEach((utterance, index) => {
            if (isDragMode() && index > 0) {
              transcriptEl.appendChild(createUtteranceBoundaryGap(index));
            }

            const block = document.createElement("article");
            block.className = "utterance";
            block.style.borderLeftColor = speakerColor(utterance.speakerId);
            block.dataset.index = String(index);
            block.dataset.start = String(utterance.startTime);

            const header = document.createElement("div");
            header.className = "utterance-header";
            header.innerHTML = `
              <span class="speaker-label" style="color:${speakerColor(utterance.speakerId)}">${speakerName(utterance.speakerId)}</span>
              <span>${formatTime(utterance.startTime)}</span>
            `;

            const wordsEl = document.createElement("div");
            wordsEl.className = "words";
            wordsEl.appendChild(createWordInsertGap(index, 0));
            utterance.words.forEach((word, wordIndex) => {
              const span = document.createElement("span");
              span.className = "word";
              span.textContent = word.word;
              span.draggable = isDragMode();
              span.dataset.utteranceIndex = String(index);
              span.dataset.wordIndex = String(wordIndex);
              span.dataset.start = String(word.startTime);
              span.dataset.end = String(word.endTime);
              span.title = wordTooltip(word.startTime, isDragMode());

              if (isDragMode()) {
                span.addEventListener("dragstart", (event) => {
                  handleWordDragStart(event, index, wordIndex);
                });
                span.addEventListener("dragend", handleWordDragEnd);
                span.addEventListener("dragover", (event) => {
                  handleWordDragOver(event, index, wordIndex);
                });
                span.addEventListener("drop", (event) => {
                  handleWordDrop(event, index, wordIndex);
                });
              }

              span.addEventListener("click", (event) => {
                event.stopPropagation();
                if (suppressNextWordClick) {
                  suppressNextWordClick = false;
                  return;
                }
                if (span.isContentEditable) return;
                startWordEdit(span, index, wordIndex);
              });

              span.addEventListener("contextmenu", (event) => {
                event.preventDefault();
                event.stopPropagation();
                playFrom(Number(span.dataset.start));
              });

              wordsEl.appendChild(span);
              wordsEl.appendChild(createWordInsertGap(index, wordIndex + 1));
            });

            wordsEl.addEventListener("dblclick", (event) => {
              if (activeEditor) return;
              event.preventDefault();
              event.stopPropagation();
              startUtteranceEdit(wordsEl, index);
            });

            block.addEventListener("contextmenu", (event) => {
              if (event.target.closest(".word")) return;
              event.preventDefault();
              playFrom(utterance.startTime);
            });

            block.appendChild(header);
            block.appendChild(wordsEl);
            transcriptEl.appendChild(block);
          });
          restoreScrollAnchor(anchor);
        }

        transcriptEl.addEventListener("mouseup", () => {
          if (!isAssignMode()) return;
          window.setTimeout(handleTranscriptSelection, 0);
        });

        modeAssignBtn.addEventListener("click", () => setEditMode("assign"));
        modeDragBtn.addEventListener("click", () => setEditMode("drag"));

        document.addEventListener("mousedown", (event) => {
          if (!speakerAssignMenu.hidden && !speakerAssignMenu.contains(event.target)) {
            hideSpeakerAssignMenu();
          }
        });

        document.addEventListener("keydown", (event) => {
          if (event.key === "Escape") hideSpeakerAssignMenu();
        });

        window.addEventListener("scroll", hideSpeakerAssignMenu, true);
        window.addEventListener("resize", hideSpeakerAssignMenu);

        function openRenameDialog(speakerId) {
          addingNewSpeaker = false;
          assignRefsAfterNewSpeaker = null;
          renamingSpeakerId = speakerId;
          renameDialog.querySelector("h3").textContent = "Rename speaker";
          renameForm.querySelector("button.primary").textContent = "Save";
          speakerNameInput.value = speakerName(speakerId);
          renameDialog.showModal();
          speakerNameInput.focus();
          speakerNameInput.select();
        }

        function openAddSpeakerDialog() {
          addingNewSpeaker = true;
          renamingSpeakerId = null;
          renameDialog.querySelector("h3").textContent = "Add speaker";
          renameForm.querySelector("button.primary").textContent = "Add";
          speakerNameInput.value = nextDefaultSpeakerName();
          renameDialog.showModal();
          speakerNameInput.focus();
          speakerNameInput.select();
        }

        renameForm.addEventListener("submit", (event) => {
          event.preventDefault();
          const nextName = speakerNameInput.value.trim();
          if (!nextName) return;

          if (addingNewSpeaker) {
            const newId = nextSpeakerId();
            speakerIds.push(newId);
            speakerNames[newId] = nextName;
            const refs = assignRefsAfterNewSpeaker;
            addingNewSpeaker = false;
            assignRefsAfterNewSpeaker = null;
            renameDialog.close();
            renderSpeakers();
            if (refs?.length) {
              assignSelectedWordsToSpeaker(refs, newId);
            } else {
              markDirty();
              scheduleWriteToLinkedFile();
            }
            return;
          }

          if (!renamingSpeakerId) return;
          speakerNames[renamingSpeakerId] = nextName;
          markDirty();
          renderSpeakers();
          renderTranscript();
          scheduleWriteToLinkedFile();
          renameDialog.close();
          renamingSpeakerId = null;
        });

        cancelRename.addEventListener("click", () => {
          renameDialog.close();
          renamingSpeakerId = null;
          addingNewSpeaker = false;
          assignRefsAfterNewSpeaker = null;
        });

        function updateHighlight() {
          if (activeEditor) return;
          const current = audio.currentTime;
          timeDisplay.textContent = `${formatTime(current)} / {{DURATION}}`;

          document.querySelectorAll(".utterance").forEach((node) => {
            const index = Number(node.dataset.index);
            const utterance = utterances[index];
            const active = current >= utterance.startTime && current <= utterance.endTime + 0.15;
            node.classList.toggle("active", active);
          });

          document.querySelectorAll(".word").forEach((node) => {
            const start = Number(node.dataset.start);
            const end = Number(node.dataset.end);
            node.classList.toggle("active", current >= start && current <= end + 0.05);
          });
        }

        audio.addEventListener("timeupdate", updateHighlight);
        audio.addEventListener("loadedmetadata", updateHighlight);

        updateEditModeUI();
        renderSpeakers();
        renderTranscript();
        syncWordBankFromUtterances();
        updateSaveStatus();
        restoreLinkedFileOnLoad().catch(() => showLinkPrompt(false));
      </script>
    </body>
    </html>
    """
}
