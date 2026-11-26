// SPDX-License-Identifier: GPL-3.0-or-later
package main

import (
 "context"
 "io"
 "net"
 "sync"
 "time"
)

const idle = 2*time.Minute
const maxSessions = 32

func serveTCP(ctx context.Context, ln net.Listener, target string) error {
 slots := make(chan struct{},maxSessions)
 stop := context.AfterFunc(ctx,func(){ln.Close()})
 defer stop()
 for {
  peer,err := ln.Accept()
  if err != nil { if ctx.Err()!=nil {return nil};return err }
  select {
  case slots<-struct{}{}:
   go func(){
    defer func(){<-slots}()
    defer peer.Close()
    local,err:=(&net.Dialer{Timeout:3*time.Second}).DialContext(ctx,"tcp",target)
    if err!=nil{return}
    defer local.Close()
    done:=context.AfterFunc(ctx,func(){peer.Close();local.Close()})
    defer done()
    pipe(peer,local)
   }()
  default: peer.Close()
  }
 }
}

func pipe(a,b net.Conn) {
 var wg sync.WaitGroup
 copyHalf:=func(dst,src net.Conn){
  defer wg.Done()
  _,err:=io.Copy(dst,src)
  if err!=nil {a.Close();b.Close();return}
  if cw,ok:=dst.(interface{CloseWrite() error});ok {cw.CloseWrite()} else {dst.Close()}
 }
 wg.Add(2)
 go copyHalf(a,b)
 go copyHalf(b,a)
 wg.Wait()
}

type udpSession struct { conn net.Conn; peer net.Addr }

func serveUDP(ctx context.Context, pc net.PacketConn, target string) error {
 var mu sync.Mutex
 sessions:=map[string]*udpSession{}
 var wg sync.WaitGroup
 stop:=context.AfterFunc(ctx,func(){pc.Close()})
 defer stop()
 defer func(){
  pc.Close()
  mu.Lock()
  for _,s:=range sessions{s.conn.Close()}
  mu.Unlock()
  wg.Wait()
 }()
 buf:=make([]byte,65535)
 for {
  n,peer,err:=pc.ReadFrom(buf)
  if err!=nil {if ctx.Err()!=nil{return nil};return err}
  key:=peer.String()
  mu.Lock()
  s:=sessions[key]
  if s==nil && len(sessions)<maxSessions {
   conn,e:=(&net.Dialer{Timeout:3*time.Second}).DialContext(ctx,"udp",target)
   if e==nil {
    s=&udpSession{conn:conn,peer:peer}
    sessions[key]=s
    conn.SetReadDeadline(time.Now().Add(idle))
    wg.Add(1)
    go func(key string,s *udpSession){
     defer wg.Done()
     defer func(){
      s.conn.Close()
      mu.Lock()
      if sessions[key]==s {delete(sessions,key)}
      mu.Unlock()
     }()
     reply:=make([]byte,65535)
     for {
      n,e:=s.conn.Read(reply)
      if e!=nil{return}
      s.conn.SetReadDeadline(time.Now().Add(idle))
      if _,e=pc.WriteTo(reply[:n],s.peer);e!=nil{return}
     }
    }(key,s)
   }
  }
  mu.Unlock()
  if s!=nil {
   s.conn.SetReadDeadline(time.Now().Add(idle))
   s.conn.SetWriteDeadline(time.Now().Add(2*time.Second))
   if _,e:=s.conn.Write(buf[:n]);e!=nil {s.conn.Close()}
  }
 }
}
