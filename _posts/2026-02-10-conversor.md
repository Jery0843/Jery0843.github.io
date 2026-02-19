---
title: "Conversor"
date: 2026-02-10T17:00:01Z
categories: [HackTheBox, Writeup]
tags: [htb, hackthebox, writeup, pentest, conversor]
description: "HackTheBox Conversor machine writeup — reconnaissance and enumeration walkthrough."
toc: true
comments: true
---


## Phase 1: Initial Reconnaissance

### Step 1.1: Port Scanning

Open your terminal and execute:

```bash
sudo nmap -sC -sV <TARGET_IP> -oN nmap_scan.txt
```

**Expected Output:**
```
Starting Nmap 7.95 ( https://nmap.org )
Nmap scan report for <TARGET_IP>
Host is up (0.21s latency).
Not shown: 998 closed tcp ports (reset)
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 8.9p1 Ubuntu 3ubuntu0.13 (Ubuntu Linux; protocol 2.0)
80/tcp open  http    Apache httpd 2.4.52
|_http-title: Did not follow redirect to http://conversor.htb/
Service Info: Host: conversor.htb; OS: Linux
```

### Step 1.2: Configure DNS Resolution

The scan reveals a hostname `conversor.htb`. Add it to your hosts file:

```bash
echo "<TARGET_IP> conversor.htb" | sudo tee -a /etc/hosts
```

Verify it's added:
```bash
tail -n 1 /etc/hosts
```

**Expected Output:**
```
<TARGET_IP> conversor.htb
```

***

## Phase 2: Web Application Discovery

### Step 2.1: Access the Web Application

Open your browser and navigate to:
```
http://conversor.htb
```

**What You'll See:** You'll be redirected to a login page at `http://conversor.htb/login`

### Step 2.2: Directory Enumeration

In your terminal, run:

```bash
gobuster dir -u http://conversor.htb -w /usr/share/seclists/Discovery/Web-Content/raft-small-words.txt -o gobuster_results.txt
```

**Expected Output:**
```
===============================================================
/login                (Status: 200) [Size: 722]
/register             (Status: 200) [Size: 726]
/logout               (Status: 302) [Size: 199] [--> /login]
/about                (Status: 200) [Size: 2842]
/javascript           (Status: 301) [Size: 319]
/.                    (Status: 302) [Size: 199] [--> /login]
/convert              (Status: 405) [Size: 153]
===============================================================
```

### Step 2.3: Register User Account

**In Browser:**

1. Navigate to: `http://conversor.htb/register`
2. **Fill in registration form:**
   - Username: `testuser` (or any username you prefer)
   - Password: `Test123!` (or any password you prefer)
3. Click **"Register"** button
4. You'll be redirected to the login page

### Step 2.4: Login to Application

**In Browser:**

1. Navigate to: `http://conversor.htb/login`
2. **Enter credentials:**
   - Username: `testuser`
   - Password: `Test123!`
3. Click **"Login"** button
4. You'll be taken to the main converter page

**What You'll See:** A page with the title "XML to HTML Converter" with two file upload fields:
- **XML File Upload** field
- **XSLT File Upload** field
- A **"Convert"** button

### Step 2.5: Download Source Code

**In Browser:**

1. Navigate to: `http://conversor.htb/about`
2. Scroll down until you see a link labeled **"Download Source Code"** or similar
3. Click the download link to download `source_code.tar.gz`

**In Terminal:**

```bash
# Create working directory
mkdir -p ~/htb/conversor
cd ~/htb/conversor

# If downloaded via browser, move it
mv ~/Downloads/source_code.tar.gz .

# Extract source code
mkdir src
tar -xvf source_code.tar.gz -C src/
```

**Expected Output:**
```
instance/
instance/users.db
app.py
templates/
templates/login.html
templates/register.html
templates/convert.html
install.md
requirements.txt
```

### Step 2.6: Analyze Source Code

```bash
cd src

# View the critical installation documentation
cat install.md
```

**Key Finding in install.md:**
```
If you want to run Python scripts (for example, our server deletes all files 
older than 60 minutes to avoid system overload), you can add the following 
line to your /etc/crontab:

* * * * * www-data for f in /var/www/conversor.htb/scripts/*.py; do python3 "$f"; done
```

**CRITICAL:** This reveals the server executes ALL `.py` files in `/var/www/conversor.htb/scripts/` every minute as `www-data` user.[9][10]

***

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
