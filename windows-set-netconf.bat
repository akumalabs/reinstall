rem set mac_addr=11:22:33:aa:bb:cc
rem set ipv4_addr=192.168.1.2/24
rem set ipv4_gateway=192.168.1.1
rem set ipv4_dns1=192.168.1.1
rem set ipv4_dns2=192.168.1.2
rem set ipv6_addr=2222::2/64
rem set ipv6_gateway=2222::1
rem set ipv6_dns1=::1
rem set ipv6_dns2=::2

@echo off
setlocal enabledelayedexpansion
mode con cp select=437 >nul

rem 禁用 IPv6 地址标识符的随机化
netsh interface ipv6 set global randomizeidentifiers=disabled

rem --- Skip ONLY network config if mac_addr isn't defined ---
if not defined mac_addr goto :skip_network

if exist "%windir%\system32\wbem\wmic.exe" (
    for /f "tokens=2 delims==" %%a in (
        'wmic nic where "MACAddress='%mac_addr%'" get InterfaceIndex /format:list ^| findstr "^InterfaceIndex=[0-9][0-9]*$"'
    ) do set id=%%a
)

if not defined id (
    for /f %%a in ('powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass ^
        -Command "(Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.MACAddress -eq '%mac_addr%' }).InterfaceIndex" ^| findstr "^[0-9][0-9]*$"'
    ) do set id=%%a
)

if not defined id (
    for /f %%a in ('powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass ^
        -Command "(Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.MACAddress -eq '%mac_addr%' }).InterfaceIndex" ^| findstr "^[0-9][0-9]*$"'
    ) do set id=%%a
)

if defined id (
    if defined ipv4_addr if defined ipv4_gateway (
        netsh interface ipv4 set address %id% static %ipv4_addr% gateway=%ipv4_gateway% gwmetric=0
    )

    for %%i in (1, 2) do (
        if defined ipv4_dns%%i (
            netsh interface ipv4 add | findstr "dnsservers" >nul
            if !errorlevel! neq 0 (
                netsh interface ipv4 add dnsserver %id% !ipv4_dns%%i! %%i
            ) else (
                netsh interface ipv4 add dnsservers %id% !ipv4_dns%%i! %%i no
            )
        )
    )

    if defined ipv6_addr if defined ipv6_gateway (
        netsh interface ipv6 set address %id% %ipv6_addr%
        netsh interface ipv6 add route prefix=::/0 %id% %ipv6_gateway%
    )

    for %%i in (1, 2) do (
        if defined ipv6_dns%%i (
            netsh interface ipv6 add | findstr "dnsservers" >nul
            if !errorlevel! neq 0 (
                netsh interface ipv6 add dnsserver %id% !ipv6_dns%%i! %%i
            ) else (
                netsh interface ipv6 add dnsservers %id% !ipv6_dns%%i! %%i no
            )
        )
    )
)

:skip_network

REM Remove memory dump files
del /q /f "C:\Windows\*.DMP" 2>nul
for /d %%D in ("C:\Windows\Minidump") do rd /s /q "%%D" 2>nul

REM Download and install Qemu Agent
powershell -Command "(New-Object System.Net.WebClient).DownloadFile('https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.285-1/virtio-win-guest-tools.exe', 'C:\Windows\Temp\virtio-win-guest-tools.exe')" <NUL
cmd /c C:\Windows\Temp\virtio-win-guest-tools.exe /quiet /norestart
del C:\Windows\Temp\virtio-win-guest-tools.exe

REM Download and run system optimizer
powershell -Command "(New-Object System.Net.WebClient).DownloadFile('https://install.virtfusion.net/optimize.exe', 'C:\Windows\Temp\optimize.exe')" <NUL
if exist "C:\Windows\Temp\optimize.exe" (
    cmd /c C:\Windows\Temp\optimize.exe -v -o -g -windowsupdate disable -storeapp remove-all -antivirus disable
    cmd /c C:\Windows\Temp\optimize.exe -f 3 4 5 6 9
    del C:\Windows\Temp\optimize.exe
)

