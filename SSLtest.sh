#!/bin/sh
# Zero Circle Math Browser v4
# Conditional SMPTE bars + HTML4/HTML5 fallback + CSS→ANSI pulses + external CSS SSL support

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
    rows=$(tput lines)
    cols=$(tput cols)
    barW=$((cols/7))

    echo "SMPTE Bars:"
    for row in $(seq 1 $((rows/2))); do
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

    # Bottom grayscale + PLUGE
    for row in $(seq 1 $((rows/4))); do
      for i in $(seq 0 6); do
        case $i in
          0) color="\033[100m" ;; # dark gray
          1) color="\033[40m"  ;; # black
          2) color="\033[45m"  ;; # purple (PLUGE)
          3) color="\033[47m"  ;; # gray
          4) color="\033[107m" ;; # white
          5) color="\033[40m"  ;; # black
          6) color="\033[100m" ;; # dark gray
        esac
        printf "${color}%${barW}s\033[0m" " "
      done
      echo
    done
    echo
  fi

  # Parse HTML4 + HTML5 fallback + CSS pulses
  awk '
  BEGIN { IGNORECASE=1; linknum=1 }
  /&nbsp;/ { gsub(/&nbsp;/," "); print "[NBSP Pulse]" }
  /<div>/ { print "[DIV Pulse]" }
  /<section>/ { print "[DIV Pulse] (HTML5 section→DIV)" }
  /<article>/ { print "[DIV Pulse] (HTML5 article→DIV)" }
  /<p>/ { print "[Text Pulse]" }
  /<span style=/ {
    match($0, /style="([^"]+)"/, arr)
    style=arr[1]
    if(style ~ /color:red/) print "\033[31m[Red Text Pulse]\033[0m"
    if(style ~ /color:blue/) print "\033[34m[Blue Text Pulse]\033[0m"
    if(style ~ /color:green/) print "\033[32m[Green Text Pulse]\033[0m"
    if(style ~ /text-align:center/) print "[Alignment Pulse: Center]"
    if(style ~ /font-weight:bold/) print "\033[1m[Bold Pulse]\033[0m"
    if(style ~ /font-style:italic/) print "\033[3m[Italic Pulse]\033[0m"
    if(style ~ /text-decoration:underline/) print "\033[4m[Underline Pulse]\033[0m"
  }
  /<link rel="stylesheet"/ {
    match($0, /href="([^"]+)"/, arr)
    if(arr[1]!="") {
      cssfile=arr[1]
      print "[External CSS Pulse] Loading " cssfile
      if(cssfile ~ /^https:/) {
        cmd="curl --silent --ssl " cssfile
      } else {
        cmd="cat " cssfile
      }
      while((cmd | getline line) > 0) {
        if(line ~ /color:red/) print "\033[31m[CSS Red Text Pulse]\033[0m"
        if(line ~ /color:blue/) print "\033[34m[CSS Blue Text Pulse]\033[0m"
        if(line ~ /background:black/) print "\033[40m[CSS Black Background Pulse]\033[0m"
        if(line ~ /text-align:center/) print "[CSS Alignment Pulse: Center]"
        if(line ~ /font-weight:bold/) print "\033[1m[CSS Bold Pulse]\033[0m"
        if(line ~ /font-style:italic/) print "\033[3m[CSS Italic Pulse]\033[0m"
        if(line ~ /text-decoration:underline/) print "\033[4m[CSS Underline Pulse]\033[0m"
      }
      close(cmd)
    }
  }
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
  /<script>/,/<\/script>/ { print "[Pulse Instruction Block]"; next }
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

  # Navigation stack
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
