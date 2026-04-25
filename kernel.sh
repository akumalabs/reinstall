#!/usr/bin/env bash

#if [[ $EUID -ne 0 ]]; then
#    clear
#   echo "Error: This script must be run as root!" 1>&2
#    exit 1
#fi

if [ -f "/usr/bin/yum" ] && [ -d "/etc/yum.repos.d" ]; then
    yum update -y
    yum install -y wget curl
    
elif [ -f "/usr/bin/apt-get" ] && [ -f "/usr/bin/dpkg" ]; then
    apt-get update --fix-missing
    apt install -y curl wget
    
fi

function CopyRight() {
  clear
  echo "########################################################"
  echo "#                                                      #"
  echo "#               Auto Reinstall Script                  #"
  echo "#                                                      #"
  echo "#               Author: AKUMAVM                        #"
  echo "#               Last Modified: 11-11-2025              #"
  echo "#                                                      #"
  echo "#               Inspired by bin456789                  #"
  echo "#                                                      #"
  echo "########################################################"
  echo -e "\n"
}

function Start() {
  CopyRight
  
curl -O https://raw.githubusercontent.com/akumalabs/reinstall/main/reinstall.sh || wget -O reinstall.sh $_


  echo -e "\nPlease select an OS:"
  echo "  1) Latest Debian"
  echo "  2) Latest Ubuntu"
  echo "  3) Latest Almalinux"
  echo "  4) Latest Alpine Linux"
  echo "  5) Latest CentOS"
  echo "  6) Kali Linux"
  #echo "  7) Windows 10 Pro"
  #echo "  8) Windows 11 Pro"
  echo "  9) Windows Server 2012 R2 DC"
  echo "  10) Windows Server 2016 DC"
  echo "  11) Windows Server 2019 DC"
  echo "  12) Windows Server 2022 DC"
  echo "  13) Windows Server 2025 DC"
  echo "  14) Windows Tiny 10 (BIOS)"
  echo "  15) Windows Tiny 11 (BIOS)"
  echo "  16) Windows Tiny 10 (UEFI)"
  echo "  17) Windows Tiny 11 (UEFI)"
  echo "  18) Netboot"
  echo "  19) Windows Server 2019 (Template AdOp)"
  echo "  99) Custom DD image"
  echo "  0) Exit"
  echo -ne "\nYour option: "
  read N
  case $N in
    1) bash reinstall.sh debian --password 123@@@ ;;
    2) bash reinstall.sh ubuntu --password 123@@@ ;;
    3) bash reinstall.sh alma --password 123@@@ ;;
    4) bash reinstall.sh alpine --password 123@@@ ;;
    5) bash reinstall.sh centos --password 123@@@ ;;
    6) bash reinstall.sh kali --password 123@@@ ;;
    #7) bash reinstall.sh windows --image-name='Windows 10 Pro' --iso='https://cloclo53.datacloudmail.ru/public/get/qjip4r6AhW1Hd5gCXn5yqHK9eB8LLgRwVygJDHCrUwhHwsCHgA6vLkqEC8oTiXjtAo14p2Pc5jNKxNbEM5YJwK4dWwk3ZEFp2Y4iE4nSdczKp4pRSuTnEFMmDMbcjAiSEcyNPwp57tTK3qURpxYNsk9BzE9rmKpetXPAs2crrfKftmsKPwmvuPikYJdA7VfPArd2FojrYfcsbdwUFYoTu7WhZwEVGJLzsB4uS4UXzfvn2YcpveJcvAyGC6zeGi7Ndjh4TKit61eb2Y7Ku35w2ZwTRyhvP76Wt3vRz235PAryNiTi69goztfXhsVNJpiRU2kYJUVrPRL2CeVQANK1isGKsVJNPEpdguw3WjUGvYQR9gygBCMSWCjh2rmgb35KyUcioSBkUCDidxh4ENwUq72/no/en_windows_10_version_22h2_with_update_19045.7184_aio_16in1_x64_v26.04.14_by_adguard.iso' --password Akuma12345 --allow-ping ;;
    #8) bash reinstall.sh windows --image-name='Windows 11 Pro' --iso='https://cloclo58.datacloudmail.ru/public/get/qjip4r6AhW1Hd5gFF4H4keY6UwyzNG5B1WR44x5m3MH5q91PVfmLvDmuU5aDsByLqKSitRRkiYM1a1kG53qcUYtWFTsjQCbwSoQ6pqyuY2fKxCDaFAuFiG8z4bNy7MiMPx3svSTk4nek3NjygCVQbdcVJtcE7Si5EpkZDVf26EhWGVgjop748aTwHSRaW5EohiHzRRT2ktMfCPxo8xLMy2MGgaymuCgZedCNGoMGt615tyjgJ3Hc4JAvCxd9df9T5bDQSRyTT17vL3P2zRJce9MycRji5JCP6C9p9bhHtFi1fiQ98L58jYMpCf7jGWnz5nEF9XkthXYiKQu7eEmhs1zQhWvxqgZjwbTDVnTMWkwESN9Wtf4sEfPuPdMKtzeGPLsw2Ls7ayfJg5sNBurQ1Rk/no/en_windows_11_version_25h2_with_update_26200.8246_aio_19in1_x64_v26.04.14_by_adguard.iso' --password Akuma12345 --allow-ping ;;
    9) bash reinstall.sh windows --image-name='Windows Server 2012 R2 SERVERDATACENTER' --iso='https://go.microsoft.com/fwlink/p/?LinkID=2195443' --password Akuma12345 --allow-ping ;;
    10) bash reinstall.sh windows --image-name='Windows Server 2016 SERVERDATACENTER' --iso='https://go.microsoft.com/fwlink/p/?LinkID=2195174' --password Akuma12345 --allow-ping ;;
    11) bash reinstall.sh windows --image-name='Windows Server 2019 SERVERDATACENTER' --iso='https://go.microsoft.com/fwlink/p/?LinkID=2195167' --password Akuma12345 --allow-ping ;;
    12) bash reinstall.sh windows --image-name='Windows Server 2022 SERVERDATACENTER' --iso='https://go.microsoft.com/fwlink/p/?LinkID=2195280' --password Akuma12345 --allow-ping ;;
    13) bash reinstall.sh windows --image-name='Windows Server 2025 SERVERDATACENTER' --iso='https://go.microsoft.com/fwlink/p/?LinkID=2293312' --password Akuma12345 --allow-ping ;;
    14) bash reinstall.sh dd --img='https://dl.lamp.sh/vhd/tiny10_23h2.xz' --password Akuma12345 --allow-ping ;;
    15) bash reinstall.sh dd --img='https://dl.lamp.sh/vhd/tiny11_23h2.xz' --password Akuma12345 --allow-ping ;;
    16) bash reinstall.sh dd --img='https://dl.lamp.sh/vhd/tiny10_23h2_uefi.xz' --password Akuma12345 --allow-ping ;;
    17) bash reinstall.sh dd --img='https://dl.lamp.sh/vhd/tiny11_23h2_uefi.xz' --password Akuma12345 --allow-ping ;;
    18) bash reinstall.sh netboot.xyz ;;
    19) bash reinstall.sh dd --img='https://cp.akumalabs.com/storage/images/win2019.xz' --password Akuma12345 --allow-ping ;;
    99)
      echo -e "\n"
      read -r -p "Custom DD image URL: " imgURL
      echo -e "\n"
      read -r -p "Are you sure start reinstall? [y/N]: " input
      case $input in
        [yY][eE][sS]|[yY]) bash reinstall.sh dd --img $imgURL ;;
        *) clear; echo "Canceled by user!"; exit 1;;
      esac
      ;;
    0) exit 0;;
    *) echo "Wrong input!"; exit 1;;
esac
}
Start
