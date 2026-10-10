import { useEffect, useRef, useState } from 'react'

/**
 * Diz se o elemento está visível na tela (pelo menos `threshold` dele).
 * Com `rootMargin`, conta como visível um pouco antes de entrar na tela.
 */
/** Se a aba está à mostra. Com a aba escondida, nada conta como assistido. */
export function usePageVisible() {
  const [visible, setVisible] = useState(() => document.visibilityState === 'visible')

  useEffect(() => {
    const update = () => setVisible(document.visibilityState === 'visible')
    document.addEventListener('visibilitychange', update)
    return () => document.removeEventListener('visibilitychange', update)
  }, [])

  return visible
}

export function useInView<T extends Element>(threshold = 0.6, rootMargin = '0px') {
  const ref = useRef<T>(null)
  const [inView, setInView] = useState(false)

  useEffect(() => {
    const element = ref.current
    if (!element) return
    const observer = new IntersectionObserver(([entry]) => setInView(entry.isIntersecting), { threshold, rootMargin })
    observer.observe(element)
    return () => observer.disconnect()
  }, [threshold, rootMargin])

  return [ref, inView] as const
}
