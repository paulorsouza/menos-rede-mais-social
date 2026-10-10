import { useEffect, useRef, useState } from 'react'

/**
 * Diz se o elemento está visível na tela (pelo menos `threshold` dele).
 * Com `rootMargin`, conta como visível um pouco antes de entrar na tela.
 */
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
