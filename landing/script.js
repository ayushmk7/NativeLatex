// Loaded right after the BB-8 switch (not deferred) so the knob matches the theme before first paint.
const toggle = document.getElementById("theme-toggle");
const themeColor = document.querySelector('meta[name="theme-color"]');

function sync() {
  const dark = document.documentElement.dataset.theme === "dark";
  toggle.checked = dark;
  themeColor.content = dark ? "#000000" : "#ffffff";
}

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
  const video = document.querySelector(".preview video");
  const play = document.querySelector(".preview-play");
  if (!video || !play) return;
  // Reduce Motion: no autoplay; the demo waits for the Play button.
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) { video.removeAttribute("autoplay"); video.pause(); }
  play.addEventListener("click", () => { video.muted = false; video.play().catch(() => {}); });
  // Checks paused, since a play event queued before pause() above still fires.
  video.addEventListener("play", () => { if (!video.paused) play.hidden = true; });
  // Shown only with JS (it does nothing without it); without JS the native controls stay visible.
  play.hidden = !video.paused;
});
