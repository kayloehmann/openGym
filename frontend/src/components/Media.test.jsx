// @vitest-environment happy-dom
import React, { act } from 'react'
import { createRoot } from 'react-dom/client'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import Media from './Media.jsx'

globalThis.IS_REACT_ACT_ENVIRONMENT = true

const mocks = vi.hoisted(() => {
  const state = { S: { gifSize: 'full' } }
  state.snapshot = () => ({
    S: state.S,
    update: mut => {
      const next = structuredClone(state.S)
      mut(next)
      state.S = next
    },
  })
  return state
})
vi.mock('../store/useStore.js', () => {
  const useStore = selector => selector(mocks.snapshot())
  useStore.getState = mocks.snapshot
  return { useStore }
})

const EX = { id: 'bench', n: 'bench press', gif: 'bench.gif', img: 'bench.jpg' }

let host, root
beforeEach(() => {
  mocks.S = { gifSize: 'full' }
  host = document.createElement('div')
  document.body.appendChild(host)
  root = createRoot(host)
})
afterEach(() => {
  act(() => root.unmount())
  host.remove()
})

const mount = props => act(() => root.render(<Media ex={EX} {...props} />))

describe('Media gifSize', () => {
  it('renders the full animation by default and toggles to mini in the workout', () => {
    mount({ minimizable: true })
    expect(host.querySelector('.exmedia img')).toBeTruthy()
    expect(host.querySelector('.exmedia.mini')).toBeFalsy()
    act(() => { host.querySelector('.giftoggle').click() })
    expect(mocks.S.gifSize).toBe('mini')
    mount({ minimizable: true })
    expect(host.querySelector('.exmedia.mini')).toBeTruthy()
  })

  it("renders nothing at all in the workout when gifSize is 'off'", () => {
    mocks.S = { gifSize: 'off' }
    mount({ minimizable: true })
    expect(host.querySelector('.exmedia')).toBeFalsy()
    expect(host.querySelector('img')).toBeFalsy()
    expect(host.innerHTML).toBe('')
  })

  it("'off' only applies to the workout — the detail sheet (not minimizable) still shows media", () => {
    mocks.S = { gifSize: 'off' }
    mount({})
    expect(host.querySelector('.exmedia img')).toBeTruthy()
  })

  it('treats a legacy/unknown value as full', () => {
    mocks.S = { gifSize: 'huge' }
    mount({ minimizable: true })
    expect(host.querySelector('.exmedia img')).toBeTruthy()
    expect(host.querySelector('.exmedia.mini')).toBeFalsy()
  })
})

