import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "counter"]

  connect() {
    this.update()
    this.inputTarget.addEventListener("input", this.update.bind(this))
  }

  update() {
    const length = this.inputTarget.value.length
    const maxLength = this.inputTarget.maxLength || 200
    this.counterTarget.textContent = length
    this.counterTarget.parentElement.classList.toggle("warning", length > maxLength * 0.9)
  }
}



