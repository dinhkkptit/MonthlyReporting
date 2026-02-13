# Monthly Reporting (PowerShell)

This repository contains a PowerShell-based monthly reporting utility for VMware vCenter environments.

It can collect and send reports for:
- Datastores
- Hosts
- Machines
- Networks
- Templates
- Admin

## Requirements

- Windows PowerShell 5.1
- VMware PowerCLI 13+
- Access to one or more vCenter servers
- SMTP server details in `configuration.ini`

## Project Structure

- `main.ps1`: entry point and orchestration
- `commonFunctions.ps1`: shared utility functions (configuration, credentials, connection)
- `fetch*.ps1`: data collection scripts per report type
- `sendReports.ps1`: email assembly and sending
- `tidyUp.ps1`: cleanup of old logs/reports
- `configuration.ini`: installation paths, cleanup settings, mail, recipients

## Run the script

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File C:\monthlyReporting\main.ps1
```

Example (single vCenter wildcard + one report type):

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File C:\monthlyReporting\main.ps1 -vCenter iaas -reportType Machines
```

## Main parameters (`main.ps1`)

- `-vCenter`: server wildcard (for matching credential files)
- `-reportType`: one of `Datastores`, `Hosts`, `Machines`, `Networks`, `Templates`, `Admin`
- `-onlySend`: only send today's generated files
- `-onlyTidy`: only run cleanup
- `-dontSend`: skip sending emails
- `-dontTidy`: skip cleanup

## Configuration (`configuration.ini`)

Update at least:
- `[Install] installPath`
- `[Mail] server`, `[Mail] from`
- Recipient sections (`[Recipient-*]`)
- Credentials XML files under `Creds/`

## How to add a new `reportType`

Use this checklist so a new team member can implement a new report type safely.

### 1) Create a new fetch script

Create a file like `fetch<MyType>.ps1`:
- Load `commonFunctions.ps1`
- Read `configuration.ini`
- Collect rows into objects/arrays
- Export to CSV with `Export-Csv -NoTypeInformation` (no delimiter override)
- Optionally write a summary `.txt`

### 2) Register the new type in `main.ps1`

In the `SWITCH( $reportType )` block:
- Add a new case (example: `"StorageAudit"`)
- Set a dedicated boolean for your new type
- Ensure other booleans are set correctly

In the execution section:
- Add an invocation line like:

```powershell
IF( $storageAudit ) { .\fetchStorageAudit.ps1 }
```

### 3) (Optional but recommended) Register script in `configuration.ini`

In `[Scripts]`, add a key for the new script file. This keeps script mapping explicit.

### 4) Include it in mail sending (`sendReports.ps1`)

If the report should be emailed:
- Add body text describing attachment(s)
- Build an attachment filter array (e.g. by file name prefix)
- Add a recipient group in `configuration.ini` (for example `[Recipient-StorageAudit]`)
- Add a `Send-MailMessage` block for that recipient group

### 5) Validate end-to-end

- Run only the new type first:

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File C:\monthlyReporting\main.ps1 -reportType StorageAudit -dontSend
```

- Confirm CSV files are created in `Reports\<yyyy-mm-dd>`
- Run send path and verify expected recipients + attachments
- Re-run cleanup and verify retention behavior is unchanged

## Notes

- CSV export currently uses `Export-Csv -NoTypeInformation` consistently.
- Keep report file naming patterns stable; `sendReports.ps1` uses wildcard attachment selection.
