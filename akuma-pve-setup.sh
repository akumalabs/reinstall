#!/usr/bin/env bash
# ============================================================
#  AKUMA PVE Bootstrap — auto install Proxmox VE di atas Debian 13
#  Dijalankan otomatis di FIRST BOOT (via cloud-init runcmd), SETELAH
#  akuma-raid-setup.sh selesai (urutan dijamin oleh kernel.sh).
#  Config: /root/akuma-raid.conf
# ============================================================

set -u

CONF=/root/akuma-raid.conf
LOG=/root/akuma-pve-setup.log
DONE_MARKER=/root/.akuma-pve-done

[ -f "$DONE_MARKER" ] && exit 0
[ -f "$CONF" ] || exit 0

exec > >(tee -a "$LOG") 2>&1

step()  { echo "[AKUMA-PVE][$(date '+%F %T')] $*"; }
fatal() { echo "[AKUMA-PVE][FATAL] $*"; exit 1; }

# shellcheck disable=SC1090
source "$CONF"

export DEBIAN_FRONTEND=noninteractive

step "AKUMA PVE Bootstrap mulai (hostname=$AKUMA_HOSTNAME)"

APT() { apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"; }

# ---------- 1. hostname + /etc/hosts (syarat PVE) ----------
step "Set hostname: $AKUMA_HOSTNAME"
_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
_short=${AKUMA_HOSTNAME%%.*}
cat > /etc/hosts <<EOF
127.0.0.1 localhost
${_ip:-127.0.1.1} $AKUMA_HOSTNAME $_short
::1 localhost ip6-localhost ip6-loopback
EOF
hostnamectl set-hostname "$AKUMA_HOSTNAME" 2>/dev/null || echo "$AKUMA_HOSTNAME" > /etc/hostname

# ---------- 2. Repo PVE (Debian 13 = trixie) ----------
step "Tambah repo Proxmox VE pve-no-subscription (trixie)"
mkdir -p /etc/apt/keyrings
wget -qO /etc/apt/keyrings/proxmox-release-trixie.gpg \
    https://download.proxmox.com/debian/proxmox-release-trixie.gpg \
    || fatal "download keyring proxmox gagal"
chmod +r /etc/apt/keyrings/proxmox-release-trixie.gpg
echo "deb [signed-by=/etc/apt/keyrings/proxmox-release-trixie.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
    > /etc/apt/sources.list.d/akuma-pve.list

step "apt update + full-upgrade"
APT update
APT full-upgrade

step "Install kernel default PVE"
APT install proxmox-default-kernel

# ---------- 3. Network: vmbr0 ----------
step "Konfigurasi ifupdown + bridge vmbr0"
APT install ifupdown

_nic=$(ip -4 route show default | awk '{print $5; exit}')
[ -n "$_nic" ] || fatal "tidak bisa deteksi NIC default"
_addr=$(ip -4 addr show "$_nic" | awk '/inet /{print $2; exit}')
_gw=$(ip -4 route show default | awk '{print $3; exit}')
[ -n "$_addr" ] && [ -n "$_gw" ] || fatal "gagal baca IP/gateway dari $_nic"

if [ -d /etc/cloud ]; then
    echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-akuma-disable-network.cfg
fi

cp /etc/network/interfaces /etc/network/interfaces.akuma-bak 2>/dev/null || true
cat > /etc/network/interfaces <<EOF
# AKUMA auto-generated — PVE bridge config
auto lo
iface lo inet loopback

auto $_nic
iface $_nic inet manual

auto vmbr0
iface vmbr0 inet static
    address $_addr
    gateway $_gw
    bridge-ports $_nic
    bridge-stp off
    bridge-fd 0
EOF
step "vmbr0: $_addr via $_nic (gw $_gw)"

# ---------- 4. Install Proxmox VE ----------
step "Install proxmox-ve (paling lama, sabar)"
echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections
APT install proxmox-ve postfix open-iscsi

step "Matikan repo enterprise"
for f in /etc/apt/sources.list.d/pve-enterprise.list \
         /etc/apt/sources.list.d/pve-enterprise.sources \
         /etc/apt/sources.list.d/ceph.list; do
    [ -f "$f" ] && sed -i 's/^deb /#deb /; s/^Types: deb/Types: #deb/' "$f"
done
APT update

# ---------- 5. Registrasi storage hasil RAID ----------
step "Registrasi storage ke PVE"
if [ "${AKUMA_RAID_TECH:-none}" = "mdadm" ] && [ "${AKUMA_RAID_FS:-}" = "lvmthin" ]; then
    pvesm add lvmthin akuma-thin --vgname akuma-data --thinpool thin \
        || step "WARN: registrasi akuma-thin gagal (cek manual)"
elif [ "${AKUMA_RAID_TECH:-none}" = "zfs" ]; then
    pvesm add zfspool akuma-zfs --pool akuma-tank \
        || step "WARN: registrasi akuma-zfs gagal (cek manual)"
else
    step "Tidak ada storage RAID khusus (mdadm non-PVE: /mnt/akuma-data, zfs: pool akuma-tank)"
fi

# ---------- 6. Selesai ----------
touch "$DONE_MARKER"
cat <<'EOM'

============================================================
 [AKUMA] PVE BOOTSTRAP SELESAI!

 Terakhir: reboot untuk pindah ke kernel PVE + vmbr0:

     reboot

 Setelah reboot:
   - Web UI   : https://<IP-SERVER>:8006  (user: root)
   - Password : sama dengan password SSH
   - Log RAID : /root/akuma-raid-setup.log
   - Log PVE  : /root/akuma-pve-setup.log
============================================================
EOM
exit 0
