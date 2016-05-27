if exists("g:loaded_vimwiki") | finish | endif
let g:loaded_vimwiki = 1

let s:old_cpo = &cpo
set cpo&vim

command! -count=1 VimwikiIndex              call vimwiki#base#goto_index(v:count1)
command! -count=1 VimwikiDiaryIndex         call vimwiki#diary#goto_diary_index(v:count1)
command! -count=1 VimwikiMakeDiaryNote      call vimwiki#diary#make_note(v:count1)
command!          VimwikiDiaryGenerateLinks call vimwiki#diary#generate_diary_section()

nnoremap <silent><unique> <leader>ww         :VimwikiIndex<CR>
nnoremap <silent><unique> <leader>wi         :VimwikiDiaryIndex<CR>
nnoremap <silent><unique> <leader>w<leader>i :VimwikiDiaryGenerateLinks<CR>
nnoremap <silent><unique> <leader>w<leader>w :VimwikiMakeDiaryNote<CR>

" Clear FlexWiki's stuff
augroup filetypedetect
  autocmd! * *.wiki
augroup END

augroup vimwiki
  autocmd!
  autocmd BufEnter           *.wiki call s:setup_buffer_reenter()
  autocmd BufWinEnter        *.wiki call s:setup_buffer_enter()
  autocmd BufLeave,BufHidden *.wiki call s:setup_buffer_leave()
  autocmd BufNewFile,BufRead *.wiki call s:setup_filetype()
  autocmd ColorScheme        *.wiki call s:setup_cleared_syntax()
augroup END

" HELPER functions {{{
function! s:default(varname, value) "{{{
  if !exists('g:vimwiki_'.a:varname)
    let g:vimwiki_{a:varname} = a:value
  endif
endfunction "}}}

function! s:path_html(idx) "{{{
  let path_html = VimwikiGet('path_html', a:idx)
  if !empty(path_html)
    return path_html
  else
    let path = VimwikiGet('path', a:idx)
    return substitute(path, '[/\\]\+$', '', '').'_html/'
  endif
endfunction "}}}

function! s:normalize_path(path) "{{{
  " resolve doesn't work quite right with symlinks ended with / or \
  let path = substitute(a:path, '[/\\]\+$', '', '')
  if path !~# '^scp:'
    return resolve(expand(path)).'/'
  else
    return path.'/'
  endif
endfunction "}}}

function! Validate_wiki_options(idx) " {{{
  call VimwikiSet('path', s:normalize_path(VimwikiGet('path', a:idx)), a:idx)
  call VimwikiSet('path_html', s:normalize_path(s:path_html(a:idx)), a:idx)
  call VimwikiSet('template_path',
        \ s:normalize_path(VimwikiGet('template_path', a:idx)), a:idx)
  call VimwikiSet('diary_rel_path',
        \ s:normalize_path(VimwikiGet('diary_rel_path', a:idx)), a:idx)
endfunction " }}}

function! s:vimwiki_idx() " {{{
  if exists('b:vimwiki_idx')
    return b:vimwiki_idx
  else
    return -1
  endif
endfunction " }}}

function! s:setup_buffer_leave() "{{{
  if &filetype ==? 'vimwiki'
    " cache global vars of current state XXX: SLOW!?
    call vimwiki#base#cache_buffer_state()
  endif

  let &autowriteall = s:vimwiki_autowriteall
endfunction "}}}

function! s:setup_filetype() "{{{
  " Find what wiki current buffer belongs to.
  let path = expand('%:p:h')
  let idx = vimwiki#base#find_wiki(path)

  if idx == -1 && g:vimwiki_global_ext == 0
    return
  endif
  "XXX when idx = -1? (an orphan page has been detected)

  "TODO: refactor (same code in setup_buffer_enter)
  " The buffer's file is not in the path and user *does* want his wiki
  " extension(s) to be global -- Add new wiki.
  if idx == -1
    let ext = '.'.expand('%:e')
    " lookup syntax using g:vimwiki_ext2syntax
    if has_key(g:vimwiki_ext2syntax, ext)
      let syn = g:vimwiki_ext2syntax[ext]
    else
      let syn = s:vimwiki_defaults.syntax
    endif
    call add(g:vimwiki_list, {'path': path, 'ext': ext, 'syntax': syn, 'temp': 1})
    let idx = len(g:vimwiki_list) - 1
    call Validate_wiki_options(idx)
  endif
  " initialize and cache global vars of current state
  call vimwiki#base#setup_buffer_state(idx)

  unlet! b:vimwiki_fs_rescan
  set filetype=vimwiki
