import { Controller } from '@hotwired/stimulus'

// Caption the hovered/tapped bird only — bilingual name + its count in the
// current window, formatted ("Spideog · European Robin · 1,204 calls today").
// Blank when no bird is focused; nothing persists. The Inky panel has no JS,
// so it shows no caption (we'll revisit a wall caption separately).
export default class extends Controller {
  static targets = ['caption']
  static values = { window: String }

  caption(event) {
    const { ga, en, count } = event.currentTarget.dataset
    const names = [ga, en].filter((s) => s && s.length).join(' · ')
    const n = Number(count).toLocaleString()
    const word = count === '1' ? 'call' : 'calls'
    const phrase = this.windowValue ? ` ${this.windowValue}` : ''
    this.captionTarget.innerHTML =
      `<span class="ct-name">${names}</span> · ` +
      `<span class="ct-n">${n}</span> <span class="ct-w">${word}${phrase}</span>`
    this.captionTarget.setAttribute('aria-hidden', 'false')
  }

  clear() {
    this.captionTarget.setAttribute('aria-hidden', 'true')
  }

  // Tapping a bird loads its detail into the modal's turbo-frame. Driven here
  // rather than via an SVG <a> because Turbo mishandles SVG anchor hrefs.
  open(event) {
    const { sci } = event.currentTarget.dataset
    if (!sci) return
    const frame = document.getElementById('detail')
    if (frame) frame.src = `/species/${encodeURIComponent(sci)}`
  }
}
