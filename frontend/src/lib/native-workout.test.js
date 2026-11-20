import { describe, expect, it, vi } from 'vitest'
import { processNativeWorkoutEvent } from './native-workout.js'

const activeState = () => ({
  S: { active: { id: 'session-1', cur: 0, entries: [{ id: 'squat', sets: [{ w: 80, r: 5, done: false }] }] } },
  user: null,
  sync: { status: 'ok' },
})

describe('native workout events', () => {
  it('applies a set to the canonical phone workout', async () => {
    const state = activeState()
    const deps = {
      processed: new Set(), getState: () => state,
      update: fn => fn(state.S), finish: vi.fn(), push: vi.fn(),
    }
    const event = { type: 'set', operationId: 'op-1', sessionId: 'session-1', exerciseIndex: 0, setIndex: 0, done: true, at: 42 }
    expect(await processNativeWorkoutEvent(event, deps)).toBe('applied')
    expect(state.S.active.entries[0].sets[0]).toMatchObject({ done: true, at: 42 })
    expect(await processNativeWorkoutEvent(event, deps)).toBe('duplicate')
  })

  it('finishes and pushes the matching session', async () => {
    const state = activeState()
    const finish = vi.fn(async () => { state.S.active = null })
    const push = vi.fn(async () => {})
    const result = await processNativeWorkoutEvent(
      { type: 'finish', operationId: 'op-2', sessionId: 'session-1', end: 99 },
      { processed: new Set(), getState: () => state, update: vi.fn(), finish, push },
    )
    expect(result).toBe('synced')
    expect(finish).toHaveBeenCalledOnce()
    expect(push).toHaveBeenCalledOnce()
  })

  it('refuses events for another workout', async () => {
    const state = activeState()
    const deps = { processed: new Set(), getState: () => state, update: fn => fn(state.S), finish: vi.fn(), push: vi.fn() }
    expect(await processNativeWorkoutEvent(
      { type: 'set', operationId: 'op-3', sessionId: 'other', exerciseIndex: 0, setIndex: 0, done: true }, deps,
    )).toBe('missing-session')
    expect(state.S.active.entries[0].sets[0].done).toBe(false)
  })
})
