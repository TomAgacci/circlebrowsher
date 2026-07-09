#!/bin/sh
# ai_halfcell_4micro_raster.sh
# 4‑micro‑pixel, AI‑driven half‑cell glyph system:
# - 4 logical micro‑pixels per half cell (2x2)
# - AI maps micro‑pixels → glyph ID (pattern)
# - AI maps micro‑pixels → ANSI color
# - two half cells → one full cell
# - full cells → full image

die(){ echo "error: $*" >&2; exit 1; }

[ $# -lt 1 ] && die "usage: ai_halfcell_4micro_raster.sh image.jpg"

IMG="$1"

# Terminal geometry
if command -v tput >/dev/null 2>&1; then
    COLS=$(tput cols 2>/dev/null || echo 80)
    ROWS=$(tput lines 2>/dev/null || echo 24)
else
    COLS=80
    ROWS=24
fi

# Each full cell = 2 half cells (top/bottom)
# Each half cell = 2x2 micro‑pixels → 4 micro‑pixels
# Effective raster: 2x2 per half, 2 halves per cell → 2x4 per full cell
RW=$((2*COLS))
RH=$((4*ROWS))

command -v convert >/dev/null 2>&1 || die "ImageMagick convert required"

TMP=$(mktemp)
convert "$IMG" -resize "${RW}x${RH}!" txt:- > "$TMP" || die "convert failed"

###############################################################################
# LOAD PIXELS (integer RGB)
###############################################################################

while IFS= read -r L; do
    case "$L" in \#*) continue ;; esac
    XY=${L%%:*}
    REST=${L#*:}
    X=${XY%%,*}
    Y=${XY#*,}

    RGB=${REST#*rgb(}
    RGB=${RGB%%)*}

    R=${RGB%%,*}
    T=${RGB#*,}
    G=${T%%,*}
    B=${T#*,}

    R=${R%.*}; G=${G%.*}; B=${B%.*}

    eval "R_${X}_${Y}=$R"
    eval "G_${X}_${Y}=$G"
    eval "B_${X}_${Y}=$B"
done < "$TMP"

brightness(){ echo $((( $1*299 + $2*587 + $3*114 )/1000 )); }

###############################################################################
# AI MICRO‑RASTER: 4 micro‑pixels per half cell (2x2)
###############################################################################
# For each cell (cx,cy):
#   top half: micro pixels at (2cx+i, 4cy+j), i=0..1, j=0..1
#   bottom half: micro pixels at (2cx+i, 4cy+2+j), i=0..1, j=0..1

# We store:
#   HALF_TOP_GID_cx_cy  (glyph ID for top half)
#   HALF_TOP_R_cx_cy, HALF_TOP_G_cx_cy, HALF_TOP_B_cx_cy (color)
#   HALF_BOT_GID_cx_cy, HALF_BOT_R/G/B_cx_cy

ai_micro_to_glyph(){
    # inputs: 4 brightness values (b00 b01 b10 b11)
    b00=$1; b01=$2; b10=$3; b11=$4

    # simple AI heuristic: classify pattern
    # high vs low threshold
    TH=160

    hi00=0; hi01=0; hi10=0; hi11=0
    [ $b00 -gt $TH ] && hi00=1
    [ $b01 -gt $TH ] && hi01=1
    [ $b10 -gt $TH ] && hi10=1
    [ $b11 -gt $TH ] && hi11=1

    sum=$((hi00+hi01+hi10+hi11))

    # pattern mapping
    if [ $sum -eq 0 ]; then
        echo "EMPTY"
    elif [ $sum -eq 4 ]; then
        echo "FULL"
    elif [ $hi00 -eq 1 ] && [ $hi01 -eq 1 ] && [ $hi10 -eq 0 ] && [ $hi11 -eq 0 ]; then
        echo "TOPBAR"
    elif [ $hi00 -eq 0 ] && [ $hi01 -eq 0 ] && [ $hi10 -eq 1 ] && [ $hi11 -eq 1 ]; then
        echo "BOTBAR"
    elif [ $hi00 -eq 1 ] && [ $hi10 -eq 1 ] && [ $hi01 -eq 0 ] && [ $hi11 -eq 0 ]; then
        echo "LEFTBAR"
    elif [ $hi01 -eq 1 ] && [ $hi11 -eq 1 ] && [ $hi00 -eq 0 ] && [ $hi10 -eq 0 ]; then
        echo "RIGHTBAR"
    else
        echo "MIX"
    fi
}

glyph_char(){
    case "$1" in
        EMPTY)    printf " " ;;
        FULL)     printf "█" ;;
        TOPBAR)   printf "▀" ;;
        BOTBAR)   printf "▄" ;;
        LEFTBAR)  printf "▌" ;;
        RIGHTBAR) printf "▐" ;;
        MIX)      printf "▒" ;;
        *)        printf " " ;;
    esac
}

