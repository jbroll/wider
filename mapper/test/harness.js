import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const DIST = path.join(HERE, '..', 'dist', 'index.html')

// Built once per run: every test loads the same artifact the launcher serves.
let html = null
function page() {
  if (html === null) {
    execFileSync('node', [path.join(HERE, '..', 'build.js')], { stdio: 'inherit' })
    html = fs.readFileSync(DIST, 'utf8')
  }
  return html
}

// One background layer and no sources, so the map builds and paints without a
// single tile request leaving the machine.
export const STYLE = {
  version: 8,
  name: 'test',
  sources: {},
  layers: [{ id: 'bg', type: 'background', paint: { 'background-color': '#cfe8cf' } }],
}

export async function routeStyle(page) {
  await page.route('**/tiles.openfreemap.org/**', (r) =>
    r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(STYLE) }))
}

export function startPage() {
  const body = page()
  const server = http.createServer((req, res) => {
    if (req.url.split('?')[0] !== '/') {
      res.writeHead(404).end('not found')
      return
    }
    res.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' })
    res.end(body)
  })
  const sockets = new Set()
  server.on('connection', (s) => { sockets.add(s); s.on('close', () => sockets.delete(s)) })
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      resolve({
        url: 'http://127.0.0.1:' + server.address().port + '/',
        close() {
          for (const s of sockets) s.destroy()
          return new Promise((done) => server.close(done))
        },
      })
    })
  })
}
