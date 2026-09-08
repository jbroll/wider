import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'

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

// The background layer needs no source. The symbol layers sit on an empty
// inline GeoJSON source and carry no text-field, so neither tiles nor glyphs
// are ever fetched for them. The building layer needs a vector source to carry
// a source-layer; its tiles are declared inline so no TileJSON is fetched, and
// routeStyle aborts any request that does reach them. The colour and name
// differ per style so a test can tell which one is drawn.
export const STYLE_COLORS = {
  liberty: '#cfe8cf',
  bright: '#f6f0d8',
  positron: '#f4f4f4',
  dark: '#222222',
  fiord: '#4a5568',
}

// The Streets label color differs per style so a test can watch an unset
// swatch re-seed on a switch.
export const LABEL_COLORS = {
  liberty: '#666666',
  bright: '#886644',
  positron: '#444444',
  dark: '#504e4e',
  fiord: '#333333',
}

// One labelled layer per color group, plus a shield with no text-color and a
// water label whose color is an hsl() the seeding code has to normalise.
// street-label declares no text-halo-width, so the transform's absent-width
// clause is exercised too. fiord drops the POI layer so a group absent from
// the current style is exercised by at least one style.
export function styleFor(id) {
  const layers = [
    { id: 'bg', type: 'background', paint: { 'background-color': STYLE_COLORS[id] || '#cfe8cf' } },
    {
      id: 'place-label',
      type: 'symbol',
      source: 'empty',
      'source-layer': 'place',
      layout: { 'text-size': 12 },
      paint: { 'text-color': '#334455', 'text-halo-color': '#ffffff', 'text-halo-width': 1.4 },
    },
  ]
  if (id !== 'fiord') {
    layers.push({
      id: 'poi-label',
      type: 'symbol',
      source: 'empty',
      'source-layer': 'poi',
      layout: { 'text-size': ['interpolate', ['linear'], ['zoom'], 10, 10, 16, 20] },
      paint: { 'text-color': '#666666', 'text-halo-width': 1 },
    })
  }
  layers.push(
    {
      id: 'street-label',
      type: 'symbol',
      source: 'empty',
      'source-layer': 'transportation_name',
      layout: { 'text-size': 12 },
      paint: { 'text-color': LABEL_COLORS[id] || '#666666' },
    },
    {
      id: 'street-shield',
      type: 'symbol',
      source: 'empty',
      'source-layer': 'transportation_name',
      layout: { 'text-size': 12 },
      paint: { 'icon-opacity': 1 },
    },
    {
      id: 'water-label',
      type: 'symbol',
      source: 'empty',
      'source-layer': 'water_name',
      layout: { 'text-size': 12 },
      paint: { 'text-color': 'hsl(210, 50%, 40%)', 'text-halo-width': 1 },
    },
    {
      id: 'building',
      type: 'fill',
      source: 'vector',
      'source-layer': 'building',
      minzoom: 13,
      paint: { 'fill-color': '#ddd' },
    },
  )
  return {
    version: 8,
    name: id,
    sources: {
      empty: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
      vector: { type: 'vector', tiles: ['https://tiles.openfreemap.org/data/{z}/{x}/{y}.pbf'] },
    },
    layers,
  }
}

export const STYLE = styleFor('liberty')

export async function routeStyle(page) {
  // Playwright matches route handlers in reverse registration order, so the
  // general handler must be registered first to let the /data/** abort win.
  await page.route('**/tiles.openfreemap.org/**', (r) => {
    const id = new URL(r.request().url()).pathname.split('/').pop()
    const body = STYLE_COLORS[id] ? styleFor(id) : STYLE
    return r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(body) })
  })
  await page.route('**/tiles.openfreemap.org/data/**', (r) => r.abort('failed'))
}

function serveHtml(body) {
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

export function startPage() {
  return serveHtml(page())
}

// Serves colors.jsx's toHex/seedColors directly, bypassing MapLibre - a style
// carrying a color toHex can't reduce to rgb() fails MapLibre's own style
// validation, so those code paths can't be observed through a loaded map.
let domHarnessBody = null
async function domHarnessPage() {
  if (domHarnessBody === null) {
    const out = await build({
      entryPoints: [path.join(HERE, 'dom-harness.jsx')],
      absWorkingDir: path.join(HERE, '..'),
      bundle: true,
      write: false,
      format: 'iife',
      target: 'es2022',
      jsx: 'automatic',
      jsxImportSource: 'preact',
    })
    domHarnessBody = '<!doctype html><body><script>' + out.outputFiles[0].text + '</script>'
  }
  return domHarnessBody
}

export async function startDomHarness() {
  return serveHtml(await domHarnessPage())
}
