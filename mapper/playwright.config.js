import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './test',
  testMatch: ['map.spec.js', 'route.spec.js'],
  timeout: 30000,
  expect: { timeout: 10000 },
  fullyParallel: false,
  workers: 1,
  use: {
    headless: true,
    // MapLibre needs a GL context, and headless Chromium has no GPU.
    launchOptions: { args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] },
  },
})
