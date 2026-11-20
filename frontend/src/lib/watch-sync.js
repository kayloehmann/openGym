// Apple Watch companion protocol. The watch is an offline-capable controller; the iPhone store
// remains the canonical workout model and the only gateway to an optional Kraftplan backend.
import { registerPlugin, Capacitor } from '@capacitor/core'
import { effectiveRoutineIds } from './history.js'
import { buildCombinedEntries, deriveSessionName } from './session-merge.js'
import { EXIDX } from './exercises.js'
import { exerciseNameFor, t } from './i18n.js'
import { isoOf, todayISO } from './format.js'
import { readJsonFile, writeJsonFile, MOBILE } from './mobile.js'

const FILE = 'opengym-watch-sync.json'
const Watch = registerPlugin('KraftplanWatch')

const setView = s => ({
  reps: Number(s?.r) || 0,
  weight: Number(s?.w) || 0,
  duration: Number(s?.sec) || 0,
  done: !!s?.done,
})

const entryView = (st, e, index) => {
  const ex = EXIDX[e.id] || (st.customEx || []).find(x => x.id === e.id)
  return {
    id: String(e.id), index,
    name: ex ? exerciseNameFor(ex) : String(e.n || e.id),
    sets: (e.sets || []).map(setView),
  }
}

export function watchContextFor(st, now = new Date()) {
  const today = isoOf(now)
  let workout = st.active
  let state = workout ? 'active' : 'idle'
  const completedToday = (st.workouts || [])
    .filter(w => w?.d === today && w?.id)
    .sort((a, b) => Number(b.end || b.start) - Number(a.end || a.start))
  const lastCompletedSessionId = completedToday[0]?.id ? String(completedToday[0].id) : null
  if (!workout) {
    const ids = effectiveRoutineIds(st, today, today)
    // A fixed weekday plan still resolves to the same routines after it has been logged. Do not
    // immediately offer that workout a second time on the Watch. A queue/rotation that advanced
    // to a genuinely new routine remains visible because its id is not covered yet.
    const completedRoutineIds = new Set(completedToday.flatMap(w => [].concat(w.routineIds || w.routineId || []).map(String)))
    const alreadyCompleted = ids.length > 0 && ids.every(id => completedRoutineIds.has(String(id)))
    const built = alreadyCompleted ? { entries: [], routineIds: [], routines: [] } : buildCombinedEntries(st, ids)
    if (alreadyCompleted) state = 'completed'
    else if (built.entries.length) {
      workout = {
        id: null, d: today, start: null, routineIds: built.routineIds,
        name: deriveSessionName(built.routines.map(r => r.name)) || t('Workout'),
        entries: built.entries,
      }
      state = 'planned'
    }
  }
  const weekStart = new Date(now)
  const startOffset = (weekStart.getDay() - Number(st.weekStart || 1) + 7) % 7
  weekStart.setDate(weekStart.getDate() - startOffset)
  weekStart.setHours(0, 0, 0, 0)
  const doneThisWeek = (st.workouts || []).filter(w => Number(w.end || w.start) >= weekStart.getTime()).length
  const plannedDays = Object.values(st.week || {}).filter(v => [].concat(v || []).filter(Boolean).length).length
  const recentWorkouts = (st.workouts || [])
    .filter(w => w?.id && Array.isArray(w.entries))
    .sort((a, b) => Number(b.end || b.start || 0) - Number(a.end || a.start || 0))
    .slice(0, 5)
    .map(w => ({
      id: String(w.id),
      date: w.d || today,
      ...(w.start ? { start: Number(w.start) } : {}),
      ...(w.end ? { end: Number(w.end) } : {}),
      name: w.name || t('Workout'),
      exercises: w.entries.map((e, i) => entryView(st, e, i)),
    }))
  return {
    version: 2,
    generatedAt: Date.now(),
    state,
    ...(lastCompletedSessionId ? { lastCompletedSessionId } : {}),
    unit: st.unit === 'lb' ? 'lb' : 'kg',
    restSeconds: Math.max(5, Number(st.restSec) || 90),
    week: { completed: doneThisWeek, target: Math.max(plannedDays, doneThisWeek) },
    recentWorkouts,
    workout: workout ? {
      // WCSession application contexts are property lists. `null` becomes NSNull in the
      // Capacitor bridge, which makes updateApplicationContext reject the *whole* payload.
      // Planned workouts deliberately have neither an id nor a start time, so omit those
      // optional keys instead of publishing null values.
      ...(workout.id ? { id: String(workout.id) } : {}),
      date: workout.d || today,
      ...(workout.start ? { start: workout.start } : {}),
      name: workout.name || t('Workout'),
      routineIds: [].concat(workout.routineIds || []).map(String),
      currentExercise: Number(workout.cur) || 0,
      exercises: (workout.entries || []).map((e, i) => entryView(st, e, i)),
    } : null,
  }
}

