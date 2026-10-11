import { useEffect, useState } from 'react'
import type { CSSProperties, FormEvent } from 'react'
import { Check, Copy, Dices } from 'lucide-react'
import { ApiError, api } from '../api'
import { useApp } from '../app-context'
import { PageHead } from '../components/Layout'
import { InfoTip } from '../components/Popover'
import { ErrorState, Loading } from '../components/States'
import { formatDate, formatMoney, formatNumber } from '../format'
import type { Advertiser, CampaignQuote, OwnCampaign } from '../types'

const COLORS = ['#c2410c', '#1d4ed8', '#15803d', '#7c3aed', '#be123c', '#0f766e']

const STATUS: Record<OwnCampaign['status'], string> = {
  in_review: 'Em análise',
  awaiting_payment: 'Esperando o PIX',
  active: 'No ar',
  rejected: 'Recusada',
  ended: 'Encerrada',
}

const iso = (date: Date) => date.toISOString().slice(0, 10)

/**
 * O lado de quem anuncia. O preço sai de uma tabela pública, igual para todo
 * mundo: não tem leilão, e o anúncio não escolhe quem vê, só a cidade.
 */
export function AdvertisePage() {
  const [advertiser, setAdvertiser] = useState<Advertiser | null | undefined>(undefined)
  const [campaigns, setCampaigns] = useState<OwnCampaign[]>([])
  const [error, setError] = useState<string | null>(null)

  function load() {
    api
      .advertiser()
      .then((data) => {
        setAdvertiser(data.advertiser)
        setCampaigns(data.campaigns)
      })
      .catch((e: Error) => setError(e.message))
  }

  useEffect(load, [])

  return (
    <div className="page">
      <PageHead title="Anunciar">
        <InfoTip label="Como funciona">
          Você compra horas de anúncio por dia, no país todo ou numa cidade. O preço por exibição está em params/ads.toml,
          igual para todo anunciante. A moderação confere o anúncio, você paga por PIX e ele entra no ar nas datas
          escolhidas, espalhado ao longo do dia. Propaganda política não entra.
        </InfoTip>
      </PageHead>

      {error && <ErrorState message={error} />}
      {advertiser === undefined && !error && <Loading />}
      {advertiser === null && <RegisterCompany onDone={load} />}
      {advertiser && (
        <>
          <p className="advertiser-line">
            <strong>{advertiser.name}</strong> · CNPJ {advertiser.cnpj}
          </p>
          <CampaignForm advertiser={advertiser} onCreated={load} />
          <ul className="campaigns">
            {campaigns.map((campaign) => (
              <CampaignItem key={campaign.id} campaign={campaign} onPaid={load} />
            ))}
          </ul>
        </>
      )}
    </div>
  )
}

function RegisterCompany({ onDone }: { onDone: () => void }) {
  const [cnpj, setCnpj] = useState('')
  const [name, setName] = useState('')
  const [errors, setErrors] = useState<Record<string, string[]>>({})
  const [message, setMessage] = useState<string | null>(null)

  async function submit(event: FormEvent) {
    event.preventDefault()
    setErrors({})
    setMessage(null)
    try {
      await api.registerAdvertiser(cnpj, name)
      onDone()
    } catch (e) {
      if (e instanceof ApiError) {
        setErrors(e.fieldErrors)
        setMessage(Object.keys(e.fieldErrors).length === 0 ? e.message : null)
      }
    }
  }

  return (
    <form className="form-card" onSubmit={submit}>
      <p className="faint">Para anunciar, cadastre a empresa. O CNPJ aparece na biblioteca pública de anúncios.</p>
      <label className="field">
        <span>CNPJ</span>
        <span className="field-row">
          <input value={cnpj} onChange={(event) => setCnpj(event.target.value)} inputMode="numeric" placeholder="00.000.000/0001-00" />
          <button
            type="button"
            className="icon-btn"
            aria-label="Gerar um CNPJ de teste"
            title="Gerar um CNPJ de teste (demonstração)"
            onClick={() => api.testCnpj().then(({ cnpj }) => setCnpj(cnpj)).catch(() => undefined)}
          >
            <Dices size={18} />
          </button>
        </span>
        {errors.cnpj && <span className="field-error">{errors.cnpj[0]}</span>}
      </label>
      <label className="field">
        <span>Nome da empresa</span>
        <input value={name} onChange={(event) => setName(event.target.value)} maxLength={80} />
        {errors.name && <span className="field-error">{errors.name[0]}</span>}
      </label>
      {message && <p className="field-error">{message}</p>}
      <button type="submit" className="btn btn-primary">
        Cadastrar a empresa
      </button>
    </form>
  )
}

