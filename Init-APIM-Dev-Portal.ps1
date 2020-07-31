#APIM Dev Portal Quickstart
#--------------------------
#This script is useful for users who
#1. Already have APIM deployed
#2. Do not have a Self Hosted Dev Portal already
#--------------------------
#Caveat.
#This script is PowerShell.  It's not using AZ, and as such it's not idempotent

#User Variables (change these)
$apimName = "ContosoTravel"
$apimRg = "ContosoTravel"

#Script variables (you don't need to change these)
$storageAccountName="contosotravel9452" #only change this if you've got a storage account created already, the script will otherwise generate you one
$storageContainerName="devportal"

#lets clone the repo and jump in
git clone https://github.com/Azure/api-management-developer-portal.git
cd api-management-developer-portal
git checkout 10.11.12
npm install

#lets check the RG out (we'll need the location for laters)
$rg = Get-AzResourceGroup $apimRg

#setting apim context
$apimContext = New-AzApiManagementContext -ResourceGroupName $apimRg -ServiceName $apimName

#Lets get the APIM management access key
$managementAccess = Get-AzApiManagementTenantAccess -Context $apimContext
if ($managementAccess.Enabled -eq $false) {
    Set-AzApiManagementTenantAccess -Context $apimContext -Enabled $True
    $managementAccess = Get-AzApiManagementTenantAccess -Context $apimContext
}

#Now managment Access is enabled, we need a SAS token
$sasgenUrl="https://helperfunc.azurewebsites.net/api/CreateApimSAS?code=E2X7dNg1r8eaJnNciqIctaHToHdm5dxq2agPllRaIVWENX4ojM2sDw=="
$sasgenBody = @{}
$sasgenBody.Add("id",$managementAccess.Id)
$sasgenBody.Add("key",$managementAccess.PrimaryKey)
$sasResponse = Invoke-WebRequest -Method Post -Uri $sasgenUrl -Body $($sasgenBody | ConvertTo-Json)
$apimSAS = "SharedAccessSignature " + $sasResponse.Content

#No idea why this didn't work, the signature never came out right.  resorted to the exact same code, in c# in an azure function
#$dateIn30=(Get-Date).AddDays(30).ToShortDateString()
#$expiry=([datetime]::ParseExact($dateIn30,"dd/MM/yyyy",[cultureinfo]::InvariantCulture))
#$expiryString = $expiry.ToString( "yyyy-MM-ddTHH:mm:ss.fffffff" ) #$expiry.ToUniversalTime().ToString( "yyyy-MM-ddTHH:mm:ss.fffffffZ" )

#$dataToSign = $managementAccess.Id + "\n" + $expiryString

#$hmacsha = New-Object System.Security.Cryptography.HMACSHA512
#$hmacsha.key = [Text.Encoding]::UTF8.GetBytes($managementAccess.PrimaryKey)
#$bytesToHash = [Text.Encoding]::UTF8.GetBytes($dataToSign)
#$signature = $hmacsha.ComputeHash($bytesToHash)
#$signature = [Convert]::ToBase64String($signature)

#$apimSAS = "SharedAccessSignature uid=" + $managementAccess.Id + "&ex=" + $expiryString + "&sn=" + $signature

#Test API call, with the APIM SAS token.
$baseUrl= "https://$ApimName.management.azure-api.net"
$apiVersion="2014-02-14-preview"
$testURL = $baseUrl +  "/groups?api-version=" + $apiVersion
$headers = @{
    Authorization="$apimSAS"
}
$req=$null
$req = Invoke-WebRequest -Method Get -Uri $testURL -Headers $headers -UseBasicParsing
Write-Host "Test API call using the APIM SAS: " + $req.StatusCode + $req.StatusDescription

#Create the storage account
if ($storageAccountName -eq "") {
    $rand = Get-Random -Minimum -1000 -Maximum 9999
    $storageAcc = New-AzStorageAccount -ResourceGroupName $apimRg -Name "$apimName$rand".ToLower() -SkuName Standard_LRS -Location $rg.Location
}
else {
    $storageAcc = Get-AzStorageAccount -ResourceGroupName $apimRg -Name "$storageAccountName"
}

$storageContext = $storageAcc.Context

$storageKey = (Get-AzStorageAccountKey -ResourceGroupName $apimrg -Name $storageAcc.StorageAccountName)[0].Value
$storageConnectionString="DefaultEndpointsProtocol=https;AccountName=" + $storageAcc.StorageAccountName + ";AccountKey=" + $storageKey + ';EndpointSuffix=core.windows.net' 

#Enable Static Website capability
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

#Create a new storage SAS
$dateIn30=(Get-Date).AddDays(30).ToShortDateString()
$expiry=([datetime]::ParseExact($dateIn30,"dd/MM/yyyy",[cultureinfo]::InvariantCulture))
$storageSAS = New-AzStorageAccountSASToken -Context $storageContext -Service Blob -ResourceType Container,Object -ExpiryTime $expiry -Permission "racwdlup"

