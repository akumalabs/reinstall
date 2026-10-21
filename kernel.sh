#!/usr/bin/env bash
# ============================================================
#   AKUMA Auto Reinstall — Interactive Wizard v2
#   Author : AKUMAVM (fork of bin456789/reinstall)
#
#   Alur:
#     1) Pilih OS (Debian/Ubuntu/Alma/Alpine/CentOS/Kali/Windows/Netboot/DD/PVE)
#     2) hostname
#     3) user      (default: root utk linux, Administrator utk Windows)
#     4) password  (+ verifikasi)
#     5) port      (default: 22 SSH / 3389 RDP)
#     6) RAID (SEMUA OS kecuali netboot/dd/windows):
#        mdadm RAID 0/1/5/6/10, none (single disk)
#        ZFS mirror/raidz1/raidz2 KHUSUS PVE
#     7) pilih disk OS + disk array (interactive lsblk)
#     8) konfirmasi → eksekusi reinstall.sh
# ============================================================

set -u

CONFHOME="https://raw.githubusercontent.com/akumalabs/reinstall/main"

C_G="\033[1;32m"; C_Y="\033[1;33m"; C_R="\033[1;31m"; C_B="\033[1;36m"; C_N="\033[0m"

info()  { echo -e "${C_G}[INFO]${C_N} $*"; }
warn()  { echo -e "${C_Y}[WARN]${C_N} $*"; }
err()   { echo -e "${C_R}[ERR ]${C_N} $*"; }
die()   { err "$*"; exit 1; }

header() {
  clear
  echo -e "${C_B}########################################################"
  echo -e "#                                                      #"
  echo -e "#          AKUMA Auto Reinstall + RAID Wizard          #"
  echo -e "#                                                      #"
  echo -e "#          Author: AKUMAVM                             #"
  echo -e "#          Inspired by bin456789                       #"
  echo -e "#                                                      #"
  echo -e "########################################################${C_N}"
  echo ""
}

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y -qq curl wget >/dev/null 2>&1 || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q curl wget >/dev/null 2>&1 || true
  fi
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || \
    die "curl/wget tidak tersedia dan gagal diinstall"
}

fetch() { # fetch <url> <outfile>
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  else
    wget -qO "$2" "$1"
  fi
}

ask() { # ask <pertanyaan> <default> → jawaban di $REPLY
  local q="$1" def="${2:-}"
  if [ -n "$def" ]; then
    read -r -p "$(echo -e "${C_B}?${C_N} ${q} ${C_Y}[${def}]${C_N}: ")" REPLY
    REPLY="${REPLY:-$def}"
  else
    read -r -p "$(echo -e "${C_B}?${C_N} ${q}: ")" REPLY
  fi
}

ask_password() { # dua kali ketik → $REPLY
  while :; do
    read -r -s -p "$(echo -e "${C_B}?${C_N} Password: ")" p1; echo
    if [ "${#p1}" -lt 6 ]; then warn "Minimal 6 karakter, ulangi."; continue; fi
    read -r -s -p "$(echo -e "${C_B}?${C_N} Ulangi password: ")" p2; echo
    if [ "$p1" != "$p2" ]; then warn "Password tidak sama, ulangi."; continue; fi
    REPLY="$p1"; break
  done
}

confirm() { # confirm <pertanyaan> → return 0 kalau y
  local yn
  read -r -p "$(echo -e "${C_R}?${C_N} $1 [y/N]: ")" yn
  case "$yn" in [yY][eE][sS]|[yY]) return 0 ;; *) return 1 ;; esac
}

is_valid_disk() { lsblk -d -no TYPE "/dev/$1" 2>/dev/null | grep -qx disk; }

# pilih 1 disk untuk OS → $OS_DISK
list_disk_os() {
  echo ""
  echo -e "${C_B}Disk yang terdeteksi:${C_N}"
  lsblk -d -o NAME,SIZE,TYPE,MODEL,SERIAL 2>/dev/null \
    | awk '$3=="disk"{printf "  %-12s %-9s %-20s %s\n", "/dev/"$1, $2, $4, $5}'
  echo ""
  while :; do
    ask "Disk untuk OS (contoh: sda atau nvme0n1)" ""
    [ -n "$REPLY" ] || { warn "Jangan kosong."; continue; }
    REPLY="${REPLY#/dev/}"
    if is_valid_disk "$REPLY"; then
      OS_DISK="$REPLY"; break
    fi
    err "/dev/$REPLY bukan disk yang valid."
  done
}

