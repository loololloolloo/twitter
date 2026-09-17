// Character counter for tweet/reply boxes.
document.querySelectorAll('[data-counter]').forEach(function (box) {
  var max = parseInt(box.getAttribute('maxlength'), 10) || 140;
  var out = box.parentElement.querySelector('[data-counter-output]');
  if (!out) return;
  function update() {
    var left = max - box.value.length;
    out.textContent = left;
    out.classList.toggle('over', left < 0);
  }
  box.addEventListener('input', update);
  update();
});

// Like buttons post via fetch so the timeline does not jump.
document.querySelectorAll('form.js-like').forEach(function (form) {
  form.addEventListener('submit', function (e) {
    e.preventDefault();
    fetch(form.action, {
      method: 'POST',
      headers: { 'Accept': 'application/json' }
    })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var btn = form.querySelector('.act');
        var span = btn.querySelector('span');
        if (span) span.textContent = data.count;
        btn.classList.toggle('liked', data.liked);
      })
      .catch(function () { form.submit(); });
  });
});