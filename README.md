# OpenClaw Mobile Pairing

An [OpenClaw](https://openclaw.ai) skill that helps you connect the **OpenClaw
mobile app** to a self-hosted gateway that has no shared LAN with your phone — a
VPS or cloud VM with a public IP — using **Tailscale** for an encrypted `wss://`
front. It also keeps a **remote HTTP client** (a server-side back-end that talks to
the gateway over the network) working at the same time.

> Status: experimental proof-of-concept.

## Why this exists

The OpenClaw mobile app must reach the gateway over an encrypted `wss://` connection.
On a home network the phone and the host share a LAN, so a plain `ws://` is allowed.
On a VPS / cloud VM there is no private path, so OpenClaw refuses to embed `ws://` in
the pairing code, and pairing fails with *"TLS handshake failed / must use https/wss"*.
This skill sets up a Tailscale Serve TLS front and walks through the pairing — while
avoiding the trap where moving the gateway to a loopback bind cuts off a remote
back-end (and its chat).

## Install

```bash
openclaw skills install git:antonzmiievskyi/openclaw-mobile-pairing@main --global
```

That drops the skill into `~/.openclaw/skills/openclaw-mobile-pairing/`, visible to
all agents on the machine.

Prefer to do it by hand? You don't need to install anything — just open
[`HUMAN-SETUP.md`](./HUMAN-SETUP.md) and follow it over SSH.

## What's in here

| File | For | Purpose |
|---|---|---|
| [`SKILL.md`](./SKILL.md) | the OpenClaw agent | Recognizes a "connect my phone" request, explains it, guides the safe parts over chat, and hands the pairing off to you. |
| [`HUMAN-SETUP.md`](./HUMAN-SETUP.md) | a person | Full step-by-step runbook: SSH access, Tailscale onboarding, the pairing phases, verification, recovery. |

## The one important catch

The agent **cannot finish the pairing through chat**. Generating the pairing code
requires flipping the gateway to a loopback bind, which drops every off-host
connection — including the chat channel the agent is using to talk to you. So the
skill has the agent prepare everything it safely can, then hand the final pairing
steps to you to run over SSH. `HUMAN-SETUP.md` explains all of it.

## Notes

- The skill is deliberately **generic** — it names no private hosts, IPs, or internal
  services. Keep it that way if you fork or edit it.
- Requires `openclaw` and `tailscale` on the host.
