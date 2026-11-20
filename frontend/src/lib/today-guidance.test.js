import { describe, expect, it } from 'vitest'
import { sessionPreview, todayGuidance } from './today-guidance.js'

const S = { workouts: [], unit: 'kg' }
const routine = { id: 'r', name: 'Push', ex: [{ id: '0025', sets: 3 }, { id: '0047', sets: 4 }] }

describe('Today guidance', () => {
  it('summarises the planned session', () => {
    expect(sessionPreview([routine])).toEqual({ exercises: 2, sets: 7 })
  })

  it('starts ready and treats one weak recovery signal as controlled', () => {
    expect(todayGuidance({ S, routines: [routine] }).level).toBe('ready')
    expect(todayGuidance({ S, routines: [routine], health: {
      signals: { sleep: { value: 6, baseline: 8 } }, coverage: ['sleep'],
    } }).level).toBe('controlled')
  })

  it('lets the explicit check-in outweigh passive sensor data', () => {
    const healthy = { signals: { sleep: { value: 8, baseline: 8 }, hrv: { value: 60, baseline: 55 } }, coverage: ['sleep', 'hrv'] }
    expect(todayGuidance({ S, routines: [routine], health: healthy, checkIn: { energy: 2, soreness: 4, pain: false } }).level).toBe('reduce')
    expect(todayGuidance({ S, routines: [routine], health: healthy, checkIn: { energy: 5, soreness: 1, pain: true } }).level).toBe('rest')
  })
})
