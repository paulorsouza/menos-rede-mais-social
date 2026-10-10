import { useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import { Download, Gavel, ShieldAlert, Trash2 } from 'lucide-react'
import { ApiError, api } from '../api'
import { useApp } from '../app-context'
import { PageHead } from '../components/Layout'
import { InfoTip } from '../components/Popover'
import { Empty, ErrorState, Loading } from '../components/States'
import { formatDate, formatDateTime } from '../format'
import type { IdentificationOrder, OpenedOrder, RemovalRequest, Rule } from '../types'

const GUARDIANS = [1, 2, 3, 4, 5]
const THRESHOLD = 3

/**
 * Ordens judiciais de identificação, para o setor jurídico da entidade
 * gestora. O CPF só abre com as partes de 3 dos 5 guardiões, e o resultado
 * aparece uma vez só.
 */
export function OrdersPage() {
  const { me } = useApp()
  const [orders, setOrders] = useState<IdentificationOrder[] | null>(null)
  const [demo, setDemo] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)
  const [results, setResults] = useState<Record<number, OpenedOrder>>({})

  useEffect(() => {
    if (!me?.legal_officer) return
    api
      .orders()
      .then((response) => {
        setOrders(response.orders)
        setDemo(response.demo)
      })
      .catch((e: Error) => setError(e.message))
  }, [me?.legal_officer])

  if (!me?.legal_officer) {
    return (
      <div className="page">
        <PageHead title="Ordens judiciais" />
        <Empty>Só o setor jurídico da entidade gestora vê esta página.</Empty>
      </div>
    )
  }

  function replace(order: IdentificationOrder) {
    setOrders((current) => current?.map((item) => (item.id === order.id ? order : item)) ?? null)
  }

  return (
    <div className="page">
      <PageHead title="Ordens judiciais">
        <InfoTip label="Como uma identificação acontece">
          Cada guardião confere a ordem por conta própria e manda a sua parte. Com 3 dos 5, o CPF e os IPs dos últimos seis
          meses aparecem aqui uma única vez e não ficam guardados. Toda abertura entra no registro público, com o juízo e
          sem identificar a pessoa.
        </InfoTip>
      </PageHead>

      {creating ? (
        <NewOrder
          onCancel={() => setCreating(false)}
          onCreated={(order) => {
            setOrders((current) => [order, ...(current ?? [])])
            setCreating(false)
          }}
        />
      ) : (
        <button type="button" className="btn btn-primary btn-sm orders-new" onClick={() => setCreating(true)}>
          <Gavel size={16} /> Registrar ordem
        </button>
      )}

      {error && <ErrorState message={error} />}
      {!orders && !error && <Loading />}
      {orders && orders.length === 0 && <Empty>Nenhuma ordem registrada.</Empty>}

      <ul className="orders">
        {orders?.map((order) => (
          <OrderItem
            key={order.id}
            order={order}
            demo={demo}
            result={results[order.id]}
            onChange={replace}
            onOpened={(result) => setResults((current) => ({ ...current, [order.id]: result }))}
          />
        ))}
      </ul>

      <Removals />
    </div>
  )
}

/**
 * Pedidos de remoção vindos de fora. Ordem judicial se cumpre; pedido de
 * outro órgão só tira o post se ele quebra uma regra pública.
 */
