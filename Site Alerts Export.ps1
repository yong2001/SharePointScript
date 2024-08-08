cls
$error.Clear()

##################################################################################################
# Load SharePoint Snapin
##################################################################################################
$snap = Get-PSSnapin | Where-Object {$_.Name -eq 'Microsoft.SharePoint.Powershell'} 
if ($snap -eq $null) { 
  Write-Host "Loading Powershell Snapin..." -ForegroundColor Yellow
	Add-PSSnapin Microsoft.SharePoint.Powershell 
}

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint") | Out-Null


##################################################################################################
# Global Variables
##################################################################################################
$Today = [string]::Format( "{0:yyyy-MM-dd}", [datetime]::Now.Date )


$SiteCollectionUrl = "Enter Site URL Here" #Change Here
$RootWeb = get-spweb $SiteCollectionUrl

$TranscriptFileName = "$Today - Excel Export User Alerts Log.txt"
$CSVFileName= "$Today - Excel Export User Alerts.csv"


$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference = "Continue"
Write-Host "Starting Transcript..." -ForegroundColor Yellow
Start-Transcript -path $TranscriptFileName

Write-Host "##########################################################################################" -ForegroundColor Yellow
Write-Host "# $Today - Running User Alerts Export Script" -ForegroundColor Yellow
Write-Host "##########################################################################################" -ForegroundColor Yellow
Write-Host ""

$AllAlerts= @()

##################################################################################################
# Loop through sites
##################################################################################################
foreach ($web in $RootWeb.Webs) 
{
	
	Write-Host ("Exporting Alerts for site: "+$web.Title)
	$webalerts = 0
	
	foreach($alert in $web.Alerts)
	{
	$alertobj = New-Object System.Object
	$alertobj | Add-Member -type NoteProperty -name ParentSite -value $web.Title
	$alertobj | Add-Member -type NoteProperty -name ParentUrl -value $web.Url
	$alertobj | Add-Member -type NoteProperty -name Title -value $alert.title	
	$alertobj | Add-Member -type NoteProperty -name List -value $alert.List
	$alertobj | Add-Member -type NoteProperty -name ListUrl -value $alert.ListUrl
	$alertobj | Add-Member -type NoteProperty -name ListID -value $alert.ListID
	$alertobj | Add-Member -type NoteProperty -name User -value $alert.user
	$alertobj | Add-Member -type NoteProperty -name UserID -value $alert.userID
	$alertobj | Add-Member -type NoteProperty -name AlertFrequency -value $alert.AlertFrequency
	$alertobj | Add-Member -type NoteProperty -name AlertTime -value $alert.AlertTime
	$alertobj | Add-Member -type NoteProperty -name AlertType -value $alert.AlertType
	$alertobj | Add-Member -type NoteProperty -name AlwaysNotify -value $alert.AlwaysNotify
	$alertobj | Add-Member -type NoteProperty -name AlertTemplate -value $alert.AlertTemplate
	$alertobj | Add-Member -type NoteProperty -name AlertTemplateName -value $alert.AlertTemplateName
	$alertobj | Add-Member -type NoteProperty -name DeliveryChannels  -value $alert.DeliveryChannels 
	$alertobj | Add-Member -type NoteProperty -name EventType  -value $alert.EventType 
	$alertobj | Add-Member -type NoteProperty -name EventTypeBitmask  -value $alert.EventTypeBitmask
	$alertobj | Add-Member -type NoteProperty -name 'Filter'  -value $alert.Filter
	$alertobj | Add-Member -type NoteProperty -name ID  -value $alert.ID
	$alertobj | Add-Member -type NoteProperty -name Item  -value $alert.Item
	$alertobj | Add-Member -type NoteProperty -name ItemID  -value $alert.ItemID
	$alertobj | Add-Member -type NoteProperty -name Status  -value $alert.Status
	$alertobj | Add-Member -type NoteProperty -name p_query -value $alert.Properties["p_query"]
	$alertobj | Add-Member -type NoteProperty -name eventtypeindex -value $alert.Properties["eventtypeindex"]
	$alertobj | Add-Member -type NoteProperty -name filterindex -value $alert.Properties["filterindex"]
	$alertobj | Add-Member -type NoteProperty -name p_lastnotificationtime -value $alert.Properties["p_lastnotificationtime"]
	$alertobj | Add-Member -type NoteProperty -name sendurlinsms -value $alert.Properties["sendurlinsms"]
	$alertobj | Add-Member -type NoteProperty -name siteurl -value $alert.Properties["siteurl"]

	$AllAlerts += , $alertobj
	$webalerts ++
	}
	
	Write-Host ($webalerts.ToString() +" Alert(s) Found`n`n"	)
}

##################################################################################################
# Export to csv
##################################################################################################
$AllAlerts | Export-Csv -NoTypeInformation  $CSVFileName -Encoding Default
$num = ($AllAlerts).count

#end
Write-Host "Exported $num alerts." -ForegroundColor Yellow
Write-Host "Script Complete.`n`n" -ForegroundColor Yellow
Stop-Transcript
