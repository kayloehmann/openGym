// @vitest-environment happy-dom
import React, { act } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createRoot } from 'react-dom/client'
import { useStore } from './store/useStore.js'
import { useUI } from './store/useUI.js'
import { todayISO } from './lib/format.js'
import { calendarSheet } from './sheets.jsx'

const mounted = []

function renderTop() {
  const sheet = useUI.getState().sheets.at(-1)
  const host = document.createElement('div')
  document.body.appendChild(host)
  const root = createRoot(host)
  mounted.push(root)
  act(() => root.render(sheet.render(() => useUI.getState().closeSheet(sheet.id))))
  return host
}

describe('Calendar canonical workout days', () => {
  let original

  beforeEach(() => {
    globalThis.IS_REACT_ACT_ENVIRONMENT = true
    original = useStore.getState().S
    useUI.setState({ sheets: [] })
    document.body.innerHTML = ''
  })

  afterEach(() => {
    act(() => { mounted.splice(0).forEach(root => root.unmount()) })
    useStore.setState({ S: original })
    vi.useRealTimers()
  })

  it('shows future dated sessions as planned while current and past overrides stay rescheduled', () => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date('2026-09-16T12:00:00'))
    useStore.setState({ S: {
      ...original,
      routines: [{ id: 'r1', name: 'Push', ex: [] }], week: {}, workouts: [],
      dayPlan: { '2026-09-15': 'r1', '2026-09-16': 'r1', '2026-09-18': 'r1' },
    } })

    calendarSheet('2026-09-16')
    const host = renderTop()
    const dotFor = day => [...host.querySelectorAll('button.cal-d')]
      .find(button => button.querySelector('span')?.textContent === String(day))?.querySelector('i')
    expect(dotFor(15)?.className).toBe('ovr')
    expect(dotFor(16)?.className).toBe('ovr')
    expect(dotFor(18)?.className).toBe('plan')
  })

  it('keeps multiple legacy sessions on the heatmap fallback day clickable in Calendar', () => {
    const day = todayISO()
    const start = new Date(day + 'T09:00:00').getTime()
    useStore.setState({ S: {
      ...original,
      workouts: [
        { id: 'legacy-a', d: '', start, end: start + 15 * 60000, name: 'Legacy A', vol: 100, entries: [] },
        { id: 'legacy-b', d: 'not-a-day', start: start + 30 * 60000, end: start + 45 * 60000, name: 'Legacy B', vol: 200, entries: [] },
      ],
    } })

    calendarSheet(day)
    const host = renderTop()
    expect(host.textContent).toContain('2 workouts')
    const trainedDay = host.querySelector('button.cal-d.has')
    expect(trainedDay).toBeTruthy()

    act(() => trainedDay.click())
    const sessions = renderTop()
    expect(sessions.textContent).toContain('Legacy A')
    expect(sessions.textContent).toContain('Legacy B')
  })
})
