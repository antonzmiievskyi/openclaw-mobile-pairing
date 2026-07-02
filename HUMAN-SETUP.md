# Connect the OpenClaw mobile app to your VM over Tailscale — human setup guide

This is the full step-by-step guide **for a person** (you run it over SSH on the
VM). The short agent skill (`SKILL.md`) points the user here. **The OpenClaw agent
cannot do the pairing itself** — see "Two hard constraints" for why — so this part
is done by hand.

The OpenClaw mobile app must reach the gateway over an **encrypted** connection
(`wss://`). On a home machine the phone and the host share a LAN, so a plain
`ws://<lan-ip>` is allowed. On a **VPS or cloud VM** (public IP, no shared LAN)
there is no private path, so OpenClaw refuses to embed `ws://` in the setup code.
The fix is a TLS front in front of the gateway — this guide uses **Tailscale
Serve**. The common hard case is a VM that must **also** serve a **remote HTTP
client** (a server-side back-end that reaches the gateway over the network), so the
target end-state keeps both paths alive at once:

```
Web/API client → a remote back-end ─http─► <public-ip>:18789 ─┐
                                                               │
                                                     [gateway: 0.0.0.0:18789]
                                                               ▲
Phone (iOS) ─wss─► tailscale serve (:443, TLS) ─http─► 127.0.0.1:18789 ─┘
```

`0.0.0.0` covers **both** `127.0.0.1` (the Tailscale Serve side) and the VM's
network IP (the remote-client side), which is why the two clients coexist on one
gateway.

## Two hard constraints (learn these first)

1. **`gateway.tailscale.mode=serve` requires a loopback bind.** The validator
   rejects `customBindHost=0.0.0.0` together with `mode=serve`:
   ```
   gateway.bind must resolve to loopback when gateway.tailscale.mode=serve
   ```
   So `serve` mode and a public/`0.0.0.0` bind **cannot coexist**. BUT — `mode=serve`
   only affects **setup-code generation** (it makes `openclaw qr` embed the
   `wss://<magic-dns>` URL). Once the phone is paired it reuses that stored `wss://`
   endpoint, and Tailscale Serve keeps proxying to `127.0.0.1:18789` **regardless of
   the flag**. So after pairing you can (and should) turn `mode` off.

2. **A loopback bind rejects every connection that is not from the same host.**
   `127.0.0.1:18789` only accepts traffic originating on the box itself. Any
   **remote** client — a server-side back-end, another VPS, or a browser that reaches
   the gateway through such a back-end — gets `connection refused`. This is exactly
   why a working remote client "breaks" the moment you move the gateway to loopback,
   and why the agent cannot pair the phone for you: generating the code needs the
   loopback flip, which drops the very chat the agent talks to you on.

## The stable coexistence end-state

Keep the gateway on `0.0.0.0`, leave `gateway.tailscale.mode` **unset**, and keep
`tailscale serve` running in the background:

```jsonc
// ~/.openclaw/openclaw.json  (gateway section)
{
  "port": 18789,
  "mode": "local",
  "bind": "custom",
  "customBindHost": "0.0.0.0",
  "auth": { "mode": "token", "token": "…redacted…" }
  // gateway.tailscale.mode is UNSET on purpose
}
```

- The remote client reaches `<public-ip>:18789`; the phone reaches `wss://<magic-dns>`
  → Serve → `127.0.0.1:18789`. Both work at once.
- You only need to flip back to loopback + `mode=serve` **temporarily** to mint a
  new pairing code (see "Re-pairing later").

> If nothing off-host uses this gateway (a personal box with no remote client), you
> can instead just stay on `127.0.0.1` + `mode=serve` — it is more secure (the port
> is never on the public IP). Everything below about coexistence is only needed when
> a remote client must reach the gateway.

## Before you start

- The host can run `openclaw` and `tailscale`.
- A Tailscale account with **HTTPS enabled** for the tailnet
  (`https://login.tailscale.com/admin/dns` → *Enable HTTPS*).
- The **phone is joined to the same tailnet** and is **online** right now
  (`tailscale status` must show it online, not "offline").

**Never used Tailscale? Do the next section first** — it walks you through the
account, the two nodes, and HTTPS. If you already have all three, skip to
"First-time setup".

## Get terminal (SSH) access first

