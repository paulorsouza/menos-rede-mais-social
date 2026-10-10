import { useEffect, useRef, useState } from 'react'
import type { CSSProperties } from 'react'
import { Link } from 'react-router'
import { Play, Radio, X } from 'lucide-react'
import { api } from '../api'
import { useApp } from '../app-context'
import { Avatar, Verified } from '../components/Avatar'
import { PageHead } from '../components/Layout'
import { ModePicker } from '../components/ModePicker'
import { InfoTip } from '../components/Popover'
import { Empty, ErrorState, Loading } from '../components/States'
import { VideoView } from '../components/VideoView'
import { formatCompact, formatDuration, timeAgo } from '../format'
import type { Ad, FeedResponse, Post } from '../types'

const MARKER_LABEL: Record<string, string> = { start: 'início', middle: 'meio', end: 'fim' }
const AD_SECONDS = 5

export function VideosPage() {
  const { mode, published } = useApp()
  const [feed, setFeed] = useState<FeedResponse | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [playing, setPlaying] = useState<Post | null>(null)

  useEffect(() => {
    let active = true
    setFeed(null)
    setError(null)
    api
      .feed(mode, 'videos')
      .then((response) => active && setFeed(response))
      .catch((e: Error) => active && setError(e.message))
    return () => {
      active = false
    }
  }, [mode])

  const fresh = published.filter((post) => post.kind === 'video' && !feed?.items.some((item) => item.id === post.id))
  // Lives no ar vêm primeiro; a ordem do resto é a do motor.
  const items = feed?.items ?? []
  const videos = [...items.filter((post) => post.kind === 'live'), ...fresh, ...items.filter((post) => post.kind !== 'live')]

  return (
    <div className="page page-wide">
      <PageHead title="Vídeos">
        <ModePicker />
      </PageHead>

      {error && <ErrorState message={error} />}
      {!feed && !error && <Loading />}
      {feed && videos.length === 0 && <Empty>Ainda não há vídeos neste modo.</Empty>}

      <div className="video-grid">
        {videos.map((post) => (
          <button key={post.id} type="button" className="video-card" onClick={() => setPlaying(post)}>
            <span className="video-thumb">
              {post.poster_url && <img src={post.poster_url} alt="" loading="lazy" />}
              <span className="video-play">
                <Play size={18} fill="currentColor" />
              </span>
              {post.kind === 'live' ? (
                <span className="live-badge">
                  <Radio size={14} /> Ao vivo
                </span>
              ) : (
                post.duration_ms !== null && <span className="video-duration">{formatDuration(post.duration_ms)}</span>
              )}
            </span>
            <span className="video-title">{post.body}</span>
            <span className="video-meta">
              {post.author.nickname} · {formatCompact(post.views)} views · {timeAgo(post.created_at)}
            </span>
          </button>
        ))}
      </div>

      {playing && <VideoPlayer post={playing} ad={feed?.ad ?? null} onClose={() => setPlaying(null)} />}
    </div>
  )
}

type AdMoment = 'start' | 'middle' | 'end'

function VideoPlayer({ post, ad, onClose }: { post: Post; ad: Ad | null; onClose: () => void }) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const markers = post.monetized && ad ? post.ad_markers : []
  const shown = useRef(new Set<string>())
  const furthest = useRef(0)
  const [adMoment, setAdMoment] = useState<AdMoment | null>(null)
  const [countdown, setCountdown] = useState(AD_SECONDS)
  // Anúncio no início entra antes do vídeo; sem ele, o vídeo começa direto.
  const [startsNow] = useState(!markers.includes('start'))

  useEffect(() => {
    if (markers.includes('start')) {
      shown.current.add('start')
      setAdMoment('start')
    }
  }, [])

  // Cada anúncio que aparece é avisado ao backend: é a view com anúncio que
  // paga o criador, pelas faixas.
  useEffect(() => {
    if (adMoment && ad) api.adView(ad.id, post.id, adMoment).catch(() => undefined)
  }, [adMoment, ad, post.id])

  useEffect(() => {
    if (!adMoment) return
    setCountdown(AD_SECONDS)
    const timer = setInterval(() => setCountdown((value) => value - 1), 1000)
    return () => clearInterval(timer)
  }, [adMoment])

  useEffect(() => {
    if (adMoment && countdown <= 0) {
      const finished = adMoment
      setAdMoment(null)
      if (finished !== 'end') videoRef.current?.play().catch(() => undefined)
    }
  }, [countdown, adMoment])

  function close() {
    if (furthest.current > 0) api.view(post.id, furthest.current * 1000).catch(() => undefined)
    onClose()
  }

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => event.key === 'Escape' && close()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  })

  function onTimeUpdate() {
    const video = videoRef.current
    if (!video) return
    furthest.current = Math.max(furthest.current, video.currentTime)
    if (markers.includes('middle') && !shown.current.has('middle') && video.currentTime >= video.duration / 2) {
      shown.current.add('middle')
      video.pause()
      setAdMoment('middle')
    }
  }

  function onEnded() {
    if (markers.includes('end') && !shown.current.has('end')) {
      shown.current.add('end')
      setAdMoment('end')
    }
  }

  return (
    <div className="modal" role="dialog" aria-modal="true" aria-label={post.body ?? 'Vídeo'} onClick={close}>
      <div className="modal-panel" onClick={(event) => event.stopPropagation()}>
        <div className="player">
          <VideoView
            ref={videoRef}
            post={post}
            playing={startsNow || undefined}
            controls={!adMoment}
            onTimeUpdate={onTimeUpdate}
            onEnded={onEnded}
          />
          {adMoment && ad && (
            <div className="player-ad" style={{ '--ad-color': ad.color ?? '#16a34a' } as CSSProperties}>
              <span className="tag tag-dark">
                Anúncio{adMoment !== 'end' && ` · ${Math.max(countdown, 0)}s`}
              </span>
              <p className="ad-advertiser">{ad.advertiser}</p>
              <h2 className="ad-title">{ad.title}</h2>
            </div>
          )}
          <button type="button" className="icon-btn icon-glass player-close" onClick={close} aria-label="Fechar">
            <X size={20} />
          </button>
        </div>

        <div className="player-info">
          <Link to={`/u/${post.author.nickname}`} className="player-author" onClick={close}>
            <Avatar nickname={post.author.nickname} size={36} />
            <span>
              <strong className="nickname">
                {post.author.nickname}
                {post.author.verified && <Verified size={14} />}
              </strong>
              <small>{timeAgo(post.created_at)}</small>
            </span>
          </Link>
          <p>{post.body}</p>

          {/* Live não tem anúncio. */}
          {post.kind !== 'live' && (
            <div className="markers">
              <span className="markers-bar">
                {['start', 'middle', 'end'].map((marker) => (
                  <span key={marker} className={`marker marker-${marker} ${markers.includes(marker) ? 'is-on' : ''}`} />
                ))}
              </span>
              <InfoTip label="Anúncios neste vídeo">
                {markers.length > 0
                  ? `O criador escolheu anúncio no ${markers.map((m) => MARKER_LABEL[m]).join(' e no ')}. Ele recebe por view, pelas faixas públicas.`
                  : 'O criador escolheu não ter anúncio neste vídeo. Sem anúncio, ele também não recebe.'}
              </InfoTip>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
