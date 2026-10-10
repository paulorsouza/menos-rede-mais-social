import { useEffect, useMemo, useRef, useState } from 'react'
import type { CSSProperties, RefObject } from 'react'
import { Link } from 'react-router'
import { Bookmark, ChevronDown, Coins, Heart, LoaderCircle, MapPin, Volume2, VolumeX } from 'lucide-react'
import { api } from '../api'
import { useApp } from '../app-context'
import { Avatar, Verified } from '../components/Avatar'
import { ModePicker } from '../components/ModePicker'
import { usePostActions } from '../components/PostCard'
import { Empty, ErrorState, Loading } from '../components/States'
import { VideoView } from '../components/VideoView'
import { formatCompact, formatMoney } from '../format'
import { useInView } from '../hooks'
import type { Ad, Post, ShortItem, ShortsResponse } from '../types'

type Watched = RefObject<Map<number, number>>

export function ShortsPage() {
  const { mode, published } = useApp()
  const [data, setData] = useState<ShortsResponse | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [muted, setMuted] = useState(true)
  const watched = useRef(new Map<number, number>())

  useEffect(() => {
    let active = true
    setData(null)
    setError(null)
    watched.current = new Map()
    api
      .shorts(mode)
      .then((response) => active && setData(response))
      .catch((e: Error) => active && setError(e.message))
    return () => {
      active = false
    }
  }, [mode])

  const items: ShortItem[] = useMemo(() => {
    if (!data) return []
    const fresh = published
      .filter((post) => post.kind === 'short')
      .filter((post) => !data.items.some((item) => item.type === 'short' && item.post.id === post.id))
      .map((post) => ({ type: 'short' as const, post }))
    return [...fresh, ...data.items]
  }, [data, published])

  const postsById = useMemo(() => {
    const map = new Map<number, Post>()
    for (const item of items) if (item.type === 'short') map.set(item.post.id, item.post)
    return map
  }, [items])

  function addWatched(postId: number, ms: number) {
    watched.current.set(postId, (watched.current.get(postId) ?? 0) + ms)
  }

  return (
    <div className="shorts">
      <div className="shorts-controls">
        <ModePicker glass />
        <button
          type="button"
          className="icon-btn icon-glass"
          onClick={() => setMuted((value) => !value)}
          aria-label={muted ? 'Ligar o som' : 'Tirar o som'}
        >
          {muted ? <VolumeX size={19} /> : <Volume2 size={19} />}
        </button>
      </div>

      <div className="shorts-scroller">
        {error && <ErrorState message={error} />}
        {!data && !error && <Loading />}
        {data && items.length === 0 && <Empty>Ainda não há shorts neste modo.</Empty>}

        {items.map((item, index) =>
          item.type === 'short' ? (
            <ShortSlide
              key={`short-${item.post.id}`}
              post={item.post}
              muted={muted}
              onWatched={(ms) => addWatched(item.post.id, ms)}
            />
          ) : (
            <AdSlide key={`ad-${index}`} ad={item.ad} shortIds={item.short_ids} watched={watched} postsById={postsById} />
          ),
        )}
      </div>
    </div>
  )
}

function ShortSlide({ post: initial, muted, onWatched }: { post: Post; muted: boolean; onWatched: (ms: number) => void }) {
  const [ref, inView] = useInView<HTMLElement>(0.6)
  const startedAt = useRef<number | null>(null)
  const { post, like, save } = usePostActions(initial)

  // Ao sair da tela, conta o tempo assistido e avisa o backend. Abaixo de 2
  // segundos a view não conta para o criador.
  function flush() {
    if (startedAt.current === null) return
    const ms = performance.now() - startedAt.current
    startedAt.current = null
    onWatched(ms)
    api.view(post.id, ms).catch(() => undefined)
  }

  useEffect(() => {
    if (inView) startedAt.current = performance.now()
    else flush()
  }, [inView])

  useEffect(() => () => flush(), [])

  return (
    <section ref={ref} className="short-slide">
      <div className="short-frame">
        {/* Sem som, a legenda automática aparece sozinha. */}
        {post.media_url && <VideoView post={post} playing={inView} muted={muted} loop captionsOn={muted} captionsAt={68} />}
        {post.media_status === 'processing' && (
          <p className="short-pending" role="status">
            <LoaderCircle size={22} className="spin" />
            Processando o vídeo. Só você vê este short até terminar.
          </p>
        )}

        <div className="short-side">
          <button type="button" className={`short-action ${post.liked ? 'is-liked' : ''}`} onClick={like} aria-label="Curtir">
            <Heart size={28} fill={post.liked ? 'currentColor' : 'none'} />
            <span>{formatCompact(post.likes)}</span>
          </button>
          <button type="button" className={`short-action ${post.saved ? 'is-saved' : ''}`} onClick={save} aria-label="Salvar">
            <Bookmark size={28} fill={post.saved ? 'currentColor' : 'none'} />
            <span>{formatCompact(post.saves)}</span>
          </button>
        </div>

        <div className="short-caption">
          <Link to={`/u/${post.author.nickname}`} className="short-author">
            <Avatar nickname={post.author.nickname} size={30} />
            {post.author.nickname}
            {post.author.verified && <Verified size={14} />}
          </Link>
          {post.body && <p>{post.body}</p>}
        </div>
      </div>
    </section>
  )
}

