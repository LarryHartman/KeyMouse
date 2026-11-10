# KeyMouse

A fork of [Deskflow](https://github.com/deskflow/deskflow) for sharing one
keyboard and mouse between an iMac and a MacBook where the MacBook keeps two
user profiles logged in at the same time (fast user switching).

## Why a fork

Apple's Universal Control stops working when more than one user is logged
into a Mac. Deskflow does not have that limitation in principle, but upstream
has a bug that produces the same symptom: the client subscribes to the
fast-user-switch suspend/resume events on the wrong event target, so a
client in a backgrounded session never releases its connection and the
active session's client cannot take over.

This fork fixes that (see `src/lib/client/Client.cpp`) and adds macOS build
and install scripts for a per-profile launch agent.

## Layout

- iMac: runs Deskflow as the **server** (it owns the keyboard and mouse).
- MacBook: runs Deskflow as the **client** in every profile. Only the
  profile currently on screen holds the connection; when you fast-switch,
  the old session's client disconnects and the new one connects.

## Build (on the MacBook, once)

    git clone https://github.com/LarryHartman/KeyMouse ~/Claude/keymouse
    cd ~/Claude/keymouse
    scripts/macos-build.sh

Produces `build/bin/Deskflow.app`.

## Install (in each profile)

    ~/Claude/keymouse/scripts/macos-install.sh

Then open Deskflow once in that profile, pick Client (or Server on the
iMac), approve the Accessibility and Input Monitoring prompts, and connect.
The launch agent keeps it running at login from then on.

For the second profile on the same Mac, `/Applications/Deskflow.app` is
already present, so the script only writes that profile's config and launch
agent. Run it from a Terminal in that profile.

## Versioning

- v1: upstream fix for suspend/resume target, build and install scripts.
- v2: install script takes a mode (server | client <ip>); client profiles run deskflow-core headless from the launch agent; TLS off for LAN.
- v3: LSUIElement (menu bar only, no Dock icon); scripts/macos-deploy.sh bundles all Qt plugins so the tray icon shows.
