#!/bin/sh
# raster3stage_fullcolor_pulse_loop.sh
# 3‑Stage full‑color half‑cell raster engine with:
# - 4x4 mini half‑cell raster (per half cell, aspect‑ratio correct)
# - 4x8 fused full‑cell raster (two 4x4 halves)
# - custom glyph atlas (logical mapping to block chars)
# - multi‑frame pulse animation (looping render)

die () { echo "error: $*" >&2; exit 1; }

[ $# -lt 1 ] && die "usage: raster3stage_fullcolor_pulse_loop.sh image.jpg"

IMG="$1"

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

PIXELS_TMP=$(mktemp)
convert "$IMG" -resize "${RASTER_W}x${RASTER_H}!" txt:- > "$PIXELS_TMP" || die "convert failed"

###############################################################################
# LOAD PIXELS
###############################################################################

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

###############################################################################
# CUSTOM GLYPH ATLAS (LOGICAL)
###############################################################################
# We define a small atlas of logical glyph IDs mapped to actual characters.
# In a real custom font, each ID would correspond to a 4x8 bitmap; here we
# approximate with block chars.

glyph_char () {
    id="$1"
    case "$id" in
        EMPTY)  printf " " ;;
        FULL)   printf "█" ;;
        TOP)    printf "▀" ;;
        BOT)    printf "▄" ;;
        MID)    printf "▒" ;;
        LIGHT)  printf "░" ;;
        DARK)   printf "▓" ;;
        *)      printf " " ;;
    esac
}

###############################################################################
# STAGE 1: 4x4 MINI HALF‑CELL RASTER (TOP/BOTTOM) — FULL COLOR
###############################################################################

stage1_precompute () {
    cy=0
    while [ "$cy" -lt "$ROWS" ]; do
        cx=0
        while [ "$cx" -lt "$COLS" ]; do

            # Top half: 4x4 micro pixels (rows 0..3)
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

            eval "TOP_R_${cx}_${cy}=$avgRT"
            eval "TOP_G_${cx}_${cy}=$avgGT"
            eval "TOP_B_${cx}_${cy}=$avgBT"
            eval "TOP_Y_${cx}_${cy}=$avgYT"

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

            eval "BOT_R_${cx}_${cy}=$avgRB"
            eval "BOT_G_${cx}_${cy}=$avgGB"
            eval "BOT_B_${cx}_${cy}=$avgBB"
            eval "BOT_Y_${cx}_${cy}=$avgYB"

            cx=$((cx+1))
        done
        cy=$((cy+1))
    done
}

stage1_precompute

###############################################################################
# STAGE 2: 4x8 FULL‑CELL RASTER (FUSING TWO 4x4 HALF‑CELL MINIS)
###############################################################################

stage2_precompute () {
    cy=0
    while [ "$cy" -lt "$ROWS" ]; do
        cx=0
        while [ "$cx" -lt "$COLS" ]; do

            eval "RT=\$TOP_R_${cx}_${cy}"
            eval "GT=\$TOP_G_${cx}_${cy}"
            eval "BT=\$TOP_B_${cx}_${cy}"
            eval "YT=\$TOP_Y_${cx}_${cy}"

            eval "RB=\$BOT_R_${cx}_${cy}"
            eval "GB=\$BOT_G_${cx}_${cy}"
            eval "BB=\$BOT_B_${cx}_${cy}"
            eval "YB=\$BOT_Y_${cx}_${cy}"

            avgR=$(( (RT + RB) / 2 ))
            avgG=$(( (GT + GB) / 2 ))
            avgB=$(( (BT + BB) / 2 ))
            avgY=$(awk "BEGIN{print ($YT + $YB) / 2}")

            eval "CELL_R_${cx}_${cy}=$avgR"
            eval "CELL_G_${cx}_${cy}=$avgG"
            eval "CELL_B_${cx}_${cy}=$avgB"
            eval "CELL_Y_${cx}_${cy}=$avgY"

            # Map brightness pattern to glyph atlas ID
            glyph_id="EMPTY"
            if awk "BEGIN{exit !($YT > 180 && $YB > 180)}"; then
                glyph_id="FULL"
            elif awk "BEGIN{exit !($YT > 180 && $YB <= 120)}"; then
                glyph_id="TOP"
            elif awk "BEGIN{exit !($YT <= 120 && $YB > 180)}"; then
                glyph_id="BOT"
            elif awk "BEGIN{exit !($avgY > 160 && $avgY <= 200)}"; then
                glyph_id="MID"
            elif awk "BEGIN{exit !($avgY > 200)}"; then
                glyph_id="LIGHT"
            elif awk "BEGIN{exit !($avgY <= 80)}"; then
                glyph_id="DARK"
            else
                glyph_id="EMPTY"
            fi

            eval "CELL_GLYPHID_${cx}_${cy}='$glyph_id'"

            cx=$((cx+1))
        done
        cy=$((cy+1))
    done
}

stage2_precompute

###############################################################################
# STAGE 3: PULSE‑COMPRESSED MULTI‑FRAME RENDERER
###############################################################################

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

render_frame () {
    t="$1"
    printf '\033[2J\033[H'

    cy=0
    while [ "$cy" -lt "$ROWS" ]; do
        cx=0
        while [ "$cx" -lt "$COLS" ]; do

            eval "R=\$CELL_R_${cx}_${cy}"
            eval "G=\$CELL_G_${cx}_${cy}"
            eval "B=\$CELL_B_${cx}_${cy}"
            eval "glyph_id=\$CELL_GLYPHID_${cx}_${cy}"

            alpha=$(pulse_phase "$t" 0 2 "sin")

            Rm=$(awk "BEGIN{print int($R * $alpha)}")
            Gm=$(awk "BEGIN{print int($G * $alpha)}")
            Bm=$(awk "BEGIN{print int($B * $alpha)}")

            r6=$((Rm * 5 / 255))
            g6=$((Gm * 5 / 255))
            b6=$((Bm * 5 / 255))
            ansi=$((16 + 36*r6 + 6*g6 + b6))

            ch=$(glyph_char "$glyph_id")

            printf '\033[38;5;%sm' "$ansi"
            printf '\033[%d;%dH%s' "$((cy+1))" "$((cx+1))" "$ch"
            printf '\033[0m'

            cx=$((cx+1))
        done
        cy=$((cy+1))
    done

    printf '\033[%d;1H' $((ROWS+1))
}

###############################################################################
# MAIN LOOP: MULTI‑FRAME PULSE ANIMATION
###############################################################################

t=0
while :; do
    render_frame "$t"
    t=$(awk "BEGIN{print $t + 0.1}")
    sleep 0.05
done

rm -f "$PIXELS_TMP"
