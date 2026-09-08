import http from 'node:http'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const html = readFileSync(join(HERE, 'dist', 'index.html'))

const server = http.createServer((req, res) => {
  if (req.url.split('?')[0] !== '/') {
    res.writeHead(404).end('not found')
    return
  }
  res.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': 'no-store' })
  res.end(html)
})

const PORT = Number(process.env.MAPPER_PORT) || 8737

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    process.stderr.write(`serve.js: port ${PORT} is already in use\n`)
    process.exit(1)
  }
  throw err
})

server.listen(PORT, '127.0.0.1', () => process.stdout.write(server.address().port + '\n'))

// The launcher's trap covers the ordinary exit. This covers a launcher that was
// killed outright, leaving the server reparented and otherwise immortal.
const parent = process.ppid
setInterval(() => { if (process.ppid !== parent) process.exit(0) }, 1000).unref()
