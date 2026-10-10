import type { ReactNode } from 'react'
import { BrowserRouter, Link, Navigate, Route, Routes } from 'react-router'
import { AppProvider, useApp } from './app-context'
import { Layout } from './components/Layout'
import { Empty, Loading } from './components/States'
import { AdvertisePage } from './pages/AdvertisePage'
import { CreatePage } from './pages/CreatePage'
import { CreatorPage } from './pages/CreatorPage'
import { DataPage } from './pages/DataPage'
import { HomePage } from './pages/HomePage'
import { LivePage } from './pages/LivePage'
import { LoginPage } from './pages/LoginPage'
import { ModerationPage } from './pages/ModerationPage'
import { NoticesPage } from './pages/NoticesPage'
import { OrdersPage } from './pages/OrdersPage'
import { ProfilePage } from './pages/ProfilePage'
import { ShortsPage } from './pages/ShortsPage'
import { TransparencyPage } from './pages/TransparencyPage'
import { TrendingPage } from './pages/TrendingPage'
import { VideosPage } from './pages/VideosPage'

function RequireAccount({ children }: { children: ReactNode }) {
  const { me, loadingMe } = useApp()
  if (loadingMe) return <Loading />
  if (!me) return <Navigate to="/entrar" replace />
  return children
}

function NotFound() {
  return (
    <div className="page">
      <Empty>
        Página não encontrada. <Link to="/">Voltar ao início</Link>
      </Empty>
    </div>
  )
}

export default function App() {
  return (
    <AppProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/entrar" element={<LoginPage />} />
          <Route element={<Layout />}>
            <Route index element={<RequireAccount><HomePage /></RequireAccount>} />
            <Route path="shorts" element={<RequireAccount><ShortsPage /></RequireAccount>} />
            <Route path="videos" element={<RequireAccount><VideosPage /></RequireAccount>} />
            <Route path="em-alta" element={<RequireAccount><TrendingPage /></RequireAccount>} />
            <Route path="criar" element={<RequireAccount><CreatePage /></RequireAccount>} />
            <Route path="transmitir" element={<RequireAccount><LivePage /></RequireAccount>} />
            <Route path="criador" element={<RequireAccount><CreatorPage /></RequireAccount>} />
            <Route path="anunciar" element={<RequireAccount><AdvertisePage /></RequireAccount>} />
            <Route path="avisos" element={<RequireAccount><NoticesPage /></RequireAccount>} />
            <Route path="dados" element={<RequireAccount><DataPage /></RequireAccount>} />
            <Route path="moderacao" element={<RequireAccount><ModerationPage /></RequireAccount>} />
            <Route path="ordens" element={<RequireAccount><OrdersPage /></RequireAccount>} />
            <Route path="transparencia" element={<TransparencyPage />} />
            <Route path="u/:nickname" element={<ProfilePage />} />
            <Route path="*" element={<NotFound />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </AppProvider>
  )
}
