#!/usr/bin/env bash
# Turn a directory of .deb files (SITE/pool/main/) into a signed apt repository in SITE, for
# GitHub Pages: dists/trixie/{Release,InRelease,Release.gpg}, main/binary-amd64/Packages.
# The release workflow runs it; it needs apt-ftparchive (apt-utils) and gpg.
#
#   APT_SIGNING_KEY         the signing subkey (armored secret key)
#   APT_SIGNING_PASSPHRASE  its passphrase
#
# Usage: scripts/apt-repo.sh SITE
set -euo pipefail

site="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
pubkey="$root/package/edison-base/usr/share/keyrings/open-edison-archive-keyring.asc"
suite=trixie
dist="$site/dists/$suite"

ls "$site"/pool/main/*.deb >/dev/null
mkdir -p "$dist/main/binary-amd64"

(cd "$site" && apt-ftparchive packages pool) > "$dist/main/binary-amd64/Packages"
gzip -9 -n -k -f "$dist/main/binary-amd64/Packages"
apt-ftparchive \
    -o APT::FTPArchive::Release::Origin=open-edison \
    -o APT::FTPArchive::Release::Label=open-edison \
    -o APT::FTPArchive::Release::Suite="$suite" \
    -o APT::FTPArchive::Release::Codename="$suite" \
    -o APT::FTPArchive::Release::Architectures="amd64 all" \
    -o APT::FTPArchive::Release::Components=main \
    -o APT::FTPArchive::Release::Description="open-edison packages for edison-image" \
    release "$dist" > "$dist/Release.new"
mv "$dist/Release.new" "$dist/Release"

GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
trap 'rm -rf "$GNUPGHOME"' EXIT
gpg --batch --quiet --import <<< "$APT_SIGNING_KEY"
sign() {
    gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 "$@" <<< "$APT_SIGNING_PASSPHRASE"
}
sign --clearsign --output "$dist/InRelease" "$dist/Release"
sign --armor --detach-sign --output "$dist/Release.gpg" "$dist/Release"

# The signatures must check against the key the image ships, not just the one in the secret.
check="$(mktemp -d)"
gpg --batch --quiet --homedir "$check" --import "$pubkey"
gpg --batch --homedir "$check" --verify "$dist/InRelease"
gpg --batch --homedir "$check" --verify "$dist/Release.gpg" "$dist/Release"
rm -rf "$check"

cp "$pubkey" "$site/open-edison-archive-keyring.asc"
cat > "$site/index.html" <<'EOF'
<!doctype html>
<meta charset="utf-8">
<title>open-edison apt repository</title>
<h1>open-edison apt repository</h1>
<p>Packages for <a href="https://github.com/open-edison/edison-image">edison-image</a>
(Debian 13 for the Intel Edison): the kernel, <code>edison-base</code> and
<code>edison-firmware</code>. Boards running edison-image v0.2.9 or later use it already:
<code>sudo apt update && sudo apt upgrade</code>.</p>
<p>Signing key: <a href="open-edison-archive-keyring.asc">open-edison-archive-keyring.asc</a>
(CB6D 240E 6E5A AC30 4DAB  B75D 1820 C349 479D 6749).</p>
EOF
ls -lR "$site"
