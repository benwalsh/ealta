import { useEffect, type ReactNode } from 'react'

// The docking shell shared by the account and admin panels. It reuses SpeciesModal's
// lifecycle exactly — Escape closes, the backdrop closes, body scroll locks via
// `body.modal-open` — but docks to the right instead of centring. It APPEARS with a
// quiet opacity fade (never a slide), so the 24h sparkline stays the only moving thing.
// `width` sets the weight: 'slim' for the account card, 'wide' for the admin console.
export function SidePanel({
  title,
  width = 'slim',
  onClose,
  children,
}: {
  title: string
  width?: 'slim' | 'wide'
  onClose: () => void
  children: ReactNode
}) {
  useEffect(() => {
    const onEsc = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onEsc)
    document.body.classList.add('modal-open')
    return () => {
      document.removeEventListener('keydown', onEsc)
      document.body.classList.remove('modal-open')
    }
  }, [onClose])

  return (
    <div className={`ed-panel-root ed-panel-root--${width} is-open`}>
      <div className="ed-panel-scrim" onClick={onClose} />
      <aside className={`ed-panel ed-panel--${width}`} role="dialog" aria-modal="true" aria-label={title}>
        <div className="ed-panel-head">
          <h1 className="acct-h1">{title}</h1>
          <button className="ed-panel-close" aria-label="close" onClick={onClose}>
            ×
          </button>
        </div>
        {children}
      </aside>
    </div>
  )
}
