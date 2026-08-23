# Soloist Direct

Soloist Direct is **experimental alpha software** for Volumio 4. It is installed
independently and is **not distributed through the Volumio plugin store**.

Requirements are Volumio 4 on Bookworm, Raspberry Pi 2 or newer/armv7/armhf,
ARM64/aarch64 or x86_64, and a Spotify Soloist API key for actual Spotify
playback. Spotify Soloist
itself is downloaded directly from Spotify and is **not redistributed** by this
project. The source/development repository is currently private; this public
repository contains only this README and the installer. Release assets are
SHA-256 integrity-checked before extraction.

## Install

Run this as the normal `volumio` SSH user (not through `sudo bash`):

```sh
curl -fsSL \
  https://raw.githubusercontent.com/chourmovs/VolumioSoloistDirect-Releases/main/install.sh \
  | bash
```

To select an immutable release explicitly:

```sh
curl -fsSL https://raw.githubusercontent.com/chourmovs/VolumioSoloistDirect-Releases/main/install.sh \
  | SOLOIST_DIRECT_VERSION=v0.4.0-alpha.11 bash
```

The installer obtains the default from the strictly validated alpha channel,
checks the downloaded archive against its published checksum, and then invokes
`volumio plugin install` for a fresh installation or `volumio plugin update` for
an existing installation. An update preserves the existing plugin configuration,
credentials, persistent data, and enabled state according to Volumio's update
semantics; it does not operate on unrelated plugins.

## Raspberry Pi 3 manual alpha check

No ARM validation is claimed until this checklist has been run on physical
hardware. The expected first architecture report is `armv7l / armhf`.

```sh
curl -fsSL \
  https://raw.githubusercontent.com/chourmovs/VolumioSoloistDirect-Releases/main/install.sh \
  | bash
soloist-direct version
soloist-direct architecture
soloist-direct system dependencies
soloist-direct doctor
sudo soloist-direct audio smoke
```

## Audio architecture

The intended path is Spotify Soloist → private PipeWire → direct ALSA hardware.
This bypasses parts of Volumio's normal audio chain. There is no intentional DSP
or sample-rate conversion, but this project does **not** claim bit-perfect
playback or latency figures.
