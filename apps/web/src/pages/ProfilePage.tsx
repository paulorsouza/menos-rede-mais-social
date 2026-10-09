import { useEffect, useState } from 'react'
import { useParams } from 'react-router'
import { BadgeCheck, Lock, MapPin } from 'lucide-react'
import { api } from '../api'
import { useApp } from '../app-context'
import { Avatar } from '../components/Avatar'
import { PageHead } from '../components/Layout'
import { InfoTip } from '../components/Popover'
import { PostCard } from '../components/PostCard'
import { Empty, ErrorState, Loading } from '../components/States'
import { formatCompact } from '../format'
import type { Profile } from '../types'

export function ProfilePage() {
  const { nickname = '' } = useParams()
  const { me, toast } = useApp()
  const [profile, setProfile] = useState<Profile | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let active = true
    setProfile(null)
    setError(null)
    api
      .profile(nickname)
      .then((response) => active && setProfile(response))
      .catch(() => active && setError('Perfil não encontrado.'))
    return () => {
      active = false
    }
  }, [nickname])

  async function toggleFollow() {
    if (!me) return toast('Entre para seguir.')
    const result = await api.follow(nickname).catch(() => null)
    if (result) {
      setProfile((current) => current && { ...current, following: result.following, counts: { ...current.counts, ...result.counts } })
    }
  }

  if (error) return <div className="page"><ErrorState message={error} /></div>
  if (!profile) return <div className="page"><Loading /></div>

  const { account, counts } = profile
  const isMe = me?.id === account.id

  return (
    <div className="page">
      <PageHead title="" />

      <section className="profile">
        <Avatar nickname={account.nickname} size={96} />
        <h1 className="profile-name">{account.nickname}</h1>
        <div className="profile-badges">
          {account.verified ? (
            <span className="badge">
              <BadgeCheck size={14} /> verificado
            </span>
          ) : (
            <span className="badge badge-muted">conta básica</span>
          )}
          {account.region && (
            <span className="badge badge-muted">
              <MapPin size={13} /> {account.region}
            </span>
          )}
          <InfoTip label="Sobre o perfil" align="start">
            O perfil mostra só o apelido e o selo. O nome do gov.br e o CPF nunca aparecem.
          </InfoTip>
        </div>
        {account.bio && <p className="profile-bio">{account.bio}</p>}

        <div className="profile-stats">
          <span>
            <strong>{formatCompact(counts.posts)}</strong> posts
          </span>
          <span>
            <strong>{formatCompact(counts.followers)}</strong> seguidores
          </span>
          <span>
            <strong>{formatCompact(counts.following)}</strong> seguindo
          </span>
        </div>

        {!isMe && (
          <button type="button" className={`btn ${profile.following ? 'btn-ghost' : 'btn-primary'}`} onClick={toggleFollow}>
            {profile.following ? 'Seguindo' : 'Seguir'}
          </button>
        )}
      </section>

      <div className="feed">
        {profile.private && (
          <Empty>
            <Lock size={18} /> Perfil privado. Só quem @{account.nickname} segue vê os posts.
          </Empty>
        )}
        {!profile.private && profile.posts.length === 0 && <Empty>Nenhum post ainda.</Empty>}
        {profile.posts.map((post) => (
          <PostCard key={post.id} post={post} showReasons={false} />
        ))}
      </div>
    </div>
  )
}
