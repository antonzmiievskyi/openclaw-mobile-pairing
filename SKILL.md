---
name: openclaw-mobile-pairing
description: Use when the user wants to connect / pair the OpenClaw mobile app (iOS or Android) to this machine — mentions the phone app, pairing, a QR or setup code, Tailscale, or hits "TLS handshake failed / must use https/wss". This skill explains what pairing involves and guides the parts that are safe to do over chat, then hands the actual pairing off to a human runbook. It does NOT pair the phone through chat — see the hard limit below.
---

# Helping the user pair the OpenClaw mobile app

The user wants to connect the phone/mobile app to this machine (or generate a
pairing QR / setup code). Your job is to **explain and prepare**, not to complete
the pairing yourself.

## Hard limit — you cannot finish pairing through this chat

Generating the pairing code needs the gateway flipped to a **loopback bind**
(`gateway.customBindHost=127.0.0.1` + `gateway.tailscale.mode=serve`). A loopback
bind drops **every off-host connection** — including the remote back-end that
relays *this very chat* to you. So if you start the pairing flip you cut the channel
you use to talk to the user, and you can't even deliver the code back to them.

**Never** run these while serving this chat:
```
openclaw config set gateway.customBindHost 127.0.0.1
openclaw config set gateway.tailscale.mode serve
```
They disconnect the user. Do not claim you paired the phone — you can only prepare
and guide.

## What to do instead

1. **Explain in one plain sentence, no jargon:** "Connecting the phone app needs a
   private, secure network (Tailscale) between your phone and this machine, plus a
   one-time setup code you enter on the phone."

2. **Help with the parts that do NOT touch the gateway bind** — these are safe over
   chat, so do as much as the user wants:
   - **First ask: "Have you used Tailscale before?"** If not, do NOT dump commands on
     them. Relay the `HUMAN-SETUP.md` section **"New to Tailscale? Set this up first"**
     inline: say in one plain sentence that Tailscale is a **free** private, encrypted
     network (a "mesh VPN") between the phone and this VM, that it is a **separate
     third-party service** they must sign up for, and that a personal account is free.
     Give them `https://login.tailscale.com` and the sign-in options (Google /
     Microsoft / GitHub). Do NOT give any `tailscale ...` command until they have an
     account and both nodes (VM + phone) show online.
   - Then guide them to enable HTTPS (admin console → **DNS → Enable HTTPS**).
   - Have them install the **Tailscale** app on the phone and sign in with the
     **same** account.
   - You may run `sudo tailscale up` on this host and relay the printed login URL
     for them to approve in a browser, then `sudo tailscale serve --bg
     http://127.0.0.1:18789`. Confirm with `tailscale status` / `tailscale serve
     status`.

3. **Make sure the user can open a terminal on this machine (SSH).** Every pairing
   step runs in a shell *here*, so the user needs SSH access first:
   - Ask if they can already `ssh` in. They need this host's **public IP**, the login
     user (commonly `ubuntu`), and their SSH key installed on the VM.
   - If they cannot, offer to register their key: ask them to paste their **public**
     key (`ssh-ed25519 …` / `ssh-rsa …` from `~/.ssh/id_*.pub` — **never** a private
     key), append it to `~/.ssh/authorized_keys` on this host, and give them the
     command `ssh <user>@<public-ip>`. You can read the public IP here for them.

4. **Read the runbook yourself and present the steps inline — do not offload the
   reading onto the user.** Reading `HUMAN-SETUP.md` is a plain file read; it touches
   nothing and drops no connection. So **read it** (on this VM:
   `~/.openclaw/skills/openclaw-mobile-pairing/HUMAN-SETUP.md`) and paste its Phase 1 /
   Phase 2 commands **directly into the chat**, in order, each with a one-line plain
   explanation, so the user can copy them straight into their SSH session. **Do NOT**
   just point them at the file or tell them to `less`/open it themselves — that is bad
   UX, and nothing about reading it is unsafe. Copy the commands **verbatim** — same
   text, same order as `HUMAN-SETUP.md`. Do NOT invent, reorder, paraphrase, or
   "improve" them from memory: the runbook is the **single source of truth**, and the
   command order matters (e.g. `gateway.bind loopback` + restart must come *before*
   `gateway.tailscale.mode serve`, or the gateway rejects it). If a step in the runbook
   looks wrong, **say so** to the user instead of silently rewriting it. The **only** step the user must run alone
   over SSH is the final loopback flip + `openclaw qr` (Phase 1's last command), because
   *that* is what drops this chat. Everything up to it, you show inline.

5. **After they finish**, they return to `gateway.customBindHost=0.0.0.0` with
   `gateway.tailscale.mode` unset (Phase 2), so this chat comes back and the phone
   keeps working through Tailscale Serve. If chat is down longer than ~20s, they may
   have skipped Phase 2 — remind them to restore the `0.0.0.0` bind.

## Troubleshooting the user may report

- **"TLS handshake failed / must use https/wss"** → Tailscale Serve is not running,
  or HTTPS is not enabled for their tailnet. See HUMAN-SETUP.md "Recovery playbook".
- **"openclaw qr refuses / gateway URL (wss://) required"** → they are on a public
  bind; the QR step needs the temporary loopback flip (Phase 1).
- **"gateway status says Connectivity probe: failed"** → harmless false alarm on a
  `0.0.0.0` bind; the gateway is fine. See HUMAN-SETUP.md "Known false alarm".