cy=0
while [ $cy -lt $ROWS ]; do
    cx=0
    while [ $cx -lt $COLS ]; do
        # TOP half micro‑pixels (2x2)
        # coords: (2cx+i, 4cy+j), i=0..1, j=0..1
        sR=0; sG=0; sB=0
        b00=0; b01=0; b10=0; b11=0

        # (0,0)
        u=$((2*cx+0)); v=$((4*cy+0))
        eval "R=\$R_${u}_${v}"; eval "G=\$G_${u}_${v}"; eval "B=\$B_${u}_${v}"
        Y=$(brightness $R $G $B); b00=$Y
        sR=$((sR+R)); sG=$((sG+G)); sB=$((sB+B))

        # (1,0)
        u=$((2*cx+1)); v=$((4*cy+0))
        eval "R=\$R_${u}_${v}"; eval "G=\$G_${u}_${v}"; eval "B=\$B_${u}_${v}"
        Y=$(brightness $R $G $B); b01=$Y
        sR=$((sR+R)); sG=$((sG+G)); sB=$((sB+B))

        # (0,1)
        u=$((2*cx+0)); v=$((4*cy+1))
        eval "R=\$R_${u}_${v}"; eval "G=\$G_${u}_${v}"; eval "B=\$B_${u}_${v}"
        Y=$(brightness $R $G $B); b10=$Y
        sR=$((sR+R)); sG=$((sG+G)); sB=$((sB+B))

        # (1,1)
        u=$((2*cx+1)); v=$((4*cy+1))
        eval "R=\$R_${u}_${v}"; eval "G=\$G_${u}_${v}"; eval "B=\$B_${u}_${v}"
        Y=$(brightness $R $G $B); b11=$Y
        sR=$((sR+R)); sG=$((sG+G)); sB=$((sB+B))

        avgR=$((sR/4)); avgG=$((sG/4)); avgB=$((sB/4))
        gid_top=$(ai_micro_to_glyph "$b00" "$b01" "$b10" "$b11")

        eval "HALF_TOP_R_${cx}_${cy}=$avgR"
        eval "HALF_TOP_G_${cx}_${cy}=$avgG"
        eval "HALF_TOP_B_${cx}_${cy}=$avgB"
        eval "HALF_TOP_GID_${cx}_${cy}='$gid_top'"

        # BOTTOM half micro‑pixels (2x2)
        # coords: (2cx+i, 4cy+2+j), i=0..1, j=0..1
        sR=0; sG=0; sB=0
        b00=0; b01=0; b10=0; b11=0

        # (0,0)
        u=$((2*cx+0)); v=$((4*cy+2))
        eval "R=\$R_${u}_${v}"; eval "G=\$G_${u}_${v}"; eval "B=\$B_${u}_${v}"
        Y=$(brightness $R $G $B); b00=$Y
        sR=$((sR+R)); sG=$((sG+G)); sB=$((sB+B))

        # (1,0)
        u=$((2*cx+1)); v=$((4*cy+2))
        eval "R=\$R_${u}_${v}"; eval "G=\$G_${u}_${v}"; eval "B=\$B_${u}_${v}"
        Y=$(brightness $R $G $B); b01=$Y
        sR=$((sR+R)); sG=$((sG+G)); sB=$((sB+B))

        # (0,1)
        u=$((2*cx+0)); v=$((4*cy+3))
        eval "R=\$R_${u}_${v}"; eval "G=\$G_${u}_${v}"; eval "B=\$B_${u}_${v}"
        Y=$(brightness $R $G $B); b10=$Y
        sR=$((sR+R)); sG=$((sG+G)); sB=$((sB+B))

        # (1,1)
        u=$((2*cx+1)); v=$((4*cy+3))
        eval "R=\$R_${u}_${v}"; eval "G=\$G_${u}_${v}"; eval "B=\$B_${u}_${v}"
        Y=$(brightness $R $G $B); b11=$Y
        sR=$((sR+R)); sG=$((sG+G)); sB=$((sB+B))

        avgR=$((sR/4)); avgG=$((sG/4)); avgB=$((sB/4))
        gid_bot=$(ai_micro_to_glyph "$b00" "$b01" "$b10" "$b11")

        eval "HALF_BOT_R_${cx}_${cy}=$avgR"
        eval "HALF_BOT_G_${cx}_${cy}=$avgG"
        eval "HALF_BOT_B_${cx}_${cy}=$avgB"
        eval "HALF_BOT_GID_${cx}_${cy}='$gid_bot'"

        cx=$((cx+1))
    done
    cy=$((cy+1))
