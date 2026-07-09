#!/bin/sh
# raster3stage.sh
# 3-stage full-color half-cell raster engine:
# Stage 1: 4x4 mini half-cell raster (per half cell)
# Stage 2: 4x8 fused full-cell raster (per cell)
# Stage 3: pulse-aware whole-screen raster

die () { echo "error: $*" >&2; exit 1; }

[ $# -lt 2 ] && die "usage: raster3stage.sh image.jpg time"

IMG="$1"
TIME="$2"

# Terminal geometry
if command -v tput >/dev/null 2>&1; then
    COLS=$(tput cols 2>/dev/null || echo 80)
    ROWS=$(tput lines 2>/dev/null || echo 24)
else
    COLS=80
    ROWS=24
fi

# Effective raster resolution: 4x8 per cell
RASTER_W=$((4 * COLS))
RASTER_H=$((8 * ROWS))

command -v convert >/dev/null 2>&1 || die "ImageMagick 'convert' required"

# Generate scaled pixel dump
PIXELS_TMP=$(mktemp)
convert "$IMG" -resize "${RASTER_W}x${RASTER_H}!" txt:- > "$PIXELS_TMP" || die "convert failed"

# Load pixels into R_x_y, G_x_y, B_x_y
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
    done < "$PIXELS_TMP"
}

brightness () {
    R=$1; G=$2; B=$3
    awk "BEGIN{print ($R*0.299 + $G*0.587 + $B*0.114)}"
}

load_pixels

# Stage 1: 4x4 mini half-cell raster descriptors
# For each cell (cx, cy), we compute two mini rasters: top and bottom (4x4 each)
# We store average color and brightness per half.

# Arrays:
# HALF_TOP_R_cx_cy, HALF_TOP_G_cx_cy, HALF_TOP_B_cx_cy, HALF_TOP_Y_cx_cy
# HALF_BOT_R_cx_cy, HALF_BOT_G_cx_cy, HALF_BOT_B_cx_cy, HALF_BOT_Y_cx_cy

stage1_mini_half_raster () {
    cy=0
    while [ "$cy" -lt "$ROWS" ]; do
        cx=0
        while [ "$cx" -lt "$COLS" ]; do
            # Top half: 4x4 micro pixels
            sumRT=0; sumGT=0; sumBT=0; sumYT=0; countT=0
            j=0
            while [ "$j" -lt 4 ]; do
                i=0
                while [ "$i" -lt 4 ]; do
                    u=$((4*cx + i))
                    v=$((8*cy + j))
                    eval "R=\$R_${u}_${v}"
                    eval "G=\$G_${u}_${v}"
                    eval "B=\$B_${u}_${v}"
                    [ -z "$R" ] && R=0
                    [ -z "$G" ] && G=0
                    [ -z "$B" ] && B=0
                    Y=$(brightness "$R" "$G" "$B")
                    sumRT=$((sumRT + R))
                    sumGT=$((sumGT + G))
                    sumBT=$((sumBT + B))
                    sumYT=$(awk "BEGIN{print $sumYT + $Y}")
                    countT=$((countT + 1))
                    i=$((i+1))
                done
                j=$((j+1))
            done
            [ "$countT" -eq 0 ] && countT=1
            avgRT=$((sumRT / countT))
            avgGT=$((sumGT / countT))
            avgBT=$((sumBT / countT))
            avgYT=$(awk "BEGIN{print $sumYT / $countT}")
            eval "HALF_TOP_R_${cx}_${cy}=$avgRT"
            eval "HALF_TOP_G_${cx}_${cy}=$avgGT"
            eval "HALF_TOP_B_${cx}_${cy}=$avgBT"
            eval "HALF_TOP_Y_${cx}_${cy}=$avgYT"

            # Bottom half: 4x4 micro pixels (rows 4..7)
            sumRB=0; sumGB=0; sumBB=0; sumYB=0; countB=0
            j=4
            while [ "$j" -lt 8 ]; do
                i=0
                while [ "$i" -lt 4 ]; do
                    u=$((4*cx + i))
                    v=$((8*cy + j))
                    eval "R=\$R_${u}_${v}"
                    eval "G=\$G_${u}_${v}"
                    eval "B=\$B_${u}_${v}"
                    [ -z "$R" ] && R=0
                    [ -z "$G" ] && G=0
                    [ -z "$B" ] && B=0
                    Y=$(brightness "$R" "$G" "$B")
                    sumRB=$((sumRB + R))
                    sumGB=$((sumGB + G))
                    sumBB=$((sumBB + B))
                    sumYB=$(awk "BEGIN{print $sumYB + $Y}")
                    countB=$((countB + 1))
                    i=$((i+1))
                done
                j=$((j+1))
            done
            [ "$countB" -eq 0 ] && countB=1
            avgRB=$((sumRB / countB))
            avgGB=$((sumGB / countB))
            avgBB=$((sumBB / countB))
            avgYB=$(awk "BEGIN{print $sumYB / $countB}")
            eval "HALF_BOT_R_${cx}_${cy}=$avgRB"
            eval "HALF_BOT_G_${cx}_${cy}=$avgGB"
            eval "HALF_BOT_B_${cx}_${cy}=$avgBB"
            eval "HALF_BOT_Y_${cx}_${cy}=$avgYB"

            cx=$((cx+1))
        done
        cy=$((cy+1))
    done
}

