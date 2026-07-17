alias grabVideo='yt-dlp --output "%(title)s.%(ext)s" --restrict-filenames --write-sub --sub-lang en --convert-subs srt --write-auto-sub'
alias grabAudio='yt-dlp --extract-audio --audio-format mp3 --output "%(title)s.%(ext)s" --restrict-filenames'
alias grabAlbum='yt-dlp --extract-audio --audio-format mp3 --output "%(title)s.%(ext)s" --restrict-filenames --split-chapters'

fix_aspect_ratio() {
    local input_file="$1"
    local output_file="$2"
    
    # Validate inputs
    if [[ -z "$input_file" ]]; then
        log_error "Input file not specified"
        return 1
    fi
    
    if [[ ! -f "$input_file" ]]; then
        log_error "Input file does not exist: $input_file"
        return 1
    fi
    
    if [[ -z "$output_file" ]]; then
        # Generate output filename
        local basename="${input_file%.*}"
        local extension="${input_file##*.}"
        output_file="${basename}_fixed.${extension}"
    fi
    
    log_info "Fixing aspect ratio for: $input_file"
    log_info "Output will be saved as: $output_file"
    
    # Check if ffmpeg is available
    if ! command -v ffmpeg &> /dev/null; then
        log_error "ffmpeg is not installed or not in PATH"
        return 1
    fi
    
    # Get video dimensions for verification
    local dimensions=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$input_file")
    log_info "Current video dimensions: $dimensions"
    
    # Fix the aspect ratio by scaling width to 4:3 ratio based on height
    # This assumes the height is correct and the width was stretched
    log_info "Converting stretched 16:9 video back to proper 4:3 aspect ratio..."
    
    ffmpeg -i "$input_file" \
           -vf "scale=ih*4/3:ih" \
           -c:a copy \
           -y \
           "$output_file"
    
    if [[ $? -eq 0 ]]; then
        log_success "Aspect ratio correction completed successfully"
        log_info "Original file: $input_file"
        log_info "Fixed file: $output_file"
        
        # Show new dimensions
        local new_dimensions=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$output_file")
        log_info "New video dimensions: $new_dimensions"
    else
        log_error "Aspect ratio correction failed"
        return 1
    fi
}

# Alternative function if you want to add pillarboxing instead of changing dimensions
fix_aspect_ratio_pillarbox() {
    local input_file="$1"
    local output_file="$2"
    
    if [[ -z "$output_file" ]]; then
        local basename="${input_file%.*}"
        local extension="${input_file##*.}"
        output_file="${basename}_pillarboxed.${extension}"
    fi
    
    log_info "Adding pillarbox to maintain 16:9 container with proper 4:3 content"
    
    # This scales the video to proper 4:3 proportions and adds black bars
    ffmpeg -i "$input_file" \
           -vf "scale=ih*4/3:ih,pad=ih*16/9:ih:(ow-iw)/2:0:black" \
           -c:a copy \
           -y \
           "$output_file"
}

# Simple live stream download
record_live_basic() {
    local url="$1"
    local output_dir="${2:-./recordings}"
    
    mkdir -p "$output_dir"
    yt-dlp \
        --live-from-start \
        --output "$output_dir/%(title)s-%(upload_date)s-%(id)s.%(ext)s" \
        "$url"
}

# Record live stream with specific quality and format
record_live_quality() {
    local url="$1"
    local output_dir="${2:-./recordings}"
    local quality="${3:-}"  # Default to no format selection
    
    mkdir -p "$output_dir"
    
    local format_opts=()
    if [[ -n "$quality" ]]; then
        format_opts+=(--format "$quality")
    fi
    
    yt-dlp \
        --live-from-start \
        "${format_opts[@]}" \
        --output "$output_dir/%(title)s-%(upload_date)s-%(id)s.%(ext)s" \
        --write-description \
        --write-info-json \
        "$url"
}

# Record with duration limit (better function signature)
record_live_with_duration() {
    local url="$1"
    local duration_seconds="$2"
    local output_dir="${3:-./recordings}"
    local quality="${4:-}"
    
    mkdir -p "$output_dir"
    
    local format_opts=()
    if [[ -n "$quality" ]]; then
        format_opts+=(--format "$quality")
    fi
    
    timeout "$duration_seconds" yt-dlp \
        --live-from-start \
        "${format_opts[@]}" \
        --output "$output_dir/%(title)s-%(upload_date)s-%(id)s.%(ext)s" \
        "$url"
}

