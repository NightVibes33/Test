package main
import("net/http/httptest";"testing";"strings";"image/png")
func TestLoginQR(t *testing.T){
 s:=&loginStatus{state:"NeedsLogin",auth:"https://login.tailscale.com/a/example"}
 request:=func(path,host string)*httptest.ResponseRecorder{r:=httptest.NewRequest("GET","http://"+host+path,nil);w:=httptest.NewRecorder();s.handler().ServeHTTP(w,r);return w}
 w:=request("/","127.0.0.1:8090");if w.Code!=200||!strings.Contains(w.Body.String(),"/qr.png")||w.Header().Get("Cache-Control")!="no-store"{t.Fatal("login page missing")}
 w=request("/qr.png","127.0.0.1:8090");if w.Code!=200{t.Fatal(w.Code)};if _,err:=png.Decode(w.Body);err!=nil{t.Fatal(err)}
 if w=request("/","evil.example:8090");w.Code!=403{t.Fatal("host guard missing")}
 s.update("Running","https://login.tailscale.com/a/example","100.64.0.1")
 if w=request("/qr.png","127.0.0.1:8090");w.Code!=404{t.Fatal("stale login QR")}
 if w=request("/","127.0.0.1:8090");!strings.Contains(w.Body.String(),"100.64.0.1"){t.Fatal("IP missing")}
}
func TestLoginURL(t *testing.T){
 for _,u:=range []string{"http://login.tailscale.com/a/x","https://login.tailscale.com.evil.example/a/x","https://evil.example/a/x","https://user@login.tailscale.com/a/x"}{if validLoginURL(u){t.Fatal(u)}}
 if !validLoginURL("https://login.tailscale.com/a/x"){t.Fatal("valid URL rejected")}
}

func TestConsoleScreenProtocol(t *testing.T){
 s:=&loginStatus{state:"NeedsLogin",auth:"https://login.tailscale.com/a/example"}
 r:=httptest.NewRequest("GET","http://127.0.0.1:8090/screen.txt",nil);w:=httptest.NewRecorder();s.handler().ServeHTTP(w,r)
 lines:=strings.Split(w.Body.String(),"\n")
 if w.Code!=200||len(lines)<7||lines[0]!="PS4TS1"||lines[1]!="NeedsLogin"||lines[4]=="0"{t.Fatal("missing QR matrix")}
 if strings.Contains(w.Body.String(),"https://"){t.Fatal("unexpected raw auth URL")}
 s.update("Running","","100.64.0.1");s.setReady(true);w=httptest.NewRecorder();s.handler().ServeHTTP(w,r)
 if w.Body.String()!="PS4TS1\nRunning\n100.64.0.1\n1\n0\n"{t.Fatal(w.Body.String())}
}
