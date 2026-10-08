(function () {
  var cache = null;
  function dist(a, b, c, d) {
    var p = Math.PI / 180, x = Math.sin((c - a) * p / 2), y = Math.sin((d - b) * p / 2);
    var h = x * x + Math.cos(a * p) * Math.cos(c * p) * y * y;
    return 12742 * Math.asin(Math.sqrt(h));
  }
  function go(btn) {
    var label = btn.textContent;
    btn.textContent = '위치 확인 중...';
    if (!navigator.geolocation) { btn.textContent = '이 브라우저는 위치 기능을 지원하지 않아요'; return; }
    navigator.geolocation.getCurrentPosition(function (pos) {
      var load = cache ? Promise.resolve(cache) : fetch('/assets/dongs.json').then(function (r) { return r.json(); });
      load.then(function (list) {
        cache = list;
        var best = null, bd = 1e9;
        for (var i = 0; i < list.length; i++) {
          var d = dist(pos.coords.latitude, pos.coords.longitude, list[i].a, list[i].o);
          if (d < bd) { bd = d; best = list[i]; }
        }
        if (best && bd < 15) {
          location.href = '/region/' + encodeURIComponent(best.d) + '/' + encodeURIComponent(best.g) + '/' + encodeURIComponent(best.n) + '/';
        } else {
          btn.textContent = '근처에 등록된 동네가 없어요';
        }
      });
    }, function () { btn.textContent = '위치 권한이 필요해요 (' + label + ')'; }, { timeout: 8000 });
  }
  document.addEventListener('click', function (e) {
    var b = e.target.closest && e.target.closest('[data-near-me]');
    if (b) { e.preventDefault(); go(b); }
  });
})();
