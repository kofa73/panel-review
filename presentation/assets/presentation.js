(function () {
  const links = Array.from(document.querySelectorAll("a[data-next], a[data-prev]"));
  const next = document.querySelector("a[data-next]");
  const previous = document.querySelector("a[data-prev]");

  document.addEventListener("keydown", function (event) {
    if (["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement.tagName)) return;
    if ((event.key === "ArrowRight" || event.key === "PageDown" || event.key === " ") && next) {
      event.preventDefault();
      window.location.href = next.href;
    }
    if ((event.key === "ArrowLeft" || event.key === "PageUp") && previous) {
      event.preventDefault();
      window.location.href = previous.href;
    }
    if (event.key.toLowerCase() === "f" && document.documentElement.requestFullscreen) {
      document.documentElement.requestFullscreen();
    }
  });
})();
