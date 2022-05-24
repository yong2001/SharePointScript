$SiteURL = "<site url goes here>"
$ListName= "Site Pages"
$Date = "2019-12-20"
$NewsID = 10
Connect-PnPOnline -Url $SiteURL -Interactive
 
if (-not (Get-PnPContext)) {
    Write-Host "Error connecting to SharePoint Online, unable to establish context" -foregroundcolor black -backgroundcolor Red
    return
}
else{
    Set-PnPListItem -List $ListName -Identity $NewsID -Values @{"FirstPublishedDate"=$Date;}  -UpdateType SystemUpdate
}
