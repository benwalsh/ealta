import { Controller } from '@hotwired/stimulus'

// Reveals the species detail overlay once its turbo-frame has loaded content,
// and tears it down (clearing the frame) on close so the next open re-fetches.
export default class extends Controller {
  static targets = ['frame']

  open() {
    if (this.frameTarget.children.length === 0) return
    this.element.classList.add('is-open')
    document.body.classList.add('modal-open')
  }

  close() {
    this.element.classList.remove('is-open')
    document.body.classList.remove('modal-open')
    this.frameTarget.removeAttribute('src')
    this.frameTarget.innerHTML = ''
  }
}
