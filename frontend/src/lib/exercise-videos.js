// Only known YouTube hosts and video paths are accepted. Never hand a saved URL directly to
// an iframe: an imported profile is user-controlled data and must not become an arbitrary embed.
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/
const YOUTUBE_HOSTS = new Set(['youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtube-nocookie.com', 'www.youtube-nocookie.com'])

export function parseYouTubeVideo(value) {
  let url
  try { url = new URL(String(value).trim()) } catch { return null }
  if (url.protocol !== 'https:' || url.username || url.password || url.port) return null
  const host = url.hostname.toLowerCase()
  let id
  if (host === 'youtu.be' || host === 'www.youtu.be') {
    const parts = url.pathname.split('/').filter(Boolean)
    if (parts.length !== 1) return null
    id = parts[0]
  } else if (YOUTUBE_HOSTS.has(host)) {
    const parts = url.pathname.split('/').filter(Boolean)
    if (parts.length === 1 && parts[0] === 'watch') id = url.searchParams.get('v')
    else if (parts.length === 2 && ['shorts', 'live', 'embed'].includes(parts[0])) id = parts[1]
  }
  if (!VIDEO_ID.test(id || '')) return null
  return {
    id,
    url: `https://www.youtube.com/watch?v=${id}`,
    embed: `https://www.youtube-nocookie.com/embed/${id}?playsinline=1&rel=0&autoplay=1`,
    thumbnail: `https://i.ytimg.com/vi/${id}/hqdefault.jpg`,
  }
}

export function videosFor(state, exerciseId) {
  const entries = state?.exVideos?.[exerciseId]
  if (!Array.isArray(entries)) return []
  return entries.map(entry => {
    const video = parseYouTubeVideo(entry?.url)
    return video && { ...video, title: typeof entry.title === 'string' ? entry.title.slice(0, 80) : '' }
  }).filter(Boolean)
}
