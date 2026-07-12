const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("mecoscribeApp", {
  startTranscription: (audioPath) => ipcRenderer.invoke("start-transcription", audioPath),
  onTranscriptionStart: (callback) => {
    ipcRenderer.on("transcription-start", (_, data) => callback(data));
  },
  onTranscriptionProgress: (callback) => {
    ipcRenderer.on("transcription-progress", (_, data) => callback(data));
  },
  onTranscriptionComplete: (callback) => {
    ipcRenderer.on("transcription-complete", (_, data) => callback(data));
  },
  onTranscriptionError: (callback) => {
    ipcRenderer.on("transcription-error", (_, data) => callback(data));
  },
});
