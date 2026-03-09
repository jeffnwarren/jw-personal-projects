#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# rename-ova-on-linux.sh
# Renames a VMware OVA and all its internal files/references so the VM appears
# under a chosen name when imported into VMware Workstation/ESXi on Linux.
#
# Adapted from rename-ova-on-mac.zsh for Linux/bash.
# Created: 2026-03-09  |  Tested on: Linux (bash)
# Author context: developed interactively with GitHub Copilot (Claude Sonnet 4.6)
#
# WHAT THIS SCRIPT DOES
#   1. Extracts the OVA (a tar archive) to a temp directory.
#   2. Renames the .ovf, .vmdk, and .nvram files to the new base name.
#   3. Updates all internal OVF XML references (<Name>, <VirtualSystemIdentifier>,
#      ovf:href file references) to match the new name.
#   4. Regenerates the .mf manifest in VMware's required format:
#        SHA256(filename)= hexhash   (NOT the raw sha256sum output format)
#   5. Repacks the OVA using GNU tar with --format=gnu to suppress PaxHeader/
#      extended-attribute entries that can cause VMware XML parse errors.
#      The OVF descriptor is packed first and the manifest last, per the OVF spec.
#
# WHAT IT HANDLES
#   - INPUT must be a single-archive .ova file. OVF-style exports (a loose folder
#     of .ovf / .vmdk / .mf files) are a different format and not handled here;
#     use ovftool to convert an OVF folder to OVA first if needed.
#   - EFI/UEFI firmware VMs: preserves the .nvram file (required for EFI boot;
#     deleting it breaks the VM — a known failure mode of earlier scripts)
#   - Single-file (monolithic) VMDKs — the standard output of ovftool exports
#   - Split-disk VMDKs (multiple -s001.vmdk etc.) are NOT currently supported
#
# LOGGING
#   Set LOG_FILE (below) to a path to capture all output to a file simultaneously.
#   Leave it empty to print to terminal only.
#
# ── HOW TO USE ────────────────────────────────────────────────────────────────
# Option A — set the variables below, then run:  bash rename-ova-on-linux.sh
# Option B — pass as CLI arguments:  bash rename-ova-on-linux.sh <input.ova> <new-name>
#
# Example (Option A): INPUT_OVA="Windows10JWvm.ova"  NEW_NAME="jeff-win10"
# Example (Option B): bash rename-ova-on-linux.sh Windows10JWvm.ova jeff-win10
#
# DRY RUN — preview all renames and OVF XML changes without writing anything:
#   Set DRY_RUN="1" above, or pass --dry-run as the first CLI argument:
#   bash rename-ova-on-linux.sh --dry-run Windows10JWvm.ova jeff-win10
#   Only the small .ovf (~14 KB) is extracted to show the XML diff — the
#   large VMDK is never touched. Completes in seconds on any size OVA.
# ─────────────────────────────────────────────────────────────────────────────

# ── USER VARIABLES ────────────────────────────────────────────────────────────
INPUT_OVA=""        # e.g. "Windows10JWvm.ova"      (leave empty to use CLI arg)
NEW_NAME=""         # e.g. "jeff-win10"              (leave empty to use CLI arg)
LOG_FILE=""         # e.g. "rename-ova.log"          (leave empty for no log file)
DRY_RUN=""          # set to "1" to preview without writing anything
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── logging setup ────────────────────────────────────────────────────────────
if [[ -n "$LOG_FILE" ]]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "$(date '+%Y-%m-%d %H:%M:%S') — rename-ova-on-linux.sh started" >> "$LOG_FILE"
fi

