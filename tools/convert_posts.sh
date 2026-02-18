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
  # Show only recon/enumeration content. Cut at the FIRST section that
  # moves beyond recon. The writeups use many different header formats:
  #   Numbered:  ## 2. Initial Access  |  ## 3. Exploitation
  #   Phased:    ## Phase 2: MSSQL Exploitation
  #   Chapters:  ## Chapter 3: First Foothold
  #   Acts:      ## Act II: The OAuth Heist  |  ## 🎬 Act 2
  #   Sections:  ## SECTION 2 - LEAKED REPO CREDENTIALS
  #   Escaped:   ## 2\. Crafting Your Profile
  #   Plain:     ## SQL Server Exploitation
  #
  # STRATEGY:
  #   1. Find the 2nd top-level ## header (skip ### sub-headers).
  #      Most writeups put all recon in the 1st ## section.
  #   2. If the 1st ## header itself is an exploit keyword, use fallback.
  #   3. Override: if a keyword match comes BEFORE the 2nd ##, use that.
  #   4. Fallback: first 30 lines.

  FREE_CONTENT=""
  CUTOFF_LINE=""

  # Get all top-level ## headers (not ### or deeper), with line numbers
  ALL_H2=$(echo "$RAW_CONTENT" | grep -n '^## ' || true)

  # Count how many ## headers exist
  H2_COUNT=$(echo "$ALL_H2" | grep -c '.' || true)

  # Keyword patterns that ALWAYS indicate paid content
  PAID_KEYWORDS="initial access|exploitation|exploit chain|weaponiz|payload|foothold|first foothold|gaining access|reverse shell|rce|remote code|post.exploitation|post exploitation|privilege escalation|privesc|priv esc|lateral movement|user flag|root flag|credential|code execution|sandbox escape|authentication bypass|the oauth|the heist|sql server exploitation|hash crack|impersonat"

  # Strategy 1: Keyword match on ## headers only (not ### to avoid false positives)
  KEYWORD_LINE=$(echo "$RAW_CONTENT" | grep -inE "^##\s+.*(${PAID_KEYWORDS})" | head -1 | cut -d: -f1 || true)

  # Strategy 2: Find the 2nd ## header (first section = free, rest = paid)
  SECOND_H2=""
  if [ "$H2_COUNT" -ge 2 ]; then
    SECOND_H2=$(echo "$ALL_H2" | sed -n '2p' | cut -d: -f1 || true)
  fi

  # Pick the EARLIEST cutoff between keyword match and 2nd section
  if [ -n "$KEYWORD_LINE" ] && [ -n "$SECOND_H2" ]; then
    if [ "$KEYWORD_LINE" -le "$SECOND_H2" ]; then
      CUTOFF_LINE="$KEYWORD_LINE"
    else
      CUTOFF_LINE="$SECOND_H2"
    fi
  elif [ -n "$KEYWORD_LINE" ]; then
    CUTOFF_LINE="$KEYWORD_LINE"
  elif [ -n "$SECOND_H2" ]; then
    CUTOFF_LINE="$SECOND_H2"
  fi

  # Safety: if cutoff is too early (< 8 lines), it's probably wrong — use 2nd H2 or fallback
  if [ -n "$CUTOFF_LINE" ] && [ "$CUTOFF_LINE" -lt 8 ]; then
    if [ -n "$SECOND_H2" ] && [ "$SECOND_H2" -ge 8 ]; then
      CUTOFF_LINE="$SECOND_H2"
    else
      CUTOFF_LINE=""
    fi
  fi

  if [ -n "$CUTOFF_LINE" ] && [ "$CUTOFF_LINE" -gt 1 ]; then
    FREE_CONTENT=$(echo "$RAW_CONTENT" | head -n $((CUTOFF_LINE - 1)))
    echo "    🔒 Paywall cutoff at line $CUTOFF_LINE"
  else
    FREE_CONTENT=$(echo "$RAW_CONTENT" | head -n 30)
    echo "    ⚠️  No section match found, using first 30 lines"
  fi

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
