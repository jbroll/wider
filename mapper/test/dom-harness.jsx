// Exposes colors.jsx's DOM-dependent functions for a Playwright test to call
// directly, without going through MapLibre's own style validation - a color
// toHex can't parse is also one MapLibre refuses to load, so the null-return
// paths can't be reached through a running map.
import { toHex, seedColors } from '../src/colors.jsx'

window.__colorsDom = { toHex, seedColors }
