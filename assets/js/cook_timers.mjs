export const remainingSeconds = (timer, now = Date.now()) =>
  Math.max(0, Math.ceil((timer.endsAt - now) / 1000))

export function startTimer(timers, {id, label, seconds}, now = Date.now()) {
  if (!timers.has(id) && Number.isFinite(seconds) && seconds > 0) {
    timers.set(id, {id, label, seconds, endsAt: now + seconds * 1000})
  }
}

export const CookTimers = {
  mounted() {
    this.timers = new Map()
    this.onStart = event => {
      startTimer(this.timers, event.detail)
      this.renderTimers()
    }
    document.addEventListener("cook:start-timer", this.onStart)
    this.interval = setInterval(() => this.renderTimers(), 250)
  },
  destroyed() {
    clearInterval(this.interval)
    document.removeEventListener("cook:start-timer", this.onStart)
  },
  renderTimers() {
    if (!this.timers.size) return
    for (const timer of this.timers.values()) {
      if (!timer.element) {
        if (this.timers.size === 1) this.el.replaceChildren()
        const card = document.createElement("div")
        card.className = "surface p-4 space-y-2"
        const label = document.createElement("p")
        label.className = "text-sm text-secondary-ink"
        label.textContent = timer.label
        const clock = document.createElement("p")
        clock.className = "font-heading text-3xl tabular-nums"
        clock.setAttribute("role", "timer")
        clock.setAttribute("aria-label", timer.label)
        const status = document.createElement("p")
        status.className = "text-sm text-muted"
        status.setAttribute("aria-live", "polite")
        const reset = document.createElement("button")
        reset.className = "action"
        reset.textContent = "Restart"
        reset.addEventListener("click", () => {
          timer.endsAt = Date.now() + timer.seconds * 1000
          timer.announced = false
          status.textContent = ""
          this.renderTimers()
        })
        card.append(label, clock, status, reset)
        this.el.append(card)
        timer.element = {clock, status}
      }
      const left = remainingSeconds(timer)
      timer.element.clock.textContent = left ? `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}` : "Done!"
      if (!left && !timer.announced) {
        timer.announced = true
        timer.element.status.textContent = `${timer.label} timer finished.`
      }
    }
  }
}
