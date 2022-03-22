param($sitename)
 
Get-SPWeb -site $sitename |
ForEach-Object{
$strsitename = "sitename " + $_.url + " title:" + $_.title ; Write-Output $strsitename; $_.lists | ForEach-Object{
  $strlistname = "  list:" + $_.Title;
  Write-Output $strlistname;
  $_.RoleAssignments |
  ForEach-Object{
    $strRole = "      " +  $_.Member.Name;
    Write-Output $strRole;
     $_.RoleDefinitionBindings |
    ForEach-Object{
     $str = "      *" + $_.Name;
     Write-Output $str;
                                }
                }
  $_.items |
  ForEach-Object{
   $strItem = "         item:" + $_.Title;
   Write-Output $strItem;
   $_.RoleAssignments |
   ForEach-Object{
     $strRoleitem = "             " + $_.Member.Name;
     Write-Output $strRoleitem;
      $_.RoleDefinitionBindings |
     ForEach-Object{
      $str = "             **" + $_.Name;
      Write-Output $str;
                                 }
   }
                }
  }
}
