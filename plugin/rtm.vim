" ============================================================================
" File: RTM.vim
" Description: Vim plugin for Remember The Milk
" Maintainer: Kosei Kitahara <surgo.jp@gmail.com>
" Created: 22 November 2009
" Last Change:  2010-10-12 (pascal@immerzeelpictures.com)
" ============================================================================

let g:rtm_vim_version = "1.1"

let s:save_cpo = &cpo
set cpo&vim

if &compatible
  finish
endif

if exists('rtm_imported')
  finish
endif
let rtm_imported = 1

if !executable("curl")
  echoerr "RTM.vim require 'curl' command"
  finish
endif

if exists('rtm_api_key')
  let s:rtm_api_key = rtm_api_key
else
  echoerr "RTM.vim api key not set. Please set rtm_api_key in .vimrc"
  finish
endif

if exists('rtm_shared_secret')
  let s:rtm_shared_secret = rtm_shared_secret
else
  echoerr "RTM.vim shared secret not set. Please set rtm_shared_secret in .vimrc"
  finish
endif

if exists('rtm_use_smartadd')
    let s:rtm_use_smartadd = rtm_use_smartadd
else
    s:rtm_use_smartadd = 0
endif

let s:rtm_rest_endpoint = "http://api.rememberthemilk.com/services/rest/"
let s:rtm_auth_endpoint = "http://www.rememberthemilk.com/services/auth/"
let s:project_home = "http://bitbucket.org/Surgo/rtm.vim/"
let s:project_issue = s:project_home . 'issues/'
let s:default_err_msg = 'Sorry, but an RTM.vim script error occured. Plese report any issues you have noticed. ' . s:project_issue

function! s:byte(nr)
  if a:nr < 0x80
    return nr2char(a:nr)
  elseif a:nr < 0x800
    return nr2char(a:nr/64+192).nr2char(a:nr%64+128)
  else
    return nr2char(a:nr/4096%16+224).nr2char(a:nr/64%64+128).nr2char(a:nr%64+128)
  endif
endfunction

function! s:char(charcode)
  if &encoding == 'utf-8'
    return nr2char(a:charcode)
  endif
  let char = s:byte(a:charcode)
  if strlen(char) > 1
    let char = strtrans(iconv(char, 'utf-8', &encoding))
  endif
  return char
endfunction

function! s:hex(nr)
  let n = a:nr
  let hex = ""
  while n
    let hex = '0123456789ABCDEF'[n % 16] . hex
    let n = n / 16
  endwhile
  return hex
endfunction

function! s:quote(str)
  let str = iconv(a:str, &enc, "utf-8")
  let len = strlen(str)
  let i = 0
  let safe_str = ''
  while i < len
    let char = str[i]
    if char =~# '[0-9A-Za-z-._~!''()*]'
      let safe_str .= char
     elseif char == ' '
       let safe_str .= '+'
    else
      let safe_str .= '%' . substitute('0' . s:hex(char2nr(char)), '^.*\(..\)$', '\1', '')
    endif
    let i = i + 1
  endwhile
  return safe_str
endfunction

function! s:unquote(str)
  let str = a:str
  let str = substitute(str, '&gt;', '>', 'g')
  let str = substitute(str, '&lt;', '<', 'g')
  let str = substitute(str, '&quot;', '"', 'g')
  let str = substitute(str, '&apos;', "'", 'g')
  let str = substitute(str, '&nbsp;', ' ', 'g')
  let str = substitute(str, '&yen;', '\&#65509;', 'g')
  let str = substitute(str, '&#\(\d\+\);', '\=s:char(submatch(1))', 'g')
  let str = substitute(str, '&amp;', '\&', 'g')
  return str
endfunction

function! s:urlencode(query, sep, equal)
  let ret = ''
  if type(a:query) == 4
    for key in sort(keys(a:query))
      if strlen(ret) | let ret .= a:sep | endif
      let ret .= key . a:equal . s:quote(a:query[key])
    endfor
  elseif type(a:query) == 3
    for param in sort(a:query)
      if strlen(ret) | let ret .= a:sep | endif
      let ret .= s:quote(param)
    endfor
  else
    let ret = a:query
  endif
  return ret
endfunction

function! s:chain_sign(query)
  let ret = ''
  for param in sort(keys(a:query))
    let ret .= param . a:query[param]
  endfor
  return ret
endfunction

function! s:gen_sign(query)
  return md5#md5(s:rtm_shared_secret . s:chain_sign(a:query))
endfunction

function! s:get_url(endpoint, method, query)
  let url = a:endpoint
  let query = a:query
  let query['api_key'] = s:rtm_api_key
  if strlen(a:method)
    let query['method'] = a:method
  endif
  let query['api_sig'] = s:gen_sign(query)
  let params = s:urlencode(query, '&', '=')
  if strlen(params)
    let url .= '?' .params
  endif
  return url
endfunction

function! s:check_err(res)
  let re_err = '.*<err code="\(\d\+\)" msg="\([^"]\+\)".*$'
  let res = a:res
  let err_code = substitute(matchstr(res, re_err), re_err, '\1', '')
  let err_msg = substitute(matchstr(res, re_err), re_err, '\2', '')
  if strlen(err_code)
    echo 'RTM API Error (' . err_code . '): ' . s:unquote(err_msg)
    return ''
  else
    return res
  endif
endfunction

function! s:api_request(method, query, cookie, returnheader)
  let url = s:get_url(s:rtm_rest_endpoint, a:method, a:query)
  let cookie = s:urlencode(a:cookie, '; ', '=')
  let command = "curl -s -k"
  if a:returnheader
    let command .= " -i"
  endif
  if strlen(cookie)
    let command .= " -H \"Cookie: " . cookie . "\""
  endif
  let command .= " \"" . url . "\""
  let res = system(command)
  let res = s:check_err(res)
  return res
