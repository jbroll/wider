import { readFile, writeFile, mkdir } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

import { build } from 'esbuild'

const HERE = dirname(fileURLToPath(import.meta.url))
const SRC = join(HERE, 'src')

async function bundle(entry, loader) {
  const out = await build({
    entryPoints: [join(SRC, entry)],
    absWorkingDir: HERE,
    bundle: true,
    write: false,
    minify: true,
    // Otherwise esbuild keeps MapLibre's /*! ... */ license banner inline, and
    // the built page is meant to carry no such text.
    legalComments: 'none',
    format: 'iife',
    target: 'es2022',
    loader,
    jsx: 'automatic',
    jsxImportSource: 'preact',
  })
  return out.outputFiles[0].text
}

export async function buildHtml() {
  const [template, css, js] = await Promise.all([
    readFile(join(SRC, 'index.html'), 'utf8'),
    bundle('style.css', { '.svg': 'dataurl', '.png': 'dataurl' }),
    bundle('main.jsx', { '.jsx': 'jsx' }),
  ])
  return template.replace('/*CSS*/', () => css.trim()).replace('/*JS*/', () => js.trim())
}

async function main() {
  const html = await buildHtml()
  const dist = join(HERE, 'dist')
  await mkdir(dist, { recursive: true })
  await writeFile(join(dist, 'index.html'), html)
  process.stderr.write(`dist/index.html ${html.length} bytes\n`)
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main()
