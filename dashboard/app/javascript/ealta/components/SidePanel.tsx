import { useEffect, type ReactNode } from 'react'

// The docking shell shared by the account and admin panels. It reuses SpeciesModal's
// lifecycle exactly — Escape closes, the backdrop closes, body scroll locks via
// `body.modal-open` — but docks to the right instead of centring. It APPEARS with a
// quiet opacity fade (never a slide), so the 24h sparkline stays the only moving thing.
// `width` sets the weight: 'slim' for the account card, 'wide' for the admin console.
//
// The head is FIXED and only the body scrolls: the admin console is long enough that a
// scrolling header would carry the close button off-screen, and an action's result banner
// (pinned to the top of the body) would land above the fold where nobody sees it.
export function SidePanel({
  title,
  width = 'slim',
  onClose,
  onBack,
  backLabel,
  children,
}: {
  title: string
  width?: 'slim' | 'wide'
  onClose: () => void
  // Optional parent surface. Admin is opened FROM the account panel, so without this its
  // only exit is closing the lot — you'd have to reopen the avatar to get back.
  onBack?: () => void
  backLabel?: string
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
          <div className="ed-panel-head-left">
            {onBack && (
              <button className="ed-panel-back" onClick={onBack}>
                ← {backLabel}
              </button>
            )}
            <h1 className="acct-h1">{title}</h1>
          </div>
          <button className="ed-panel-close" aria-label="close" onClick={onClose}>
            ×
          </button>
        </div>
        <div className="ed-panel-body">{children}</div>
      </aside>
    </div>
  )
}
