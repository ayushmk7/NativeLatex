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
