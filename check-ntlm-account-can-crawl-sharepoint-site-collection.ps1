$site_col_url="https://your.sharepoint-site.com/sites/mysitecol"

$cred = (Get-Credential)

if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type)
{
$certCallback = @"
    using System;
    using System.Net;
    using System.Net.Security;
    using System.Security.Cryptography.X509Certificates;
    public class ServerCertificateValidationCallback
    {
        public static void Ignore()
        {
            if(ServicePointManager.ServerCertificateValidationCallback ==null)
            {
                ServicePointManager.ServerCertificateValidationCallback +=
                    delegate
                    (
                        Object obj,
                        X509Certificate certificate,
                        X509Chain chain,
                        SslPolicyErrors errors
                    )
                    {
                        return true;
                    };
            }
        }
    }
"@
    Add-Type $certCallback
 }

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
[ServerCertificateValidationCallback]::Ignore()

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "text/xml")
$headers.Add("SOAPAction", "http://schemas.microsoft.com/sharepoint/soap/GetUpdatedFormDigestInformation")
$headers.Add("X-RequestForceAuthentication", "true")
$headers.Add("X-FORMS_BASED_AUTH_ACCEPTED", "f")

$body = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n<soap:Envelope xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`" xmlns:xsd=`"http://www.w3.org/2001/XMLSchema`" xmlns:soap=`"http://schemas.xmlsoap.org/soap/envelope/`">`n  <soap:Body>`n    <GetUpdatedFormDigestInformation xmlns=`"http://schemas.microsoft.com/sharepoint/soap/`" />`n  </soap:Body>`n</soap:Envelope>"

$response = Invoke-RestMethod "${site_col_url}/_vti_bin/sites.asmx" -Method 'POST' -Headers $headers -Body $body -Credential $cred

$digest_value = $response.Envelope.Body.GetUpdatedFormDigestInformationResponse.FirstChild.DigestValue

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "text/xml")
$headers.Add("X-RequestForceAuthentication", "true")
$headers.Add("X-RequestDigest", $digest_value)
$headers.Add("Accept", "application/json")
$headers.Add("X-FORMS_BASED_AUTH_ACCEPTED", "f")

$body = @'
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="14.0.0.0" LibraryVersion="16.0.0.0"
         ApplicationName=".NET Library" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009">
    <Actions>
        <ObjectPath Id="2" ObjectPathId="1"/>
        <ObjectPath Id="4" ObjectPathId="3"/>
        <Query Id="5" ObjectPathId="3">
            <Query SelectAllProperties="false">
                <Properties>
                    <Property Name="Webs" SelectAll="true">
                        <Query SelectAllProperties="false">
                            <Properties/>
                        </Query>
                    </Property>
                    <Property Name="Title" ScalarProperty="true"/>
                    <Property Name="ServerRelativeUrl" ScalarProperty="true"/>
                    <Property Name="RoleDefinitions" SelectAll="true">
                        <Query SelectAllProperties="false">
                            <Properties/>
                        </Query>
                    </Property>
                    <Property Name="RoleAssignments" SelectAll="true">
                        <Query SelectAllProperties="false">
                            <Properties/>
                        </Query>
                    </Property>
                    <Property Name="HasUniqueRoleAssignments" ScalarProperty="true"/>
                    <Property Name="Description" ScalarProperty="true"/>
                    <Property Name="Id" ScalarProperty="true"/>
                    <Property Name="LastItemModifiedDate" ScalarProperty="true"/>
                </Properties>
            </Query>
        </Query>
    </Actions>
    <ObjectPaths>
        <StaticProperty Id="1" TypeId="{3747adcd-a3c3-41b9-bfab-4a64dd2f1e0a}" Name="Current"/>
        <Property Id="3" ParentId="1" Name="Web"/>
    </ObjectPaths>
</Request>
'@

$response = Invoke-RestMethod "${site_col_url}/_vti_bin/client.svc/ProcessQuery" -Method 'POST' -Headers $headers -Body $body -Credential $cred
$response | ConvertTo-Json -Depth 100
