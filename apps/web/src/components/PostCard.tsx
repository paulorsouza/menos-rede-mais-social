import { useEffect, useState } from 'react'
import { Link } from 'react-router'
import { Bookmark, Compass, Eye, Flag, Flame, Heart, LoaderCircle, Radio, UserCheck, Users, UsersRound } from 'lucide-react'
import { ApiError, api } from '../api'
import { useApp } from '../app-context'
import { formatCompact, timeAgo } from '../format'
import { loadRules } from '../rules'
import type { Author, Post, Reason, Rule } from '../types'
import { Avatar, Verified } from './Avatar'
import { Popover } from './Popover'
import { VideoView } from './VideoView'

export function usePostActions(initial: Post) {
  const [post, setPost] = useState(initial)
  const { me, toast } = useApp()

  async function like() {
    if (!me) return toast('Entre para curtir.')
    setPost((p) => ({ ...p, liked: !p.liked, likes: p.likes + (p.liked ? -1 : 1) }))
    const result = await api.like(post.id).catch(() => null)
    if (result) setPost((p) => ({ ...p, liked: result.liked, likes: result.likes }))
  }

  async function save() {
    if (!me) return toast('Entre para salvar.')
    const result = await api.save(post.id).catch(() => null)
    if (!result) return
    setPost((p) => ({ ...p, saved: result.saved, saves: result.saves }))
    toast(result.saved ? 'Salvo' : 'Removido dos salvos')
  }

  // Vídeo recém-publicado: confere de tempos em tempos se a conversão acabou.
  useEffect(() => {
    if (post.media_status !== 'processing') return
    const timer = setInterval(() => {
      api
        .getPost(post.id)
        .then(({ post: fresh }) => {
          if (fresh.media_status !== 'processing') setPost((p) => ({ ...p, ...fresh }))
        })
        .catch(() => undefined)
    }, 4000)
    return () => clearInterval(timer)
  }, [post.id, post.media_status])

  return { post, like, save }
}

/** Vídeo ou short dentro de um card: a capa, e o vídeo só quando a pessoa dá play. */
export function PostVideo({ post, className }: { post: Post; className: string }) {
  if (post.media_status === 'processing') {
    return (
      <div className={`${className} media-pending`} role="status">
        <LoaderCircle size={20} className="spin" />
        Processando o vídeo. Só você vê este post até terminar.
      </div>
    )
  }
  if (post.media_status === 'failed') {
    return (
      <div className={`${className} media-pending`} role="status">
        Não foi possível processar este vídeo. Tente enviar de novo.
      </div>
    )
  }
  if (!post.media_url) return null
  if (post.kind === 'live') {
    return (
      <div className="live-card">
        <VideoView className={className} post={post} controls aria-label={post.body ?? 'Live'} />
        <span className="live-badge">
          <Radio size={14} /> Ao vivo
        </span>
      </div>
    )
  }
  return <VideoView className={className} post={post} controls aria-label={post.body ?? 'Vídeo'} />
}

