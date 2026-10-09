import { useEffect, useState } from 'react'
import { Check, Copy, ExternalLink } from 'lucide-react'
import { api } from '../api'
import { PageHead } from '../components/Layout'
import { InfoTip } from '../components/Popover'
import { ErrorState, Loading } from '../components/States'
import { formatCompact, formatDate, formatMoney } from '../format'
import { REPO_URL, RULES_URL } from '../links'
import type { ParamsFile, TransparencyReport } from '../types'

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
