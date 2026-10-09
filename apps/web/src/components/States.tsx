import type { ReactNode } from 'react'
import { CircleAlert, LoaderCircle } from 'lucide-react'

export function Loading() {
  return (
    <div className="state" aria-label="Carregando">
      <LoaderCircle className="spin" size={22} />
    </div>
  )
}

export function FeedSkeleton() {
  return (
    <div aria-label="Carregando" className="skeleton-list">
      {[0, 1, 2].map((item) => (
        <div key={item} className="skeleton-post">
          <span className="skeleton skeleton-avatar" />
          <span className="skeleton-lines">
            <span className="skeleton skeleton-line" style={{ width: '32%' }} />
            <span className="skeleton skeleton-line" style={{ width: '88%' }} />
            <span className="skeleton skeleton-line" style={{ width: '64%' }} />
          </span>
        </div>
      ))}
    </div>
  )
}

export function ErrorState({ message }: { message: string }) {
  return (
    <div className="state state-error">
      <CircleAlert size={20} />
      <span>{message}</span>
    </div>
  )
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="state">{children}</div>
}
