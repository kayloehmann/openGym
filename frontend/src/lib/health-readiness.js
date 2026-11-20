// Optional Apple Health inputs for the Today view. This is intentionally separate from
// health-sync.js: reading recovery signals must never silently switch on writing workouts.
// The native plugin returns only a derived snapshot, and this file stays device-local.
import { MOBILE, readJsonFile, writeJsonFile } from './mobile.js'

export const HEALTH_READINESS_FILE = 'opengym-health-readiness.json'
const OFF = { on: false, snapshot: null, at: 0, error: null }

let cached = null
let pluginP = null
const listeners = new Set()
const told = value => listeners.forEach(fn => { try { fn(value) } catch { /* closed view */ } })

const plugin = () => pluginP || (pluginP = (async () => {
  const { Capacitor, registerPlugin } = await import('@capacitor/core')
  if (Capacitor.getPlatform() !== 'ios') return null
  return registerPlugin('AppleHealth')
})().catch(() => null))

export function onHealthReadinessChange(fn) { listeners.add(fn); return () => listeners.delete(fn) }

export async function loadHealthReadiness() {
  if (cached) return cached
  const file = await readJsonFile(HEALTH_READINESS_FILE)
  cached = file && typeof file === 'object' ? { ...OFF, ...file } : { ...OFF }
  return cached
}

async function save(value) {
  cached = value
  await writeJsonFile(HEALTH_READINESS_FILE, value)
  told(value)
  return value
}

export async function healthReadinessAvailable() {
  if (!MOBILE) return false
  return !!(await plugin())
}

export async function refreshHealthReadiness() {
  const current = await loadHealthReadiness()
  if (!current.on) return current
  const native = await plugin()
  if (!native) return save({ ...current, error: 'unsupported' })
  try {
    const snapshot = await native.readTodaySnapshot()
    return save({ ...current, snapshot, at: Date.now(), error: null })
  } catch (error) {
    return save({ ...current, error: error?.code === 'unavailable' ? 'unavailable' : 'failed' })
  }
}

export async function enableHealthReadiness() {
  const native = await plugin()
  if (!native) return { ok: false, reason: 'unsupported' }
  try {
    await native.requestReadPermissions()
    await save({ ...(await loadHealthReadiness()), on: true, error: null })
    const readiness = await refreshHealthReadiness()
    return { ok: !readiness.error, readiness }
  } catch (error) {
    return { ok: false, reason: error?.code === 'unavailable' ? 'unavailable' : 'denied' }
  }
}

export async function disableHealthReadiness() {
  return save({ ...OFF })
}

// Home calls this on mount. The cache makes a disabled or already-loaded feature essentially free.
export async function todayHealthSnapshot() {
  const value = await loadHealthReadiness()
  if (!value.on) return null
  const stale = !value.at || Date.now() - value.at > 15 * 60 * 1000
  return (stale ? await refreshHealthReadiness() : value).snapshot
}

export function _resetHealthReadinessForTests() { cached = null; pluginP = null; listeners.clear() }
