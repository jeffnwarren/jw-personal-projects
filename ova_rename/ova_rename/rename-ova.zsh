#!/bin/zsh
# ─────────────────────────────────────────────────────────────────────────────
# rename-ova.zsh
# Renames a VMware OVA and all its internal files/references so the VM appears
# under a chosen name when imported into VMware Fusion on macOS.
#
# Created: 2026-02-27  |  Tested on: VMware Fusion 25H2u1 (macOS)
# Author context: developed interactively with GitHub Copilot (Claude Sonnet 4.6)
#
# WHAT THIS SCRIPT DOES
#   1. Extracts the OVA (a tar archive) to a temp directory.
#   2. Renames the .ovf, .vmdk, and .nvram files to the new base name.
#   3. Updates all internal OVF XML references (<Name>, <VirtualSystemIdentifier>,
#      ovf:href file references) to match the new name.
#   4. Regenerates the .mf manifest in VMware's required format:
#        SHA256(filename)= hexhash   (NOT the raw shasum output format)
#   5. Repacks the OVA using GNU tar with two macOS-specific flags that prevent
#      Fusion's "Line 1: not well-formed (invalid token)" XML parse error:
#        - COPYFILE_DISABLE=1      suppresses ._AppleDouble resource-fork entries
#        - --format=gnutar         suppresses PaxHeader/ xattr entries (ustar
#                                  is not used because it has an 8 GB size limit,
#                                  which is too small for large VMDKs)
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
#   - No CD/DVD drive is required. Pre-2013 ESXi required removing the CD before
#     export or import failed; this is no longer an issue in Fusion 13+.
#   - VMware hardware compatibility vmx-22 (Fusion 13+). Not visible in Fusion's
#     GUI — readable in the .vmx file as:  virtualhw.version = "22"
#
# LOGGING
#   Set LOG_FILE (below) to a path to capture all output to a file simultaneously.
#   Leave it empty to print to terminal only.
#   The log is suitable for review by a human or AI when diagnosing errors.
#   Errors from set -e will still print to terminal even if LOG_FILE is set.
#
# ── HOW TO USE ────────────────────────────────────────────────────────────────
# Option A — set the variables below, then run:  zsh rename-ova.zsh
# Option B — pass as CLI arguments:  zsh rename-ova.zsh <input.ova> <new-name>
#
# Example (Option A): INPUT_OVA="Windows10JWvm.ova"  NEW_NAME="jeff-win10"
# Example (Option B): zsh rename-ova.zsh Windows10JWvm.ova jeff-win10
#
# DRY RUN — preview all renames and OVF XML changes without writing anything:
#   Set DRY_RUN="1" above, or pass --dry-run as the first CLI argument:
#   zsh rename-ova.zsh --dry-run Windows10JWvm.ova jeff-win10
#   Only the small .ovf (~14 KB) is extracted to show the XML diff — the
#   large VMDK is never touched. Completes in seconds on any size OVA.
#
# DRY RUN for ovftool import — run ovftool with source only (no target):
#   "$OVFTOOL" jeff-win10.ova
#   Fast, read-only, uses the same internal parser as Fusion. Prints VM name,
#   hardware, disk sizes, and any real errors. (See Step 1 below.)
#
# ── IMPORTING INTO VMWARE FUSION (macOS) ─────────────────────────────────────
# ovftool is bundled inside Fusion and can import without the GUI wizard.
# OVFTOOL="/Applications/VMware Fusion.app/Contents/Library/VMware OVF Tool/ovftool"
#
# Step 1 — Validate (fast, read-only — same parser Fusion uses internally):
#   "$OVFTOOL" jeff-win10.ova 2>&1 | tee ovftool-validate.log
#   Look for "Name: jeff-win10" and no errors. Warnings about ExtraConfig keys
#   are harmless and can be ignored.
#
# Step 2 — Import directly to Fusion's VM library (skips the GUI wizard):
#   "$OVFTOOL" \
#     --acceptAllEulas \
#     --allowAllExtraConfig \
#     --name="jeff-win10" \
#     jeff-win10.ova \
#     "$HOME/Virtual Machines.localized/jeff-win10.vmwarevm" \
#     2>&1 | tee ovftool-import.log
#   Success output ends with:  "Completed successfully"
#   Warnings about ExtraConfig keys and manifest entries are harmless.
#
#   IMPORTANT: Fusion's library folder is ~/Virtual Machines.localized/
#   The .localized suffix is hidden by macOS/Finder (shows as "Virtual Machines").
#   Do NOT use ~/Virtual Machines/ (without .localized) — Fusion won't see it.
#
# Step 3 — Register with Fusion (if VM doesn't appear in the Library after import):
#   open -a "VMware Fusion" \
#     "$HOME/Virtual Machines.localized/jeff-win10.vmwarevm/jeff-win10.vmx"
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') — rename-ova.zsh started" >> "$LOG_FILE"
fi

# ── resolve arguments (CLI args override blank variables) ────────────────────
# Support --dry-run as an optional first CLI argument
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
SCRIPT_DIR="${0:A:h}"            # absolute dir where this script lives
OUTPUT_OVA="$SCRIPT_DIR/$NEW_NAME.ova"

