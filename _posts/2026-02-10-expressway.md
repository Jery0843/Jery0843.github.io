---
title: "Expressway"
date: 2026-02-10T17:00:01Z
categories: [HackTheBox, Writeup]
tags: [htb, hackthebox, writeup, pentest, expressway]
description: "HackTheBox Expressway machine writeup — reconnaissance and enumeration walkthrough."
toc: true
comments: true
---

---

## Chapter 1: Recon — Listening for Opportunity

### The Opening Scene
Imagine the network as a vast, silent street—shrouded in shadows. My first step: turn on the headlights and see what’s out there.

### TCP Scan — First Pass, False Comfort
```bash
nmap -p- -T4 -sS 10.10.11.87 -oN initial_tcp_scan.txt
```
SSH (port 22) greets me and then slams the door in my face. No welcome mat here. The box seems as silent as a ghost. Seasoned hackers know—if you only look for doors, you might miss the windows.

### The UDP Angle — Where All the Clues Hide
```bash
sudo nmap -sU 10.10.11.87 --min-rate 5000
```
Port 500 lights up. IPsec/IKE. VPN land: hostile territory for most, but a playground for those who know the rules.

---

## Chapter 2: The VPN Enigma

### Aggressive Negotiations
IKE is like the bouncer at the Expressway nightclub—it checks IDs and sometimes lets a little info slip during “aggressive mode.” I deploy the toolkit:

```bash
sudo apt install ike-scan
sudo ike-scan -A 10.10.11.87
```

**"Aggressive Mode"** leaks something precious — a user ID: `ike@expressway.htb`. In this city, names are keys.

### Cracking the Vault — Snatching the Pre-Shared Key
I provoke the handshake to spill its hashed secrets:

```bash
sudo ike-scan -A 10.10.11.87 --id=ike@expressway.htb -Pike.psk
```

The file `ike.psk` contains the hashed PSK. I bring in heavy artillery: `psk-crack`.

```bash
psk-crack -d /usr/share/wordlists/rockyou.txt ike.psk
```

And in the wordlist, in classic CTF fashion, the passphrase **freakingrockstarontheroad** emerges. Weak credentials — the box builder’s favorite lesson. Never reuse your club’s master key as your personal password.

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
