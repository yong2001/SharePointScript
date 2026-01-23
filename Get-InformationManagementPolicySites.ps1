#Requires -Version 7.1
#Requires -PSEdition Core

<#
.SYNOPSIS
情報管理ポリシーが有効化されているSharePointサイト/リスト/ライブラリを検出するスクリプト

.DESCRIPTION
SharePointの情報管理ポリシー（保持、バーコードなど）が構成されているリスト/ライブラリを
内部列（_dlc_で始まる列）の存在をもとに検出し、一覧を出力します。

前提条件:
- PowerShell 7.1 以上
- PnP.PowerShell モジュール

検出対象の内部列:
- _dlc_ExpireDate: 保持ポリシーによる有効期限
- _dlc_BarcodeValue: バーコード値
- _dlc_BarcodePreview: バーコードプレビュー
- _dlc_Exempt: 保持ポリシーからの除外フラグ
- その他 _dlc_ で始まる列

.PARAMETER SiteUrl
対象サイトのURL（省略時は対話的に入力）

.PARAMETER TenantAdminUrl
テナント管理サイトのURL（全サイトスキャン時に使用）

.PARAMETER ScanAllSites
テナント内の全サイトをスキャンする場合に指定

.PARAMETER OutputPath
結果CSVファイルの出力先パス

.PARAMETER IncludeHiddenLists
非表示リストも含める場合に指定

.EXAMPLE
# 単一サイトのスキャン
.\Get-InformationManagementPolicySites.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/sitename"

.EXAMPLE
# テナント全体のスキャン
.\Get-InformationManagementPolicySites.ps1 -ScanAllSites -TenantAdminUrl "https://tenant-admin.sharepoint.com"

.EXAMPLE
# アプリ認証（クライアントシークレット）を使用
.\Get-InformationManagementPolicySites.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/sitename" -ClientId "00000000-0000-0000-0000-000000000000" -ClientSecret "your-client-secret" -Tenant "tenant.onmicrosoft.com"

.EXAMPLE
# アプリ認証（証明書サムプリント）を使用
.\Get-InformationManagementPolicySites.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/sitename" -ClientId "00000000-0000-0000-0000-000000000000" -Thumbprint "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" -Tenant "tenant.onmicrosoft.com"

.EXAMPLE
# アプリ認証（証明書ファイル）を使用
.\Get-InformationManagementPolicySites.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/sitename" -ClientId "00000000-0000-0000-0000-000000000000" -CertificatePath ".\cert.pfx" -CertificatePassword (ConvertTo-SecureString "password" -AsPlainText -Force) -Tenant "tenant.onmicrosoft.com"

.EXAMPLE
# マネージドID認証を使用（Azure上で実行時）
.\Get-InformationManagementPolicySites.ps1 -SiteUrl "https://tenant.sharepoint.com/sites/sitename" -ManagedIdentity

.NOTES
作成者: ガバナンスチーム
作成日: 2026-01-23
バージョン: 1.0

必要なモジュール: PnP.PowerShell
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SiteUrl = "",
    
    [Parameter(Mandatory = $false)]
    [string]$TenantAdminUrl = "",
    
    [Parameter(Mandatory = $false)]
    [switch]$ScanAllSites,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\InformationManagementPolicy_Results_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeHiddenLists,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeSubsites,
    
    [Parameter(Mandatory = $false)]
    [string]$UserName = "",
    
    [Parameter(Mandatory = $false)]
    [switch]$UseWebLogin,
    
    # === アプリ認証オプション ===
    
    [Parameter(Mandatory = $false)]
    [string]$ClientId = "ae783ed7-4583-48ea-8573-f9070d0691f6",
    
    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = "",
    
    [Parameter(Mandatory = $false)]
    [string]$Tenant = "",
    
    [Parameter(Mandatory = $false)]
    [string]$Thumbprint = "",
    
    [Parameter(Mandatory = $false)]
    [string]$CertificatePath = "",
    
    [Parameter(Mandatory = $false)]
    [SecureString]$CertificatePassword = $null,
    
    [Parameter(Mandatory = $false)]
    [switch]$ManagedIdentity,
    
    [Parameter(Mandatory = $false)]
    [switch]$AutoAddSiteAdmin
)

