# Sourced by project commands; source may be on SMB, build files stay on this Mac.
sessionbar_source_id=$(printf '%s' "$sessionbar_root" | shasum -a 256 | cut -c1-12)
sessionbar_build_root="${SESSIONBAR_BUILD_ROOT:-$HOME/Library/Caches/sessionbar/$sessionbar_source_id}"
export SESSIONBAR_BUILD_ROOT="$sessionbar_build_root"
