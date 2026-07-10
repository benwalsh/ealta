import { Controller } from '@hotwired/stimulus'

// Plays a species' call/song sample inline (a Wikimedia Commons audio URL),
// toggling the chip between "song" and "playing". One tap plays, another stops.
export default class extends Controller {
  static targets = ['audio', 'label']

  connect() {
    this.audioTarget.addEventListener('ended', () => this.reset())
  }

  toggle() {
    if (this.audioTarget.paused) {
      this.audioTarget.currentTime = 0
      this.audioTarget.play()
      this.element.classList.add('playing')
      this.labelTarget.textContent = 'playing'
    } else {
      this.reset()
    }
  }

  reset() {
    this.audioTarget.pause()
    this.element.classList.remove('playing')
    this.labelTarget.textContent = 'song'
  }
}
