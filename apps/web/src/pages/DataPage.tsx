import { useState } from 'react'
import { useNavigate } from 'react-router'
import { Download, Trash2 } from 'lucide-react'
import { ApiError, api } from '../api'
import { useApp } from '../app-context'
import { PageHead } from '../components/Layout'
import { InfoTip } from '../components/Popover'

/** Regra pétrea 11: os dados são de quem usa. */
export function DataPage() {
  const { me, setMe, toast } = useApp()
  const navigate = useNavigate()
  const [confirming, setConfirming] = useState(false)
  const [nickname, setNickname] = useState('')
  const [deleting, setDeleting] = useState(false)

  if (!me) return null

  async function remove() {
    setDeleting(true)
    try {
      await api.deleteAccount(nickname)
      setMe(null)
      toast('Conta apagada', 'success')
      navigate('/entrar', { replace: true })
    } catch (error) {
      toast(error instanceof ApiError ? error.message : 'Não foi possível apagar a conta.', 'error')
      setDeleting(false)
    }
  }

  return (
    <div className="page">
      <PageHead title="Seus dados">
        <InfoTip label="O que a rede guarda">
          Só o que você fez aqui dentro: seus posts, curtidas, quem você segue, o que assistiu, denúncias e recursos. O CPF
          não fica guardado, só uma impressão digital que impede contas duplicadas.
        </InfoTip>
      </PageHead>

      <div className="data-actions">
        <a className="data-action" href="/api/me/export" download>
          <Download size={20} />
          <span>
            <strong>Baixar meus dados</strong>
            <small>Um arquivo com tudo o que a rede guarda sobre você.</small>
          </span>
        </a>

        {!confirming ? (
          <button type="button" className="data-action is-danger" onClick={() => setConfirming(true)}>
            <Trash2 size={20} />
            <span>
              <strong>Apagar minha conta</strong>
              <small>Leva junto posts, fotos, vídeos, curtidas e seguidores.</small>
            </span>
          </button>
        ) : (
          <div className="data-confirm">
            <p>
              Não tem volta. Ficam só as decisões da moderação e os registros de anúncios, que são da rede e não seus, sem
              o seu apelido. Para confirmar, digite <strong>{me.nickname}</strong>.
            </p>
            <input
              value={nickname}
              onChange={(event) => setNickname(event.target.value)}
              autoFocus
              autoCapitalize="none"
              autoComplete="off"
              aria-label="Seu apelido"
            />
            <div className="data-confirm-actions">
              <button type="button" className="btn btn-sm" onClick={() => setConfirming(false)}>
                Cancelar
              </button>
              <button
                type="button"
                className="btn btn-sm btn-danger"
                disabled={deleting || nickname.trim().toLowerCase() !== me.nickname}
                onClick={remove}
              >
                {deleting ? 'Apagando…' : 'Apagar para sempre'}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