endfunction

function! s:get_frob()
  let re_frob = '^.*<frob[^>]*>\(.*\)</frob>.*$'
  let res = s:api_request('rtm.auth.getFrob', {}, {}, 0)
  if strlen(res)
    return substitute(matchstr(res, re_frob), re_frob, '\1', '')
  else
    echoerr s:default_err_msg
  endif
endfunction

function! s:get_token_url(frob)
  let query = {'perms': 'write', 'frob': a:frob}
  return s:get_url(s:rtm_auth_endpoint, '', query)
endfunction

function! s:get_token(frob)
  let re_token = '^.*<token[^>]*>\(.*\)</token>.*$'
  let query = {'frob': a:frob}
  let res = s:api_request('rtm.auth.getToken', query, {}, 0)
  if strlen(res)
    return substitute(matchstr(res, re_token), re_token, '\1', '')
  else
    echoerr s:default_err_msg
  endif
endfunction

function! s:check_token(token)
  let re_token = '^.*<token[^>]*>\(.*\)</token>.*$'
  let query = {'auth_token': a:token}
  let res = s:api_request('rtm.auth.checkToken', query, {}, 0)
  if strlen(res)
    return substitute(matchstr(res, re_token), re_token, '\1', '')
  endif
endfunction

function! s:create_timeline()
  let re_timeline = '^.*<timeline[^>]*>\(.*\)</timeline>.*$'
  let query = {'auth_token': s:rtm_token}
  let res = s:api_request('rtm.timelines.create', query, {}, 0)
  if strlen(res)
    let timeline = substitute(matchstr(res, re_timeline), re_timeline, '\1', '')
    echo 'Timeline ID: ' . timeline
    return timeline
  else
    echoerr s:default_err_msg
  endif
endfunction

function! s:optimize_name(name)
  let name = a:name
  " XXX Don't want to substitute anything.
  " let name = substitute(name, '\n$', '', '')
  " let name = substitute(name, '\n', ' ', 'g')
  " let name = substitute(name, '^\s*', '', '')
  " let name = substitute(name, '\(^\s*\|\s$\)', '', 'g')
  " let name = substitute(name, '\(^\W*\)', '', 'g')
  " let name = substitute(name, '^TODO\(\s*\)', '', '')
  return name
endfunction

function! s:add_task(name)
  echo 'Trying to add a task...'
  let re_list = '^.*<list id="\([^"]\+\)".*$'
  let re_taskseries = '^.*<taskseries id="\([^"]\+\)".*$'
  let re_task = '^.*<task id="\([^"]\+\)".*$'
  let timeline = s:create_timeline()
  let name = s:optimize_name(a:name)
  echo 'Add task: ' . name
  let query = {'timeline': timeline, 'name': name, 'parse': s:rtm_use_smartadd, 'auth_token': s:rtm_token}
  let res = s:api_request('rtm.tasks.add', query, {}, 0)
  if strlen(res)
    let list = substitute(matchstr(res, re_list), re_list, '\1', '')
    let taskseries = substitute(matchstr(res, re_taskseries), re_taskseries, '\1', '')
    let task = substitute(matchstr(res, re_task), re_task, '\1', '')
    echo 'Successfly added task -> list: ' . list . ', taskseries: ' . taskseries . ', task' . task
    " return 'RTM:' . list . '-' . taskseries . '-' . task
  else
    return ''
  endif
endfunction

let b:frob = ''

function! s:rtm_activate()
  let b:frob = s:get_frob()
  if strlen(b:frob)
    return 'Access and activate API access via: ' . s:get_token_url(b:frob)
  else
    echoerr s:default_err_msg
    finish
  endif
endfunction

function! s:rtm_get_token()
  if strlen(b:frob) < 1
    echoerr '1st, u need activate api access via: `:echo rtm#auth()`'
  endif
  return s:get_token(b:frob)
endfunction

function! s:rtm_command(option)
  if strlen(a:option)
    if a:option == '-a'
      echo s:rtm_activate()
    elseif a:option == '-t'
      echo s:rtm_get_token()
    else
      echo 'Invalid option'
    endif
  else
    call inputsave()
    let name = input("New task: ")
    call inputrestore()
    call s:add_task(name)
  endif
endfunction

function! s:rtm_api(option, line, update)
  let newline = ''
  if strlen(a:option)
    let option = a:option
  else
    let option = '-a'
  endif
  if option == '-a'
    let res = s:add_task(a:line)
    if strlen(res)
      let newline = a:line . ' ' . res
    endif
  elseif a:option == '-c'
    echo 'Complete task: under constructing'
  else
    echo 'Invalid option'
  endif
  if update && strlen(newline)
    normal dd
    -put =newline
  endif
endfunction

if exists('rtm_token')
  let s:rtm_token = s:check_token(rtm_token)
  if strlen(s:rtm_token) < 1
    echoerr 'this token is unuseable. reactivate token via: `:echo rtm#auth()` and `:echo rtm#get_token()`'
  endif
else
  echo 'RTM.vim api need authentication.'
  echo '* 1st: get activate url via: `:RTM -a` command'
  echo '* 2nd: allow api acccess'
  echo '* 3rd: get token via: `:RTM -t` command'
  echo '* 4th: token put ur .vimrc file'
endif

command! -nargs=? RTM :call <SID>rtm_command(<q-args>)
command! -nargs=? CRTM :call <SID>rtm_api(<q-args>, getline('.'), 0) " XXX Disabled update, gave errors."
command! -nargs=? BRTM :call <SID>rtm_api(<q-args>, join(getline(1, "$")), 0)

let &cpo = s:save_cpo
unlet s:save_cpo

