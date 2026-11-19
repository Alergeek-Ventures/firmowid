// reveal on scroll and the billing period switch
(function () {
  var reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  var revealed = document.querySelectorAll('.reveal');
  // content stays visible without JavaScript; the script turns on the scroll reveal.
  // If the page has already been painted, what is on screen stays put instead of blinking.
  if (performance.getEntriesByType('paint').length) {
    revealed.forEach(function (el) {
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
  revealed.forEach(function (el) { io.observe(el); });
  if (reduce) revealed.forEach(function (el) { el.classList.add('in'); });

  // monthly or yearly prices on the plan cards
  var buttons = document.querySelectorAll('#billing button');
  buttons.forEach(function (button) {
    button.addEventListener('click', function () {
      buttons.forEach(function (other) {
        other.classList.toggle('on', other === button);
        other.setAttribute('aria-pressed', other === button);
      });
      document.querySelector('.plans').classList.toggle('yearly', button.dataset.b === 'y');
      document.querySelectorAll('.plan__price b[data-m]').forEach(function (price) {
        price.textContent = price.dataset[button.dataset.b];
      });
    });
  });
})();
