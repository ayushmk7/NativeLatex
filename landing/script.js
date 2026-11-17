const toggle = document.getElementById("theme-toggle");

function syncToggle() {
  const dark = document.documentElement.dataset.theme === "dark";
  toggle.setAttribute("aria-checked", String(dark));
  document.querySelector('meta[name="theme-color"]').content = dark ? "#000000" : "#ffffff";
}

toggle.addEventListener("click", () => {
  const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
  document.documentElement.dataset.theme = next;
  try { localStorage.setItem("nativelatex-theme", next); } catch {}
  syncToggle();
});

syncToggle();
