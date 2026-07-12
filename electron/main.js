const {
  app,
  BrowserWindow,
  ipcMain,
  dialog,
  Menu,
  shell,
} = require("electron");
const path = require("path");
const fs = require("fs");
const fsp = require("fs/promises");
const { spawn } = require("child_process");
const os = require("os");
const { pathToFileURL } = require("url");

const SETTINGS_FILE = "settings.json";
const AUDIO_EXTENSIONS = ["wav", "mp3", "m4a", "aac", "flac", "ogg"];
const TRANSCRIPT_EXTENSION = "txt";

let mainWindow = null;
let progressWindow = null;
let editorWindow = null;
let fileWatcher = null;
let settings = loadSettings();
let activeProject = null;

function loadSettings() {
  const defaults = {
    diarizationMode: "offline",
    threshold: 0.6,
    modelVersion: "v3",
    modelsDir: "",
    modelDir: "",
    presetSpeakers: "",
  };
  try {
    const settingsPath = path.join(app.getPath("userData"), SETTINGS_FILE);
    if (fs.existsSync(settingsPath)) {
      return { ...defaults, ...JSON.parse(fs.readFileSync(settingsPath, "utf8")) };
    }
  } catch (_) {}
  return defaults;
}

function saveSettings() {
  const settingsPath = path.join(app.getPath("userData"), SETTINGS_FILE);
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
}