# pilih N disk untuk array → $RAID_DISKS (spasi, tanpa /dev/)
list_disk_raid() {
  echo ""
  echo -e "${C_B}Disk tersisa (KECUALI disk OS ${C_G}/dev/$OS_DISK${C_B}):${C_N}"
  lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null \
    | awk -v od="$OS_DISK" '$3=="disk" && $1!=od {printf "  %-12s %-9s %s\n", "/dev/"$1, $2, $4}'
  echo ""
  while :; do
    local min_n=$1
    read -r -p "$(echo -e "${C_B}?${C_N} Disk RAID (min $min_n, pisah spasi): ")" -a disks_in
    RAID_DISKS=""
    for d in "${disks_in[@]}"; do
      d="${d#/dev/}"
      if [ "$d" = "$OS_DISK" ]; then err "$d = disk OS, ga boleh."; continue; fi
      if is_valid_disk "$d"; then
        RAID_DISKS+="${d} "
      else
        err "/dev/$d bukan disk valid, dilewati."
      fi
    done
    RAID_DISKS="${RAID_DISKS% }"
    if [ "$(echo $RAID_DISKS | wc -w)" -ge "$min_n" ]; then break; fi
    warn "Minimal $min_n disk valid buat array ini."
  done
}

# validasi jumlah disk vs level RAID → $RAID_LEVEL, $RAID_DISKS
validate_raid_count() {
  ndev=$(echo $RAID_DISKS | wc -w)
  case "$RAID_LEVEL" in
    raid0)  [ "$ndev" -ge 2 ] || die "RAID0 butuh >=2 disk (dapat: $ndev)" ;;
    raid1)  [ "$ndev" -eq 2 ] || die "RAID1 butuh tepat 2 disk (dapat: $ndev)" ;;
    raid5)  [ "$ndev" -ge 3 ] || die "RAID5 butuh >=3 disk (dapat: $ndev)" ;;
    raid6)  [ "$ndev" -ge 4 ] || die "RAID6 butuh >=4 disk (dapat: $ndev)" ;;
    raid10) { [ "$ndev" -ge 4 ] && [ $((ndev % 2)) -eq 0 ]; } || die "RAID10 butuh >=4 disk genap (dapat: $ndev)" ;;
    mirror) [ "$ndev" -ge 2 ] || die "ZFS mirror butuh >=2 disk (dapat: $ndev)" ;;
    raidz1) [ "$ndev" -ge 3 ] || die "RAIDZ1 butuh >=3 disk (dapat: $ndev)" ;;
    raidz2) [ "$ndev" -ge 4 ] || die "RAIDZ2 butuh >=4 disk (dapat: $ndev)" ;;
  esac
}

# ============================================================
#  1) PILIH OS
# ============================================================
install_deps
header

echo -e "${C_B}Please select an OS:${C_N}"
echo "   1) Debian 13 (Trixie)"
echo "   2) Latest Ubuntu"
echo "   3) Latest AlmaLinux"
echo "   4) Latest Alpine"
echo "   5) Latest CentOS"
echo "   6) Kali Linux"
echo "   7) Windows 10 Pro"
echo "   8) Windows 11 Pro"
echo "   9) Windows Server 2019 DC"
echo "  10) Windows Server 2022 DC"
echo "  11) Windows Server 2025 DC"
echo "  12) Netboot.xyz"
echo "  13) Custom DD image"
echo -e "${C_G}  14) Proxmox VE  (Debian 13 + PVE + RAID)${C_N}"
echo "   0) Exit"
echo ""
ask "Your option" ""
N="$REPLY"

