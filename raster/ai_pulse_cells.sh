#!/bin/sh
# ai_pulse_cells.sh
# Pulse-aware AI cell selector for Zero-Circle display lists.

die () { echo "error: $*" >&2; exit 1; }

[ $# -lt 3 ] && die "usage: ai_pulse_cells.sh display.txt pixels.txt time"

DISPLAY="$1"
PIXELS="$2"
TIME="$3"

# Load pixel field into R_x_y, G_x_y, B_x_y
load_pixels () {
    while IFS= read -r line; do
        case "$line" in
            \#*) continue ;;
        esac
        xy=${line%%:*}
        rest=${line#*:}

        x=${xy%%,*}
        y=${xy#*,}

        rgb=${rest#*rgb(}
        rgb=${rgb%%)*}

        R=${rgb%%,*}
        tmp=${rgb#*,}
        G=${tmp%%,*}
        B=${tmp#*,}

        R=${R%.*}; G=${G%.*}; B=${B%.*}

        eval "R_${x}_${y}=$R"
        eval "G_${x}_${y}=$G"
        eval "B_${x}_${y}=$B"
    done < "$PIXELS"
}

load_pixels

# Brightness function
brightness () {
    R=$1; G=$2; B=$3
    awk "BEGIN{print ($R*0.299 + $G*0.587 + $B*0.114)}"
}

# Pulse phase function
pulse_phase () {
    t=$1; t0=$2; t1=$3; curve=$4
    dur=$(awk "BEGIN{print $t1 - $t0}")
    phase=$(awk "BEGIN{print ($t - $t0) % $dur}")
    alpha=$(awk "BEGIN{print $phase / $dur}")

    case "$curve" in
        sin)
            awk "BEGIN{print (sin(3.14159 * $alpha))}"
            ;;
        ease)
            awk "BEGIN{print ($alpha * $alpha * (3 - 2 * $alpha))}"
            ;;
        step)
            awk "BEGIN{print ($alpha < 0.5 ? 0 : 1)}"
            ;;
        linear|*)
            echo "$alpha"
            ;;
    esac
}

# AI scoring function
score_glyph () {
    glyph="$1"
    px="$2"
    py="$3"

    eval "R=\$R_${px}_${py}"
    eval "G=\$G_${px}_${py}"
    eval "B=\$B_${px}_${py}"

    imgY=$(brightness "$R" "$G" "$B")

    case "$glyph" in
        ASCII\(\ \))
            glyphY=0
            ;;
        ASCII\(▀\))
            glyphY=180
            ;;
        ASCII\(▄\))
            glyphY=180
            ;;
        ASCII\(█\))
            glyphY=255
            ;;
        BLOCK\(*\))
            lvl=${glyph#BLOCK(}; lvl=${lvl%)}
            glyphY=$((lvl * 32))
            ;;
        BRAILLE\(*\))
            bits=${glyph#BRAILLE(}; bits=${bits%)}
            # approximate brightness by dot count
            dotcount=$(awk "BEGIN{print gsub(/1/,\"\",sprintf(\"%08d\",$bits))}")
            glyphY=$((dotcount * 32))
            ;;
        *)
            glyphY=128
            ;;
    esac

    awk "BEGIN{print ($imgY - $glyphY)^2}"
}

# Choose best glyph from candidates
choose_best_glyph () {
    px="$1"
    py="$2"
    glyphA="$3"
    glyphB="$4"
    alpha="$5"

    # Interpolate brightness target
    eval "RA=\$R_${px}_${py}"
    eval "GA=\$G_${px}_${py}"
    eval "BA=\$B_${px}_${py}"

    # Candidate set
    candidates="ASCII( ) ASCII(▀) ASCII(▄) ASCII(█) BLOCK(0) BLOCK(4) BLOCK(8)"

    best=""
    bestscore=999999

    for g in $candidates; do
        s=$(score_glyph "$g" "$px" "$py")
        if awk "BEGIN{exit !($s < $bestscore)}"; then
            best="$g"
            bestscore="$s"
        fi
    done

    echo "$best"
}

# Process display list
while IFS= read -r line; do
    set -- $line
    kind="$1"

    case "$kind" in
        DRAW)
            x="$2"; y="$3"; layer="$4"; z="$5"; glyph="$6"
