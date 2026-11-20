import { EXIDX } from './exercises.js'
import { musclesOf, MUSCLE_NAME } from './muscles.js'
import { fatigueOf } from './recovery.js'

const ratio = signal => signal?.baseline > 0 ? signal.value / signal.baseline : 1
const named = slug => MUSCLE_NAME[slug] || slug

export function sessionPreview(routines = []) {
  const entries = routines.flatMap(routine => routine.ex || [])
  const sets = entries.reduce((sum, entry) => sum + Math.max(0, Number(entry.sets) || 0), 0)
  return { exercises: entries.length, sets }
}

export function todayGuidance({ S, routines = [], health = null, checkIn = null, week = {} }) {
  const signals = health?.signals || {}
  const targetMuscles = new Set()
  for (const entry of routines.flatMap(routine => routine.ex || [])) {
    for (const muscle of Object.keys(musclesOf(EXIDX[entry.id] || entry))) targetMuscles.add(muscle)
  }
  const fatigue = fatigueOf(S?.workouts || [], Date.now(), { unit: S?.unit })
  const targetFatigue = [...targetMuscles].sort((a, b) => (fatigue[b] || 0) - (fatigue[a] || 0))
  const tired = targetFatigue.filter(muscle => (fatigue[muscle] || 0) > 0.5)
  const recovering = targetFatigue.filter(muscle => (fatigue[muscle] || 0) > 0.25)

  const warnings = []
  if (ratio(signals.sleep) < 0.88) warnings.push('sleep')
  if (ratio(signals.hrv) < 0.85) warnings.push('hrv')
  if (ratio(signals.restingHeartRate) > 1.08) warnings.push('restingHeartRate')
  if (ratio(signals.respiratoryRate) > 1.08) warnings.push('respiratoryRate')
  if (tired.length) warnings.push('muscles')

  let level = routines.length ? 'ready' : 'off'
  if (checkIn?.pain) level = 'rest'
  else if ((checkIn?.energy && checkIn.energy <= 2) || (checkIn?.soreness && checkIn.soreness >= 4) || warnings.length >= 3) level = 'reduce'
  else if (warnings.length >= 1 || recovering.length || (checkIn?.energy && checkIn.energy <= 3)) level = 'controlled'

  const top = []
  if (targetMuscles.size) top.push({
    key: 'recovery', tone: tired.length ? 'warn' : recovering.length ? 'care' : 'good',
    detail: tired.length
      ? `${tired.slice(0, 2).map(named).join(', ')} need more recovery`
      : recovering.length ? `${recovering.slice(0, 2).map(named).join(', ')} are still recovering` : 'Target muscles look recovered',
  })
  if (signals.sleep) top.push({ key: 'sleep', tone: warnings.includes('sleep') ? 'warn' : 'good', value: signals.sleep.value })
  else if (signals.hrv || signals.restingHeartRate) top.push({ key: 'health', tone: warnings.some(x => x !== 'muscles') ? 'warn' : 'good' })
  top.push({ key: 'week', tone: week.planned && week.done >= week.planned ? 'good' : 'neutral', done: week.done || 0, planned: week.planned || 0 })

  return { level, warnings, signals: top.slice(0, 3), preview: sessionPreview(routines), healthCoverage: health?.coverage?.length || 0 }
}