USERNAME_DEFAULT="root"; PORT_LABEL="SSH"; PORT_DEFAULT="22"
WINIMG=""; WINISO=""; DDIMG=""
OSNAME=""; RAID_CAPABLE=0
case $N in
  1)  OSNAME="debian";  RAID_CAPABLE=1 ;;
  2)  OSNAME="ubuntu";  RAID_CAPABLE=1 ;;
  3)  OSNAME="alma";    RAID_CAPABLE=1 ;;
  4)  OSNAME="alpine";  RAID_CAPABLE=1 ;;
  5)  OSNAME="centos";  RAID_CAPABLE=1 ;;
  6)  OSNAME="kali";    RAID_CAPABLE=1 ;;
  7)  OSNAME="windows"; WINIMG="Windows 10 Pro"
      WINISO="https://templates.akumalabs.com/win10.iso"
      USERNAME_DEFAULT="Administrator"; PORT_LABEL="RDP"; PORT_DEFAULT="3389" ;;
  8)  OSNAME="windows"; WINIMG="Windows 11 Pro"
      WINISO="https://dl.zerofs.link/dl/eyJhbG...5h4Q"
      USERNAME_DEFAULT="Administrator"; PORT_LABEL="RDP"; PORT_DEFAULT="3389" ;;
  9)  OSNAME="windows"; WINIMG="Windows Server 2019 SERVERDATACENTER"
      WINISO="https://go.microsoft.com/fwlink/p/?LinkID=2195167"
      USERNAME_DEFAULT="Administrator"; PORT_LABEL="RDP"; PORT_DEFAULT="3389" ;;
  10) OSNAME="windows"; WINIMG="Windows Server 2022 SERVERDATACENTER"
      WINISO="https://go.microsoft.com/fwlink/p/?LinkID=2195280"
      USERNAME_DEFAULT="Administrator"; PORT_LABEL="RDP"; PORT_DEFAULT="3389" ;;
  11) OSNAME="windows"; WINIMG="Windows Server 2025 SERVERDATACENTER"
      WINISO="https://go.microsoft.com/fwlink/p/?LinkID=2293312"
      USERNAME_DEFAULT="Administrator"; PORT_LABEL="RDP"; PORT_DEFAULT="3389" ;;
  12) OSNAME="netboot.xyz" ;;
  13) OSNAME="dd" ;;
  14) OSNAME="pve";     RAID_CAPABLE=1 ;;
  0)  exit 0 ;;
  *)  die "Wrong input!" ;;
esac

# ============================================================
#  2) PERTANYAAN UMUM
# ============================================================
header
ask "Hostname untuk server ini" "srv1"
HOSTNAME_IN="$REPLY"

header
ask "Username (login OS baru)" "$USERNAME_DEFAULT"
USERNAME_IN="$REPLY"

header
echo -e "${C_B}?${C_N} Password untuk user ${C_G}$USERNAME_IN${C_N} (min 6 char, hidden)"
ask_password
PASSWORD_IN="$REPLY"

header
ask "Port $PORT_LABEL di OS baru" "$PORT_DEFAULT"
PORT_IN="$REPLY"
case "$PORT_IN" in
  ''|*[!0-9]*) die "Port harus angka" ;;
esac
if [ "$PORT_IN" -lt 1 ] || [ "$PORT_IN" -gt 65535 ]; then
  die "Port di luar range 1-65535"
fi

# DD: tanya URL image
if [ "$OSNAME" = "dd" ]; then
  header
  ask "Custom DD image URL" ""
  DDIMG="$REPLY"
  [ -n "$DDIMG" ] || die "URL image wajib diisi"
fi

# ============================================================
#  3) RAID (universal — semua OS kecuali windows/netboot/dd)
#     ZFS hanya tersedia di PVE
# ============================================================
OS_DISK=""; RAID_TECH="none"; RAID_LEVEL=""; RAID_DISKS=""; RAID_FS="ext4"

