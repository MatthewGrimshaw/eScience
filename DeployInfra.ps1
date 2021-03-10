#variables

$userUPN = "myusername@myorg.com"
$provisioningPackagePath = 'C:\myProvisioningPackage\'


$subscriptionID = "XXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
$location = "westeurope"
$containerName = 'provisioningpackages'

##Start Script 
az login
az account set --subscription $subscriptionID 

#Get OrgName
$dnsOrgName = ($userUPN -split "@")[1]
$orgname = $dnsOrgName.Split(".")[0]

# create Resource Group based on OrgName
az group create --location $location --name $orgname

#create storageaccount for provisioning package
az storage account create `
  --name ($orgname + 'escience') `
  --sku Standard_LRS `
  --https-only $true `
  --location $location `
  --resource-group $orgname

#Get Storage Account name
$storageAccountName = az storage account list `
  --resource-group $orgname `
  --query [0].'name' `
  --output tsv

#Get account key
$artifactsStorageKey = az storage account keys list `
  --account-name $storageAccountName `
  --query [0].value `
  --output tsv

#create container in the Storage account to upload the provisioning package to
az storage container create `
  --name $containerName `
  --account-name $storageAccountName `
  --account-key $artifactsStorageKey 

#Create zip archive for Provisioning Package artifacts
Compress-Archive -Path $provisioningPackagePath\* -DestinationPath .\$orgname.zip -Force -Debug

# upload to storage
$SasToken = az storage container generate-sas `
  --account-name $storageAccountName `
  --name $containerName `
  --account-key $artifactsStorageKey `
  --permissions w `
  --output tsv

    
$connectionString = az storage account show-connection-string `
  --resource-group $orgname `
  --name $storageAccountName `
  --output tsv

## upload artifacts to blob storage
az storage blob upload `
  --name .\$orgname.zip `
  --container-name $containerName.ToLower() `
  --file .\$orgname.zip `
  --account-name $storageAccountName `
  --connection-string $connectionString `
  --sas-token $SasToken 

az storage blob upload `
  --name .\RunProvisioningPackage.ps1 `
  --container-name $containerName.ToLower() `
  --file .\RunProvisioningPackage.ps1 `
  --account-name $storageAccountName `
  --connection-string $connectionString `
  --sas-token $SasToken

#Get data for sas key
$date = (Get-Date).AddMinutes(90).ToString("yyyy-MM-dTH:mZ")
$date = $date.Replace(".", ":")

#Get SAS for powershell script 
$scriptURILocation = az storage blob generate-sas `
  --account-name $storageAccountName `
  --container-name $containerName.ToLower() `
  --name RunProvisioningPackage.ps1 `
  --account-key $artifactsStorageKey `
  --permissions rw `
  --expiry $date `
  --full-uri `
  --output tsv
  
#Get SAS for powershell script 
$provisioningPackageLocation = az storage blob generate-sas `
  --account-name $storageAccountName `
  --container-name $containerName.ToLower() `
  --name "$($orgname).zip" `
  --account-key $artifactsStorageKey `
  --permissions rw `
  --expiry $date `
  --full-uri `
  --output tsv
   
#Fix up parameters file
$tempParameterFile = '.\temp-eScienceVM.deployment.paramaters.json'
Copy-Item .\eScienceVM.deployment.paramaters.json .\$tempParameterFile

((Get-Content -path $tempParameterFile -Raw) -replace '"replaceUserUpn"', $('"' + $userUPN + '"')) | Set-Content -Path $tempParameterFile
((Get-Content -path $tempParameterFile -Raw) -replace '"replaceScriptURI"', $('"' + $scriptURILocation + '"')) | Set-Content -Path $tempParameterFile
((Get-Content -path $tempParameterFile -Raw) -replace '"replaceprovisioningPackage"', $('"' + $provisioningPackageLocation + '"')) | Set-Content -Path $tempParameterFile

# Deploy VM with Public IP
az deployment group create `
  --resource-group $orgname `
  --name (New-Guid).Guid `
  --template-file .\eScienceVM.deployment.json `
  --parameters $tempParameterFile 

az vm extension set `
  --publisher Microsoft.Azure.ActiveDirectory `
  --name AADLoginForWindows `
  --resource-group $orgname `
  --vm-name "escience"

# Deploy VM with isolated network
$tempParameterFile = '.\temp-Isolated.eScienceVM.deployment.paramaters.json'
Copy-Item .\isolated.eScienceVM.deployment.paramaters.json .\$tempParameterFile

((Get-Content -path $tempParameterFile -Raw) -replace '"replaceUserUpn"', $('"' + $userUPN + '"')) | Set-Content -Path $tempParameterFile
((Get-Content -path $tempParameterFile -Raw) -replace '"replaceScriptURI"', $('"' + $scriptURILocation + '"')) | Set-Content -Path $tempParameterFile
((Get-Content -path $tempParameterFile -Raw) -replace '"replaceprovisioningPackage"', $('"' + $provisioningPackageLocation + '"')) | Set-Content -Path $tempParameterFile

az deployment group create `
  --resource-group $orgname `
  --name (New-Guid).Guid `
  --template-file .\isolated.eScienceVM.deployment.json `
  --parameters $tempParameterFile 

az vm extension set `
  --publisher Microsoft.Azure.ActiveDirectory `
  --name AADLoginForWindows `
  --resource-group $orgname `
  --vm-name "escience1"