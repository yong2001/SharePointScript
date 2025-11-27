SharePoint Server 2019 と SharePoint Server サブスクリプション エディションの累積更新プログラムのインストール時間を比較すると、顕著な差があります。
例えば、私のテストマシンでは、SharePoint Server 2019 の修正プログラムのインストールには約 20 分かかるのに対し、同様の SharePoint Server サブスクリプション エディションの修正プログラムではほぼ 1 時間かかります。

このインストール時間延長の理由は、SharePoint Server 2019 の修正プログラムでは、インストーラーが修正プログラムのインストールを実行する前に、関連するすべての SharePoint および IIS Windows サービスを停止するのに対し、SharePoint Server サブスクリプション エディションの修正プログラムではこれらのサービスが停止されないためです。根本的な原因は、サービス停止に使用される方法が SharePoint Server サブスクリプションでは機能しなくなったことです。これにより、ファイルが使用中であるためにインストーラーがグローバル アセンブリ キャッシュ内のアセンブリを更新しようとすると、パフォーマンスの問題が発生します。
パフォーマンスを改善するには、修正を適用する前に該当するWindowsサービスを停止し、その後再起動する必要があります。
修正を適用する前に停止すべきサービスのリストは以下の通りです。サービスを停止した状態を維持し、自動的に再起動されないようにするには順序が重要です：
      Server Role	Service
      All	SharePoint Timer Service (SPTimerV4)
      All	SharePoint Tracing Service (SPTraceV4)
      All	SharePoint Administration (SPAdminV4)
      All	World Wide Web (W3SVC)
      Search	SharePoint Server Search (OSearch16)
      Search	SharePoint Search Host Controller Service (SPSearchHostController)
      Distributed Cache	SharePoint Caching Service (SPCache)

上記に列挙したサービスの停止/再起動手順は、スクリプトを使用して自動化できます。便宜上、必要な操作を実行するサンプルスクリプトを作成しました：
GetSiteclectionPermisson.ps1

このスクリプトには2つのパラメータがあります：

CULocation (必須): インストール予定のCUの場所を指定します。例: C:\temp\uber-subscription-kb5002560-fullfile-x64-glb.exe
ShouldGracefulStopDCache (オプション): 現在のサーバー上の分散キャッシュサービスの正常なシャットダウンを試行する場合は $true を指定します。
ゼロダウンタイムパッチングを実施中のファーム（複数の分散キャッシュホストが存在）において、
分散キャッシュのインスタンスをホストするサーバーの臨時ディレクトリに事前にダウンロード済みの2024年2月SharePoint累積更新プログラムを適用する場合
Install-SPSE_Fix.ps1 -CULocation C:\temp\uber-subscription-kb5002560-fullfile-x64-glb.exe -ShouldGracefulStopDCache $true
ゼロダウンタイムパッチングを行わない場合、以下のコマンドを
Install-SPSE_Fix.ps1 -CULocation C:\temp\uber-subscription-kb5002560-fullfile-x64-glb.exe
