// Exposes colors.jsx's DOM-dependent functions for a Playwright test to call
// directly, without going through MapLibre's own style validation - a style
// carrying a color toHex can't parse also fails that validation, so the
// null-return paths can't be observed through a loaded map.
import { toHex, seedColors, forSwatch } from '../src/colors.jsx'

window.__colorsDom = { toHex, seedColors, forSwatch }
