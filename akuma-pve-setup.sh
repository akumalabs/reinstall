#!/usr/bin/env bash
# ============================================================
#  AKUMA PVE Bootstrap — auto install Proxmox VE di atas Debian 13
#  + auto setup RAID (mdadm RAID1/10 atau ZFS mirror/RAIDZ1)
#
#  Dijalankan otomatis di FIRST BOOT Debian 13 baru (via cloud-init),
#  config dibaca dari /root/akuma-pve.conf (ditulis oleh wizard kernel.sh)
# ============================================================

set -u

CONF=/root/akuma-pve.conf
LOG=/root/akuma-pve-setup.log
DONE_MARKER=/root/.akuma-pve-done

# kalau udah pernah sukses, jangan jalan lagi
[ -f "$DONE_MARKER" ] && exit 0

exec > >(tee -a "$LOG") 2>&1

step()  { echo -e "\n[AKUMA] [$(date '+%F %T')] $*"; }
fatal() { echo "[AKUMA][FATAL] $*" | tee -a "$LOG"; exit 1; }

step "AKUMA PVE Bootstrap mulai"

[ -f "$CONF" ] || fatal "config $CONF tidak ditemukan"
# shellcheck disable=SC1090
source "$CONF"

export DEBIAN_FRONTEND=noninteractive

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

# ---------- 2. RAID (sebelum install PVE) ----------
if [ "$AKUMA_RAID_TECH" != "none" ]; then
    [ -n "${AKUMA_RAID_DISKS:-}" ] || fatal "AKUMA_RAID_DISKS kosong"
    step "Setup RAID: tech=$AKUMA_RAID_TECH level=${AKUMA_RAID_LEVEL:-auto} disks=$AKUMA_RAID_DISKS"

    if [ "$AKUMA_RAID_TECH" = "mdadm" ]; then
        step "Install mdadm + lvm2"
        APT update
        APT install mdadm lvm2

        _ndev=$(echo $AKUMA_RAID_DISKS | wc -w)
        step "Buat array /dev/md0 (level=$AKUMA_RAID_LEVEL, devices=$_ndev)"
        # yes Y untuk jawab otomatis kalau disk ternyata masih ada metadata lama
        yes Y | mdadm --create --run /dev/md0 --level="$AKUMA_RAID_LEVEL" \
            --raid-devices="$_ndev" $AKUMA_RAID_DISKS \
            || fatal "mdadm --create gagal"

        # pastikan array auto-assemble saat boot
        mdadm --detail --scan >> /etc/mdadm/mdadm.conf
        update-initramfs -u

        step "Setup LVM-thin di atas /dev/md0"
        pvcreate -f /dev/md0
        vgcreate akuma-data /dev/md0
        # sisa ~10% biar thin pool bisa di-trim
        lvcreate -l 90%FREE -T akuma-data/thin
        RAID_STORAGE_OK=1
    fi

    if [ "$AKUMA_RAID_TECH" = "zfs" ]; then
        step "Install zfsutils-linux"
        APT update
        APT install zfsutils-linux
        modprobe zfs 2>/dev/null

        step "Buat pool akuma-tank ($AKUMA_RAID_LEVEL)"
        zpool create -o ashift=12 -O compression=lz4 -m none akuma-tank \
            "$AKUMA_RAID_LEVEL" $AKUMA_RAID_DISKS \
            || fatal "zpool create gagal"
        RAID_STORAGE_OK=1
    fi
else
    step "RAID dilewati (single disk / none)"
    RAID_STORAGE_OK=0
fi

# ---------- 3. Repo PVE (Debian 13 = trixie = PVE 9.x) ----------
step "Tambah repo Proxmox VE pve-no-subscription (trixie)"
mkdir -p /etc/apt/keyrings
wget -qO /etc/apt/keyrings/proxmox-release-trixie.gpg \
    https://download.proxmox.com/debian/proxmox-release-trixie.gpg \
    || fatal "download keyring proxmox gagal"
chmod +r /etc/apt/keyrings/proxmox-release-trixie.gpg
echo "deb [signed-by=/etc/apt/keyrings/proxmox-release-trixie.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
    > /etc/apt/sources.list.d/akuma-pve.list

step "apt update + full-upgrade (bisa lumayan lama)"
APT update
APT full-upgrade

step "Install kernel default PVE"
APT install proxmox-default-kernel

# ---------- 4. Network: vmbr0 (bridge PVE) ----------
step "Konfigurasi ifupdown + bridge vmbr0"
APT install ifupdown

_nic=$(ip -4 route show default | awk '{print $5; exit}')
[ -n "$_nic" ] || fatal "tidak bisa deteksi NIC default"
_addr=$(ip -4 addr show "$_nic" | awk '/inet /{print $2; exit}')
_gw=$(ip -4 route show default | awk '{print $3; exit}')
[ -n "$_addr" ] && [ -n "$_gw" ] || fatal "gagal baca IP/gateway dari $_nic"

# cloud-init jangan otak-atik network lagi (biar vmbr0 aman)
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
echo "vmbr0: $_addr via $_nic (gw $_gw)"

# ---------- 5. Install Proxmox VE ----------
step "Install proxmox-ve (ini yang paling lama, sabar ya)"
echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections
APT install proxmox-ve postfix open-iscsi

step "Matikan repo enterprise (butuh subscription)"
for f in /etc/apt/sources.list.d/pve-enterprise.list \
         /etc/apt/sources.list.d/pve-enterprise.sources \
         /etc/apt/sources.list.d/ceph.list; do
    [ -f "$f" ] && sed -i 's/^deb /#deb /; s/^Types: deb/Types: #deb/' "$f"
done
APT update

# ---------- 6. Registrasi storage hasil RAID ----------
if [ "${RAID_STORAGE_OK:-0}" = "1" ]; then
    step "Daftarkan storage ke PVE"
    if [ "$AKUMA_RAID_TECH" = "mdadm" ]; then
        pvesm add lvmthin akuma-thin --vgname akuma-data --thinpool thin
    else
        pvesm add zfspool akuma-zfs --pool akuma-tank
    fi
fi

# ---------- 7. Selesai ----------
touch "$DONE_MARKER"
cat <<'EOM'

============================================================
 [AKUMA] PVE BOOTSTRAP SELESAI!

 Terakhir: reboot untuk pindah ke kernel PVE + vmbr0:

     reboot

 Setelah reboot:
   - Web UI   : https://<IP-SERVER>:8006  (user: root)
   - Password : sama dengan password SSH
   - Log setup: /root/akuma-pve-setup.log
============================================================
EOM
exit 0