#Test storageSAS actually can upload something (just a ranom image is being used)
$tempfile=[System.IO.Path]::GetTempPath() + "test-image.png"
Invoke-WebRequest -uri "https://gordon.byers.me/assets/img/die-bart-die.png" -OutFile $tempfile
$testfile = Get-Content $tempfile -Raw
$storageAcc.PrimaryEndpoints.Blob + $storageSAS
$uri = $storageAcc.PrimaryEndpoints.Blob + $storageContainerName + "/test-image.png" + $storageSAS
$headers = @{}
$headers.Add("x-ms-blob-type","BlockBlob")
$storageTestResult = Invoke-WebRequest -uri $uri -Method Put -Body $file -ContentType "image/png"  -Headers $headers
Write-Host "Test image upload using Storage SAS: " + $storageTestResult.StatusCode + " " + $storageTestResult.StatusDescription

#Flipping text output stuff on windows.  For PowerShell 5.1 you need to do this, rather than use out-file
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
$basepath= Get-Location
#[System.IO.File]::WriteAllLines($MyPathOut, $MyFile, $Utf8NoBomEncoding)

#Portal Config file output
$configdesignjson = (Get-Content ("./src/config.design.json") | ConvertFrom-Json)
$configdesignjson.managementApiUrl = $configdesignjson.managementApiUrl.Replace("<service-name>",$apimName)
$configdesignjson.managementApiAccessToken = $apimSAS 
$configdesignjson.blobStorageContainer=$storageContainerName
$configdesignjson.blobStorageUrl=$storageAcc.PrimaryEndpoints.Blob + $storageSAS 
$configdesignjson.backendUrl = $configdesignjson.backendUrl.Replace("<service-name>",$apimName)
$configdesignjsonout = $configdesignjson | ConvertTo-Json | % { [System.Text.RegularExpressions.Regex]::Unescape($_) } 
[System.IO.File]::WriteAllLines("$basepath\src\config.design.json", $configdesignjsonout, $Utf8NoBomEncoding)


#Config Publish Json
$configpublishjson = (Get-Content ("./src/config.publish.json") | ConvertFrom-Json)
$configpublishjson.managementApiUrl = $configpublishjson.managementApiUrl.Replace("<service-name>",$apimName)
$configpublishjson.managementApiAccessToken = $apimSAS 
$configpublishjson.blobStorageContainer=$storageContainerName
$configpublishjson.blobStorageConnectionString=$storageConnectionString
$configpublishjson | ConvertTo-Json | % { [System.Text.RegularExpressions.Regex]::Unescape($_) } 
$configpublishjsonout = $configdesignjson | ConvertTo-Json | % { [System.Text.RegularExpressions.Regex]::Unescape($_) } 
[System.IO.File]::WriteAllLines("$basepath\src\config.publish.json", $configpublishjsonout, $Utf8NoBomEncoding)


#Config runtime json
$configruntimejson = (Get-Content ("./src/config.runtime.json") | ConvertFrom-Json)
$configruntimejson.managementApiUrl = $configruntimejson.managementApiUrl.Replace("<service-name>",$apimName)
$configruntimejson.backendUrl = $configruntimejson.backendUrl.Replace("<service-name>",$apimName)
$configruntimejson | ConvertTo-Json | % { [System.Text.RegularExpressions.Regex]::Unescape($_) } 
$configruntimejsonout = $configdesignjson | ConvertTo-Json | % { [System.Text.RegularExpressions.Regex]::Unescape($_) } 
[System.IO.File]::WriteAllLines("$basepath\src\config.runtime.json", $configruntimejsonout, $Utf8NoBomEncoding)

#generate.bat
$generatebat = Get-Content ("./scripts/generate.bat")
For ($i=0; $i -lt $generatebat.Length; $i++) {
    if ($generatebat[$i].StartsWith("set management_endpoint")) { $generatebat[$i]='set management_endpoint="' + $apimname + '.management.azure-api.net"' }
    if ($generatebat[$i].StartsWith("set access_token")) { $generatebat[$i]='set access_token="' + $configpublishjson.managementApiAccessToken + '"' }
    if ($generatebat[$i].StartsWith("set storage_connection_string")) { $generatebat[$i]='set storage_connection_string="' + $storageConnectionString + '"' }
    
}
$generatebat | Out-File "./scripts/generate.bat" -Encoding "UTF8"

#start the generation
Start-Process "./scripts/generate.bat" -Wait

#Run the portal
#npm start

#The following command will translate them into static files 
#and place the output in the ./dist/website directory:
npm run publish


#using azcopy to publish
$azcopyargs = @("copy", 
                "$(get-location)dist\website\", 
                $($storageAcc.PrimaryEndpoints.Blob + "`$web" + $storageSAS), 
                "--from-to=LocalBlob",
                "--blob-type Detect ",
                "--follow-symlinks"
                "--put-md5 ",
                "--follow-symlinks ",
                "–recursive ")
$azcopypath = "C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy\azcopy"
#start-process -FilePath  -ArgumentList $azcopyargs -Wait
Write-host $azcopypath $($azcopyargs -join " ")