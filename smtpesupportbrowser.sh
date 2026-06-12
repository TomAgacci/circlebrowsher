#!/bin/sh
# Zero Circle Math Browser with conditional SMPTE bars

FILE="$1"
if [ -z "$FILE" ]; then
  echo "Usage: $0 file.html"
  exit 1
fi

HISTORY=()

while true; do
  clear
  echo "=== Zero Circle Math Browser ==="
  echo "Rendering: $FILE"
  echo

  # Check if file contains SMPTE/NTSC keywords
  if grep -qi "SMPTE\|NTSC" "$FILE"; then
    rows=$(tput lines)
    cols=$(tput cols)
    barW=$((cols/7))
    echo "SMPTE Bars:"
    for row in $(seq 1 $((rows/3))); do
      for i in $(seq 0 6); do
        case $i in
          0) color="\033[47m" ;; # white
          1) color="\033[43m" ;; # yellow
          2) color="\033[46m" ;; # cyan
          3) color="\033[42m" ;; # green
          4) color="\033[45m" ;; # magenta
          5) color="\033[41m" ;; # red
          6) color="\033[44m" ;; # blue
        esac
        printf "${color}%${barW}s\033[0m" " "
      done
      echo
    done
    echo
  fi

  # Parse HTML4: text, links, images, scripts
  awk '
  BEGIN { IGNORECASE=1; linknum=1 }
  /<a href=/ {
    match($0, /href="([^"]+)"/, arr)
    if(arr[1]!="") {
      printf("\033[36m[%d] LINK:\033[0m %s\n", linknum, arr[1])
      linknum++
    }
  }
  /<img src=/ {
    match($0, /src="([^"]+)"/, arr)
    if(arr[1] ~ /\.gif$/) {
      print "\033[35m[GIF Pulse]\033[0m " arr[1]
    } else if(arr[1] ~ /\.jpe?g$/) {
      print "\033[32m[JPG Texture]\033[0m " arr[1]
    } else if(arr[1] ~ /\.bmp$/) {
      print "\033[34m[BMP Texture]\033[0m " arr[1]
    }
  }
  /<script>/,/<\/script>/ {
    print "\033[33m[Pulse Instruction Block]\033[0m"
    next
  }
  {
    gsub(/<[^>]+>/,"")
    if(length($0)>0) print $0
  }
  ' "$FILE"

  echo
  echo "Options:"
  echo "  Enter link number to follow"
  echo "  b = back"
  echo "  q = quit"
  echo

  # GIF pulse animation
  for i in 1 2 3; do
    echo -ne "\033[35mGIF pulse frame $i ▒▓█\033[0m\r"
    sleep 0.3
  done
  echo

  read -p "Choice: " choice
  if [ "$choice" = "q" ]; then
    break
  fi
  if [ "$choice" = "b" ]; then
    if [ ${#HISTORY[@]} -gt 0 ]; then
      FILE="${HISTORY[-1]}"
      HISTORY=("${HISTORY[@]:0:${#HISTORY[@]}-1}")
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
