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

set "LOGFILE=C:\Windows\Temp\provision.log"
if not exist "C:\Windows\Temp" mkdir "C:\Windows\Temp" >nul 2>&1
echo [%date% %time%] Provisioning started >> "%LOGFILE%"

rem Disable IPv6 identifier randomization
netsh interface ipv6 set global randomizeidentifiers=disabled >> "%LOGFILE%" 2>&1

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

if not defined id (
    echo [%date% %time%] ERROR: Could not resolve InterfaceIndex for MAC %mac_addr% >> "%LOGFILE%"
) else (
    echo [%date% %time%] Resolved interface id=!id! for MAC %mac_addr% >> "%LOGFILE%"

    if defined ipv4_addr if defined ipv4_gateway (
        netsh interface ipv4 set address !id! static %ipv4_addr% gateway=%ipv4_gateway% gwmetric=0 >> "%LOGFILE%" 2>&1
    )

    for %%i in (1, 2) do (
        if defined ipv4_dns%%i (
            netsh interface ipv4 add | findstr "dnsservers" >nul
            if !errorlevel! neq 0 (
                netsh interface ipv4 add dnsserver !id! !ipv4_dns%%i! %%i >> "%LOGFILE%" 2>&1
            ) else (
                netsh interface ipv4 add dnsservers !id! !ipv4_dns%%i! %%i no >> "%LOGFILE%" 2>&1
            )
        )
    )

    if defined ipv6_addr if defined ipv6_gateway (
        netsh interface ipv6 set address !id! %ipv6_addr% >> "%LOGFILE%" 2>&1
        netsh interface ipv6 add route prefix=::/0 !id! %ipv6_gateway% >> "%LOGFILE%" 2>&1
    )

    for %%i in (1, 2) do (
        if defined ipv6_dns%%i (
            netsh interface ipv6 add | findstr "dnsservers" >nul
            if !errorlevel! neq 0 (
                netsh interface ipv6 add dnsserver !id! !ipv6_dns%%i! %%i >> "%LOGFILE%" 2>&1
            ) else (
                netsh interface ipv6 add dnsservers !id! !ipv6_dns%%i! %%i no >> "%LOGFILE%" 2>&1
            )
        )
    )
)

:skip_network

REM Remove memory dump files
del /q /f "C:\Windows\*.DMP" 2>nul
for /d %%D in ("C:\Windows\Minidump") do rd /s /q "%%D" 2>nul
echo [%date% %time%] Dump files cleaned >> "%LOGFILE%"

REM --- Download and install Qemu Agent ---
echo [%date% %time%] Downloading virtio-win-guest-tools... >> "%LOGFILE%"
powershell -NoLogo -NoProfile -Command ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { (New-Object System.Net.WebClient).DownloadFile('https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.285-1/virtio-win-guest-tools.exe','C:\Windows\Temp\virtio-win-guest-tools.exe') } catch { Add-Content -Path '%LOGFILE%' -Value ('DOWNLOAD FAILED (virtio): ' + $_.Exception.Message) }" <NUL

if exist "C:\Windows\Temp\virtio-win-guest-tools.exe" (
    echo [%date% %time%] Installing virtio-win-guest-tools... >> "%LOGFILE%"
    cmd /c "C:\Windows\Temp\virtio-win-guest-tools.exe" /quiet /norestart
    echo [%date% %time%] virtio install exit code: !errorlevel! >> "%LOGFILE%"
    del "C:\Windows\Temp\virtio-win-guest-tools.exe"
) else (
    echo [%date% %time%] ERROR: virtio-win-guest-tools.exe not found after download attempt >> "%LOGFILE%"
)

REM --- Download and run system optimizer ---
echo [%date% %time%] Downloading optimize.exe... >> "%LOGFILE%"
powershell -NoLogo -NoProfile -Command ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { (New-Object System.Net.WebClient).DownloadFile('https://install.virtfusion.net/optimize.exe','C:\Windows\Temp\optimize.exe') } catch { Add-Content -Path '%LOGFILE%' -Value ('DOWNLOAD FAILED (optimize): ' + $_.Exception.Message) }" <NUL

if exist "C:\Windows\Temp\optimize.exe" (
    echo [%date% %time%] Running optimize.exe... >> "%LOGFILE%"
    cmd /c "C:\Windows\Temp\optimize.exe" -v -o -g -windowsupdate disable -storeapp remove-all >> "%LOGFILE%" 2>&1
    cmd /c "C:\Windows\Temp\optimize.exe" -f 3 4 5 6 9 >> "%LOGFILE%" 2>&1
    del "C:\Windows\Temp\optimize.exe"
) else (
    echo [%date% %time%] ERROR: optimize.exe not found after download attempt >> "%LOGFILE%"
)

