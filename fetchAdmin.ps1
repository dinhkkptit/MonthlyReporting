###########################################################################################################
#                                                                                                         #
# File:          fetchAdmin.ps1                                                                           #
#                                                                                                         #
# Purpose:       Script to collect administrative vSphere reports from a connected vCenter Server         #
#                                                                                                         #
# Requirements:  Windows PowerShell 5.1 (Windows Server 2019) + VMware PowerCLI 13+                     #
#                                                                                                         #
###########################################################################################################

# Source file with common function:
# ---------------------------------
. .\commonFunctions.ps1


# Read configuration file:
# ------------------------
$confTable = readConfiguration


# Prepare output directory:
# -------------------------
$dateFolder = Get-Date -UFormat "%Y-%m-%d"
$timestamp = Get-Date -UFormat "%Y-%m-%d_%H-%M-%S"
$aktReportDir = "$($confTable["Subdirs"]["reportDir"])\$dateFolder"
IF( !$(Test-Path "$aktReportDir") )
{
	mkdir "$aktReportDir" > $null
}

$serverName = $server.Name
Write-Host ""
Write-Host "Collecting admin information from $serverName ..."


# 1) Turn off SSH on hosts if running:
# ------------------------------------
$hostSshRows = @()
ForEach( $vmHost in (Get-VMHost | Sort-Object Name) )
{
	$sshService = Get-VMHostService -VMHost $vmHost | Where-Object { $_.Key -eq "TSM-SSH" }
	IF( $sshService )
	{
		$stateBefore = $sshService.Running
		$action = "None"
		IF( $sshService.Running )
		{
			try
			{
				Stop-VMHostService -HostService $sshService -Confirm:$false > $null
				$action = "Stopped"
			}
			catch
			{
				$action = "StopFailed"
			}
		}
		$row = "" | Select-Object Host, SSHWasRunning, ActionTaken
		$row.Host = $vmHost.Name
		$row.SSHWasRunning = $stateBefore
		$row.ActionTaken = $action
		$hostSshRows += $row
	}
}
$sshOutfile = "$aktReportDir\AdminSshStatus_$serverName`_$timestamp.csv"
$hostSshRows | Export-Csv "$sshOutfile" -NoTypeInformation -Delimiter ";"
Write-Host "Saved SSH host status in $sshOutfile"


# 2) Count VMs per cluster:
# -------------------------
$clusterVmRows = @()
ForEach( $cluster in (Get-Cluster | Sort-Object Name) )
{
	$row = "" | Select-Object Cluster, VMCount
	$row.Cluster = $cluster.Name
	$row.VMCount = (Get-VM -Location $cluster | Measure-Object).Count
	$clusterVmRows += $row
}
$clusterCountOutfile = "$aktReportDir\AdminClusterVmCount_$serverName`_$timestamp.csv"
$clusterVmRows | Export-Csv "$clusterCountOutfile" -NoTypeInformation -Delimiter ";"
Write-Host "Saved VM count per cluster in $clusterCountOutfile"


# 3) 10 largest VMs per cluster:
# ------------------------------
$largestVmRows = @()
ForEach( $cluster in (Get-Cluster | Sort-Object Name) )
{
	$clusterVms = Get-VM -Location $cluster
	$topVms = $clusterVms | Sort-Object -Property ProvisionedSpaceGB -Descending | Select-Object -First 10
	ForEach( $vm in $topVms )
	{
		$row = "" | Select-Object Cluster, VM, ProvisionedGB, UsedGB, PowerState
		$row.Cluster = $cluster.Name
		$row.VM = $vm.Name
		$row.ProvisionedGB = [Math]::Round($vm.ProvisionedSpaceGB, 2)
		$row.UsedGB = [Math]::Round($vm.UsedSpaceGB, 2)
		$row.PowerState = $vm.PowerState
		$largestVmRows += $row
	}
}
$largestOutfile = "$aktReportDir\AdminLargestVmsPerCluster_$serverName`_$timestamp.csv"
$largestVmRows | Export-Csv "$largestOutfile" -NoTypeInformation -Delimiter ";"
Write-Host "Saved largest VMs per cluster in $largestOutfile"


