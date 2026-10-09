import { useEffect, useRef, useState } from 'react'

/** Diz se o elemento está visível na tela (pelo menos `threshold` dele). */
export function useInView<T extends Element>(threshold = 0.6) {
  const ref = useRef<T>(null)
  const [inView, setInView] = useState(false)

  useEffect(() => {
    const element = ref.current
    if (!element) return
    const observer = new IntersectionObserver(([entry]) => setInView(entry.isIntersecting), { threshold })
    observer.observe(element)
    return () => observer.disconnect()
  }, [threshold])

  return [ref, inView] as const
}
