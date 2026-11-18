// reveal on scroll, counters, and the hours bars
(function () {
  var reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  // content stays visible without JavaScript; the script turns on the scroll reveal.
  // If the page has already been painted, what is on screen stays put instead of blinking.
  if (performance.getEntriesByType('paint').length) {
    document.querySelectorAll('.reveal, .hours').forEach(function (el) {
      if (el.getBoundingClientRect().top < innerHeight) el.classList.add('in');
    });
  }
  document.documentElement.classList.add('js');
  var io = new IntersectionObserver(function (es) {
    es.forEach(function (e) {
      if (!e.isIntersecting) return;
      e.target.classList.add('in');
      io.unobserve(e.target);
    });
  }, { threshold: 0.18 });
  document.querySelectorAll('.reveal, .hours').forEach(function (el) { io.observe(el); });

  // once the reader passes the problems, stamp each one as solved
  var probs = document.querySelector('.probs'), bridge = document.getElementById('bridge');
  if (probs && bridge) {
    new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (e.isIntersecting) { probs.classList.add('solved'); bridge.classList.add('in'); }
      });
    }, { rootMargin: '0px 0px -30% 0px' }).observe(bridge);
  }
  // language menu: close on a click outside
  document.addEventListener('click', function (e) {
    document.querySelectorAll('details.lang[open]').forEach(function (d) { if (!d.contains(e.target)) d.open = false; });
  });
  if (reduce) document.querySelectorAll('.reveal, .hours').forEach(function (el) { el.classList.add('in'); });
})();
