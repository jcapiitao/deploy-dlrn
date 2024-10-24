call plug#begin('~/.vim/plugged')
Plug 'tpope/vim-sensible'
Plug 'nvim-tree/nvim-web-devicons' " optional, for file icons
Plug 'nvim-tree/nvim-tree.lua', { 'tag': 'v1.0' }
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim', { 'tag': '0.1.8' }
call plug#end()

" Don't use swapfile
set noswapfile

" Highlight the screen line of the cursor
set cursorline

" Do not highlight the column of the cursor
set nocursorcolumn

" Allows you to switch from an unsaved buffer without saving it first. 
" Also allows you to keep an undo history for multiple files. Vim will 
" complain if you try to quit without saving, and swap files will keep
" you safe if your computer crashes.
set hidden

" Better command-line completion
set wildmenu

" Show partial commands in the last line of the screen
set showcmd

" Show the current mode
set showmode

" Highlight searches (use <C-L> to temporarily turn off highlighting
set hlsearch

" Allow backspacing over autoindent, line breaks and start of insert action
set backspace=indent,eol,start

" Copy indent from current line when starting a new line
set autoindent

" The cursor is kept in the same column (if possible)
set nostartofline

" Show the line and column number of the cursor position, separated by a comma
set ruler

" Always display the status line, even if only one windows is displayed
set laststatus=2

" Raise a dialogue asking if you wish to save changed files
set confirm

" Set the command window height to 2 lines
set cmdheight=2

" Display line numbers on the left
set number

" Show the line number relative to the line with the cursor in front of line
set relativenumber

" No beeps
set noerrorbells

" Split vertical windows right to the current windows
set splitright

" Split horizontal windows below to the current windows
set splitbelow

" Set default encoding to UTF-8
set encoding=utf-8

" Show the match while typing
set incsearch

" python indent
autocmd BufNewFile,BufRead *.py setlocal tabstop=4 softtabstop=4 shiftwidth=4 textwidth=80 smarttab expandtab

" shell indent
autocmd BufNewFile,BufRead *.sh setlocal tabstop=4 softtabstop=4 shiftwidth=4 smarttab expandtab


"--------------------------------------------------
" Mappings
"

let mapleader = ","

nnoremap <leader>w :w <CR>
nnoremap <leader>x :x <CR>
nnoremap <leader>q :q <CR>
nnoremap <leader>nh :set invhlsearch <CR>
nnoremap <leader>nu :set invnumber <CR>
nnoremap <leader>n :NvimTreeFocus <CR>
nnoremap <leader>ff <cmd>lua require('telescope.builtin').find_files()<cr>
nnoremap <leader>fg <cmd>lua require('telescope.builtin').live_grep()<cr>
nnoremap <leader>fb <cmd>lua require('telescope.builtin').buffers()<cr>
nnoremap <leader>fh <cmd>lua require('telescope.builtin').help_tags()<cr>

" Press jk to escape
imap jk <Esc>

" Disable the key movements
nnoremap <Up> <Nop>
vnoremap <Up> <Nop>
inoremap <Up> <Nop>
nnoremap <Down> <Nop>
vnoremap <Down> <Nop>
inoremap <Down> <Nop>
nnoremap <Left> <Nop>
vnoremap <Left> <Nop>
inoremap <Left> <Nop>
nnoremap <Right> <Nop>
vnoremap <Right> <Nop>
inoremap <Right> <Nop>

" Shortcutting split navigation, saving a keypress:
map <C-h> <C-w>h
map <C-j> <C-w>j
map <C-k> <C-w>k
map <C-l> <C-w>l


" NVim tree config
lua << EOF
-- disable netrw at the very start of your init.lua (strongly advised)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- set termguicolors to enable highlight groups
vim.opt.termguicolors = true

local function my_on_attach(bufnr)
  local api = require "nvim-tree.api"

  local function opts(desc)
    return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
  end

  -- default mappings
  api.config.mappings.default_on_attach(bufnr)

  -- custom mappings
  vim.keymap.set('n', 's', api.node.open.vertical,                opts('Open: Vertical Split'))
  vim.keymap.set('n', 't', api.node.open.tab,                     opts('Open: New Tab'))
end

require("nvim-tree").setup({
  on_attach = my_on_attach,
  sort_by = "case_sensitive",
  view = {
    adaptive_size = true,
  },
  renderer = {
    group_empty = true,
  },
  filters = {
    dotfiles = false,
    custom = { "^.git$" }
  },
  actions = {
    open_file = {
      quit_on_open = false
    }
  }
})
