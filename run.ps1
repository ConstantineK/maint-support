Set-StrictMode -Version 2

$start_time = "$(Get-Date -Format "yyyy-M-d HH:mm:ss")"
$sourcedir = "~\code\sql-server-maintenance-solution\MaintenanceSolution.sql"
$sqlserver = "localhost"
$database = "master"

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues=@{
  "Invoke-SqlCommand:ServerInstance" = $sqlserver
  "Invoke-SqlCommand:Database" = $database
  "Invoke-SqlCmd:ServerInstance" = $sqlserver
  "Invoke-SqlCmd:Database" = $database
}

function Invoke-SqlCommand {
  Param(
    [string]$ServerInstance,
    [string]$Database,
    [string]$Script,
    [int]$Timeout = 300
  )
  # nabbed https://www.robinosborne.co.uk/2014/10/13/getting-past-powershell-sqls-incorrect-syntax-near-go-message/
  # plus tiny edits
  $batches = $Script -split "GO\r\n"

  $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
  $SqlConnection.ConnectionString = "Server=$ServerInstance;Database=$Database;Trusted_Connection=True;Connection Timeout=$Timeout;"
  $SqlConnection.Open()

  $Global:message_capture = New-Object System.Collections.ArrayList
  $handler = [System.Data.SqlClient.SqlInfoMessageEventHandler] {
    param($sender, $event)
    $Global:message_capture.Add($event.Message)
  }
  $SqlConnection.add_InfoMessage($handler)
  $SqlConnection.FireInfoMessageEventOnUserErrors = $true

  foreach($batch in $batches)
  {
      if ($batch.Trim() -ne ""){
          $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
          $SqlCmd.CommandText = $batch
          $SqlCmd.Connection = $SqlConnection
          [int]$out = $SqlCmd.ExecuteNonQuery()
          $hander
      }
  }
  $SqlConnection.Close()
}

$cases = @{
  "IndexOptimize-SystemDatabases" = "
    EXECUTE [dbo].[IndexOptimize]
      @Databases = 'SYSTEM_DATABASES',
      @LogToTable = 'Y'"

  "DatabaseIntegrityCheck-SystemDatabases" = "
    EXECUTE [dbo].[DatabaseIntegrityCheck]
      @Databases = 'SYSTEM_DATABASES',
      @LogToTable = 'Y'"

  "DatabaseBackup-SystemDatabases" = "
    DECLARE @output TABLE (Value nvarchar(50), Data nvarchar(500))
    DECLARE @path nvarchar(500)

    INSERT @output (Value, Data)
    EXEC master.dbo.xp_instance_regread
      N'HKEY_LOCAL_MACHINE',
      N'Software\Microsoft\MSSQLServer\MSSQLServer',N'BackupDirectory'
    SET @path = (SELECT TOP 1 Data FROM @output)

    EXECUTE [dbo].[DatabaseBackup]
      @Databases = 'SYSTEM_DATABASES',
      @Directory = @path,
      @BackupType = 'FULL',
      @Verify = 'Y',
      @CleanupTime = NULL,
      @CheckSum = 'Y',
      @LogToTable = 'Y'"
}

# get install script
$queries = (Get-Content $sourcedir -raw).Replace('C:\Backup','E:\Install\Data\MSSQL14.MSSQLSERVER\MSSQL\Backup')

# run install script
Invoke-SqlCommand -Script $queries

# start jobs
foreach ($job in $jobs){
  Invoke-SqlCmd -Query "

  "
}

Start-Sleep -Seconds 2
# verify jobs are done
$verify_done = "
  SELECT COUNT(*) as done
  FROM msdb.dbo.sysjobactivity ja
  WHERE ja.session_id = (SELECT TOP 1 session_id FROM msdb.dbo.syssessions ORDER BY agent_start_date DESC)
  AND start_execution_date is not null
  AND stop_execution_date is null;
"
$breaker = 1
while (1 -eq $breaker){
  $running_jobs = (
    Invoke-SqlCmd -Query $verify_done |
    Select-Object -ExpandProperty done
  )

  if ($running_jobs -eq 0){
    $breaker = 2
  }
  else {
    $running_jobs
  }
}
Start-Sleep -Seconds 2
# Invoke-SqlCmd -Query "select * from dbo.CommandLog order by id desc" |
#   Where-Object { $_.EndTime -gt (Get-Date).AddHours(-1) } |
#   Select-Object Command, CommandType, ErrorMessage, ErrorNumber, EndTime |
#
# check output