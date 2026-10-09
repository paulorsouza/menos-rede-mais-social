import { useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import { Download, Gavel, ShieldAlert } from 'lucide-react'
import { ApiError, api } from '../api'
import { useApp } from '../app-context'
import { PageHead } from '../components/Layout'
import { InfoTip } from '../components/Popover'
import { Empty, ErrorState, Loading } from '../components/States'
import { formatDate, formatDateTime } from '../format'
import type { IdentificationOrder, OpenedOrder } from '../types'

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
    </div>
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
