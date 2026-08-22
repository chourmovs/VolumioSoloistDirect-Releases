#!/bin/sh
set -eu

repository=chourmovs/VolumioSoloistDirect-Releases
workdir=
cleanup() { [ -z "$workdir" ] || [ ! -d "$workdir" ] || rm -rf "$workdir"; }
trap cleanup EXIT HUP INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

printf '%s\n' 'Soloist Direct installer' '-------------------------' ''
[ "$(id -u)" -ne 0 ] || fail 'run as the normal volumio user, not with sudo'
command -v volumio >/dev/null 2>&1 || fail 'Volumio command not found'
command -v tar >/dev/null 2>&1 || fail 'tar is required'
command -v sha256sum >/dev/null 2>&1 || fail 'sha256sum is required'

if command -v curl >/dev/null 2>&1; then
  download() { curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
  download() { wget --https-only --quiet -O "$2" "$1"; }
else
  fail 'curl or wget is required'
fi

volumio_output=$(volumio version 2>/dev/null) || fail 'could not determine Volumio version'
volumio_version=$(printf '%s\n' "$volumio_output" | sed -n 's/.*\b\(4\.[0-9][0-9.]*\)\b.*/\1/p' | head -n 1)
[ -n "$volumio_version" ] || fail 'Volumio 4 is required'
os_codename=$(sed -n 's/^VERSION_CODENAME=//p' "${SOLOIST_DIRECT_OS_RELEASE:-/etc/os-release}" | tr -d '"' | head -n 1)
[ "$os_codename" = bookworm ] || fail "Volumio 4 on Bookworm is required (found ${os_codename:-unknown})"

machine=$(uname -m)
debian=$(dpkg --print-architecture 2>/dev/null || true)
case $debian in amd64) runtime=x86_64 ;; arm64) runtime=aarch64 ;; armhf) runtime=armv7 ;;
  '') case $machine in x86_64|amd64) runtime=x86_64 ;; aarch64|arm64) runtime=aarch64 ;; armv7l|armv7) runtime=armv7 ;; *) fail "unsupported architecture: $machine" ;; esac ;;
  *) fail "unsupported Debian userspace architecture: $debian" ;;
esac

if [ -n "${SOLOIST_DIRECT_VERSION:-}" ]; then
  version=$SOLOIST_DIRECT_VERSION
else
  workdir=$(mktemp -d "${TMPDIR:-/tmp}/soloist-direct.XXXXXX") || fail 'could not create temporary directory'
  channel=$workdir/channel
  download "https://raw.githubusercontent.com/$repository/main/release-channel-alpha" "$channel" || fail 'alpha release channel download failed'
  version=$(cat "$channel")
fi
printf '%s\n' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$' || fail 'invalid alpha release version'
base=https://github.com/$repository/releases/download/$version

[ -n "$workdir" ] || workdir=$(mktemp -d "${TMPDIR:-/tmp}/soloist-direct.XXXXXX") || fail 'could not create temporary directory'
archive=$workdir/soloist-direct.tar.gz
checksum=$workdir/soloist-direct.tar.gz.sha256
download "$base/soloist-direct.tar.gz" "$archive" || fail 'archive download failed'
download "$base/soloist-direct.tar.gz.sha256" "$checksum" || fail 'checksum download failed'
printf '%-18s %s\n' Downloading PASS
(cd "$workdir" && sha256sum -c soloist-direct.tar.gz.sha256 >/dev/null) || fail 'SHA256 mismatch; installation stopped'
printf '%-18s %s\n' SHA256 PASS

tar -tzf "$archive" | awk '/^soloist_direct\// && $0 !~ /(^|\/)\.\.?(\/|$)/ { next } { bad=1 } END { exit bad }' || fail 'unsafe release archive layout'
tar -xzf "$archive" -C "$workdir"
for required in package.json install.sh index.js; do
  [ -f "$workdir/soloist_direct/$required" ] || fail "release is missing $required"
done
plugin_release=$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$workdir/soloist_direct/package.json" | head -n 1)
[ -n "$plugin_release" ] || fail 'could not read plugin version'

printf '\n%-18s %s\n' Volumio "$volumio_version"
printf '%-18s %s\n%-18s %s\n%-18s %s\n' 'Kernel architecture' "$machine" 'Debian userspace' "${debian:-unknown}" 'Soloist runtime' "$runtime"
printf '%-18s %s\n\n' 'Plugin release' "$plugin_release"
printf '%-18s %s\n' Architecture PASS

cd "$workdir/soloist_direct"
if [ -d /data/plugins/music_service/soloist_direct ]; then
  printf '%s\n' 'Existing install   detected; using verified local reinstall path'
fi
# Volumio 4 local-image testing verifies that `plugin install` handles both a
# first installation and reinstall from a local package. There is no verified
# local `volumio plugin update` command, so do not invent or use one here.
printf 'y\n' | volumio plugin install || fail 'local plugin installation failed'
printf '%-18s %s\n' Dependencies PASS
printf '%-18s %s\n' 'Plugin install' PASS
printf '\n%s\n\n' 'Soloist Direct installed.'
printf '%s\n' 'Open:' 'Settings → Plugins → Installed Plugins → Soloist Direct' '' \
  'Then configure your Spotify Soloist API key.'
