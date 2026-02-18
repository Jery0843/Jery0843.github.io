#!/usr/bin/env bash
# convert_posts.sh — Fetch writeups from private GitHub repo and convert to Chirpy posts
# Usage: ./tools/convert_posts.sh [GITHUB_PAT]
# If no PAT is provided, it will try to use the GH_TOKEN environment variable.

set -euo pipefail

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
  # Extract only the free content (up to reconnaissance/enumeration).
  # We search for headers (## or ###) containing keywords that indicate
  # the START of the paid section (exploitation, initial access, etc.).
  # Headers can be numbered (## 3. Initial Access) or plain (## Initial Access).

  FREE_CONTENT=""
  CUTOFF_LINE=""

  # Keywords that indicate the end of the free (recon) section.
  # These match against ## or ### headers, case-insensitive.
  # Order matters — we take the FIRST match.
  PAYWALL_KEYWORDS="initial access|exploitation|exploit|foothold|gaining access|shell|reverse shell|post.exploitation|post exploitation|privilege escalation|privesc|priv esc|lateral movement|flag"

  # Find the first ## or ### header that contains any paywall keyword
  CUTOFF_LINE=$(echo "$RAW_CONTENT" | grep -inE "^\s*#{2,3}\s+.*(${PAYWALL_KEYWORDS})" | head -1 | cut -d: -f1)

  # Fallback: try numbered section 3 (## 3. or ## 3 )
  if [ -z "$CUTOFF_LINE" ]; then
    CUTOFF_LINE=$(echo "$RAW_CONTENT" | grep -n '^\s*##\s*3[.\s ]' | head -1 | cut -d: -f1)
  fi

  if [ -n "$CUTOFF_LINE" ] && [ "$CUTOFF_LINE" -gt 1 ]; then
    # Take everything before the paywall cutoff header
    FREE_CONTENT=$(echo "$RAW_CONTENT" | head -n $((CUTOFF_LINE - 1)))
    echo "    🔒 Paywall cutoff at line $CUTOFF_LINE"
  else
    # Final fallback: take the first 30 lines
    FREE_CONTENT=$(echo "$RAW_CONTENT" | head -n 30)
    echo "    ⚠️  No keyword match found, using first 30 lines"
  fi

  # Remove the first H1 line (it becomes the post title in front matter)
  TITLE_LINE=$(echo "$RAW_CONTENT" | grep -n '^# ' | head -1 | cut -d: -f1)
  if [ -n "$TITLE_LINE" ]; then
    # Also remove the intro paragraph right after the H1 title (if it exists before the first ---)
    FIRST_HR=$(echo "$FREE_CONTENT" | grep -n '^---$' | head -1 | cut -d: -f1)
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
