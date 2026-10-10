import { useEffect, useState } from 'react'
import { Check, Copy, ExternalLink } from 'lucide-react'
import { api } from '../api'
import { PageHead } from '../components/Layout'
import { InfoTip } from '../components/Popover'
import { ErrorState, Loading } from '../components/States'
import { formatCompact, formatDate, formatMoney } from '../format'
import { REPO_URL, RULES_URL } from '../links'
import type { ParamsFile, Registro, TransparencyReport, VideoCosts } from '../types'

export function TransparencyPage() {
  const [report, setReport] = useState<TransparencyReport | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    api
      .transparency()
      .then(setReport)
      .catch((e: Error) => setError(e.message))
  }, [])

  // Links como /transparencia#regras chegam antes do conteúdo: rola quando ele aparece.
  useEffect(() => {
    if (report && window.location.hash) {
      document.getElementById(window.location.hash.slice(1))?.scrollIntoView()
    }
  }, [report])

  if (error) return <div className="page"><ErrorState message={error} /></div>
  if (!report) return <div className="page"><Loading /></div>

  const { engine } = report
  const online = engine.status === 'ok'
  const posts = Object.values(report.posts).reduce((sum, value) => sum + (value ?? 0), 0)

  return (
    <div className="page">
      <PageHead title="Transparência">
        <InfoTip label="O que é conferido aqui">
          O motor publica o hash dos parâmetros que está usando. No piloto, ele roda em máquinas que provam, com a assinatura
          do processador, qual programa está carregado.
        </InfoTip>
      </PageHead>

      <section className="status">
        <span className={`status-dot ${online ? 'is-online' : ''}`} />
        <span>
          Motor {online ? `v${engine.engine_version}` : 'fora do ar'}
          {online && <code>{engine.engine_build}</code>}
        </span>
      </section>

      {engine.feed_params && <ParamsCard file={engine.feed_params} title="Feed" />}
      {engine.ads_params && <ParamsCard file={engine.ads_params} title="Anúncios" />}
      {engine.guardians_params && <ParamsCard file={engine.guardians_params} title="Guardiões do CPF" />}

      <section className="numbers">
        <div>
          <strong>{formatCompact(report.accounts.verified)}</strong>
          <span>verificadas</span>
        </div>
        <div>
          <strong>{formatCompact(posts)}</strong>
          <span>posts</span>
        </div>
        <div>
          <strong>{formatCompact(report.removals)}</strong>
          <span>removidos</span>
        </div>
        <div>
          <strong>{report.ads.length}</strong>
          <span>anúncios</span>
        </div>
      </section>

      <RegistroSection />
      <VideoCostSection costs={report.video.costs} />
      <ParamsCard file={report.video.params} title="Vídeo" />
      <Rules report={report} />
      <Identifications report={report} />

      <section>
        <h2 className="section-label">Quem anunciou</h2>
        <ul className="ad-list">
          {report.ads.map((ad) => (
            <li key={ad.id}>
              <span className="ad-dot" style={{ background: ad.color ?? undefined }} />
              <span className="ad-list-name">
                {ad.advertiser}
                <small>{ad.scope === 'regional' ? ad.region : 'Nacional'}</small>
              </span>
              <strong>{formatMoney(ad.paid_cents)}</strong>
            </li>
          ))}
        </ul>
      </section>

      <nav className="footer-links">
        <a href={RULES_URL} target="_blank" rel="noreferrer">
          Regras pétreas <ExternalLink size={13} />
        </a>
        <a href={REPO_URL} target="_blank" rel="noreferrer">
          Código <ExternalLink size={13} />
        </a>
      </nav>
    </div>
  )
}

const KIND_LABEL: Record<string, string> = {
  motor: 'Versão do motor',
  'raiz-dados': 'Retrato do grafo',
  identificacao: 'Ordem judicial aberta',
}