REM Download and Install Google Chrome Silently ---
echo Downloading Google Chrome Enterprise Installer...
powershell -Command "(New-Object System.Net.WebClient).DownloadFile('https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi', 'C:\Windows\Temp\chrome_installer.msi')" <NUL
if exist "C:\Windows\Temp\chrome_installer.msi" (
    echo Installing Google Chrome...
    msiexec /i "C:\Windows\Temp\chrome_installer.msi" /qn /norestart
    del "C:\Windows\Temp\chrome_installer.msi"
)

REM Set account lockout threshold to 0 (explicitly run via sysnative if needed)
net accounts /lockoutthreshold:0

net accounts | find /i "Lockout threshold"

echo Detecting Windows Server version...
echo.

for /f "tokens=*" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName 2^>nul') do (
    set "reg_output=%%a"
    for /f "tokens=2,*" %%b in ("!reg_output!") do set "osname=%%c"
)

set "osarch=%PROCESSOR_ARCHITECTURE%"
echo OS Info: !osname! [Build: !osarch!]
echo.

set "ProductKey="
set "OSVersion="
set "DismTarget="

:: Check for Windows Server 2025
echo !osname! | find /i "2025" >nul
if !errorlevel! equ 0 (
    echo !osname! | find /i "Datacenter" >nul
    if !errorlevel! equ 0 (
        set "ProductKey=D764K-2NDRG-47T6Q-P8T8W-YP6DF"
        set "OSVersion=Windows Server 2025 Datacenter"
        set "DismTarget=ServerDatacenter"
    ) else (
        set "ProductKey=TVRH6-WHNXV-R9WG3-9XRFY-MY832"
        set "OSVersion=Windows Server 2025 Standard"
        set "DismTarget=ServerStandard"
    )
)

:: Check for Windows Server 2022
if not defined ProductKey (
    echo !osname! | find /i "2022" >nul
    if !errorlevel! equ 0 (
        echo !osname! | find /i "Datacenter" >nul
        if !errorlevel! equ 0 (
            set "ProductKey=WX4NM-KYWYW-QJJR4-XV3QB-6VM33"
            set "OSVersion=Windows Server 2022 Datacenter"
            set "DismTarget=ServerDatacenter"
        ) else (
            set "ProductKey=VDYBN-27WPP-V4HQT-9VMD4-VMK7H"
            set "OSVersion=Windows Server 2022 Standard"
            set "DismTarget=ServerStandard"
        )
    )
)

:: Check for Windows Server 2019
if not defined ProductKey (
    echo !osname! | find /i "2019" >nul
    if !errorlevel! equ 0 (
        echo !osname! | find /i "Datacenter" >nul
        if !errorlevel! equ 0 (
            set "ProductKey=WMDGN-G9PQG-XVVXX-R3X43-63DFG"
            set "OSVersion=Windows Server 2019 Datacenter"
            set "DismTarget=ServerDatacenter"
        ) else (
            set "ProductKey=N69G4-B89J2-4G8F4-WWYCC-J464C"
            set "OSVersion=Windows Server 2019 Standard"
            set "DismTarget=ServerStandard"
        )
    )
)

if not defined ProductKey (
    echo ERROR: Unsupported operating system detected.
    echo Detected: !osname!
    pause
    exit /b 1
)

echo Check if system is Evaluation edition...
echo !osname! | find /i "Evaluation" >nul
if !errorlevel! equ 0 (
    echo System is an Evaluation edition. Converting to retail target edition via DISM...
    dism /online /set-edition:!DismTarget! /productkey:!ProductKey! /accepteula /norestart
    echo Edition conversion completed. Proceeding to activation...
)

echo.
echo Processing Windows Volume Activation...
cscript //nologo %windir%\system32\slmgr.vbs /ipk !ProductKey! >nul 2>&1

cscript //nologo %windir%\system32\slmgr.vbs /skms kms8.msguides.com >nul 2>&1

cscript //nologo %windir%\system32\slmgr.vbs /ato

echo.
echo Activation sequence completed.
endlocal

rem Delete script file after execution
del "%~f0"