done

###############################################################################
# AI MACRO‑RASTER: HALF CELLS → FULL CELLS → FULL IMAGE
###############################################################################
# For each full cell:
#   top glyph/color from HALF_TOP_*
#   bottom glyph/color from HALF_BOT_*
# We render two rows per terminal row: one for top half, one for bottom half.

PULSE=(0 40 80 120 160 200 240 255 240 200 160 120 80 40 0 40 80 120 160 200)

t=0
while :; do
    alpha=${PULSE[$((t%20))]}  # 0..255

    FRAME=""
    cy=0
    while [ $cy -lt $ROWS ]; do
        # top half row
        cx=0
        while [ $cx -lt $COLS ]; do
            eval "R=\$HALF_TOP_R_${cx}_${cy}"
            eval "G=\$HALF_TOP_G_${cx}_${cy}"
            eval "B=\$HALF_TOP_B_${cx}_${cy}"
            eval "gid=\$HALF_TOP_GID_${cx}_${cy}"

            Rm=$(( (R*alpha)/255 ))
            Gm=$(( (G*alpha)/255 ))
            Bm=$(( (B*alpha)/255 ))

            r6=$((Rm*5/255))
            g6=$((Gm*5/255))
            b6=$((Bm*5/255))
            ansi=$((16 + 36*r6 + 6*g6 + b6))

            ch=$(glyph_char "$gid")
            FRAME="$FRAME\033[38;5;${ansi}m${ch}\033[0m"
            cx=$((cx+1))
        done
        FRAME="$FRAME\n"

        # bottom half row
        cx=0
        while [ $cx -lt $COLS ]; do
            eval "R=\$HALF_BOT_R_${cx}_${cy}"
            eval "G=\$HALF_BOT_G_${cx}_${cy}"
            eval "B=\$HALF_BOT_B_${cx}_${cy}"
            eval "gid=\$HALF_BOT_GID_${cx}_${cy}"

            Rm=$(( (R*alpha)/255 ))
            Gm=$(( (G*alpha)/255 ))
            Bm=$(( (B*alpha)/255 ))

            r6=$((Rm*5/255))
            g6=$((Gm*5/255))
            b6=$((Bm*5/255))
            ansi=$((16 + 36*r6 + 6*g6 + b6))

            ch=$(glyph_char "$gid")
            FRAME="$FRAME\033[38;5;${ansi}m${ch}\033[0m"
            cx=$((cx+1))
        done
        FRAME="$FRAME\n"

        cy=$((cy+1))
    done

    printf "\033[2J\033[H%s" "$FRAME"

    t=$((t+1))
    sleep 0.05
done

rm -f "$TMP"
