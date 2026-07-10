import { Controller } from '@hotwired/stimulus'

// Toggles the species description between English and Irish (Gaeilge) prose.
// Only mounted when both languages are available.
export default class extends Controller {
  static targets = ['body', 'button']

  show(event) {
    const lang = event.currentTarget.dataset.lang
    this.bodyTargets.forEach((b) => (b.hidden = b.dataset.lang !== lang))
    this.buttonTargets.forEach((b) =>
      b.setAttribute('aria-current', b.dataset.lang === lang ? 'true' : 'false'),
    )
  }
}
