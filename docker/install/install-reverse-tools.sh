#!/usr/bin/env bash
#
# Install the reverse-engineering toolchain for
# yolo-agent-reverse-engineering.
#
#   Python side  : handled by install-python-env.sh with
#                  docker/requirements-reverse.txt (same venv as the base image)
#   Bytecode     : pycdc + pycdas, built from source (C++, cmake)
#   JVM side     : Eclipse Temurin JDK 21, jadx (DEX -> Java), Ghidra headless
#   Native       : radare2 (official release .deb), gdb, elfutils, bindiff-ish
#                  helpers
#
# Ghidra 12 requires Java 21 (application.java.min=21), and Debian 12 only
# ships OpenJDK 17 — hence the pinned Temurin tarball rather than an apt
# package. jadx runs on the same JVM.
#
# Every download is pinned; the build fails on any hash mismatch.
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# --- pinned versions ---------------------------------------------------------
JAVA_VERSION="${JAVA_VERSION:-21.0.12.1_1}"
JAVA_URL="${JAVA_URL:-https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz}"
JAVA_SHA256="${JAVA_SHA256:-ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94}"

JADX_VERSION="${JADX_VERSION:-1.5.6}"
JADX_SHA256="${JADX_SHA256:-545ea2be9c242511bc145755cf4bda2485ade42966e096f8b4d3da2a230e8974}"

GHIDRA_VERSION="${GHIDRA_VERSION:-12.1.3}"
GHIDRA_DATE="${GHIDRA_DATE:-20260817}"
GHIDRA_SHA256="${GHIDRA_SHA256:-93a5d11a9ad510622acaaf908c556a7b9b764d338e78a7567f3689bf5081fd54}"

RADARE2_VERSION="${RADARE2_VERSION:-6.2.2}"
RADARE2_SHA256="${RADARE2_SHA256:-09234e4139bf8dfcbb7fc1fdb2519859ad516e63c19d3c27d92aaecdf463b1ad}"

PYCDC_COMMIT="${PYCDC_COMMIT:-b4289760970dbc399684f1e155ec6d1ea1cc787e}"
PYCDC_SHA256="${PYCDC_SHA256:-d7d8c53d37a1a586097145b532fca02535db2f2f0999b3b1e910133c9941bf31}"

verify() { echo "$1  $2" | sha256sum -c - >/dev/null; }

# One apt pass, including the local radare2 .deb, so the package indexes are
# fetched once and removed once. `apt-get update` is required even for a local
# .deb because apt still resolves that package's dependencies from the indexes.
echo ">> installing distro analysis tools"
curl -fsSL --retry 3 -o /tmp/radare2.deb \
  "https://github.com/radareorg/radare2/releases/download/${RADARE2_VERSION}/radare2_${RADARE2_VERSION}_amd64.deb"
verify "$RADARE2_SHA256" /tmp/radare2.deb

apt-get update

# Package list is an array, not a backslash continuation: a `#` comment inside a
# continuation ends the command and makes apt try to execute the next line.
packages=(
  # native analysis / debugging
  gdb binutils binutils-multiarch elfutils strace ltrace
  # file carving and signature scanning
  binwalk foremost yara
  # hex inspection
  xxd hexedit bsdextrautils
  # archive handling used by every one of these tools
  zip unzip xz-utils p7zip-full cabextract
  # pycdc and pycdas are built from source below, so this image needs a native
  # toolchain of its own: the base image deliberately ships no compilers.
  cmake ninja-build gcc g++ make pkg-config
  # radare2 itself, from the pinned release .deb
  /tmp/radare2.deb
)