# ── sanity checks ─────────────────────────────────────────────────────────────
[[ -f "$INPUT_OVA" ]] || { echo "ERROR: '$INPUT_OVA' not found."; exit 1; }
[[ "$INPUT_OVA" == *.ova ]] || { echo "ERROR: Input file must have .ova extension."; exit 1; }

if [[ -f "$OUTPUT_OVA" && -z "$DRY_RUN" ]]; then
    echo "WARNING: '$OUTPUT_OVA' already exists and will be overwritten."
    read -q "?Continue? (y/n) " || { echo; echo "Aborted."; exit 0; }
    echo
fi

# ── dry run ───────────────────────────────────────────────────────────────────
# Extracts only the .ovf (small) to preview all changes. VMDK never touched.
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

    # Derive old base name from the OVF entry in the tar listing
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
OVF_FILE=$(print -l *.ovf(N))
VMDK_FILE=$(print -l *-disk1.vmdk(N) *.vmdk(N) | head -1)
NVRAM_FILE=$(print -l *.nvram(N) | head -1)   # may be empty — kept if present
MF_FILE=$(print -l *.mf(N) | head -1)          # old manifest — will be replaced

[[ -n "$OVF_FILE"  ]] || { echo "ERROR: No .ovf file found in OVA.";  exit 1; }
[[ -n "$VMDK_FILE" ]] || { echo "ERROR: No .vmdk file found in OVA."; exit 1; }

echo "Found: $OVF_FILE | $VMDK_FILE${NVRAM_FILE:+ | $NVRAM_FILE}"

# derive the old base name from the OVF filename
OLD_BASE="${OVF_FILE%.ovf}"

# ── rename files ──────────────────────────────────────────────────────────────
echo "Renaming files to '$NEW_NAME' ..."

NEW_OVF="$NEW_NAME.ovf"
mv "$OVF_FILE" "$NEW_OVF"

# VMDK: replace only the leading base name, preserve any suffix like -disk1
NEW_VMDK="${VMDK_FILE/$OLD_BASE/$NEW_NAME}"
mv "$VMDK_FILE" "$NEW_VMDK"

NEW_NVRAM=""
if [[ -n "$NVRAM_FILE" ]]; then
    NEW_NVRAM="${NVRAM_FILE/$OLD_BASE/$NEW_NAME}"
    mv "$NVRAM_FILE" "$NEW_NVRAM"
fi

[[ -n "$MF_FILE" ]] && rm -f "$MF_FILE"   # remove old manifest; we regenerate it

# ── update OVF references ─────────────────────────────────────────────────────
echo "Updating OVF internal references ..."

# Replace every occurrence of the old base name with the new one,
# plus update the two <Name> / <VirtualSystemIdentifier> display-name fields
# to use the new name.
#
# sed -i '' is the macOS/BSD form (no backup suffix needed)

sed -i '' \
    -e "s|${OLD_BASE}|${NEW_NAME}|g" \
    -e "s|<Name>[^<]*</Name>|<Name>${NEW_NAME}</Name>|g" \
    -e "s|<vssd:VirtualSystemIdentifier>[^<]*</vssd:VirtualSystemIdentifier>|<vssd:VirtualSystemIdentifier>${NEW_NAME}</vssd:VirtualSystemIdentifier>|g" \
    "$NEW_OVF"

# ── regenerate manifest ───────────────────────────────────────────────────────
# VMware manifest format (exactly):  SHA256(filename)= hexhash
# Note: shasum -a 256 outputs "hash  filename"; we reformat with awk.
echo "Regenerating manifest ..."
NEW_MF="$NEW_NAME.mf"
: > "$NEW_MF"   # truncate / create

for f in "$NEW_OVF" "$NEW_VMDK" ${NEW_NVRAM:+"$NEW_NVRAM"}; do
    shasum -a 256 "$f" | awk '{print "SHA256(" $2 ")= " $1}' >> "$NEW_MF"
done

# ── repack ────────────────────────────────────────────────────────────────────
# OVF spec mandates: OVF descriptor first, manifest LAST.
# Explicit file list guarantees order and no ./ prefix.
#
# macOS tar pitfalls — both must be addressed:
#   1. ._AppleDouble resource-fork entries  → COPYFILE_DISABLE=1
#   2. PaxHeader/ extended-attribute entries → strip xattrs + --format=gnutar
#      (ustar would fix PaxHeaders but has an 8 GB file size limit — too small
#       for large VMDKs; gnutar handles large files without PaxHeaders)
# Fusion parses the first tar entry as the OVF XML; any binary prefix entry
# causes "Line 1: not well-formed (invalid token)" and import failure.
echo "Stripping macOS extended attributes from output files ..."
xattr -c "$NEW_OVF" "$NEW_VMDK" ${NEW_NVRAM:+"$NEW_NVRAM"} "$NEW_MF" 2>/dev/null || true

echo "Repacking → '$OUTPUT_OVA' ..."
COPYFILE_DISABLE=1 tar --format=gnutar -cf "$OUTPUT_OVA" \
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
