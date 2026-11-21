#!/bin/sh
# Fetch the Vector-06C upstream sources into upstream/ (git-ignored), pinned commits.
#  - svofski/vector06cc (BSD + others, see its LICENSE.TXT): the original FPGA replica, Tang Nano 9K HDMI branch
#  - MiSTer-devel/Vector-06C_MiSTer (Sorgelig; BSD-2 / GPL-3 / CC-BY per file): the base of this core
set -eu
cd "$(dirname "$0")/.."
mkdir -p upstream
get() { # dir url commit
	[ -d "upstream/$1/.git" ] || git clone -q "$2" "upstream/$1"
	git -C "upstream/$1" fetch -q origin
	git -C "upstream/$1" checkout -q "$3"
	echo "$1 $(git -C "upstream/$1" rev-parse --short HEAD)"
}
get vector06cc      https://github.com/svofski/vector06cc.git                90815e1452d580cf9ea910de567aa651102d171e # tangnano9k-hdmi
get vector06_mister https://github.com/MiSTer-devel/Vector-06C_MiSTer.git    e88a52f36a9dc0c99dcf1ac1d8d03ec25429769a
echo "upstream ok"
