param (
    [string]$SQLServerName, 
    [string]$SQLpassword
)

# Install Microsoft .Net Core 2.1.0
$exeDotNetTemp = [System.IO.Path]::GetTempPath().ToString() + "dotnet-sdk-2.1.300-win-x64.exe"
if (Test-Path $exeDotNetTemp) { Remove-Item $exeDotNetTemp -Force }
# Download file from Microsoft Downloads and save to local temp file (%LocalAppData%/Temp/2)
$exeFileNetCore = [System.IO.Path]::GetTempFileName() | Rename-Item -NewName "dotnet-sdk-2.1.300-win-x64.exe" -PassThru
Invoke-WebRequest -Uri "https://download.microsoft.com/download/8/8/5/88544F33-836A-49A5-8B67-451C24709A8F/dotnet-sdk-2.1.300-win-x64.exe" -OutFile $exeFileNetCore
# Run the exe with arguments
$proc = (Start-Process -FilePath $exeFileNetCore.Name.ToString() -ArgumentList ('/install','/quiet') -WorkingDirectory $exeFileNetCore.Directory.ToString() -Passthru)
$proc | Wait-Process

# Disable Internet Explorer Enhanced Security Configuration
$AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
$UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -Force
Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0 -Force
Stop-Process -Name Explorer -Force

# Download eShopOnWeb to c:\eShopOnWeb and extract contents
$zipFileeShopTemp = [System.IO.Path]::GetTempPath().ToString() + "eShopOnWeb-master.zip"
if (Test-Path $zipFileeShopTemp) { Remove-Item $zipFileeShopTemp -Force }
$zipFileeShop = [System.IO.Path]::GetTempFileName() | Rename-Item -NewName "eShopOnWeb-master.zip" -PassThru
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri "https://github.com/dotnet-architecture/eShopOnWeb/archive/master.zip" -OutFile $zipFileeShop
$BackUpPath = $zipFileeShop.FullName
New-Item -Path c:\eshoponweb -ItemType directory -Force
$Destination = "C:\eshoponweb"
Add-Type -assembly "system.io.compression.filesystem" -PassThru
[io.compression.zipfile]::ExtractToDirectory($BackUpPath, $destination)

#Update eShopOnWeb project to use SQL Server
#modify Startup.cs
$Startupfile = 'C:\eshoponweb\eShopOnWeb-master\src\Web\Startup.cs'
$find = '            ConfigureInMemoryDatabases(services);'
$replace = '            //ConfigureInMemoryDatabases(services);'
(Get-Content $Startupfile).replace($find, $replace) | Set-Content $Startupfile -Force
$find1 = '            // ConfigureProductionServices(services);'
$replace1 = '            ConfigureProductionServices(services);'
(Get-Content $Startupfile).replace($find1, $replace1) | Set-Content $Startupfile -Force

#modify appsettings.json
$SQLusername = "sqladmin"
$appsettingsfile = 'C:\eshoponweb\eShopOnWeb-master\src\Web\appsettings.json'
$find = '    "CatalogConnection": "Server=(localdb)\\mssqllocaldb;Integrated Security=true;Initial Catalog=Microsoft.eShopOnWeb.CatalogDb;",'
$replace = '    "CatalogConnection": "Server=' + $SQLServername + ';Integrated Security=false;User ID=' + $SQLusername + ';Password=' + $SQLpassword + ';Initial Catalog=Microsoft.eShopOnWeb.CatalogDb;",'
(Get-Content $appsettingsfile).replace($find, $replace) | Set-Content $appsettingsfile -Force
$find1 = '    "IdentityConnection": "Server=(localdb)\\mssqllocaldb;Integrated Security=true;Initial Catalog=Microsoft.eShopOnWeb.Identity;"'
$replace1 = '    "IdentityConnection": "Server=' + $SQLServername + ';Integrated Security=false;User ID=' + $SQLusername + ';Password=' + $SQLpassword + ';Initial Catalog=Microsoft.eShopOnWeb.Identity;"'
(Get-Content $appsettingsfile).replace($find1, $replace1) | Set-Content $appsettingsfile -Force