function cliBinaryPath() {
  const candidates = [
    path.join(__dirname, "..", ".build", "release", "mecoscribe"),
    path.join(__dirname, "..", ".build", "debug", "mecoscribe"),
    path.join(process.cwd(), ".build", "release", "mecoscribe"),
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  return candidates[0];
}

function editorTemplatePath() {
  return path.join(
    __dirname,
    "..",
    "Sources",
    "MecoScribeCore",
    "Resources",
    "editor-template.html"
  );
}

function escapeHTML(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function formatDuration(seconds) {
  const total = Math.floor(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const secs = total % 60;
  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
  }
  return `${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
}

function sidecarPathForTxt(txtPath) {
  const base = txtPath.replace(/\.[^.]+$/, "");
  return `${base}.mecoscribe.json`;
}

async function loadTranscriptData(txtPath, audioPath) {
  const sidecarPath = sidecarPathForTxt(txtPath);
  if (fs.existsSync(sidecarPath)) {
    const sidecar = JSON.parse(await fsp.readFile(sidecarPath, "utf8"));
    return {
      utterances: sidecar.utterances,
      speakerIds: sidecar.speakerIds,
      speakerNames: sidecar.speakerNames || {},
      audioFile: sidecar.audioFile || audioPath,
      durationSeconds: sidecar.durationSeconds || 0,
      speakerCount: sidecar.speakerCount || sidecar.speakerIds?.length || 0,
      txtBaseName: path.basename(txtPath),
      timingsBaseName: path.basename(sidecarPath),
    };
  }

  await runCLI([audioPath, "--html-only", "--json-progress"], { cwd: path.dirname(audioPath) });
  if (fs.existsSync(sidecarPath)) {
    return loadTranscriptData(txtPath, audioPath);
  }
  throw new Error("Could not load transcript sidecar");
}

async function renderEditorHTML(data, projectDir) {
  const template = await fsp.readFile(editorTemplatePath(), "utf8");
  const audioFileName = path.basename(data.audioFile);
  const audioSrc = path.relative(projectDir, data.audioFile);

  return template
    .replace(/\{\{TITLE\}\}/g, escapeHTML(audioFileName))
    .replace(/\{\{TXT_BASENAME\}\}/g, escapeHTML(data.txtBaseName))
    .replace(/\{\{TIMINGS_BASENAME\}\}/g, escapeHTML(data.timingsBaseName))
    .replace(/\{\{AUDIO_SRC\}\}/g, escapeHTML(audioSrc))
    .replace(/\{\{SOURCE_FILE\}\}/g, escapeHTML(data.audioFile))
    .replace(/\{\{DURATION\}\}/g, escapeHTML(formatDuration(data.durationSeconds)))
    .replace(/\{\{DURATION_SECONDS\}\}/g, String(data.durationSeconds))
    .replace(/\{\{SPEAKER_COUNT\}\}/g, String(data.speakerCount))
    .replace(/\{\{UTTERANCES_JSON\}\}/g, JSON.stringify(data.utterances))
    .replace(/\{\{SPEAKER_IDS_JSON\}\}/g, JSON.stringify(data.speakerIds))
    .replace(/\{\{SPEAKER_NAMES_JSON\}\}/g, JSON.stringify(data.speakerNames));
}

function closeProgressWindow() {
  const win = progressWindow;
  progressWindow = null;
  if (win && !win.isDestroyed()) {
    win.close();
  }
  if (mainWindow === win) {
    mainWindow = null;
  }
}

function buildCLIArgs(audioPath) {
  const args = [audioPath, "--json-progress", "--both"];
  if (settings.diarizationMode) args.push("--mode", settings.diarizationMode);
  if (settings.threshold) args.push("--threshold", String(settings.threshold));
  if (settings.modelVersion) args.push("--model-version", settings.modelVersion);
  if (settings.modelsDir) args.push("--models-dir", settings.modelsDir);
  if (settings.modelDir) args.push("--model-dir", settings.modelDir);
  if (settings.presetSpeakers) {
    args.push("--speakers", settings.presetSpeakers);
  }
  return args;
}

function runCLI(args, { cwd, onProgress, onLine } = {}) {
  return new Promise((resolve, reject) => {
    const binary = cliBinaryPath();
    const child = spawn(binary, args, {
      cwd: cwd || process.cwd(),
      env: {
        ...process.env,
        ...(settings.modelsDir ? { MECOSCRIBE_MODELS_DIR: settings.modelsDir } : {}),
      },
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      stdout += text;
      text.split("\n").forEach((line) => {
        const trimmed = line.trim();
        if (!trimmed) return;
        try {
          const payload = JSON.parse(trimmed);
          if (payload.type === "progress" && onProgress) {
            onProgress(payload);
          }
        } catch (_) {
          if (onLine) onLine(trimmed, "stdout");
        }
      });
    });

    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      stderr += text;
      if (onLine) {
        text.split("\n").forEach((line) => {
          if (line.trim()) onLine(line.trim(), "stderr");
        });
      }
    });

    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve({ stdout, stderr });
      else reject(new Error(stderr.trim() || stdout.trim() || `CLI exited with code ${code}`));
    });
  });
}

function stopFileWatcher() {
  if (fileWatcher) {
    fileWatcher.close();
    fileWatcher = null;
  }
}

function startFileWatcher(projectDir, txtBaseName, webContents) {
  stopFileWatcher();
  const txtPath = path.join(projectDir, txtBaseName);
  let debounce = null;
  fileWatcher = fs.watch(projectDir, (_, filename) => {
    if (filename && filename !== txtBaseName) return;
    clearTimeout(debounce);
    debounce = setTimeout(() => {
      if (fs.existsSync(txtPath) && webContents && !webContents.isDestroyed()) {
        webContents.send("external-file-change");
      }
    }, 300);
  });
}

function createWelcomeWindow() {
  if (mainWindow) {
    mainWindow.focus();
    return;
  }

  mainWindow = new BrowserWindow({
    width: 560,
    height: 480,
    minWidth: 480,
    minHeight: 400,
    title: "MecoScribe",
    webPreferences: {
      preload: path.join(__dirname, "preload-welcome.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, "src", "welcome.html"));
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

async function openEditor({ txtPath, audioPath }) {
  closeProgressWindow();

  const projectDir = path.dirname(txtPath);
  const data = await loadTranscriptData(txtPath, audioPath);
  const html = await renderEditorHTML(data, projectDir);
  const editorHtmlPath = path.join(os.tmpdir(), `mecoscribe-editor-${Date.now()}.html`);
  await fsp.writeFile(editorHtmlPath, html, "utf8");

  activeProject = {
    projectDir,
    txtPath,
    audioPath,
    txtBaseName: data.txtBaseName,
    timingsBaseName: data.timingsBaseName,
    editorHtmlPath,
  };

  if (editorWindow) {
    editorWindow.close();
  }

  editorWindow = new BrowserWindow({
    width: 1100,
    height: 800,
    minWidth: 900,
    minHeight: 700,
    title: `${path.basename(audioPath)} — MecoScribe`,
    webPreferences: {
      preload: path.join(__dirname, "preload-editor.js"),
      contextIsolation: true,
      nodeIntegration: false,
      webSecurity: false,
    },
  });

  editorWindow.loadFile(editorHtmlPath);
  startFileWatcher(projectDir, data.txtBaseName, editorWindow.webContents);

  editorWindow.on("closed", () => {
    stopFileWatcher();
    const htmlPath = activeProject?.editorHtmlPath;
    activeProject = null;
    editorWindow = null;
    if (htmlPath) fsp.unlink(htmlPath).catch(() => {});
  });

  if (mainWindow) {
    mainWindow.close();
    mainWindow = null;
  }
}

async function openAudioFile(audioPath) {
  const baseName = path.basename(audioPath, path.extname(audioPath));
  const txtPath = path.join(path.dirname(audioPath), `${baseName}.txt`);

  if (fs.existsSync(txtPath)) {
    await openEditor({ txtPath, audioPath });
    return;
  }

  createProgressWindow(audioPath);
}

let pendingTranscription = null;

function createProgressWindow(audioPath, { overwrite = false } = {}) {
  pendingTranscription = { audioPath, overwrite };
  closeProgressWindow();
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.close();
    mainWindow = null;
  }

  mainWindow = new BrowserWindow({
    width: 520,
    height: 420,
    minWidth: 440,
    minHeight: 360,
    title: "Transcribing — MecoScribe",
    webPreferences: {
      preload: path.join(__dirname, "preload-progress.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, "src", "progress.html"), {
    query: { audioPath },
  });
  progressWindow = mainWindow;
  mainWindow.on("closed", () => {
    if (progressWindow === mainWindow) progressWindow = null;
    mainWindow = null;
  });
}

function buildMenu() {
  const template = [
    {
      label: "Transcript",
      submenu: [
        {
          label: "Re-transcribe",
          click: async () => {
            if (!activeProject) return;
            try {
              await ipcMain.emit("retranscribe-request");
            } catch (_) {}
          },
        },
        {
          label: "Export HTML…",
          click: async () => {
            if (!activeProject) return;
            try {
              await ipcMain.emit("export-html-request");
            } catch (_) {}
          },
        },
        { type: "separator" },
        {
          label: "Close Transcript",
          click: () => {
            if (editorWindow) editorWindow.close();
            createWelcomeWindow();
          },
        },
      ],
    },
    {
      label: "MecoScribe",
      submenu: [
        {
          label: "Open Audio…",
          accelerator: "CmdOrCtrl+O",
          click: () => ipcMain.emit("menu-open-audio"),
        },
        {
          label: "Open Transcript…",
          accelerator: "CmdOrCtrl+Shift+T",
          click: () => ipcMain.emit("menu-open-transcript"),
        },
        { type: "separator" },
        {
          label: "Settings…",
          accelerator: "CmdOrCtrl+,",
          click: () => {
            if (mainWindow) mainWindow.webContents.send("open-settings");
            else if (editorWindow) editorWindow.webContents.send("open-settings");
            else createWelcomeWindow();
          },
        },
        { type: "separator" },
        { role: "quit" },
      ],
    },
    {
      label: "Edit",
      submenu: [
        { role: "undo" },
        { role: "redo" },
        { type: "separator" },
        { role: "cut" },
        { role: "copy" },
        { role: "paste" },
        { role: "selectAll" },
      ],
    },
    {
      label: "Transcript",
      submenu: [
        {
          label: "Re-transcribe",
          click: async () => {
            if (!activeProject) return;
            const { audioPath } = activeProject;
            const editorHtmlPath = activeProject.editorHtmlPath;
            if (editorWindow) editorWindow.close();
            if (editorHtmlPath) fsp.unlink(editorHtmlPath).catch(() => {});
            createProgressWindow(audioPath, { overwrite: true });
          },
        },
        {
          label: "Export HTML…",
          click: async () => {
            if (!activeProject) return;
            try {
              const data = await loadTranscriptData(activeProject.txtPath, activeProject.audioPath);
              const html = await renderEditorHTML(data, activeProject.projectDir);
              const defaultName = path.basename(activeProject.txtPath, ".txt") + ".html";
              const result = await dialog.showSaveDialog({
                defaultPath: defaultName,
                filters: [{ name: "HTML", extensions: ["html"] }],
              });
              if (!result.canceled && result.filePath) {
                await fsp.writeFile(result.filePath, html, "utf8");
              }
            } catch (error) {
              dialog.showErrorBox("Export HTML", error.message);
            }
          },
        },
        { type: "separator" },
        {
          label: "Close Transcript",
          click: () => {
            if (editorWindow) editorWindow.close();
            createWelcomeWindow();
          },
        },
      ],
    },
    {
      label: "View",
      submenu: [{ role: "reload" }, { role: "toggleDevTools" }],
    },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

app.whenReady().then(() => {
  buildMenu();
  createWelcomeWindow();

  app.on("activate", () => {
    if (!mainWindow && !editorWindow) createWelcomeWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

ipcMain.handle("get-settings", () => settings);

ipcMain.handle("set-settings", (_, next) => {
  settings = { ...settings, ...next };
  saveSettings();
  return settings;
});

ipcMain.handle("open-audio-dialog", async () => {
  const result = await dialog.showOpenDialog({
    properties: ["openFile"],
    filters: [{ name: "Audio", extensions: AUDIO_EXTENSIONS }],
  });
  return result.canceled ? null : result.filePaths[0];
});

ipcMain.handle("open-transcript-dialog", async () => {
  const result = await dialog.showOpenDialog({
    properties: ["openFile"],
    filters: [{ name: "Transcript", extensions: [TRANSCRIPT_EXTENSION] }],
  });
  return result.canceled ? null : result.filePaths[0];
});

ipcMain.handle("open-audio", async (_, audioPath) => {
  await openAudioFile(audioPath);
});

ipcMain.handle("open-transcript", async (_, txtPath) => {
  const baseName = path.basename(txtPath, ".txt");
  const dir = path.dirname(txtPath);
  const candidates = AUDIO_EXTENSIONS.map((ext) =>
    path.join(dir, `${baseName}.${ext}`)
  );
  const audioPath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!audioPath) {
    throw new Error(`No audio file found beside ${path.basename(txtPath)}`);
  }
  await openEditor({ txtPath, audioPath });
});

ipcMain.handle("start-transcription", async (event, audioPath) => {
  pendingTranscription = null;
  try {
    await runCLI(buildCLIArgs(audioPath), {
      cwd: path.dirname(audioPath),
      onProgress: (payload) => {
        event.sender.send("transcription-progress", payload);
      },
    });
    const baseName = path.basename(audioPath, path.extname(audioPath));
    const txtPath = path.join(path.dirname(audioPath), `${baseName}.txt`);
    event.sender.send("transcription-complete", { txtPath, audioPath });
    closeProgressWindow();
    await openEditor({ txtPath, audioPath });
    return { ok: true };
  } catch (error) {
    event.sender.send("transcription-error", { message: error.message });
    throw error;
  }
});

ipcMain.handle("cancel-transcription", () => {
  // Future: track and kill child process
});

ipcMain.handle("get-project-info", () => {
  if (!activeProject) return null;
  return {
    projectDir: activeProject.projectDir,
    projectDirName: path.basename(activeProject.projectDir),
    txtBaseName: activeProject.txtBaseName,
    timingsBaseName: activeProject.timingsBaseName,
    audioPath: activeProject.audioPath,
    audioURL: pathToFileURL(activeProject.audioPath).href,
  };
});

ipcMain.handle("read-project-file", async (_, relativePath) => {
  if (!activeProject) return null;
  const fullPath = path.join(activeProject.projectDir, relativePath);
  try {
    const stat = await fsp.stat(fullPath);
    const text = await fsp.readFile(fullPath, "utf8");
    return { text, lastModified: stat.mtimeMs };
  } catch (_) {
    return null;
  }
});

ipcMain.handle("write-project-file", async (_, relativePath, content) => {
  if (!activeProject) throw new Error("No active project");
  const fullPath = path.join(activeProject.projectDir, relativePath);
  await fsp.writeFile(fullPath, content, "utf8");
  const stat = await fsp.stat(fullPath);
  return stat.mtimeMs;
});

ipcMain.handle("retranscribe", async () => {
  if (!activeProject) throw new Error("No active project");
  const { audioPath } = activeProject;
  const editorHtmlPath = activeProject.editorHtmlPath;
  if (editorWindow) editorWindow.close();
  if (editorHtmlPath) fsp.unlink(editorHtmlPath).catch(() => {});
  createProgressWindow(audioPath, { overwrite: true });
  return true;
});

ipcMain.handle("export-html", async () => {
  if (!activeProject) throw new Error("No active project");
  const data = await loadTranscriptData(activeProject.txtPath, activeProject.audioPath);
  const html = await renderEditorHTML(data, activeProject.projectDir);
  const defaultName = path.basename(activeProject.txtPath, ".txt") + ".html";
  const result = await dialog.showSaveDialog({
    defaultPath: defaultName,
    filters: [{ name: "HTML", extensions: ["html"] }],
  });
  if (result.canceled || !result.filePath) return false;
  await fsp.writeFile(result.filePath, html, "utf8");
  return true;
});

ipcMain.handle("close-editor", () => {
  if (editorWindow) editorWindow.close();
  createWelcomeWindow();
});

ipcMain.on("menu-open-audio", async () => {
  const audioPath = await dialog.showOpenDialog({
    properties: ["openFile"],
    filters: [{ name: "Audio", extensions: AUDIO_EXTENSIONS }],
  }).then((r) => (r.canceled ? null : r.filePaths[0]));
  if (audioPath) await openAudioFile(audioPath);
});

ipcMain.on("menu-open-transcript", async () => {
  const txtPath = await dialog.showOpenDialog({
    properties: ["openFile"],
    filters: [{ name: "Transcript", extensions: [TRANSCRIPT_EXTENSION] }],
  }).then((r) => (r.canceled ? null : r.filePaths[0]));
  if (!txtPath) return;
  try {
    const baseName = path.basename(txtPath, ".txt");
    const dir = path.dirname(txtPath);
    const candidates = AUDIO_EXTENSIONS.map((ext) =>
      path.join(dir, `${baseName}.${ext}`)
    );
    const audioPath = candidates.find((candidate) => fs.existsSync(candidate));
    if (!audioPath) {
      throw new Error(`No audio file found beside ${path.basename(txtPath)}`);
    }
    await openEditor({ txtPath, audioPath });
  } catch (error) {
    dialog.showErrorBox("Open Transcript", error.message);
  }
});
