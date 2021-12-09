#dir "d:\images\*.vhd*" | sort lastwritetime | select -last 10 | sort Basename | ft Basename

$remoteServers = "FARM1-SERVER02","FARM1-SERVER03","FARM2-SERVER01","FARM2-SERVER02","FARM2-SERVER02";
$remoteFarmServer = "FARM2-SERVER01";
$localSharePath = "d:\images";
$remoteSharePath = "d$\images";
[int] $remoteCount = $remoteServers.count;
[int] $remoteImageCount = 0;
[int] $optionCount = 1;
$imageOptions = @{};

Add-PSSnapin citrix*;

dir "$localSharePath\*.vhd*" | % {
    $remoteImageCount = 0;
    $imageName = $_.Name;

    foreach ($remoteServer in $remoteServers)
    {
        if(Test-Path "\\$remoteServer\$remoteSharePath\$imageName")
        {
            $remoteImageCount++;
        }    
    }
    if ($remoteImageCount -ne $remoteCount)
    {
        $imageLocatorName = $imageName -replace "\.vhdx?", "";
        #Filter disks that are type 9, "Read Only Cache in Device RAM with Overflow on Hard Disk"
        Set-PvsConnection -Server "localhost";
        $site = (Get-PvsSite).name;
        try
        {
            $writeCacheType = (Get-PvsDisk -Name $imageLocatorName -SiteName $site -StoreName "Local" -ErrorAction SilentlyContinue).WriteCacheType
        }
        catch
        {
            #do nothing
        }
        finally
        {
            if ($writeCacheType -eq 9)
            {
                $imageOptions.Add($optionCount++,$imageName);
            }
        }
    }
}

$imageOptions.GetEnumerator() | sort Name | ft Name,Value -a
$imageKey = Read-Host -Prompt "Select the image number to copy";
$selectedImage = $imageOptions[[int]$imagekey];


if ($selectedImage -ne $null)
{
    Write-Host "You selected $selectedImage";
    $pvpName = $selectedImage -replace "\.vhdx?", ".pvp"
    $imageLocatorName = $selectedImage -replace "\.vhdx?", "";

    $jobArray = @();

    foreach ($remoteServer in $remoteServers)
    {
        $job = Start-Job -ScriptBlock {
            param($selectedImage, $pvpName, $remoteServer)
            Copy-Item -Path "$localSharePath\$pvpName" -Destination "\\$remoteServer\$remoteSharePath\" -Force;
            Copy-Item -Path "$localSharePath\$selectedImage" -Destination "\\$remoteServer\$remoteSharePath\" -Force
        } -ArgumentList $selectedImage, $pvpName, $remoteServer;
        
        $jobArray += $job;
    }
    Wait-Job -Job $jobArray;

    #import image into LAF
    Set-PvsConnection -Server $remoteFarmServer;
    $site = (Get-PvsSite).name;
    if ($selectedImage -match "\.vhdx$")
    {
        #Import a VHDX
        New-PvsDiskLocator -DiskLocatorName $imageLocatorName -SiteName $site -StoreName "Local" -VHDX;
    }
    else
    {
        #Import a VHD
        New-PvsDiskLocator -DiskLocatorName $imageLocatorName -SiteName $site -StoreName "Local";
    }
}
else
{
    Write-Host "You chose poorly.";
}