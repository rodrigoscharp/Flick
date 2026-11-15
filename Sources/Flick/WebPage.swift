// Página que o iPhone abre no Safari. Fica embutida no binário.
let webPageHTML = #"""
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Flick">
<meta name="theme-color" content="#000000">
<title>Flick</title>
<style>
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { height: 100%; margin: 0; overflow: hidden; }
  body {
    background: #000; color: #fff;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
    display: flex; flex-direction: column;
    padding: calc(env(safe-area-inset-top) + 18px) 20px calc(env(safe-area-inset-bottom) + 18px);
    -webkit-user-select: none; user-select: none;
  }
  header { display: flex; align-items: center; justify-content: space-between; }
  h1 { font-size: 22px; margin: 0; letter-spacing: -0.02em; }
  #status { font-size: 12px; color: #8e8e93; display: flex; align-items: center; gap: 6px; }
  #dot { width: 8px; height: 8px; border-radius: 50%; background: #ff453a; }
  #dot.on { background: #30d158; }
  main { flex: 1; display: flex; align-items: center; justify-content: center; position: relative; }
  #pick {
    width: 100%; max-width: 320px; aspect-ratio: 3 / 4;
    border: 1.5px dashed #3a3a3c; border-radius: 28px;
    display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px;
    color: #8e8e93; font-size: 15px; text-align: center; padding: 24px;
  }
  #pick strong { color: #fff; font-size: 17px; }
  #pick .plus { font-size: 44px; font-weight: 200; color: #fff; line-height: 1; }
  #card {
    display: none; position: relative;
    width: 100%; max-width: 320px; aspect-ratio: 3 / 4;
    border-radius: 28px; background: #1c1c1e; overflow: hidden;
    touch-action: none; will-change: transform;
    box-shadow: 0 20px 50px rgba(0,0,0,.6);
  }
  #card img, #card video { width: 100%; height: 100%; object-fit: cover; pointer-events: none; }
  #card .generic { width: 100%; height: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; padding: 24px; text-align: center; }
  #card .generic .ext { font-size: 34px; font-weight: 700; letter-spacing: .04em; }
  #card .generic .name { font-size: 14px; color: #8e8e93; word-break: break-all; }
  #badge {
    position: absolute; top: 14px; right: 14px;
    background: rgba(0,0,0,.65); backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px);
    border-radius: 999px; padding: 6px 12px; font-size: 13px; font-weight: 600;
  }
  #hint { text-align: center; font-size: 14px; color: #8e8e93; min-height: 40px; margin: 14px 0; }
  #hint b { color: #fff; font-weight: 600; }
  #bar { height: 4px; border-radius: 2px; background: #1c1c1e; overflow: hidden; opacity: 0; transition: opacity .2s; }
  #bar.on { opacity: 1; }
  #fill { height: 100%; width: 0; background: #0a84ff; transition: width .15s linear; }
  footer { display: flex; gap: 10px; margin-top: 14px; }
  button {
    flex: 1; border: 0; border-radius: 16px; padding: 15px; font-size: 16px; font-weight: 600;
    background: #1c1c1e; color: #fff; font-family: inherit;
  }
  button:active { background: #2c2c2e; }
  button.primary { background: #0a84ff; }
  button.primary:active { background: #0060df; }
  #send { display: none; }
  #sheet {
    position: fixed; inset: 0; background: rgba(0,0,0,.7); display: none;
    align-items: flex-end; padding: 16px; padding-bottom: calc(env(safe-area-inset-bottom) + 16px);
  }
  #sheet.on { display: flex; }
  #sheet .box { width: 100%; background: #1c1c1e; border-radius: 24px; padding: 16px; }
  textarea {
    width: 100%; height: 120px; border: 0; border-radius: 14px; background: #2c2c2e; color: #fff;
    font-size: 16px; padding: 12px; font-family: inherit; resize: none; outline: none;
    -webkit-user-select: text; user-select: text;
  }
  #sheet .row { display: flex; gap: 10px; margin-top: 12px; }
</style>
</head>
<body>
<header>
  <h1>Flick</h1>
  <div id="status"><span id="dot"></span><span id="statusText">procurando o Mac</span></div>
</header>

<main>
  <label id="pick" for="file">
    <span class="plus">+</span>
    <strong>Escolher o que enviar</strong>
    <span>Fotos, vídeos ou qualquer arquivo</span>
  </label>
  <div id="card"><div id="preview"></div><div id="badge"></div></div>
</main>

<div id="hint"></div>
<div id="bar"><div id="fill"></div></div>

<footer>
  <button id="choose">Escolher</button>
  <button id="send" class="primary">Enviar</button>
  <button id="textBtn">Enviar texto</button>
</footer>

<input id="file" type="file" multiple hidden>

<div id="sheet">
  <div class="box">
    <textarea id="text" placeholder="Cole ou digite. Vai direto para a área de transferência do Mac."></textarea>
    <div class="row">
      <button id="cancelText">Cancelar</button>
      <button id="sendText" class="primary">Enviar</button>
    </div>
  </div>
</div>

<script>
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var input = $('file'), pick = $('pick'), card = $('card'), preview = $('preview');
  var badge = $('badge'), hint = $('hint'), bar = $('bar'), fill = $('fill');
  var files = [], sending = false, objectURL = null;

  function ping() {
    fetch('/ping', { cache: 'no-store' }).then(function (r) {
      $('dot').className = r.ok ? 'on' : '';
      $('statusText').textContent = r.ok ? 'Mac conectado' : 'sem conexão';
    }).catch(function () {
      $('dot').className = '';
      $('statusText').textContent = 'sem conexão';
    });
  }
  ping(); setInterval(ping, 4000);

  $('choose').onclick = function () { if (!sending) input.click(); };
  $('send').onclick = function () { if (!sending && files.length) fling(1); };
  hint.innerHTML = 'Toque em <b>Escolher</b> e selecione as fotos';

  input.onchange = function () {
    files = Array.prototype.slice.call(input.files || []);
    input.value = '';
    render();
  };

  function render() {
    if (objectURL) { URL.revokeObjectURL(objectURL); objectURL = null; }
    preview.innerHTML = '';
    $('send').style.display = files.length ? 'block' : 'none';
    $('textBtn').style.display = files.length ? 'none' : 'block';
    if (!files.length) {
      card.style.display = 'none';
      pick.style.display = 'flex';
      return;
    }
    var f = files[0];
    var el;
    if (f.type.indexOf('image/') === 0) {
      objectURL = URL.createObjectURL(f);
      el = document.createElement('img');
      el.src = objectURL;
    } else if (f.type.indexOf('video/') === 0) {
      objectURL = URL.createObjectURL(f);
      el = document.createElement('video');
      el.src = objectURL + '#t=0.1';
      el.muted = true; el.playsInline = true; el.preload = 'metadata';
    } else {
      el = document.createElement('div');
      el.className = 'generic';
      var ext = document.createElement('div');
      ext.className = 'ext';
      var parts = f.name.split('.');
      ext.textContent = parts.length > 1 ? parts.pop().toUpperCase().slice(0, 5) : 'ARQ';
      var name = document.createElement('div');
      name.className = 'name';
      name.textContent = f.name;
      el.appendChild(ext); el.appendChild(name);
    }
    el.style.width = '100%'; el.style.height = '100%';
    preview.style.width = '100%'; preview.style.height = '100%';
    preview.appendChild(el);
    badge.textContent = files.length === 1 ? '1 item' : files.length + ' itens';
    pick.style.display = 'none';
    card.style.display = 'block';
    card.style.transition = 'none';
    card.style.transform = 'scale(.9)';
    card.style.opacity = '0';
    requestAnimationFrame(function () {
      card.style.transition = 'transform .35s cubic-bezier(.2,1.3,.4,1), opacity .2s';
      card.style.transform = '';
      card.style.opacity = '1';
    });
    hint.innerHTML = '<b>Arraste o cartão para o lado</b> ou toque em <b>Enviar</b>';
  }

  // Gesto: arrastar o cartão para fora da tela.
  var startX = 0, startY = 0, dx = 0, dy = 0, lastX = 0, lastT = 0, vx = 0, dragging = false;

  card.addEventListener('pointerdown', function (e) {
    if (sending) return;
    dragging = true;
    startX = lastX = e.clientX; startY = e.clientY; lastT = e.timeStamp; vx = 0; dx = 0; dy = 0;
    card.setPointerCapture(e.pointerId);
    card.style.transition = 'none';
  });

  card.addEventListener('pointermove', function (e) {
    if (!dragging) return;
    dx = e.clientX - startX;
    dy = (e.clientY - startY) * 0.25;
    var dt = e.timeStamp - lastT;
    if (dt > 0) { vx = (e.clientX - lastX) / dt; lastX = e.clientX; lastT = e.timeStamp; }
    card.style.transform = 'translate(' + dx + 'px,' + dy + 'px) rotate(' + (dx / 22) + 'deg)';
  });

  function release() {
    if (!dragging) return;
    dragging = false;
    var far = Math.abs(dx) > window.innerWidth * 0.28;
    var fast = Math.abs(vx) > 0.55 && Math.abs(dx) > 30;
    if (far || fast) {
      fling((fast ? vx : dx) < 0 ? -1 : 1);
    } else {
      card.style.transition = 'transform .4s cubic-bezier(.2,1.4,.4,1)';
      card.style.transform = '';
    }
  }
  function fling(dir) {
    card.style.transition = 'transform .32s cubic-bezier(.4,0,.9,.6)';
    card.style.transform = 'translate(' + (dir * window.innerWidth * 1.4) + 'px,' + (dy - 40) + 'px) rotate(' + (dir * 24) + 'deg)';
    if (navigator.vibrate) { try { navigator.vibrate(12); } catch (err) {} }
    setTimeout(sendAll, 200);
  }

  card.addEventListener('pointerup', release);
  card.addEventListener('pointercancel', release);

  function sendAll() {
    if (sending || !files.length) return;
    sending = true;
    var queue = files.slice();
    var total = queue.reduce(function (s, f) { return s + f.size; }, 0) || 1;
    var done = 0, count = queue.length, index = 0, failed = 0;
    bar.className = 'on'; fill.style.width = '0%';

    function next() {
      if (index >= count) { finish(); return; }
      var f = queue[index];
      hint.textContent = 'Enviando ' + (index + 1) + ' de ' + count + '…';
      var xhr = new XMLHttpRequest();
      xhr.open('POST', '/upload?name=' + encodeURIComponent(f.name || 'arquivo'));
      xhr.upload.onprogress = function (e) {
        fill.style.width = Math.min(100, ((done + e.loaded) / total) * 100) + '%';
      };
      xhr.onload = function () {
        if (xhr.status !== 200) failed++;
        done += f.size; index++; next();
      };
      xhr.onerror = function () { failed++; done += f.size; index++; next(); };
      xhr.send(f);
    }

    function finish() {
      fill.style.width = '100%';
      sending = false;
      files = [];
      render();
      hint.innerHTML = failed
        ? '<b>' + failed + ' de ' + count + ' falharam.</b> Confira o Wi-Fi e tente de novo.'
        : '<b>Enviado.</b> Já está no Mac.';
      setTimeout(function () { bar.className = ''; }, 900);
    }
    next();
  }

  // Texto para a área de transferência do Mac.
  $('textBtn').onclick = function () { $('sheet').className = 'on'; $('text').focus(); };
  $('cancelText').onclick = function () { $('sheet').className = ''; };
  $('sendText').onclick = function () {
    var t = $('text').value;
    if (!t.trim()) return;
    fetch('/text', { method: 'POST', body: t }).then(function (r) {
      $('sheet').className = '';
      $('text').value = '';
      hint.innerHTML = r.ok ? '<b>Texto copiado no Mac.</b>' : '<b>Não deu para enviar o texto.</b>';
    }).catch(function () {
      hint.innerHTML = '<b>Não deu para enviar o texto.</b>';
    });
  };
})();
</script>
</body>
</html>
"""#
