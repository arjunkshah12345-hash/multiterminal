// Smooth anchor scrolling that accounts for the sticky nav.
document.addEventListener("click", (e) => {
  const a = e.target.closest('a[href^="#"]');
  if (!a) return;
  const id = a.getAttribute("href");
  if (id.length < 2) return;
  const el = document.querySelector(id);
  if (!el) return;
  e.preventDefault();
  const y = el.getBoundingClientRect().top + window.pageYOffset - 70;
  window.scrollTo({ top: y, behavior: "smooth" });
  history.replaceState(null, "", id);
});