REM --- Download and Install Google Chrome Silently ---
echo [%date% %time%] Downloading Google Chrome Enterprise Installer... >> "%LOGFILE%"
powershell -NoLogo -NoProfile -Command ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { (New-Object System.Net.WebClient).DownloadFile('https://dl.google.com/chrome/install/googlechromestandaloneenterprise64.msi','C:\Windows\Temp\chrome_installer.msi') } catch { Add-Content -Path '%LOGFILE%' -Value ('DOWNLOAD FAILED (chrome): ' + $_.Exception.Message) }" <NUL

if exist "C:\Windows\Temp\chrome_installer.msi" (
    echo [%date% %time%] Installing Google Chrome... >> "%LOGFILE%"
    msiexec /i "C:\Windows\Temp\chrome_installer.msi" /qn /norestart
    echo [%date% %time%] Chrome install exit code: !errorlevel! >> "%LOGFILE%"
    del "C:\Windows\Temp\chrome_installer.msi"
) else (
    echo [%date% %time%] ERROR: chrome_installer.msi not found after download attempt >> "%LOGFILE%"
)

REM --- Uninstall Internet Explorer if it exists ---
echo [%date% %time%] Checking for Internet Explorer optional feature... >> "%LOGFILE%"
dism /online /Get-FeatureInfo /FeatureName:Internet-Explorer-Optional-amd64 >> "%LOGFILE%" 2>&1
if !errorlevel! equ 0 (
    echo [%date% %time%] Removing Internet Explorer... >> "%LOGFILE%"
    dism /online /Disable-Feature /FeatureName:Internet-Explorer-Optional-amd64 /norestart >> "%LOGFILE%" 2>&1
) else (
    echo [%date% %time%] IE feature not found or DISM query failed (errorlevel !errorlevel!) >> "%LOGFILE%"
)

REM --- Set account lockout threshold to 0 ---
net accounts /lockoutthreshold:0 >> "%LOGFILE%" 2>&1
net accounts | find /i "Lockout threshold" >> "%LOGFILE%"

REM --- Disable Ctrl+Alt+Del requirement on login ---
echo [%date% %time%] Disabling Ctrl+Alt+Del secure sign-in... >> "%LOGFILE%"
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableCAD /t REG_DWORD /d 1 /f >> "%LOGFILE%" 2>&1
rem Also cover RDP sessions, which ignore the key above
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v fDisableCAD /t REG_DWORD /d 1 /f >> "%LOGFILE%" 2>&1

echo [%date% %time%] Detecting Windows Server version... >> "%LOGFILE%"

for /f "tokens=*" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName 2^>nul') do (
    set "reg_output=%%a"
    for /f "tokens=2,*" %%b in ("!reg_output!") do set "osname=%%c"
)

set "osarch=%PROCESSOR_ARCHITECTURE%"
echo [%date% %time%] OS Info: !osname! [Build: !osarch!] >> "%LOGFILE%"

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
    echo [%date% %time%] ERROR: Unsupported operating system detected: !osname! >> "%LOGFILE%"
    exit /b 1
)

echo !osname! | find /i "Evaluation" >nul
if !errorlevel! equ 0 (
    echo [%date% %time%] Evaluation edition detected. Converting to !DismTarget! via DISM... >> "%LOGFILE%"
    dism /online /set-edition:!DismTarget! /productkey:!ProductKey! /accepteula /norestart >> "%LOGFILE%" 2>&1
    echo [%date% %time%] Edition conversion exit code: !errorlevel! >> "%LOGFILE%"
)

echo [%date% %time%] Processing Windows Volume Activation for !OSVersion!... >> "%LOGFILE%"
cscript //nologo %windir%\system32\slmgr.vbs /ipk !ProductKey! >> "%LOGFILE%" 2>&1
cscript //nologo %windir%\system32\slmgr.vbs /skms kms8.msguides.com >> "%LOGFILE%" 2>&1
cscript //nologo %windir%\system32\slmgr.vbs /ato >> "%LOGFILE%" 2>&1

echo [%date% %time%] Activation sequence completed. >> "%LOGFILE%"

echo [%date% %time%] Scheduling reboot in 15 seconds... >> "%LOGFILE%"
endlocal

rem Delete script file after execution
del "%~f0"
