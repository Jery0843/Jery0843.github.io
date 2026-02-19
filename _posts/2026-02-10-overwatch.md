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
