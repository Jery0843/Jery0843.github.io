---
title: "MonitorsFour"
date: 2026-02-10T17:00:01Z
categories: [HackTheBox, Writeup]
tags: [htb, hackthebox, writeup, pentest, monitorsfour]
description: "HackTheBox MonitorsFour machine writeup — reconnaissance and enumeration walkthrough."
toc: true
comments: true
---


MonitorsFour is a Windows-based HackTheBox machine that demonstrates a multi-stage attack chain combining web application vulnerabilities, authentication bypass through PHP type juggling, CVE exploitation, and Docker API abuse for privilege escalation. This writeup details the complete exploitation process from initial reconnaissance to root access.

## Environment Configuration

Configure DNS resolution for the target domain:

```bash
echo "10.10.11.98 monitorsfour.htb cacti.monitorsfour.htb" | sudo tee -a /etc/hosts
```

**Target:** 10.10.11.98  
**Attacker:** 10.10.14.143

## Reconnaissance & Information Gathering

### Network Enumeration

Initial port scanning reveals the attack surface:

```bash
nmap -A -O 10.10.11.98
```

**Open Ports:**
- 80/tcp: nginx HTTP service redirecting to monitorsfour.htb
- 5985/tcp: WinRM (Microsoft HTTPAPI httpd 2.0)

**Operating System:** Windows Server (2022/2012/2016)

### Virtual Host Discovery

Enumerate subdomains using ffuf with virtual host fuzzing:

```bash
ffuf -t 400 -w /usr/share/seclists/Discovery/DNS/combined_subdomains.txt \
  -u http://monitorsfour.htb \
  -H "Host: FUZZ.monitorsfour.htb" -ac
```

**Discovered:** cacti.monitorsfour.htb (Status: 302)

### Web Directory Enumeration

Scan for hidden directories and files:

```bash
ffuf -t 400 -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories-lowercase.txt \
  -u http://monitorsfour.htb/FUZZ -ac
```

**Critical Findings:**
- /views - Status 301
- /symposium - Status 200
- /logis - Status 200
- /videofiles - Status 200

**Note:** The scan encountered numerous timeout errors, indicating rate limiting or network instability. Reducing thread count (-t 100) improves reliability.

### Configuration File Discovery

Standard web application file scanning reveals sensitive data:

```bash
dirsearch -u http://monitorsfour.htb/ -x 404
```

**Critical Discovery:** /.env file exposed containing database credentials

```bash
curl http://monitorsfour.htb/.env
```

**Leaked Credentials:**

```
DB_HOST=mariadb
DB_PORT=3306
DB_NAME=monitorsfour_db
DB_USER=monitorsdbuser
DB_PASS=f37p2j8f4t0r
```

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
