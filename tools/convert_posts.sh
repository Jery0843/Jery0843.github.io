#!/usr/bin/env bash
# convert_posts.sh — Fetch writeups from private GitHub repo and convert to Chirpy posts
# Usage: ./tools/convert_posts.sh [GITHUB_PAT]
# If no PAT is provided, it will try to use the GH_TOKEN environment variable.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
POSTS_DIR="$PROJECT_DIR/_posts"
TEMP_DIR="$PROJECT_DIR/.tmp-htb"

REPO_OWNER="Jery0843"
REPO_NAME="HTB"
BRANCH="main"
API_BASE="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME"

# Resolve GitHub PAT
PAT="${1:-${GH_TOKEN:-}}"
if [ -z "$PAT" ]; then
  echo "❌ Error: GitHub Personal Access Token required."
  echo "   Usage: ./tools/convert_posts.sh <GITHUB_PAT>"
  echo "   Or set GH_TOKEN environment variable."
  exit 1
fi

AUTH_HEADER="Authorization: token $PAT"

mkdir -p "$POSTS_DIR"
mkdir -p "$TEMP_DIR"

echo "🔄 Fetching file list from $REPO_OWNER/$REPO_NAME..."

# Get list of .md files from the repo (excluding README.md)
FILES_JSON=$(curl -s -H "$AUTH_HEADER" \
  -H "Accept: application/vnd.github.v3+json" \
  "$API_BASE/contents/?ref=$BRANCH")

# Check for API errors
if echo "$FILES_JSON" | grep -q '"message"'; then
  echo "❌ GitHub API error:"
  echo "$FILES_JSON" | grep '"message"' | head -1
  exit 1
fi

# Extract .md filenames (excluding README.md)
MD_FILES=$(echo "$FILES_JSON" | grep -oP '"name":\s*"\K[^"]+\.md' | grep -vi 'readme')

if [ -z "$MD_FILES" ]; then
  echo "⚠️  No markdown files found in the repo."
  exit 0
fi

FILE_COUNT=$(echo "$MD_FILES" | wc -l)
echo "📝 Found $FILE_COUNT writeup(s). Processing..."

PROCESSED=0
SKIPPED=0

