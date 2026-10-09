import type { ReactNode } from 'react'
import { Link, NavLink, Outlet, useNavigate } from 'react-router'
import {
  Bell,
  ChartColumn,
  Clapperboard,
  Database,
  Flame,
  Gavel,
  House,
  LogIn,
  LogOut,
  Plus,
  Scale,
  ShieldCheck,
  SquarePlay,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { useApp } from '../app-context'
import { Avatar, Verified } from './Avatar'
import { LogoMark, Wordmark } from './Logo'
import { Popover } from './Popover'
import { ThemePicker, ThemeSwatches } from './ThemePicker'

interface NavItem {
  to: string
  label: string
  icon: LucideIcon
}

const MAIN: NavItem[] = [
  { to: '/', label: 'Início', icon: House },
  { to: '/shorts', label: 'Shorts', icon: Clapperboard },
  { to: '/videos', label: 'Vídeos', icon: SquarePlay },
  { to: '/em-alta', label: 'Em alta', icon: Flame },
]

const MORE: NavItem[] = [
  { to: '/criador', label: 'Criador', icon: ChartColumn },
  { to: '/transparencia', label: 'Transparência', icon: Scale },
]

export function Layout() {
  return (
    <div className="app">
      <Rail />
      <main className="main">
        <Outlet />
      </main>
      <Dock />
    </div>
  )
}

function Rail() {
  const { me } = useApp()

  return (
    <nav className="rail" aria-label="Menu">
      <Link to="/" className="rail-mark" aria-label="Início">
        <LogoMark size={36} />
      </Link>
      <div className="rail-group">
        {MAIN.map(({ to, label, icon: Icon }) => (
          <NavLink key={to} to={to} end={to === '/'} className="rail-link" data-tip={label} aria-label={label}>
            <Icon size={22} />
          </NavLink>
        ))}
        {me && (
          <NavLink to="/criar" className="rail-link rail-create" data-tip="Criar" aria-label="Criar">
            <Plus size={22} />
          </NavLink>
        )}
      </div>
      <div className="rail-group rail-secondary">
        {MORE.map(({ to, label, icon: Icon }) => (
          <NavLink key={to} to={to} className="rail-link" data-tip={label} aria-label={label}>
            <Icon size={20} />
          </NavLink>
        ))}
      </div>
      <div className="rail-bottom">
        {me ? (
          <UserMenu placement="right" align="end" />
        ) : (
          <>
            <ThemePicker placement="right" align="end" />
            <Link to="/entrar" className="rail-link" data-tip="Entrar" aria-label="Entrar">
              <LogIn size={20} />
            </Link>
          </>
        )}
      </div>
    </nav>
  )
}

function Dock() {
  const { me } = useApp()
  if (!me) return null

  return (
    <nav className="dock" aria-label="Menu">
      <NavLink to="/" end className="dock-link" aria-label="Início">
        <House size={22} />
      </NavLink>
      <NavLink to="/shorts" className="dock-link" aria-label="Shorts">
        <Clapperboard size={22} />
      </NavLink>
      <NavLink to="/criar" className="dock-link dock-create" aria-label="Criar">
        <Plus size={24} />
      </NavLink>
      <NavLink to="/videos" className="dock-link" aria-label="Vídeos">
        <SquarePlay size={22} />
      </NavLink>
      <NavLink to="/em-alta" className="dock-link" aria-label="Em alta">
        <Flame size={22} />
      </NavLink>
    </nav>
  )
}

export function UserMenu({ placement = 'bottom', align = 'end' }: { placement?: 'bottom' | 'right'; align?: 'start' | 'end' }) {
  const { me, logout } = useApp()
  const navigate = useNavigate()

  if (!me) return <ThemePicker />

  return (
    <Popover
      label="Sua conta"
      placement={placement}
      align={align}
      buttonClassName="avatar-btn"
      button={
        <>
          <Avatar nickname={me.nickname} size={34} />
          {me.unread_notices > 0 && <span className="unread-dot" aria-label="Avisos novos" />}
        </>
      }
    >
      {(close) => (
        <div className="menu">
          <Link to={`/u/${me.nickname}`} className="menu-account" onClick={close}>
            <Avatar nickname={me.nickname} size={40} />
            <span>
              <strong className="nickname">
                @{me.nickname}
                {me.verified && <Verified size={14} />}
              </strong>
              <small>{me.verified ? `gov.br ${me.govbr_level}` : 'conta básica'}</small>
            </span>
          </Link>
          <div className="menu-links">
            {me.can_publish && (
              <Link to="/avisos" className="menu-item menu-item-compact" onClick={close}>
                <Bell size={18} />
                <span>Avisos</span>
                {me.unread_notices > 0 && <span className="menu-count">{me.unread_notices}</span>}
              </Link>
            )}
            {me.legal_officer && (
              <Link to="/ordens" className="menu-item menu-item-compact" onClick={close}>
                <Gavel size={18} />
                <span>Ordens judiciais</span>
              </Link>
            )}
            {me.moderator && (
              <Link to="/moderacao" className="menu-item menu-item-compact" onClick={close}>
                <ShieldCheck size={18} />
                <span>Moderação</span>
              </Link>
            )}
            <Link to="/dados" className="menu-item menu-item-compact" onClick={close}>
              <Database size={18} />
              <span>Seus dados</span>
            </Link>
            {MORE.map(({ to, label, icon: Icon }) => (
              <Link key={to} to={to} className="menu-item menu-item-compact" onClick={close}>
                <Icon size={18} />
                <span>{label}</span>
              </Link>
            ))}
          </div>
          <p className="menu-title">Tema</p>
          <ThemeSwatches />
          <button
            type="button"
            className="menu-item menu-item-compact menu-danger"
            onClick={async () => {
              close()
              await logout()
              navigate('/entrar')
            }}
          >
            <LogOut size={18} />
            <span>Sair</span>
          </button>
        </div>
      )}
    </Popover>
  )
}

/** Cabeçalho fixo de cada tela. No celular ele também leva o menu da conta. */
export function PageHead({ title, brand = false, children }: { title?: string; brand?: boolean; children?: ReactNode }) {
  return (
    <header className="page-head">
      <div className="page-head-left">{brand ? <Wordmark /> : <h1>{title}</h1>}</div>
      <div className="page-head-right">
        {children}
        <span className="mobile-only">
          <UserMenu />
        </span>
      </div>
    </header>
  )
}
