#!/bin/bash

# ~/.local/share/prbl/scripts/enhanced-audio-grabber.sh
# Purpose: Smart YouTube audio downloader with automatic album organization, metadata tagging, and Plex optimization
# Usage: ./enhanced-audio-grabber.sh [OPTIONS] <URL>
#        Run from artist directory - script auto-detects album name and creates subfolders
#
# Features:
# - Auto-detects album/playlist names and creates appropriate folders
# - Embeds album art and metadata for Plex compatibility
# - Handles artist directory structure intelligently
# - Fixes common ffmpeg detection issues
# - Supports batch processing of playlists
# - Fixed stdout/stderr handling to prevent directory name corruption

set -euo pipefail

# Script configuration
SCRIPT_NAME="enhanced-audio-grabber"
VERSION="2.0.2"
DEFAULT_FORMAT="mp3"
DEFAULT_QUALITY="192"
DEFAULT_BITRATE="192k"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output (always to stderr to avoid capture)
print_status() {
    local level=$1
    shift
    case $level in
        "error")   echo -e "${RED}[ERROR]${NC} $*" >&2 ;;
        "warning") echo -e "${YELLOW}[WARNING]${NC} $*" >&2 ;;
        "success") echo -e "${GREEN}[SUCCESS]${NC} $*" >&2 ;;
        "info")    echo -e "${BLUE}[INFO]${NC} $*" >&2 ;;
        "debug")   echo -e "${CYAN}[DEBUG]${NC} $*" >&2 ;;
        *)         echo "$*" >&2 ;;
    esac
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to find ffmpeg path
find_ffmpeg() {
    local ffmpeg_candidates=(
        "$(command -v ffmpeg 2>/dev/null || true)"
        "/usr/bin/ffmpeg"
        "/usr/local/bin/ffmpeg"
        "/opt/homebrew/bin/ffmpeg"
        "$HOME/bin/ffmpeg"
        "/snap/bin/ffmpeg"
        "./ffmpeg"
    )

    for path in "${ffmpeg_candidates[@]}"; do
        if [[ -n "$path" && -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done

    return 1
}

# Function to sanitize filename/directory names
sanitize_name() {
    local name="$1"
    # Remove problematic characters but preserve readability
    echo "$name" | sed -E 's/[<>:"/\\|?*]/_/g' | sed -E 's/__+/_/g' | sed -E 's/^_+|_+$//g' | sed -E 's/\.$//g'
}

# Function to get YouTube metadata
get_youtube_metadata() {
    local url="$1"
    local temp_info="/tmp/yt_info_$$.json"

    # Get metadata without downloading
    if yt-dlp --dump-json --flat-playlist "$url" > "$temp_info" 2>/dev/null; then
        echo "$temp_info"
        return 0
    else
        rm -f "$temp_info"
        return 1
    fi
}

# Function to extract album info from metadata
extract_album_info() {
    local metadata_file="$1"
    local album_title=""
    local artist_name=""
    local track_count=""

    # Try to extract playlist/album title
    if command_exists jq; then
        album_title=$(jq -r '.title // .playlist_title // empty' "$metadata_file" 2>/dev/null | head -n1)
        artist_name=$(jq -r '.uploader // .channel // empty' "$metadata_file" 2>/dev/null | head -n1)
        track_count=$(jq -r '.playlist_count // empty' "$metadata_file" 2>/dev/null)
    else
        # Fallback to grep if jq not available
        album_title=$(grep -o '"title":\s*"[^"]*"' "$metadata_file" | head -n1 | cut -d'"' -f4)
        artist_name=$(grep -o '"uploader":\s*"[^"]*"' "$metadata_file" | head -n1 | cut -d'"' -f4)
    fi

    # Clean up the names
    album_title=$(sanitize_name "$album_title")
    artist_name=$(sanitize_name "$artist_name")

    echo "$album_title|$artist_name|$track_count"
}

# Function to detect current directory context
detect_directory_context() {
    local current_dir=$(basename "$PWD")
    local parent_dir=$(basename "$(dirname "$PWD")")

    # Check if we're in what looks like an artist directory
    if [[ -d "../$current_dir" ]] && [[ $(find . -maxdepth 1 -type d | wc -l) -gt 1 ]]; then
        echo "artist|$current_dir"
    elif [[ -d "../../$parent_dir" ]] && [[ -d "../$current_dir" ]]; then
        echo "album|$current_dir|$parent_dir"
    else
        echo "unknown|$current_dir"
    fi
}

# Function to create album directory and organize (FIXED - no stdout pollution)
setup_album_directory() {
    local album_name="$1"
    local artist_name="$2"
    local context="$3"

    local target_dir=""

    case $context in
        "artist")
            # We're in artist directory, create album subdirectory
            target_dir="./$album_name"
            ;;
        "album")
            # We're already in an album directory
            target_dir="."
            ;;
        *)
            # Unknown context, create artist/album structure
            if [[ -n "$artist_name" ]]; then
                target_dir="./$artist_name/$album_name"
            else
                target_dir="./$album_name"
            fi
            ;;
    esac

    # Create directory if it doesn't exist
    if [[ "$target_dir" != "." ]]; then
        mkdir -p "$target_dir"
        print_status "info" "Created album directory: $target_dir"
    fi

    # Only echo the target directory to stdout (for capture)
    echo "$target_dir"
}

