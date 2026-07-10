import { Controller } from '@hotwired/stimulus'

// A small menu popover (the account avatar). Toggles .is-open, and closes on an
// outside click or Escape.
export default class extends Controller {
  static targets = ['button']

  toggle(event) {
    event.stopPropagation()
    this.element.classList.toggle('is-open')
    this.sync()
  }

  close() {
    if (!this.element.classList.contains('is-open')) return
    this.element.classList.remove('is-open')
    this.sync()
  }

  sync() {
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute('aria-expanded', this.element.classList.contains('is-open'))
    }
  }

  connect() {
    this.onOutside = (e) => {
      if (!this.element.contains(e.target)) this.close()
    }
    this.onKey = (e) => {
      if (e.key === 'Escape') this.close()
    }
    document.addEventListener('click', this.onOutside)
    document.addEventListener('keydown', this.onKey)
  }

  disconnect() {
    document.removeEventListener('click', this.onOutside)
    document.removeEventListener('keydown', this.onKey)
  }
}
