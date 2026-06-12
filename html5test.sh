#!/bin/sh
# Zero Circle Math Browser v4
# Adds HTML4→HTML5 fallback parser table

FILE="$1"
if [ -z "$FILE" ]; then
  echo "Usage: $0 file.html"
  exit 1
fi

HISTORY=()
FORWARD=()

while true; do
  clear
  echo "=== Zero Circle Math Browser v4 ==="
  echo "Rendering: $FILE"
  echo

  # Conditional SMPTE detection
  if grep -qi "SMPTE\|NTSC" "$FILE"; then
    echo ">>> SMPTE Bars Detected (ANSI Simulation)"
    # (ANSI SMPTE + grayscale ramp + PLUGE code here, same as v3)
  fi

  # Parse HTML4 + HTML5 fallback
  awk '
  BEGIN { IGNORECASE=1; linknum=1 }
  /&nbsp;/ {
    gsub(/&nbsp;/," ")
    print "[NBSP Pulse]"
  }
  /<div>/ { print "[DIV Pulse] (HTML4 container)" }
  /<section>/ { print "[DIV Pulse] (HTML5 section→DIV)" }
  /<article>/ { print "[DIV Pulse] (HTML5 article→DIV)" }
  /<p>/ { print "[Text Pulse]" }
  /<img src=/ {
    match($0, /src="([^"]+)"/, arr)
    if(arr[1] ~ /\.gif$/) {
      print "[GIF Pulse] " arr[1]
    } else if(arr[1] ~ /\.jpe?g$/) {
      print "[JPG Texture] " arr[1]
    } else if(arr[1] ~ /\.bmp$/) {
      print "[BMP Texture] " arr[1]
    } else {
      print "[IMG Pulse] " arr[1]
    }
  }
  /<video>/ { print "[IMG Pulse] [VIDEO Placeholder]" }
  /<audio>/ { print "[Pulse] [AUDIO Placeholder]" }
  /<font>/ { print "[Color Pulse] (HTML4 font→SPAN)" }
  /<center>/ { print "[Alignment Pulse] (center)" }
  /<marquee>/ { print "[Motion Pulse] (scroll)" }
  /<script>/,/<\/script>/ {
    print "[Pulse Instruction Block]"
    next
  }
  /<a href=/ {
    match($0, /href="([^"]+)"/, arr)
    if(arr[1]!="") {
      printf("[%d] LINK: %s\n", linknum, arr[1])
      linknum++
    }
  }
  {
    gsub(/<[^>]+>/,"")
    if(length($0)>0) print $0
  }
  ' "$FILE"

  echo
  echo "Options: Enter link number, b=back, f=forward, h=history, q=quit"
  read -p "Choice: " choice

  # Navigation stack logic (same as v3)
  if [ "$choice" = "q" ]; then break; fi
  if [ "$choice" = "b" ]; then
    if [ ${#HISTORY[@]} -gt 0 ]; then
      FORWARD+=("$FILE")
      FILE="${HISTORY[-1]}"
      HISTORY=("${HISTORY[@]:0:${#HISTORY[@]}-1}")
    fi
    continue
  fi
  if [ "$choice" = "f" ]; then
    if [ ${#FORWARD[@]} -gt 0 ]; then
      HISTORY+=("$FILE")
      FILE="${FORWARD[-1]}"
      FORWARD=("${FORWARD[@]:0:${#FORWARD[@]}-1}")
    fi
    continue
  fi
  if [ "$choice" = "h" ]; then
    echo "Visited pages:"
    for i in "${!HISTORY[@]}"; do
      echo "[$i] ${HISTORY[$i]}"
    done
    read -p "Jump to: " idx
    if [ -n "${HISTORY[$idx]}" ]; then
      FILE="${HISTORY[$idx]}"
    fi
    continue
  fi

  if [ -n "$choice" ]; then
    HISTORY+=("$FILE")
    FILE=$(awk -v n="$choice" '
      BEGIN { IGNORECASE=1; linknum=1 }
      /<a href=/ {
        match($0, /href="([^"]+)"/, arr)
        if(arr[1]!="" && linknum==n) { print arr[1]; exit }
        linknum++
      }
    ' "$FILE")
    if [ -z "$FILE" ]; then
      echo "Invalid choice."
      exit 1
    fi
  fi
done
