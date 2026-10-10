import { useEffect, useRef, useState } from 'react'
import { Link, useLocation } from 'react-router'
import { Check, Copy, Radio } from 'lucide-react'
import { ApiError, api } from '../api'
import type { LiveInfo } from '../api'
import { useApp } from '../app-context'
import { PageHead } from '../components/Layout'
import { InfoTip } from '../components/Popover'
import { broadcast } from '../live'
import type { Broadcast } from '../live'

type Stage = 'idle' | 'starting' | 'waiting-obs' | 'live' | 'ended'

/**
 * Fazer uma live. A câmera abre na hora; um toque e a live está no ar. Quem
 * prefere o OBS recebe o servidor e a chave. O post da live só aparece para
 * os outros quando a imagem chega, e vira vídeo com a gravação quando acaba.
 */
export function LivePage() {
  const { me } = useApp()
  const location = useLocation()
  const [body, setBody] = useState<string>((location.state as { body?: string } | null)?.body ?? '')
  const [stage, setStage] = useState<Stage>('idle')
  const [error, setError] = useState<string | null>(null)
  const [obs, setObs] = useState<LiveInfo | null>(null)
  const [startedAt, setStartedAt] = useState<number | null>(null)
  const [now, setNow] = useState(Date.now())
  const [cameraReady, setCameraReady] = useState(false)
  const preview = useRef<HTMLVideoElement>(null)
  const stream = useRef<MediaStream | null>(null)
  const session = useRef<Broadcast | null>(null)

  // A câmera abre assim que a tela abre, para a pessoa se ver antes de começar.
  useEffect(() => {
    let cancelled = false
    navigator.mediaDevices
      ?.getUserMedia({ video: { width: { ideal: 1280 }, height: { ideal: 720 }, facingMode: 'user' }, audio: true })
      .then((media) => {
        if (cancelled) return media.getTracks().forEach((track) => track.stop())
        stream.current = media
        if (preview.current) preview.current.srcObject = media
        setCameraReady(true)
      })
      .catch(() => setError('Sem acesso à câmera. Dá para transmitir pelo OBS.'))
    return () => {
      cancelled = true
      session.current?.stop()
      stream.current?.getTracks().forEach((track) => track.stop())
    }
  }, [])

  useEffect(() => {
    if (stage !== 'live') return
    const timer = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [stage])

  // Pelo OBS, a página descobre pelo post quando a imagem chegou e quando acabou.
  useEffect(() => {
    if (!obs || (stage !== 'waiting-obs' && stage !== 'live')) return
    const timer = setInterval(async () => {
      const { post } = await api.getPost(obs.post_id).catch(() => ({ post: null }))
      if (!post) return
      if (stage === 'waiting-obs' && post.kind === 'live' && post.media_status === 'ready') {
        setStage('live')
        setStartedAt(Date.now())
      } else if (stage === 'live' && (post.kind !== 'live' || post.media_status !== 'ready')) {
        // Saiu do ar: a gravação já está na fila para virar vídeo.
        setStage('ended')
      }
    }, 3000)
    return () => clearInterval(timer)
  }, [obs, stage])

  if (!me?.can_go_live) {
    return (
      <div className="page">
        <PageHead title="Ao vivo" />
        <p className="faint">Lives são para contas verificadas de maiores de idade.</p>
      </div>
    )
  }

  async function open() {
    const { live } = await api.createLive(body.trim())
    return live
  }

  async function startCamera() {
    if (!stream.current) return
    setStage('starting')
    setError(null)
    try {
      const live = await open()
      session.current = await broadcast(live.whip_url, live.key, stream.current)
      setStartedAt(Date.now())
      setStage('live')
    } catch (e) {
      setError(e instanceof ApiError || e instanceof Error ? e.message : 'Não foi possível começar.')
      setStage('idle')
    }
  }

  async function startObs() {
    setError(null)
    try {
      setObs(await open())
      setStage('waiting-obs')
      stream.current?.getTracks().forEach((track) => track.stop())
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Não foi possível abrir a live.')
    }
  }

  function stop() {
    session.current?.stop()
    session.current = null
    stream.current?.getTracks().forEach((track) => track.stop())
    setStage('ended')
  }

  const elapsed = startedAt ? Math.max(0, Math.floor((now - startedAt) / 1000)) : 0
  const clock = `${Math.floor(elapsed / 60)}:${String(elapsed % 60).padStart(2, '0')}`

  return (
    <div className="page">
      <PageHead title="Ao vivo">
        <InfoTip label="Como funciona a live">
          A live aparece para os outros quando a imagem chega, no feed de vídeos. Quando você encerra, a gravação vira um
          vídeo comum no seu perfil, e dá para apagar como qualquer post. Live não tem anúncio por enquanto.
        </InfoTip>
      </PageHead>

      {!obs && (
        <div className="live-stage">
          <video ref={preview} autoPlay muted playsInline />
          {stage === 'live' && (
            <span className="live-badge">
              <Radio size={14} /> Ao vivo · {clock}
            </span>
          )}
        </div>
      )}

      {stage === 'ended' ? (
        <div className="live-done">
          <p>Live encerrada. A gravação vira vídeo no seu perfil em instantes.</p>
          <Link to={`/u/${me.nickname}`} className="btn btn-primary btn-sm">
            Ver no perfil
          </Link>
        </div>
      ) : (
        <>
          <textarea
            className="live-title"
            value={body}
            onChange={(event) => setBody(event.target.value)}
            placeholder="Sobre o que é a live?"
            maxLength={500}
            rows={2}
            disabled={stage !== 'idle'}
          />

          {stage === 'idle' && (
            <div className="live-actions">
              <button type="button" className="btn btn-primary" onClick={startCamera} disabled={!cameraReady}>
                Começar live
              </button>
              <button type="button" className="text-link" onClick={startObs}>
                Transmitir pelo OBS
              </button>
            </div>
          )}
          {stage === 'starting' && <p className="faint">Conectando…</p>}
          {stage === 'live' && !obs && (
            <button type="button" className="btn btn-danger" onClick={stop}>
              Encerrar
            </button>
          )}
        </>
      )}

      {obs && stage !== 'ended' && (
        <div className="live-obs">
          <p className="faint">
            {stage === 'live'
              ? `Ao vivo pelo OBS · ${clock}. Pare a transmissão no OBS para encerrar.`
              : 'No OBS, em Configurações › Transmissão, escolha "Personalizado" e use os dados abaixo. A live começa quando a imagem chegar.'}
          </p>
          <CopyField label="Servidor" value={obs.rtmp.server ?? `rtmp://${window.location.hostname}/ao-vivo`} />
          <CopyField label="Chave de transmissão" value={obs.rtmp.stream_key} secret />
        </div>
      )}

      {error && <p className="field-error">{error}</p>}
    </div>
  )
}

function CopyField({ label, value, secret = false }: { label: string; value: string; secret?: boolean }) {
  const [copied, setCopied] = useState(false)

  async function copy() {
    await navigator.clipboard.writeText(value).catch(() => undefined)
    setCopied(true)
    setTimeout(() => setCopied(false), 1800)
  }

  return (
    <div className="copy-field">
      <span>{label}</span>
      <code>{secret ? '•'.repeat(16) : value}</code>
      <button type="button" className="icon-btn icon-btn-sm" onClick={copy} aria-label={`Copiar ${label.toLowerCase()}`}>
        {copied ? <Check size={15} /> : <Copy size={15} />}
      </button>
    </div>
  )
}
