// @vitest-environment happy-dom
import React, { act } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createRoot } from 'react-dom/client'
import { useStore } from '../store/useStore.js'
import Home from './Home.jsx'

vi.mock('react-router-dom', () => ({ useNavigate: () => vi.fn() }))
vi.mock('../sheets.jsx', () => ({
  starterPlanSheet: vi.fn(), bwSheet: vi.fn(), goalSheet: vi.fn(), dayOverrideSheet: vi.fn(),
  calendarSheet: vi.fn(), startFlow: vi.fn(), bwDeltaColor: () => '', weighInsSheet: vi.fn(),
}))

describe('Home week strip for dated training', () => {
  let original, host, root

  beforeEach(() => {
    globalThis.IS_REACT_ACT_ENVIRONMENT = true
    vi.stubGlobal('localStorage', {
      getItem: () => null, setItem: () => {}, removeItem: () => {},
    })
    original = useStore.getState().S
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date('2026-09-16T12:00:00'))
    host = document.createElement('div')
    document.body.appendChild(host)
    root = createRoot(host)
  })

  afterEach(() => {
    act(() => root.unmount())
    host.remove()
    useStore.setState({ S: original })
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })

  it('keeps today rescheduled but marks the future fixed-date session planned', () => {
    useStore.setState({ S: {
      ...original,
      routines: [{ id: 'r1', name: 'Push', emoji: null, ex: [] }], week: {}, workouts: [],
      dayPlan: { '2026-09-16': 'r1', '2026-09-18': 'r1' },
    }, user: null })
    act(() => root.render(<Home />))
    const dotFor = day => [...host.querySelectorAll('.wday')]
      .find(element => element.querySelector('.num')?.textContent === String(day))?.querySelector('.dot')
    expect(dotFor(16)?.classList.contains('ovr')).toBe(true)
    expect(dotFor(18)?.classList.contains('plan')).toBe(true)
    expect(dotFor(18)?.classList.contains('ovr')).toBe(false)
  })
})