endfunction "}}}

function! s:setup_buffer_enter() "{{{
  if !vimwiki#base#recall_buffer_state()
    " Find what wiki current buffer belongs to.
    " If wiki does not exist in g:vimwiki_list -- add new wiki there with
    " buffer's path and ext.
    " Else set g:vimwiki_current_idx to that wiki index.
    let path = expand('%:p:h')
    let idx = vimwiki#base#find_wiki(path)

    " The buffer's file is not in the path and user *does NOT* want his wiki
    " extension to be global -- Do not add new wiki.
    if idx == -1 && g:vimwiki_global_ext == 0
      return
    endif

    "TODO: refactor (same code in setup_filetype)
    " The buffer's file is not in the path and user *does* want his wiki
    " extension(s) to be global -- Add new wiki.
    if idx == -1
      let ext = '.'.expand('%:e')
      " lookup syntax using g:vimwiki_ext2syntax
      if has_key(g:vimwiki_ext2syntax, ext)
        let syn = g:vimwiki_ext2syntax[ext]
      else
        let syn = s:vimwiki_defaults.syntax
      endif
      call add(g:vimwiki_list, {'path': path, 'ext': ext, 'syntax': syn, 'temp': 1})
      let idx = len(g:vimwiki_list) - 1
      call Validate_wiki_options(idx)
    endif
    " initialize and cache global vars of current state
    call vimwiki#base#setup_buffer_state(idx)

  endif

  " If you have
  "     au GUIEnter * VimwikiIndex
  " Then change it to
  "     au GUIEnter * nested VimwikiIndex
  if &filetype == ''
    set filetype=vimwiki
  elseif &syntax ==? 'vimwiki'
    " to force a rescan of the filesystem which may have changed
    " and update VimwikiLinks syntax group that depends on it;
    " b:vimwiki_fs_rescan indicates that setup_filetype() has not been run
    if exists("b:vimwiki_fs_rescan") && VimwikiGet('maxhi')
      set syntax=vimwiki
    endif
    let b:vimwiki_fs_rescan = 1
  endif

  " And conceal level too.
  if g:vimwiki_conceallevel && exists("+conceallevel")
    let &conceallevel = g:vimwiki_conceallevel
  endif
endfunction "}}}

function! s:setup_buffer_reenter() "{{{
  if !vimwiki#base#recall_buffer_state()
    " Do not repeat work of s:setup_buffer_enter() and s:setup_filetype()
    " Once should be enough ...
  endif
  if !exists("s:vimwiki_autowriteall")
    let s:vimwiki_autowriteall = &autowriteall
  endif
  let &autowriteall = g:vimwiki_autowriteall
endfunction "}}}

function! s:setup_cleared_syntax() "{{{ highlight groups that get cleared
  " on colorscheme change because they are not linked to Vim-predefined groups
  hi def VimwikiBold term=bold cterm=bold gui=bold
  hi def VimwikiItalic term=italic cterm=italic gui=italic
  hi def VimwikiBoldItalic term=bold cterm=bold gui=bold,italic
  hi def VimwikiUnderline gui=underline
  if g:vimwiki_hl_headers == 1
    for i in range(1,6)
      execute 'hi def VimwikiHeader'.i.' guibg=bg guifg='.g:vimwiki_hcolor_guifg_{&bg}[i-1].' gui=bold ctermfg='.g:vimwiki_hcolor_ctermfg_{&bg}[i-1].' term=bold cterm=bold'
    endfor
  endif
endfunction "}}}

" OPTION get/set functions {{{
" return complete list of options
function! VimwikiGetOptionNames() "{{{
  return keys(s:vimwiki_defaults)
endfunction "}}}

function! VimwikiGetOptions(...) "{{{
  let idx = a:0 == 0 ? g:vimwiki_current_idx : a:1
  let option_dict = {}
  for kk in keys(s:vimwiki_defaults)
    let option_dict[kk] = VimwikiGet(kk, idx)
  endfor
  return option_dict
endfunction "}}}

" Return value of option for current wiki or if second parameter exists for
"   wiki with a given index.
" If the option is not found, it is assumed to have been previously cached in a
"   buffer local dictionary, that acts as a cache.
" If the option is not found in the buffer local dictionary, an error is thrown
function! VimwikiGet(option, ...) "{{{
  let idx = a:0 == 0 ? g:vimwiki_current_idx : a:1

  if has_key(g:vimwiki_list[idx], a:option)
    let val = g:vimwiki_list[idx][a:option]
  elseif has_key(s:vimwiki_defaults, a:option)
    let val = s:vimwiki_defaults[a:option]
    let g:vimwiki_list[idx][a:option] = val
  else
    let val = b:vimwiki_list[a:option]
  endif

  " XXX no call to vimwiki#base here or else the whole autoload/base gets loaded!
  return val
endfunction "}}}

" Set option for current wiki or if third parameter exists for
"   wiki with a given index.
" If the option is not found or recognized (i.e. does not exist in
"   s:vimwiki_defaults), it is saved in a buffer local dictionary, that acts
"   as a cache.
" If the option is not found in the buffer local dictionary, an error is thrown
function! VimwikiSet(option, value, ...) "{{{
  let idx = a:0 == 0 ? g:vimwiki_current_idx : a:1

  if has_key(s:vimwiki_defaults, a:option) ||
        \ has_key(g:vimwiki_list[idx], a:option)
    let g:vimwiki_list[idx][a:option] = a:value
  elseif exists('b:vimwiki_list')
    let b:vimwiki_list[a:option] = a:value
  else
    let b:vimwiki_list = {}
    let b:vimwiki_list[a:option] = a:value
  endif

endfunction "}}}

" Clear option for current wiki or if second parameter exists for
"   wiki with a given index.
" Currently, only works if option was previously saved in the buffer local
"   dictionary, that acts as a cache.
function! VimwikiClear(option, ...) "{{{
  let idx = a:0 == 0 ? g:vimwiki_current_idx : a:1

  if exists('b:vimwiki_list') && has_key(b:vimwiki_list, a:option)
    call remove(b:vimwiki_list, a:option)
  endif

endfunction "}}}
" }}}

function! s:vimwiki_get_known_extensions() " {{{
  " Getting all extensions that different wikis could have
  let extensions = {}
  for wiki in g:vimwiki_list
    if has_key(wiki, 'ext')
      let extensions[wiki.ext] = 1
    else
      let extensions['.wiki'] = 1
    endif
  endfor
  " append map g:vimwiki_ext2syntax
  for ext in keys(g:vimwiki_ext2syntax)
    let extensions[ext] = 1
  endfor
  return keys(extensions)
endfunction " }}}

" }}}

" CALLBACK functions " {{{1

if !exists("*VimwikiLinkHandler")
  function VimwikiLinkHandler(url)
    return 0
  endfunction
endif

if !exists("*VimwikiLinkConverter")
  function VimwikiLinkConverter(url, source, target)
    return ''
  endfunction
endif

if !exists("*VimwikiWikiIncludeHandler")
  function! VimwikiWikiIncludeHandler(value)
    return ''
  endfunction
endif

" }}}1

" DEFAULT wiki {{{
let s:vimwiki_defaults = {}
let s:vimwiki_defaults.path = '~/vimwiki/'
let s:vimwiki_defaults.path_html = ''   " '' is replaced by derived path.'_html/'
let s:vimwiki_defaults.css_name = 'style.css'
let s:vimwiki_defaults.index = 'index'
let s:vimwiki_defaults.ext = '.wiki'
let s:vimwiki_defaults.maxhi = 0
let s:vimwiki_defaults.syntax = 'default'

let s:vimwiki_defaults.template_path = '~/vimwiki/templates/'
let s:vimwiki_defaults.template_default = 'default'
let s:vimwiki_defaults.template_ext = '.tpl'

let s:vimwiki_defaults.nested_syntaxes = {}
let s:vimwiki_defaults.automatic_nested_syntaxes = 1
let s:vimwiki_defaults.auto_export = 0
let s:vimwiki_defaults.auto_toc = 0
" is wiki temporary -- was added to g:vimwiki_list by opening arbitrary wiki
" file.
let s:vimwiki_defaults.temp = 0

" diary
let s:vimwiki_defaults.diary_rel_path = 'diary/'
let s:vimwiki_defaults.diary_index = 'diary'
let s:vimwiki_defaults.diary_header = 'Diary'
let s:vimwiki_defaults.diary_sort = 'desc'

" Do not change this! Will wait till vim become more datetime awareable.
let s:vimwiki_defaults.diary_link_fmt = '%Y-%m-%d'

" NEW! in v2.0
" custom_wiki2html
let s:vimwiki_defaults.custom_wiki2html = ''
"
let s:vimwiki_defaults.list_margin = -1

let s:vimwiki_defaults.auto_tags = 0
"}}}

" DEFAULT options {{{
call s:default('list', [s:vimwiki_defaults])
call s:default('use_mouse', 0)
call s:default('folding', '')
call s:default('global_ext', 1)
call s:default('ext2syntax', {}) " syntax map keyed on extension
call s:default('hl_headers', 0)
call s:default('hl_cb_checked', 0)
call s:default('list_ignore_newline', 1)
call s:default('listsyms', ' .oOX')
call s:default('use_calendar', 1)
call s:default('table_mappings', 1)
call s:default('table_auto_fmt', 1)
call s:default('w32_dir_enc', '')
call s:default('CJK_length', 0)
call s:default('dir_link', '')
call s:default('valid_html_tags', 'b,i,s,u,sub,sup,kbd,br,hr,div,center,strong,em')
call s:default('user_htmls', '')
call s:default('autowriteall', 1)
call s:default('toc_header', 'Contents')

call s:default('html_header_numbering', 0)
call s:default('html_header_numbering_sym', '')
call s:default('conceallevel', 2)
call s:default('url_maxsave', 15)

call s:default('diary_months',
      \ {
      \ 1: 'January', 2: 'February', 3: 'March',
      \ 4: 'April', 5: 'May', 6: 'June',
      \ 7: 'July', 8: 'August', 9: 'September',
      \ 10: 'October', 11: 'November', 12: 'December'
      \ })

call s:default('map_prefix', '<Leader>w')

call s:default('current_idx', 0)

call s:default('auto_chdir', 0)

" Scheme regexes should be defined even if syntax file is not loaded yet
" cause users should be able to <leader>w<leader>w without opening any
" vimwiki file first
" Scheme regexes {{{
call s:default('schemes', 'wiki\d\+,diary,local')
call s:default('web_schemes1', 'http,https,file,ftp,gopher,telnet,nntp,ldap,'.
        \ 'rsync,imap,pop,irc,ircs,cvs,svn,svn+ssh,git,ssh,fish,sftp')
call s:default('web_schemes2', 'mailto,news,xmpp,sip,sips,doi,urn,tel')

let s:rxSchemes = '\%('.
      \ join(split(g:vimwiki_schemes, '\s*,\s*'), '\|').'\|'.
      \ join(split(g:vimwiki_web_schemes1, '\s*,\s*'), '\|').'\|'.
      \ join(split(g:vimwiki_web_schemes2, '\s*,\s*'), '\|').
      \ '\)'

call s:default('rxSchemeUrl', s:rxSchemes.':.*')
call s:default('rxSchemeUrlMatchScheme', '\zs'.s:rxSchemes.'\ze:.*')
call s:default('rxSchemeUrlMatchUrl', s:rxSchemes.':\zs.*\ze')
" scheme regexes }}}

for s:idx in range(len(g:vimwiki_list))
  call Validate_wiki_options(s:idx)
endfor
"}}}

let &cpo = s:old_cpo