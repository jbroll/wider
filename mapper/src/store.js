// window.localStorage can throw on access (e.g. a browser policy blocking
// site data). view.js and places.js stay pure and just take a store, so the
// fallback lives here instead of in either of them.
export const store = {
  getItem(key) {
    try {
      return window.localStorage.getItem(key)
    } catch {
      return null
    }
  },
  setItem(key, value) {
    try {
      window.localStorage.setItem(key, value)
    } catch {
      // ignored: no persistence this session
    }
  },
}