# 4) Users currently logged into vCenter:
# ---------------------------------------
$sessionManager = Get-View SessionManager
$activeSessions = @($sessionManager.SessionList)
$sessionRows = @()
ForEach( $session in $activeSessions )
{
	$row = "" | Select-Object UserName, FullName, IpAddress, LoginTime, LastActiveTime, SessionKey
	$row.UserName = $session.UserName
	$row.FullName = $session.FullName
	$row.IpAddress = $session.IpAddress
	$row.LoginTime = $session.LoginTime
	$row.LastActiveTime = $session.LastActiveTime
	$row.SessionKey = $session.Key
	$sessionRows += $row
}
$sessionsOutfile = "$aktReportDir\AdminLoggedInUsers_$serverName`_$timestamp.csv"
$sessionRows | Export-Csv "$sessionsOutfile" -NoTypeInformation -Delimiter ";"
Write-Host "Saved logged-in user sessions in $sessionsOutfile"


# 5) Disconnect idle users:
# -------------------------
$idleMinutes = 60
IF( $confTable.ContainsKey("Admin") -and $confTable["Admin"].ContainsKey("disconnectIdleMinutes") )
{
	$idleMinutes = [int]$confTable["Admin"]["disconnectIdleMinutes"]
}

$disconnectRows = @()
$now = Get-Date
$currentSessionKey = $sessionManager.CurrentSession.Key
ForEach( $session in $activeSessions )
{
	$minutesIdle = [Math]::Round((New-TimeSpan -Start $session.LastActiveTime -End $now).TotalMinutes, 2)
	$action = "Skipped"
	IF( $session.Key -eq $currentSessionKey )
	{
		$action = "SkippedCurrentSession"
	}
	ELSEIF( $minutesIdle -ge $idleMinutes )
	{
		try
		{
			$sessionManager.TerminateSession(@($session.Key))
			$action = "Disconnected"
		}
		catch
		{
			$action = "DisconnectFailed"
		}
	}
	$row = "" | Select-Object UserName, IpAddress, LastActiveTime, IdleMinutes, Action
	$row.UserName = $session.UserName
	$row.IpAddress = $session.IpAddress
	$row.LastActiveTime = $session.LastActiveTime
	$row.IdleMinutes = $minutesIdle
	$row.Action = $action
	$disconnectRows += $row
}
$disconnectOutfile = "$aktReportDir\AdminDisconnectedIdleUsers_$serverName`_$timestamp.csv"
$disconnectRows | Export-Csv "$disconnectOutfile" -NoTypeInformation -Delimiter ";"
Write-Host "Saved idle session disconnect report in $disconnectOutfile"


# 6) List VMs with snapshots:
# ---------------------------
$snapshotRows = @()
ForEach( $snapshot in (Get-VM | Get-Snapshot | Sort-Object VM, Created) )
{
	$row = "" | Select-Object VM, SnapshotName, Description, Created, SizeGB, PowerState
	$row.VM = $snapshot.VM.Name
	$row.SnapshotName = $snapshot.Name
	$row.Description = $snapshot.Description
	$row.Created = $snapshot.Created
	$row.SizeGB = [Math]::Round($snapshot.SizeGB, 2)
	$row.PowerState = $snapshot.PowerState
	$snapshotRows += $row
}
$snapshotOutfile = "$aktReportDir\AdminVmsWithSnapshots_$serverName`_$timestamp.csv"
$snapshotRows | Export-Csv "$snapshotOutfile" -NoTypeInformation -Delimiter ";"
Write-Host "Saved VM snapshot report in $snapshotOutfile"


# Summary file:
# -------------
$summaryOutfile = "$aktReportDir\AdminSummary_$serverName`_$timestamp.txt"
"Admin report for: $serverName" | Add-Content $summaryOutfile
"Timestamp: $timestamp" | Add-Content $summaryOutfile
"" | Add-Content $summaryOutfile
"Hosts scanned: $($hostSshRows.Count)" | Add-Content $summaryOutfile
"Clusters scanned: $($clusterVmRows.Count)" | Add-Content $summaryOutfile
"Top-VM rows generated: $($largestVmRows.Count)" | Add-Content $summaryOutfile
"Active sessions found: $($sessionRows.Count)" | Add-Content $summaryOutfile
"Snapshot rows found: $($snapshotRows.Count)" | Add-Content $summaryOutfile
"Idle cutoff (minutes): $idleMinutes" | Add-Content $summaryOutfile
Write-Host "Saved admin summary in $summaryOutfile"

# DONE!
