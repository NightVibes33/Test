// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone runtime validation program. Not a PS4-loadable artifact.
package main
import (
 "crypto/rand"
 "fmt"
 "io"
 "net"
 "os"
 "runtime"
 "sync"
 "time"
)
func check(err error){if err!=nil{panic(err)}}
func main(){
 fmt.Printf("runtime=%s os=%s arch=%s pagesize=%d cpus=%d\n",runtime.Version(),runtime.GOOS,runtime.GOARCH,os.Getpagesize(),runtime.NumCPU())
 var wg sync.WaitGroup
 for i:=0;i<8;i++{wg.Add(1);go func(){defer wg.Done();time.Sleep(time.Millisecond);b:=make([]byte,32);_,err:=rand.Read(b);check(err)}()}
 wg.Wait()
 fmt.Println("goroutines, timer, entropy: PASS")
 ln,err:=net.Listen("tcp4","127.0.0.1:0");check(err);defer ln.Close()
 done:=make(chan error,1)
 go func(){c,e:=ln.Accept();if e==nil{defer c.Close();_,e=c.Write([]byte("ok"))};done<-e}()
 c,err:=net.DialTimeout("tcp4",ln.Addr().String(),time.Second);check(err)
 check(c.SetReadDeadline(time.Now().Add(time.Second)))
 b:=make([]byte,2);_,err=io.ReadFull(c,b);check(err);c.Close();check(<-done)
 if string(b)!="ok"{panic("bad TCP response")}
 fmt.Println("TCP loopback: PASS")
 u,err:=net.ListenPacket("udp4","127.0.0.1:0");check(err);defer u.Close()
 check(u.SetDeadline(time.Now().Add(time.Second)))
 _,err=u.WriteTo([]byte("ok"),u.LocalAddr());check(err)
 n,_,err:=u.ReadFrom(b);check(err);if n!=2||string(b)!="ok"{panic("bad UDP response")}
 fmt.Println("UDP loopback: PASS")
}
