---
title: "Global-Hyperlink-Zone"
date: 2026-02-10T17:00:01Z
categories: [HackTheBox, Writeup]
tags: [htb, hackthebox, writeup, pentest, global-hyperlink-zone]
description: "HackTheBox Global-Hyperlink-Zone machine writeup — reconnaissance and enumeration walkthrough."
toc: true
comments: true
---

---

## Challenge Overview

The Global Hyperlink Zone is a quantum computing challenge that simulates a 5-qubit quantum circuit over multiple measurement shots. The challenge server reads gate instructions, builds and executes the circuit, then verifies if the measurement results satisfy a specific pattern. Understanding quantum gates and their behavior is essential to craft the correct payload and retrieve the flag.

### What Makes This Challenge Interesting

This challenge elegantly combines three concepts:
1. **Quantum Gate Operations** - understanding how H (Hadamard) and CX (CNOT) gates transform qubit states
2. **Measurement & Probabilistic Outcomes** - how repeated measurements create bit-strings (shares)
3. **Constraint Satisfaction** - satisfying three specific equality/inequality conditions simultaneously

---

## Understanding the Challenge Mechanics

### The Server's Workflow

The Global Hyperlink Zone service operates in the following sequence:

1. **Accept Instructions** - The server prompts for a gate instruction string formatted as `GATE:QUBIT[,QUBIT];GATE:QUBIT[,QUBIT];...`
2. **Build Circuit** - Constructs a 5-qubit quantum circuit and applies gates in the specified order
3. **Execute & Measure** - Runs the circuit for many shots (measurement iterations) and records outcomes
4. **Extract Shares** - For each qubit (0-4), concatenates all measured bits into a binary string called a "share"
5. **Validate Constraints** - Checks three conditions:
   - `share0 == share1 == share3` (three qubits must have identical measurement patterns)
   - `share2 == share4` (two qubits must have identical measurement patterns)
   - `share2/4 != share0/1/3` (the two groups must differ)
6. **Return Flag** - If all conditions pass, outputs the flag from `flag.txt`

### The Constraint Pattern Visualized

```
Required Pattern:
┌─────────────────────────┐
│  Qubits: 0, 1, 3        │  ← Must all be identical (Group A)
│  Pattern: share0        │
└─────────────────────────┘
            ≠
┌─────────────────────────┐
│  Qubits: 2, 4          │  ← Must all be identical (Group B)
│  Pattern: share2        │
└─────────────────────────┘
```

---

## Quantum Gate Fundamentals

### The Hadamard (H) Gate

The Hadamard gate is the quantum equivalent of flipping a fair coin:

- **Initial State:** Qubit starts at |0⟩
- **Operation:** Places the qubit in superposition
- **Measurement Result:** 50% chance of measuring 0, 50% chance of measuring 1
- **Across Multiple Shots:** Produces a random bit-string where each bit is independently 0 or 1

**Key Insight:** Two independently applied H gates on different qubits will produce almost completely different bit-strings across many measurements.

### The CNOT (CX) Gate

The CNOT gate is a controlled operation:

- **Parameters:** Requires a control qubit and target qubit (e.g., `CX:0,1`)
- **Operation:** Flips the target qubit's state only if control qubit is 1
- **Practical Effect:** Copies the measured bit from control to target across all shots
- **Constraint:** Target qubit should start in |0⟩ state for predictable copying

**Key Insight:** Applying `CX:0,1` means every time qubit 0 measures as 0, qubit 1 will measure as 0; every time qubit 0 measures as 1, qubit 1 will also measure as 1.

---

## Exploit Strategy & Analysis

### The Core Idea

The exploit leverages the deterministic copying behavior of CNOT gates combined with the randomness of Hadamard gates:

1. **Create Independent Random Sources** - Use two separate Hadamard gates on two different qubits to generate two statistically independent random bit-strings
2. **Copy Within Groups** - Use CNOT gates to distribute one random source to multiple target qubits and the other random source to additional targets
3. **Guarantee Differences** - Since the two Hadamard gates operate independently, their resulting bit-strings will differ with extremely high probability (approaching certainty)

### Step-by-Step Breakdown

| Step | Gate | Target(s) | Effect |
|------|------|-----------|--------|
| 1 | H:0 | Qubit 0 | Qubit 0 becomes random (0 or 1 per shot) |
| 2 | CX:0,1 | Qubit 1 | Qubit 1 copies Qubit 0's measurements |
| 3 | CX:0,3 | Qubit 3 | Qubit 3 copies Qubit 0's measurements |
| 4 | H:2 | Qubit 2 | Qubit 2 becomes random (independent source) |
| 5 | CX:2,4 | Qubit 4 | Qubit 4 copies Qubit 2's measurements |

### Verification

After circuit execution:
- **share0** = random bits from qubit 0 → e.g., `1011010110...`
- **share1** = copied from qubit 0 → identical: `1011010110...`
- **share3** = copied from qubit 0 → identical: `1011010110...`
- **share2** = random bits from qubit 2 → different: `0101101001...`
- **share4** = copied from qubit 2 → identical: `0101101001...`

**Condition Check:**
- ✓ share0 == share1 == share3 (all from same source)
- ✓ share2 == share4 (both from independent source)
- ✓ share0/1/3 != share2/4 (independent random sources almost certainly differ)
- ✓ **All conditions satisfied → Flag retrieved!**

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
