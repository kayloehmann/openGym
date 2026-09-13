import { useRef, useState } from 'react'
import { imgSrc, gifSrc } from '../lib/exercises.js'
import { useStore } from '../store/useStore.js'
import { t, exerciseNameFor } from '../lib/i18n.js'
import Icon from './Icon.jsx'
import { videosFor } from '../lib/exercise-videos.js'

function VideoPoster({ video }) {
  const [failed, setFailed] = useState(false)
  // YouTube supplies a preview thumbnail, not the literal first frame of the stream.
  // A missing thumbnail leaves the play control usable without a broken-image glyph.
  return failed ? null : <img className="exmedia-video-poster" src={video.thumbnail} alt="" loading="lazy"
    referrerPolicy="no-referrer" onError={() => setFailed(true)} />
}

// Big autoplaying animation; tap toggles to the still frame. `compact` shrinks it (superset cards).
// Custom exercises have no media — the animation stays blank by design (issue #11).
// `minimizable` (workout view) adds a persistent minimize/expand control so the animation stops
// eating the screen; the chosen size is saved to settings and carries across exercises and
// future workouts (issue #12). Settings can also turn workout media off entirely
// (gifSize 'off') — then nothing renders here and the exercise card closes up, exactly like
// a custom exercise without media. Any other/legacy value behaves as 'full'.
export default function Media({ ex, id, compact, minimizable }) {
  const [playing, setPlaying] = useState(true)
  const [videoIndex, setVideoIndex] = useState(0)
  const [videoPlaying, setVideoPlaying] = useState(false)
  const touchStartX = useRef(null)
  // 'gif' → the animation failed, the still is showing; 'all' → the still failed too. Media is
  // fetched from wherever the build points (a mount, a CDN): a dropped connection, an expired
  // session on a gated instance or a CDN hiccup used to leave the browser's broken-image glyph
  // on a white block. Now the still stands in for the animation, a neutral tile stands in for
  // both, and a tap tries again — no text, so nothing new to translate.
  const [failed, setFailed] = useState(null)
  const gifSize = useStore(s => s.S.gifSize)
  const videoEntries = useStore(s => s.S.exVideos?.[ex.id])
  const videos = videosFor({ exVideos: { [ex.id]: videoEntries } }, ex.id)
  const update = useStore(s => s.update)
  if (!ex.gif && !videos.length) return null
  if (minimizable && gifSize === 'off') return null
  const mini = minimizable && gifSize === 'mini'
  const toggleSize = e => { e.stopPropagation(); setVideoPlaying(false); update(s => { s.gifSize = mini ? 'full' : 'mini' }) }
  const selectedVideo = videoIndex < 0 ? null : (videos[videoIndex] || videos[0] || null)
  const selectVideo = index => { setVideoPlaying(false); setVideoIndex(index) }
  const slideCount = videos.length + (ex.gif ? 1 : 0)
  const selectedPosition = selectedVideo ? (videos[videoIndex] ? videoIndex : 0) : videos.length
  const go = step => {
    if (slideCount < 2) return
    const next = (selectedPosition + step + slideCount) % slideCount
    selectVideo(next === videos.length ? -1 : next)
  }
  const onTouchEnd = e => {
    if (touchStartX.current == null) return
    const distance = e.changedTouches[0].clientX - touchStartX.current
    touchStartX.current = null
    if (Math.abs(distance) >= 48) go(distance < 0 ? 1 : -1)
  }
  const showGif = playing && failed == null
  const onError = () => setFailed(showGif ? 'gif' : 'all')
  const onTap = () => {
    if (failed) { setFailed(null); setPlaying(true); return }
    setPlaying(p => !p)
  }
  return (
    <div className={'exmedia' + (compact ? ' compact' : '') + (mini ? ' mini' : '') + (!selectedVideo && failed === 'all' ? ' broken' : '')} id={id}>
      <div className="exmedia-stage" onTouchStart={e => { touchStartX.current = e.touches[0].clientX }} onTouchEnd={onTouchEnd}>
      {selectedVideo
        ? (mini
          ? <div className="exmedia-video-mini"><VideoPoster key={selectedVideo.id} video={selectedVideo} /><span><Icon name="play" /> {t('Video paused')}</span></div>
          : videoPlaying
            ? <iframe className="exmedia-video-frame" src={selectedVideo.embed} title={selectedVideo.title || t('Video {0}', videoIndex + 1)}
                loading="lazy" referrerPolicy="strict-origin-when-cross-origin" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share" allowFullScreen />
            : <button type="button" className="exmedia-video-play" aria-label={t('Play video')} onClick={() => setVideoPlaying(true)}>
                <VideoPoster key={selectedVideo.id} video={selectedVideo} />
                <span className="exmedia-video-play-icon"><Icon name="play" /></span>
              </button>)
        : (failed === 'all'
          ? <div className="exmedia-x" onClick={onTap}><Icon name="dumbbell" /></div>
          : <img decoding="async" draggable={false} src={showGif ? gifSrc(ex) : imgSrc(ex)} alt={exerciseNameFor(ex)} onError={onError} onClick={onTap} />)}
      {minimizable && (
        <button className="giftoggle" onClick={toggleSize}>
          <Icon name={mini ? 'expand' : 'minimize'} />{mini ? t('Expand') : t('Minimize')}
        </button>
      )}
      {!selectedVideo && !mini && !failed && (
        <span className="gifhint">
          <Icon name={playing ? 'pause' : 'play'} />{playing ? t('tap to pause') : t('tap to play')}
        </span>
      )}
      </div>
      {videos.length > 0 && <div className="exmedia-carousel" aria-label={t('Exercise videos')}>
        <button type="button" className="exmedia-carousel-arrow" aria-label={t('Previous video')} disabled={slideCount < 2} onClick={() => go(-1)}><Icon name="chevronLeft" /></button>
        <div className="exmedia-carousel-center">
          <div className="exmedia-carousel-title">{selectedVideo ? (selectedVideo.title || t('Video {0}', selectedPosition + 1)) : t('Animation')} <span>{selectedPosition + 1} / {slideCount}</span></div>
          <div className="exmedia-carousel-dots">
            {videos.map((video, index) => <button key={video.id} type="button" className={selectedPosition === index ? 'on' : ''}
              aria-label={video.title || t('Video {0}', index + 1)} aria-current={selectedPosition === index ? 'true' : undefined} onClick={() => selectVideo(index)} />)}
            {ex.gif && <button type="button" className={selectedPosition === videos.length ? 'on' : ''}
              aria-label={t('Animation')} aria-current={selectedPosition === videos.length ? 'true' : undefined} onClick={() => selectVideo(-1)} />}
          </div>
        </div>
        <button type="button" className="exmedia-carousel-arrow" aria-label={t('Next video')} disabled={slideCount < 2} onClick={() => go(1)}><Icon name="chevronRight" /></button>
      </div>}
    </div>
  )
}

export function Thumb({ ex }) {
  if (!ex.img) return <div className="thumb thumb-x"><Icon name="dumbbell" /></div>
  return <img className="thumb" loading="lazy" decoding="async" draggable={false} src={imgSrc(ex)} alt="" />
}
