import { useState } from 'react'
import type { FormEvent } from 'react'
import { ChevronDown, Download } from 'lucide-react'
import { ApiError, api } from '../api'
import { useApp } from '../app-context'
import { formatMoney, formatNumber, monthName } from '../format'
import type { Dashboard, PayoutStatus, Statement, StatementSummary } from '../types'
import { InfoTip } from './Popover'

const STATUS: Record<PayoutStatus, string> = {
  paid: 'Pago por PIX',
  sending: 'Enviando o PIX',
  carried: 'Fica para o mês seguinte',
  no_key: 'Falta a chave PIX',
  failed: 'O banco recusou o PIX',
}

const capitalize = (text: string) => text.charAt(0).toUpperCase() + text.slice(1)

const REASON: Record<string, string> = {
  unverified_viewer: 'conta sem gov.br',
  repeated_same_day: 'mesma pessoa, mesmo vídeo, mesmo dia',
  creator_daily_limit: 'passou do limite de views por dia',
}

/**
 * A chave PIX do criador. O banco diz de quem é a chave, e a rede só aceita
 * se for do próprio CPF da conta, sem guardar o número.
 */
export function PixKeyCard({ dashboard, onSaved }: { dashboard: Dashboard; onSaved: () => void }) {
  const { me, toast } = useApp()
  const [editing, setEditing] = useState(dashboard.pix_key === null)
  const [key, setKey] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  async function save(event: FormEvent) {
    event.preventDefault()
    setSaving(true)
    setError(null)
    try {
      await api.setPixKey(key)
      toast('Chave PIX salva', 'success')
      setEditing(false)
      onSaved()
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Não foi possível salvar a chave.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <section className="pix-card">
      <div className="params-head">
        <span className="hero-label">Recebimento</span>
        <InfoTip label="Por que não o CPF">
          O repasse vai para uma chave PIX no seu CPF: o banco diz de quem é a chave, e a rede confere pela impressão
          digital do CPF, sem guardar o número. Por isso a chave não pode ser o próprio CPF. Quem recebe como empresa
          cadastra o CNPJ e usa uma chave dele, que pode ser o próprio CNPJ. Na demonstração, a sua chave é{' '}
          <code>{me?.nickname}@pix.demo</code>.
        </InfoTip>
      </div>
      {editing ? (
        <form className="pix-form" onSubmit={save}>
          <input
            value={key}
            onChange={(event) => setKey(event.target.value)}
            placeholder={dashboard.company ? 'E-mail, celular, chave aleatória ou CNPJ' : 'E-mail, celular ou chave aleatória'}
            aria-label="Chave PIX"
            autoComplete="off"
          />
          <button type="submit" className="btn btn-primary btn-sm" disabled={saving || key.trim() === ''}>
            Salvar
          </button>
        </form>
      ) : (
        <p className="pix-line">
          PIX em {dashboard.pix_key?.hint}
          <button type="button" className="text-link" onClick={() => setEditing(true)}>
            trocar
          </button>
        </p>
      )}
      {error && <p className="field-error">{error}</p>}
      <CompanyLine company={dashboard.company} onSaved={onSaved} />
    </section>
  )
}

/** Receber como empresa: o CNPJ fica na conta, como o de quem anuncia. */
function CompanyLine({ company, onSaved }: { company: Dashboard['company']; onSaved: () => void }) {
  const { toast } = useApp()
  const [open, setOpen] = useState(false)
  const [cnpj, setCnpj] = useState('')
  const [name, setName] = useState('')
  const [saving, setSaving] = useState(false)

  if (company) {
    return (
      <p className="faint">
        Empresa: {company.name} · CNPJ {company.cnpj}
      </p>
    )
  }

  if (!open) {
    return (
      <button type="button" className="text-link" onClick={() => setOpen(true)}>
        Receber como empresa
      </button>
    )
  }

  async function save(event: FormEvent) {
    event.preventDefault()
    setSaving(true)
    try {
      await api.setCompany({ cnpj, name })
      toast('Empresa cadastrada. Agora a chave pode ser do CNPJ.', 'success')
      onSaved()
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Não foi possível cadastrar.', 'error')
      setSaving(false)
    }
  }

  return (
    <form className="pix-form" onSubmit={save}>
      <input value={cnpj} onChange={(event) => setCnpj(event.target.value)} placeholder="CNPJ" aria-label="CNPJ" required />
      <input value={name} onChange={(event) => setName(event.target.value)} placeholder="Nome da empresa" aria-label="Nome da empresa" required />
      <button type="submit" className="btn btn-primary btn-sm" disabled={saving}>
        Salvar
      </button>
    </form>
  )
}

/** Os meses fechados, com o detalhe de cada um e o arquivo para conferir. */
export function Statements({ statements }: { statements: StatementSummary[] }) {
  if (statements.length === 0) return null

  return (
    <section>
      <div className="params-head">
        <h2 className="section-label">Extratos</h2>
        <InfoTip label="Como conferir o extrato">
          Cada mês fecha no dia 1º, pelo motor aberto. Baixe o extrato e rode{' '}
          <code>verificador pagamento extrato.json --parametros params/ads.toml --registro entradas.json</code>: ele refaz
          a conta com o mesmo código e confere que cada linha está na árvore publicada no registro.
        </InfoTip>
      </div>
      <ul className="statements">
        {statements.map((item) => (
          <StatementRow key={item.month} item={item} />
        ))}
      </ul>
    </section>
  )
}

function StatementRow({ item }: { item: StatementSummary }) {
  const [open, setOpen] = useState(false)
  const [detail, setDetail] = useState<Statement | null>(null)

  function toggle() {
    setOpen((value) => !value)
    if (!detail) api.statement(item.month).then(({ statement }) => setDetail(statement)).catch(() => undefined)
  }

  return (
    <li className={`statement ${open ? 'is-open' : ''}`}>
      <button type="button" className="statement-head" onClick={toggle} aria-expanded={open}>
        <span>
          {capitalize(monthName(`${item.month}-01`))}
          <small className={`payout-status payout-${item.status}`}>{STATUS[item.status]}</small>
        </span>
        <strong>{formatMoney(item.total_cents)}</strong>
        <ChevronDown size={16} className="statement-caret" />
      </button>
      {open && detail && <StatementDetail statement={detail} />}
    </li>
  )
}

function StatementDetail({ statement }: { statement: Statement }) {
  const discarded = Object.entries(statement.discarded_by_reason)

  return (
    <div className="statement-body">
      <table className="table">
        <tbody>
          <tr>
            <td>Views com anúncio nacional</td>
            <td>{formatNumber(statement.national_views)}</td>
          </tr>
          {statement.regional_views > 0 && (
            <tr>
              <td>Com anúncio regional (valem metade)</td>
              <td>{formatNumber(statement.regional_views)}</td>
            </tr>
          )}
          {discarded.map(([reason, count]) => (
            <tr key={reason}>
              <td>Não contaram: {REASON[reason] ?? reason}</td>
              <td>{formatNumber(count)}</td>
            </tr>
          ))}
          <tr>
            <td>Vídeos, depois das faixas ({formatNumber(statement.effective_views)} views)</td>
            <td>{formatMoney(statement.video_cents)}</td>
          </tr>
          <tr>
            <td>Shorts ({statement.shorts.length} anúncios)</td>
            <td>{formatMoney(statement.shorts_cents)}</td>
          </tr>
          {statement.bonus_cents > 0 && (
            <tr>
              <td>Bônus dos criadores pequenos</td>
              <td>{formatMoney(statement.bonus_cents)}</td>
            </tr>
          )}
          {statement.carry_in_cents > 0 && (
            <tr>
              <td>Saldo do mês anterior</td>
              <td>{formatMoney(statement.carry_in_cents)}</td>
            </tr>
          )}
          <tr className="table-total">
            <td>Total</td>
            <td>{formatMoney(statement.total_cents)}</td>
          </tr>
        </tbody>
      </table>
      <p className="faint">
        {statement.status === 'paid' && statement.pix_e2e_id
          ? `PIX para ${statement.pix_key_hint}, id ${statement.pix_e2e_id}.`
          : STATUS[statement.status] + '.'}{' '}
        {statement.lines} linhas na árvore do fechamento, raiz <code className="hash-inline">{statement.root.slice(0, 12)}…</code>
        {statement.registro_position !== null && `, entrada #${statement.registro_position} do registro`}.
      </p>
      <a className="btn btn-sm" href={`/api/creator/statements/${statement.month}/file`} download={`extrato-${statement.month}.json`}>
        <Download size={15} /> Baixar para conferir
      </a>
    </div>
  )
}
