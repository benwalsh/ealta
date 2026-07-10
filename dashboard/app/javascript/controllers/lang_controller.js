import { Controller } from '@hotwired/stimulus'

// Site-wide chrome/nav language toggle. Flips <html data-lang> live (CSS shows
// the matching .lang-* spans, hides the other) and persists the choice in a
// cookie so the server seeds data-lang on the next render — no flash of the
// wrong language.
export default class extends Controller {
  set(event) {
    const to = event.currentTarget.dataset.to
    if (to !== 'en' && to !== 'ga') return
    document.documentElement.setAttribute('data-lang', to)
    document.documentElement.setAttribute('lang', to)
    document.cookie = `ui_lang=${to}; path=/; max-age=31536000; samesite=lax`
    this.element
      .querySelectorAll('[data-to]')
      .forEach((b) => b.classList.toggle('is-on', b.dataset.to === to))
  }
}