# ── resolve arguments (CLI args override blank variables) ────────────────────
if [[ $# -ge 1 && "$1" == "--dry-run" ]]; then
    DRY_RUN="1"
    shift
fi
[[ -z "$INPUT_OVA" && $# -ge 1 ]] && INPUT_OVA="$1"
[[ -z "$NEW_NAME"  && $# -ge 2 ]] && NEW_NAME="$2"

if [[ -z "$INPUT_OVA" || -z "$NEW_NAME" ]]; then
    echo "Usage: $0 [--dry-run] <input.ova> <new-vm-name>"
    echo "   or: set INPUT_OVA and NEW_NAME at the top of the script."
    echo "Example: $0 Windows10JWvm.ova jeff-win10"
    echo "Example: $0 --dry-run Windows10JWvm.ova jeff-win10"
    exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_OVA="$SCRIPT_DIR/$NEW_NAME.ova"

# ── sanity checks ─────────────────────────────────────────────────────────────
[[ -f "$INPUT_OVA" ]] || { echo "ERROR: '$INPUT_OVA' not found."; exit 1; }
[[ "$INPUT_OVA" == *.ova ]] || { echo "ERROR: Input file must have .ova extension."; exit 1; }

if [[ -f "$OUTPUT_OVA" && -z "$DRY_RUN" ]]; then
    echo "WARNING: '$OUTPUT_OVA' already exists and will be overwritten."
    read -r -p "Continue? (y/n) " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# ── dry run ───────────────────────────────────────────────────────────────────
if [[ -n "$DRY_RUN" ]]; then
    echo "════════════════════════════════════════════════════════════════════"
    echo "  DRY RUN — no files will be written"
    echo "  Input : $INPUT_OVA"
    echo "  Output: $OUTPUT_OVA  (would be created)"
    echo "════════════════════════════════════════════════════════════════════"
    echo

    echo "── Current OVA contents ─────────────────────────────────────────────"
    tar -tvf "$INPUT_OVA"
    echo

    local_ovf=$(tar -tf "$INPUT_OVA" | grep '\.ovf$' | head -1)
    local_base="${local_ovf%.ovf}"

    echo "── File renames ─────────────────────────────────────────────────────"
    tar -tf "$INPUT_OVA" | while read -r entry; do
        new_entry="${entry/$local_base/$NEW_NAME}"
        if [[ "$entry" == *.nvram ]]; then
            printf "  %-52s → %s  (KEPT — required for EFI)\n" "$entry" "$new_entry"
        elif [[ "$entry" == *.mf ]]; then
            printf "  %-52s → %s  (regenerated)\n" "$entry" "$new_entry"
        else
            printf "  %-52s → %s\n" "$entry" "$new_entry"
        fi
    done
    echo

    echo "── OVF XML changes (key fields only) ───────────────────────────────"
    DRY_TMP=$(mktemp -d)
    trap 'rm -rf "$DRY_TMP"' EXIT
    tar -xOf "$INPUT_OVA" "$local_ovf" > "$DRY_TMP/original.ovf"
    sed \
        -e "s|${local_base}|${NEW_NAME}|g" \
        -e "s|<Name>[^<]*</Name>|<Name>${NEW_NAME}</Name>|g" \
        -e "s|<vssd:VirtualSystemIdentifier>[^<]*</vssd:VirtualSystemIdentifier>|<vssd:VirtualSystemIdentifier>${NEW_NAME}</vssd:VirtualSystemIdentifier>|g" \
        "$DRY_TMP/original.ovf" > "$DRY_TMP/new.ovf"
    diff "$DRY_TMP/original.ovf" "$DRY_TMP/new.ovf" | grep '^[<>]' | head -20 || true
    echo
    echo "── Manifest would be regenerated as ────────────────────────────────"
    echo "  SHA256($NEW_NAME.ovf)= <recomputed>"
    echo "  SHA256($NEW_NAME-disk1.vmdk)= <recomputed>"
    local_nvram=$(tar -tf "$INPUT_OVA" | grep '\.nvram$' | head -1)
    [[ -n "$local_nvram" ]] && echo "  SHA256(${local_nvram/$local_base/$NEW_NAME})= <recomputed>"
    echo
    echo "════════════════════════════════════════════════════════════════════"
    echo "  DRY RUN COMPLETE — nothing was written"
    echo "  Remove --dry-run (or DRY_RUN=\"1\") to perform the actual rename."
    echo "════════════════════════════════════════════════════════════════════"
    exit 0
fi

# ── extract ───────────────────────────────────────────────────────────────────
TMP_DIR=$(mktemp -d)
trap 'echo "Cleaning up $TMP_DIR ..."; rm -rf "$TMP_DIR"' EXIT

echo "Extracting '$INPUT_OVA' → $TMP_DIR ..."
tar -xf "$INPUT_OVA" -C "$TMP_DIR"
cd "$TMP_DIR"

# ── discover internal files ───────────────────────────────────────────────────
shopt -s nullglob
ovf_files=(*.ovf)
vmdk_files=(*-disk1.vmdk *.vmdk)
nvram_files=(*.nvram)
mf_files=(*.mf)
shopt -u nullglob

OVF_FILE="${ovf_files[0]:-}"
VMDK_FILE="${vmdk_files[0]:-}"
NVRAM_FILE="${nvram_files[0]:-}"   # may be empty — kept if present
MF_FILE="${mf_files[0]:-}"         # old manifest — will be replaced

[[ -n "$OVF_FILE"  ]] || { echo "ERROR: No .ovf file found in OVA.";  exit 1; }
[[ -n "$VMDK_FILE" ]] || { echo "ERROR: No .vmdk file found in OVA."; exit 1; }

echo "Found: $OVF_FILE | $VMDK_FILE${NVRAM_FILE:+ | $NVRAM_FILE}"

OLD_BASE="${OVF_FILE%.ovf}"

# ── rename files ──────────────────────────────────────────────────────────────
echo "Renaming files to '$NEW_NAME' ..."

NEW_OVF="$NEW_NAME.ovf"
mv "$OVF_FILE" "$NEW_OVF"

NEW_VMDK="${VMDK_FILE/$OLD_BASE/$NEW_NAME}"
mv "$VMDK_FILE" "$NEW_VMDK"

NEW_NVRAM=""
if [[ -n "$NVRAM_FILE" ]]; then
    NEW_NVRAM="${NVRAM_FILE/$OLD_BASE/$NEW_NAME}"
    mv "$NVRAM_FILE" "$NEW_NVRAM"
fi

[[ -n "$MF_FILE" ]] && rm -f "$MF_FILE"

# ── update OVF references ─────────────────────────────────────────────────────
echo "Updating OVF internal references ..."

# GNU sed on Linux uses -i without a suffix (unlike macOS BSD sed which needs -i '')
sed -i \
    -e "s|${OLD_BASE}|${NEW_NAME}|g" \
    -e "s|<Name>[^<]*</Name>|<Name>${NEW_NAME}</Name>|g" \
    -e "s|<vssd:VirtualSystemIdentifier>[^<]*</vssd:VirtualSystemIdentifier>|<vssd:VirtualSystemIdentifier>${NEW_NAME}</vssd:VirtualSystemIdentifier>|g" \
    "$NEW_OVF"

# ── regenerate manifest ───────────────────────────────────────────────────────
# VMware manifest format (exactly):  SHA256(filename)= hexhash
# sha256sum outputs "hash  filename"; reformat with awk (same as macOS shasum -a 256)
echo "Regenerating manifest ..."
NEW_MF="$NEW_NAME.mf"
: > "$NEW_MF"

for f in "$NEW_OVF" "$NEW_VMDK" ${NEW_NVRAM:+"$NEW_NVRAM"}; do
    sha256sum "$f" | awk '{print "SHA256(" $2 ")= " $1}' >> "$NEW_MF"
done

# ── repack ────────────────────────────────────────────────────────────────────
# OVF spec mandates: OVF descriptor first, manifest LAST.
# --format=gnu suppresses PaxHeader extended-attribute entries that can cause
# VMware's "Line 1: not well-formed (invalid token)" XML parse error.
echo "Repacking → '$OUTPUT_OVA' ..."
tar --format=gnu -cf "$OUTPUT_OVA" \
    "$NEW_OVF" \
    "$NEW_VMDK" \
    ${NEW_NVRAM:+"$NEW_NVRAM"} \
    "$NEW_MF"

echo
echo "Contents of new OVA:"
tar -tvf "$OUTPUT_OVA"
echo
echo "══════════════════════════════════════════════════════════════════"
echo "  RENAME COMPLETE"
echo "  Output : $OUTPUT_OVA"
echo "  Size   : $(du -h "$OUTPUT_OVA" | cut -f1)"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "══════════════════════════════════════════════════════════════════"
[[ -n "$LOG_FILE" ]] && echo "Log saved to: $LOG_FILE"