apt-get install -y --no-install-recommends "${packages[@]}"
rm -f /tmp/radare2.deb
rm -rf /var/lib/apt/lists/*
apt-get clean
r2 -v | head -1

# --- Temurin JDK 21 (Ghidra >= 12 and jadx both need it) --------------------
echo ">> installing Temurin JDK ${JAVA_VERSION}"
curl -fsSL --retry 3 -o /tmp/temurin.tar.gz "$JAVA_URL"
verify "$JAVA_SHA256" /tmp/temurin.tar.gz
mkdir -p /opt/java
tar -xzf /tmp/temurin.tar.gz -C /opt/java --strip-components=1
rm -f /tmp/temurin.tar.gz
"/opt/java/bin/java" -version
export JAVA_HOME=/opt/java
export PATH="/opt/java/bin:$PATH"

# --- pycdc / pycdas (C++ decompiler for arbitrary Python bytecode) ----------
# Built from source so it works without any pip package: this is the tool that
# covers Python versions that the Python-side decompilers cannot.
echo ">> building pycdc @ ${PYCDC_COMMIT:0:12}"
curl -fsSL --retry 3 -o /tmp/pycdc.tgz \
  "https://codeload.github.com/zrax/pycdc/tar.gz/${PYCDC_COMMIT}"
verify "$PYCDC_SHA256" /tmp/pycdc.tgz
mkdir -p /opt/pycdc-src
tar -xzf /tmp/pycdc.tgz -C /opt/pycdc-src --strip-components=1
rm -f /tmp/pycdc.tgz
command -v cmake >/dev/null || { echo "ERROR: cmake missing; pycdc cannot be built" >&2; exit 1; }
command -v ninja >/dev/null || { echo "ERROR: ninja missing; pycdc cannot be built" >&2; exit 1; }
cmake -S /opt/pycdc-src -B /opt/pycdc-src/build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release
cmake --build /opt/pycdc-src/build --parallel "$(nproc)"
install -m 0755 /opt/pycdc-src/build/pycdc /usr/local/bin/pycdc
install -m 0755 /opt/pycdc-src/build/pycdas /usr/local/bin/pycdas
rm -rf /opt/pycdc-src/build
test -x /usr/local/bin/pycdc || { echo "ERROR: pycdc not installed" >&2; exit 1; }
test -x /usr/local/bin/pycdas || { echo "ERROR: pycdas not installed" >&2; exit 1; }
pycdc 2>&1 | head -1 || true
pycdas 2>&1 | head -1 || true

# --- jadx (DEX/APK -> Java source) ------------------------------------------
echo ">> installing jadx ${JADX_VERSION}"
curl -fsSL --retry 3 -o /tmp/jadx.zip \
  "https://github.com/skylot/jadx/releases/download/v${JADX_VERSION}/jadx-${JADX_VERSION}.zip"
verify "$JADX_SHA256" /tmp/jadx.zip
mkdir -p /opt/jadx
unzip -q /tmp/jadx.zip -d /opt/jadx
rm -f /tmp/jadx.zip
# CLI only: jadx-gui needs a display and this image has none.
chmod 0755 /opt/jadx/bin/jadx
ln -sf /opt/jadx/bin/jadx /usr/local/bin/jadx
jadx --version

# --- Ghidra headless -------------------------------------------------------
echo ">> installing Ghidra ${GHIDRA_VERSION}"
curl -fsSL --retry 3 -o /tmp/ghidra.zip \
  "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/ghidra_${GHIDRA_VERSION}_PUBLIC_${GHIDRA_DATE}.zip"
verify "$GHIDRA_SHA256" /tmp/ghidra.zip
mkdir -p /opt/ghidra
unzip -q /tmp/ghidra.zip -d /tmp/ghidra-extract
rm -f /tmp/ghidra.zip
# The zip contains ghidra_<ver>_PUBLIC/ as its single top-level directory.
mv /tmp/ghidra-extract/ghidra_*_PUBLIC/* /tmp/ghidra-extract/ghidra_*_PUBLIC/.[!.]* /opt/ghidra/ 2>/dev/null || true
rm -rf /tmp/ghidra-extract
chmod 0755 /opt/ghidra/support/analyzeHeadless
ln -sf /opt/ghidra/support/analyzeHeadless /usr/local/bin/ghidra-headless
test -x /opt/ghidra/support/analyzeHeadless

# --- radare2 ----------------------------------------------------------------
# Already installed above from the pinned release .deb; this only reports it.
echo ">> radare2 ${RADARE2_VERSION} installed"

# --- environment for the runtime -------------------------------------------
# Ghidra and jadx both locate Java through JAVA_HOME.
mkdir -p /opt/yolo
cat > /opt/yolo/toolchain-env.sh <<'EOF'
# Sourced by /home/agent/.bashrc for the reverse-engineering image.
export JAVA_HOME=/opt/java
export PATH="/opt/java/bin:$PATH"
# Ghidra writes project state and temp files; keep them off the read-only
# rootfs and inside the home volume.
export GHIDRA_USER_DIR="${GHIDRA_USER_DIR:-$HOME/.ghidra}"
mkdir -p "$GHIDRA_USER_DIR"
EOF
chmod 0644 /opt/yolo/toolchain-env.sh

echo ">> install-reverse-tools.sh: reverse-engineering toolchain installed"
