#APIM Dev Portal Quickstart
#--------------------------
#This script is useful for users who
#1. Already have APIM deployed
#2. Do not have a Self Hosted Dev Portal already
#--------------------------
#Caveat.
#This script is PowerShell.  It's not using AZ.  It's not idempotent.  It'll work onetime, and onetime only.

#User Variables (change these)
$apimName = "ContosoTravel"
$apimRg = "ContosoTravel"


#Script variables (don't need to change these)
$storageContainerName="devportal"

#lets check the RG out (we'll need the location for laters)
$rg = Get-AzResourceGroup $apimRg

#setting apim context
$apimContext = New-AzApiManagementContext -ResourceGroupName $apimRg -ServiceName $apimName

#Lets get the APIM management access key
$managementAccess = Get-AzApiManagementTenantAccess -Context $apimContext
if ($managementAccess.Enabled == false) {
    Set-AzApiManagementTenantAccess -Context $apimContext -Enabled $True
    $managementAccess = Get-AzApiManagementTenantAccess -Context $apimContext
}

#Create the storage account
$rand = Get-Random -Minimum -1000 -Maximum 9999
$storageAcc = New-AzStorageAccount -ResourceGroupName $apimRg -Name "$apimName$rand".ToLower() -SkuName Standard_LRS -Location $rg.Location
#$storageAcc = Get-AzStorageAccount -ResourceGroupName $apimRg -Name "ContosoTravel9452"
$storageContext = $storageAcc.Context

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $apimrg -Name $storageAcc.StorageAccountName)[0].Value
$storageConnectionString="DefaultEndpointsProtocol=https;AccountName=" + $storageAcc.StorageAccountName + ";AccountKey=" + $storageKey + ';EndpointSuffix=core.windows.net' 

Enable-AzStorageStaticWebsite -Context $storageContext -IndexDocument "index.html" -ErrorDocument404Path "404/index.html"

#Set the CORS rules on the storage account
$CorsRules = (@{
    AllowedHeaders=@("*");
    AllowedOrigins=@("*");
    MaxAgeInSeconds=0;
    AllowedMethods=@("DELETE", "GET", "HEAD", "MERGE", "POST", "OPTIONS", "PUT", "PATCH")})
Set-AzStorageCORSRule -Context $storageContext -ServiceType Blob -CorsRules $CorsRules

#Create a container for the portal to be published to
New-AzStorageContainer -Context $storageContext -Name $storageContainerName -Permission Off

$storageSAS = New-AzStorageAccountSASToken -Context $storageContext -Service Blob -ResourceType Container

#Portal Config file output
$configdesignjson = (Get-Content ("./src/config.design.json") | ConvertFrom-Json)
$configdesignjson.managementApiUrl = $configdesignjson.managementApiUrl.Replace("<service-name>",$apimName)
$configdesignjson.managementApiAccessToken = $configdesignjson.managementApiAccessToken.Replace("...",$managementAccess.PrimaryKey)
$configdesignjson.blobStorageContainer=$storageContainerName
$configdesignjson.blobStorageUrl=$storageAcc.PrimaryEndpoints.Blob + $storageSAS 
$configdesignjson.backendUrl = $configdesignjson.backendUrl.Replace("<service-name>",$apimName)
$configdesignjson | ConvertTo-Json | Out-File "./src/config.design.json"

#Config Publish Json
$configpublishjson = (Get-Content ("./src/config.publish.json") | ConvertFrom-Json)
$configpublishjson.managementApiUrl = $configpublishjson.managementApiUrl.Replace("<service-name>",$apimName)
$configpublishjson.managementApiAccessToken = $configpublishjson.managementApiAccessToken.Replace("...",$managementAccess.PrimaryKey)
$configpublishjson.blobStorageContainer=$storageContainerName
$configpublishjson.blobStorageConnectionString=$storageConnectionString
$configpublishjson | ConvertTo-Json | Out-File "./src/config.publish.json"

#Config runtime json
$configruntimejson = (Get-Content ("./src/config.runtime.json") | ConvertFrom-Json)
$configruntimejson.managementApiUrl = $configruntimejson.managementApiUrl.Replace("<service-name>",$apimName)
$configruntimejson.backendUrl = $configruntimejson.backendUrl.Replace("<service-name>",$apimName)
$configruntimejson.proxyHostnames = $configruntimejson.proxyHostnames.Replace("<service-name>",$apimName)
$configruntimejson | ConvertTo-Json | Out-File "./src/config.runtime.json"

#generate.bat
$generatebat = Get-Content ("./scripts/generate.bat")
For ($i=0; $i -lt $generatebat.Length; $i++) {
    if ($generatebat[$i].StartsWith("set management_endpoint")) { $generatebat[$i]='set management_endpoint="' + $apimname + '.management.azure-api.net"' }
    if ($generatebat[$i].StartsWith("set access_token")) { $generatebat[$i]='set access_token="' + $configpublishjson.managementApiAccessToken + '"' }
    if ($generatebat[$i].StartsWith("set storage_connection_string")) { $generatebat[$i]='set storage_connection_string="' + $storageConnectionString + '"' }
}
$generatebat | Out-File "./scripts/generate.bat"

Start-Process "./scripts/generate.bat"

#Run the portal
npm start

#The following command will translate them into static files 
#and place the output in the ./dist/website directory:
npm run publish