function CampaignForm({ advertiser, onCreated }: { advertiser: Advertiser; onCreated: () => void }) {
  const { me, toast } = useApp()
  const today = new Date()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<Record<string, string>>({
    title: '',
    body: '',
    cta: 'Conhecer',
    color: COLORS[0],
    scope: 'regional',
    region: me?.region ?? '',
    hours_per_day: '2',
    starts_on: iso(today),
    ends_on: iso(new Date(today.getTime() + 29 * 86_400_000)),
  })
  const [quote, setQuote] = useState<CampaignQuote | null>(null)
  const [errors, setErrors] = useState<Record<string, string[]>>({})
  const [sending, setSending] = useState(false)

  const set = (key: string) => (value: string) => setForm((current) => ({ ...current, [key]: value }))

  // O preço muda na hora, a cada campo.
  useEffect(() => {
    if (!open) return
    const timer = setTimeout(() => {
      api
        .quoteCampaign({ ...form, title: form.title || 'prévia' })
        .then(({ quote }) => {
          setQuote(quote)
          setErrors({})
        })
        .catch((e) => {
          setQuote(null)
          if (e instanceof ApiError) setErrors(e.fieldErrors)
        })
    }, 300)
    return () => clearTimeout(timer)
  }, [form, open])

  async function submit(event: FormEvent) {
    event.preventDefault()
    setSending(true)
    try {
      await api.createCampaign(form)
      toast('Campanha enviada para análise', 'success')
      setOpen(false)
      onCreated()
    } catch (e) {
      if (e instanceof ApiError) {
        setErrors(e.fieldErrors)
        if (Object.keys(e.fieldErrors).length === 0) toast(e.message, 'error')
      }
    } finally {
      setSending(false)
    }
  }

  if (!open) {
    return (
      <button type="button" className="btn btn-primary" onClick={() => setOpen(true)}>
        Nova campanha
      </button>
    )
  }

  const fieldError = (key: string) => errors[key] && <span className="field-error">{errors[key][0]}</span>

  return (
    <form className="form-card campaign-form" onSubmit={submit}>
      <div className="ad-preview" style={{ '--ad-color': form.color } as CSSProperties}>
        <span className="tag tag-dark">Anúncio</span>
        <p className="ad-advertiser">{advertiser.name}</p>
        <h2 className="ad-title">{form.title || 'O título do anúncio'}</h2>
        {form.body && <p className="ad-body">{form.body}</p>}
        {form.cta && <span className="btn btn-light btn-sm">{form.cta}</span>}
      </div>

      <label className="field">
        <span>Título</span>
        <input value={form.title} onChange={(event) => set('title')(event.target.value)} maxLength={60} />
        {fieldError('title')}
      </label>
      <label className="field">
        <span>Texto</span>
        <input value={form.body} onChange={(event) => set('body')(event.target.value)} maxLength={140} />
      </label>
      <div className="field-grid">
        <label className="field">
          <span>Botão</span>
          <input value={form.cta} onChange={(event) => set('cta')(event.target.value)} maxLength={24} />
        </label>
        <div className="field">
          <span>Cor</span>
          <span className="swatches" role="radiogroup" aria-label="Cor do anúncio">
            {COLORS.map((color) => (
              <button
                key={color}
                type="button"
                role="radio"
                aria-checked={form.color === color}
                aria-label={color}
                className="swatch"
                style={{ background: color }}
                onClick={() => set('color')(color)}
              />
            ))}
          </span>
        </div>
      </div>

      <div className="segmented" role="radiogroup" aria-label="Onde o anúncio aparece">
        <button type="button" role="radio" className="segment" aria-checked={form.scope === 'regional'} onClick={() => set('scope')('regional')}>
          Uma cidade
        </button>
        <button type="button" role="radio" className="segment" aria-checked={form.scope === 'national'} onClick={() => set('scope')('national')}>
          O país todo
        </button>
      </div>
      {form.scope === 'regional' && (
        <label className="field">
          <span>Cidade</span>
          <input value={form.region} onChange={(event) => set('region')(event.target.value)} placeholder="Campinas/SP" />
          {fieldError('region')}
        </label>
      )}

      <div className="field-grid">
        <label className="field">
          <span>Horas de anúncio por dia</span>
          <input type="number" min={1} value={form.hours_per_day} onChange={(event) => set('hours_per_day')(event.target.value)} />
          {fieldError('hours_per_day')}
        </label>
        <label className="field">
          <span>Começa</span>
          <input type="date" value={form.starts_on} onChange={(event) => set('starts_on')(event.target.value)} />
          {fieldError('starts_on')}
        </label>
        <label className="field">
          <span>Termina</span>
          <input type="date" value={form.ends_on} onChange={(event) => set('ends_on')(event.target.value)} />
          {fieldError('ends_on')}
        </label>
      </div>

      <div className="quote-line">
        {quote ? (
          <>
            <strong>{formatMoney(quote.total_cents)}</strong>
            <span className="faint">
              {formatNumber(quote.impressions_per_day)} exibições por dia × {quote.days} dias ×{' '}
              {formatMoney(quote.cents_per_impression)}
            </span>
          </>
        ) : (
          <span className="faint">Preencha para ver o preço.</span>
        )}
      </div>

      <div className="form-actions">
        <button type="submit" className="btn btn-primary" disabled={sending || !quote || form.title.trim() === ''}>
          Enviar para análise
        </button>
        <button type="button" className="text-link" onClick={() => setOpen(false)}>
          Cancelar
        </button>
      </div>
    </form>
  )
}

