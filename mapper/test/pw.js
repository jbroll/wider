import { test as base, expect } from '@playwright/test'

// Playwright matches the most recently registered route first, so a spec's own
// routeStyle() still wins over the abort below.
function guard(route) {
  const h = new URL(route.request().url()).hostname
  return h === '127.0.0.1' || h === 'localhost' ? route.continue() : route.abort()
}

export const test = base.extend({
  page: async ({ page }, use) => {
    await page.route('**/*', guard)
    await use(page)
  },
})

export { expect }