/** Uma linha curta para cada entrada, a partir do texto exato publicado. */
function describe(kind: string, data: string) {
  try {
    const payload = JSON.parse(data.slice(data.indexOf('\n') + 1))
    if (kind === 'motor') return `v${payload.versao} · feed ${String(payload.feed_sha256).slice(0, 8)}…`
    if (kind === 'raiz-dados') return `${payload.ligacoes} ligações · raiz ${String(payload.raiz).slice(0, 8)}…`
    if (kind === 'identificacao') return payload.sigiloso ? 'Processo sigiloso' : payload.juizo
  } catch {
    // Entrada de um tipo novo: mostra só o tipo.
  }
  return kind
}

/**
 * O registro público: uma árvore que só aceita acréscimos, com o cabeçalho
 * assinado. Os dois arquivos daqui são o que o verificador aberto precisa.
 */
function RegistroSection() {
  const [registro, setRegistro] = useState<Registro | null>(null)

  useEffect(() => {
    api.registro().then(setRegistro).catch(() => setRegistro(null))
  }, [])

  if (!registro) return null

  return (
    <section id="registro">
      <div className="params-head">
        <h2 className="section-label">Registro público</h2>
        <InfoTip label="Como conferir o registro">
          Cada versão do motor, cada retrato do grafo e cada ordem judicial aberta vira uma entrada que não pode mais ser
          mudada nem apagada. Baixe o cabeçalho e as entradas e rode{' '}
          <code>verificador registro registro.json entradas.json</code>. Guarde o cabeçalho de hoje: amanhã, a prova de
          consistência mostra que nada dele foi trocado.
        </InfoTip>
      </div>
      <p className="rules-foot">
        {registro.head.size} {registro.head.size === 1 ? 'entrada' : 'entradas'} · raiz{' '}
        <code className="hash-inline">{registro.head.root.slice(0, 16)}…</code>
      </p>
      <ul className="ad-list">
        {registro.entries.slice(0, 6).map((entry) => (
          <li key={entry.index}>
            <span className="ad-list-name">
              {KIND_LABEL[entry.kind] ?? entry.kind}
              <small>{describe(entry.kind, entry.data)}</small>
            </span>
            <strong>#{entry.index}</strong>
          </li>
        ))}
      </ul>
      <nav className="footer-links">
        <a href="/api/registro" download="registro.json">
          Baixar o cabeçalho
        </a>
        <a href="/api/registro/entradas" download="entradas.json">
          Baixar as entradas
        </a>
      </nav>
    </section>
  )
}

const cents = (value: number | undefined) => (value === undefined ? '—' : formatMoney(value))

/**
 * Quanto custa uma hora de vídeo: o que os vídeos convertidos realmente
 * ocuparam e gastaram, ao lado do teto que os parâmetros permitem.
 */
