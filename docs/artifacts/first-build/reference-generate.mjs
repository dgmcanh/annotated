import { getStroke } from 'perfect-freehand'
const opts = { simulatePressure: true, size: 8.5, thinning: 0.6, smoothing: 0.5,
  streamline: 0.5, easing: (t) => Math.sin((t * Math.PI) / 2), last: true }
const curvy = []
for (let i = 0; i <= 60; i++) curvy.push([i * 7, 40 * Math.sin(i / 6) + i * 1.5])
for (let i = 0; i <= 20; i++) curvy.push([420 - i * 9, 60 + i * 2])
const zigzag = []
for (let i = 0; i < 40; i++) zigzag.push([i * 12, i % 2 ? 0 : 90])
const slow = []
for (let i = 0; i < 30; i++) slow.push([100 + i * 0.6, 100 + i * 0.4])   // barely moving: fat, min-length filter
const cases = {
  dot: [[10, 10]],
  two: [[0, 0], [80, 40]],
  three: [[0, 0], [40, 10], [80, 0]],
  curvy, zigzag, slow,
  dup: [[5,5],[5,5],[5,5],[60,60],[60,60],[120,10]],
}
const outFor = (pts) => getStroke(pts, opts)
console.log(JSON.stringify(Object.fromEntries(
  Object.entries(cases).map(([k, v]) => [k, { input: v, out: outFor(v) }]))))
