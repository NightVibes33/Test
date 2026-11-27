#!/usr/bin/env python3
"""Build the complete pinned upstream daemon, with explicit PS4 adapters.
The original HTML, CSS, JS and portable feature implementations are retained.
"""
import pathlib, shutil, sys
src=pathlib.Path(sys.argv[1]).resolve()
dst=pathlib.Path(sys.argv[2]).resolve()
shutil.copytree(src/"tsd", dst)
shutil.copyfile(src/"LICENSE", dst/"LICENSE.upstream")
def patch(name,old,new):
    p=dst/name
    s=p.read_text()
    if old not in s: raise RuntimeError(f"upstream changed: {name}: {old[:80]}")
    p.write_text(s.replace(old,new,1))
def replaceall(name,old,new):
    p=dst/name
    p.write_text(p.read_text().replace(old,new))
# No PS5-only system notifications, PID killing or ELF-loader helper.
(dst/"console_ps5.go").unlink()
(dst/"instance_ps5.go").unlink()
patch("console_other.go","//go:build !freebsd\n\n","")
patch("instance_other.go","//go:build !freebsd\n\n","")
patch("main.go",'os.Getenv("PS5TS_DATA")','os.Getenv("PS4TS_DATA")')
patch("main.go",'return "/data/tailscale"','return "/data/ps4-tailscale"')
patch("main.go","os.MkdirAll(dataDir, 0o755)","os.MkdirAll(dataDir, 0o700)")
patch("main.go",'logFile, err := openLog','if err := os.Chmod(dataDir, 0o700); err != nil { console.Printf("private storage unavailable: %v\\n", err); os.Exit(1) }\n\tlogFile, err := openLog')
patch("main.go", 'cfg, err := loadConfig(filepath.Join(dataDir, "config.json"))', 'cfg, err := loadConfig(filepath.Join(dataDir, "config.json"))')
# Require local private status by default, remote dashboard only with password.
patch("main.go","d.quit = make(chan struct{})","d.quit = make(chan struct{})\n\tif err := validatePS4Config(d.cfg); err != nil { return err }")
patch("main.go",'go d.watchForUpdates(ctx)','// PS4 builds cannot install PS5 ELF updates.')
patch("main.go",'os.RemoveAll(filepath.Join(dataDir, updateDirName))','// PS5 self-update storage is unused on PS4.')
patch("main.go",'d.logf("login URL: %s", u)','d.logf("Tailscale login link available")')
patch("main.go",'return "http://" + net.JoinHostPort(lanIP(), port)','host, _, _ := net.SplitHostPort(d.cfg.WebAddr)\n\tif host == "127.0.0.1" { return "http://" + net.JoinHostPort(host, port) }\n\treturn "http://" + net.JoinHostPort(lanIP(), port)')
patch("config.go",'Hostname:     "ps5"','Hostname:     "ps4"')
patch("config.go",'WebAddr:      ":8090"','WebAddr:      "127.0.0.1:8090"')
patch("config.go",'CheckUpdates: true,','CheckUpdates: false,\n\t\tAllowFrom: accessOwn,\n\t\tBlockedPorts: []uint16{21,22,23,2121,9020,9021,9090},')
patch("config.go",'cfg.Hostname = "ps5"','cfg.Hostname = "ps4"')
patch("config.go",'cfg.WebAddr = ":8090"','cfg.WebAddr = "127.0.0.1:8090"')
patch("taildrop.go",'const defaultReceiveDir = "/data/tailscale/received"','var defaultReceiveDir = filepath.Join(dataDir, "received")')
patch("inboundudp.go",'var remotePlayUDPPorts = []uint16{9295, 9296, 9297, 9302}','var remotePlayUDPPorts = []uint16{9295, 9296, 9297, 987}')
# Keep outbound local forwards local; no accidental public proxy or debug server.
patch("settings.go","d.cfg = cfg\n\td.mu.Unlock()", """if err := validatePS4Config(cfg); err != nil {
        d.mu.Unlock()
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    d.cfg = cfg
    d.mu.Unlock()""")