function AdSlide({
  ad,
  shortIds,
  watched,
  postsById,
}: {
  ad: Ad
  shortIds: number[]
  watched: Watched
  postsById: Map<number, Post>
}) {
  const [ref, inView] = useInView<HTMLElement>(0.6)
  const sent = useRef(false)
  const [result, setResult] = useState<{ revenue_cents: number; splits: Record<string, number> } | null>(null)
  const [failed, setFailed] = useState(false)
  const [open, setOpen] = useState(false)
  const { toast } = useApp()

  // Na primeira vez que o anúncio aparece, manda o tempo assistido de cada
  // short do bloco. O motor de anúncios faz o rateio.
  useEffect(() => {
    if (!inView || sent.current) return
    sent.current = true
    const payload = shortIds.map((id) => ({ post_id: id, watched_ms: Math.round(watched.current.get(id) ?? 0) }))
    api
      .impression(ad.id, payload)
      .then(setResult)
      .catch(() => setFailed(true))
  }, [inView, ad.id, shortIds, watched])

  const creators = useMemo(() => {
    const byAuthor = new Map<string, { nickname: string; ms: number }>()
    for (const id of shortIds) {
      const post = postsById.get(id)
      if (!post) continue
      const current = byAuthor.get(post.author.id) ?? { nickname: post.author.nickname, ms: 0 }
      current.ms += watched.current.get(id) ?? 0
      byAuthor.set(post.author.id, current)
    }
    return [...byAuthor.entries()]
    // O tempo assistido só é lido de novo quando o resultado chega.
  }, [shortIds, postsById, result])

  return (
    <section ref={ref} className="short-slide">
      <div className="short-frame ad-frame" style={{ '--ad-color': ad.color ?? '#16a34a' } as CSSProperties}>
        <div className="ad-content">
          <div className="ad-pills">
            <span className="tag tag-dark">Anúncio</span>
            {ad.scope === 'regional' && (
              <span className="tag tag-light">
                <MapPin size={12} /> {ad.region}
              </span>
            )}
          </div>
          <p className="ad-advertiser">{ad.advertiser}</p>
          <h2 className="ad-title">{ad.title}</h2>
          {ad.body && <p className="ad-body">{ad.body}</p>}
          {ad.cta && (
            <button type="button" className="btn btn-light" onClick={() => toast('Na versão real, abriria a página do anunciante.')}>
              {ad.cta}
            </button>
          )}
        </div>

        <div className={`money ${open ? 'is-open' : ''}`}>
          <button type="button" className="money-toggle" onClick={() => setOpen((value) => !value)} aria-expanded={open}>
            <Coins size={16} />
            Para onde vai o dinheiro
            <ChevronDown size={16} className="money-caret" />
          </button>
          {open && (
            <div className="money-sheet">
              {failed && <p className="faint">Não foi possível registrar o anúncio agora.</p>}
              {!result && !failed && <p className="faint">Calculando…</p>}
              {result && (
                <>
                  <p className="money-lead">
                    {formatMoney(result.revenue_cents)} divididos pelo tempo que você assistiu a cada criador.
                  </p>
                  <ul className="money-list">
                    {creators.map(([authorId, creator]) => (
                      <li key={authorId}>
                        <Avatar nickname={creator.nickname} size={24} />
                        <span className="money-name">{creator.nickname}</span>
                        <span className="money-time">{(creator.ms / 1000).toFixed(0)}s</span>
                        <strong>{authorId in result.splits ? formatMoney(result.splits[authorId]) : '—'}</strong>
                      </li>
                    ))}
                  </ul>
                  <p className="faint">— fora do rateio: anúncios desligados ou gov.br sem monetização.</p>
                </>
              )}
            </div>
          )}
        </div>
      </div>
    </section>
  )
}
