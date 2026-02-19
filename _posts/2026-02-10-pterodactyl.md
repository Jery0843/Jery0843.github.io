---
title: "Pterodactyl"
date: 2026-02-10T17:00:01Z
categories: [HackTheBox, Writeup]
tags: [htb, hackthebox, writeup, pentest, pterodactyl]
description: "HackTheBox Pterodactyl machine writeup — reconnaissance and enumeration walkthrough."
toc: true
comments: true
---

---

## Reconnaissance & Enumeration

### Host Configuration

First, we add the target to our hosts file for proper name resolution:

```bash
echo "10.129.5.168 pterodactyl.htb panel.pterodactyl.htb" | sudo tee -a /etc/hosts
```

### Subdomain Discovery

Using `ffuf` to brute-force virtual hosts:

```bash
ffuf -w /usr/share/wordlists/seclists/Discovery/Web-Content/big.txt \
-u http://pterodactyl.htb/ \
-H "Host: FUZZ.pterodactyl.htb" -fw
```

**Discovery:** `panel.pterodactyl.htb`

This subdomain hosts the Pterodactyl Panel application - a popular game server management platform built on Laravel (PHP framework).

### Vulnerability Identification

Checking for PHP configuration disclosure:

```bash
curl http://panel.pterodactyl.htb/phpinfo.php
```

**Key Finding:** PEAR (PHP Extension and Application Repository) is enabled with writable configuration paths.

---

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