export function applyWatchStart(st, event) {
  if (st.active?.id === event.sessionId) return 'duplicate'
  if (st.active) return 'conflict'
  const built = buildCombinedEntries(st, event.routineIds || [])
  if (!built.entries.length) return 'missing-plan'
  st.active = {
    id: event.sessionId,
    d: event.date || todayISO(),
    start: Number(event.start) || Date.now(),
    routineIds: built.routineIds,
    name: event.name || deriveSessionName(built.routines.map(r => r.name)) || t('Workout'),
    bw: null, cur: 0, entries: built.entries,
    workoutView: st.workoutView || 'cards',
    watchSession: true,
  }
  return 'applied'
}

export function applyWatchSet(st, event) {
  if (!st.active || st.active.id !== event.sessionId) return 'missing-session'
  const e = st.active.entries?.[Number(event.exerciseIndex)]
  const s = e?.sets?.[Number(event.setIndex)]
  if (!s) return 'missing-set'
  if (Number.isFinite(Number(event.reps))) s.r = Math.max(0, Number(event.reps))
  if (Number.isFinite(Number(event.weight))) s.w = Math.max(0, Number(event.weight))
  if (typeof event.done === 'boolean') {
    s.done = event.done
    if (s.done) s.at = Number(event.at) || Date.now()
    else delete s.at
  }
  st.active.cur = Number(event.exerciseIndex) || 0
  return 'applied'
}

export async function processWatchEvent(event, deps) {
  if (!event?.operationId || !event?.type || !event?.sessionId) return 'invalid'
  if (deps.processed.has(event.operationId)) return 'duplicate'
  let result = 'unsupported'
  if (event.type === 'start') deps.update(s => { result = applyWatchStart(s, event) })
  else if (event.type === 'set') deps.update(s => { result = applyWatchSet(s, event) })
  else if (event.type === 'finish') {
    if (deps.getState().S.active?.id !== event.sessionId) result = 'missing-session'
    else {
      await deps.finish(event)
      await deps.push()
      result = deps.getState().user && deps.getState().sync?.status !== 'ok' ? 'saved' : 'synced'
    }
  }
  if (!['conflict', 'missing-plan', 'missing-session', 'missing-set', 'invalid'].includes(result)) {
    deps.processed.add(event.operationId)
  }
  return result
}

export async function startWatchSync(store) {
  if (!MOBILE || Capacitor.getPlatform() !== 'ios') return () => {}
  const saved = await readJsonFile(FILE) || {}
  const processed = new Set(saved.processed || [])
  let running = Promise.resolve()
  const persist = () => writeJsonFile(FILE, { processed: [...processed].slice(-1000) })
  const publish = () => Watch.publish({ context: watchContextFor(store.getState().S) }).catch(() => {})
  const handle = event => {
    running = running.then(async () => {
      const result = await processWatchEvent(event, {
        processed,
        getState: store.getState,
        update: (fn) => store.getState().update(fn),
        finish: async ev => {
          const { doFinishWorkout } = await import('../sheets.jsx')
          doFinishWorkout({ quiet: true, source: 'watch', end: ev.end })
        },
        push: () => store.getState().pushState(),
      })
      await persist()
      await Watch.ack({ operationId: event.operationId, sessionId: event.sessionId, status: result }).catch(() => {})
      if (!['conflict', 'missing-plan', 'missing-session', 'missing-set', 'invalid'].includes(result)) {
        await Watch.clear({ operationIds: [event.operationId] }).catch(() => {})
      }
      publish()
    }).catch(() => {})
  }
  const listener = await Watch.addListener('watchEvent', ({ event }) => handle(event))
  const pending = await Watch.pending().catch(() => ({ events: [] }))
  ;(pending.events || []).sort((a, b) => (a.sequence || 0) - (b.sequence || 0)).forEach(handle)
  const unsubscribe = store.subscribe(publish)
  document.addEventListener('visibilitychange', publish)
  publish()
  return () => { listener.remove(); unsubscribe(); document.removeEventListener('visibilitychange', publish) }
}
