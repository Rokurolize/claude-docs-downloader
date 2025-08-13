#!/bin/bash

# Claude Code Documentation Downloader - Standalone Version
# Automatically downloads Claude Code documentation from Anthropic's official docs
# Author: Claude Code Assistant
# Version: Standalone 1.0

set -euo pipefail

readonly DOCS_BASE_URL="https://docs.anthropic.com"
readonly OVERVIEW_URL="$DOCS_BASE_URL/en/docs/claude-code/overview"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TARGET_DIR="$SCRIPT_DIR/claude-code-docs"
readonly MAX_FILE_SIZE=$((5 * 1024 * 1024))  # 5MB limit
readonly CURL_TIMEOUT=30

# Colors (only if stdout is a terminal)
if [[ -t 1 ]]; then
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly RED='\033[0;31m'
    readonly NC='\033[0m'
else
    readonly GREEN='' YELLOW='' RED='' NC=''
fi

# Global variables (initialized in main)
TEMP_DIR=""
LOG_FILE=""
REPORT_FILE=""

cleanup() {
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
}

cleanup_keep() {
    echo "Temporary files kept in: $TEMP_DIR" >&2
}

die() {
    echo -e "${RED}✗${NC} $1" >&2
    exit 1
}

log() {
    echo -e "${GREEN}✓${NC} $1" >&2
    [[ -n "$LOG_FILE" ]] && echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1" >&2
    [[ -n "$LOG_FILE" ]] && echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}✗${NC} $1" >&2
    [[ -n "$LOG_FILE" ]] && echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $1" >> "$LOG_FILE"
}

validate_url() {
    local url="$1"
    # Allow alphanumeric, dots, hyphens, underscores, slashes in path
    # Must start with expected base path
    if [[ ! "$url" =~ ^/en/docs/claude-code/[a-zA-Z0-9._/-]+$ ]]; then
        error "Invalid URL detected: $url"
        return 1
    fi
    return 0
}