stage1_mini_half_raster

# Stage 2: fuse two mini half rasters into one full cell descriptor (4x8)
# We compute cell-level average color and brightness, and choose a glyph family.

# CELL_R_cx_cy, CELL_G_cx_cy, CELL_B_cx_cy, CELL_Y_cx_cy
# CELL_GLYPH_cx_cy (ASCII(▀), ASCII(▄), ASCII(█), ASCII( ))

stage2_full_cell_raster () {
    cy=0
    while [ "$cy" -lt "$ROWS" ]; do
        cx=0
        while [ "$cx" -lt "$COLS" ]; do
            eval "RT=\$HALF_TOP_R_${cx}_${cy}"
            eval "GT=\$HALF_TOP_G_${cx}_${cy}"
            eval "BT=\$HALF_TOP_B_${cx}_${cy}"
            eval "YT=\$HALF_TOP_Y_${cx}_${cy}"

            eval "RB=\$HALF_BOT_R_${cx}_${cy}"
            eval "GB=\$HALF_BOT_G_${cx}_${cy}"
            eval "BB=\$HALF_BOT_B_${cx}_${cy}"
            eval "YB=\$HALF_BOT_Y_${cx}_${cy}"

            avgR=$(( (RT + RB) / 2 ))
            avgG=$(( (GT + GB) / 2 ))
            avgB=$(( (BT + BB) / 2 ))
            avgY=$(awk "BEGIN{print ($YT + $YB) / 2}")

            eval "CELL_R_${cx}_${cy}=$avgR"
            eval "CELL_G_${cx}_${cy}=$avgG"
            eval "CELL_B_${cx}_${cy}=$avgB"
            eval "CELL_Y_${cx}_${cy}=$avgY"

            # Simple glyph decision based on top/bottom brightness
            glyph="ASCII( )"
            if awk "BEGIN{exit !($YT > 160 && $YB > 160)}"; then
                glyph="ASCII(█)"
            elif awk "BEGIN{exit !($YT > 160 && $YB <= 160)}"; then
                glyph="ASCII(▀)"
            elif awk "BEGIN{exit !($YT <= 160 && $YB > 160)}"; then
                glyph="ASCII(▄)"
            else
                glyph="ASCII( )"
            fi
            eval "CELL_GLYPH_${cx}_${cy}='$glyph'"

            cx=$((cx+1))
        done
        cy=$((cy+1))
    done
}

stage2_full_cell_raster

# Stage 3: pulse-aware whole-screen raster
# We modulate brightness/color over time using a simple pulse curve.

pulse_phase () {
    t=$1; t0=$2; t1=$3; curve=$4
    dur=$(awk "BEGIN{print $t1 - $t0}")
    phase=$(awk "BEGIN{print ($t - $t0) % $dur}")
    alpha=$(awk "BEGIN{print $phase / $dur}")
    case "$curve" in
        sin)
            awk "BEGIN{print (0.5 + 0.5 * sin(2*3.14159 * $alpha))}"
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

# Render function: emits ANSI escape codes to draw the raster
render_screen () {
    t="$1"
    printf '\033[2J\033[H'
    cy=0
    while [ "$cy" -lt "$ROWS" ]; do
        cx=0
        while [ "$cx" -lt "$COLS" ]; do
            eval "R=\$CELL_R_${cx}_${cy}"
            eval "G=\$CELL_G_${cx}_${cy}"
            eval "B=\$CELL_B_${cx}_${cy}"
            eval "glyph=\$CELL_GLYPH_${cx}_${cy}"

            # Simple pulse: t0=0, t1=2, sin curve
            alpha=$(pulse_phase "$t" 0 2 "sin")

            # Modulate brightness via alpha
            Rm=$(awk "BEGIN{print int($R * $alpha)}")
            Gm=$(awk "BEGIN{print int($G * $alpha)}")
            Bm=$(awk "BEGIN{print int($B * $alpha)}")

            # Map to ANSI 256 color
            r6=$((Rm * 5 / 255))
            g6=$((Gm * 5 / 255))
            b6=$((Bm * 5 / 255))
            ansi=$((16 + 36*r6 + 6*g6 + b6))

            # Extract actual character from glyph
            case "$glyph" in
                ASCII\(\ \)) ch=" " ;;
                ASCII\(▀\)) ch="▀" ;;
                ASCII\(▄\)) ch="▄" ;;
                ASCII\(█\)) ch="█" ;;
                *) ch=" " ;;
            esac

            printf '\033[38;5;%sm' "$ansi"
            printf '\033[%d;%dH%s' "$((cy+1))" "$((cx+1))" "$ch"
            printf '\033[0m'

            cx=$((cx+1))
        done
        cy=$((cy+1))
    done
    printf '\033[%d;1H' $((ROWS+1))
}

# Single-frame render at given TIME
render_screen "$TIME"

rm -f "$PIXELS_TMP"