#add exception to ManageController.cs
$ManageControllerfile = 'C:\eshoponweb\eShopOnWeb-master\src\Web\Controllers\ManageController.cs'
$Match = [regex]::Escape("public async Task<IActionResult> ChangePassword()")
$NewLine = 'throw new ApplicationException($"Oh no!  Error!  Error! Yell at Rob!  He put this here!");'
$Content = Get-Content $ManageControllerfile -Force
$Index = ($content | Select-String -Pattern $Match).LineNumber + 2
$NewContent = @()
0..($Content.Count-1) | Foreach-Object {
    if ($_ -eq $index) {
        $NewContent += $NewLine
    }
    $NewContent += $Content[$_]
}
$NewContent | Out-File $ManageControllerfile -Force

#Configure eShoponWeb application
# Run dotnet with arguments
$eShopWebDestination = "C:\eshoponweb\eShopOnWeb-master\src\Web"
$proc = (Start-Process -FilePath 'dotnet' -ArgumentList ('restore') -WorkingDirectory $eShopWebDestination -Passthru)
$proc | Wait-Process

#Configure CatalogDb
$proc = (Start-Process -FilePath 'dotnet' -ArgumentList ('ef','database','update','-c','catalogcontext','-p','../Infrastructure/Infrastructure.csproj','-s','Web.csproj') -WorkingDirectory $eShopWebDestination -Passthru)
$proc | Wait-Process

#Configure Identity Db
$proc = (Start-Process -FilePath 'dotnet' -ArgumentList ('ef','database','update','-c','appidentitydbcontext','-p','../Infrastructure/Infrastructure.csproj','-s','Web.csproj') -WorkingDirectory $eShopWebDestination -Passthru)
$proc | Wait-Process

# Build Project and publish to a folder
# Share folder to vmadmin and SYSTEM
New-Item -ItemType directory -Path C:\eShopPub
New-SmbShare -Name "eShopPub" -Path "C:\eShopPub" -FullAccess $env:computername"\vmadmin"
Grant-SmbShareAccess -Name "eShopPub" -AccountName SYSTEM -AccessRight Full -Force

#Download nuget.exe
$exeFilenugetTemp = [System.IO.Path]::GetTempPath().ToString() + "nuget.exe"
if (Test-Path $exeFilenugetTemp) { Remove-Item $exeFilenugetTemp -Force }
$exeFilenuget = [System.IO.Path]::GetTempFileName() | Rename-Item -NewName "nuget.exe" -PassThru
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $exeFilenuget

#Update eShoponWeb Solution with latest dependences
$eShopPath = "C:\eshoponweb\eShopOnWeb-master"
$proc = (Start-Process -FilePath $exeFilenuget.ToString() -ArgumentList ('restore','C:\eshoponweb\eShopOnWeb-master\eShopOnWeb.sln') -WorkingDirectory $eShopPath -Passthru)
$proc | Wait-Process

# Run MSbuild to publish files to folder
$eShopWebPath = "C:\eshoponweb\eShopOnWeb-master\src\Web"
$proc = (Start-Process -FilePath "C:\Program Files (x86)\Microsoft Visual Studio\Preview\Community\MSBuild\15.0\Bin\MSBuild.exe" -ArgumentList ('/p:WebPublishMethod=FileSystem','/p:PublishProvider=FileSystem','/p:LastUsedBuildConfiguration=Release','/p:LaunchSiteAfterPublish=False','/p:ExcludeApp_Data=False','/p:TargetFramework=netcoreapp2.1','/p:SelfContained=false','/p:_IsPortable=true','/p:publishUrl=C:\eShopPub','/p:DeleteExistingFiles=False','/p:DeployOnBuild=True') -WorkingDirectory $eShopWebPath -Passthru)
$proc | Wait-Process