# Function to embed metadata and album art
embed_metadata() {
    local audio_file="$1"
    local album_title="$2"
    local artist_name="$3"
    local track_number="$4"
    local album_art="$5"
    local year="$6"

    if [[ ! -f "$audio_file" ]]; then
        return 1
    fi

    # Find ffmpeg path for metadata embedding
    local ffmpeg_path
    if ! ffmpeg_path=$(find_ffmpeg); then
        print_status "warning" "ffmpeg not found for metadata embedding"
        return 1
    fi

    # Build ffmpeg metadata command
    local temp_output="${audio_file}.tmp"
    local cmd=("$ffmpeg_path" -i "$audio_file" -c copy)

    # Add metadata
    if [[ -n "$album_title" ]]; then
        cmd+=(-metadata "album=$album_title")
    fi

    if [[ -n "$artist_name" ]]; then
        cmd+=(-metadata "artist=$artist_name")
        cmd+=(-metadata "album_artist=$artist_name")
    fi

    if [[ -n "$track_number" ]]; then
        cmd+=(-metadata "track=$track_number")
    fi

    if [[ -n "$year" ]]; then
        cmd+=(-metadata "date=$year")
    fi

    # Add album art if available
    if [[ -n "$album_art" && -f "$album_art" ]]; then
        cmd+=(-i "$album_art" -map 0 -map 1 -disposition:v:0 attached_pic)
    fi

    cmd+=(-y "$temp_output")

    # Execute metadata embedding
    if "${cmd[@]}" >/dev/null 2>&1; then
        mv "$temp_output" "$audio_file"
        return 0
    else
        rm -f "$temp_output"
        return 1
    fi
}

