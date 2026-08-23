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

os_release=${SOLOIST_DIRECT_OS_RELEASE:-/etc/os-release}
[ -r "$os_release" ] || fail 'could not read Volumio OS release information'
volumio_version=$(sed -n 's/^VOLUMIO_VERSION=//p' "$os_release" | head -n 1)
case $volumio_version in
  \"*\") volumio_version=${volumio_version#\"}; volumio_version=${volumio_version%\"} ;;
esac
case $volumio_version in 4.*) ;; *) fail 'Volumio 4 is required' ;; esac
os_codename=$(sed -n 's/^VERSION_CODENAME=//p' "$os_release" | tr -d '"' | head -n 1)
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
plugin_dir=${SOLOIST_DIRECT_PLUGIN_DIR:-/data/plugins/music_service/soloist_direct}
state_dir=${SOLOIST_DIRECT_STATE_DIR:-/data/soloist-direct/state}
marker=$state_dir/deployment-complete.json
installed_cli=${SOLOIST_DIRECT_INSTALLED_CLI:-/usr/local/bin/soloist-direct}
if [ -d "$plugin_dir" ]; then
  printf '%-20s %s\n' 'Existing install' YES 'Upgrade method' 'volumio plugin update'
  previous_marker=$(sha256sum "$marker" 2>/dev/null | awk '{print $1}' || true)
  timeout_s=${SOLOIST_DIRECT_VOLUMIO_TIMEOUT_S:-300}
  grace_s=${SOLOIST_DIRECT_VOLUMIO_GRACE_S:-5}
  case $timeout_s:$grace_s in *[!0-9:]*) fail 'deployment timeout values must be integers' ;; esac
  volumio plugin update & update_pid=$!
  started=$(date +%s); verified=false; verified_at=; exited=false; update_rc=
  while :; do
    if ! kill -0 "$update_pid" 2>/dev/null; then
      set +e; wait "$update_pid"; update_rc=$?; set -e; exited=true
      [ "$update_rc" -eq 0 ] || fail 'local plugin update failed'
    fi
    current_marker=$(sha256sum "$marker" 2>/dev/null | awk '{print $1}' || true)
    if [ -n "$current_marker" ] && [ "$current_marker" != "$previous_marker" ] && \
       python3 -c 'import json,sys; marker=json.load(open(sys.argv[1],encoding="utf-8")); package=json.load(open(sys.argv[3],encoding="utf-8")); raise SystemExit(0 if marker.get("version")==sys.argv[2] and package.get("version")==sys.argv[2] else 1)' "$marker" "$plugin_release" "$plugin_dir/package.json" && \
       [ -x "$installed_cli" ] && [ "$("$installed_cli" version 2>/dev/null)" = "$plugin_release" ]; then
      if ! $verified; then
        verified=true
        verified_at=$(date +%s)
      fi
    fi
    $exited && { $verified && break; fail 'plugin update exited without a verified deployment'; }
    now=$(date +%s)
    elapsed=$(( now - started ))
    if $verified && [ $(( now - verified_at )) -ge "$grace_s" ]; then
      printf '%s\n' 'WARNING: deployment verified; terminating hung Volumio CLI wrapper' >&2
      kill "$update_pid" 2>/dev/null || :; wait "$update_pid" 2>/dev/null || :
      break
    fi
    [ "$elapsed" -lt "$timeout_s" ] || { kill "$update_pid" 2>/dev/null || :; wait "$update_pid" 2>/dev/null || :; fail 'plugin update timed out before deployment could be verified'; }
    sleep 1
  done
else
  printf '%-20s %s\n' 'Existing install' NO 'Install method' 'volumio plugin install'
  printf 'y\n' | volumio plugin install || fail 'local plugin installation failed'
fi
printf '%-18s %s\n' Dependencies PASS
printf '%-18s %s\n' 'Plugin deployment' PASS
printf '\n%s\n\n' 'Soloist Direct installed.'
printf '%s\n' 'Open:' 'Settings → Plugins → Installed Plugins → Soloist Direct' '' \
  'Then configure your Spotify Soloist API key.'
