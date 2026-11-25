#!/bin/zsh
# Prepares, once, what the Neovim tests of F6 load without network (spec F6, C3 and C11):
# lazy.nvim and claudecode.nvim pinned below, in build/nvim-fixtures/ (git-ignored with build/), and an init.lua that
# does what NvChad's does for the installer: `{ import = "plugins" }`, with no installs, checks or network.
#
#   scripts/harnesses/prepare-nvim-fixtures.sh
#
# Idempotent: a checkout at the pinned commit is left as it is.
set -euo pipefail

here=${0:A:h}
target=${here:h:h}/build/nvim-fixtures
lazy_commit=85c7ff3711b730b4030d03144f6db6375044ae82        # lazy.nvim v11.17.5
claudecode_commit=112c0c6046d20e2a76fae2f77ef059530fa19c86  # claudecode.nvim v0.4.0

checkout() {
  local repo=$1 commit=$2 directory=$3
  if [[ "$(git -C $directory rev-parse HEAD 2>/dev/null)" == $commit ]]; then return; fi
  rm -rf $directory
  git clone -q --filter=blob:none https://github.com/$repo $directory
  git -C $directory -c advice.detachedHead=false checkout -q $commit
}

mkdir -p $target/plugins
checkout folke/lazy.nvim $lazy_commit $target/lazy.nvim
checkout coder/claudecode.nvim $claudecode_commit $target/plugins/claudecode.nvim

cat >$target/init.lua <<'EOF'
-- Loads the user's lua/plugins/*.lua the way NvChad does, from the plugins prepared by prepare-nvim-fixtures.sh.
local fixtures = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.rtp:prepend(fixtures .. "/lazy.nvim")
require("lazy").setup({ { import = "plugins" } }, {
  root = fixtures .. "/plugins",
  install = { missing = false },
  checker = { enabled = false },
  change_detection = { enabled = false },
  rocks = { enabled = false },
  pkg = { enabled = false },
  performance = { reset_packpath = false },
})
EOF
echo "nvim fixtures ready in $target"