# Function to download and process album
download_album() {
    local url="$1"
    local audio_format="$2"
    local quality="$3"
    local embed_metadata_flag="$4"
    local verbose="$5"

    print_status "info" "Analyzing URL: $url"

    # Get YouTube metadata
    local metadata_file
    if ! metadata_file=$(get_youtube_metadata "$url"); then
        print_status "error" "Failed to get metadata from YouTube URL"
        return 1
    fi

    # Extract album information
    local album_info
    album_info=$(extract_album_info "$metadata_file")
    IFS='|' read -r album_title artist_name track_count <<< "$album_info"

    if [[ -z "$album_title" ]]; then
        print_status "warning" "Could not detect album title, using generic name"
        album_title="Downloaded_Album_$(date +%Y%m%d_%H%M%S)"
    fi

    print_status "info" "Album: $album_title"
    [[ -n "$artist_name" ]] && print_status "info" "Artist: $artist_name"
    [[ -n "$track_count" ]] && print_status "info" "Tracks: $track_count"

    # Detect directory context
    local dir_context
    dir_context=$(detect_directory_context)

    # Parse directory context info
    local context_type current_name parent_name
    context_type=$(echo "$dir_context" | cut -d'|' -f1)
    current_name=$(echo "$dir_context" | cut -d'|' -f2)
    parent_name=$(echo "$dir_context" | cut -d'|' -f3)

    # Setup album directory (FIXED - properly capture only the directory path)
    local album_dir
    album_dir=$(setup_album_directory "$album_title" "$artist_name" "$context_type")

    # Find ffmpeg
    local ffmpeg_path
    if ffmpeg_path=$(find_ffmpeg); then
        print_status "debug" "Found ffmpeg at: $ffmpeg_path"
    else
        print_status "error" "ffmpeg not found. Please install ffmpeg."
        rm -f "$metadata_file"
        return 1
    fi

    # Build yt-dlp command for actual download
    local yt_cmd=(yt-dlp)

    # Add ffmpeg location
    yt_cmd+=(--ffmpeg-location "$ffmpeg_path")

    # Audio extraction settings
    yt_cmd+=(--extract-audio --audio-format "$audio_format" --audio-quality "$quality")

    # Output template with track numbering for playlists
    yt_cmd+=(--output "$album_dir/%(playlist_index)02d - %(title)s.%(ext)s")

    # Additional options for better quality and metadata
    yt_cmd+=(
        --ignore-errors
        --add-metadata
        --embed-thumbnail
        --write-info-json
        --write-thumbnail
        --restrict-filenames
        --no-warnings
    )

    # Add verbose flag if requested
    if [[ "$verbose" == "true" ]]; then
        yt_cmd+=(--verbose)
    fi

    print_status "info" "Starting download to: $album_dir"

    # Execute download
    if "${yt_cmd[@]}" "$url"; then
        print_status "success" "Download completed"

        # Post-process files if metadata embedding is requested
        if [[ "$embed_metadata_flag" == "true" ]]; then
            post_process_album "$album_dir" "$album_title" "$artist_name" "$audio_format" "$verbose"
        fi

        # Clean up temporary files
        find "$album_dir" -name "*.info.json" -delete 2>/dev/null || true
        find "$album_dir" -name "*.webp" -delete 2>/dev/null || true

    else
        print_status "error" "Download failed"
        rm -f "$metadata_file"
        return 1
    fi

    rm -f "$metadata_file"
    return 0
}

# Function to post-process downloaded album (FIXED - added audio_format parameter)
post_process_album() {
    local album_dir="$1"
    local album_title="$2"
    local artist_name="$3"
    local audio_format="$4"
    local verbose="$5"

    print_status "info" "Post-processing album metadata..."

    # Find album art (thumbnail downloaded by yt-dlp)
    local album_art
    album_art=$(find "$album_dir" -name "*.jpg" -o -name "*.png" -o -name "*.webp" | head -n1)

    # Get current year
    local year=$(date +%Y)

    # Process each audio file
    local track_num=1
    while IFS= read -r -d '' audio_file; do
        if [[ "$verbose" == "true" ]]; then
            print_status "debug" "Processing: $(basename "$audio_file")"
        fi

        # Extract track number from filename if present
        local filename=$(basename "$audio_file")
        if [[ $filename =~ ^([0-9]+) ]]; then
            track_num="${BASH_REMATCH[1]#0}"  # Remove leading zeros
        fi

        # Embed metadata
        if ! embed_metadata "$audio_file" "$album_title" "$artist_name" "$track_num" "$album_art" "$year"; then
            print_status "warning" "Failed to embed metadata for: $(basename "$audio_file")"
        fi

        ((track_num++))
    done < <(find "$album_dir" -maxdepth 1 -name "*.$audio_format" -print0 | sort -z)

    # Create a folder.jpg for Plex if we have album art
    if [[ -n "$album_art" && -f "$album_art" ]]; then
        cp "$album_art" "$album_dir/folder.jpg"
        print_status "success" "Created folder.jpg for Plex"
    fi

    print_status "success" "Metadata processing completed"
}