if [ "$RAID_CAPABLE" = "1" ]; then
  header
  echo -e "${C_B}RAID technology:${C_N}"
  echo "   1) Tanpa RAID (single disk / skip)"
  echo "   2) mdadm RAID 0  (striping, min 2 disk, no redundancy)"
  echo "   3) mdadm RAID 1  (mirror, 2 disk)"
  echo "   4) mdadm RAID 5  (min 3 disk, 1 parity)"
  echo "   5) mdadm RAID 6  (min 4 disk, 2 parity)"
  echo "   6) mdadm RAID 10 (min 4 disk genap, mirror+stripe)"
  if [ "$OSNAME" = "pve" ]; then
    echo -e "${C_G}   7) ZFS mirror    (2 disk, native PVE)${C_N}"
    echo -e "${C_G}   8) ZFS RAIDZ1    (min 3 disk, 1 parity)${C_N}"
    echo -e "${C_G}   9) ZFS RAIDZ2    (min 4 disk, 2 parity)${C_N}"
  fi
  echo ""
  ask "RAID option" "1"
  case $REPLY in
    1) RAID_TECH="none" ;;
    2) RAID_TECH="mdadm"; RAID_LEVEL="raid0"  ;;
    3) RAID_TECH="mdadm"; RAID_LEVEL="raid1"  ;;
    4) RAID_TECH="mdadm"; RAID_LEVEL="raid5"  ;;
    5) RAID_TECH="mdadm"; RAID_LEVEL="raid6"  ;;
    6) RAID_TECH="mdadm"; RAID_LEVEL="raid10" ;;
    7) [ "$OSNAME" = "pve" ] || die "ZFS cuma tersedia buat PVE"; RAID_TECH="zfs"; RAID_LEVEL="mirror" ;;
    8) [ "$OSNAME" = "pve" ] || die "ZFS cuma tersedia buat PVE"; RAID_TECH="zfs"; RAID_LEVEL="raidz1" ;;
    9) [ "$OSNAME" = "pve" ] || die "ZFS cuma tersedia buat PVE"; RAID_TECH="zfs"; RAID_LEVEL="raidz2" ;;
    *) die "Wrong input" ;;
  esac

  if [ "$RAID_TECH" != "none" ]; then
    header
    list_disk_os
    header
    list_disk_raid 2
    validate_raid_count

    # mdadm non-PVE: filesystem buat data array
    if [ "$RAID_TECH" = "mdadm" ] && [ "$OSNAME" != "pve" ]; then
      header
      echo -e "${C_B}Filesystem untuk array data:${C_N}"
      echo "   1) ext4 (default, universal)"
      echo "   2) Kosongkan saja (ga diformat, diatur manual nanti)"
      ask "Filesystem" "1"
      case $REPLY in
        1) RAID_FS="ext4" ;;
        2) RAID_FS="none" ;;
        *) die "Wrong input" ;;
      esac
    fi
    # PVE: mdadm -> LVM-thin storage, zfs -> pool storage (auto di bootstrap)
    if [ "$RAID_TECH" = "mdadm" ] && [ "$OSNAME" = "pve" ]; then
      RAID_FS="lvmthin"
    fi
  else
    header
    list_disk_os
  fi
fi

# ============================================================
#  4) RINGKASAN + KONFIRMASI
# ============================================================
header
echo -e "${C_B}=================== RINGKASAN ===================${C_N}"
echo -e "  OS            : ${C_G}$OSNAME${C_N}"
[ -n "$WINIMG" ] && echo -e "  Windows image : $WINIMG"
[ -n "$DDIMG" ]  && echo -e "  DD image      : $DDIMG"
echo -e "  Hostname      : $HOSTNAME_IN"
echo -e "  Username      : $USERNAME_IN"
echo -e "  Password      : ${C_Y}********${C_N}"
echo -e "  Port $PORT_LABEL     : $PORT_IN"
if [ "$RAID_CAPABLE" = "1" ]; then
  echo -e "  Disk OS       : /dev/$OS_DISK"
  if [ "$RAID_TECH" = "none" ]; then
    echo -e "  RAID          : tidak (single disk)"
  else
    echo -e "  RAID          : ${C_G}$RAID_TECH ${RAID_LEVEL}${C_N}"
    echo -e "  Disk RAID     : $RAID_DISKS"
    [ -n "$RAID_FS" ] && [ "$RAID_TECH" = "mdadm" ] && \
      { [ "$OSNAME" = "pve" ] && echo -e "  Di atas array : LVM-thin (storage akuma-thin)" || \
        [ "$RAID_FS" = "ext4" ] && echo -e "  Filesystem    : ext4 di /mnt/akuma-data"; }
    [ "$RAID_TECH" = "zfs" ] && echo -e "  ZFS pool      : akuma-tank"
  fi
