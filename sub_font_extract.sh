#!/bin/bash

# Default values
inputDir="./input"
outputDir="./output"
fontDir="./output/fonts"
providedName=""

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -i|--input) inputDir="$2"; shift ;;
        -o|--output) outputDir="$2"; shift ;;
        -n|--name) providedName="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

mkdir -p "$fontDir"

# Function to extract season and episode numbers
extract_season_episode() {
    filename="$1"
    # Default season and episode
    season="01"
    episode="01"
    if [[ $filename =~ S([0-9]{2})E([0-9]{2}) ]]; then
        season="${BASH_REMATCH[1]}"
        episode="${BASH_REMATCH[2]}"
    elif [[ $filename =~ Season[[:space:]]*([0-9]+)/([0-9]+) ]]; then
        season=$(printf "%02d" "${BASH_REMATCH[1]}")
        episode=$(printf "%02d" "${BASH_REMATCH[2]}")
    elif [[ $filename =~ Episode[[:space:]]*([0-9]+)/([0-9]+) ]]; then
        season=$(printf "%02d" "${BASH_REMATCH[1]}")
        episode=$(printf "%02d" "${BASH_REMATCH[2]}")
    elif [[ $filename =~ ([0-9]+)/([0-9]+) ]]; then
        season="01"
        episode=$(printf "%02d" "${BASH_REMATCH[2]}")
    fi
    echo "$season:$episode"
}

# Loop through all .mkv files in the input directory
for mkvfile in "$inputDir"/*.mkv; do
    echo "Processing file: $mkvfile"

    # Extract the name without the path and extension
    filename=$(basename -- "$mkvfile")
    base="${filename%.*}"

    # Extract season and episode numbers
    se_numbers=$(extract_season_episode "$base")
    season="${se_numbers%%:*}"
    episode="${se_numbers##*:}"

    # Apply season and episode numbers to providedName
    if [[ ! -z "$providedName" ]]; then
        namePattern="${providedName//%S/$season}"
        namePattern="${namePattern//%E/$episode}"
    else
        namePattern="$base"
    fi

    # Use mkvmerge with -J to get JSON output and parse it with jq for subtitle track ID and font attachment IDs
    json=$(mkvmerge -J "$mkvfile")

    # Extract subtitle tracks information
#    subtitleTracks=$(echo "$json" | jq '.tracks[] | select(.type=="subtitles") | {id: .id, language: .properties.language, track_name: .properties.track_name}')
    subtitleTracks=$(echo "$json" | jq '.tracks[] | select(.type=="subtitles") | {id: .id, language: .properties.language, track_name: .properties.track_name // empty, codec: .codec}')

    # Loop through subtitle tracks
    echo "$subtitleTracks" | jq -c . | while read subtitleTrack; do
        id=$(echo "$subtitleTrack" | jq '.id')
        language=$(echo "$subtitleTrack" | jq -r '.language')
        codec=$(echo "$subtitleTrack" | jq -r '.codec')
#        track_name=$(echo "$subtitleTrack" | jq -r '.track_name | gsub("[ /]";"_")') # replace spaces and slashes with underscores for filename safety
        track_name=$(echo "$subtitleTrack" | jq -r '.track_name | if . == "" then "null" else . end | gsub("[/]";"_")')
#        subtitleFilename="$base.$language.$track_name.ass"

        # Use id if track_name is null
        if [ "$track_name" = "null" ]; then
            subtitleFilename="$namePattern.$language.$id"
        else
            subtitleFilename="$namePattern.$language.$track_name"
        fi

        # Append appropriate file extension based on codec
        case "$codec" in
            "S_TEXT/UTF8" | "SubRip/SRT") subtitleFilename+=".srt";;
            "S_TEXT/SSA" | "SubStationAlpha") subtitleFilename+=".ass";;
            "S_TEXT/ASS") subtitleFilename+=".ass";;
            * ) subtitleFilename+=".sub";; # Assuming MicroDVD or other types not explicitly handled, adjust as necessary
        esac

        # Extract the subtitle track
        mkvextract tracks "$mkvfile" "$id:\"$outputDir/$subtitleFilename\""
    done

    # Extract font attachments based on file extensions (ttf, otf, etc.)
    echo "$json" | jq -r '.attachments[] | select(.file_name | endswith(".ttf") or endswith(".otf")) | "\(.id):\(.file_name)"' | while read -r attachment; do
        IFS=':' read -r id fileName <<< "$attachment"
        mkvextract attachments "$mkvfile" "$id:\"$outputDir/fonts/${fileName}\""
    done

    # # Extract font attachments based on MIME types
    # echo "$json" | jq -r '.attachments[] | select(.content_type=="application/x-truetype-font" or .content_type=="application/vnd.ms-opentype" or .content_type=="font/ttf" or .content_type=="font/otf") | .id' | while read id; do
    #     mkvextract attachments "$mkvfile" $id:"$outputDir/${id}_$(echo "$json" | jq -r --arg id "$id" '.attachments[] | select(.id==$id | tonumber).file_name')"
    # done

    echo "Extraction completed for: $mkvfile"
done

echo "All files processed."