function CampaignItem({ campaign, onPaid }: { campaign: OwnCampaign; onPaid: () => void }) {
  const { me, toast } = useApp()
  const [copied, setCopied] = useState(false)

  async function copy() {
    if (!campaign.brcode) return
    await navigator.clipboard.writeText(campaign.brcode).catch(() => undefined)
    setCopied(true)
    setTimeout(() => setCopied(false), 1800)
  }

  async function simulate() {
    if (!campaign.charge_txid) return
    try {
      await api.payCharge(campaign.charge_txid)
      toast('Pagamento confirmado. A campanha está no ar.', 'success')
      onPaid()
    } catch (e) {
      toast(e instanceof ApiError ? e.message : 'Não foi possível simular o pagamento.', 'error')
    }
  }

  return (
    <li className="campaign-item" style={{ '--ad-color': campaign.color ?? '#16a34a' } as CSSProperties}>
      <span className="campaign-dot" />
      <div className="campaign-main">
        <p className="campaign-title">
          {campaign.title}
          <span className={`campaign-status status-${campaign.status}`}>{STATUS[campaign.status]}</span>
        </p>
        <p className="faint">
          {campaign.scope === 'regional' ? campaign.region : 'País todo'} · {formatDate(campaign.starts_on)} a{' '}
          {formatDate(campaign.ends_on)} · {campaign.price_cents !== null ? formatMoney(campaign.price_cents) : '—'}
        </p>
        {campaign.status === 'rejected' && campaign.rejection_rule && (
          <p className="field-error">
            Recusada pela regra {campaign.rejection_rule.number}: {campaign.rejection_rule.title.toLowerCase()}.
          </p>
        )}
        {campaign.status === 'ended' && campaign.delivered !== null && (
          <p className="faint">
            {formatNumber(campaign.delivered)} exibições entregues
            {campaign.refunded_cents ? ` · ${formatMoney(campaign.refunded_cents)} devolvidos por PIX` : ''}
          </p>
        )}
        {campaign.status === 'awaiting_payment' && campaign.brcode && (
          <div className="pix-charge">
            <span className="faint">PIX copia e cola</span>
            <code>{campaign.brcode}</code>
            <span className="pix-actions">
              <button type="button" className="btn btn-sm" onClick={copy}>
                {copied ? <Check size={15} /> : <Copy size={15} />} Copiar
              </button>
              {me?.demo && (
                <button type="button" className="btn btn-sm" onClick={simulate}>
                  Simular o pagamento
                </button>
              )}
            </span>
          </div>
        )}
      </div>
    </li>
  )
}