function Removals() {
  const [requests, setRequests] = useState<RemovalRequest[] | null>(null)
  const [rules, setRules] = useState<Rule[]>([])
  const [error, setError] = useState<string | null>(null)
  const [creating, setCreating] = useState(false)

  useEffect(() => {
    api
      .removals()
      .then((response) => setRequests(response.requests))
      .catch((e: Error) => setError(e.message))
    api
      .rules()
      .then((response) => setRules(response.rules))
      .catch(() => undefined)
  }, [])

  function replace(request: RemovalRequest) {
    setRequests((current) => current?.map((item) => (item.id === request.id ? request : item)) ?? null)
  }

  return (
    <section className="removals">
      <div className="params-head">
        <h2 className="section-label">Pedidos de remoção</h2>
        <InfoTip label="Como um pedido de remoção é tratado">
          Pedido de remoção só vale por aqui, com quem pediu e a base legal. Ordem judicial é cumprida e o post sai pela
          regra 9. Pedido de ministério, partido ou empresa só tira o post se ele quebra uma regra pública; senão, é
          recusado com o motivo. Toda decisão entra no registro público e todo pedido entra no relatório trimestral.
        </InfoTip>
      </div>

      {creating ? (
        <NewRemoval
          onCancel={() => setCreating(false)}
          onCreated={(request) => {
            setRequests((current) => [request, ...(current ?? [])])
            setCreating(false)
          }}
        />
      ) : (
        <button type="button" className="btn btn-primary btn-sm orders-new" onClick={() => setCreating(true)}>
          <Trash2 size={16} /> Registrar pedido
        </button>
      )}

      {error && <ErrorState message={error} />}
      {!requests && !error && <Loading />}
      {requests && requests.length === 0 && <Empty>Nenhum pedido registrado.</Empty>}

      <ul className="orders">
        {requests?.map((request) => (
          <RemovalItem key={request.id} request={request} rules={rules} onChange={replace} />
        ))}
      </ul>
    </section>
  )
}

function NewRemoval({ onCreated, onCancel }: { onCreated: (request: RemovalRequest) => void; onCancel: () => void }) {
  const { toast } = useApp()
  const [postRef, setPostRef] = useState('')
  const [kind, setKind] = useState<'judicial' | 'outro'>('judicial')
  const [authority, setAuthority] = useState('')
  const [legalBasis, setLegalBasis] = useState('')
  const [caseNumber, setCaseNumber] = useState('')
  const [secret, setSecret] = useState(false)
  const [sending, setSending] = useState(false)

  async function submit(event: FormEvent) {
    event.preventDefault()
    setSending(true)
    try {
      const { request } = await api.createRemoval({
        post: postRef,
        kind,
        authority,
        legal_basis: legalBasis,
        case_number: caseNumber,
        secret_case: secret,
      })
      toast('Pedido registrado.', 'success')
      onCreated(request)
    } catch (error) {
      toast(error instanceof ApiError ? error.message : 'Não foi possível registrar.', 'error')
      setSending(false)
    }
  }

  return (
    <form className="order-form" onSubmit={submit}>
      <input value={postRef} onChange={(e) => setPostRef(e.target.value)} placeholder="Link ou número do post" required autoFocus aria-label="Post" />
      <select value={kind} onChange={(e) => setKind(e.target.value as 'judicial' | 'outro')} aria-label="Quem pede">
        <option value="judicial">Ordem judicial</option>
        <option value="outro">Outro órgão</option>
      </select>
      <input value={authority} onChange={(e) => setAuthority(e.target.value)} placeholder={kind === 'judicial' ? 'Juízo' : 'Órgão'} required aria-label="Quem pediu" />
      <input value={legalBasis} onChange={(e) => setLegalBasis(e.target.value)} placeholder="Base legal" required aria-label="Base legal" />
      {!secret && (
        <input value={caseNumber} onChange={(e) => setCaseNumber(e.target.value)} placeholder="Número do processo" aria-label="Número do processo" />
      )}
      <label className="order-secret">
        <input type="checkbox" checked={secret} onChange={(e) => setSecret(e.target.checked)} />
        Processo sigiloso
      </label>
      <div className="order-form-actions">
        <button type="button" className="btn btn-sm" onClick={onCancel}>
          Cancelar
        </button>
        <button type="submit" className="btn btn-primary btn-sm" disabled={sending}>
          Registrar
        </button>
      </div>
    </form>
  )
}

const REMOVAL_STATUS: Record<RemovalRequest['status'], string> = {
  recebido: 'Aguardando decisão',
  cumprido: 'Cumprido',
  recusado: 'Recusado',
}

