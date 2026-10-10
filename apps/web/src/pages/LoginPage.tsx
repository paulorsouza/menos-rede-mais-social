import { useEffect, useState } from 'react'
import type { FormEvent } from 'react'
import { useNavigate, useSearchParams } from 'react-router'
import { ArrowLeft, Dices } from 'lucide-react'
import { ApiError, api } from '../api'
import { useApp } from '../app-context'
import { Avatar } from '../components/Avatar'
import { Wordmark } from '../components/Logo'
import { InfoTip } from '../components/Popover'
import { ThemePicker } from '../components/ThemePicker'
import { REGIONS } from '../regions'
import type { GovBrLevel, Me } from '../types'

type View = 'home' | 'govbr' | 'basic' | 'nickname'

const LEVELS: GovBrLevel[] = ['bronze', 'prata', 'ouro']

export function LoginPage() {
  const { me, setMe } = useApp()
  const navigate = useNavigate()
  const [params] = useSearchParams()
  // ?govbr=apelido: o gov.br já confirmou quem é, falta escolher o apelido.
  const [view, setView] = useState<View>(params.get('govbr') === 'apelido' ? 'nickname' : 'home')
  const [personas, setPersonas] = useState<Me[]>([])
  const [govbrReal, setGovbrReal] = useState(false)
  const govbrFailed = params.get('govbr') === 'erro'

  useEffect(() => {
    api
      .personas()
      .then(({ personas }) => setPersonas(personas))
      .catch(() => setPersonas([]))
    api
      .govbrStatus()
      .then(({ enabled }) => setGovbrReal(enabled))
      .catch(() => setGovbrReal(false))
  }, [])

  // Com o Login Único configurado, o botão leva para o gov.br de verdade.
  function startGovbr() {
    if (govbrReal) window.location.assign('/api/govbr/entrar')
    else setView('govbr')
  }

  useEffect(() => {
    if (me) navigate('/', { replace: true })
  }, [me, navigate])

  if (me) return null

  async function enter(nickname: string) {
    const { account } = await api.login(nickname)
    setMe(account)
  }

  function created(account: Me) {
    setMe(account)
  }

  return (
    <div className="login">
      <div className="login-top">
        <ThemePicker />
      </div>

      <main className="login-center">
        <Wordmark size="xl" />
        <p className="login-tagline">Pública, aberta e sem dono.</p>

        {govbrFailed && view === 'home' && (
          <p className="field-error">Não deu para entrar pelo gov.br. Tente de novo.</p>
        )}

        {view === 'home' && (
          <>
            <div className="persona-row" aria-label="Pessoas de exemplo">
              {personas.map((persona) => (
                <button key={persona.id} type="button" className="persona" onClick={() => enter(persona.nickname)}>
                  <Avatar nickname={persona.nickname} size={52} />
                  <span>{shortName(persona.nickname, personas)}</span>
                </button>
              ))}
            </div>
            <div className="login-cta">
              <button type="button" className="btn btn-primary" onClick={startGovbr}>
                Entrar com gov.br
              </button>
              <button type="button" className="btn btn-ghost" onClick={() => setView('basic')}>
                Conta básica
              </button>
            </div>
          </>
        )}

        {view === 'govbr' && <GovBrForm onBack={() => setView('home')} onCreated={created} />}
        {view === 'basic' && <BasicForm onBack={() => setView('home')} onCreated={created} />}
        {view === 'nickname' && <NicknameForm onBack={() => setView('home')} onCreated={created} />}
      </main>

      {personas.length > 0 && (
        <footer className="login-foot">
          Demonstração · {govbrReal ? 'gov.br em homologação' : 'gov.br simulado'} · dados fictícios
        </footer>
      )}
    </div>
  )
}

function GovBrForm({ onBack, onCreated }: { onBack: () => void; onCreated: (me: Me) => void }) {
  const [cpf, setCpf] = useState('')
  const [nickname, setNickname] = useState('')
  const [level, setLevel] = useState<GovBrLevel>('prata')
  const [region, setRegion] = useState('Campinas/SP')
  const [minor, setMinor] = useState(false)
  const [errors, setErrors] = useState<Record<string, string[]>>({})
  const [sending, setSending] = useState(false)

  async function generateCpf() {
    const { cpf } = await api.testCpf()
    setCpf(cpf)
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    setSending(true)
    setErrors({})
    try {
      const { account } = await api.register({
        cpf,
        nickname,
        govbr_level: level,
        age_band: minor ? 'minor' : 'adult',
        region,
      })
      onCreated(account)
    } catch (error) {
      setErrors(error instanceof ApiError ? error.fieldErrors : { geral: ['Não foi possível criar a conta.'] })
    } finally {
      setSending(false)
    }
  }

  const cpfError = [...(errors.cpf ?? []), ...(errors.cpf_fingerprint ?? [])][0]

  return (
    <form className="login-form" onSubmit={submit}>
      <div className="login-form-head">
        <button type="button" className="icon-btn" onClick={onBack} aria-label="Voltar">
          <ArrowLeft size={18} />
        </button>
        <span>
          gov.br <span className="tag">simulado</span>
        </span>
        <InfoTip label="O que a rede guarda">
          O gov.br só confirma que existe uma pessoa real. O CPF não é guardado: fica só uma impressão digital dele, que
          impede contas duplicadas. No perfil aparece só o apelido.
        </InfoTip>
      </div>

      <div className="input-with-action">
        <input value={cpf} onChange={(e) => setCpf(e.target.value)} placeholder="CPF de teste" required aria-label="CPF de teste" />
        <button type="button" className="icon-btn" onClick={generateCpf} aria-label="Gerar CPF de teste" title="Gerar CPF de teste">
          <Dices size={18} />
        </button>
      </div>
      {cpfError && <span className="field-error">{cpfError}</span>}

      <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="apelido" required aria-label="Apelido" />
      {errors.nickname?.[0] && <span className="field-error">{errors.nickname[0]}</span>}

      <div className="segmented segmented-sm" role="radiogroup" aria-label="Nível da conta gov.br">
        {LEVELS.map((option) => (
          <button key={option} type="button" role="radio" aria-checked={level === option} className="segment" onClick={() => setLevel(option)}>
            {option}
          </button>
        ))}
      </div>

      <select value={region} onChange={(e) => setRegion(e.target.value)} aria-label="Cidade">
        {REGIONS.map((name) => (
          <option key={name}>{name}</option>
        ))}
      </select>

      <label className="option-row">
        <span className="option-label">Menor de idade</span>
        <button
          type="button"
          role="switch"
          aria-checked={minor}
          className={`switch ${minor ? 'is-on' : ''}`}
          onClick={() => setMinor((value) => !value)}
        >
          <span />
        </button>
      </label>

      {errors.geral && <span className="field-error">{errors.geral[0]}</span>}

      <button type="submit" className="btn btn-primary btn-block" disabled={sending}>
        {sending ? 'Criando…' : 'Entrar'}
      </button>
    </form>
  )
}

