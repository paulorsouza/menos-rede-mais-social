import { useEffect, useState } from 'react'
import { Link } from 'react-router'
import { CircleCheck, CircleX, ShieldAlert } from 'lucide-react'
import { ApiError, api } from '../api'
import { useApp } from '../app-context'
import { PageHead } from '../components/Layout'
import { InfoTip } from '../components/Popover'
import { PostPreview } from '../components/PostPreview'
import { Empty, ErrorState, Loading } from '../components/States'
import type { Notice } from '../types'

/** Avisos da moderação: o que saiu, por qual regra, e o recurso. */
export function NoticesPage() {
  const { me, setMe } = useApp()
  const [notices, setNotices] = useState<Notice[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api
      .notices()
      .then(({ notices }) => {
        setNotices(notices)
        // Abrir a página já conta como ter lido.
        if (notices.some((notice) => !notice.read)) api.readNotices().catch(() => undefined)
      })
      .catch((e: Error) => setError(e.message))
  }, [])

  useEffect(() => {
    if (me && me.unread_notices > 0 && notices) setMe({ ...me, unread_notices: 0 })
  }, [me, notices, setMe])

  function appealed(id: number) {
    setNotices((current) =>
      current?.map((notice) => (notice.id === id ? { ...notice, appeal: 'pending', can_appeal: false } : notice)) ?? null,
    )
  }

  return (
    <div className="page">
      <PageHead title="Avisos">
        <InfoTip label="Como funciona">
          Quando um post seu sai do ar, o aviso diz qual regra foi usada. Você pode recorrer uma vez, e quem julga o recurso
          é outra pessoa da moderação, nunca quem removeu.
        </InfoTip>
      </PageHead>

      {error && <ErrorState message={error} />}
      {!notices && !error && <Loading />}
      {notices && notices.length === 0 && <Empty>Nenhum aviso.</Empty>}

      <ul className="notices">
        {notices?.map((notice) => (
          <li key={notice.id} className={`notice ${notice.read ? '' : 'is-unread'}`}>
            <NoticeText notice={notice} />
            {notice.post && <PostPreview post={notice.post} />}
            {notice.can_appeal && notice.post && (
              <AppealForm postId={notice.post.id} onDone={() => appealed(notice.id)} />
            )}
            {notice.kind === 'removed' && notice.appeal === 'pending' && (
              <p className="notice-status">Recurso enviado. Outra pessoa da moderação vai decidir.</p>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}

function NoticeText({ notice }: { notice: Notice }) {
  const rule = notice.rule && (
    <Link to="/transparencia#regras" className="notice-rule">
      regra {notice.rule.number}, {notice.rule.title.toLowerCase()}
    </Link>
  )

  switch (notice.kind) {
    case 'removed':
      return (
        <p className="notice-text">
          <ShieldAlert size={18} />
          <span>Seu post saiu do ar pela {rule}.</span>
        </p>
      )
    case 'restored':
      return (
        <p className="notice-text is-good">
          <CircleCheck size={18} />
          <span>Seu recurso foi aceito e o post voltou.</span>
        </p>
      )
    case 'upheld':
      return (
        <p className="notice-text">
          <CircleX size={18} />
          <span>Seu recurso foi negado. A remoção pela {rule} foi mantida.</span>
        </p>
      )
  }
}

function AppealForm({ postId, onDone }: { postId: number; onDone: () => void }) {
  const { toast } = useApp()
  const [open, setOpen] = useState(false)
  const [text, setText] = useState('')
  const [sending, setSending] = useState(false)

  if (!open) {
    return (
      <button type="button" className="btn btn-sm notice-action" onClick={() => setOpen(true)}>
        Recorrer
      </button>
    )
  }

  async function send() {
    setSending(true)
    try {
      await api.appeal(postId, text)
      toast('Recurso enviado', 'success')
      onDone()
    } catch (error) {
      toast(error instanceof ApiError ? error.message : 'Não foi possível recorrer.', 'error')
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="appeal-form">
      <textarea
        value={text}
        onChange={(event) => setText(event.target.value)}
        placeholder="Se quiser, explique por que o post não quebra a regra"
        rows={3}
        maxLength={1000}
        autoFocus
        aria-label="Explicação do recurso"
      />
      <button type="button" className="btn btn-primary btn-sm" onClick={send} disabled={sending}>
        {sending ? 'Enviando…' : 'Enviar recurso'}
      </button>
    </div>
  )
}
