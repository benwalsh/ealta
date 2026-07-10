import { useFollow } from '../favourites'
import { useLang } from '../lang'

// The follow checkbox. A species Subscription in disguise: tick it and you get an
// email when the station next hears the bird. Only shown to signed-in users
// (`enabled`); a line icon in the muted engraved voice, never a filled/glowing
// control. `card` is the compact corner mark on a directory plate; `full` carries
// the word beside it in the species modal.
export function FollowButton({ sci, variant }: { sci: string; variant: 'card' | 'full' }) {
  const { enabled, following, toggle } = useFollow()
  const { t } = useLang()
  if (!enabled) return null

  const on = following(sci)
  const label = on ? t('Following', 'Á leanúint') : t('Follow', 'Lean')

  return (
    <button
      type="button"
      role="checkbox"
      aria-checked={on}
      aria-label={label}
      title={label}
      className={`follow follow-${variant}${on ? ' is-on' : ''}`}
      onClick={(e) => {
        e.stopPropagation() // don't open the modal from a directory card
        toggle(sci)
      }}
    >
      <i className={`ti ${on ? 'ti-square-check' : 'ti-square'}`} aria-hidden="true" />
      {variant === 'full' && <span className="follow-label">{label}</span>}
    </button>
  )
}
