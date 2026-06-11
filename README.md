<h1 align="center">tabterm.nvim</h1>

<p align="center">
  <b>A tab-scoped floating terminal workspace for Neovim</b>
</p>

`tabterm.nvim` gives each Neovim tabpage its own floating terminal workspace:
a sidebar of terminal tabs on the left, and a panel for the active terminal on
the right.

It is designed for workflows where you want several project-local shells or
one-shot commands available without permanently taking space in the editor
layout.

## Features

- Tab-local workspaces: every tabpage has its own terminal list and active terminal.
- Floating layout with backdrop, sidebar, and terminal panel.
- Shell terminals and one-shot command terminals.
- Sidebar labels with command/title, cwd, status, spinner, and unread result badges.
- Bash and zsh shell integration for prompt state, running command state, cwd,
  title, and exit status tracking.
- Exited command terminals stay visible so their output can be inspected.
- Buffer-local UI keymaps and a small Lua API for custom mappings.
- No external plugin dependencies.

For the full reference, see `:h tabterm`.

## Requirements

- Neovim 0.10 or newer.

## Installation

### vim.pack

```lua
vim.pack.add({
  { src = "https://github.com/kremovtort/tabterm.nvim" },
}, { load = true })

require("tabterm").setup()

vim.keymap.set("n", "<leader>tt", function()
  require("tabterm").toggle()
end, { desc = "Toggle tabterm" })

vim.keymap.set("n", "<leader>tn", function()
  require("tabterm").new_shell()
end, { desc = "New tabterm shell" })

vim.keymap.set("n", "<leader>tc", function()
  require("tabterm").new_command()
end, { desc = "New tabterm command" })
```

### NixVim

`tabterm.nvim` exposes a native NixVim module from its flake. This uses the
generated `plugins.tabterm` option; no `extraPlugins` entry is needed.

Add the plugin as a flake input and import `nixvimModules.default` where you
construct your NixVim configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tabterm = {
      url = "github:kremovtort/tabterm.nvim";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixvim.follows = "nixvim";
    };
  };

  outputs = inputs@{ nixpkgs, nixvim, tabterm, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = nixvim.legacyPackages.${system}.makeNixvimWithModule {
        inherit pkgs;
        module = {
          imports = [
            tabterm.nixvimModules.default
          ];
        };
      };
    };
}
```

Then enable and configure it through `plugins.tabterm` in your NixVim module:

```nix
{
  plugins.tabterm = {
    enable = true;
    settings = {
      ui = {
        border = "round";
        sidebar_width = 30;
        float = {
          width = 0.90;
          height = 0.90;
        };
      };
    };
  };

  keymaps = [
    {
      mode = [
        "n"
        "t"
      ];
      key = "<C-/>";
      action.__raw = ''function() require("tabterm").toggle() end'';
      options.desc = "Toggle tab terminals";
    }
  ];
}
```

### Native packages

```sh
git clone https://github.com/kremovtort/tabterm.nvim \
  ~/.local/share/nvim/site/pack/tabterm/start/tabterm.nvim
```

Then restart Neovim or run `:packloadall`.

## Quick Start

Open the workspace:

```vim
:Tabterm toggle
```

Create a new shell:

```vim
:Tabterm shell
```

Run a one-shot command terminal:

```vim
:Tabterm command git status
```

Inside the workspace:

| Key | Action |
| --- | --- |
| `<C-h>` | Focus the sidebar from the panel |
| `l` or `<C-l>` | Focus the panel from the sidebar |
| `i` / `a` | Insert a shell before / after the current terminal |
| `ci` / `ca` | Insert a command terminal before / after the current terminal |
| `r` | Rename the selected terminal |
| `d` | Delete the selected terminal |
| `q` | Hide the workspace |

Opening an empty workspace creates and starts a default shell terminal. Command
terminals run once and remain available after exit until you close or delete
them.

## Commands

Tabterm exposes one user command, `:Tabterm`, with subcommands:

| Command | Description |
| --- | --- |
| `:Tabterm toggle` | Toggle the current tab's workspace. |
| `:Tabterm open` | Open the workspace and focus the panel. |
| `:Tabterm close` | Hide the workspace and restore the last editor window when possible. |
| `:Tabterm shell` | Create, start, and focus a new shell terminal. |
| `:Tabterm command [cmd]` | Create, start, and focus a one-shot command terminal. Prompts when `cmd` is omitted. |
| `:Tabterm start` | Start the active terminal, or create a shell if none exists. |
| `:Tabterm rename` | Rename the active terminal. |
| `:Tabterm delete` | Delete the active terminal. Running terminals ask for confirmation. |
| `:Tabterm next` | Select the next terminal. |
| `:Tabterm prev` | Select the previous terminal. |

## Lua API

The public module is `require("tabterm")`.

```lua
local tabterm = require("tabterm")

