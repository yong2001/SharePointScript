<#Disclaimer:

This code is sample code. These samples are provided "as is" without warranty of any kind.

Microsoft further disclaims all implied warranties including without limitation 
any implied warranties of merchantability or of fitness for a particular purpose. 
The entire risk arising out of the use or performance of the samples remains with you. 
In no event shall Microsoft or its suppliers be liable for any damages whatsoever 
(including, without limitation, damages for loss of business profits, business interruption, 
loss of business information, or other pecuniary loss) arising out of the use of or inability to use the samples, 
even if Microsoft has been advised of the possibility of such damages. Because some states do not allow 
the exclusion or limitation of liability for consequential or incidental damages, 
the above limitation may not apply to you. #>


<#
HELPFUL UNIFIED GROUP SAMPLE COMMANDS

Here are some helpful Exchange Online PowerShell commands,
when troubleshooting unified group "Follow in Inbox" settings.
#>

#Find subscribers - people who have ALL emails to this group coming in to their inboxes
Get-UnifiedGroup "test-team@domain.com" | Get-UnifiedGroupLinks -LinkType Subscribers

#Check subscription status for ALL unified groups
Get-UnifiedGroup | Format-Table Name,*subscribe* -AutoSize

#Prevent new group members from being subscribed to all messages
Set-UnifiedGroup -Identity "test-team@domain.com" -AutoSubscribeNewMembers:$false

#Prevent new group members from being subscribed to calendar events
Set-UnifiedGroup -Identity "test-team@domain.com" -AlwaysSubscribeMembersToCalendarEvents:$false

<#
HOW TO: UNSUBSCRIBE ALL TEAM MEMBERS FROM UNIFIED GROUP "FOLLOW IN INBOX" EMAILS

If your users are recieving Teams channel meeting calendar invites delivered to their inboxes,
it is likely that the unified group settings are causing the "Follow in inbox" to be turned on.
You can use these steps to unsubscribe all members of a Team from "Follow in inbox".

Remember that Teams are built on top of Unified Groups,
and Unified Groups are managed in Exchange Online PowerShell: https://aka.ms/exops

Since the UnifiedGroup cmdlets are limited,
the only way to unsubscribe all members of a Unified Group / Team
is to first subscribe them all, then unsubscribe them all.

Please note this will not remove members from the group.
However, this procedure will forcefully remove/reset 
all of the group members' subscription preferences. The assumption 
with this procedure is that you are ready to set all group members
subscription preferences to be "Recieve only replies to you" for "Follow in Inbox" settings.
#>


##########################################
#  Loop 1 - SUBSCRIBE all group members  #
##########################################

#Store the team name in a variable. Change this to match your team. 
#To find this for your team, use (Get-UnifiedGroup *test-team*).PrimarySmtpAddress
$teamname = "test-team@example.com"

#Find all the members of the Unified Group "test-team" and store their UserMailbox objects in a variable called "members"
$members = Get-UnifiedGroup $teamname | Get-UnifiedGroupLinks -LinkType Member

#Create a variable to keep track of how many members we have subscribed or unsubscribed
$membercount = ($members.Count)

#Loop through the list of members and add a subscriber link for each one
foreach ($member in $members) 
{
    #Decrement the member count
    $membercount--
    
    #Write progress to the PowerShell window
    Write-Host "Adding subscriber link for user $($member.PrimarySmtpAddress), $membercount users remaining"
    
    #Add the UnifiedGroupLink to make each user a subscriber
    Add-UnifiedGroupLinks -Identity $teamname -Links $($member.PrimarySmtpAddress) -LinkType Subscriber -Confirm:$false
}

##########################################
# Loop 2 - UNSUBSCRIBE all group members #
##########################################

#Find all the subscribers of the Unified Group "test-team" and store their UserMailbox objects in a variable called "subscribers"
$subscribers = Get-UnifiedGroup $teamname | Get-UnifiedGroupLinks -LinkType Subscriber

#Create a variable to keep track of how many members we have subscribed or unsubscribed
$subscribercount = ($subscribers.Count)

#Loop through the list of subscribers and remove the subscriber link, unsubscribing each user
foreach ($subscriber in $subscribers) 
{
    #Decrement the subscriber count
    $subscribercount--

    #Write progress to the PowerShell window
    Write-Host "Removing subscriber link for user $($subscriber.PrimarySmtpAddress), $subscribercount users remaining"
    
    #Remove the UnifiedGroupLink to unsubscribe each member
    Remove-UnifiedGroupLinks -Identity $teamname -Links $($subscriber.PrimarySmtpAddress) -LinkType Subscriber -Confirm:$false
}
