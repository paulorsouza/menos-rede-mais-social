import { useEffect, useRef, useState } from 'react'
import type { ClipboardEvent, DragEvent, FormEvent, KeyboardEvent } from 'react'
import { Clapperboard, Film, Image, ImagePlus, Radio, X } from 'lucide-react'
import { useNavigate } from 'react-router'
import type { LucideIcon } from 'lucide-react'
import { ApiError, api } from '../api'
import { useApp } from '../app-context'
import type { Post, PostKind } from '../types'
import { startUpload } from '../upload'
import type { UploadHandle } from '../upload'
import { Avatar } from './Avatar'

const TEXT_LIMIT = 140
const CAPTION_LIMIT = 500
const ACCEPT = 'image/jpeg,image/png,image/webp,image/gif,video/mp4,video/webm,video/quicktime'

// Vídeo em pé e curto vira short. Acima disso é vídeo, mesmo que vertical,
// porque short é feito para passar um atrás do outro.
const SHORT_MAX_SECONDS = 180

const KIND_LABEL: Record<Exclude<PostKind, 'text' | 'live'>, { label: string; icon: LucideIcon }> = {
  photo: { label: 'Foto', icon: Image },
  video: { label: 'Vídeo', icon: Film },
  short: { label: 'Short', icon: Clapperboard },
}

const MARKERS = [
  { id: 'start', label: 'início' },
  { id: 'middle', label: 'meio' },
  { id: 'end', label: 'fim' },
]

interface Attachment {
  file: File
  url: string
  // Vídeo fica sem tipo até o navegador ler a largura, a altura e a duração.
  kind: PostKind | null
  // Quanto do arquivo já chegou no servidor (de 0 a 1).
  progress: number
}

function attach(file: File): Attachment | null {
  if (file.type.startsWith('image/')) return { file, url: URL.createObjectURL(file), kind: 'photo', progress: 0 }
  if (file.type.startsWith('video/')) return { file, url: URL.createObjectURL(file), kind: null, progress: 0 }
  return null
}

/**
 * Um campo só para tudo. O tipo do post sai do arquivo anexado, e não existe
 * tema nem tag: quem publica não precisa escolher nada.
 *
 * O arquivo começa a subir assim que é escolhido, enquanto a pessoa escreve
 * a legenda, e retoma sozinho se a conexão cair (upload.ts).
 */
