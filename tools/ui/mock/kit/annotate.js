// Numbered callouts for "what each button does" pictures. Mark elements with
// data-n="3" (and optionally data-tag="chg|add|keep|prob" for the colour,
// data-at="tc|tl|tr|bl|br|c" for where the number sits, default top centre). Runs only when
// <html> has the class "annotate" (render.py --annotate adds it), so the same
// mockup renders clean and annotated.
(function () {
  function run() {
    if (!document.documentElement.classList.contains('annotate')) return;
    var root = document.querySelector('.ph, .fs, .win') || document.body;
    var base = root.getBoundingClientRect();
    document.querySelectorAll('[data-n]').forEach(function (el) {
      var r = el.getBoundingClientRect();
      var tag = el.getAttribute('data-tag') || 'chg';
      var at = el.getAttribute('data-at') || 'tc';
      var box = document.createElement('div');
      box.className = 'mk-box ' + tag;
      box.style.left = (r.left - base.left - 2) + 'px';
      box.style.top = (r.top - base.top - 2) + 'px';
      box.style.width = (r.width + 4) + 'px';
      box.style.height = (r.height + 4) + 'px';
      var n = document.createElement('div');
      n.className = 'mk-n ' + tag;
      n.textContent = el.getAttribute('data-n');
      var x = at.indexOf('l') >= 0 ? r.left : at.indexOf('r') >= 0 ? r.right : r.left + r.width / 2;
      var y = at.indexOf('b') >= 0 ? r.bottom : at === 'c' ? r.top + r.height / 2 : r.top;
      n.style.left = Math.min(Math.max(x - base.left, 12), base.width - 12) + 'px';
      n.style.top = Math.min(Math.max(y - base.top, 12), base.height - 12) + 'px';
      root.appendChild(box);
      root.appendChild(n);
    });
  }
  if (document.readyState === 'complete') run(); else window.addEventListener('load', run);
})();