Every step in this guide runs in a shell **on the VM**, so you need SSH access to it
before anything else:

- You need the VM's **public IP**, its **login user** (commonly `ubuntu` on Ubuntu
  images), and your **SSH key** installed on the VM.
- No SSH key yet? Generate one: `ssh-keygen -t ed25519`. Your **public** key is
  `~/.ssh/id_ed25519.pub` — share only that line, **never** the private key.
- If your key is not on the VM yet, have whoever manages the VM add your public key to
  its `~/.ssh/authorized_keys`. (If you can already chat with the OpenClaw agent on
  that VM, it can append the key for you — just ask it.)
- Connect: `ssh <user>@<public-ip>` (e.g. `ssh ubuntu@<public-ip>`).

Run everything below inside that SSH session.

## New to Tailscale? Set this up first

**What it is.** Tailscale is a private, encrypted network — a "mesh VPN" built on
WireGuard. It lets two of your devices (here: your phone and this VM) talk to each
other directly and safely, as if on the same LAN, without opening any port to the
public internet. Each device you add is a **node**. You need three things before the
technical steps: an account, this VM joined as a node, and your phone joined as a
node — all under the **same** account.

1. **Create a free account.** Open `https://login.tailscale.com` and sign in with
   Google, Microsoft, or GitHub (personal use is free).
2. **Enable HTTPS for your tailnet.** In the admin console: **DNS → Enable HTTPS**.
   This lets Tailscale Serve get a TLS certificate for your VM's name later. Without
   it the phone gets "TLS handshake failed".
3. **Join this VM as a node.** Done in "First-time setup → Phase 0" below
   (`sudo tailscale up`, then open the printed link in a browser and approve). After
   it, `tailscale status` shows the VM with a `100.x.x.x` address and a MagicDNS name
   like `myhost.tailXXXXXX.ts.net`.
4. **Join your phone as a node.** Install the **Tailscale** app from the App Store /
   Play Store, open it, and sign in with the **same** account. The phone then appears
   in `tailscale status`.
5. **Check both are online.** On the VM run `tailscale status` — you should see both
   the VM and the phone as online (not "offline"). If the phone shows offline, open
   the Tailscale app on it and toggle it on.

Only after both nodes are online **and** HTTPS is enabled do the pairing steps below
work. Then continue to "First-time setup".

## First-time setup

Replace `<magic-dns>` / `<tailnet-ip>` / `<public-ip>` with this host's values
(from `tailscale status` and `ip a`).

**Phase 0 — Tailscale + Serve (once):**
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up                                  # open the printed link in a browser to authorize this node
tailscale status                                   # note tailnet IP + MagicDNS name
sudo tailscale serve --bg http://127.0.0.1:18789   # TLS front on :443 → loopback
tailscale serve status                             # confirm https://<magic-dns> → http://127.0.0.1:18789
```
`tailscale serve` is a **separate** thing from OpenClaw's `mode=serve` — the config
flag never starts it. It survives reboots on its own.

**Phase 1 + 2 — pair the phone (run the script — recommended):**

Pairing needs the gateway on loopback for a moment, which takes the remote client
down. `pair.sh` (bundled with this skill) does the flip, shows the QR, and — on
success, on error, **or on Ctrl-C** — **always** restores the `0.0.0.0` bind. That
guaranteed restore is what stops you from getting stuck in the broken loopback state
(the #1 way this setup takes the back-end down).
```bash
cd ~/.openclaw/skills/openclaw-mobile-pairing   # folder that holds pair.sh (adjust if yours differs)
chmod +x pair.sh                                 # first time only
./pair.sh
```
Scan the QR with the app, then press Enter. The script restores `0.0.0.0`
automatically — confirm with "Verify both paths" below.

<details>
<summary><strong>Manual fallback</strong> — only if the script isn't available</summary>

Run these by hand. You **must** complete Phase 2 afterwards, or the remote client
stays down — this is the single most common way to break the back-end.

*Phase 1 — mint the code (loopback + mode=serve):*
```bash
openclaw config set gateway.bind loopback          # loopback bind FIRST — mode=serve is rejected while bind is public
openclaw gateway restart                           # apply the loopback bind before touching mode
openclaw config set gateway.tailscale.mode serve   # now this passes; would fail if bind were still public
openclaw gateway restart
curl -v https://<magic-dns>/                       # expect 200 (first call ~10–15s: cert issue)
openclaw qr                                         # scannable QR (or: openclaw qr --setup-code-only for a text code)
```
> **Order matters.** Set `gateway.bind loopback` and **restart** *before* setting
> `gateway.tailscale.mode serve` — the validator checks the running bind the moment
> you set `mode`, so setting `mode` first fails with `gateway.bind must resolve to
> loopback`. `bind=loopback` is more robust than `customBindHost=127.0.0.1` (the
> latter is ignored unless `gateway.bind` is already `custom`).

*Phase 2 — restore the public bind (DO NOT SKIP):*
```bash
openclaw config unset gateway.tailscale.mode       # if unset is rejected: set gateway.tailscale.mode off
openclaw config set gateway.bind custom            # undo the loopback bind from Phase 1
openclaw config set gateway.customBindHost 0.0.0.0  # public bind used by both the remote client and Tailscale Serve
openclaw gateway restart                           # the remote client's chat is down for these few seconds
```
</details>

The phone stays paired and keeps working through Tailscale Serve — restoring the
`0.0.0.0` bind does not disconnect it.

## Verify both paths

```bash
ss -tlnp | grep 18789                              # must be 0.0.0.0:18789 (not 127.0.0.1)
curl -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18789/   # 200 (Tailscale side)
curl -o /dev/null -w '%{http_code}\n' http://<public-ip>:18789/ # 200 (remote-client side)
tailscale serve status                             # https://<magic-dns> → http://127.0.0.1:18789
```

## Known false alarm

`openclaw gateway status` reports, when bound to `0.0.0.0`:
```
Connectivity probe: failed
  connect failed: SECURITY ERROR: Cannot connect to "0.0.0.0" over plaintext ws://.
