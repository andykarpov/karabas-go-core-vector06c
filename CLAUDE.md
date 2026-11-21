# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A core of the Soviet home computer Vector-06C (KR580VM80A 3 MHz, 64 KB RAM + 256 KB RAM disk, 256 x 256 x 16 colours, KR580VI53, 50 Hz frame interrupt, KR1818VG93 floppy) for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST).

Status: skeleton (2026-11-21), phase Ф0 next. Docs, in Russian: `docs/PLAN.md` (research, decisions, architecture, phases), `docs/HARDWARE.md` (ports, memory, video; from Ф0), `docs/BACKLOG.md`. Follow the phases; record a changed decision in PLAN.md.

All file work goes through the firmware (OSD, `FL` / `F` items, burst): no loader or soft CPU in the core. Base: the MiSTer core of Sorgelig (`upstream/vector06_mister`, BSD-2 / GPL-3 / CC-BY per file), brought to our rules; video timing and behaviour checked against svofski's vector06cc (`upstream/vector06cc`, branch tangnano9k-hdmi). Get both with `tools/fetch_upstream.sh` (git-ignored). Keep the upstream headers; mark changed lines `// karabas:`. The core is GPL v3 (`LICENSE`).

Pieces from our cores: `../karabas-go-core-specialist` (tops, Makefile, sram wrapper, wd1793 + fdd cache, sim harness, Z80 option, Go physical FDD), `../karabas-go-core-orion128`.

## Rules of the core

The rules of orion128 / specialist apply: one clock with enables (no `negedge`, no derived clocks), syncs always present, `FT_CLK_OUT` about 8 MHz on Mini / Mini G, Go `FDC_*` outputs 0 when unused, SDRAM idle (Mini G2 `~CS` = FLASH_CS_N, drive 1), OSD switch index = item position unless `"index"`, an OSD value shows 10 characters at most, Verilog-2001 for XST.

- HDMI = the native Vector frame (576p, 624 lines, ~50.08 Hz) by line doubling, no frame buffer (user 2026-11-21).
- ROMs: only the boot loader («Загрузчик») goes into the repo and the `.kg` (user 2026-11-21); others from `/vector06c` on the SD through `FL`.
- `karabas-go-modules` is shared with other sessions: change it only in a git worktree, PR there, then move the submodule.
- Before a step that needs the board or the HDMI capture, tell the user; capture frames only after a yes; ask before a firmware flash.
- One branch per phase of `docs/PLAN.md`, one PR at its end (local master until the repo is public).

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`, `link.sh` there makes the links). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
