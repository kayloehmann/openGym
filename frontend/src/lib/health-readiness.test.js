import { beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({
  file: null,
  requestReadPermissions: vi.fn(async () => ({ requested: true })),
  readTodaySnapshot: vi.fn(async () => ({ generatedAt: 1, signals: { sleep: { value: 7.5, baseline: 7.7 } }, coverage: ['sleep'] })),
}))

vi.mock('./mobile.js', () => ({
  MOBILE: true,
  readJsonFile: vi.fn(async () => mocks.file),
  writeJsonFile: vi.fn(async (_name, value) => { mocks.file = value }),
}))
vi.mock('@capacitor/core', () => ({
  Capacitor: { getPlatform: () => 'ios' },
  registerPlugin: () => ({ requestReadPermissions: mocks.requestReadPermissions, readTodaySnapshot: mocks.readTodaySnapshot }),
}))

import { disableHealthReadiness, enableHealthReadiness, loadHealthReadiness, todayHealthSnapshot, _resetHealthReadinessForTests } from './health-readiness.js'

beforeEach(() => {
  mocks.file = null
  mocks.requestReadPermissions.mockClear()
  mocks.readTodaySnapshot.mockClear()
  _resetHealthReadinessForTests()
})

describe('Apple Health Today inputs', () => {
  it('starts off and does not query HealthKit', async () => {
    expect(await loadHealthReadiness()).toMatchObject({ on: false, snapshot: null })
    expect(await todayHealthSnapshot()).toBeNull()
    expect(mocks.readTodaySnapshot).not.toHaveBeenCalled()
  })

  it('requests read access separately and stores only the derived snapshot locally', async () => {
    const result = await enableHealthReadiness()
    expect(result.ok).toBe(true)
    expect(mocks.requestReadPermissions).toHaveBeenCalledTimes(1)
    expect(mocks.file.on).toBe(true)
    expect(mocks.file.snapshot.coverage).toEqual(['sleep'])
  })

  it('disabling removes the cached health snapshot', async () => {
    await enableHealthReadiness()
    await disableHealthReadiness()
    expect(mocks.file).toMatchObject({ on: false, snapshot: null })
  })
})
