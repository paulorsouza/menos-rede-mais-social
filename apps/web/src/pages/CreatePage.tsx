import { useNavigate } from 'react-router'
import { Lock } from 'lucide-react'
import { useApp } from '../app-context'
import { Composer } from '../components/Composer'
import { PageHead } from '../components/Layout'
import { InfoTip } from '../components/Popover'
import type { PostKind } from '../types'

const DESTINATION: Record<PostKind, string> = { text: '/', photo: '/', video: '/videos', short: '/shorts' }

export function CreatePage() {
  const { me } = useApp()
  const navigate = useNavigate()

  if (!me) return null

  if (!me.can_publish) {
    return (
      <div className="page">
        <PageHead title="Criar" />
        <div className="locked">
          <Lock size={26} />
          <h2>Contas básicas não publicam</h2>
          <p className="muted">Entre com o gov.br para ganhar o selo e publicar.</p>
        </div>
      </div>
    )
  }

  return (
    <div className="page">
      <PageHead title="Criar">
        <InfoTip label="Como publicar">
          Texto sozinho tem até 140 caracteres e não aceita resposta. Anexe uma foto ou um vídeo e o tipo sai do arquivo:
          vídeo em pé de até 3 minutos vira short. Não existe tema nem tag: quem vê o post é decidido por quem curte.
          {!me.can_monetize && ' Receber por anúncio exige gov.br prata ou ouro.'}
        </InfoTip>
      </PageHead>

      <Composer onPublished={(post) => navigate(DESTINATION[post.kind])} />
    </div>
  )
}
