// Native iPhone workout controller. The React store remains the single source of truth; SwiftUI
// only renders a compact projection and sends idempotent user actions back into that store.
import { Capacitor, registerPlugin } from '@capacitor/core'
import { MOBILE } from './mobile.js'
import { applyWatchSet, watchContextFor } from './watch-sync.js'

const NativeWorkout = registerPlugin('NativeWorkout')
const processed = new Set()
let presented = false

export const nativeWorkoutAvailable = () => MOBILE && Capacitor.getPlatform() === 'ios'

export async function openNativeWorkout(state) {
  if (!nativeWorkoutAvailable() || !state?.active) return false
  await NativeWorkout.present({ context: watchContextFor(state) })
  presented = true
  return true
}

export async function processNativeWorkoutEvent(event, deps) {
  if (!event?.operationId || !event?.type || !event?.sessionId) return 'invalid'
  if (deps.processed.has(event.operationId)) return 'duplicate'
  let result = 'unsupported'
  if (event.type === 'set') deps.update(s => { result = applyWatchSet(s, event) })
  else if (event.type === 'finish') {
    if (deps.getState().S.active?.id !== event.sessionId) result = 'missing-session'
    else {
      await deps.finish(event)
      await deps.push()
      result = deps.getState().user && deps.getState().sync?.status !== 'ok' ? 'saved' : 'synced'
    }
  }
  if (!['missing-session', 'missing-set', 'invalid'].includes(result)) deps.processed.add(event.operationId)
  return result
}

export async function startNativeWorkoutSync(store) {
  if (!nativeWorkoutAvailable()) return () => {}
  let running = Promise.resolve()
  const publish = () => {
    if (!presented) return
    NativeWorkout.update({ context: watchContextFor(store.getState().S) }).catch(() => {})
  }
  const listener = await NativeWorkout.addListener('nativeWorkoutEvent', ({ event }) => {
    if (event?.type === 'dismiss') { presented = false; return }
    running = running.then(async () => {
      await processNativeWorkoutEvent(event, {
        processed,
        getState: store.getState,
        update: fn => store.getState().update(fn),
        finish: async ev => {
          const { doFinishWorkout } = await import('../sheets.jsx')
          doFinishWorkout({ quiet: true, source: 'native', end: ev.end })
        },
        push: () => store.getState().pushState(),
      })
      publish()
    }).catch(() => {})
  })
  const unsubscribe = store.subscribe(publish)
  return () => { listener.remove(); unsubscribe() }
}
