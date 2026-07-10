import type { CurrentUser } from '../types'

function csrf(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''
}

// The masthead account control. Signed out: a plain mono "Sign in" that posts
// straight to Google (OmniAuth needs a CSRF-protected POST). Signed in: the avatar
// links to /account — sign-out and the admin link live on that page.
export function AccountMenu({ user }: { user: CurrentUser | null }) {
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
    <a className="ed-avatar" href="/account" aria-label="Your account" title={user.name}>
      {user.avatar_url ? (
        <img className="ed-avatar-img" src={user.avatar_url} alt={user.name} referrerPolicy="no-referrer" />
      ) : (
        <span className="ed-avatar-initial">{user.name.trim().charAt(0).toUpperCase()}</span>
      )}
    </a>
  )
}
