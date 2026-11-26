package main

import (
 "context"
 "io"
 "net"
 "testing"
 "time"
)

func TestTCPRelay(t *testing.T){
 target,err:=net.Listen("tcp4","127.0.0.1:0");if err!=nil{t.Fatal(err)};defer target.Close()
 go func(){ c,e:=target.Accept();if e==nil{defer c.Close();io.Copy(c,c)} }()
 front,err:=net.Listen("tcp4","127.0.0.1:0");if err!=nil{t.Fatal(err)}
 ctx,cancel:=context.WithCancel(context.Background());defer cancel()
 done:=make(chan error,1);go func(){done<-serveTCP(ctx,front,target.Addr().String())}()
 c,err:=net.Dial("tcp",front.Addr().String());if err!=nil{t.Fatal(err)};defer c.Close()
 c.SetDeadline(time.Now().Add(3*time.Second))
 if _,err=c.Write([]byte("ps4"));err!=nil{t.Fatal(err)}
 b:=make([]byte,3);if _,err=io.ReadFull(c,b);err!=nil||string(b)!="ps4"{t.Fatalf("%q %v",b,err)}
 cancel();select{case err:=<-done:if err!=nil{t.Fatal(err)};case <-time.After(3*time.Second):t.Fatal("shutdown timeout")}
}
func TestUDPRelayIsolatesPeers(t *testing.T){
 target,err:=net.ListenPacket("udp4","127.0.0.1:0");if err!=nil{t.Fatal(err)};defer target.Close()
 go func(){b:=make([]byte,4096);for{n,a,e:=target.ReadFrom(b);if e!=nil{return};target.WriteTo(b[:n],a)}}()
 front,err:=net.ListenPacket("udp4","127.0.0.1:0");if err!=nil{t.Fatal(err)}
 ctx,cancel:=context.WithCancel(context.Background());defer cancel()
 done:=make(chan error,1);go func(){done<-serveUDP(ctx,front,target.LocalAddr().String())}()
 for _,msg:=range []string{"first-client","second-client"}{
  c,e:=net.Dial("udp4",front.LocalAddr().String());if e!=nil{t.Fatal(e)};defer c.Close()
  c.SetDeadline(time.Now().Add(3*time.Second))
  if _,e=c.Write([]byte(msg));e!=nil{t.Fatal(e)}
  b:=make([]byte,100);n,e:=c.Read(b);if e!=nil||string(b[:n])!=msg{t.Fatalf("got %q %v",b[:n],e)}
 }
 cancel();select{case err:=<-done:if err!=nil{t.Fatal(err)};case <-time.After(3*time.Second):t.Fatal("shutdown timeout")}
}
