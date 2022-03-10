################################################################################
#	File: GetSiteclectionPermisson.ps1
#	Title: サイトコレクション権限出力 PowerShell スクリプト
#	Description: サイトコレクション権限出力　PowerShell スクリプト
#	Created: Ma / Microsoft Solution Consulting Center
#	Copyright: Copyright (C) 2020 Sonorite Co.,LTD. All rights reserved.
#	Update History:
#  0.01 2022.03.03 作成開始
#  0.02 2022.03.0  引数変更
#  .\Get_SiteCollectionPermisson.ps1 -url "http://sonorite-sps19/sites/test101"  -ReportFile "F:\work\PermisosErreius-test101.htm"
#  
###############################################################################


    Param
    (
        # 権限出力対象サイトコレクションURL
        [Parameter(Mandatory=$true, 
                   ParameterSetName='Permissionreport')]
        [string]$url,

        #出力レポートのファイル名
        [Parameter(Mandatory=$true,
                    ParameterSetName='Permissionreport')]
        [string]$ReportFile
    )

if([string]::IsNullorEmpty($url))
{
 Write-Host "対象URLは設定されておりません" 
 exit
 }
if([string]::IsNullorEmpty($ReportFile))
{
 Write-Host "出力ファイルは設定されておりません" 
 exit
 }



Add-PSSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue
 
$HTMLTemplate=@"
<html>
<head>
<!-- Sal - Javascript Function to apply formatting -->
<script type="text/javascript">
function altRows(id){
 if(document.getElementsByTagName){    
  var table = document.getElementById(id); 
  var rows = table.getElementsByTagName("tr");    
  for(i = 0; i < rows.length; i++){         
   if(i % 2 == 0){
    rows[i].className = "evenrowcolor";
   }else{
    rows[i].className = "oddrowcolor";
   }     
  }
 }
}
window.onload=function(){
 altRows('alternatecolor');
}
</script>
  
<!-- CSS Styles for Table TH, TR and TD -->
<style type="text/css">
body{ font-family: Calibri; height: 12pt; }
 
