// SPDX-License-Identifier: GPL-3.0-or-later
package main

import (
 "context"
 "fmt"
 "html/template"
 "log"
 "net"
 "net/http"
 "net/url"
 "strings"
 "sync"
 "time"

 qrcode "github.com/skip2/go-qrcode"
 "tailscale.com/client/local"
)

type loginStatus struct {
 mu sync.RWMutex
 state,auth,ip string
 ready bool
}
type statusView struct { State, Auth, IP string; Ready bool }
func(s *loginStatus)setReady(v bool){s.mu.Lock();s.ready=v;s.mu.Unlock()}
func(s *loginStatus)update(state,auth,ip string){
 if !validLoginURL(auth)||state=="Running"{auth=""}
 s.mu.Lock()
 changed:=auth!=""&&auth!=s.auth
 s.state,s.auth,s.ip=state,auth,ip
 s.mu.Unlock()
 if changed{
  if q,err:=qrcode.New(auth,qrcode.Medium);err==nil{
   // Terminal output is local only: do not publish login QR codes in CI.
   log.Printf("Scan this Tailscale login QR from your local terminal:\n%s",q.ToSmallString(false))
  }
 }
}
func validLoginURL(raw string)bool{
 u,err:=url.Parse(raw)
 return err==nil&&u.Scheme=="https"&&u.User==nil&&u.Port()==""&&strings.EqualFold(u.Hostname(),"login.tailscale.com")&&u.Path!=""
}
func monitorLogin(ctx context.Context,lc *local.Client,s *loginStatus){
 t:=time.NewTicker(time.Second);defer t.Stop()
 for{
  req,cancel:=context.WithTimeout(ctx,3*time.Second)
  st,err:=lc.Status(req);cancel()
  if err==nil{
   ip:="";for _,a:=range st.TailscaleIPs{if a.Is4(){ip=a.String();break}}
   s.update(st.BackendState,st.AuthURL,ip)
  }else if ctx.Err()==nil{s.update("Connecting","","")}
  select{case <-ctx.Done():return;case <-t.C:}
 }
}
var statusHTML=template.Must(template.New("status").Parse(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="refresh" content="5"><title>PS4 Tailscale</title><style>body{background:#101827;color:#f1f5f9;font:18px system-ui;margin:2rem auto;padding:1rem;max-width:34rem}main{border:1px solid #475569;border-radius:18px;padding:1.5rem}img{display:block;width:min(280px,100%);margin:1rem auto}a{color:#93c5fd}code{color:#86efac}p{line-height:1.5}</style></head><body><main><h1>PS4 Tailscale</h1><p>Connection: {{.State}}</p>{{if .Auth}}<p>Scan using your iPhone Camera to authorize this device.</p><img alt="Tailscale authorization QR" src="/qr.png"><p><a rel="noreferrer" href="{{.Auth}}">Open Tailscale login</a></p>{{end}}{{if .IP}}<p>Tailnet IP: <code>{{.IP}}</code></p>{{end}}{{if .Ready}}<p>Remote Play relay ready. Use the tailnet IP in PXPlay.</p>{{else}}<p>Waiting for relay startup. Device approval may be required.</p>{{end}}<p>Local status only. No network settings are modified.</p></main></body></html>`))
func(s *loginStatus)handler()http.Handler{
 return http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){
  // Prevent DNS rebinding and cross-origin access to the authorization URL.
  host,_,err:=net.SplitHostPort(r.Host);if err!=nil||host!="127.0.0.1"{http.Error(w,"local only",403);return}
  if r.Method!="GET"{http.Error(w,"GET only",405);return}
  w.Header().Set("Cache-Control","no-store")
  w.Header().Set("Referrer-Policy","no-referrer")
  w.Header().Set("X-Content-Type-Options","nosniff")
  w.Header().Set("Content-Security-Policy","default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'")
  s.mu.RLock();v:=statusView{State:s.state,Auth:s.auth,IP:s.ip,Ready:s.ready};s.mu.RUnlock()
  switch r.URL.Path{
  case "/":
   w.Header().Set("Content-Type","text/html; charset=utf-8")
   if err:=statusHTML.Execute(w,v);err!=nil{log.Printf("status rendering: %v",err)}
  case "/screen.txt":
   w.Header().Set("Content-Type","text/plain; charset=us-ascii")
   w.Write([]byte(screenText(v)))
  case "/qr.png":
   if v.Auth==""{http.NotFound(w,r);return}
   png,err:=qrcode.Encode(v.Auth,qrcode.Medium,320);if err!=nil{http.Error(w,"QR unavailable",500);return}
   w.Header().Set("Content-Type","image/png");w.Write(png)
  default:http.NotFound(w,r)
  }
 })
}
func startStatusPage(addr string,s *loginStatus)(func(),error){
 if addr==""{return func(){},nil}
 host,_,err:=net.SplitHostPort(addr)
 if err!=nil||host!="127.0.0.1"{return nil,&net.AddrError{Err:"status address must use 127.0.0.1",Addr:addr}}
 ln,err:=net.Listen("tcp4",addr);if err!=nil{return nil,err}
 server:=&http.Server{Handler:s.handler(),ReadHeaderTimeout:3*time.Second,WriteTimeout:5*time.Second,IdleTimeout:15*time.Second}
 log.Printf("Local login/status page: http://%s",ln.Addr())
 go func(){if err:=server.Serve(ln);err!=nil&&err!=http.ErrServerClosed{log.Printf("status page: %v",err)}}()
 return func(){server.Close()},nil
}

 // screenText is a bounded read-only protocol for the PS4 frontend.
 // The matrix includes the QR quiet zone from the encoder.
 func screenText(v statusView) string {
  state:=v.State
  switch state {case "Running","NeedsLogin","NeedsMachineAuth","Starting","Connecting","Stopped","NoState":default:state="Connecting"}
  ip:="-";if v.IP!=""{ip=v.IP}
  ready:=0;if v.Ready&&state=="Running"{ready=1}
  var b strings.Builder
  fmt.Fprintf(&b,"PS4TS1\n%s\n%s\n%d\n",state,ip,ready)
  if !validLoginURL(v.Auth)||state=="Running"{b.WriteString("0\n");return b.String()}
  q,err:=qrcode.New(v.Auth,qrcode.Medium)
  if err!=nil{b.WriteString("0\n");return b.String()}
  m:=q.Bitmap()
  if len(m)>121{b.WriteString("0\n");return b.String()}
  fmt.Fprintf(&b,"%d\n",len(m))
  for _,row:=range m{for _,cell:=range row{if cell{b.WriteByte('1')}else{b.WriteByte('0')}};b.WriteByte('\n')}
  return b.String()
 }