# 検出対象の _dlc_ 内部列
$Script:DlcColumns = @(
    "_dlc_ExpireDate",
    "_dlc_BarcodeValue", 
    "_dlc_BarcodePreview",
    "_dlc_Exempt",
    "_dlc_BarcodeImage",
    "_dlc_DocId",
    "_dlc_DocIdUrl",
    "_dlc_DocIdPersistId"
)

# ポリシータイプの判定用マッピング
$Script:PolicyTypeMapping = @{
    "_dlc_ExpireDate" = "保持ポリシー (Retention)"
    "_dlc_BarcodeValue" = "バーコードポリシー (Barcode)"
    "_dlc_BarcodePreview" = "バーコードポリシー (Barcode)"
    "_dlc_BarcodeImage" = "バーコードポリシー (Barcode)"
    "_dlc_Exempt" = "保持ポリシー除外 (Retention Exempt)"
    "_dlc_DocId" = "ドキュメントID (Document ID)"
    "_dlc_DocIdUrl" = "ドキュメントID (Document ID)"
    "_dlc_DocIdPersistId" = "ドキュメントID (Document ID)"
}

# 結果格納用
$Script:Results = @()
$Script:ProcessedSites = 0
$Script:TotalSites = 0
$Script:StartTime = Get-Date
$Script:TempAddedAdminSites = @()  # 一時的に管理者を追加したサイトを追跡
$Script:CurrentUserEmail = $null   # 現在のユーザーのメールアドレス

