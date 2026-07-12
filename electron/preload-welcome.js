const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("mecoscribeApp", {
  openAudioDialog: () => ipcRenderer.invoke("open-audio-dialog"),
  openTranscriptDialog: () => ipcRenderer.invoke("open-transcript-dialog"),
  openAudio: (path) => ipcRenderer.invoke("open-audio", path),
  openTranscript: (path) => ipcRenderer.invoke("open-transcript", path),
  getSettings: () => ipcRenderer.invoke("get-settings"),
  setSettings: (settings) => ipcRenderer.invoke("set-settings", settings),
  onOpenSettings: (callback) => {
    ipcRenderer.on("open-settings", () => callback());
  },
});