```
This is the CLI's built-in probe refusing to talk to its own gateway over plaintext
`ws://` on a public bind. **The gateway is healthy** — prove it with the two `curl`
checks above (both return 200). Ignore this line in this configuration.

## Re-pairing the app later

Need a fresh code later (new phone, expired code)? Just run the script again — it
re-flips to loopback, shows a new QR, and restores `0.0.0.0`:
```bash
cd ~/.openclaw/skills/openclaw-mobile-pairing && ./pair.sh
```
(By hand: repeat the manual Phase 1 + Phase 2 from "First-time setup". Remote-client
downtime is a few seconds per restart, ~10–20s total — do it in a low-traffic window
if it matters.)

## If the phone can't use Tailscale / you'd rather not

Two alternatives to the coexistence state above, by where the remote client lives:

- **Client can join your tailnet:** keep the gateway on loopback + `mode=serve`, and
  point the client at `http://<tailnet-ip>:18789` (or the `wss://<magic-dns>` URL).
  All traffic rides Tailscale WireGuard; nothing is exposed publicly. (Not an option
  for a shared server-side back-end you can't add to a personal tailnet.)
- **Client cannot join the tailnet:** use the `0.0.0.0` + `mode` unset state above —
  that is the only way both work at once.

## Is the port actually exposed? Check, don't assume

`0.0.0.0` means the gateway *binds* every interface — it does **not** by itself mean
the port is open to the internet. Two layers usually protect it already:

- **The gateway requires a token** (`gateway.auth.mode = token`), so reaching the port
  is not enough — a request still needs the auth token.
- **On managed / cloud platforms the port is typically firewalled** to allowed sources
  by the platform (a "security group"), configured off the VM. A host firewall like
  `ufw` often has **no effect** on such VMs, so don't rely on it.

**Do not test from the VM itself** — a local `curl` to your own public IP hits the
local socket and always "succeeds", telling you nothing about internet exposure.
Instead test from a machine that is **NOT** this VM and **NOT** on your tailnet:
```bash
nc -z -w5 <public-ip> 18789     # or: curl -m8 -o /dev/null -w '%{http_code}\n' http://<public-ip>:18789/
```
- **Times out / refused** → the port is already firewalled from the internet. Nothing
  to do.
- **Connects / returns a code** → the port is open to the internet. If that is not
  intended, restrict inbound TCP `18789` to your remote client's IP(s) at whatever
  firewall layer actually applies (usually the cloud security group; not host `ufw`).
  Re-test from outside after.

## Recovery playbook

**Remote client / browser chat broken (the remote back-end can't reach the gateway):**
1. `openclaw gateway status` — running? If not: `openclaw gateway restart`
   (ignore the "Connectivity probe: failed" false alarm — see above).
2. `ss -tlnp | grep 18789` — must be `0.0.0.0:18789`. If it shows `127.0.0.1`, the
   bind got reset:
   ```bash
   openclaw config unset gateway.tailscale.mode
   openclaw config set gateway.bind custom
   openclaw config set gateway.customBindHost 0.0.0.0
   openclaw gateway restart
   ```
3. From the remote client's network: `curl -v http://<public-ip>:18789/` → expect
   200. If refused, check your cloud / provider firewall (security group) — or a host
   firewall like `ufw`, if your VM actually uses one.

**Phone chat broken (app disconnected):**
1. `tailscale status` — is the VM online in the tailnet? Is the phone online?
2. `tailscale serve status` — should show `https://<magic-dns> → http://127.0.0.1:18789`.
   If empty, re-arm: `sudo tailscale serve --bg http://127.0.0.1:18789`.
3. From the VM: `curl -v https://<magic-dns>/` → expect 200.

**Both broken?** The gateway process likely died or the config changed — start from
step 1 of both playbooks.

**VM was reset / reprovisioned by your provider?** All manual setup on the box is gone
(Tailscale uninstalled, OpenClaw config reset) — redo everything in this doc. If it
happens often, snapshot a golden image or automate the setup.

## Key commands

| What | Command |
|---|---|
| OpenClaw config file | `~/.openclaw/openclaw.json` |
| Read config keys | `openclaw config get gateway` |
| Change a key | `openclaw config set gateway.customBindHost 0.0.0.0` |
| Restart gateway | `openclaw gateway restart` |
| Gateway status | `openclaw gateway status` (see "Known false alarm") |
| See what is listening | `ss -tlnp \| grep 18789` |
| Start Tailscale Serve | `sudo tailscale serve --bg http://127.0.0.1:18789` |
| Serve status | `tailscale serve status` |
| Tailnet status | `tailscale status` |
| Gateway logs | `/tmp/openclaw/openclaw-YYYY-MM-DD.log` |
| Pair / re-pair the phone | `./pair.sh` (flips to loopback, shows QR, auto-restores `0.0.0.0`) |

## Gotchas that cost real time

- `gateway.tailscale.mode=serve` **forces a loopback bind** (validator error with
  `0.0.0.0`), and it **only affects QR generation** — turn it off after pairing so a
  remote client can reach the gateway.
- A loopback bind refuses all off-host connections — that is what breaks a remote
  client the moment you rebind.
- `tailscale serve` is a **separate** command from OpenClaw's `mode=serve` flag; start
  it yourself with `sudo tailscale serve --bg http://127.0.0.1:18789`.
- `openclaw gateway status` shows `Connectivity probe: failed` on a `0.0.0.0` bind —
  false alarm; verify with `curl`.
- `openclaw qr` refuses to run on a public bind (the token could be sniffed over
  plaintext `ws://`) — flip to loopback to generate a code.
- The first HTTPS request to the MagicDNS name is slow (~10–15s, cert issuance); later
  ones are instant.

## What a correct end-state looks like (checklist)

On a VM serving both a remote client and the paired phone, expect all of these
(substitute your own `<public-ip>` / `<magic-dns>`):

- `openclaw config get gateway.customBindHost` → `0.0.0.0`
- `openclaw config get gateway.tailscale` → `{}` (i.e. `mode` is **unset**)
- `ss -tlnp | grep 18789` → `0.0.0.0:18789` (a `node` process, gateway running)
- `curl -o /dev/null -w '%{http_code}' http://127.0.0.1:18789/` → `200` (phone path)
- `curl -o /dev/null -w '%{http_code}' http://<public-ip>:18789/` → `200` (remote-client path)
- `curl -o /dev/null -w '%{http_code}' https://<magic-dns>/` → `200` (TLS front)
- `tailscale serve status` → `https://<magic-dns> → http://127.0.0.1:18789`
- `openclaw gateway status` → `Runtime: running` **plus** the harmless
  `Connectivity probe: failed` line (see "Known false alarm")

This shape was verified on a live VM; the flow is generic — every user substitutes
their own host, IPs, MagicDNS name, and device.
