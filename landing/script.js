// Loaded right after the BB-8 switch (not deferred) so the knob matches the theme before first paint.
const toggle = document.getElementById("theme-toggle");
const themeColor = document.querySelector('meta[name="theme-color"]');

function sync() {
  const dark = document.documentElement.dataset.theme === "dark";
  toggle.checked = dark;
  themeColor.content = dark ? "#000000" : "#ffffff";
  showDemo();
}

// Demo: a light and a dark video share one timeline. The visible one follows the theme (CSS), and a switch
// carries over the time, play state and sound, so the footage just changes appearance.
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const demo = (theme) => document.querySelector(`.preview video[data-demo="${theme}"]`);
const theme = () => (document.documentElement.dataset.theme === "dark" ? "dark" : "light");
const otherTheme = () => (theme() === "dark" ? "light" : "dark");
let demoShown = null;

// Starts fetching the hidden demo (BB-8 hover or focus), so the switch is instant.
function warmDemo() {
  const v = demo(otherTheme());
  if (v && v.readyState === 0 && v.preload === "none") { v.preload = "auto"; v.load(); }
}

// Called inline right after the videos (before either loads), then on every theme change.
function showDemo() {
  const on = demo(theme()), off = demo(otherTheme());
  if (!on || !off || demoShown === on) return;
  const first = demoShown === null;
  demoShown = on;
  if (first) {
    // Only the visible demo loads and autoplays (none under Reduce Motion).
    off.removeAttribute("autoplay"); off.preload = "none";
    on.preload = "metadata"; on.autoplay = !reduceMotion;
    if (reduceMotion) on.removeAttribute("autoplay");
    // re-run media selection with these attributes when the light demo is the visible one (the markup defaults to dark)
    if (on.dataset.demo === "light") { off.load(); on.load(); }
    return;
  }
  const playing = !off.paused, t = off.currentTime, since = performance.now();
  on.muted = off.muted; on.volume = off.volume;
  off.pause();
  if (!playing && t === 0) return; // not started yet: the poster already matches
  const resume = () => {
    // keep the place, plus whatever time passed while the other file loaded
    const late = playing ? (performance.now() - since) / 1000 : 0;
    on.currentTime = on.duration ? (t + late) % on.duration : t;
    if (playing) on.play().catch(() => {});
  };
  if (on.readyState >= 1) resume();
  else { if (on.preload === "none") { on.preload = "auto"; on.load(); } on.addEventListener("loadedmetadata", resume, { once: true }); }
}
toggle.addEventListener("pointerenter", warmDemo);
toggle.addEventListener("focus", warmDemo);

toggle.addEventListener("change", () => {
  const next = toggle.checked ? "dark" : "light";
  document.documentElement.dataset.theme = next;
  try { localStorage.setItem("libreweave-theme", next); } catch {}
  sync();
});

// Follow live OS appearance changes until the visitor picks a theme themselves.
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
  try { if (localStorage.getItem("libreweave-theme")) return; } catch {}
  document.documentElement.dataset.theme = e.matches ? "dark" : "light";
  sync();
});

sync();

document.addEventListener("DOMContentLoaded", () => {
  const play = document.querySelector(".preview-play");
  const videos = document.querySelectorAll(".preview video");
  if (!play || !videos.length) return;
  // Reduce Motion: no autoplay; the demo waits for the Play button.
  if (reduceMotion) videos.forEach((v) => v.pause());
  play.addEventListener("click", () => { const v = demo(theme()); v.muted = false; v.play().catch(() => {}); });
  // Checks paused, since a play event queued before pause() above still fires.
  videos.forEach((v) => v.addEventListener("play", () => { if (!v.paused) play.hidden = true; }));
  // Shown only with JS (it does nothing without it); without JS the native controls stay visible.
  play.hidden = !demo(theme()).paused;
});