function RemovalItem({
  request,
  rules,
  onChange,
}: {
  request: RemovalRequest
  rules: Rule[]
  onChange: (request: RemovalRequest) => void
}) {
  const { toast } = useApp()
  const [busy, setBusy] = useState(false)
  const [rule, setRule] = useState<number | ''>('')
  const [reason, setReason] = useState('')
  const open = request.status === 'recebido'
  const publicRules = rules.filter((item) => item.number !== 9)

  async function act(action: () => Promise<{ request: RemovalRequest }>) {
    setBusy(true)
    try {
      onChange((await action()).request)
    } catch (error) {
      toast(error instanceof ApiError ? error.message : 'Não foi possível concluir.', 'error')
    } finally {
      setBusy(false)
    }
  }

  return (
    <li className="order">
      <p className="order-title">
        <strong>{request.post_id ? `Post #${request.post_id}` : 'Post apagado'}</strong> · {request.authority}
      </p>
      <p className="order-meta">
        {request.kind === 'judicial' ? 'Ordem judicial' : 'Outro órgão'} · {request.legal_basis} ·{' '}
        {request.secret_case ? 'Processo sigiloso' : request.case_number || 'Sem número de processo'} · registrado em{' '}
        {formatDate(request.created_at)}
      </p>
      {request.post_body && <p className="order-meta">“{request.post_body}”</p>}
      <p className="order-meta">
        {REMOVAL_STATUS[request.status]}
        {request.rule !== null && ` · regra ${request.rule}`}
        {request.refusal_reason && ` · ${request.refusal_reason}`}
        {request.registro_position !== null && ` · registro #${request.registro_position}`}
      </p>

      {open && request.kind === 'judicial' && (
        <div className="order-actions">
          <button type="button" className="btn btn-primary btn-sm" disabled={busy} onClick={() => act(() => api.complyRemoval(request.id))}>
            Cumprir
          </button>
        </div>
      )}

      {open && request.kind === 'outro' && (
        <div className="order-actions removal-decide">
          <select value={rule} onChange={(e) => setRule(e.target.value === '' ? '' : Number(e.target.value))} aria-label="Regra que o post quebra">
            <option value="">Regra que o post quebra</option>
            {publicRules.map((item) => (
              <option key={item.number} value={item.number}>
                {item.number}. {item.title}
              </option>
            ))}
          </select>
          <button
            type="button"
            className="btn btn-primary btn-sm"
            disabled={busy || rule === ''}
            onClick={() => act(() => api.complyRemoval(request.id, Number(rule)))}
          >
            Remover
          </button>
          <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Motivo da recusa" aria-label="Motivo da recusa" />
          <button
            type="button"
            className="btn btn-sm"
            disabled={busy || reason.trim() === ''}
            onClick={() => act(() => api.refuseRemoval(request.id, reason))}
          >
            Recusar
          </button>
        </div>
      )}
    </li>
  )
}

function NewOrder({ onCreated, onCancel }: { onCreated: (order: IdentificationOrder) => void; onCancel: () => void }) {
  const { toast } = useApp()
  const [nickname, setNickname] = useState('')
  const [court, setCourt] = useState('')
  const [caseNumber, setCaseNumber] = useState('')
  const [secret, setSecret] = useState(false)
  const [sending, setSending] = useState(false)

  async function submit(event: FormEvent) {
    event.preventDefault()
    setSending(true)
    try {
      const { order } = await api.createOrder({ nickname, court, case_number: caseNumber, secret_case: secret })
      toast('Ordem registrada. Agora os guardiões decidem.', 'success')
      onCreated(order)
    } catch (error) {
      toast(error instanceof ApiError ? error.message : 'Não foi possível registrar.', 'error')
      setSending(false)
    }
  }

  return (
    <form className="order-form" onSubmit={submit}>
      <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="Apelido da conta" required autoFocus aria-label="Apelido da conta" />
      <input value={court} onChange={(e) => setCourt(e.target.value)} placeholder="Juízo, por exemplo 1ª Vara Criminal de Campinas" required aria-label="Juízo" />
      {!secret && (
        <input value={caseNumber} onChange={(e) => setCaseNumber(e.target.value)} placeholder="Número do processo" aria-label="Número do processo" />
      )}
      <label className="order-secret">
        <input type="checkbox" checked={secret} onChange={(e) => setSecret(e.target.checked)} />
        Processo sigiloso
      </label>
      <div className="order-form-actions">
        <button type="button" className="btn btn-sm" onClick={onCancel}>
          Cancelar
        </button>
        <button type="submit" className="btn btn-primary btn-sm" disabled={sending}>
          Registrar
        </button>
      </div>
    </form>
  )
}