function VideoCostSection({ costs }: { costs: VideoCosts }) {
  const { measured, ceiling, prices } = costs
  const watched = new Map((measured.watch ?? []).map((row) => [row.short_side, row]))

  return (
    <section id="video">
      <div className="params-head">
        <h2 className="section-label">Quanto custa uma hora de vídeo</h2>
        <InfoTip label="Como a conta é feita">
          Medido: o espaço e o tempo de processador que os vídeos já convertidos gastaram, por hora de vídeo. Teto: o
          máximo que o bitrate de cada qualidade em <code>params/video.toml</code> permite. Os preços (
          {formatMoney(prices.storage_cents_per_gb_month)} por GB ao mês, {formatMoney(prices.egress_cents_per_gb)} por
          GB entregue, {formatMoney(prices.cpu_cents_per_hour)} por hora de processador) são ilustrativos até alguém
          operar a rede.
        </InfoTip>
      </div>
      <table className="table cost-table">
        <thead>
          <tr>
            <td />
            <td>Medido</td>
            <td>Teto</td>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>Guardar por {prices.months_stored} meses</td>
            <td>{cents(measured.store_cents)}</td>
            <td>{cents(ceiling.store_cents)}</td>
          </tr>
          <tr>
            <td>Converter</td>
            <td>{cents(measured.transcode_cents)}</td>
            <td>—</td>
          </tr>
          {ceiling.watch.map((row) => (
            <tr key={row.short_side}>
              <td>Assistir em {row.short_side}</td>
              <td>{cents(watched.get(row.short_side)?.cents)}</td>
              <td>{cents(row.cents)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="rules-foot">
        {measured.videos > 0
          ? `Medido em ${measured.videos} ${measured.videos === 1 ? 'vídeo' : 'vídeos'} (${Math.round(measured.hours * 60)} min).`
          : 'Nenhum vídeo convertido ainda.'}
      </p>
    </section>
  )
}

/**
 * As regras de conteúdo, com quantas remoções cada uma já teve, e o que
 * aconteceu com os recursos.
 */
function Rules({ report }: { report: TransparencyReport }) {
  const { removals_by_rule: byRule, kept, appeals } = report.moderation

  return (
    <section id="regras">
      <h2 className="section-label">Regras de conteúdo</h2>
      <ol className="rules">
        {report.rules.map((rule) => (
          <li key={rule.number}>
            <span className="rule-number">{rule.number}</span>
            <div>
              <strong>{rule.title}</strong>
              <p>{rule.text}</p>
              <small>
                Exemplo: {rule.example} · {rule.law}
              </small>
            </div>
            <span className="rule-count" title="Remoções por esta regra">
              {byRule[rule.number] ?? 0}
            </span>
          </li>
        ))}
      </ol>
      <p className="rules-foot">
        {kept} {kept === 1 ? 'post denunciado foi mantido' : 'posts denunciados foram mantidos'} · {appeals.restored}{' '}
        {appeals.restored === 1 ? 'recurso aceito' : 'recursos aceitos'} · {appeals.upheld}{' '}
        {appeals.upheld === 1 ? 'negado' : 'negados'} · {appeals.pending} em análise
      </p>
    </section>
  )
}

/**
 * Ordens judiciais que abriram um CPF: o juízo e a data, nunca quem foi
 * identificado. Processo sigiloso entra só na contagem.
 */
function Identifications({ report }: { report: TransparencyReport }) {
  const { requested, opened, secret, entries } = report.identifications

  return (
    <section id="identificacoes">
      <h2 className="section-label">Identificações por ordem judicial</h2>
      <p className="rules-foot">
        {requested} {requested === 1 ? 'ordem recebida' : 'ordens recebidas'} · {opened}{' '}
        {opened === 1 ? 'aberta' : 'abertas'} com 3 de 5 guardiões{secret > 0 && ` · ${secret} em processo sigiloso`}
      </p>
      {entries.length > 0 && (
        <ul className="ad-list">
          {entries.map((entry) => (
            <li key={`${entry.opened_at}-${entry.court}`}>
              <span className="ad-list-name">
                {entry.court}
                <small>{entry.case_number ?? 'sem número de processo'}</small>
              </span>
              <strong>{formatDate(entry.opened_at)}</strong>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

function ParamsCard({ file, title }: { file: ParamsFile; title: string }) {
  const [copied, setCopied] = useState(false)
  const [open, setOpen] = useState(false)

  async function copy() {
    try {
      await navigator.clipboard.writeText(file.sha256)
      setCopied(true)
      setTimeout(() => setCopied(false), 1800)
    } catch {
      setCopied(false)
    }
  }

  return (
    <section className="params">
      <div className="params-head">
        <span className="params-title">
          {title}
          <small>
            {file.path} · v{file.version}
          </small>
        </span>
        <InfoTip label="Como conferir">
          Baixe o repositório e rode <code>sha256sum {file.path}</code>. O resultado tem que ser igual ao hash abaixo.
        </InfoTip>
      </div>
      <div className="hash">
        <code>{file.sha256}</code>
        <button type="button" className="icon-btn icon-btn-sm" onClick={copy} aria-label="Copiar hash">
          {copied ? <Check size={15} /> : <Copy size={15} />}
        </button>
      </div>
      <button type="button" className="disclosure" onClick={() => setOpen((value) => !value)} aria-expanded={open}>
        {open ? 'Esconder arquivo' : 'Ver arquivo'}
      </button>
      {open && <pre className="code">{file.source}</pre>}
    </section>
  )
}
