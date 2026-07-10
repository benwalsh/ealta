import { createContext, useContext, useState, type ReactNode } from 'react'

// Following a bird = a species Subscription on the server. This context holds the
// set of followed sci_names (seeded from the bootstrap) and toggles them against
// the authenticated /favourites endpoint — optimistically, reverting on failure so
// the checkbox never lies about a write that didn't land. `enabled` is false when
// signed out, which is how the checkbox knows to hide itself.

function csrf(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''
}

interface FollowValue {
  enabled: boolean
  following: (sci: string) => boolean
  toggle: (sci: string) => void
}

const FollowContext = createContext<FollowValue>({
  enabled: false,
  following: () => false,
  toggle: () => {},
})

export const useFollow = () => useContext(FollowContext)

export function FollowProvider({
  enabled,
  initial,
  children,
}: {
  enabled: boolean
  initial: string[]
  children: ReactNode
}) {
  const [set, setSet] = useState<Set<string>>(() => new Set(initial))

  const flip = (sci: string, on: boolean) =>
    setSet((prev) => {
      const next = new Set(prev)
      if (on) next.add(sci)
      else next.delete(sci)
      return next
    })

  const toggle = (sci: string) => {
    const wasOn = set.has(sci)
    flip(sci, !wasOn) // optimistic
    fetch('/favourites', {
      method: wasOn ? 'DELETE' : 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': csrf(),
      },
      body: JSON.stringify({ sci_name: sci }),
    })
      .then((res) => {
        if (!res.ok) throw new Error(String(res.status))
      })
      .catch(() => flip(sci, wasOn)) // revert
  }

  return (
    <FollowContext.Provider value={{ enabled, following: (sci) => set.has(sci), toggle }}>
      {children}
    </FollowContext.Provider>
  )
}
