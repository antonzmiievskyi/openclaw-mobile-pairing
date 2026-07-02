#!/usr/bin/env bash
#
# pair.sh — safely mint an OpenClaw mobile-app pairing code.
#
# Pairing needs the gateway TEMPORARILY on a loopback bind + gateway.tailscale.mode=serve
# (the only state in which `openclaw qr` will emit a wss:// setup code). A loopback bind
# CUTS OFF every remote client — e.g. a server-side back-end that talks to the gateway
# over the network — so the moment you flip, that client (and its chat) goes down.
#
# This script flips to loopback ONLY long enough to show the code, then ALWAYS restores
# the public 0.0.0.0 bind — on success, on error, or on Ctrl-C — via an EXIT trap. That
# guaranteed restore is the whole point: it stops you from getting stuck in the broken
# loopback state that takes the back-end down.
#
# Prerequisites (Phase 0, once): `sudo tailscale up` and
# `sudo tailscale serve --bg http://127.0.0.1:18789`, plus your phone joined to the
# same tailnet with HTTPS enabled for the tailnet.

set -u

PORT=18789
OC="$(command -v openclaw || echo "$HOME/.npm-global/bin/openclaw")"

wait_loopback() {  # poll until the gateway answers on loopback (or give up)
  local i code
  for i in $(seq 1 15); do
    code="$(curl -s -m3 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/" || true)"
    [ "$code" = "200" ] && return 0
    sleep 1
  done
  return 1
}

restore_public_bind() {  # ALWAYS runs on exit — puts the gateway back on 0.0.0.0
  echo
  echo ">> Restoring the public bind (0.0.0.0) so the remote client works again..."
  # unset serve FIRST: the validator forbids a non-loopback bind while mode=serve.
  "$OC" config unset gateway.tailscale.mode          >/dev/null 2>&1 \
    || "$OC" config set gateway.tailscale.mode off    >/dev/null 2>&1
  "$OC" config set gateway.bind custom               >/dev/null 2>&1
  "$OC" config set gateway.customBindHost 0.0.0.0    >/dev/null 2>&1
  "$OC" gateway restart                              >/dev/null 2>&1
  sleep 2
  local listen
  listen="$(ss -tlnp 2>/dev/null | grep ":${PORT} " | head -1)"
  case "$listen" in
    *0.0.0.0:${PORT}*) echo ">> OK — gateway is back on 0.0.0.0:${PORT}. Back-end path restored." ;;
    *) echo ">> WARNING: gateway is NOT on 0.0.0.0 (listener: ${listen:-none})."
       echo ">>          Re-run this script, or run the manual Phase 2 commands from HUMAN-SETUP.md." ;;
  esac
}

# ---- keep OpenClaw current (older builds miss git: install / --global and some gateway
#      behavior). Runs `openclaw update` unless PAIR_SKIP_UPDATE=1. Non-fatal; note that
#      `openclaw update` restarts the gateway, which is fine here (pairing restarts it too).
if [ "${PAIR_SKIP_UPDATE:-0}" != "1" ]; then
  echo ">> Ensuring OpenClaw is up to date (set PAIR_SKIP_UPDATE=1 to skip)..."
  if "$OC" update >/dev/null 2>&1; then
    echo ">> OpenClaw is current."
  else
    echo ">> (openclaw update skipped or failed — continuing anyway)"
  fi
fi

# ---- pre-checks (before arming the trap, so an early exit causes no needless restart) ----
command -v tailscale >/dev/null 2>&1 \
  || { echo "ERROR: tailscale is not installed. Do Phase 0 first (see HUMAN-SETUP.md)."; exit 1; }

if ! tailscale serve status 2>/dev/null | grep -q "127.0.0.1:${PORT}"; then
  echo "ERROR: Tailscale Serve is not fronting http://127.0.0.1:${PORT}."
  echo "Do Phase 0 first:  sudo tailscale serve --bg http://127.0.0.1:${PORT}"
  exit 1
fi

echo ">> Tailscale Serve looks good."
echo ">> Flipping the gateway to loopback to mint a pairing code."
echo ">> NOTE: the remote client / web chat is briefly DOWN during this step —"
echo ">>       it is restored automatically when this script exits."
echo

# From here on, ALWAYS restore on exit (normal, error, or Ctrl-C).
trap restore_public_bind EXIT

# ---- Phase 1: loopback bind FIRST + restart, THEN mode=serve (validator order) ----
"$OC" config set gateway.bind loopback             >/dev/null 2>&1
"$OC" gateway restart                              >/dev/null 2>&1
"$OC" config set gateway.tailscale.mode serve      >/dev/null 2>&1
"$OC" gateway restart                              >/dev/null 2>&1

if ! wait_loopback; then
  echo "ERROR: the gateway did not come up on loopback. Aborting (bind will be restored)."
  exit 1
fi

echo
echo "=====================  SCAN THIS  ====================="
"$OC" qr                          # scannable QR; run `openclaw qr --setup-code-only` for a paste-able text code
echo "======================================================="
echo
echo "In the OpenClaw mobile app: add a connection and scan the QR above."
echo "(Need a text code instead? open another SSH shell and run:"
echo "   openclaw qr --setup-code-only )"
echo "The code is single-use and short-lived — pair now."
echo
# When you press Enter (or Ctrl-C), the EXIT trap restores the 0.0.0.0 bind.
read -r -p ">> Press Enter once the app shows it is paired (or Ctrl-C to abort)... " _ || true
