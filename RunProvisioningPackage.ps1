param(
    $provisioningPackageBlob,
    $userUPN
)

# create c:\temp if it doesn't exist
if(!(Test-Path 'c:\temp')){
    New-Item -Path 'C:\temp' -ItemType Directory -Force | Out-Null
}

# Download provisioning package
Invoke-WebRequest -Uri $provisioningPackageBlob -OutFile 'c:\temp\provisioningPackage.zip'

# extract provisioning package
Expand-Archive -Path 'c:\temp\provisioningPackage.zip' -DestinationPath 'c:\temp\provisioningPackage\' -force

#Disable NLA
(Get-WmiObject -class Win32_TSGeneralSetting -Namespace root\cimv2\terminalservices -ComputerName '.' -Filter "TerminalName='RDP-tcp'").SetUserAuthenticationRequired(0)

# run provisioning package
Install-ProvisioningPackage -PackagePath c:\temp\provisioningPackage\TrialRun.ppkg -QuietInstall

