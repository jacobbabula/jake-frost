param(
    [Parameter(Mandatory=$true)][int]$AppProcessId,
    [Parameter(Mandatory=$true)][string]$GiftReceipt
)
$ErrorActionPreference = 'Stop'
$framework = [Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()
$assemblies = @('System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll')
foreach ($name in 'UIAutomationClient','UIAutomationTypes','WindowsBase') {
    $assemblies += (Join-Path $framework "WPF\$name.dll")
}
Add-Type -Path (Join-Path $PSScriptRoot 'WindowsPanel.cs') -ReferencedAssemblies $assemblies
[WindowsPanel]::Run($AppProcessId, $GiftReceipt)