# Check if stream is live
check_stream_status() {
    local url="$1"
    
    echo "Checking stream status..."
    yt-dlp --quiet --simulate --print "%(title)s" --print "%(is_live)s" --print "%(live_status)s" "$url" 2>/dev/null || {
        echo "Error: Could not access stream or stream not found"
        return 1
    }
}

# List available formats
list_stream_formats() {
    local url="$1"
    
    echo "Available formats for stream:"
    yt-dlp --list-formats "$url"
}

# Record live stream until it ends
record_live_wait() {
    local url="$1"
    local output_dir="${2:-./recordings}"
    
    mkdir -p "$output_dir"
    yt-dlp \
        --live-from-start \
        --wait-for-video 60 \
        --output "$output_dir/%(title)s-%(upload_date)s-%(id)s.%(ext)s" \
        --write-thumbnail \
        --embed-metadata \
        "$url"
}

# Record with time limit
record_live_duration() {
    local url="$1"
    local duration="$2"  # in seconds
    local output_dir="${3:-./recordings}"
    
    mkdir -p "$output_dir"
    timeout "$duration" yt-dlp \
        --live-from-start \
        --output "$output_dir/%(title)s-%(upload_date)s-%(id)s.%(ext)s" \
        "$url"
}

# Monitor and record when live starts
monitor_and_record() {
    local url="$1"
    local output_dir="${2:-./recordings}"
    local check_interval="${3:-300}"  # 5 minutes
    
    mkdir -p "$output_dir"
    
    while true; do
        echo "Checking if stream is live..."
        
        # Check if stream is currently live
        if yt-dlp --quiet --simulate --print "%(is_live)s" "$url" 2>/dev/null | grep -q "True"; then
            echo "Stream is live! Starting recording..."
            yt-dlp \
                --live-from-start \
                --output "$output_dir/%(title)s-%(upload_date)s-%(id)s.%(ext)s" \
                --write-description \
                --write-info-json \
                "$url"
            break
        else
            echo "Stream not live yet. Waiting $check_interval seconds..."
            sleep "$check_interval"
        fi
    done
}

# Alternative using streamlink for better live stream handling
record_with_streamlink() {
    local url="$1"
    local quality="${2:-best}"
    local output_file="$3"
    
    if command -v streamlink >/dev/null 2>&1; then
        streamlink "$url" "$quality" --output "$output_file"
    else
        echo "Streamlink not installed. Install with: pip install streamlink"
        return 1
    fi
}

# FFmpeg direct recording (for RTMP/HLS streams)
record_with_ffmpeg() {
    local stream_url="$1"
    local output_file="$2"
    local duration="${3:-}"
    
    local ffmpeg_opts=()
    
    if [[ -n "$duration" ]]; then
        ffmpeg_opts+=(-t "$duration")
    fi
    
    ffmpeg -i "$stream_url" \
        "${ffmpeg_opts[@]}" \
        -c copy \
        -f mp4 \
        "$output_file"
}

# Troubleshooting functions
troubleshoot_stream() {
    local url="$1"
    
    echo "=== STREAM TROUBLESHOOTING ==="
    echo "URL: $url"
    echo
    
    echo "1. Checking if URL is accessible..."
    if check_stream_status "$url"; then
        echo "✓ Stream URL is accessible"
    else
        echo "✗ Stream URL is not accessible"
        return 1
    fi
    
    echo
    echo "2. Available formats:"
    list_stream_formats "$url"
    
    echo
    echo "3. Recommended commands:"
    echo "   Basic recording (no format selection):"
    echo "   record_live_basic \"$url\""
    echo
    echo "   With duration (30 minutes):"
    echo "   record_live_with_duration \"$url\" \$((60*30))"
    echo
    echo "   With specific quality:"
    echo "   record_live_with_duration \"$url\" \$((60*30)) \"./recordings\" \"720p\""
}

# Example usage (CORRECTED)
# Basic recording:
# record_live_basic "https://youtube.com/watch?v=STREAM_ID"

# Record for 30 minutes:
# record_live_with_duration "https://youtube.com/watch?v=STREAM_ID" $((60*30))

# Record with specific quality and duration:
# record_live_with_duration "https://youtube.com/watch?v=STREAM_ID" $((60*30)) "./recordings" "720p"

# Troubleshoot a problematic stream:
# troubleshoot_stream "https://youtube.com/watch?v=STREAM_ID"

# Monitor for when stream goes live:
# monitor_and_record "https://youtube.com/watch?v=STREAM_ID" "./recordings" 600