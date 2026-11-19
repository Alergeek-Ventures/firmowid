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

  // cookie consent: the banner stays until the visitor chooses. The choice is the same cookie
  // the rest of the site reads. Telemetry waits in a <template> and loads only after "accept".
  var consent = document.getElementById('consent');
  if (consent && !/(^| )cookie_consent=/.test(document.cookie)) {
    consent.hidden = false;
    consent.addEventListener('click', function (e) {
      var button = e.target.closest('[data-consent]');
      if (!button) return;
      var secure = location.protocol === 'https:' ? ';Secure' : '';
      document.cookie = 'cookie_consent=' + button.dataset.consent + ';path=/;max-age=' + 365 * 24 * 60 * 60 + ';SameSite=Lax' + secure;
      consent.hidden = true;
      var template = document.getElementById('telemetry-script');
      var waiting = template && template.content.querySelector('script');
      if (button.dataset.consent === 'accepted' && waiting) {
        // a script cloned out of a template may not run, so it is built anew with the same attributes
        var script = document.createElement('script');
        Array.prototype.forEach.call(waiting.attributes, function (a) { script.setAttribute(a.name, a.value); });
        document.body.appendChild(script);
      }
    });
  }
})();