# ログ関数
function Write-LogMessage {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Color = switch ($Level) {
        "INFO" { "White" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
    }
    
    Write-Host "[$Timestamp] [$Level] $Message" -ForegroundColor $Color
}

# PnP PowerShell モジュールの確認
function Initialize-PnPModule {
    Write-LogMessage "PnP PowerShell モジュールを確認中..." "INFO"
    
    $Module = Get-Module -Name "PnP.PowerShell" -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    
    if (-not $Module) {
        Write-LogMessage "PnP.PowerShell モジュールがインストールされていません" "ERROR"
        Write-LogMessage "次のコマンドでインストールしてください: Install-Module -Name PnP.PowerShell -Force" "INFO"
        return $false
    }
    
    Import-Module PnP.PowerShell -Force
    Write-LogMessage "✅ PnP.PowerShell v$($Module.Version) 読み込み完了" "SUCCESS"
    return $true
}

# SharePoint に接続
function Connect-SharePointSite {
    param(
        [string]$Url,
        [bool]$IsAdmin = $false
    )
    
    try {
        # 既存の接続を確認
        $CurrentConnection = Get-PnPConnection -ErrorAction SilentlyContinue
        if ($CurrentConnection -and $CurrentConnection.Url -eq $Url) {
            return $true
        }
        
        # テナント管理サイトかどうかを判定
        $IsTenantAdmin = $Url -like "*-admin.sharepoint.com*" -or $IsAdmin
        
        # === アプリ認証（クライアントシークレット）===
        if ($ClientId -and $ClientSecret -and $Tenant) {
            Write-LogMessage "アプリ認証（クライアントシークレット）で接続します..." "INFO"
            Connect-PnPOnline -Url $Url -ClientId $ClientId -ClientSecret $ClientSecret -Tenant $Tenant -ErrorAction Stop
        }
        # === アプリ認証（証明書サムプリント）===
        elseif ($ClientId -and $Thumbprint -and $Tenant) {
            Write-LogMessage "アプリ認証（証明書サムプリント）で接続します..." "INFO"
            Connect-PnPOnline -Url $Url -ClientId $ClientId -Thumbprint $Thumbprint -Tenant $Tenant -ErrorAction Stop
        }
        # === アプリ認証（証明書ファイル）===
        elseif ($ClientId -and $CertificatePath -and $Tenant) {
            Write-LogMessage "アプリ認証（証明書ファイル）で接続します..." "INFO"
            if ($CertificatePassword) {
                Connect-PnPOnline -Url $Url -ClientId $ClientId -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword -Tenant $Tenant -ErrorAction Stop
            }
            else {
                $CertPass = Read-Host "証明書のパスワードを入力してください" -AsSecureString
                Connect-PnPOnline -Url $Url -ClientId $ClientId -CertificatePath $CertificatePath -CertificatePassword $CertPass -Tenant $Tenant -ErrorAction Stop
            }
        }
        # === マネージドID認証（Azure上で実行時）===
        elseif ($ManagedIdentity) {
            Write-LogMessage "マネージドID認証で接続します..." "INFO"
            Connect-PnPOnline -Url $Url -ManagedIdentity -ErrorAction Stop
        }
        # === ブラウザ認証 ===
        elseif ($UseWebLogin) {
            Write-LogMessage "ブラウザ認証で接続します..." "INFO"
            Connect-PnPOnline -Url $Url -UseWebLogin -ErrorAction Stop
        }
        # === ユーザー名/パスワード認証 ===
        elseif ($UserName) {
            Write-LogMessage "ユーザー認証で接続します (ユーザー: $UserName)..." "INFO"
            $SecurePassword = Read-Host "パスワードを入力してください" -AsSecureString
            $Credentials = New-Object System.Management.Automation.PSCredential ($UserName, $SecurePassword)
            Connect-PnPOnline -Url $Url -Credentials $Credentials -ErrorAction Stop
        }
        # === インタラクティブ認証（デフォルト）===
        else {
            if ($IsTenantAdmin) {
                # テナント管理サイトへの接続時は管理者スコープを要求
                Write-LogMessage "インタラクティブ認証で接続します (テナント管理サイト, ClientId: $ClientId)..." "INFO"
                Write-LogMessage "※ SharePoint管理者権限が必要です" "WARNING"
                Connect-PnPOnline -Url $Url -Interactive -ClientId $ClientId -ErrorAction Stop
            }
            else {
                Write-LogMessage "インタラクティブ認証で接続します (ClientId: $ClientId)..." "INFO"
                Connect-PnPOnline -Url $Url -Interactive -ClientId $ClientId -ErrorAction Stop
            }
        }
        
        # 接続確認
        $Connection = Get-PnPConnection -ErrorAction SilentlyContinue
        if ($Connection) {
            Write-LogMessage "✅ 接続成功: $Url" "SUCCESS"
            return $true
        }
        else {
            Write-LogMessage "❌ 接続が確立されていません" "ERROR"
            return $false
        }
    }
    catch {
        Write-LogMessage "❌ 接続失敗 [$Url]: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# リストの _dlc_ 列を検出
function Get-ListDlcColumns {
    param(
        [object]$List
    )
    
    $FoundColumns = @()
    
    try {
        $Fields = Get-PnPField -List $List -ErrorAction Stop
        
        foreach ($Field in $Fields) {
            if ($Field.InternalName -like "_dlc_*") {
                $FoundColumns += [PSCustomObject]@{
                    InternalName = $Field.InternalName
                    Title = $Field.Title
                    TypeAsString = $Field.TypeAsString
                    PolicyType = if ($Script:PolicyTypeMapping.ContainsKey($Field.InternalName)) {
                        $Script:PolicyTypeMapping[$Field.InternalName]
                    } else {
                        "その他の情報管理ポリシー"
                    }
                }
            }
        }
    }
    catch {
        Write-LogMessage "⚠️ フィールド取得エラー [$($List.Title)]: $($_.Exception.Message)" "WARNING"
    }
    
    return $FoundColumns
}

# 一時的にサイトコレクション管理者を追加
function Add-TemporarySiteAdmin {
    param(
        [string]$SiteUrl
    )
    
    try {
        # テナント管理サイトに接続
        $AdminUrl = $TenantAdminUrl
        if (-not $AdminUrl) {
            # SiteUrlからテナント管理URLを推測
            if ($SiteUrl -match "https://([^.]+)\.sharepoint\.com") {
                $AdminUrl = "https://$($Matches[1])-admin.sharepoint.com"
            }
        }
        
        if (-not $AdminUrl) {
            Write-LogMessage "⚠️ テナント管理URLが不明です" "WARNING"
            return $false
        }
        
        Write-LogMessage "🔑 一時的にサイトコレクション管理者を追加します: $SiteUrl" "INFO"
        
        # テナント管理サイトに接続
        Connect-PnPOnline -Url $AdminUrl -Interactive -ClientId $ClientId -ErrorAction Stop
        
        # 現在のユーザー情報を取得（初回のみ）
        if (-not $Script:CurrentUserEmail) {
            $CurrentUser = Get-PnPProperty -ClientObject (Get-PnPWeb) -Property CurrentUser -ErrorAction SilentlyContinue
            if ($CurrentUser) {
                $Script:CurrentUserEmail = $CurrentUser.Email
            }
            if (-not $Script:CurrentUserEmail) {
                # 別の方法で取得を試みる
                $Context = Get-PnPContext
                $Context.Load($Context.Web.CurrentUser)
                $Context.ExecuteQuery()
                $Script:CurrentUserEmail = $Context.Web.CurrentUser.Email
            }
        }
        
        if (-not $Script:CurrentUserEmail) {
            Write-LogMessage "⚠️ 現在のユーザーのメールアドレスを取得できませんでした" "WARNING"
            return $false
        }
        
        # サイトコレクション管理者を追加
        Set-PnPTenantSite -Url $SiteUrl -Owners $Script:CurrentUserEmail -ErrorAction Stop
        
        # 追加したサイトを記録
        $Script:TempAddedAdminSites += $SiteUrl
        
        Write-LogMessage "✅ サイトコレクション管理者を一時追加: $($Script:CurrentUserEmail)" "SUCCESS"
        
        # 少し待機（反映待ち）
        Start-Sleep -Seconds 3
        
        return $true
    }
    catch {
        Write-LogMessage "❌ サイトコレクション管理者の追加に失敗: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# 一時的に追加したサイトコレクション管理者を削除
function Remove-TemporarySiteAdmin {
    param(
        [string]$SiteUrl
    )
    
    try {
        # テナント管理サイトに接続
        $AdminUrl = $TenantAdminUrl
        if (-not $AdminUrl) {
            if ($SiteUrl -match "https://([^.]+)\.sharepoint\.com") {
                $AdminUrl = "https://$($Matches[1])-admin.sharepoint.com"
            }
        }
        
        if (-not $AdminUrl -or -not $Script:CurrentUserEmail) {
            return
        }
        
        Write-LogMessage "🔓 一時的に追加したサイトコレクション管理者を削除します: $SiteUrl" "INFO"
        
        # テナント管理サイトに接続
        Connect-PnPOnline -Url $AdminUrl -Interactive -ClientId $ClientId -ErrorAction Stop
        
        # 現在のサイト管理者を取得
        $Site = Get-PnPTenantSite -Url $SiteUrl -ErrorAction Stop
        $CurrentOwners = $Site.OwnerEmail
        
        # 自分以外の管理者がいる場合のみ削除（最後の管理者は削除できない）
        # Remove-PnPSiteCollectionAdmin は直接使用できないため、Set-PnPTenantSite で上書き
        # ここでは警告のみ表示
        Write-LogMessage "⚠️ サイトコレクション管理者から手動で削除してください: $($Script:CurrentUserEmail)" "WARNING"
        Write-LogMessage "   サイト: $SiteUrl" "WARNING"
        
    }
    catch {
        Write-LogMessage "⚠️ サイトコレクション管理者の削除に失敗: $($_.Exception.Message)" "WARNING"
    }
}

# サイトをスキャン
function Scan-Site {
    param(
        [string]$SiteUrl,
        [bool]$IsSubsite = $false
    )
    
    $SiteType = if ($IsSubsite) { "サブサイト" } else { "サイト" }
    Write-LogMessage "🔍 ${SiteType}をスキャン中: $SiteUrl" "INFO"
    
    $TempAdminAdded = $false
    
    # まず通常の接続を試みる
    $Connected = Connect-SharePointSite -Url $SiteUrl
    
    # 接続失敗かつ AutoAddSiteAdmin が有効な場合、管理者を一時追加
    if (-not $Connected -and $AutoAddSiteAdmin -and -not $IsSubsite) {
        Write-LogMessage "⚠️ 接続失敗。一時的なサイトコレクション管理者の追加を試みます..." "WARNING"
        
        if (Add-TemporarySiteAdmin -SiteUrl $SiteUrl) {
            $TempAdminAdded = $true
            # 再度接続を試みる
            $Connected = Connect-SharePointSite -Url $SiteUrl
        }
    }
    
    if (-not $Connected) {
        Write-LogMessage "❌ サイトに接続できませんでした: $SiteUrl" "ERROR"
        return
    }
    
    try {
        # サイト情報を取得
        $Web = Get-PnPWeb -ErrorAction Stop
        
        # リスト一覧を取得
        $Lists = Get-PnPList -ErrorAction Stop
        
        if (-not $IncludeHiddenLists) {
            $Lists = $Lists | Where-Object { -not $_.Hidden }
        }
        
        $ListCount = $Lists.Count
        $ProcessedLists = 0
        
        foreach ($List in $Lists) {
            $ProcessedLists++
            Write-Progress -Activity "リストをスキャン中" -Status "$ProcessedLists / $ListCount : $($List.Title)" -PercentComplete (($ProcessedLists / $ListCount) * 100)
            
            # _dlc_ 列を検出
            $DlcColumns = Get-ListDlcColumns -List $List
            
            if ($DlcColumns.Count -gt 0) {
                # ポリシータイプを集約
                $PolicyTypes = ($DlcColumns | Select-Object -ExpandProperty PolicyType -Unique) -join "; "
                $ColumnNames = ($DlcColumns | Select-Object -ExpandProperty InternalName) -join "; "
                
                Write-LogMessage "✅ 検出: $($List.Title) - $PolicyTypes" "SUCCESS"
                
                $Script:Results += [PSCustomObject]@{
                    SiteUrl = $SiteUrl
                    SiteTitle = $Web.Title
                    SiteType = $SiteType
                    ListTitle = $List.Title
                    ListUrl = $List.RootFolder.ServerRelativeUrl
                    ListTemplate = $List.BaseTemplate
                    ListTemplateType = Get-ListTemplateTypeName -TemplateId $List.BaseTemplate
                    ItemCount = $List.ItemCount
                    PolicyTypes = $PolicyTypes
                    DlcColumns = $ColumnNames
                    DlcColumnCount = $DlcColumns.Count
                    IsHidden = $List.Hidden
                    Created = $List.Created
                    LastItemModifiedDate = $List.LastItemModifiedDate
                }
            }
        }
        
        Write-Progress -Activity "リストをスキャン中" -Completed
        
        # サブサイトをスキャン（-IncludeSubsites が指定されている場合）
        if ($IncludeSubsites -and -not $IsSubsite) {
            Scan-Subsites -ParentSiteUrl $SiteUrl
        }
        elseif ($IncludeSubsites -and $IsSubsite) {
            # サブサイトのサブサイトも再帰的にスキャン
            Scan-Subsites -ParentSiteUrl $SiteUrl
        }
    }
    catch {
        Write-LogMessage "❌ サイトスキャンエラー [$SiteUrl]: $($_.Exception.Message)" "ERROR"
    }
    finally {
        # 一時的に追加した管理者を削除（サイトコレクションのみ）
        if ($TempAdminAdded) {
            Remove-TemporarySiteAdmin -SiteUrl $SiteUrl
        }
    }
}

# サブサイトをスキャン
function Scan-Subsites {
    param(
        [string]$ParentSiteUrl
    )
    
    try {
        # 親サイトに接続
        if (-not (Connect-SharePointSite -Url $ParentSiteUrl)) {
            return
        }
        
        # サブサイト一覧を取得
        $Subsites = Get-PnPSubWeb -Recurse -ErrorAction Stop
        
        if ($Subsites -and $Subsites.Count -gt 0) {
            Write-LogMessage "📂 $($Subsites.Count) 個のサブサイトを検出: $ParentSiteUrl" "INFO"
            
            foreach ($Subsite in $Subsites) {
                $SubsiteUrl = $Subsite.Url
                Scan-Site -SiteUrl $SubsiteUrl -IsSubsite $true
            }
        }
    }
    catch {
        Write-LogMessage "⚠️ サブサイト取得エラー [$ParentSiteUrl]: $($_.Exception.Message)" "WARNING"
    }
}

# リストテンプレートタイプ名を取得
function Get-ListTemplateTypeName {
    param([int]$TemplateId)
    
    $TemplateNames = @{
        100 = "カスタムリスト"
        101 = "ドキュメントライブラリ"
        102 = "アンケート"
        103 = "リンク"
        104 = "お知らせ"
        105 = "連絡先"
        106 = "予定表"
        107 = "タスク"
        108 = "ディスカッション掲示板"
        109 = "画像ライブラリ"
        110 = "サイトページ"
        115 = "サイトテンプレートギャラリー"
        119 = "サイトページ (モダン)"
        120 = "カスタムリスト (データシートビュー)"
        140 = "ワークフロー履歴"
        150 = "Webパーツギャラリー"
        170 = "サイトアセット"
        171 = "スタイルライブラリ"
        175 = "コンテンツタイプギャラリー"
        850 = "ページライブラリ"
        851 = "アセットライブラリ"
    }
    
    if ($TemplateNames.ContainsKey($TemplateId)) {
        return $TemplateNames[$TemplateId]
    }
    return "その他 ($TemplateId)"
}

# テナント全体をスキャン
function Scan-AllSites {
    param(
        [string]$AdminUrl
    )
    
    Write-LogMessage "🌐 テナント全体のスキャンを開始..." "INFO"
    Write-LogMessage "📌 テナント管理URL: $AdminUrl" "INFO"
    
    # AdminUrlからテナント名を自動抽出（例: https://tenant-admin.sharepoint.com/ → tenant.onmicrosoft.com）
    $TenantName = $Tenant
    if (-not $TenantName) {
        if ($AdminUrl -match "https://([^-]+)-admin\.sharepoint\.com") {
            $TenantName = "$($Matches[1]).onmicrosoft.com"
            Write-LogMessage "📌 テナント名を自動検出: $TenantName" "INFO"
        }
    }
    
    # テナント管理サイトに接続
    try {
        Write-LogMessage "テナント管理サイトに接続中..." "INFO"
        
        if ($ClientSecret -and $ClientId -and $TenantName) {
            # アプリ認証（クライアントシークレット）
            Write-LogMessage "アプリ認証（クライアントシークレット）で接続します..." "INFO"
            Connect-PnPOnline -Url $AdminUrl -ClientId $ClientId -ClientSecret $ClientSecret -Tenant $TenantName -ErrorAction Stop
        }
        elseif ($Thumbprint -and $ClientId -and $TenantName) {
            # アプリ認証（証明書サムプリント）
            Write-LogMessage "アプリ認証（証明書サムプリント）で接続します..." "INFO"
            Connect-PnPOnline -Url $AdminUrl -ClientId $ClientId -Thumbprint $Thumbprint -Tenant $TenantName -ErrorAction Stop
        }
        elseif ($ManagedIdentity) {
            # マネージドID認証
            Write-LogMessage "マネージドID認証で接続します..." "INFO"
            Connect-PnPOnline -Url $AdminUrl -ManagedIdentity -ErrorAction Stop
        }
        else {
            # インタラクティブ認証（ブラウザポップアップ）
            Write-LogMessage "インタラクティブ認証で接続します (ClientId: $ClientId)..." "INFO"
            Write-LogMessage "※ ブラウザでSharePoint管理者アカウントでサインインしてください" "WARNING"
            Connect-PnPOnline -Url $AdminUrl -Interactive -ClientId $ClientId -ErrorAction Stop
        }
        
        # 接続確認
        $Connection = Get-PnPConnection -ErrorAction SilentlyContinue
        if (-not $Connection) {
            Write-LogMessage "❌ テナント管理サイトへの接続が確立されていません" "ERROR"
            return
        }
        Write-LogMessage "✅ テナント管理サイトに接続済み: $($Connection.Url)" "SUCCESS"
    }
    catch {
        Write-LogMessage "❌ テナント管理サイトへの接続に失敗: $($_.Exception.Message)" "ERROR"
        return
    }
    
    try {
        # 全サイトコレクションを取得
        Write-LogMessage "サイトコレクション一覧を取得中..." "INFO"
        
        $Sites = $null
        try {
            # Get-PnPTenantSiteを試行
            $Sites = Get-PnPTenantSite -ErrorAction Stop
            Write-LogMessage "✅ Get-PnPTenantSite で $($Sites.Count) サイトを取得" "SUCCESS"
        }
        catch {
            $ErrorMsg = $_.Exception.Message
            Write-LogMessage "⚠️ Get-PnPTenantSite でエラー: $ErrorMsg" "WARNING"
            
            # Search APIによるフォールバック
            Write-LogMessage "🔄 Search API を使用してサイト一覧を取得します..." "INFO"
            try {
                # ルートサイトに接続
                $RootUrl = $AdminUrl -replace "-admin", ""
                Write-LogMessage "ルートサイトに接続: $RootUrl" "INFO"
                Connect-PnPOnline -Url $RootUrl -Interactive -ClientId $ClientId -ErrorAction Stop
                
                # Search APIでサイト一覧を取得
                $SearchResults = Submit-PnPSearchQuery -Query "contentclass:STS_Site" -SelectProperties "SPSiteUrl" -All -ErrorAction Stop
                
                if ($SearchResults.ResultRows) {
                    $Sites = $SearchResults.ResultRows | ForEach-Object {
                        [PSCustomObject]@{
                            Url = $_.SPSiteUrl
                        }
                    } | Where-Object { $_.Url } | Sort-Object Url -Unique
                    Write-LogMessage "✅ Search API で $($Sites.Count) サイトを検出" "SUCCESS"
                }
                else {
                    Write-LogMessage "❌ Search API でサイトが見つかりませんでした" "ERROR"
                    return
                }
            }
            catch {
                Write-LogMessage "❌ Search API でも取得できませんでした: $($_.Exception.Message)" "ERROR"
                return
            }
        }
        
        if (-not $Sites -or $Sites.Count -eq 0) {
            Write-LogMessage "❌ サイトを取得できませんでした" "ERROR"
            return
        }
        
        # OneDriveサイトを除外（-my.sharepoint.com/personal/）
        $OriginalCount = $Sites.Count
        $Sites = $Sites | Where-Object { $_.Url -notmatch "-my\.sharepoint\.com" }
        $ExcludedCount = $OriginalCount - $Sites.Count
        
        if ($ExcludedCount -gt 0) {
            Write-LogMessage "📌 OneDriveサイトを除外: $ExcludedCount 件" "INFO"
        }
        
        $Script:TotalSites = $Sites.Count
        Write-LogMessage "✅ $($Script:TotalSites) 個のサイトを検出（OneDrive除く）" "SUCCESS"
        
        # サイト一覧をキャッシュ（接続切り替え後も使用するため）
        $SiteUrls = $Sites | ForEach-Object { $_.Url }
        
        foreach ($SiteUrl in $SiteUrls) {
            $Script:ProcessedSites++
            
            Write-Progress -Activity "サイトをスキャン中" -Status "$($Script:ProcessedSites) / $($Script:TotalSites) : $SiteUrl" -PercentComplete (($Script:ProcessedSites / $Script:TotalSites) * 100)
            
            # 各サイトをスキャン
            Scan-Site -SiteUrl $SiteUrl
        }
        
        Write-Progress -Activity "サイトをスキャン中" -Completed
    }
    catch {
        Write-LogMessage "❌ テナントスキャンエラー: $($_.Exception.Message)" "ERROR"
        Write-LogMessage "   詳細: $($_.Exception.StackTrace)" "ERROR"
    }
}

# 結果をエクスポート
function Export-Results {
    param(
        [string]$Path
    )
    
    try {
        if ($Script:Results.Count -eq 0) {
            Write-LogMessage "⚠️ 情報管理ポリシーが設定されているリスト/ライブラリは見つかりませんでした" "WARNING"
            return
        }
        
        $Script:Results | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        
        Write-LogMessage "✅ 結果を出力しました: $Path" "SUCCESS"
        Write-LogMessage "検出件数: $($Script:Results.Count) 件" "INFO"
        
        # サマリー表示
        Write-LogMessage "" "INFO"
        Write-LogMessage "📊 検出サマリー" "SUCCESS"
        Write-LogMessage "============================================================" "INFO"
        
        # ポリシータイプ別集計
        Write-LogMessage "【ポリシータイプ別】" "INFO"
        $PolicySummary = $Script:Results | ForEach-Object {
            $_.PolicyTypes -split "; "
        } | Group-Object | Sort-Object Count -Descending
        
        foreach ($Policy in $PolicySummary) {
            Write-LogMessage "  $($Policy.Name): $($Policy.Count) 件" "INFO"
        }
        
        Write-LogMessage "" "INFO"
        
        # サイト別集計
        Write-LogMessage "【サイト別】" "INFO"
        $SiteSummary = $Script:Results | Group-Object SiteTitle | Sort-Object Count -Descending | Select-Object -First 10
        
        foreach ($Site in $SiteSummary) {
            Write-LogMessage "  $($Site.Name): $($Site.Count) 件" "INFO"
        }
        
        Write-LogMessage "============================================================" "INFO"
        
        # 一時的に管理者を追加したサイトのサマリー
        if ($Script:TempAddedAdminSites.Count -gt 0) {
            Write-LogMessage "" "WARNING"
            Write-LogMessage "⚠️ 以下のサイトに一時的にサイトコレクション管理者を追加しました:" "WARNING"
            Write-LogMessage "   必要に応じて手動で削除してください: $($Script:CurrentUserEmail)" "WARNING"
            foreach ($TempSite in $Script:TempAddedAdminSites) {
                Write-LogMessage "   - $TempSite" "WARNING"
            }
        }
    }
    catch {
        Write-LogMessage "❌ 結果出力エラー: $($_.Exception.Message)" "ERROR"
    }
}

# メイン処理
function Start-InformationManagementPolicyScan {
    Write-LogMessage "============================================================" "SUCCESS"
    Write-LogMessage "🔍 情報管理ポリシー検出ツール" "SUCCESS"
    Write-LogMessage "============================================================" "INFO"
    Write-LogMessage "実行時刻: $(Get-Date -Format 'yyyy年MM月dd日 HH:mm:ss')" "INFO"
    Write-LogMessage "" "INFO"
    Write-LogMessage "検出対象の内部列:" "INFO"
    foreach ($Col in $Script:DlcColumns) {
        $PolicyType = if ($Script:PolicyTypeMapping.ContainsKey($Col)) { $Script:PolicyTypeMapping[$Col] } else { "その他" }
        Write-LogMessage "  - $Col ($PolicyType)" "INFO"
    }
    Write-LogMessage "" "INFO"
    
    # モジュール初期化
    if (-not (Initialize-PnPModule)) {
        return
    }
    
    # スキャン実行
    # -SiteUrl が指定されている場合は単一サイトスキャンを優先（管理サイト接続不要）
    if ($SiteUrl) {
        Write-LogMessage "📌 単一サイトスキャンモード（管理サイト接続なし）" "INFO"
        Scan-Site -SiteUrl $SiteUrl
    }
    elseif ($ScanAllSites) {
        if (-not $TenantAdminUrl) {
            $TenantAdminUrl = Read-Host "テナント管理サイトURLを入力してください (例: https://tenant-admin.sharepoint.com)"
        }
        
        Scan-AllSites -AdminUrl $TenantAdminUrl
    }
    else {
        $SiteUrl = Read-Host "スキャン対象のサイトURLを入力してください"
        Scan-Site -SiteUrl $SiteUrl
    }
    
    # 結果出力
    Export-Results -Path $OutputPath
    
    # 処理時間
    $ElapsedTime = (Get-Date) - $Script:StartTime
    Write-LogMessage "" "INFO"
    Write-LogMessage "処理時間: $([math]::Round($ElapsedTime.TotalMinutes, 2)) 分" "INFO"
    Write-LogMessage "" "INFO"
    Write-LogMessage "============================================================" "SUCCESS"
    Write-LogMessage "🎉 スキャン完了！" "SUCCESS"
    Write-LogMessage "============================================================" "INFO"
}

# スクリプト実行
if ($MyInvocation.InvocationName -ne '.') {
    Start-InformationManagementPolicyScan
}