table.altrowstable {
 border-collapse: collapse; font-family: verdana,arial,sans-serif;
 font-size:11px; color:#333333; border-width: 1px; border-color: #a9c6c9;
 border: b1a0c7 0.5pt solid; /*Sal Table format */ 
}
table.altrowstable th {
 border-width: 1px; padding: 5px; background-color:#8064a2;
 border: #b1a0c7 0.5pt solid; font-family: Calibri; height: 15pt;
 color: white;  font-size: 11pt;  font-weight: 700;  text-decoration: none;
}
table.altrowstable td {
 border: #b1a0c7 0.5pt solid; font-family: Calibri; height: 15pt; color: black;
 font-size: 11pt; font-weight: 400; text-decoration: none;
}
.oddrowcolor{ background-color: #e4dfec; }
.evenrowcolor{ background-color:#FFFFFF; }
</style>
</head>
<body>
"@
 
#Function to get permissions of an object Sal. Such as: Web, List, Folder, ListItem
Function Get-Permissions([Microsoft.SharePoint.SPRoleAssignmentCollection]$RoleAssignmentsCollection, $OutputReport)
{
   foreach($RoleAssignment in $RoleAssignmentsCollection)
    {
        #Get the Permissions assigned to Group/User
        $UserPermissions=@()
        foreach ($RoleDefinition in $RoleAssignment.RoleDefinitionBindings)
        {
            #Exclude "Limited Access" - We don't need it sal.
            if($RoleDefinition.Name -ne "Limited Access")
            {
                $UserPermissions += $RoleDefinition.Name +";"
            }   
        }
         
        if($UserPermissions)
        {
            #*** Get  User/Group Name *****#
            $UserGroupName=$RoleAssignment.Member.Name
            $UserName=$RoleAssignment.Member.LoginName 
            #**** Get User/Group Type ***** Is it a User or Group (SharePoint/AD)?
            #Is it a AD Domain Group?
            If($RoleAssignment.Member.IsDomainGroup)
                {
                   $Type="Domain Group"
                }
            #Is it a SharePoint Group?           
            Elseif($RoleAssignment.Member.GetType() -eq [Microsoft.SharePoint.SPGroup])
            {
                 $Type="SharePoint Group"
            }
            #it a SharePoint User Account
            else
            {
                   $Type="User"
            }
            #Send the Data to Report
            " <tr> <td> $($UserGroupName) </td><td> $($Type) </td><td> $($UserName) </td><td>  $($UserPermissions)</td></tr>" >> $OutputReport
        }
    }
}
 
Function Generate-PermissionRpt()
{
    Param([Parameter(Mandatory=$true)] [string]$SiteCollectionURL,
          [Parameter(Mandatory=$true)] [string]$OutputReport,
          [Parameter(Mandatory=$true)] [bool]$ScanFolders,
          [Parameter(Mandatory=$true)] [bool]$ScanItemLevel)
 
    #Try to Get the site collection 
    try
    {
        $Site = Get-SPSite $SiteCollectionURL -ErrorAction SilentlyContinue
    }
    catch
    {
        write-host Site Collection with URL:$SiteCollectionURL Does not Exists!
        return
    }  
     
    #Append the HTML File with CSS into the Output report
    $Content = $HTMLTemplate > $OutputReport
    
    "<h2> Site Collection Permission Report: $($Site.RootWeb.Title) </h2>" >> $OutputReport
    
    #Table of Contents
    "<h3> List of Sites</h3> <table class='altrowstable' id='alternatecolor' cellpadding='5px'><tr><th>Site Name </th><th> URL </th><th> Permission Setup </th></tr>" >> $OutputReport
    #Get Users of All Webs : Loop throuh all Sub Sites
    foreach($Web in $Site.AllWebs)
    {
         
        if($Web.HasUniqueRoleAssignments -eq $true)
        {
            $PermissionSetup ="Unique Permissions"
        }
        else
        {
            $PermissionSetup="Inheriting from Parent"
        }
         
        "<tr> <td> <a href='#$($web.Title.ToLower())'>$($web.Title)</a> </td><td> $($web.URL)</td> <td> $($PermissionSetup)</td></tr>" >> $OutputReport
    }
    
    #Site Collection Administrators Heading
    "</table><br/><b>Site Collection Administrators</b>" >> $OutputReport
     "<table class='altrowstable' id='alternatecolor' cellpadding='5px'><tr>" >> $OutputReport
  
    #Write Table Header
    "<th>User Account ID </th> <th>User Name </th></tr>" >> $OutputReport
    
    #Get All Site Collection Administrators
    $Site.RootWeb.SiteAdministrators | sort $_.Name | ForEach-Object { 
    "<tr><td> $($_.LoginName) </td> <td> $($_.Name)</td></tr> " >> $OutputReport
    }
 
    $Counter=0;
    #Get Users of All Webs : Loop throuh all Sub Sites
    foreach($Web in $Site.AllWebs)
    {
        Write-Progress -Activity "Collecting permissions data. Please wait..." -status "Processing Web: $($Web.URL)" -percentComplete ($Counter/$Site.AllWebs.count*100)
     
        #Check if site is using Unique Permissions or Inheriting from its Parent Site!
        if($Web.HasUniqueRoleAssignments -eq $true)
        {
            "</table><br/><hr> <h3>Site: <a name='$($Web.Title.ToLower())' href='$($web.URL)' target='_blank'>$($Web.Title)</a> is using Unique Permissions. </h3>" >> $OutputReport
        }
        else
        {
            "</table><br/><hr> <h3>Site: <a name='$($Web.Title.ToLower())' href='$($web.URL)' target='_blank'>$($Web.Title)</a> is Inheriting Permissions from its Parent Site.</h3>" >> $OutputReport
        }
    
        #Get the Users & Groups from site which has unique permissions - TOP sites always with Unique Permissions
        if($Web.HasUniqueRoleAssignments -eq $True)
        {       
            Write-host Processing Web $Web.URL
            #*** Get all the users granted permissions DIRECTLY to the site ***
            "<b>Site Permissions</b><table class='altrowstable' id='alternatecolor' cellpadding='5px'><tr>" >> $OutputReport
            "<th>Users/Groups </th> <th> Type </th><th> User Name </th> <th>Permissions</th></tr>" >> $OutputReport
 
            #Call the function to get Permissions Applied
            Get-Permissions $Web.RoleAssignments $OutputReport
         
               
            #****** Get Members of Each Group at Web Level *********#
            "</table></br> " >>$OutputReport
             
            #Check if any SharePoint Groups Exists, if yes, Get members of it
            $WebGroupRoleAssignments = $Web.RoleAssignments | Where { $_.Member.GetType() -eq [Microsoft.SharePoint.SPGroup]}
            if($WebGroupRoleAssignments)
            {
                "<b>Group Users</b><table class='altrowstable' id='alternatecolor' cellpadding='5px'><tr>" >>$OutputReport
                foreach($WebRoleAssignment in $WebGroupRoleAssignments)
                {
                    "<th colspan='3'><b>Group:</b> $($WebRoleAssignment.Member.Name)</th></tr> " >> $OutputReport
                    foreach($user in $WebRoleAssignment.member.users)
                    {
                        #Send the Data to Log file
                        " <tr> <td> $($user.Name) </td><td> $($user.LoginName) </td><td> $($user.Email)</td><tr>" >> $OutputReport
                    }
                }
            }
        } #Web.HasUniqueRoleAssignments Over     
       
     #********  Check All List's Permissions ********/
        foreach($List in $Web.lists)
        {
            #Skip the Hidden Lists
            if( ($List.HasUniqueRoleAssignments -eq $True) -and  ($List.Hidden -eq $false))
            {
                "</table><br/><b>List: [ $($List.Title) ] at <a href='$($List.ParentWeb.Url)/$($List.RootFolder.Url)'>$($List.ParentWeb.Url)/$($List.RootFolder.Url)</a> is using Unique Permissions.</b><table class='altrowstable' id='alternatecolor' cellpadding='5px'><tr>" >> $OutputReport
                "<th>Users/Groups </th><th> Type </th><th> User Name </th><th> Permissions</th></tr>" >> $OutputReport
                    
                #Call the function to get Permissions Applied
                Get-Permissions $List.RoleAssignments $OutputReport
            }
            "</table>" >>$OutputReport
             
            #********  Check Folders with Unique Permissions ********/
            if($ScanFolders -eq $True)
            {
                $UniqueFolders = $List.Folders | where { $_.HasUniqueRoleAssignments -eq $True }    
                #Check if any folder has Unique Permission
                if($UniqueFolders)
                {
                    #Get Folder permissions
                    foreach($folder in $UniqueFolders)
                    {
                        #Write Table Headers
                        #$FolderURL=$folder.ParentList.ParentWeb.URL/$folder.Url
                        $FolderURL=$folder.ParentList.ParentWeb.URL + "/" +$folder.Url
                        "<br/><b>Folder: <a href='$($FolderURL)' target='_blank'>$($Folder.Title)</a> is using Unique Permissions.</b><table class='altrowstable' id='alternatecolor' cellpadding='5px'><tr>" >> $OutputReport
                        "<th>Users/Groups </th><th> Type </th><th> User Name </th><th> Permissions</th></tr>" >> $OutputReport
 
                        #Call the function to get Permissions Applied
                        Get-Permissions $folder.RoleAssignments $OutputReport
                         
                        "</table>" >>$OutputReport
                    }
                }
            }
             
            #********  Check Items with Unique Permissions ********/
            if($ScanItemLevel -eq $True)
            {
                $UniqueItems = $List.Items  | where { $_.HasUniqueRoleAssignments -eq $True }    
                #Check if any Item has Unique Permission Sal
                if($UniqueItems)
                {
                    #Get Folder permissions
                    foreach($Item in $UniqueItems)
                    {
                        #Get Item's Name if Title is NULL
                        if($Item.Title -ne $null) {$ItemTitle = $Item.Title } else {$ItemTitle= $Item["Name"] }
                        #Write Table Headers
                        $ItemURL= $item.ParentList.ParentWeb.Site.MakeFullUrl($item.ParentList.DefaultDisplayFormUrl)
                        "<br/><b>Item: <a target='_blank' href='$($ItemURL)?ID=$($Item.ID)'>$($ItemTitle)</a> in list/library <a href='$($List.ParentWeb.Url)/$($List.RootFolder.Url)'>$($List.Title) </a> is using Unique Permissions.</b><table class='altrowstable' id='alternatecolor' cellpadding='5px'><tr>" >> $OutputReport
                        "<th>Users/Groups </th><th> Type </th><th> User Name </th><th> Permissions</th></tr>" >> $OutputReport
 
                        #Call the function to get Permissions Applied
                        Get-Permissions $Item.RoleAssignments $OutputReport
                         
                        "</table>" >>$OutputReport
                    }
                }
            }
        } #List
    $Counter=$Counter+1;       
    } #Web
"</body></html>" >>$OutputReport
Write-host "`n Permission report generated successfully at "$OutputReport
 
}
 
#**********Configuration Variables************

#$OutputReport = "F:\work\PermisosErreius" + (Get-Random 1000) + ".htm"
$OutputReport = $ReportFile
New-Item $OutputReport -ItemType file
#$SiteCollURL="http://sonorite-sps19/sites/test101"
$SiteCollURL= $url
$ScanFolders=$false
$ScanItemLevel=$True
 
#Call the function to Get Permissions Report
Generate-PermissionRpt $SiteCollURL $OutputReport $ScanFolders $ScanItemLevel