describe('Media with multiple exercise videos', () => {
  it('hides saved videos by default without hiding the built-in animation', () => {
    mocks.S.exVideos = { bench: [{ url: 'https://youtu.be/dQw4w9WgXcQ' }] }
    mount({ minimizable: true })
    expect(host.querySelector('.exmedia img')).toBeTruthy()
    expect(host.querySelector('.exmedia-carousel')).toBeFalsy()
    expect(host.querySelector('.exmedia-video-play')).toBeFalsy()
    expect(host.querySelector('iframe')).toBeFalsy()
  })

  it('hides videos on custom exercises without a GIF until explicitly enabled', () => {
    mocks.S.exVideos = { custom: [{ url: 'https://youtu.be/dQw4w9WgXcQ' }] }
    mount({ ex: { id: 'custom', n: 'Custom exercise' } })
    expect(host.innerHTML).toBe('')
    mocks.S.showExerciseVideos = true
    mount({ ex: { id: 'custom', n: 'Custom exercise' } })
    expect(host.querySelector('.exmedia-video-play')).toBeTruthy()
  })

  it('shows opted-in videos even when workout animations are hidden', () => {
    mocks.S.gifSize = 'off'
    mocks.S.showExerciseVideos = true
    mocks.S.exVideos = { bench: [{ url: 'https://youtu.be/dQw4w9WgXcQ' }] }
    mount({ minimizable: true })
    expect(host.querySelector('.exmedia-video-play')).toBeTruthy()
    expect(host.querySelector('.exmedia-carousel-dots button')).toBeTruthy()
    expect(host.querySelectorAll('.exmedia-carousel-dots button')).toHaveLength(1)
    expect(host.querySelector('.exmedia img:not(.exmedia-video-poster)')).toBeFalsy()
  })

  it('switches between multiple videos and the built-in animation', () => {
    mocks.S.showExerciseVideos = true
    mocks.S.exVideos = { bench: [
      { url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', title: 'Form' },
      { url: 'https://youtu.be/M7lc1UVf-VE', title: 'Variation' },
    ] }
    mount({})
    expect(host.querySelectorAll('.exmedia-carousel-dots button')).toHaveLength(3)
    expect(host.querySelector('iframe')).toBeFalsy()
    expect(host.querySelector('.exmedia-video-play')).toBeTruthy()
    expect(host.querySelector('.exmedia-video-poster').getAttribute('src')).toBe('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg')
    expect(host.querySelector('.exmedia-carousel-title').textContent).toContain('Form')
    act(() => host.querySelector('.exmedia-carousel-arrow:last-child').click())
    expect(host.querySelector('iframe')).toBeFalsy()
    expect(host.querySelector('.exmedia-carousel-title').textContent).toContain('Variation')
    expect(host.querySelector('.exmedia-video-poster').getAttribute('src')).toBe('https://i.ytimg.com/vi/M7lc1UVf-VE/hqdefault.jpg')
    act(() => host.querySelector('.exmedia-carousel-arrow:last-child').click())
    expect(host.querySelector('iframe')).toBeFalsy()
    expect(host.querySelector('.exmedia img')).toBeTruthy()
    expect(host.querySelector('.exmedia-carousel-title').textContent).toContain('3 / 3')
    act(() => host.querySelector('.exmedia-carousel-arrow:first-child').click())
    expect(host.querySelector('.exmedia-video-play')).toBeTruthy()
    expect(host.querySelector('.exmedia-carousel-title').textContent).toContain('2 / 3')
    expect(host.querySelector('.exmedia-video-poster').getAttribute('src')).toBe('https://i.ytimg.com/vi/M7lc1UVf-VE/hqdefault.jpg')
  })

  it('shows videos for custom exercises without a built-in GIF', () => {
    mocks.S.showExerciseVideos = true
    mocks.S.exVideos = { custom: [{ url: 'https://youtu.be/dQw4w9WgXcQ' }] }
    mount({ ex: { id: 'custom', n: 'Custom exercise' } })
    expect(host.querySelector('.exmedia-video-play')).toBeTruthy()
    expect(host.querySelector('.exmedia-video-poster')).toBeTruthy()
  })

  it('moves to the next video when the preview is swiped left', () => {
    mocks.S.showExerciseVideos = true
    mocks.S.exVideos = { custom: [
      { url: 'https://youtu.be/dQw4w9WgXcQ' },
      { url: 'https://youtu.be/M7lc1UVf-VE' },
    ] }
    mount({ ex: { id: 'custom', n: 'Custom exercise' } })
    const stage = host.querySelector('.exmedia-stage')
    const start = new Event('touchstart', { bubbles: true })
    Object.defineProperty(start, 'touches', { value: [{ clientX:220 }] })
    const end = new Event('touchend', { bubbles: true })
    Object.defineProperty(end, 'changedTouches', { value: [{ clientX:100 }] })
    act(() => { stage.dispatchEvent(start); stage.dispatchEvent(end) })
    expect(host.querySelector('.exmedia-carousel-title').textContent).toContain('2 / 2')
  })

  it('unmounts a playing video when the setting is switched off', () => {
    mocks.S.showExerciseVideos = true
    mocks.S.exVideos = { bench: [{ url: 'https://youtu.be/dQw4w9WgXcQ' }] }
    mount({ minimizable: true })
    act(() => host.querySelector('.exmedia-video-play').click())
    expect(host.querySelector('iframe')).toBeTruthy()
    mocks.S.showExerciseVideos = false
    mount({ minimizable: true })
    expect(host.querySelector('iframe')).toBeFalsy()
    expect(host.querySelector('.exmedia-carousel')).toBeFalsy()
    expect(host.querySelector('.exmedia img')).toBeTruthy()
    mocks.S.showExerciseVideos = true
    mount({ minimizable: true })
    expect(host.querySelector('iframe')).toBeFalsy()
    expect(host.querySelector('.exmedia-video-play')).toBeTruthy()
  })
})
