import {
  buildExport, exportName, parseImport, applyImport, confirmText, importedText, nothingText,
} from './backup.js'

// The import result has to outlive the reload that applies it.
const NOTICE = 'mapper.importNotice'

export function takeNotice() {
  try {
    const text = window.sessionStorage.getItem(NOTICE)
    window.sessionStorage.removeItem(NOTICE)
    return text
  } catch {
    return null
  }
}

function leaveNotice(text) {
  try {
    window.sessionStorage.setItem(NOTICE, text)
  } catch {
    // ignored: the import still applies, just without the message
  }
}

function download(name, text) {
  const url = URL.createObjectURL(new Blob([text], { type: 'application/json' }))
  const a = document.createElement('a')
  a.href = url
  a.download = name
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

function exportData(store) {
  const now = new Date()
  download(exportName(now), JSON.stringify(buildExport(store, now), null, 2) + '\n')
}

async function importFile(store, toast, file) {
  let text
  try {
    text = await file.text()
  } catch {
    toast('Could not read ' + file.name + '.')
    return
  }
  const result = parseImport(text)
  if (result.error) {
    toast(result.error)
    return
  }
  if (!result.writes.length) {
    toast(nothingText(result, file.name))
    return
  }
  if (!window.confirm(confirmText(result, file.name))) return
  applyImport(store, result.writes)
  leaveNotice(importedText(result))
  // Every module reads its key once at startup, so a reload is what applies it.
  window.location.reload()
}

export function Backup({ store, toast }) {
  let input = null
  const picked = (e) => {
    const file = e.currentTarget.files[0]
    // Cleared so picking the same file again still fires change.
    e.currentTarget.value = ''
    if (file) importFile(store, toast, file)
  }
  return (
    <div id="backup">
      <div class="backup-heading">Saved data</div>
      <div class="backup-row">
        <button id="export" class="backup-button" title="Download the saved settings and places" onClick={() => exportData(store)}>
          Export
        </button>
        <button id="import" class="backup-button" title="Replace the saved settings and places from a file" onClick={() => input.click()}>
          Import…
        </button>
        <input
          id="import-file"
          type="file"
          accept=".json,application/json"
          hidden
          ref={(el) => { input = el }}
          onChange={picked}
        />
      </div>
    </div>
  )
}
