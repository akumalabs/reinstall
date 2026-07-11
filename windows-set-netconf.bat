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

rem 禁用 IPv6 地址标识符的随机化，防止 IPv6 和后台面板不一致
netsh interface ipv6 set global randomizeidentifiers=disabled

rem --- NEW LOGIC: Skip ONLY network config if mac_addr isn't defined ---
if not defined mac_addr goto :skip_network

rem vista 没有自带 powershell
rem win11 24h2 安装后有 wmic，但是过一段时间会自动删除，因此有的 dd 镜像没有 wmic
if exist "%windir%\system32\wbem\wmic.exe" (
    rem wmic 换行符是 \r\r\n
    rem 虽然这里用了 findstr 全字匹配 ，但是结尾还是有 \r
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
    rem 配置静态 IPv4 地址和网关
    if defined ipv4_addr if defined ipv4_gateway (
        rem 如果使用了 setlocal EnableDelayedExpansion
        rem netsh interface ipv4 set address !id! static %ipv4_addr% gateway=%ipv4_gateway% gwmetric=0
        rem !id! 变量最后有 \r 会导致语句不正确
        rem %id% 变量则没有这个问题

        rem gwmetric 默认值为 1，自动跃点需设为 0
        netsh interface ipv4 set address %id% static %ipv4_addr% gateway=%ipv4_gateway% gwmetric=0
    )

    rem 配置静态 IPv4 DNS 服务器
    for %%i in (1, 2) do (
        if defined ipv4_dns%%i (
            netsh interface ipv4 add | findstr "dnsservers" >nul
            if ErrorLevel 1 (
                rem vista
                setlocal EnableDelayedExpansion
                netsh interface ipv4 add dnsserver %id% !ipv4_dns%%i! %%i
                endlocal
            ) else (
                rem win7
                setlocal EnableDelayedExpansion
                netsh interface ipv4 add dnsservers %id% !ipv4_dns%%i! %%i no
                endlocal
            )
        )
    )

    rem 配置 IPv6 地址和网关
    if defined ipv6_addr if defined ipv6_gateway (
        netsh interface ipv6 set address %id% %ipv6_addr%
        netsh interface ipv6 add route prefix=::/0 %id% %ipv6_gateway%
    )

    rem 配置 IPv6 DNS 服务器
    for %%i in (1, 2) do (
        if defined ipv6_dns%%i (
            netsh interface ipv6 add | findstr "dnsservers" >nul
            if ErrorLevel 1 (
                rem vista
                setlocal EnableDelayedExpansion
                netsh interface ipv6 add dnsserver %id% !ipv6_dns%%i! %%i
                endlocal
            ) else (
                rem win7
                setlocal EnableDelayedExpansion
                netsh interface ipv6 add dnsservers %id% !ipv6_dns%%i! %%i no
                endlocal
            )
        )
    )
)
:skip_network
rem --- Network block ends; the rest of the script will now run safely ---

REM Remove memory dump files
del /q /f "C:\Windows\*.DMP"
for /d %%D in ("C:\Windows\Minidump") do rd /s /q "%%D"

REM Download and run system optimizer
powershell -Command "(New-Object System.Net.WebClient).DownloadFile('https://install.virtfusion.net/optimize.exe', 'C:\Windows\Temp\optimize.exe')" <NUL
cmd /c C:\Windows\Temp\optimize.exe -v -o -g -windowsupdate disable -storeapp remove-all -antivirus disable
cmd /c C:\Windows\Temp\optimize.exe -f 3 4 5 6 9
del C:\Windows\Temp\optimize.exe

REM Set account lockout threshold to 0 (disable)
net accounts /lockoutthreshold:0

echo Detecting Windows Server version...
echo.

for /f "tokens=4-5 delims=[.]" %%i in ('ver') do (
    set /a "major=%%i"
    set /a "minor=%%j"
)

for /f "tokens=*" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v ProductName 2^>nul') do (
    set "reg_output=%%a"
    for /f "tokens=2,*" %%b in ("!reg_output!") do set "osname=%%c"
)

set "osarch=%PROCESSOR_ARCHITECTURE%"
echo OS Info: !osname! [Build: !osarch!]
echo.

set "ProductKey="
set "OSVersion="

:: Check for Windows Server 2025
echo !osname! | find /i "2025" >nul
if !errorlevel! equ 0 (
    echo !osname! | find /i "Datacenter" >nul
    if !errorlevel! equ 0 (
        set "ProductKey=D764K-2NDRG-47T6Q-P8T8W-YP6DF"
        set "OSVersion=Windows Server 2025 Datacenter"
    ) else (
        echo !osname! | find /i "Standard" >nul
        if !errorlevel! equ 0 (
            set "ProductKey=TVRH6-WHNXV-R9WG3-9XRFY-MY832"
            set "OSVersion=Windows Server 2025 Standard"
        )
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
        ) else (
            echo !osname! | find /i "Standard" >nul
            if !errorlevel! equ 0 (
                set "ProductKey=VDYBN-27WPP-V4HQT-9VMD4-VMK7H"
                set "OSVersion=Windows Server 2022 Standard"
            )
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
        ) else (
            echo !osname! | find /i "Standard" >nul
            if !errorlevel! equ 0 (
                set "ProductKey=N69G4-B89J2-4G8F4-WWYCC-J464C"
                set "OSVersion=Windows Server 2019 Standard"
            )
        )
    )
)

:: If no supported OS detected
if not defined ProductKey (
    echo ERROR: Unsupported operating system detected.
    echo Detected: !osname!
    echo Supported versions: Windows Server 2019/2022/2025 Standard/Datacenter
    pause
    exit /b 1
)

echo.
echo Processing Windows...
echo Installing Product Key for !OSVersion!
echo Key: [!ProductKey!]

echo.
echo Activating Volume Products...
cscript //nologo %windir%\system32\slmgr.vbs /ipk %ProductKey% >nul 2>&1
if !errorlevel! neq 0 (
    echo ERROR: Failed to install product key
    pause
    exit /b 1
)

cscript //nologo %windir%\system32\slmgr.vbs /skms kms8.msguides.com >nul 2>&1
if !errorlevel! neq 0 (
    echo ERROR: Failed to set KMS server
    pause
    exit /b 1
)

cscript //nologo %windir%\system32\slmgr.vbs /ato >nul 2>&1
if !errorlevel! neq 0 (
    echo ERROR: Activation failed
    pause
    exit /b 1
)

echo.
echo !OSVersion! is successfully activated for 180 days.
endlocal

rem 删除此脚本
del "%~f0"