tabterm.setup()

vim.keymap.set("n", "<leader>tt", tabterm.toggle, { desc = "Toggle tabterm" })
vim.keymap.set("n", "<leader>ts", tabterm.new_shell, { desc = "New tabterm shell" })
vim.keymap.set("n", "<leader>tc", tabterm.new_command, { desc = "New tabterm command" })
```

| Function | Description |
| --- | --- |
| `setup(opts)` | Merge options with defaults, define highlights, and install autocmds. |
| `open()` | Open the workspace, creating a default shell if needed. |
| `hide()` | Hide the workspace and restore editor focus when possible. |
| `close()` | Close tabterm's floating windows without focus restoration. |
| `toggle()` | Toggle the workspace. |
| `new_shell(spec?)` | Create and start a shell terminal. |
| `new_command(cmd?)` | Create and start a command terminal, prompting when `cmd` is omitted. |
| `start_active()` | Start or restart the active terminal. |
| `rename_active(name?)` | Rename the active terminal, prompting when `name` is omitted. |
| `delete_active()` | Delete the active terminal. |
| `next_terminal()` | Select the next terminal. |
| `prev_terminal()` | Select the previous terminal. |
| `focus_sidebar()` | Focus the sidebar window. |
| `focus_panel()` | Focus the panel window. |
| `scroll_panel(keys)` | Run a Normal-mode scroll command in the panel window. |

`new_shell()` accepts an optional spec:

```lua
require("tabterm").new_shell({
  cmd = vim.env.SHELL,
  cwd = vim.fn.getcwd(),
  name_override = "server",
  title = "server",
})
```

## Configuration

Calling `setup()` is optional for the default configuration. Commands and API
calls initialize tabterm on demand when needed.

Default configuration:

```lua
require("tabterm").setup({
  ui = {
    border = "single",
    sidebar_width = 30,
    float = {
      width = 0.70,
      height = 0.70,
    },
  },
  shell_integration = {
    enabled = true,
    shells = {
      bash = true,
      zsh = true,
    },
  },
})
```

### UI

| Option | Default | Description |
| --- | --- | --- |
| `ui.border` | `"single"` | Border style. One of `"single"`, `"double"`, `"round"`, or `"none"`. Boolean aliases are accepted: `true` means `"single"`, `false` means `"none"`. |
| `ui.sidebar_width` | `30` | Requested sidebar width in columns. Values are normalized to at least `20`. |
| `ui.float.width` | `0.70` | Fraction of `&columns` used for the floating workspace width. |
| `ui.float.height` | `0.70` | Fraction of `&lines` used for the floating workspace height. |

### Shell Integration

| Option | Default | Description |
| --- | --- | --- |
| `shell_integration.enabled` | `true` | Enable integration for detected supported shell terminals. |
| `shell_integration.shells.bash` | `true` | Enable integration when the shell executable basename is `bash`. |
| `shell_integration.shells.zsh` | `true` | Enable integration when the shell executable basename is `zsh`. |

## Keymaps

Tabterm keymaps are buffer-local and are installed only in tabterm UI buffers.

<details>
<summary>Sidebar keymaps</summary>

Filetype: `tabterm-sidebar`

| Key | Action |
| --- | --- |
| `<CR>` | Select the terminal under the cursor. |
| `i` | Insert a shell before the cursor terminal. |
| `a` | Insert a shell after the cursor terminal. |
| `I` | Insert a shell at the first position. |
| `A` | Insert a shell at the last position. |
| `ci` | Insert a command before the cursor terminal. |
| `ca` | Insert a command after the cursor terminal. |
| `cI` | Insert a command at the first position. |
| `cA` | Insert a command at the last position. |
| `r` | Rename the cursor terminal. |
| `d` | Delete the cursor terminal. |
| `J` | Move the cursor terminal down. |
| `K` | Move the cursor terminal up. |
| `j` / `<Down>` | Move the sidebar cursor down. |
| `k` / `<Up>` | Move the sidebar cursor up. |
| `gg` | Go to terminal 1, or `[count]` when provided. |
| `G` | Go to the last terminal, or `[count]` when provided. |
| `l` / `<C-l>` | Focus the panel. |
| `<C-D>` / `<C-U>` | Scroll the panel half a page down / up. |
| `<C-F>` / `<C-B>` | Scroll the panel one page forward / backward. |
| `q` | Hide the workspace. |

</details>

<details>
<summary>Panel keymaps</summary>

Placeholder panel filetype: `tabterm-panel-placeholder`

| Key | Action |
| --- | --- |
| `<CR>` | Start the active terminal, or create a shell when none exists. |
| `i` / `a` | Insert a shell before / after the active terminal. |
| `I` / `A` | Insert a shell at the first / last position. |
| `ci` / `ca` | Insert a command before / after the active terminal. |
| `cI` / `cA` | Insert a command at the first / last position. |
| `r` | Rename the active terminal. |
| `d` | Delete the active terminal. |
| `<C-h>` | Focus the sidebar. |
| `q` | Hide the workspace. |

Terminal panel filetypes: `tabterm-panel-shell`, `tabterm-panel-command`

| Key | Action |
| --- | --- |
| `<CR>` | Confirm the active terminal. Live terminals enter Insert mode, stopped terminals start, exited command terminals close. |
| `<C-h>` | Focus the sidebar in Normal and Terminal modes. |

</details>

## Filetypes

Tabterm uses these filetypes for its UI buffers:

| Filetype | Purpose |
| --- | --- |
| `tabterm-backdrop` | Background dimmer buffer. |
| `tabterm-sidebar` | Terminal list sidebar. |
| `tabterm-panel-placeholder` | Placeholder panel for empty, stopped, failed, or unavailable terminal states. |
| `tabterm-panel-shell` | Shell terminal panel. |
| `tabterm-panel-command` | Command terminal panel. |

You can target these buffers with normal `FileType` autocmds.

## Highlights

Tabterm defines highlight groups with `default = true`, so colorschemes or user
configuration can override them normally.

| Highlight | Default link / purpose |
| --- | --- |
| `TabtermSidebarNumberActive` | `CursorLineNr` |
| `TabtermSidebarNumberInactive` | `LineNr` |
| `TabtermSidebarCommand` | `String` |
| `TabtermSidebarCwd` | `Directory` |
| `TabtermPanelHeaderMuted` | `Comment` |
| `TabtermPanelHeaderSuccess` | `DiagnosticOk` |
| `TabtermPanelHeaderUnknown` | `DiagnosticInfo` |
| `TabtermPanelHeaderError` | `DiagnosticError` |
| `TabtermSidebar` | `Normal` |
| `TabtermPanel` | `NormalFloat` |
| `TabtermSidebarSuccess` | Success notification badge. |
| `TabtermSidebarUnknown` | Unknown notification badge. |
| `TabtermSidebarLoader` | Waiting spinner badge. |
| `TabtermSidebarError` | Error notification badge. |
| `TabtermSidebarCommandFade1` | First fade cell for truncated command text. |
| `TabtermSidebarCommandFade2` | Second fade cell for truncated command text. |
| `TabtermSidebarCwdFade1` | First fade cell for truncated cwd text. |
| `TabtermSidebarCwdFade2` | Second fade cell for truncated cwd text. |
| `TabtermSidebarHover` | `Visual` |
| `TabtermBackdrop` | Backdrop window background. |

Example override:

```lua
vim.api.nvim_set_hl(0, "TabtermBackdrop", { bg = "#000000" })
vim.api.nvim_set_hl(0, "TabtermSidebarHover", { link = "Visual" })
```

## Help

After installing, open the full help with:

```vim
:h tabterm
```

The help file includes the complete command, API, lifecycle, shell integration,
filetype, and highlight reference.

## License

MPL-2.0
