import { describe, expect, it } from 'vitest'
import { parseYouTubeVideo, videosFor } from './exercise-videos.js'

describe('YouTube exercise videos', () => {
  it('accepts regular, short and share links and returns a safe embed URL', () => {
    for (const url of [
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=20',
      'https://youtu.be/dQw4w9WgXcQ',
      'https://youtube.com/shorts/dQw4w9WgXcQ',
    ]) {
      expect(parseYouTubeVideo(url)).toEqual({
        id: 'dQw4w9WgXcQ',
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        embed: 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?playsinline=1&rel=0&autoplay=1',
        thumbnail: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      })
    }
  })

  it('rejects non-YouTube, insecure, malformed and credentialed URLs', () => {
    for (const url of [
      'https://youtube.com.evil.test/watch?v=dQw4w9WgXcQ',
      'https://evil.test/embed/dQw4w9WgXcQ',
      'http://youtube.com/watch?v=dQw4w9WgXcQ',
      'https://user:pass@youtube.com/watch?v=dQw4w9WgXcQ',
      'https://youtube.com/playlist?list=dQw4w9WgXcQ',
      'javascript:alert(1)',
    ]) expect(parseYouTubeVideo(url)).toBeNull()
  })

  it('keeps multiple valid videos in saved order', () => {
    const state = { exVideos: { bench: [
      { url: 'https://youtu.be/dQw4w9WgXcQ', title: 'Demo 1' },
      { url: 'https://evil.test/video', title: 'Invalid' },
      { url: 'https://youtube.com/watch?v=M7lc1UVf-VE', title: 'Demo 2' },
    ] } }
    expect(videosFor(state, 'bench').map(v => v.title)).toEqual(['Demo 1', 'Demo 2'])
  })
})
