import { useEffect, useState } from 'react'
import { Captions } from 'lucide-react'
import { ApiError, api } from '../api'
import { useApp } from '../app-context'
import type { CaptionCue } from '../types'

/**
 * Quem publicou corrige a legenda automática: o texto de cada trecho, com os
 * tempos que o whisper gerou. Trecho vazio sai da legenda.
 */
export function CaptionEditor({ postId, onSaved }: { postId: number; onSaved: (captionsUrl: string) => void }) {
  const { toast } = useApp()
  const [open, setOpen] = useState(false)
  const [cues, setCues] = useState<CaptionCue[] | null>(null)
  const [texts, setTexts] = useState<string[]>([])
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!open || cues) return
    api
      .captions(postId)
      .then(({ cues }) => {
        setCues(cues)
        setTexts(cues.map((cue) => cue.text))
      })
      .catch((error: Error) => {
        toast(error.message, 'error')
        setOpen(false)
      })
  }, [open, cues, postId, toast])

  async function save() {
    setSaving(true)
    try {
      const response = await api.updateCaptions(postId, texts)
      setCues(response.cues)
      setTexts(response.cues.map((cue) => cue.text))
      onSaved(response.captions_url)
      toast('Legenda corrigida.', 'success')
      setOpen(false)
    } catch (error) {
      toast(error instanceof ApiError ? error.message : 'Não foi possível salvar.', 'error')
    } finally {
      setSaving(false)
    }
  }

  if (!open) {
    return (
      <button type="button" className="btn btn-sm caption-edit-open" onClick={() => setOpen(true)}>
        <Captions size={15} /> Corrigir legenda
      </button>
    )
  }

  return (
    <div className="caption-editor">
      {!cues && <p className="faint">Carregando…</p>}
      {cues && (
        <ol className="caption-cues">
          {cues.map((cue, index) => (
            <li key={`${cue.start}-${index}`}>
              <span className="caption-time">{cue.start.slice(3, 8)}</span>
              <textarea
                value={texts[index] ?? ''}
                rows={2}
                maxLength={300}
                aria-label={`Trecho em ${cue.start}`}
                onChange={(event) => setTexts((current) => current.map((text, i) => (i === index ? event.target.value : text)))}
              />
            </li>
          ))}
        </ol>
      )}
      <div className="order-form-actions">
        <button type="button" className="btn btn-sm" onClick={() => setOpen(false)}>
          Cancelar
        </button>
        <button type="button" className="btn btn-primary btn-sm" disabled={!cues || saving} onClick={save}>
          Salvar
        </button>
      </div>
    </div>
  )
}
