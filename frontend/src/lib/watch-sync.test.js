import { describe, expect, it, vi } from 'vitest'
import { applyWatchSet, applyWatchStart, processWatchEvent, watchContextFor } from './watch-sync.js'

const base = () => ({
  unit: 'kg', restSec: 90, weekStart: 1, week: { 1: ['r1'], 4: ['r1'] }, dayPlan: {}, workouts: [], exWeights: {}, customEx: [],
  routines: [{ id: 'r1', name: 'Push', ex: [{ id: '0025', sets: 2, reps: 8, weight: 60 }] }],
})

describe('Apple Watch workout protocol', () => {
  it('publishes a planned workout as a property-list-safe context', () => {
    const context = watchContextFor(base(), new Date(2026, 9, 26, 12))
    expect(context.state).toBe('planned')
    expect(context.workout).not.toHaveProperty('id')
    expect(context.workout).not.toHaveProperty('start')
    expect(JSON.stringify(context)).not.toContain(':null')
  })

  it('publishes an active workout and weekly progress without exposing the whole store', () => {
    const st = base()
    st.active = { id: 'watch-1', d: '2026-10-27', start: 12, name: 'Push', routineIds: ['r1'], cur: 0,
      entries: [{ id: '0025', sets: [{ r: 8, w: 60, done: true }, { r: 8, w: 60, done: false }] }] }
    const context = watchContextFor(st, new Date(2026, 9, 27, 12))
    expect(context.state).toBe('active')
    expect(context.workout.exercises[0].sets.map(s => s.done)).toEqual([true, false])
    expect(context).not.toHaveProperty('workouts')
  })

  it('publishes only the five newest completed workouts for Watch history', () => {
    const st = base()
    st.workouts = Array.from({ length: 7 }, (_, i) => ({
      id: `history-${i}`,
      d: `2026-10-${String(i + 1).padStart(2, '0')}`,
      start: 1000 + i * 100,
      end: 1050 + i * 100,
      name: `Training ${i}`,
      entries: [{ id: '0025', sets: [{ r: 8 + i, w: 60, done: true }] }],
    }))
    const context = watchContextFor(st, new Date(2026, 9, 20, 12))
    expect(context.version).toBe(2)
    expect(context.recentWorkouts).toHaveLength(5)
    expect(context.recentWorkouts.map(w => w.id)).toEqual(['history-6', 'history-5', 'history-4', 'history-3', 'history-2'])
    expect(context.recentWorkouts[0]).toMatchObject({ name: 'Training 6', start: 1600, end: 1650 })
    expect(context.recentWorkouts[0].exercises[0].sets[0]).toMatchObject({ reps: 14, weight: 60, done: true })
  })

  it('publishes a finished phone session as completed instead of offering the same plan again', () => {
    const st = base()
    st.workouts = [{ id: 'phone-1', d: '2026-10-26', start: 100, end: 200, routineIds: ['r1'], entries: [] }]
    const context = watchContextFor(st, new Date(2026, 9, 26, 12))
    expect(context).toMatchObject({ state: 'completed', lastCompletedSessionId: 'phone-1', workout: null })
  })

  it('still publishes a newly advanced queue session after today\'s previous session completed', () => {
    const st = base()
    st.routines.push({ id: 'r2', name: 'Pull', ex: [{ id: '0025', sets: 2, reps: 8, weight: 50 }] })
    st.week = {}
    st.queue = { ids: ['r1', 'r2'], since: 0, startsOn: '2026-10-27' }
    st.workouts = [{ id: 'phone-1', d: '2026-10-27', start: 100, end: 200, routineIds: ['r1'], entries: [] }]
    const context = watchContextFor(st, new Date(2026, 9, 27, 12))
    expect(context.state).toBe('planned')
    expect(context.workout.routineIds).toEqual(['r2'])
  })

  it('starts once and applies a retransmitted set event idempotently', () => {
    const st = base()
    const start = { sessionId: 'watch-1', routineIds: ['r1'], start: 100, date: '2026-10-27' }
    expect(applyWatchStart(st, start)).toBe('applied')
    expect(applyWatchStart(st, start)).toBe('duplicate')
    const event = { sessionId: 'watch-1', exerciseIndex: 0, setIndex: 0, done: true, at: 200 }
    expect(applyWatchSet(st, event)).toBe('applied')
    expect(applyWatchSet(st, event)).toBe('applied')
    expect(st.active.entries[0].sets[0]).toMatchObject({ done: true, at: 200 })
  })

  it('updates Watch weight and reps without changing completion', () => {
    const st = base()
    st.active = { id: 'watch-1', cur: 0, entries: [{ id: '0025', sets: [{ r: 8, w: 60, done: true, at: 100 }] }] }
    const event = { sessionId: 'watch-1', exerciseIndex: 0, setIndex: 0, reps: 10, weight: 62.5 }
    expect(applyWatchSet(st, event)).toBe('applied')
    expect(st.active.entries[0].sets[0]).toEqual({ r: 10, w: 62.5, done: true, at: 100 })
  })

  it('finishes through the canonical phone path, pushes, and ignores duplicate operation ids', async () => {
    const state = { S: { active: { id: 'watch-1' } }, user: { id: 'u' }, sync: { status: 'ok' } }
    const deps = { processed: new Set(), getState: () => state, update: vi.fn(), finish: vi.fn(async () => {}), push: vi.fn(async () => {}) }
    const event = { operationId: 'op-1', sessionId: 'watch-1', sequence: 3, type: 'finish', end: 300 }
    expect(await processWatchEvent(event, deps)).toBe('synced')
    expect(await processWatchEvent(event, deps)).toBe('duplicate')
    expect(deps.finish).toHaveBeenCalledTimes(1)
    expect(deps.push).toHaveBeenCalledTimes(1)
  })
})
