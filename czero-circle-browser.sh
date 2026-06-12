#!/bin/sh
# zero-circle-browser.sh
# Minimal HTML4 terminal browser (text only, GIF aware)

FILE="$1"
if [ -z "$FILE" ]; then
  echo "Usage: $0 file.html"
  exit 1
fi

# Parse HTML4: strip tags, keep links and GIFs
awk '
BEGIN { IGNORECASE=1 }
/<a href=/ {
  match($0, /href="([^"]+)"/, arr)
  if(arr[1]!="") print "[LINK] " arr[1]
}
/<img src=/ {
  match($0, /src="([^"]+)"/, arr)
  if(arr[1] ~ /\.gif$/) print "[GIF] " arr[1]
}
{
  # remove tags
  gsub(/<[^>]+>/,"")
  if(length($0)>0) print $0
}
' "$FILE"