check_dependencies() {
    local missing_deps=()
    
    # Check command existence
    for cmd in curl grep sed diff wc; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    [[ ${#missing_deps[@]} -gt 0 ]] && die "Missing required commands: ${missing_deps[*]}"
    
    # Test curl HTTPS capability
    curl --version | grep -q "https" || die "curl does not support HTTPS"
    
    # Test basic connectivity
    curl -s --head --max-time 10 "$OVERVIEW_URL" >/dev/null || die "Cannot connect to $OVERVIEW_URL"
}

discover_urls() {
    local temp_overview="$TEMP_DIR/overview.html"
    local urls_file="$TEMP_DIR/claude_code_urls.txt"
    
    echo "Discovering documentation URLs..." >&2
    
    # Download overview page with error capture
    if ! curl -s -f --max-time "$CURL_TIMEOUT" -o "$temp_overview" "$OVERVIEW_URL" 2>"$TEMP_DIR/curl_error.log"; then
        error "Failed to download overview page:"
        cat "$TEMP_DIR/curl_error.log" >&2
        return 1
    fi
    
    log "Downloaded overview page"
    
    # Extract URLs
    if ! grep -o 'href="/en/docs/claude-code/[^"]*"' "$temp_overview" | \
         sed 's/href="//g; s/"//g' | \
         grep -v "#" | \
         sort | uniq > "$urls_file"; then
        error "Failed to extract URLs from overview page"
        return 1
    fi
    
    # Validate URLs and count valid ones
    local valid_count=0
    local temp_valid="$TEMP_DIR/valid_urls.txt"
    : > "$temp_valid"
    
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        if validate_url "$url"; then
            echo "$url" >> "$temp_valid"
            ((valid_count++))
        else
            warn "Skipping invalid URL: $url"
        fi
    done < "$urls_file"
    
    [[ $valid_count -eq 0 ]] && { error "No valid URLs discovered"; return 1; }
    
    mv "$temp_valid" "$urls_file"
    log "Discovered $valid_count valid documentation URLs"
    echo "$urls_file"
}

download_file() {
    local url_path="$1"
    local filename="$(basename "$url_path").md"
    local full_url="${DOCS_BASE_URL}${url_path}.md"
    local target_file="$TARGET_DIR/$filename"
    local temp_file="$TEMP_DIR/downloaded_$filename"
    
    echo "  Processing: $filename" >&2
    
    # Download with error logging
    if ! curl -s -f --max-time "$CURL_TIMEOUT" -o "$temp_file" "$full_url" 2>"$TEMP_DIR/curl_${filename}.log"; then
        error "Failed to download $filename:"
        cat "$TEMP_DIR/curl_${filename}.log" >&2
        echo "FAILED $filename" >> "$REPORT_FILE"
        return 1
    fi
    
    # Validate downloaded content
    if [[ ! -s "$temp_file" ]]; then
        error "Downloaded empty file: $filename"
        echo "FAILED $filename" >> "$REPORT_FILE"
        return 1
    fi
    
    local file_size
    file_size=$(wc -c < "$temp_file")
    if [[ $file_size -gt $MAX_FILE_SIZE ]]; then
        error "File too large: $filename ($file_size bytes)"
        echo "FAILED $filename" >> "$REPORT_FILE"
        return 1
    fi
    
    # Basic markdown validation
    if ! head -1 "$temp_file" | grep -q "^#"; then
        warn "File may not be markdown: $filename"
    fi
    
    # Compare and update
    if [[ -f "$target_file" ]]; then
        if ! diff -q "$temp_file" "$target_file" >/dev/null 2>&1; then
            cp "$temp_file" "$target_file"
            echo "UPDATED $filename" >> "$REPORT_FILE"
        else
            echo "UNCHANGED $filename" >> "$REPORT_FILE"
        fi
    else
        cp "$temp_file" "$target_file"
        echo "NEW $filename" >> "$REPORT_FILE"
    fi
    
    rm -f "$temp_file"
    return 0
}

download_all_files() {
    local urls_file="$1"
    local total_urls
    total_urls=$(wc -l < "$urls_file")
    local downloaded=0
    local failed=0
    
    echo "Downloading $total_urls documentation files..." >&2
    
    # Initialize results file
    : > "$REPORT_FILE"
    
    while IFS= read -r url_path; do
        [[ -z "$url_path" ]] && continue
        if download_file "$url_path"; then
            ((downloaded++))
        else
            ((failed++))
        fi
    done < "$urls_file"
    
    # Store summary data for later display
    echo "TOTAL_URLS=$total_urls" > "$TEMP_DIR/summary.txt"
    echo "DOWNLOADED=$downloaded" >> "$TEMP_DIR/summary.txt"
    echo "FAILED=$failed" >> "$TEMP_DIR/summary.txt"
    
    # Return success only if no failures
    [[ $failed -eq 0 ]]
}

show_summary() {
    # Display download summary first
    if [[ -f "$TEMP_DIR/summary.txt" ]]; then
        source "$TEMP_DIR/summary.txt"
        echo >&2
        echo "=== DOWNLOAD SUMMARY ===" >&2
        log "Total URLs processed: $TOTAL_URLS"
        log "Successfully downloaded: $DOWNLOADED"
        [[ $FAILED -gt 0 ]] && error "Failed downloads: $FAILED"
    fi
    
    # Display changes summary
    if [[ -f "$REPORT_FILE" ]]; then
        echo >&2
        echo "=== CHANGES SUMMARY ===" >&2
        
        local new_count updated_count unchanged_count failed_count
        new_count=$(grep -c "^NEW " "$REPORT_FILE" 2>/dev/null || echo "0")
        new_count=${new_count//[^0-9]/}  # Remove non-numeric characters
        updated_count=$(grep -c "^UPDATED " "$REPORT_FILE" 2>/dev/null || echo "0")
        updated_count=${updated_count//[^0-9]/}
        unchanged_count=$(grep -c "^UNCHANGED " "$REPORT_FILE" 2>/dev/null || echo "0")
        unchanged_count=${unchanged_count//[^0-9]/}
        failed_count=$(grep -c "^FAILED " "$REPORT_FILE" 2>/dev/null || echo "0")
        failed_count=${failed_count//[^0-9]/}
        
        echo "  New files: $new_count" >&2
        echo "  Updated files: $updated_count" >&2
        echo "  Unchanged files: $unchanged_count" >&2
        [[ $failed_count -gt 0 ]] && echo "  Failed downloads: $failed_count" >&2
        
        echo >&2
        log "Documentation saved to: $TARGET_DIR"
        [[ -n "$LOG_FILE" ]] && echo "Download log: $LOG_FILE" >&2
        [[ -n "$REPORT_FILE" ]] && echo "Changes report: $REPORT_FILE" >&2
    fi
}

usage() {
    cat << 'EOF'
Claude Code Documentation Downloader

Usage: $0 [OPTIONS]

Options:
  --keep-temp    Keep temporary files for debugging
  --help         Show this help message
  --version      Show version information

Description:
  Downloads all Claude Code documentation from docs.anthropic.com
  Only updates files that have changed (differential updates)

Requirements:
  - curl (with HTTPS support)
  - grep, sed, diff, wc (standard Unix tools)
  - Internet connection

Examples:
  $0                      # Download all documentation
  $0 --keep-temp          # Download and keep temp files for debugging
EOF
}

version() {
    echo "Claude Code Documentation Downloader v1.0"
    echo "URL: https://docs.anthropic.com/en/docs/claude-code/"
}

main() {
    local keep_temp=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --keep-temp) keep_temp=true; shift ;;
            --help) usage; exit 0 ;;
            --version) version; exit 0 ;;
            *) die "Unknown option: $1. Use --help for usage information." ;;
        esac
    done
    
    # Check dependencies before doing anything
    check_dependencies
    
    # Setup temp directory and logging with timestamps
    TEMP_DIR=$(mktemp -d -t claude_docs.XXXXXX)
    local timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    LOG_FILE="$TEMP_DIR/download_${timestamp}.log"
    REPORT_FILE="$TARGET_DIR/../reports/changes_${timestamp}.txt"
    
    # Create reports directory
    mkdir -p "$(dirname "$REPORT_FILE")"
    
    # Setup cleanup with proper signal handling
    if [[ $keep_temp == true ]]; then
        trap cleanup_keep EXIT INT TERM
    else
        trap cleanup EXIT INT TERM
    fi
    
    # Create target directory
    mkdir -p "$TARGET_DIR"
    
    echo "Starting Claude Code documentation download" >&2
    
    # Main workflow
    local urls_file
    urls_file=$(discover_urls) || die "Failed to discover URLs"
    download_all_files "$urls_file" || die "Download process failed"
    show_summary
    
    log "Claude Code documentation download completed!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi