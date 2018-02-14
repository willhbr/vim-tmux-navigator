" Maps <C-h/j/k/l> to switch vim splits in the given direction. If there are
" no more windows in that direction, forwards the operation to tmux.
" Additionally, <C-\> toggles between last active vim splits/tmux panes.

if exists("g:loaded_tmux_navigator") || &cp || v:version < 700
  finish
endif
let g:loaded_tmux_navigator = 1

if !exists("g:tmux_navigator_save_on_switch")
  let g:tmux_navigator_save_on_switch = 0
endif

if !exists("g:tmux_navigator_disable_when_zoomed")
  let g:tmux_navigator_disable_when_zoomed = 0
endif

function! s:TmuxOrTmateExecutable()
  return (match($TMUX, 'tmate') != -1 ? 'tmate' : 'tmux')
endfunction

function! s:UseTmuxNavigatorMappings()
  return !get(g:, 'tmux_navigator_no_mappings', 0)
endfunction

function! s:InTmuxSession()
  return $TMUX != ''
endfunction

function! s:TmuxVimPaneIsZoomed()
  return s:TmuxCommand("display-message -p '#{window_zoomed_flag}'") == 1
endfunction

function! s:TmuxSocket()
  " The socket path is the first value in the comma-separated list of $TMUX.
  return split($TMUX, ',')[0]
endfunction

function! s:TmuxCommand(args)
  let cmd = s:TmuxOrTmateExecutable() . ' -S ' . s:TmuxSocket() . ' ' . a:args
  return system(cmd)
endfunction

function! s:TmuxPaneCurrentCommand()
  echo s:TmuxCommand("display-message -p '#{pane_current_command}'")
endfunction
command! TmuxPaneCurrentCommand call s:TmuxPaneCurrentCommand()

let s:tmux_is_last_pane = 0
augroup tmux_navigator
  au!
  autocmd WinEnter * let s:tmux_is_last_pane = 0
augroup END

" Like `wincmd` but also change tmux panes instead of vim windows when needed.
function! s:TmuxWinCmd(direction)
  if s:InTmuxSession()
    call s:TmuxAwareNavigate(a:direction)
  else
    call s:VimNavigate(a:direction)
  endif
endfunction

function! s:NeedsVitalityRedraw()
  return exists('g:loaded_vitality') && v:version < 704 && !has("patch481")
endfunction

function! s:ShouldForwardNavigationBackToTmux(tmux_last_pane, at_tab_page_edge)
  if g:tmux_navigator_disable_when_zoomed && s:TmuxVimPaneIsZoomed()
    return 0
  endif
  return a:tmux_last_pane || a:at_tab_page_edge
endfunction

function! s:TmuxAwareNavigate(direction)
  let nr = winnr()
  let tmux_last_pane = (a:direction == 'p' && s:tmux_is_last_pane)
  if !tmux_last_pane
    call s:VimNavigate(a:direction)
  endif
  let at_tab_page_edge = (nr == winnr())
  " Forward the switch panes command to tmux if:
  " a) we're toggling between the last tmux pane;
  " b) we tried switching windows in vim but it didn't have effect.
  if s:ShouldForwardNavigationBackToTmux(tmux_last_pane, at_tab_page_edge)
    if g:tmux_navigator_save_on_switch == 1
      try
        update " save the active buffer. See :help update
      catch /^Vim\%((\a\+)\)\=:E32/ " catches the no file name error
      endtry
    elseif g:tmux_navigator_save_on_switch == 2
      try
        wall " save all the buffers. See :help wall
      catch /^Vim\%((\a\+)\)\=:E141/ " catches the no file name error
      endtry
    endif
    let args = 'select-pane -t ' . shellescape($TMUX_PANE) . ' -' . tr(a:direction, 'phjkl', 'lLDUR')
    silent call s:TmuxCommand(args)
    if s:NeedsVitalityRedraw()
      redraw!
    endif
    let s:tmux_is_last_pane = 1
  else
    let s:tmux_is_last_pane = 0
  endif
endfunction

function! s:VimNavigate(direction)
  try
    execute 'wincmd ' . a:direction
  catch
    echohl ErrorMsg | echo 'E11: Invalid in command-line window; <CR> executes, CTRL-C quits: wincmd k' | echohl None
  endtry
endfunction

let s:vim_to_tmux ={ '<':'-L', '>':'-R', '+':'-D', '-':'-U' }
function! s:TmuxAwareResize(sign, amount)
  if winnr('$') == 1
    "only one vim window, go straight to tmux
    let l:pass_to_tmux = 1
  els
    " save the original window index
    let initial = winnr()
    let isvert = (a:sign =~ '<\|>') ? 'vertical ' : ''
    let anchor = (isvert == 'vertical ') ? 'h' : 'k'
    let prefix = (a:sign =~ '<\|-') ? '-' : '+'
    execute 'noautocmd wincmd ' . anchor
    "did find other window towards anchor point
    if winnr()	!= initial
      "edge case: trying to resize from bottom/right window if have three, flips. so test moving again...
      "DUMB: breaks again with four in a row. should prob handle that, then give up because fuck the kind of person with five windows in one single dimension
      let new = winnr() | execute 'noautocmd wincmd ' . anchor
      "did find third win. Anchor is flipped, so change strategy
      if winnr() != new
        execute 'noautocmd ' . initial . 'wincmd w'
        execute 'noautocmd ' . isvert . 'resize ' .(prefix == '+' ? '-' : '+').a:amount
        "no third window this direction
      else
        execute 'noautocmd ' . isvert . 'resize ' .prefix.a:amount
        execute 'noautocmd ' . initial . 'wincmd w'
      endif
    else
      "try other side
      execute 'wincmd ' . (anchor == 'h' ? 'l' : 'j')
      "moved away from anchor. switch back, then resize
      if winnr() != initial
        execute 'noautocmd ' . initial . 'wincmd w'
        execute 'noautocmd ' . isvert . ' resize ' .prefix.a:amount
      else
        let pass_to_tmux = 1
      endif
    endif
  endif

  if get(l:, 'pass_to_tmux', 0)
    let args = 'resize-pane ' . s:vim_to_tmux[a:sign] .' '. a:amount
    call s:TmuxCommand(args)
  endif
endfunction

command! TmuxNavigateLeft call s:TmuxWinCmd('h')
command! TmuxNavigateDown call s:TmuxWinCmd('j')
command! TmuxNavigateUp call s:TmuxWinCmd('k')
command! TmuxNavigateRight call s:TmuxWinCmd('l')
command! TmuxNavigatePrevious call s:TmuxWinCmd('p')

command! TmuxResizeLeft call s:TmuxAwareResize('<', 1)
command! TmuxResizeDown call s:TmuxAwareResize('+', 1)
command! TmuxResizeUp call s:TmuxAwareResize('-', 1)
command! TmuxResizeRight call s:TmuxAwareResize('>', 1)

if s:UseTmuxNavigatorMappings()
  inoremap <silent> <c-h> <c-o>:TmuxNavigateLeft<cr>
  inoremap <silent> <c-j> <c-o>:TmuxNavigateDown<cr>
  inoremap <silent> <c-k> <c-o>:TmuxNavigateUp<cr>
  inoremap <silent> <c-l> <c-o>:TmuxNavigateRight<cr>
  inoremap <silent> <c-\> <c-o>:TmuxNavigatePrevious<cr>

  nnoremap <silent> <c-h> :TmuxNavigateLeft<cr>
  nnoremap <silent> <c-j> :TmuxNavigateDown<cr>
  nnoremap <silent> <c-k> :TmuxNavigateUp<cr>
  nnoremap <silent> <c-l> :TmuxNavigateRight<cr>
  nnoremap <silent> <c-\> :TmuxNavigatePrevious<cr>

  inoremap <silent> <M-h> <c-o>:TmuxResizeLeft<cr>
  inoremap <silent> <M-j> <c-o>:TmuxResizeDown<cr>
  inoremap <silent> <M-k> <c-o>:TmuxResizeUp<cr>
  inoremap <silent> <M-l> <c-o>:TmuxResizeRight<cr>

  nnoremap <M-h> :TmuxResizeLeft<cr>
  nnoremap <M-j> :TmuxResizeDown<cr>
  nnoremap <M-k> :TmuxResizeUp<cr>
  nnoremap <M-l> :TmuxResizeRight<cr>
endif
