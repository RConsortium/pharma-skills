#!/usr/bin/env bash
# Opt-in installer for the Paperclip CLI (the recommended evidence channel). Not run automatically.
command -v paperclip >/dev/null 2>&1 && { echo "paperclip already installed: $(command -v paperclip)"; exit 0; }
echo "Installing paperclip CLI..."; curl -fsSL https://paperclip.gxl.ai/install.sh | bash
