#!/usr/bin/env bash
# ============================================================
#   AKUMA Auto Reinstall — Interactive Wizard
#   Author : AKUMAVM (fork of bin456789/reinstall)
#   Scope  : kernel.sh — wizard interaktif PVE + RAID
#
#   Alur:
#     1) Pilih OS (Debian/Ubuntu/Alma/Alpine/CentOS/Kali/Windows/Netboot/DD/PVE)
#     2) hostname
#     3) user      (default: root utk linux, Administrator utk Windows)
#     4) password  (+ verifikasi)
#     5) port      (default: 22 SSH / 3389 RDP)
#     6) disk OS   (interactive list dari lsblk)   [khusus PVE]
#     7) khusus PVE: RAID tech (mdadm/zfs/none) + pilih disk array
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
  echo -e "#          AKUMA Auto Reinstall + PVE Wizard           #"
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

ask() { # ask <pertanyaan> <default>  → jawaban di $REPLY
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

# pilih >=2 disk untuk array → $RAID_DISKS (dipisah spasi, tanpa /dev/)
list_disk_raid() {
  echo ""
  echo -e "${C_B}Disk tersisa (KECUALI disk OS ${C_G}/dev/$OS_DISK${C_B}):${C_N}"
  lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null \
    | awk -v od="$OS_DISK" '$3=="disk" && $1!=od {printf "  %-12s %-9s %s\n", "/dev/"$1, $2, $4}'
  echo ""
  while :; do
    read -r -p "$(echo -e "${C_B}?${C_N} Disk RAID (minimal 2, pisah spasi): ")" -a disks_in
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
    if [ "$(echo $RAID_DISKS | wc -w)" -ge 2 ]; then break; fi
    warn "Minimal 2 disk valid buat array."
  done
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
echo -e "${C_G}  14) Proxmox VE  (Debian 13 + auto RAID)${C_N}"
echo "   0) Exit"
echo ""
ask "Your option" ""
N="$REPLY"

USERNAME_DEFAULT="root"; PORT_LABEL="SSH"; PORT_DEFAULT="22"
WINIMG=""; WINISO=""; DDIMG=""
OSNAME=""
case $N in
  1)  OSNAME="debian" ;;
  2)  OSNAME="ubuntu" ;;
  3)  OSNAME="alma" ;;
  4)  OSNAME="alpine" ;;
  5)  OSNAME="centos" ;;
  6)  OSNAME="kali" ;;
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
  14) OSNAME="pve" ;;
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
#  3) KHUSUS PVE: DISK OS + RAID
# ============================================================
OS_DISK=""; RAID_TECH="none"; RAID_LEVEL=""; RAID_DISKS=""

if [ "$OSNAME" = "pve" ]; then
  header
  list_disk_os

  header
  echo -e "${C_B}RAID technology untuk data storage:${C_N}"
  echo "   1) mdadm  (RAID1 / RAID10 → LVM-thin, simple & ringan)"
  echo "   2) ZFS    (mirror / RAIDZ1 → native PVE, snapshot & compression)"
  echo "   3) Tanpa RAID (skip data array)"
  echo ""
  ask "RAID option" "3"
  case $REPLY in
    1)
      RAID_TECH="mdadm"
      echo ""; echo -e "${C_B}mdadm level:${C_N}"
      echo "   1) RAID1  (mirror, 2 disk)"
      echo "   2) RAID10 (min 4 disk, genap)"
      ask "Level" "1"
      case $REPLY in
        1) RAID_LEVEL="raid1" ;;
        2) RAID_LEVEL="raid10" ;;
        *) die "Wrong level" ;;
      esac
      ;;
    2)
      RAID_TECH="zfs"
      echo ""; echo -e "${C_B}ZFS pool layout:${C_N}"
      echo "   1) mirror (2 disk)"
      echo "   2) raidz1 (min 3 disk)"
      ask "Layout" "1"
      case $REPLY in
        1) RAID_LEVEL="mirror" ;;
        2) RAID_LEVEL="raidz1" ;;
        *) die "Wrong layout" ;;
      esac
      ;;
    3) RAID_TECH="none" ;;
    *) die "Wrong input" ;;
  esac

  if [ "$RAID_TECH" != "none" ]; then
    header
    list_disk_raid
    ndev=$(echo $RAID_DISKS | wc -w)
    case "$RAID_LEVEL" in
      raid1)  [ "$ndev" -eq 2 ] || die "RAID1 butuh tepat 2 disk (dapat: $ndev)" ;;
      raid10) { [ "$ndev" -ge 4 ] && [ $((ndev % 2)) -eq 0 ]; } || die "RAID10 butuh >=4 disk genap (dapat: $ndev)" ;;
      mirror) [ "$ndev" -ge 2 ] || die "ZFS mirror butuh >=2 disk" ;;
      raidz1) [ "$ndev" -ge 3 ] || die "RAIDZ1 butuh >=3 disk (dapat: $ndev)" ;;
    esac
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
if [ "$OSNAME" = "pve" ]; then
  echo -e "  Disk OS       : /dev/$OS_DISK"
  echo -e "  RAID          : $RAID_TECH${RAID_LEVEL:+ ($RAID_LEVEL)}"
  [ -n "$RAID_DISKS" ] && echo -e "  Disk RAID     : $RAID_DISKS"
fi
echo -e "${C_B}=================================================${C_N}"
echo ""
confirm "Lanjut eksekusi? DATA DI DISK AKAN HILANG!" || die "Canceled by user!"

# ============================================================
#  5) EKSEKUSI
# ============================================================
header
info "Download reinstall.sh terbaru dari fork..."
fetch "$CONFHOME/reinstall.sh" ./reinstall.sh || die "Gagal download reinstall.sh"
chmod +x reinstall.sh

if [ "$OSNAME" = "pve" ]; then
  # ----------------------------------------------------------
  #  PVE = Debian 13 + --cloud-data (bootstrap script via cloud-init)
  # ----------------------------------------------------------
  info "Menyiapkan cloud-data (PVE bootstrap)..."
  TMPD=$(mktemp -d)
  fetch "$CONFHOME/akuma-pve-setup.sh" "$TMPD/akuma-pve-setup.sh" \
    || die "Gagal download akuma-pve-setup.sh"

  # indentasi script utk embed di user-data YAML (6 spasi)
  SETUP_INDENTED=$(sed 's/^/      /' "$TMPD/akuma-pve-setup.sh")

  cat > "$TMPD/user-data" <<UDEOF
#cloud-config
disable_root: false
ssh_pwauth: true
write_files:
  - path: /root/akuma-pve.conf
    content: |
      AKUMA_HOSTNAME='$HOSTNAME_IN'
      AKUMA_RAID_TECH='$RAID_TECH'
      AKUMA_RAID_LEVEL='$RAID_LEVEL'
      AKUMA_RAID_DISKS='$RAID_DISKS'
  - path: /root/akuma-pve-setup.sh
    content: |
$SETUP_INDENTED
runcmd:
  - chmod +x /root/akuma-pve-setup.sh
  - bash /root/akuma-pve-setup.sh
UDEOF
  touch "$TMPD/meta-data"

  info "Menjalankan reinstall (Debian 13 + cloud-data)..."
  bash reinstall.sh debian 13 \
    --password "$PASSWORD_IN" \
    --ssh-port "$PORT_IN" \
    --cloud-data "$TMPD"
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
