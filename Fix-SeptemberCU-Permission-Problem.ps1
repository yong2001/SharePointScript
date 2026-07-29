<#
 This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment.  
 THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, 
 INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  
 We grant you a nonexclusive, royalty-free right to use and modify the sample code and to reproduce and distribute the object 
 code form of the Sample Code, provided that you agree: 
    (i)   to not use our name, logo, or trademarks to market your software product in which the sample code is embedded; 
    (ii)  to include a valid copyright notice on your software product in which the sample code is embedded; and 
    (iii) to indemnify, hold harmless, and defend us and our suppliers from and against any claims or lawsuits, including 
          attorneys' fees, that arise or result from the use or distribution of the sample code.
 Please note: None of the conditions outlined in the disclaimer above will supercede the terms and conditions contained within 
              the Premier Customer Services Description.


  SUMMARY: 
    
   This script removes all incorrect Deny Write ACEs from 14\template\layouts and 16\template\layouts directory applied by September 2025 CU

   Reference: 
   https://blog.stefan-gossner.com/2025/09/11/trending-issue-sharepoint-fixes-fail-to-install-after-installation-of-september-2025-cu/

   Version History:
    1.0 - initial version
  
#>

try {
    # Define accounts and rights
    $wssWpgGroup  = "WSS_WPG"
    $iisIusrsGroup = "IIS_IUSRS"

    # Get path to to installation root - usually C:\Program Files\Common Files
    $commonProgramFiles = [System.Environment]::GetEnvironmentVariable("CommonProgramFiles")
    if (-not $commonProgramFiles) {
        $commonProgramFiles = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::CommonProgramFiles)
    }

    # Process both version 14 and 16 paths
    $versions = @("14", "16")
    foreach ($version in $versions) {
        $layoutsPathTemplate      = "%COMMONPROGRAMFILES%\Microsoft Shared\Web Server Extensions\$version\TEMPLATE\LAYOUTS"
        $layoutsPath = [System.Environment]::ExpandEnvironmentVariables($layoutsPathTemplate)

        # Fallback to manual construction if environment variable expansion fails
        if (-not (Test-Path -LiteralPath $layoutsPath -PathType Container)) {
            $layoutsPath = Join-Path $commonProgramFiles "Microsoft Shared\Web Server Extensions\$version\TEMPLATE\LAYOUTS"
        }

        # check if the path exists
        if (Test-Path -LiteralPath $layoutsPath -PathType Container) {

            # get current Acl from Layouts directory
            $acl = Get-Acl -LiteralPath $layoutsPath

            # update Acl for WSS_WPG and IIS_IUSRS
            foreach ($group in @($wssWpgGroup, $iisIusrsGroup)) {

                # Find all matching Deny/Write rules for the group
                $rulesToRemove = $acl.Access | Where-Object {
                    $_.IdentityReference.Value -like "*\$group" -or
                    $_.IdentityReference.Value -eq $group
                } | Where-Object {
                    $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
                    ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Write) -ne 0
                }

                # Remove all matching Deny/Write rules for the group
                foreach ($rule in $rulesToRemove) {
                    $acl.RemoveAccessRuleSpecific($rule)
                }
            }

            # Update the Acl on the Layouts directory
            Set-Acl -LiteralPath $layoutsPath -AclObject $acl

            Write-Host "Fixed Permissions for $layoutsPath"
        }
        else {
            Write-Host "WARNING: The LAYOUTS folder does not exist at '$layoutsPath'" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "ERROR: Failed unsetting deny WSS_WPG and IIS_IUSRS groups write access. [Exception=$($_.Exception.ToString())]" -ForegroundColor Red
}