function OrderItem({
  order,
  demo,
  result,
  onChange,
  onOpened,
}: {
  order: IdentificationOrder
  demo: boolean
  result?: OpenedOrder
  onChange: (order: IdentificationOrder) => void
  onOpened: (result: OpenedOrder) => void
}) {
  const { toast } = useApp()
  const [busy, setBusy] = useState(false)
  const ready = order.ready_guardians.length
  const open = order.status === 'collecting'

  async function act<T>(action: () => Promise<T>, done: (value: T) => void) {
    setBusy(true)
    try {
      done(await action())
    } catch (error) {
      toast(error instanceof ApiError ? error.message : 'Não foi possível concluir.', 'error')
    } finally {
      setBusy(false)
    }
  }

  return (
    <li className="order">
      <p className="order-title">
        <strong>@{order.nickname ?? 'conta apagada'}</strong> · {order.court}
      </p>
      <p className="order-meta">
        {order.secret_case ? 'Processo sigiloso' : order.case_number || 'Sem número de processo'} · registrada em{' '}
        {formatDate(order.created_at)}
        {order.opened_at && ` · aberta em ${formatDate(order.opened_at)}`}
      </p>

      <div className="guardians" role="group" aria-label="Partes dos guardiões">
        {GUARDIANS.map((guardian) => {
          const given = order.ready_guardians.includes(guardian)
          const canSimulate = demo && open && !given
          return (
            <button
              key={guardian}
              type="button"
              className={`guardian ${given ? 'is-given' : ''}`}
              disabled={!canSimulate || busy}
              title={given ? `Guardião ${guardian} mandou a parte` : canSimulate ? `Simular o guardião ${guardian}` : `Guardião ${guardian}`}
              aria-label={given ? `Guardião ${guardian}: parte recebida` : `Guardião ${guardian}: sem parte`}
              onClick={() => act(() => api.simulateGuardian(order.id, guardian), ({ order }) => onChange(order))}
            >
              {guardian}
            </button>
          )
        })}
        <span className="guardians-count">
          {Math.min(ready, THRESHOLD)} de {THRESHOLD}
        </span>
      </div>
      {demo && open && ready < THRESHOLD && (
        <p className="order-hint">Na demonstração, toque num guardião para simular a parte dele.</p>
      )}

      {open && (
        <div className="order-actions">
          <a className="btn btn-sm" href={`/api/identification/orders/${order.id}/package`} download>
            <Download size={15} /> Pedido para os guardiões
          </a>
          <button
            type="button"
            className="btn btn-primary btn-sm"
            disabled={ready < THRESHOLD || busy}
            onClick={() =>
              act(
                () => api.openOrder(order.id),
                (response) => {
                  onOpened(response.result)
                  onChange(response.order)
                },
              )
            }
          >
            Abrir
          </button>
        </div>
      )}

      {result && (
        <div className="order-result">
          <p className="order-warning">
            <ShieldAlert size={16} /> Isto aparece uma vez só. A rede não guarda o resultado.
          </p>
          <p className="order-cpf">CPF {result.cpf ?? 'não guardado: a conta foi apagada'}</p>
          {result.accesses.length > 0 && (
            <ul className="order-accesses">
              {result.accesses.map((access) => (
                <li key={access.at}>
                  <span>{formatDateTime(access.at)}</span>
                  <code>{access.ip}</code>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </li>
  )
}