for FILENAME in $MD_FILES; do
  MACHINE_NAME="${FILENAME%.md}"
  SLUG=$(echo "$MACHINE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

  echo "  → Processing: $MACHINE_NAME"

  # Get the last commit date for this file
  COMMIT_JSON=$(curl -s -H "$AUTH_HEADER" \
    -H "Accept: application/vnd.github.v3+json" \
    "$API_BASE/commits?path=$FILENAME&sha=$BRANCH&per_page=1")

  COMMIT_DATE=$(echo "$COMMIT_JSON" | grep -oP '"date":\s*"\K[^"]+' | head -1)

  if [ -z "$COMMIT_DATE" ]; then
    echo "    ⚠️  Could not get commit date, using today's date"
    COMMIT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  fi

  # Format date for filename (YYYY-MM-DD)
  POST_DATE=$(echo "$COMMIT_DATE" | cut -c1-10)
  POST_FILE="$POSTS_DIR/${POST_DATE}-${SLUG}.md"

  # Download the raw content
  RAW_CONTENT=$(curl -s -H "$AUTH_HEADER" \
    -H "Accept: application/vnd.github.v3.raw" \
    "$API_BASE/contents/$FILENAME?ref=$BRANCH")

  # Save raw content to temp for hash comparison
  TEMP_FILE="$TEMP_DIR/$FILENAME"
  echo "$RAW_CONTENT" > "$TEMP_FILE.new"

  # Check if content has changed (skip if identical)
  if [ -f "$TEMP_FILE" ] && diff -q "$TEMP_FILE" "$TEMP_FILE.new" > /dev/null 2>&1; then
    echo "    ⏭️  No changes, skipping"
    rm "$TEMP_FILE.new"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  mv "$TEMP_FILE.new" "$TEMP_FILE"

  # --- TRUNCATION LOGIC ---
  # 3-tier strategy to find where the free (recon) content ends:
  #   PRIMARY:    Ask Grok AI to identify the cutoff line
  #   FALLBACK 1: Keyword-based header matching
  #   FALLBACK 2: Fixed 30-line preview

  CUTOFF_LINE=""
  TOTAL_LINES=$(echo "$RAW_CONTENT" | wc -l)

  # ═══ PRIMARY: Groq Llama 70B → fallback to Llama 8B ═══
  if [ -n "${GROQ_API_KEY:-}" ]; then
    # Send only numbered headers to save tokens
    HEADERS_WITH_LINES=$(echo "$RAW_CONTENT" | grep -n '^#' || true)

    # Build the prompt
    AI_PROMPT="You are analyzing a HackTheBox writeup for a paywall cutoff. Given the numbered headers below, return ONLY the line number where the FREE PREVIEW should end. The free preview should ONLY show: basic port scanning, nmap results, service version detection, host configuration, and basic web page discovery (what the site looks like). It must NOT include ANY of the following — cut BEFORE any of these: username enumeration, LDAP injection, SQL injection, command injection, type juggling, brute force, hash cracking, credential discovery, password leaks, exploitation, initial access, foothold, reverse shell, source code analysis, vulnerability identification, CVE exploitation, privilege escalation, flag capture, sensitive findings, tokens, secrets, SSRF, XSS, file inclusion, deserialization, or any offensive technique beyond basic scanning. Be strict — when in doubt, cut earlier.\n\nHeaders:\n${HEADERS_WITH_LINES}\n\nRespond with ONLY a number (the line number to cut at). Nothing else."

    # Escape the prompt for JSON
    AI_JSON_PROMPT=$(echo "$AI_PROMPT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || true)

    if [ -n "$AI_JSON_PROMPT" ]; then
      # Try Llama 70B first, then 8B
      for MODEL in "llama-3.3-70b-versatile" "llama-3.1-8b-instant"; do
        echo "    🤖 Trying Groq $MODEL..."

        AI_RESPONSE=$(curl -s --max-time 20 \
          -H "Authorization: Bearer ${GROQ_API_KEY}" \
          -H "Content-Type: application/json" \
          -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":${AI_JSON_PROMPT}}],\"temperature\":0,\"max_tokens\":10}" \
          "https://api.groq.com/openai/v1/chat/completions" 2>/dev/null || true)

        if [ -n "$AI_RESPONSE" ]; then
          # Check for API errors
          API_ERROR=$(echo "$AI_RESPONSE" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    if "error" in data:
        print(data["error"].get("message", "unknown error"))
except:
    pass
' 2>/dev/null || true)

          if [ -n "$API_ERROR" ]; then
            echo "    ⚠️  $MODEL error: $API_ERROR"
            continue
          fi

          # Extract the line number
          AI_LINE=$(echo "$AI_RESPONSE" | python3 -c '
import sys, json, re
try:
    data = json.load(sys.stdin)
    text = data["choices"][0]["message"]["content"].strip()
    match = re.search(r"\d+", text)
    if match:
        print(match.group())
except:
    pass
' 2>/dev/null || true)

          if [ -n "$AI_LINE" ] && [ "$AI_LINE" -gt 5 ] 2>/dev/null && [ "$AI_LINE" -lt "$TOTAL_LINES" ] 2>/dev/null; then
            CUTOFF_LINE="$AI_LINE"
            echo "    ✅ $MODEL says: cut at line $CUTOFF_LINE"
            break
          else
            echo "    ⚠️  $MODEL returned invalid line: '$AI_LINE'"
          fi
        else
          echo "    ⚠️  $MODEL returned no response"
        fi
      done
    fi
  else
    echo "    ℹ️  No GROQ_API_KEY set, skipping AI analysis"
  fi

  # ═══ FALLBACK 1: Keyword-based header matching ═══
  if [ -z "$CUTOFF_LINE" ]; then
    PAID_KEYWORDS="initial access|exploitation|exploit chain|weaponiz|payload|foothold|gaining access|reverse shell|rce|remote code|privilege escalation|privesc|lateral movement|code execution|sandbox escape|authentication bypass|hash crack|username enumerat|ldap injection|sql injection|command injection|brute.force|type juggling|ssrf|xss|file inclusion|deserializ|credential"

    CUTOFF_LINE=$(echo "$RAW_CONTENT" | grep -inE "^##\s+.*(${PAID_KEYWORDS})" | head -1 | cut -d: -f1 || true)

    if [ -n "$CUTOFF_LINE" ] && [ "$CUTOFF_LINE" -gt 5 ]; then
      echo "    🔑 Keyword fallback: cut at line $CUTOFF_LINE"
    else
      CUTOFF_LINE=""
    fi
  fi

  # ═══ FALLBACK 2: Fixed 30-line preview ═══
  if [ -z "$CUTOFF_LINE" ]; then
    CUTOFF_LINE=31
    echo "    📏 Fixed fallback: using first 30 lines"
  fi

  # Apply the cutoff
  FREE_CONTENT=$(echo "$RAW_CONTENT" | head -n $((CUTOFF_LINE - 1)))
  echo "    🔒 Preview: $((CUTOFF_LINE - 1)) of $TOTAL_LINES lines"

  # Remove the first H1 line (it becomes the post title in front matter)
  TITLE_LINE=$(echo "$RAW_CONTENT" | grep -n '^# ' | head -1 | cut -d: -f1 || true)
  if [ -n "$TITLE_LINE" ]; then
    # Also remove the intro paragraph right after the H1 title (if it exists before the first ---)
    FIRST_HR=$(echo "$FREE_CONTENT" | grep -n '^---$' | head -1 | cut -d: -f1 || true)
    if [ -n "$FIRST_HR" ] && [ "$FIRST_HR" -gt "$TITLE_LINE" ]; then
      FREE_CONTENT=$(echo "$FREE_CONTENT" | tail -n +"$FIRST_HR")
    else
      FREE_CONTENT=$(echo "$FREE_CONTENT" | tail -n +"$((TITLE_LINE + 1))")
    fi
  fi

  # Build the post file with Chirpy front matter
  cat > "$POST_FILE" <<EOF
---
title: "$MACHINE_NAME"
date: $COMMIT_DATE
categories: [HackTheBox, Writeup]
tags: [htb, hackthebox, writeup, pentest, $SLUG]
description: "HackTheBox $MACHINE_NAME machine writeup — reconnaissance and enumeration walkthrough."
toc: true
comments: true
---

$FREE_CONTENT

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
EOF

  PROCESSED=$((PROCESSED + 1))
  echo "    ✅ Created: $POST_FILE"
done

echo ""
echo "🎉 Done! Processed: $PROCESSED | Skipped: $SKIPPED | Total: $FILE_COUNT"
