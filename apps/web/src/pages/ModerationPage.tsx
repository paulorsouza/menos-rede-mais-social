import { useEffect, useState } from 'react'
import { ShieldCheck } from 'lucide-react'
import { ApiError, api } from '../api'
import { useApp } from '../app-context'
import { PageHead } from '../components/Layout'
import { InfoTip } from '../components/Popover'
import { PostPreview } from '../components/PostPreview'
import { Empty, ErrorState, Loading } from '../components/States'
import { loadRules } from '../rules'
import type { AppealItem, QueueEntry, Rule } from '../types'

type Tab = 'reports' | 'appeals'

/**
 * A mesa da moderação: denúncias e recursos. Toda remoção cita uma regra, e
 * recurso contra uma remoção sua fica para outra pessoa decidir.
 */
export function ModerationPage() {
  const { me } = useApp()
  const [tab, setTab] = useState<Tab>('reports')
  const [reports, setReports] = useState<QueueEntry[] | null>(null)
  const [appeals, setAppeals] = useState<AppealItem[] | null>(null)
  const [rules, setRules] = useState<Rule[]>([])
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!me?.moderator) return
    api
      .moderationQueue()
      .then((queue) => {
        setReports(queue.reports)
        setAppeals(queue.appeals)
      })
      .catch((e: Error) => setError(e.message))
    loadRules().then(setRules).catch(() => undefined)
  }, [me?.moderator])

  if (!me?.moderator) {
    return (
      <div className="page">
        <PageHead title="Moderação" />
        <Empty>Só a equipe de moderação vê esta página.</Empty>
      </div>
    )
  }

  const loaded = reports !== null && appeals !== null

  return (
    <div className="page">
      <PageHead title="Moderação">
        <InfoTip label="Como a moderação decide">
          Remova só o que quebra uma das regras públicas, e cite qual. O autor recebe o aviso e pode recorrer uma vez. Um
          recurso contra uma remoção sua aparece aqui, mas só outra pessoa da moderação pode decidir.
        </InfoTip>
      </PageHead>

      <div className="segmented" role="tablist" aria-label="O que revisar">
        <button type="button" role="tab" className="segment" aria-selected={tab === 'reports'} onClick={() => setTab('reports')}>
          Denúncias{reports && reports.length > 0 ? ` · ${reports.length}` : ''}
        </button>
        <button type="button" role="tab" className="segment" aria-selected={tab === 'appeals'} onClick={() => setTab('appeals')}>
          Recursos{appeals && appeals.length > 0 ? ` · ${appeals.length}` : ''}
        </button>
      </div>

      {error && <ErrorState message={error} />}
      {!loaded && !error && <Loading />}

      {loaded && tab === 'reports' && (
        <ul className="mod-list">
          {reports.length === 0 && <Empty>Nenhuma denúncia em aberto.</Empty>}
          {reports.map((entry) => (
            <ReportItem
              key={entry.post.id}
              entry={entry}
              rules={rules}
              onDone={() => setReports((current) => current?.filter((item) => item.post.id !== entry.post.id) ?? null)}
            />
          ))}
        </ul>
      )}

      {loaded && tab === 'appeals' && (
        <ul className="mod-list">
          {appeals.length === 0 && <Empty>Nenhum recurso esperando.</Empty>}
          {appeals.map((appeal) => (
            <AppealItemView
              key={appeal.id}
              appeal={appeal}
              mine={appeal.removed_by?.id === me.id}
              onDone={() => setAppeals((current) => current?.filter((item) => item.id !== appeal.id) ?? null)}
            />
          ))}
        </ul>
      )}
    </div>
  )
}

function useAction(onDone: () => void) {
  const { toast } = useApp()
  const [busy, setBusy] = useState(false)

  return {
    busy,
    async run(action: () => Promise<unknown>, message: string) {
      setBusy(true)
      try {
        await action()
        toast(message, 'success')
        onDone()
      } catch (error) {
        toast(error instanceof ApiError ? error.message : 'Não foi possível concluir.', 'error')
        setBusy(false)
      }
    },
  }
}

function ReportItem({ entry, rules, onDone }: { entry: QueueEntry; rules: Rule[]; onDone: () => void }) {
  const [rule, setRule] = useState(entry.reports[0].rule)
  const { busy, run } = useAction(onDone)
  const summary = entry.reports.map((report) => `${report.title} (${report.count})`).join(', ')

  return (
    <li className="mod-item">
      <p className="mod-summary">
        <strong>
          {entry.total} {entry.total === 1 ? 'denúncia' : 'denúncias'}
        </strong>{' '}
        · {summary}
      </p>
      <PostPreview post={entry.post} />
      <div className="mod-actions">
        <select value={rule} onChange={(event) => setRule(Number(event.target.value))} aria-label="Regra da remoção">
          {(rules.length > 0 ? rules : entry.reports.map((report) => ({ number: report.rule, title: report.title }))).map(
            (option) => (
              <option key={option.number} value={option.number}>
                {option.number}. {option.title}
              </option>
            ),
          )}
        </select>
        <button
          type="button"
          className="btn btn-primary btn-sm"
          disabled={busy}
          onClick={() => run(() => api.removePost(entry.post.id, rule), 'Post removido e autor avisado')}
        >
          Remover
        </button>
        <button type="button" className="btn btn-sm" disabled={busy} onClick={() => run(() => api.keepPost(entry.post.id), 'Post mantido')}>
          Manter
        </button>
      </div>
    </li>
  )
}

function AppealItemView({ appeal, mine, onDone }: { appeal: AppealItem; mine: boolean; onDone: () => void }) {
  const { busy, run } = useAction(onDone)

  return (
    <li className="mod-item">
      <p className="mod-summary">
        Removido{appeal.removed_by ? ` por @${appeal.removed_by.nickname}` : ''} pela regra {appeal.rule?.number},{' '}
        {appeal.rule?.title.toLowerCase()}
      </p>
      <PostPreview post={appeal.post} />
      {appeal.text && <blockquote className="mod-quote">{appeal.text}</blockquote>}
      {mine ? (
        <p className="mod-note">
          <ShieldCheck size={15} />
          Você removeu este post. Outra pessoa da moderação decide o recurso.
        </p>
      ) : (
        <div className="mod-actions">
          <button
            type="button"
            className="btn btn-primary btn-sm"
            disabled={busy}
            onClick={() => run(() => api.decideAppeal(appeal.id, 'restore'), 'Post devolvido')}
          >
            Devolver o post
          </button>
          <button
            type="button"
            className="btn btn-sm"
            disabled={busy}
            onClick={() => run(() => api.decideAppeal(appeal.id, 'uphold'), 'Remoção mantida')}
          >
            Manter a remoção
          </button>
        </div>
      )}
    </li>
  )
}
