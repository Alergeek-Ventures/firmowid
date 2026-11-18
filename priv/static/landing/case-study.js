// reveal on scroll, counters, and the hours bars
(function () {
  var reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
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
  if (reduce) document.querySelectorAll('.reveal, .hours').forEach(function (el) { el.classList.add('in'); });
})();