# Function to show usage
show_usage() {
    cat << EOF
$SCRIPT_NAME v$VERSION - Smart YouTube Audio Downloader

DESCRIPTION:
    Downloads YouTube playlists/albums with automatic organization and metadata tagging.
    Designed to work seamlessly with Plex and media server setups.

USAGE:
    $0 [OPTIONS] <YOUTUBE_URL>

OPTIONS:
    -f, --format FORMAT     Audio format (mp3, aac, flac, m4a) [default: $DEFAULT_FORMAT]
    -q, --quality QUALITY   Audio quality (0-320 for mp3, 0-500 for aac) [default: $DEFAULT_QUALITY]
    -m, --metadata          Embed album art and metadata in files
    -s, --skip-metadata     Skip metadata embedding (faster)
    -b, --bitrate BITRATE   Specify exact bitrate (e.g., 320k, 192k) [default: $DEFAULT_BITRATE]
    -v, --verbose           Verbose output
    -d, --dry-run           Show what would be downloaded without downloading
    -h, --help              Show this help message

DIRECTORY BEHAVIOR:
    - Run from artist directory: Creates album subdirectory automatically
    - Run from album directory: Downloads to current directory
    - Run from anywhere else: Creates Artist/Album structure

EXAMPLES:
    # Download album with metadata (recommended)
    $0 -m https://www.youtube.com/playlist?list=PL224DDF005A5C86A9

    # High quality FLAC with metadata
    $0 -f flac -m -q 0 https://www.youtube.com/playlist?list=example

    # Quick download without metadata processing
    $0 -s https://www.youtube.com/watch?v=example

METADATA FEATURES:
    - Automatically extracts album/artist names from YouTube
    - Embeds album artwork in individual tracks
    - Creates folder.jpg for Plex media server recognition
    - Numbers tracks correctly for proper playback order
    - Adds year, artist, and album metadata tags

DEPENDENCIES:
    - yt-dlp (pip install yt-dlp)
    - ffmpeg (auto-detected from PATH or common locations)
    - jq (optional, for better metadata parsing)

CLEANUP:
    To remove corrupted directories with ANSI codes in names:
    find . -name "*\$'*" -type d -exec rm -rf {} +

EOF
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()

    # Check for yt-dlp
    if ! command_exists yt-dlp; then
        missing_deps+=("yt-dlp")
    fi

    # Check for ffmpeg and set path
    if FFMPEG_PATH=$(find_ffmpeg); then
        export FFMPEG_PATH
        print_status "debug" "Found ffmpeg at: $FFMPEG_PATH"
    else
        missing_deps+=("ffmpeg")
    fi

    # Check for jq (optional but recommended)
    if ! command_exists jq; then
        print_status "warning" "jq not found - metadata parsing will be limited"
        print_status "info" "Install jq for better results: sudo apt install jq  # or brew install jq"
    fi

    # Report missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_status "error" "Missing required dependencies: ${missing_deps[*]}"
        print_status "info" "Install commands:"
        for dep in "${missing_deps[@]}"; do
            case $dep in
                "yt-dlp")
                    echo "  pip install yt-dlp" >&2
                    echo "  # or: brew install yt-dlp" >&2
                    echo "  # or: sudo apt install yt-dlp" >&2
                    ;;
                "ffmpeg")
                    echo "  # Ubuntu/Debian: sudo apt install ffmpeg" >&2
                    echo "  # macOS: brew install ffmpeg" >&2
                    echo "  # Arch: sudo pacman -S ffmpeg" >&2
                    ;;
            esac
        done
        return 1
    fi

    return 0
}

# Function for dry run - show what would be downloaded
dry_run() {
    local url="$1"

    print_status "info" "DRY RUN - Analyzing what would be downloaded"

    # Get metadata
    local metadata_file
    if ! metadata_file=$(get_youtube_metadata "$url"); then
        print_status "error" "Failed to get metadata for dry run"
        return 1
    fi

    # Extract info
    local album_info
    album_info=$(extract_album_info "$metadata_file")
    IFS='|' read -r album_title artist_name track_count <<< "$album_info"

    # Show what would happen (all to stderr to avoid capture issues)
    {
        echo
        echo "DOWNLOAD PLAN:"
        echo "=============="
        echo "Album: ${album_title:-Unknown}"
        echo "Artist: ${artist_name:-Unknown}"
        echo "Tracks: ${track_count:-Unknown}"
        echo "Current directory: $PWD"

        local dir_context
        dir_context=$(detect_directory_context)

        # Parse directory context
        local context_type current_name
        context_type=$(echo "$dir_context" | cut -d'|' -f1)
        current_name=$(echo "$dir_context" | cut -d'|' -f2)

        local target_dir
        case $context_type in
            "artist")
                target_dir="$PWD/$album_title"
                echo "Target directory: $target_dir (new album subdirectory)"
                ;;
            "album")
                target_dir="$PWD"
                echo "Target directory: $target_dir (current album directory)"
                ;;
            *)
                if [[ -n "$artist_name" ]]; then
                    target_dir="$PWD/$artist_name/$album_title"
                else
                    target_dir="$PWD/$album_title"
                fi
                echo "Target directory: $target_dir (new artist/album structure)"
                ;;
        esac

        echo "Audio format: $audio_format"
        echo "Quality: $quality"
        echo

        # Show actual tracks that would be downloaded
        if command_exists jq && [[ -f "$metadata_file" ]]; then
            echo "TRACKS:"
            echo "======="
            jq -r '.entries[]?.title // .title // "Unknown Track"' "$metadata_file" 2>/dev/null | nl -w2 -s'. '
        fi
    } >&2

    rm -f "$metadata_file"
}

