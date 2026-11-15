import test from "node:test"
import assert from "node:assert/strict"
import {remainingSeconds, startTimer} from "./cook_timers.mjs"

test("timers use wall time, survive step changes, and cannot be duplicated", () => {
  const timers = new Map()
  startTimer(timers, {id: "step-1", label: "Rice", seconds: 60}, 1000)
  startTimer(timers, {id: "step-2", label: "Greens", seconds: 30}, 11000)
  startTimer(timers, {id: "step-1", label: "Rice", seconds: 60}, 21000)
  assert.equal(remainingSeconds(timers.get("step-1"), 31000), 30)
  assert.equal(remainingSeconds(timers.get("step-2"), 31000), 10)
  assert.equal(remainingSeconds(timers.get("step-1"), 99000), 0)
  assert.equal(timers.size, 2)
})
