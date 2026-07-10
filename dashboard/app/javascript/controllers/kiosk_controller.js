import { Controller } from '@hotwired/stimulus'

// Drives the /kiosk display: cycles the four cards with a slow cross-fade (no
// page reload, so a monitor/iPad never flashes white), and separately reloads
// the whole page every so often to pull fresh detections. All four cards live
// in the DOM at once; only one carries .is-active.
export default class extends Controller {
  static targets = ['screen']
  static values = {
    dwell: { type: Number, default: 30000 },
    freshen: { type: Number, default: 900000 }, // reload for new data every 15 min
  }

  connect() {
    this.index = 0
    this.show(0)
    this.cycle = setInterval(() => this.advance(), this.dwellValue)
    this.reload = setInterval(() => window.location.reload(), this.freshenValue)
  }

  disconnect() {
    clearInterval(this.cycle)
    clearInterval(this.reload)
  }

  advance() {
    this.index = (this.index + 1) % this.screenTargets.length
    this.show(this.index)
  }

  show(i) {
    this.screenTargets.forEach((el, n) => el.classList.toggle('is-active', n === i))
  }
}
