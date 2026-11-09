import Foundation

enum DriveWebPage {
    static let html = #"""
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
    <title>DriveDeck Display</title>
    <style>
    :root{color-scheme:dark;--bg:#080b14;--surface:#181d2b;--text:#eef2fb;--muted:#a8b2ca;--accent:#558dff}
    *{box-sizing:border-box}
    body{font:16px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:var(--bg);color:var(--text);margin:0}
    header{height:69px;background:var(--surface);display:flex;align-items:center;justify-content:space-between;gap:14px;padding:12px 22px}
    header .brand{display:flex;gap:12px;align-items:center;font-weight:700;font-size:22px}
    .logo{display:grid;place-items:center;background:linear-gradient(135deg,#4f85ff,#734cff);width:43px;height:43px;border-radius:12px}
    .status{font-size:12px;color:var(--muted)}
    .app{display:flex;min-height:calc(100vh - 95px)}
    .dock{background:#111624;display:flex;flex-direction:column;padding:13px 8px;gap:12px;min-width:76px}
    .dock button{border:0;background:#1e2638;border-radius:16px;color:#fff;font-size:25px;height:54px;cursor:pointer}
    .dock button.active{background:#315fc2}
    main{padding:21px;width:100%;max-width:1200px;margin:0 auto}
    h1{font-size:32px;margin:0 0 10px}
    .disclaimer{color:var(--muted);font-size:12px}
    .cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:18px 0}
    .card{background:var(--surface);border-radius:20px;padding:24px;min-height:170px}
    .card h2{margin:0 0 14px;font-size:18px}
    .card button,.actions button{background:#376dd7;border:0;color:white;border-radius:12px;padding:11px 16px;font:inherit;cursor:pointer}
    .card button:disabled{opacity:.5;cursor:default}
    .tuner{font:300 58px -apple-system,system-ui;color:#ffaa36}
    .small{color:var(--muted);font-size:12px;line-height:1.5}
    input[type=text],input[type=url]{background:#101626;color:white;border:1px solid #46536f;padding:12px;border-radius:9px;width:100%;font:inherit}
    input[type=range]{width:100%}
    .controls{display:flex;gap:10px;flex-wrap:wrap;align-items:center}
    .controls button{border:none;border-radius:14px;background:#353f56;color:#fff;padding:11px 20px;font:inherit}
    .gauges{display:flex;gap:15px}
    .gauges div{background:var(--surface);border-radius:16px;padding:25px;flex:1;text-align:center;font:300 42px system-ui}
    .gauges span{display:block;font-size:13px;color:#aaa}
    .hidden{display:none}
    footer{font-size:11px;padding:7px 15px;background:var(--surface);color:var(--muted)}
    @media(max-width:610px){main{padding:12px}.dock{min-width:55px;padding:8px 5px}.dock button{height:42px;font-size:20px}
    .card{min-height:120px;padding:17px}.tuner{font-size:45px}}
    </style></head>
    <body>
    <header><div class="brand"><span class="logo">🚘</span><span id="car-name">DriveDeck</span></div>
    <span class="status" id="connection">Local dashboard • Connecting...</span></header>
    <div class="app">
    <nav class="dock" aria-label="Screen selector">
    <button data-page="home" class="active" title="Home">▦</button>
    <button data-page="radio" title="Radio">♫</button>
    <button data-page="maps" title="Maps">⌖</button>
    <button data-page="cluster" title="Cluster">◉</button>
    </nav>
    <main>
    <section id="home">
      <h1>DriveDeck</h1>
      <p class="disclaimer">LOCAL BROWSER SCREEN. Not a decoded CarPlay / Android Auto projection.</p>
      <div class="cards">
       <div class="card"><h2>Maps</h2><p class="small">Use your phone's navigation app.</p>
         <button onclick="show('maps')">Open maps tile</button></div>
       <div class="card"><h2>Internet Radio</h2><p class="small">Stream live audio directly in this browser.</p>
         <button onclick="show('radio')">Tune radio</button></div>
       <div class="card"><h2>Instrument Cluster</h2><p class="small">Simulated gauges, no vehicle connection.</p>
         <button onclick="show('cluster')">Open cluster</button></div>
      </div>
      <p class="small" id="headunit">Receiver mode is not available. This browser display works over local Wi-Fi.</p>
    </section>
    <section id="radio" class="hidden">
      <h1>Internet Radio</h1><p class="disclaimer">FM/AM dial is a visual simulator only.</p>
      <div class="card">
       <div class="controls"><button id="band" onclick="flipBand()">FM</button><span id="frequency" class="tuner">101.9</span><span id="unit">MHz</span></div>
       <input id="dial" type="range" min="87.5" max="108" value="101.9" step=".2" aria-label="Demo dial">
       <p class="small">Changing FM/AM frequency does not tune an RF receiver.</p>
       <input id="stream-url" type="url" placeholder="https://station.example/live.mp3" aria-label="Audio stream URL">
       <p class="controls"><button id="play" onclick="play()">▶ Play Stream</button><button onclick="pause()">⏸ Pause</button></p>
       <label>Volume <input type="range" id="volume" min="0" max="1" step=".01" value=".8"></label>
       <p class="small" id="radio-state">Enter a direct audio-stream URL.</p>
      </div>
    </section>
    <section id="maps" class="hidden">
      <h1>Maps</h1>
      <div class="card">
        <h2>Navigation</h2><p class="small">Open the actual Maps app on this device. Embedded third-party map tiles are not bundled.</p>
        <a href="https://maps.apple.com/" target="_blank" rel="noopener" style="color:#87baff">Open Apple Maps ↗</a>
      </div>
    </section>
    <section id="cluster" class="hidden">
      <h1>Instrument cluster</h1><p class="disclaimer">SIMULATED VEHICLE DATA</p>
      <div class="gauges"><div id="speed">0<span>MPH</span></div><div id="rpm">0<span>RPM</span></div></div>
      <div class="card"><label>Demo speed <input id="speed-slider" type="range" min="0" max="140" value="0"></label>
      <p class="small">No CarPlay Ultra decoded frames, CAN bus, or vehicle telemetry are present.</p></div>
    </section>
    </main></div>
    <footer id="footer">DriveDeck browser mirror • HTTP on trusted local networks only</footer>
    <audio id="audio" preload="none"></audio>
    <script>
      const $=id=>document.getElementById(id),audio=$('audio');
      let band='FM',ws;
      function show(id){
        document.querySelectorAll('main section').forEach(s=>s.classList.toggle('hidden',s.id!==id));
        document.querySelectorAll('.dock button').forEach(b=>b.classList.toggle('active',b.dataset.page===id));
      }
      document.querySelectorAll('[data-page]').forEach(b=>b.addEventListener('click',()=>show(b.dataset.page)));
      function flipBand(){band=band==='FM'?'AM':'FM';$('band').textContent=band;
        const input=$('dial');input.min=band==='FM'?'87.5':'530';input.max=band==='FM'?'108':'1710';
        input.step=band==='FM'?'.2':'10';input.value=band==='FM'?'101.9':'1000';
        $('unit').textContent=band==='FM'?'MHz':'kHz';showFrequency();}
      function showFrequency(){$('frequency').textContent=band==='FM'?Number($('dial').value).toFixed(1):Math.round(Number($('dial').value))}
      $('dial').addEventListener('input',showFrequency);
      async function play(){
        const link=$('stream-url').value.trim();
        try{const u=new URL(link);if(!['http:','https:'].includes(u.protocol))throw new Error('Use a http(s) direct stream URL');
          audio.src=u.href;audio.volume=Number($('volume').value);await audio.play();
          $('radio-state').textContent='Playing browser stream';}catch(e){$('radio-state').textContent='Could not play: '+e.message;}
      }
      function pause(){audio.pause();$('radio-state').textContent='Paused'}
      $('volume').addEventListener('input',e=>audio.volume=Number(e.target.value));
      $('speed-slider').addEventListener('input',e=>{const n=Number(e.target.value);
        $('speed').innerHTML=n+'<span>MPH</span>';$('rpm').innerHTML=(n*38)+'<span>RPM</span>';});
      fetch('/status',{cache:'no-store'}).then(r=>r.json()).then(s=>{
        $('car-name').textContent=s.carName||'DriveDeck';$('footer').textContent='DriveDeck '+s.version+' • '+s.ipStatus;
        if(!s.cluster){document.querySelector('[data-page="cluster"]').classList.add('hidden');}
        try{ws=new WebSocket('ws://'+location.hostname+':'+s.websocketPort+'/');
          ws.onopen=()=>$('connection').textContent='Dashboard connected • WebSocket live';
          ws.onmessage=e=>{try{const data=JSON.parse(e.data);if(data.car)$('car-name').textContent=data.car;}catch(_){}};
          ws.onerror=()=>$('connection').textContent='Dashboard via HTTP • WebSocket unavailable';
        }catch(e){$('connection').textContent='Dashboard via HTTP';}
      }).catch(()=>$('connection').textContent='Status unavailable');
    </script></body></html>
    """#
}