const plural = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`

function ReasonText({ reason, author }: { reason: Reason; author: Author }) {
  switch (reason.kind) {
    case 'you_follow':
      return (
        <>
          <UserCheck size={15} /> Você segue @{author.nickname}
        </>
      )
    case 'follows_engaged':
      return (
        <>
          <Users size={15} />{' '}
          {plural(reason.value, 'pessoa que você segue curtiu', 'pessoas que você segue curtiram')}
        </>
      )
    case 'similar_engaged':
      return (
        <>
          <UsersRound size={15} />{' '}
          {plural(reason.value, 'pessoa que curte o que você curte também curtiu', 'pessoas que curtem o que você curte também curtiram')}
        </>
      )
    case 'outside_bubble':
      return (
        <>
          <Compass size={15} /> Ninguém perto de você chegou aqui ainda
        </>
      )
    case 'public_ranking':
      return (
        <>
          <Flame size={15} /> Em alta, igual para todo mundo
        </>
      )
  }
}

/**
 * O "?" de cada post: por que ele apareceu (quando veio de um algoritmo) e a
 * denúncia. Fica fechado até a pessoa pedir.
 */
export function PostInfo({ post, showReasons }: { post: Post; showReasons: boolean }) {
  const { me, toast } = useApp()
  const [rules, setRules] = useState<Rule[] | null>(null)
  const [reporting, setReporting] = useState(false)
  const reasons = showReasons ? post.reasons : []
  const canReport = me !== null && me.id !== post.author.id

  if (reasons.length === 0 && !canReport) return null

  function startReport() {
    setReporting(true)
    loadRules()
      .then((all) => setRules(all.filter((rule) => rule.reportable)))
      .catch(() => toast('Não foi possível carregar as regras.', 'error'))
  }

  async function send(rule: Rule, close: () => void) {
    try {
      await api.report(post.id, rule.number)
      toast('Denúncia enviada. Uma pessoa da moderação vai olhar.', 'success')
      setReporting(false)
      close()
    } catch (error) {
      toast(error instanceof ApiError ? error.message : 'Não foi possível denunciar.', 'error')
    }
  }

  return (
    <Popover
      label={reasons.length > 0 ? 'Por que estou vendo isto' : 'Sobre este post'}
      align="end"
      buttonClassName="why-btn"
      button={<span aria-hidden="true">?</span>}
      panelClassName="pop-why"
    >
      {(close) =>
        reporting ? (
          <div className="why">
            <p className="menu-title">Qual regra este post quebra?</p>
            {!rules && <p className="why-note">Carregando…</p>}
            {rules && (
              <ul className="report-rules">
                {rules.map((rule) => (
                  <li key={rule.number}>
                    <button type="button" onClick={() => send(rule, close)} title={rule.text}>
                      <span className="report-number">{rule.number}</span>
                      {rule.title}
                    </button>
                  </li>
                ))}
              </ul>
            )}
            <Link to="/transparencia#regras" className="text-link" onClick={close}>
              Ler as regras
            </Link>
          </div>
        ) : (
          <div className="why">
            {reasons.length > 0 && (
              <>
                <p className="menu-title">Por que você está vendo isto</p>
                <ul>
                  {reasons.map((reason, index) => (
                    <li key={index}>
                      <ReasonText reason={reason} author={post.author} />
                    </li>
                  ))}
                </ul>
                <Link to="/transparencia" className="text-link" onClick={close}>
                  Ver as regras do motor
                </Link>
              </>
            )}
            {canReport && (
              <button type="button" className="why-report" onClick={startReport}>
                <Flag size={14} />
                Denunciar
              </button>
            )}
          </div>
        )
      }
    </Popover>
  )
}

export function PostCard({ post: initial, showReasons = true }: { post: Post; showReasons?: boolean }) {
  const { post, like, save } = usePostActions(initial)

  return (
    <article className={`post post-${post.kind}`}>
      <Link to={`/u/${post.author.nickname}`} className="post-avatar" aria-label={`Perfil de @${post.author.nickname}`}>
        <Avatar nickname={post.author.nickname} size={40} />
      </Link>

      <div className="post-main">
        <header className="post-head">
          <Link to={`/u/${post.author.nickname}`} className="post-name">
            {post.author.nickname}
            {post.author.verified && <Verified size={14} />}
          </Link>
          <span className="post-time">{timeAgo(post.created_at)}</span>
          <PostInfo post={post} showReasons={showReasons} />
        </header>

        {post.body && <p className={`post-text ${post.kind === 'text' ? 'post-text-short' : ''}`}>{post.body}</p>}

        {post.kind === 'photo' && post.media_url && (
          <img className="post-media" src={post.media_url} alt={post.alt_text ?? post.body ?? 'Foto'} loading="lazy" />
        )}
        {(post.kind === 'video' || post.kind === 'short' || post.kind === 'live') && (
          <PostVideo post={post} className="post-media" />
        )}

        <footer className="post-actions">
          <button type="button" className={`act ${post.liked ? 'is-liked' : ''}`} aria-pressed={post.liked} aria-label="Curtir" onClick={like}>
            <Heart size={19} fill={post.liked ? 'currentColor' : 'none'} />
            {post.likes > 0 && formatCompact(post.likes)}
          </button>
          <button type="button" className={`act ${post.saved ? 'is-saved' : ''}`} aria-pressed={post.saved} aria-label="Salvar" onClick={save}>
            <Bookmark size={19} fill={post.saved ? 'currentColor' : 'none'} />
            {post.saves > 0 && formatCompact(post.saves)}
          </button>
          {post.views > 0 && (
            <span className="act act-static" title="Visualizações">
              <Eye size={19} />
              {formatCompact(post.views)}
            </span>
          )}
        </footer>
      </div>
    </article>
  )
}
