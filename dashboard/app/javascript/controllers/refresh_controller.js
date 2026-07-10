import { Controller } from '@hotwired/stimulus'

// Periodically reloads the collage so new detections appear — but holds off
// while a species modal is open, so reading a bird's detail isn't interrupted.
// (Replaces a meta http-equiv="refresh", which couldn't be paused.)
export default class extends Controller {
  static values = { interval: { type: Number, default: 15000 } }

  connect() {
    this.timer = setInterval(() => this.tick(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    if (document.getElementById('detail-modal')?.classList.contains('is-open')) return
    window.location.reload()
  }
}