function BasicForm({ onBack, onCreated }: { onBack: () => void; onCreated: (me: Me) => void }) {
  const [nickname, setNickname] = useState('')
  const [region, setRegion] = useState('Campinas/SP')
  const [errors, setErrors] = useState<Record<string, string[]>>({})

  async function submit(event: FormEvent) {
    event.preventDefault()
    try {
      const { account } = await api.registerBasic({ nickname, region })
      onCreated(account)
    } catch (error) {
      setErrors(error instanceof ApiError ? error.fieldErrors : {})
    }
  }

  return (
    <form className="login-form" onSubmit={submit}>
      <div className="login-form-head">
        <button type="button" className="icon-btn" onClick={onBack} aria-label="Voltar">
          <ArrowLeft size={18} />
        </button>
        <span>Conta básica</span>
        <InfoTip label="O que a conta básica faz">
          Sem gov.br você vê o feed, segue e salva, mas não publica nem recebe por anúncios.
        </InfoTip>
      </div>
      <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="apelido" required aria-label="Apelido" />
      {errors.nickname?.[0] && <span className="field-error">{errors.nickname[0]}</span>}
      <select value={region} onChange={(e) => setRegion(e.target.value)} aria-label="Cidade">
        {REGIONS.map((name) => (
          <option key={name}>{name}</option>
        ))}
      </select>
      <button type="submit" className="btn btn-primary btn-block">
        Criar conta
      </button>
    </form>
  )
}

/** Volta do gov.br com conta nova: só falta o apelido e a cidade. */
function NicknameForm({ onBack, onCreated }: { onBack: () => void; onCreated: (me: Me) => void }) {
  const [nickname, setNickname] = useState('')
  const [region, setRegion] = useState('Campinas/SP')
  const [errors, setErrors] = useState<Record<string, string[]>>({})
  const [sending, setSending] = useState(false)

  async function submit(event: FormEvent) {
    event.preventDefault()
    setSending(true)
    setErrors({})
    try {
      const { account } = await api.govbrRegister({ nickname, region })
      onCreated(account)
    } catch (error) {
      if (error instanceof ApiError) {
        setErrors(Object.keys(error.fieldErrors).length > 0 ? error.fieldErrors : { geral: [error.message] })
      } else {
        setErrors({ geral: ['Não foi possível criar a conta.'] })
      }
    } finally {
      setSending(false)
    }
  }

  return (
    <form className="login-form" onSubmit={submit}>
      <div className="login-form-head">
        <button type="button" className="icon-btn" onClick={onBack} aria-label="Voltar">
          <ArrowLeft size={18} />
        </button>
        <span>Escolha seu apelido</span>
        <InfoTip label="O que a rede guarda">
          O gov.br confirmou que você é uma pessoa real. O nome do gov.br não é lido nem guardado: no perfil aparece só o
          apelido. O CPF fica só como impressão digital e numa cópia selada que só abre com ordem judicial.
        </InfoTip>
      </div>
      <input value={nickname} onChange={(e) => setNickname(e.target.value)} placeholder="apelido" required autoFocus aria-label="Apelido" />
      {errors.nickname?.[0] && <span className="field-error">{errors.nickname[0]}</span>}
      <select value={region} onChange={(e) => setRegion(e.target.value)} aria-label="Cidade">
        {REGIONS.map((name) => (
          <option key={name}>{name}</option>
        ))}
      </select>
      {errors.geral && <span className="field-error">{errors.geral[0]}</span>}
      <button type="submit" className="btn btn-primary btn-block" disabled={sending}>
        {sending ? 'Criando…' : 'Entrar'}
      </button>
    </form>
  )
}

/** "maria.silva" vira "maria"; se a primeira parte se repete ("moderacao"), usa a segunda. */
function shortName(nickname: string, personas: Me[]) {
  const [first, second] = nickname.split('.')
  const repeated = personas.filter((persona) => persona.nickname.split('.')[0] === first).length > 1
  return repeated && second ? second : first
}
