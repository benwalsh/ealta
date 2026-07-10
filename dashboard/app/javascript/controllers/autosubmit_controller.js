import { Controller } from '@hotwired/stimulus'

// Submit the form as soon as a control changes — so a checkbox toggle saves itself
// without a separate button. Used by the account page's daily-email checkboxes.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
