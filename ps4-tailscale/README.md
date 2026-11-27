# PS4 Tailscale: experimental Remote Play port
Target: already-jailbroken PS4 14.02, iOS Remote Play via a private tailnet, no PC required **after** the native runtime is proven. This is an initial implementation, not a working console release.

## What is implemented
* Real Tailscale tsnet node, persistent authentication and IPv4 tailnet address.
* Remote Play only: TCP 9295, UDP 9295/9296/9297/987, independent UDP sessions, bounded session count and idle cleanup. No generic forwarding or public port forwarding.
* Local TCP and UDP integration tests; separate read-only PS4 SDK network probe.
* CI builds a Linux development binary, a stock FreeBSD amd64 intermediate (NOT a console payload), and an experimental PS4 SDK probe (not validated for 14.02).

Architecture/reference: [holdmysocks/ps5-tailscale](https://github.com/holdmysocks/ps5-tailscale/tree/be639c6ccde8f456d76dd7eb9978f48837b0a1b8) (GPL-3.0). Uses the same tsnet approach and dependency versions, but not the PS5-specific loader, updater or process changes. [Remote Play port reference](https://chiaki-ng.github.io/chiaki-ng/setup/remoteconnection/). SDK: [ps4-payload-dev/sdk](https://github.com/ps4-payload-dev/sdk/tree/v0.9).

## Development test (not a PS4 install)
Go 1.27.1 required. From this folder: `go test -race ./...`, then `go run . -target 192.168.4.22` on a machine already on the console LAN (replace IP if changed). Authenticate using the URL in the terminal. Configure tailnet policy to allow only your iPhone access to these ports; never publish the auth URL or state directory. In PXPlay, pair locally first and use the printed tailnet IPv4 for manual connection. Verify video and controller traffic. On-console target would be 127.0.0.1 **if** the PS4 Remote Play service accepts loopback.

## Native milestones / safety gates
1. Confirm a PS4 SDK/loader explicitly compatible with 14.02; upstream SDK documentation does not list it. Do not load the experimental probe on 14.02 without confirming compatibility. The probe does not intentionally alter console networking.
2. Capture console socket and runtime ABI behavior and verify Remote Play responds to loopback; if not, assess a console-local address without altering the network.
3. Implement a PS4-compatible Go runtime and launch mechanism, validate threads, TLS, timers, kqueue, sockets, entropy and signals. The PS5 loader and runtime patch are not interchangeable with PS4. No guessed offsets or privilege changes in this branch.
4. Test a native Tailscale login, encrypted peer connectivity, real Remote Play video/audio/controller session, direct versus relayed throughput, game coexistence and clean shutdown.
5. Only then publish a native payload. CI green does not establish console compatibility.

This branch does not change Wi-Fi, DNS, routes, jailbreak, or PSN settings. Native runtime is currently the blocker. No installable Tailscale ELF or PKG is claimed.

## Runtime research (second milestone)

The PS4 SDK v0.9 includes FreeBSD 9.3 headers. Its ucontext header does not
declare the additional 48-byte field in the upstream PS5 Go patch, and its
kevent has the old six-field shape. Header declarations alone do not establish
the 14.02 retail kernel ABI. The CI runtime-research job uses the exact upstream
Go patch at `be639c6`, removes the PS5-only ucontext padding assumption, and
attempts to compile both a standalone runtime smoke program and the relay as
FreeBSD PIE intermediates. These are **not** loadable PS4 payloads. The other
PS5 assumptions in that patch still need hardware validation. No PS5 launcher,
firmware offsets, or kernel patching logic is included.

The ABI probe adds ordinary pthread/TLS, monotonic timer, kqueue, anonymous
read/write memory and entropy checks without changing configuration. It
prints SDK header sizes separately from measured behavior. A successful host
run or SDK build is not a console test. The native probe remains unvalidated
for 14.02. The SDK fork at https://github.com/iHaiDeeZ/ps4-payload-sdk is
a firmware research lead, not proof of compatible elfldr startup or Go.

## QR sign-in and desktop validation
The relay now displays the actual Tailscale authorization URL as a terminal QR and at the local browser page http://127.0.0.1:8090. Scan from another device using its camera, or click the link. Once authorized, the page hides the QR and shows the tailnet address and relay readiness. The local-only listener rejects foreign Host headers and does not expose a control API. No account password is collected. If a local listener is unavailable, use -status "" to disable it; terminal QR still works. On a future native console build, the same page can be opened using the console's local browser; this is not yet a PS4 UI integration.

Windows and Linux CI exercise relay and login UI logic. [shadPS4](https://github.com/shadps4-emu/shadPS4) is suitable for a future normal OpenOrbis homebrew UI/SDK test, but its high-level emulated OS cannot establish that a raw jailbreak payload loader, PS4 14.02 kernel ABI or Sony's Remote Play service works. Do not feed SDK diagnostic payloads into a game emulator and treat a crash as a real-console result. Native desktop testing is not emulation. A stock FreeBSD VM can test generic FreeBSD binaries, not Sony's kernel-specific compatibility.

## OpenOrbis frontend and emulator evidence (major milestone)
The separate normal PS4 homebrew frontend reads a bounded read-only status
protocol at 127.0.0.1:8090/screen.txt, renders real login QR modules, connection
status, IP and relay readiness. It is a frontend, not a native daemon or
installable standalone VPN. If the daemon is absent it reports unavailable.
The fixture executable renders the same UI from a synthetic QR linking to
example.com, labeled as not authenticated. No credentials are included.
CI builds both eboot.bin files with OpenOrbis v0.5.4, tests the protocol
parser and attempts to launch the fixture in pinned shadPS4 v0.21.0 on Linux.
The emulator job publishes logs and a screenshot only after observing the
app's actual flip-presented marker and a visible emulator-owned window.
A fixture screenshot does not demonstrate live Tailscale, Remote Play or
14.02 compatibility. CI may fail because hosted runners lack Vulkan
features or shadPS4 lacks a needed library implementation. The native
daemon still needs a validated console-compatible runtime entry path and
a real PS4 test. No firmware-specific patches or network changes are added.

## Experimental PKG container
The package-frontend CI job builds a proper PS4 homebrew PKG container from
the **live frontend only**, using LibOrbisPkg v0.2 (pinned source, rebuilt
for .NET 8). It generates original artwork, title metadata and a GP4 manifest,
then extracts the result and compares its eboot.bin with the input binary.
The output is named PS4-Tailscale-Frontend-TEST.pkg with a SHA-256 digest.
No demo QR fixture, stock FreeBSD executable, or unvalidated kernel payload
is embedded. This is an experimental UI package, not a standalone native
VPN; 14.02 installation, background runtime and actual Remote Play remain
unverified. No proprietary right.sprx is bundled. Do not claim a working
hardware release based on container validation.

## Integrated runtime launcher research
Unlike the frontend-only package, the runtime-integration job embeds the
actual Go relay in a normal OpenOrbis executable. A separate Go runtime
probe and map-only emulator test use the same loader. The loader validates
ELF bounds and dependencies, applies relative relocations, enforces W^X
using ordinary userspace protection, and refuses execution if mapping fails.
The daemon candidate starts the C UI on a separate signal-blocked thread
and transfers the initial thread to Go using the FreeBSD startup ABI.
It refuses to create state if the normal application sandbox does not allow it.
No kernel permission modifications are included. No real PS4 syscall ABI,
Go signal/TLS behavior, or concurrent UI operation is proven yet. The map-only
emulator test deliberately does not execute raw FreeBSD syscalls because
shadPS4 is not a full PS4 kernel. The native daemon launcher is NOT an
installation release. Background operation during a game remains unproven.
Do not install these unvalidated runtime launchers on 14.02. The old frontend
PKG is only a UI test, not the final app.

The current CI package-runtime job supersedes package-frontend. It takes the
actual daemon launcher (not map-only or fixture), verifies that the complete
Go relay is embedded byte-for-byte, round-trips the PKG, and repeats the
embedded-runtime check on the extracted SELF. The separate title ID avoids
replacing the previous UI-only test. It is still experimental: mapping success
is not proof of working native Go execution or background service support.

## Branding
The runtime package is named TailScale.pkg and its PS4 title is TailScale.
The app icon is the original Tailscale Android store icon from pinned commit
b12728a809e132ce1ad0ba93ae2bed131907663a, verified by its Git blob hash.
This is an unofficial experimental PS4 port, not an official Tailscale release.
Tailscale branding belongs to its owner; native runtime execution on 14.02
remains unverified. Package contents are unchanged by the branding update.

## PS5 dashboard port
The original upstream status.html (be639c6) provides the CSS, panel ordering,
state dot, facts, QR panel, and devices table for the PS4 local web status page.
The OpenOrbis frontend renders a native adaptation of the same dark palette
and login layout. The web UI uses actual local-client peer data and never
displays a fixture as a real login. The browser dashboard remains bound to
127.0.0.1; the console uses its native view. PS5-specific privileged settings,
self-update, uninstall, proxy, Wake-on-LAN and arbitrary forwarding controls
are not exposed because their PS4 backends have not been implemented.

## Full upstream dashboard and feature port
The runtime artifact now builds the entire pinned upstream tsd source, not
the earlier minimal relay. prepare-full-daemon.py preserves the original
status.html, JavaScript, CSS, and portable APIs. Peer testing, Taildrop,
settings, password/session handling, configurable UDP and TCP blocking,
local forwards, Moonlight/Sunshine forwarding, proxy, Wake-on-LAN, logs and
diagnostics use upstream implementations. The dashboard is at 127.0.0.1:8090;
a password is required before exposing it to LAN or tailnet browsers.
The native QR screen reads the same daemon's bounded status endpoint.
PS5 system notifications, process termination, self-update, uninstall helper,
and scheduling changes are not copied as executable console operations;
the related settings are disabled or explicitly rejected. Debug/loader
ports remain blocked, outbound listeners stay loopback-only, and Taildrop
storage stays within the application data directory. The upstream original
tests and adapted PS4 tests are CI prerequisites for packaging. The browser
dashboard is a port of the complete upstream layout, not a new custom UI.
Actual PS4 browser compatibility, Go execution, authentication and game
coexistence still require physical-console validation.
