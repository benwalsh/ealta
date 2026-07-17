import type { CurrentUser } from '../types'

function csrf(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''
}

// The masthead account control. Signed out: a plain mono "Sign in" that posts
// straight to Google (OmniAuth needs a CSRF-protected POST). Signed in: the avatar
// opens the account side-panel in place — sign-out and the admin link live there.
export function AccountMenu({
  user,
  onOpenAccount,
}: {
  user: CurrentUser | null
  onOpenAccount: () => void
}) {
  if (!user) {
    return (
      <form className="ed-signin" method="post" action="/auth/google_oauth2">
        <input type="hidden" name="authenticity_token" value={csrf()} />
        <button className="ed-signin-btn" type="submit">
          Sign in
        </button>
      </form>
    )
  }

  return (
    <button className="ed-avatar" onClick={onOpenAccount} aria-label="Your account" title={user.name}>
      {user.avatar_url ? (
        <img className="ed-avatar-img" src={user.avatar_url} alt={user.name} referrerPolicy="no-referrer" />
      ) : (
        <span className="ed-avatar-initial">{user.name.trim().charAt(0).toUpperCase()}</span>
      )}
    </button>
  )
}
