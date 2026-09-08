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
// single tile request leaving the machine. The colour and name differ per style
// so a test can tell which one is drawn.
export const STYLE_COLORS = {
  liberty: '#cfe8cf',
  bright: '#f6f0d8',
  positron: '#f4f4f4',
  dark: '#222222',
  fiord: '#4a5568',
}

export function styleFor(id) {
  return {
    version: 8,
    name: id,
    sources: {},
    layers: [{ id: 'bg', type: 'background', paint: { 'background-color': STYLE_COLORS[id] || '#cfe8cf' } }],
  }
}

export const STYLE = styleFor('liberty')

export async function routeStyle(page) {
  await page.route('**/tiles.openfreemap.org/**', (r) => {
    const id = new URL(r.request().url()).pathname.split('/').pop()
    const body = STYLE_COLORS[id] ? styleFor(id) : STYLE
    return r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) })
  })
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