export function Composer({ inline = false, onPublished }: { inline?: boolean; onPublished?: (post: Post) => void }) {
  const { me, toast, addPublished } = useApp()
  const navigate = useNavigate()
  const [body, setBody] = useState('')
  const [attachment, setAttachment] = useState<Attachment | null>(null)
  const [ads, setAds] = useState(true)
  const [markers, setMarkers] = useState<string[]>(['start'])
  const [altText, setAltText] = useState<string | null>(null)
  const [focused, setFocused] = useState(false)
  const [dragging, setDragging] = useState(false)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const fileInput = useRef<HTMLInputElement>(null)
  const textarea = useRef<HTMLTextAreaElement>(null)
  const upload = useRef<UploadHandle | null>(null)

  const attachmentUrl = attachment?.url
  useEffect(() => {
    if (!attachmentUrl) return
    return () => URL.revokeObjectURL(attachmentUrl)
  }, [attachmentUrl])

  // Saiu da tela com um envio pela metade: desiste dele.
  useEffect(() => () => upload.current?.cancel(), [])

  if (!me?.can_publish) return null

  const kind: PostKind | null = attachment ? attachment.kind : 'text'
  const limit = attachment ? CAPTION_LIMIT : TEXT_LIMIT
  const remaining = limit - body.length
  const open = !inline || focused || body.length > 0 || attachment !== null
  const canAd = me.can_monetize && (kind === 'video' || kind === 'short')
  const canSend = !sending && remaining >= 0 && kind !== null && (attachment !== null || body.trim().length > 0)

  function pick(file: File | undefined) {
    if (!file) return
    const next = attach(file)
    if (!next) {
      setError('Só dá para anexar foto ou vídeo.')
      return
    }
    upload.current?.cancel()
    setError(null)
    setAttachment(next)
    textarea.current?.focus()

    const handle = startUpload(file, (progress) =>
      setAttachment((current) => (current?.file === file ? { ...current, progress } : current)),
    )
    upload.current = handle
    handle.done.catch((e: Error) => {
      if (upload.current === handle) setError(e.message)
    })
  }

  function onVideoMetadata(video: HTMLVideoElement) {
    const vertical = video.videoHeight > video.videoWidth
    // Alguns webm gravados no navegador chegam sem duração; aí vale só a orientação.
    const short = !Number.isFinite(video.duration) || video.duration <= SHORT_MAX_SECONDS
    const kind: PostKind = vertical && short ? 'short' : 'video'
    setAttachment((current) => (current && current.kind === null ? { ...current, kind } : current))
  }

  function toggleMarker(id: string) {
    const next = markers.includes(id) ? markers.filter((marker) => marker !== id) : [...markers, id]
    if (next.length === 0) {
      setAds(false)
      setMarkers(['start'])
    } else {
      setMarkers(next)
    }
  }

  function removeAttachment() {
    upload.current?.cancel()
    upload.current = null
    setAttachment(null)
    setAltText(null)
    setAds(true)
    setMarkers(['start'])
    setError(null)
    if (fileInput.current) fileInput.current.value = ''
  }

  async function submit(event?: FormEvent) {
    event?.preventDefault()
    if (!canSend || !kind) return
    setSending(true)
    setError(null)

    try {
      // Se o arquivo ainda está subindo, espera terminar antes de publicar.
      const uploadId = upload.current ? await upload.current.done : undefined
      const { post } = await api.createPost({
        kind,
        body,
        upload_id: uploadId,
        alt_text: kind === 'photo' && altText?.trim() ? altText.trim() : undefined,
        ad_markers: kind === 'video' && ads && me!.can_monetize ? markers : undefined,
        monetized: kind === 'short' ? ads && me!.can_monetize : undefined,
      })
      // O envio virou post: não há mais nada para cancelar.
      upload.current = null
      addPublished(post)
      setBody('')
      removeAttachment()
      setFocused(false)
      textarea.current?.blur()
      toast('Publicado', 'success')
      onPublished?.(post)
    } catch (e) {
      const message = e instanceof ApiError ? (Object.values(e.fieldErrors).flat()[0] ?? e.message) : null
      setError(message ?? 'Não foi possível publicar.')
    } finally {
      setSending(false)
    }
  }

  function onKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
      event.preventDefault()
      submit()
    } else if (event.key === 'Escape' && !body && !attachment) {
      setFocused(false)
      event.currentTarget.blur()
    }
  }

  function onPaste(event: ClipboardEvent<HTMLTextAreaElement>) {
    const file = event.clipboardData.files[0]
    if (file) {
      event.preventDefault()
      pick(file)
    }
  }

  function onDrop(event: DragEvent) {
    event.preventDefault()
    setDragging(false)
    pick(event.dataTransfer.files[0])
  }

  const Kind = attachment?.kind && attachment.kind !== 'text' && attachment.kind !== 'live' ? KIND_LABEL[attachment.kind] : null

  return (
    <form
      className={`composer ${inline ? 'composer-inline' : 'composer-page'} ${open ? 'is-open' : ''} ${dragging ? 'is-dragging' : ''}`}
      onSubmit={submit}
      onDragOver={(event) => {
        event.preventDefault()
        setDragging(true)
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={onDrop}
    >
      {inline && <Avatar nickname={me.nickname} size={40} />}

      <div className="composer-body">
        <div className="composer-line">
          <textarea
            ref={textarea}
            value={body}
            onChange={(event) => setBody(event.target.value)}
            onFocus={() => setFocused(true)}
            onKeyDown={onKeyDown}
            onPaste={onPaste}
            autoFocus={!inline}
            placeholder={attachment ? 'Legenda' : 'O que está acontecendo?'}
            rows={open ? (inline ? 2 : 4) : 1}
            aria-label={attachment ? 'Legenda' : 'Texto curto, até 140 caracteres'}
          />
          {!open && (
            <button type="button" className="icon-btn" aria-label="Anexar foto ou vídeo" onClick={() => fileInput.current?.click()}>
              <ImagePlus size={20} />
            </button>
          )}
        </div>

        {attachment && (
          <div className="attachment">
            {attachment.file.type.startsWith('image/') ? (
              <img src={attachment.url} alt="Prévia" />
            ) : (
              <video
                src={attachment.url}
                muted
                playsInline
                controls
                onLoadedMetadata={(event) => onVideoMetadata(event.currentTarget)}
                onError={() => setAttachment((current) => (current ? { ...current, kind: current.kind ?? 'video' } : current))}
              />
            )}
            {Kind && (
              <span className="attachment-kind">
                <Kind.icon size={13} />
                {Kind.label}
              </span>
            )}
            <button type="button" className="attachment-remove" aria-label="Tirar anexo" onClick={removeAttachment}>
              <X size={16} />
            </button>
            {attachment.progress < 1 && (
              <span
                className="upload-bar"
                role="progressbar"
                aria-label="Envio do arquivo"
                aria-valuenow={Math.round(attachment.progress * 100)}
              >
                <span style={{ width: `${attachment.progress * 100}%` }} />
              </span>
            )}
          </div>
        )}

        {attachment?.kind === 'photo' &&
          (altText === null ? (
            <button type="button" className="alt-toggle" onClick={() => setAltText('')}>
              Descrever a imagem
            </button>
          ) : (
            <input
              className="alt-input"
              value={altText}
              onChange={(event) => setAltText(event.target.value)}
              placeholder="O que aparece na foto, para quem usa leitor de tela"
              maxLength={1000}
              autoFocus
              aria-label="Descrição da imagem"
            />
          ))}

        {canAd && (
          <div className="ad-line">
            <button
              type="button"
              role="switch"
              aria-checked={ads}
              aria-label="Anúncio"
              className={`switch switch-sm ${ads ? 'is-on' : ''}`}
              onClick={() => setAds((on) => !on)}
              title={kind === 'short' ? 'Um anúncio a cada 6 shorts, dividido pelo tempo assistido' : 'Sem anúncio, sem receita'}
            >
              <span />
            </button>
            <span className="ad-line-label">Anúncio</span>
            {ads && kind === 'video' && (
              <span className="marker-pick" role="group" aria-label="Momento do anúncio">
                {MARKERS.map((marker) => (
                  <button
                    key={marker.id}
                    type="button"
                    aria-pressed={markers.includes(marker.id)}
                    onClick={() => toggleMarker(marker.id)}
                  >
                    {marker.label}
                  </button>
                ))}
              </span>
            )}
          </div>
        )}

        {open && (
          <div className="composer-foot">
            <button type="button" className="icon-btn" aria-label="Anexar foto ou vídeo" onClick={() => fileInput.current?.click()}>
              <ImagePlus size={20} />
            </button>
            {me.can_go_live && !attachment && (
              <button
                type="button"
                className="icon-btn"
                aria-label="Fazer uma live"
                title="Fazer uma live"
                onClick={() => navigate('/transmitir', { state: { body } })}
              >
                <Radio size={20} />
              </button>
            )}
            <span className="composer-spacer" />
            {remaining <= 20 && (
              <span className={`counter ${remaining < 0 ? 'is-over' : 'is-near'}`}>{remaining}</span>
            )}
            <button
              type="submit"
              className="btn btn-primary btn-sm"
              disabled={!canSend}
              title="Ctrl + Enter"
            >
              {sending
                ? attachment && attachment.progress < 1
                  ? `Enviando ${Math.floor(attachment.progress * 100)}%`
                  : 'Publicando…'
                : 'Publicar'}
            </button>
          </div>
        )}

        {error && <p className="field-error">{error}</p>}
      </div>

      <input
        ref={fileInput}
        type="file"
        accept={ACCEPT}
        hidden
        onChange={(event) => pick(event.target.files?.[0])}
      />
    </form>
  )
}
