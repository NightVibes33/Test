// SPDX-License-Identifier: GPL-3.0-or-later
// A deliberately small userspace Remote Play node. The console runtime is
// a separate porting milestone; a stock FreeBSD binary is NOT a PS4 payload.
package main

import (
 "context"
 "flag"
 "fmt"
 "log"
 "net"
 "net/netip"
 "os"
 "os/signal"
 "path/filepath"
 "syscall"
 _ "golang.org/x/crypto/x509roots/fallback"
 "tailscale.com/tsnet"
)

func main() {
 target := flag.String("target", "127.0.0.1", "PS4 IPv4 address (loopback or private)")
 state := flag.String("state", "./ps4-tailnet-state", "private persistent identity directory")
 name := flag.String("hostname", "ps4-remoteplay", "tailnet device name")
 flag.Parse()
 addr, err := netip.ParseAddr(*target)
 if err != nil || !addr.Is4() || !(addr.IsLoopback() || addr.IsPrivate()) {
  log.Fatal("target must be a literal loopback or private IPv4 address")
 }
 dir, err := filepath.Abs(*state)
 if err != nil { log.Fatal(err) }
 if err = os.MkdirAll(dir, 0700); err != nil { log.Fatal(err) }
 if err = os.Chmod(dir, 0700); err != nil { log.Fatal(err) }
 ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
 defer cancel()
 if err := run(ctx, addr.String(), dir, *name); err != nil { log.Fatal(err) }
}

func run(ctx context.Context, target, dir, name string) error {
 ctx, cancel := context.WithCancel(ctx)
 defer cancel()
 node := &tsnet.Server{Dir:dir, Hostname:name, UserLogf:log.Printf, AuthKey:os.Getenv("TS_AUTHKEY")}
 defer node.Close()
 // Interactive login URL is written to the local console by tsnet.
 // Auth keys may be supplied through TS_AUTHKEY, never committed.
 if _, err := node.Up(ctx); err != nil { return fmt.Errorf("tailnet login: %w",err) }
 ip4, _ := node.TailscaleIPs()
 if !ip4.IsValid() { return fmt.Errorf("no tailnet IPv4 address") }
 log.Printf("tailnet address %s; Remote Play target %s",ip4,target)
 // Only these ports are exposed. No payload loader, FTP, proxy or admin UI.
 tcp, err := node.Listen("tcp", net.JoinHostPort(ip4.String(),"9295"))
 if err != nil { return err }
 defer tcp.Close()
 errs := make(chan error,5)
 go func(){ errs <- serveTCP(ctx,tcp,net.JoinHostPort(target,"9295")) }()
 for _, port := range []string{"9295","9296","9297","987"} {
  pc, err := node.ListenPacket("udp",net.JoinHostPort(ip4.String(),port))
  if err != nil { return fmt.Errorf("UDP %s: %w",port,err) }
  defer pc.Close()
  go func(p net.PacketConn, destination string){ errs <- serveUDP(ctx,p,destination) }(pc,net.JoinHostPort(target,port))
 }
 log.Print("Remote Play relay ready; use the tailnet IP in your client")
 select {
 case <-ctx.Done(): return nil
 case err := <-errs: return err
 }
}
