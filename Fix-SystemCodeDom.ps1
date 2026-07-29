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
    
   This script adds the missing authorizedType entry prevening SP2010 workflows from working after installing July 2026 CU
   
   Reference: 
   https://blog.stefan-gossner.com/2026/07/17/trending-issue-sharepoint-2010-workflows-are-failing-after-installing-july-2026-cu/
   Version History:
    1.0 - initial version
  
#>


param(
    [Parameter(Mandatory = $true)]
    [string]$WebApplicationUrl
)

$webApp = Get-SPWebApplication $WebApplicationUrl

if ($null -eq $webApp)
{
    throw "Web Application '$WebApplicationUrl' not found."
}

$modification = New-Object Microsoft.SharePoint.Administration.SPWebConfigModification

$modification.Owner = "CustomWorkflowAuthorizedType"

$modification.Path = "configuration/System.Workflow.ComponentModel.WorkflowCompiler/authorizedTypes/targetFx[@version='v4.0']"

$modification.Name = "authorizedType[@Assembly='System, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089' and @Namespace='System.CodeDom' and @TypeName='*' and @Authorized='True']"

$modification.Sequence = 0
$modification.Type = [Microsoft.SharePoint.Administration.SPWebConfigModification+SPWebConfigModificationType]::EnsureChildNode

$modification.Value = '<authorizedType Assembly="System, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089" Namespace="System.CodeDom" TypeName="*" Authorized="True" />'

# Prevent duplicates
$existing = $webApp.WebConfigModifications |
    Where-Object {
        $_.Owner -eq $modification.Owner -and
        $_.Path -eq $modification.Path -and
        $_.Name -eq $modification.Name
    }

if ($existing)
{
    Write-Host "Modification already exists." -ForegroundColor Yellow
}
else
{
    $webApp.WebConfigModifications.Add($modification)
    $webApp.Update()

    Write-Host "Applying web.config modifications..." -ForegroundColor Green
    $webApp.Parent.ApplyWebConfigModifications()

    Write-Host "Modification added successfully." -ForegroundColor Green
}