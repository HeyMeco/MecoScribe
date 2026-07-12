const { contextBridge, ipcRenderer } = require("electron");

let externalChangeCallback = null;

contextBridge.exposeInMainWorld("mecoscribe", {
  isElectron: true,
  projectDirName: "",
  audioURL: "",
  async init() {
    const info = await ipcRenderer.invoke("get-project-info");
    if (!info) return;
    this.projectDirName = info.projectDirName;
    this.audioURL = info.audioURL;
    return info;
  },
  readFile: (relativePath) => ipcRenderer.invoke("read-project-file", relativePath),
  writeFile: (relativePath, content) =>
    ipcRenderer.invoke("write-project-file", relativePath, content),
  onExternalChange(callback) {
    externalChangeCallback = callback;
  },
  closeEditor: () => ipcRenderer.invoke("close-editor"),
  retranscribe: () => ipcRenderer.invoke("retranscribe"),
  exportHTML: () => ipcRenderer.invoke("export-html"),
});

ipcRenderer.on("external-file-change", () => {
  if (externalChangeCallback) externalChangeCallback();
});
