
$auditLogs = Search-UnifiedAuditLog -Operations ListItemViewed -ResultSize 5000 -StartDate '2022/03/01' -EndDate '2022/03/16' | % AuditData | ConvertFrom-Json
$auditLogs | group ObjectId -n | sort Count -Descending | ft -a
