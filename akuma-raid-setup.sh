#!/usr/bin/env bash
# ============================================================
#  AKUMA RAID Bootstrap — first-boot RAID setup (universal, semua OS Linux)
#  Dijalankan otomatis via cloud-init runcmd.
#  Config: /root/akuma-raid.conf (ditulis wizard kernel.sh)
#
#  Mode:
#    mdadm  : RAID 0/1/5/6/10  ->  /dev/md0  (+ LVM-thin opsional utk PVE)
#    zfs    : mirror/raidz1/raidz2  (khusus PVE)
#    none   : single disk, skip
# ============================================================

set -u

CONF=/root/akuma-raid.conf
LOG=/root/akuma-raid-setup.log
DONE_MARKER=/root/.akuma-raid-done

[ -f "$DONE_MARKER" ] && exit 0
[ -f "$CONF" ] || exit 0

exec > >(tee -a "$LOG") 2>&1

step()  { echo "[AKUMA-RAID][$(date '+%F %T')] $*"; }
fatal() { echo "[AKUMA-RAID][FATAL] $*"; exit 1; }

# shellcheck disable=SC1090
source "$CONF"

export DEBIAN_FRONTEND=noninteractive

step "AKUMA RAID Bootstrap mulai (tech=$AKUMA_RAID_TECH level=$AKUMA_RAID_LEVEL disks=[$AKUMA_RAID_DISKS])"

[ -n "${AKUMA_RAID_DISKS:-}" ] || fatal "AKUMA_RAID_DISKS kosong"

APT() { apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"; }
PKG() {
  if command -v apt-get >/dev/null 2>&1; then
    APT update
    APT install "$@"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "$@"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$@"
  else
    fatal "package manager tidak dikenal"
  fi
}

# sanity: semua disk ada & bukan disk OS
OS_DISK="${AKUMA_OS_DISK:-}"
for d in $AKUMA_RAID_DISKS; do
  [ -b "/dev/$d" ] || fatal "/dev/$d tidak ada"
  [ "$d" = "$OS_DISK" ] && fatal "/dev/$d adalah disk OS, tidak boleh masuk array"
done

# ---------- mdadm: RAID 0/1/5/6/10 ----------
if [ "$AKUMA_RAID_TECH" = "mdadm" ]; then
  case "${AKUMA_RAID_LEVEL:-}" in
    raid0)  MLEVEL=0 ;;
    raid1)  MLEVEL=1 ;;
    raid5)  MLEVEL=5 ;;
    raid6)  MLEVEL=6 ;;
    raid10) MLEVEL=10 ;;
    *) fatal "level mdadm tidak dikenal: ${AKUMA_RAID_LEVEL:-}" ;;
  esac

  step "Install mdadm"
  PKG mdadm

  ndev=$(echo $AKUMA_RAID_DISKS | wc -w)
  step "Buat /dev/md0: level=$MLEVEL devices=$ndev"
  yes Y | mdadm --create --run --force /dev/md0 \
      --level="$MLEVEL" --raid-devices="$ndev" $AKUMA_RAID_DISKS \
      || fatal "mdadm --create gagal"

  # auto-assemble saat boot
  mkdir -p /etc/mdadm
  mdadm --detail --scan >> /etc/mdadm/mdadm.conf
  if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u
  elif command -v dracut >/dev/null 2>&1; then
    dracut -f
  fi

  # filesystem + mountpoint
  case "${AKUMA_RAID_FS:-ext4}" in
    ext4)
      step "Format md0: ext4"
      mkfs.ext4 -F -L akuma-data /dev/md0
      mkdir -p /mnt/akuma-data
      UUID=$(blkid -s UUID -o value /dev/md0)
      echo "UUID=$UUID /mnt/akuma-data ext4 defaults,nofail 0 2" >> /etc/fstab
      mount /mnt/akuma-data
      ;;
    lvmthin)
      step "Setup LVM-thin di atas md0"
      PKG lvm2
      pvcreate -f /dev/md0
      vgcreate akuma-data /dev/md0
      lvcreate -l 90%FREE -T akuma-data/thin
      ;;
    *)
      fatal "AKUMA_RAID_FS tidak dikenal: $AKUMA_RAID_FS"
      ;;
  esac

# ---------- ZFS (khusus PVE) ----------
elif [ "$AKUMA_RAID_TECH" = "zfs" ]; then
  step "Install zfsutils-linux"
  PKG zfsutils-linux
  modprobe zfs 2>/dev/null || true

  case "${AKUMA_RAID_LEVEL:-mirror}" in
    mirror) ZV="mirror" ;;
    raidz1) ZV="raidz1" ;;
    raidz2) ZV="raidz2" ;;
    *) fatal "level zfs tidak dikenal: $AKUMA_RAID_LEVEL" ;;
  esac

  step "Buat pool akuma-tank ($ZV)"
  zpool create -o ashift=12 -O compression=lz4 -m none akuma-tank \
      "$ZV" $AKUMA_RAID_DISKS || fatal "zpool create gagal"
  touch /etc/zfs/zpool.cache 2>/dev/null || true

# ---------- none ----------
elif [ "$AKUMA_RAID_TECH" = "none" ]; then
  step "RAID dilewati (single disk / none)"
  touch "$DONE_MARKER"
  exit 0

else
  fatal "AKUMA_RAID_TECH tidak dikenal: $AKUMA_RAID_TECH"
fi

touch "$DONE_MARKER"
step "SELESAI — RAID $AKUMA_RAID_TECH/$AKUMA_RAID_LEVEL siap"
exit 0
