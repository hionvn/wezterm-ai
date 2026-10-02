# Thông báo Windows bấm được: bấm vào → nhảy về đúng ô WezTerm (link wezai-o:<PANEID> → chuyen-o.ps1).
# WezTerm gọi qua an.vbs (không nháy cửa sổ). Cần đăng ký link một lần: dang-ky-thong-bao.ps1.
param([int]$Pane = -1, [string]$Title = 'WezTerm · đội AI', [string]$Text = 'AI cần bạn')

function Esc([string]$s) { [Security.SecurityElement]::Escape($s) }
$launch = if ($Pane -ge 0) { "wezai-o:$Pane" } else { '' }
$attr = if ($launch) { " activationType=""protocol"" launch=""$launch""" } else { '' }
$xmlText = @"
<toast$attr>
  <visual><binding template="ToastGeneric">
    <text>$(Esc $Title)</text>
    <text>$(Esc $Text)</text>
    $(if ($launch) { '<text placement="attribution">Bấm để mở đúng ô</text>' })
  </binding></visual>
</toast>
"@

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml($xmlText)
$appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