fi
echo -e "${C_B}=================================================${C_N}"
echo ""
confirm "Lanjut eksekusi? DATA DI DISK TERPILIH AKAN HILANG!" || die "Canceled by user!"

# ============================================================
#  5) EKSEKUSI
# ============================================================
header
info "Download reinstall.sh terbaru dari fork..."
fetch "$CONFHOME/reinstall.sh" ./reinstall.sh || die "Gagal download reinstall.sh"
chmod +x reinstall.sh

if [ "$RAID_CAPABLE" = "1" ] && [ "$RAID_TECH" != "none" ]; then
  # ----------------------------------------------------------
  #  Dengan RAID: linux + --cloud-data berisi bootstrap script
  #  (PVE: debian 13 + setup PVE; OS lain: RAID setup doang)
  # ----------------------------------------------------------
  info "Menyiapkan cloud-data (RAID bootstrap)..."
  TMPD=$(mktemp -d)
  fetch "$CONFHOME/akuma-raid-setup.sh" "$TMPD/akuma-raid-setup.sh" \
    || die "Gagal download akuma-raid-setup.sh"

  RAID_INDENTED=$(sed 's/^/      /' "$TMPD/akuma-raid-setup.sh")

  # file tambahan khusus PVE: bootstrap PVE sendiri
  PVE_FILES=""
  if [ "$OSNAME" = "pve" ]; then
    fetch "$CONFHOME/akuma-pve-setup.sh" "$TMPD/akuma-pve-setup.sh" \
      || die "Gagal download akuma-pve-setup.sh"
    PVE_INDENTED=$(sed 's/^/      /' "$TMPD/akuma-pve-setup.sh")
    PVE_FILES="
  - path: /root/akuma-pve-setup.sh
    content: |
$PVE_INDENTED"
    PVE_RUNCMD="
  - bash /root/akuma-pve-setup.sh"
  fi

  cat > "$TMPD/user-data" <<UDEOF
#cloud-config
disable_root: false
ssh_pwauth: true
write_files:
  - path: /root/akuma-raid.conf
    content: |
      AKUMA_OS_DISK='$OS_DISK'
      AKUMA_RAID_TECH='$RAID_TECH'
      AKUMA_RAID_LEVEL='$RAID_LEVEL'
      AKUMA_RAID_DISKS='$RAID_DISKS'
      AKUMA_RAID_FS='$RAID_FS'
  - path: /root/akuma-raid-setup.sh
    content: |
$RAID_INDENTED$PVE_FILES
runcmd:
  - chmod +x /root/akuma-raid-setup.sh
  - bash /root/akuma-raid-setup.sh$PVE_RUNCMD
UDEOF
  touch "$TMPD/meta-data"

  case "$OSNAME" in
    pve)
      info "Menjalankan reinstall (Debian 13 + PVE bootstrap)..."
      bash reinstall.sh debian 13 \
        --password "$PASSWORD_IN" \
        --ssh-port "$PORT_IN" \
        --cloud-data "$TMPD"
      ;;
    *)
      info "Menjalankan reinstall ($OSNAME + RAID bootstrap)..."
      bash reinstall.sh "$OSNAME" \
        --username "$USERNAME_IN" \
        --password "$PASSWORD_IN" \
        --ssh-port "$PORT_IN" \
        --cloud-data "$TMPD"
      ;;
  esac
  rm -rf "$TMPD"

elif [ "$OSNAME" = "dd" ]; then
  bash reinstall.sh dd --img "$DDIMG"

elif [ "$OSNAME" = "windows" ]; then
  bash reinstall.sh windows \
    --image-name "$WINIMG" \
    --iso "$WINISO" \
    --username "$USERNAME_IN" \
    --password "$PASSWORD_IN" \
    --rdp-port "$PORT_IN" \
    --allow-ping

else
  bash reinstall.sh "$OSNAME" \
    --username "$USERNAME_IN" \
    --password "$PASSWORD_IN" \
    --ssh-port "$PORT_IN"
fi

echo ""
info "Selesai. Reboot server untuk mulai instalasi OS baru."