patch("settings.go","if err := validListenAddr(f.Listen); err != nil {","if err := ps4LocalListener(f.Listen); err != nil { return err }\n\t\tif err := validListenAddr(f.Listen); err != nil {")
patch("forward.go","port := dst.Port()","port := dst.Port()\n\tif ps4ReservedPort(port) { return nil, false }")
# All remote UI access must have a password; block foreign Host on loopback.
patch("auth.go",'if hash == "" || fromConsole(r) {','if fromConsole(r) {\n\t\treturn true\n\t}\n\tif hash == "" { return false }\n\tif false {')
# Do not install, remove or transmit any PS5 payload.
patch("web.go",'mux.HandleFunc("GET /api/status", d.protect(d.handleStatus))','mux.HandleFunc("GET /api/status", d.protect(d.handleStatus))\n\tmux.HandleFunc("GET /screen.txt", d.handlePS4Screen)')
patch("web.go",'"/api/uninstall":  d.handleUninstall,','"/api/uninstall":  ps4ManualUninstall,')
patch("web.go",'"/api/update":     d.handleUpdate,','"/api/update":     ps4ManualUpdate,')
patch("web.go","return mux\n}","return ps4WebGuard(mux)\n}")
# Port the original entire page, retaining JS, CSS, all panels and real API.
replaceall("status.html","PS5","PS4")
replaceall("status.html","ps5-tailscale","TailScale")
replaceall("status.html","X-PS4-Tailscale","X-PS5-Tailscale") # protocol stays same
replaceall("status.html","/data/tailscale","/data/ps4-tailscale")
replaceall("status.html","9295, 9296, 9297, 9302","9295, 9296, 9297, 987")
replaceall("status.html","the payload loader, Remote Play, anything that listens on the console.","Remote Play and permitted services on the console.")
replaceall("status.html","every open TCP port","permitted TCP ports")
replaceall("status.html","Every other open TCP port on the console is reachable.","Other permitted TCP services are reachable. Debug and payload-loader ports remain blocked.")
replaceall("status.html","ProsperoLight","a compatible Moonlight client")
replaceall("status.html","ProsperoSunshine","a compatible Sunshine host")
patch("status.html",'<p class="sub" id="version"></p>','<p class="sub" id="version"></p><p class="note">Unofficial PS4 port. Hardware runtime is experimental. Console-only operations are not supported yet.</p>')
patch("status.html",'<button id="btn-uninstall" class="danger">Uninstall</button>','<button id="btn-uninstall" class="danger" disabled title="Use the PS4 home screen to remove the PKG">Uninstall (PS4 home screen)</button>')
patch("status.html",'<select id="set-priority">','<select id="set-priority" disabled title="PS4 scheduler integration not validated">')
patch("status.html",'<input type="text" id="set-payloadpath"','<input disabled type="text" id="set-payloadpath"')
patch("status.html",'<input type="checkbox" id="set-updates">','<input disabled type="checkbox" id="set-updates">')
replaceall("status.html","Check GitHub for new releases","Automatic updates (PS4 support pending)")
replaceall("status.html","Payload file to keep up to date","Payload file (PS5-only, unavailable)")
replaceall("status.html","Priority\n","Priority (PS4 support pending)\n")
replaceall("status.html","Send the payload again to start it.","Reopen the PS4 app to start it.")
# Never advertise an upstream PS5 release as a PS4 update.
replaceall("web.go","ps5-tailscale ","ps4-tailscale ")
# Keep Go tests upstream source in checkout; run port-specific tests separately.
(dst/"ps4_adapter.go").write_text(pathlib.Path(__file__).with_name("ps4_adapter.go.txt").read_text())
(dst/"ps4_adapter_test.go").write_text(pathlib.Path(__file__).with_name("ps4_adapter_test.go.txt").read_text())

# Native-only management transport; no browser page or remotely accessible API.
patch("web.go",'mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {','mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {')
patch("web.go",'w.Write(statusHTML)','http.NotFound(w, r)')
patch("web.go",'mux.HandleFunc("GET /screen.txt", d.handlePS4Screen)','mux.HandleFunc("GET /screen.txt", d.handlePS4Screen)\n\tmux.HandleFunc("GET /native", d.nativePage)\n\tmux.HandleFunc("POST /native", d.nativeAction)')
patch("main.go",'if stopRunningInstance(cfg.WebAddr) {\n\t\tlogf("stopped the instance that was already running")\n\t}','// Existing instance is never killed by a new launch.')
patch("forward.go",'if port == d.webPort {','if port == d.webPort {\n\t\treturn nil, false\n\t}\n\tif false {')
(dst/"native_ps4.go").write_text(pathlib.Path(__file__).with_name("native_ps4.go.txt").read_text())
(dst/"native_ps4_test.go").write_text(pathlib.Path(__file__).with_name("native_ps4_test.go.txt").read_text())