# Function to clean up corrupted directories
cleanup_corrupted_dirs() {
    print_status "info" "Searching for directories with ANSI escape codes in their names..."
    
    # Find directories with ANSI escape sequences
    local corrupted_dirs
    corrupted_dirs=$(find . -maxdepth 1 -name "*\$'*" -type d 2>/dev/null || true)
    
    if [[ -n "$corrupted_dirs" ]]; then
        print_status "warning" "Found corrupted directories:"
        echo "$corrupted_dirs" >&2
        
        echo -n "Remove these directories? (y/N): " >&2
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            while IFS= read -r dir; do
                if [[ -d "$dir" ]]; then
                    print_status "info" "Removing: $dir"
                    rm -rf "$dir"
                fi
            done <<< "$corrupted_dirs"
            print_status "success" "Corrupted directories cleaned up"
        else
            print_status "info" "Skipping cleanup"
        fi
    else
        print_status "info" "No corrupted directories found"
    fi
}

# Main function
main() {
    # Default values
    local audio_format="$DEFAULT_FORMAT"
    local quality="$DEFAULT_QUALITY"
    local bitrate="$DEFAULT_BITRATE"
    local embed_metadata_flag="true"  # Default to embedding metadata
    local verbose="false"
    local dry_run_flag="false"
    local cleanup_flag="false"
    local url=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            -f|--format)
                audio_format="$2"
                shift 2
                ;;
            -q|--quality)
                quality="$2"
                shift 2
                ;;
            -b|--bitrate)
                bitrate="$2"
                shift 2
                ;;
            -m|--metadata)
                embed_metadata_flag="true"
                shift
                ;;
            -s|--skip-metadata)
                embed_metadata_flag="false"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -d|--dry-run)
                dry_run_flag="true"
                shift
                ;;
            --cleanup)
                cleanup_flag="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                print_status "error" "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$url" ]]; then
                    url="$1"
                else
                    print_status "error" "Multiple URLs not supported"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Handle cleanup mode
    if [[ "$cleanup_flag" == "true" ]]; then
        cleanup_corrupted_dirs
        exit 0
    fi

    # Validate inputs
    if [[ -z "$url" ]]; then
        print_status "error" "No YouTube URL provided"
        show_usage
        exit 1
    fi

    # Validate audio format
    case $audio_format in
        mp3|aac|flac|m4a|wav|ogg) ;;
        *)
            print_status "error" "Unsupported audio format: $audio_format"
            print_status "info" "Supported formats: mp3, aac, flac, m4a, wav, ogg"
            exit 1
            ;;
    esac

    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi

    # Handle dry run
    if [[ "$dry_run_flag" == "true" ]]; then
        dry_run "$url"
        exit 0
    fi

    # Show configuration if verbose
    if [[ "$verbose" == "true" ]]; then
        print_status "debug" "Configuration:"
        echo "  Format: $audio_format" >&2
        echo "  Quality: $quality" >&2
        echo "  Bitrate: $bitrate" >&2
        echo "  Embed metadata: $embed_metadata_flag" >&2
        echo "  Current directory: $PWD" >&2
    fi

    # Download and process
    if download_album "$url" "$audio_format" "$quality" "$embed_metadata_flag" "$verbose"; then
        print_status "success" "Album download and processing completed!"
        print_status "info" "Files are ready for Plex media server"
    else
        print_status "error" "Download failed"
        exit 1
    fi
}

# Helper function to create config file
create_config_example() {
    local config_dir="$HOME/.config/transcribe"
    local config_file="$config_dir/config.json"

    mkdir -p "$config_dir"

    cat > "$config_file" << 'EOF'
{
    "hf_token": "your_huggingface_token_here",
    "default_audio_format": "mp3",
    "default_quality": "192",
    "auto_embed_metadata": true
}
EOF

    print_status "info" "Created example config file at: $config_file"
    print_status "info" "Edit this file to set your preferences"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
