scriptencoding utf-8

if expand("%:p") ==# expand("<sfile>:p")
	unlet! s:Morph_loaded
endif
if exists("s:Morph_loaded") || &cp
	finish
endif
let s:Morph_loaded = 1

" ----------------------
" GLOBAL VARIABLES
" ----------------------

" The default location for the user morphs
if !exists("g:Morph_UserMorphs")
	let g:Morph_UserMorphs = expand("~")."/.vim/Morphs.morph"
endif

" Whether undo should be used after morphing the file, or
" if the morph's restore command should explicitly be used to
" display the buffer's contents.
if !exists("g:Morph_PostMorphRestore")
	let g:Morph_PostMorphRestore = 1
endif

" flag to always automatically create the user's morph file
if !exists("g:Morph_AlwaysCreateMorphFile")
	let g:Morph_AlwaysCreateMorphFile = 0
endif

" This is used to misc. actions, E.g. determining if a glob pattern
" matches the current file's name.
if !exists("g:Morph_TmpDirectory")
	let g:Morph_TmpDirectory = "/tmp/morphtmp"
endif


" --------------------
" CORE FUNCTIONS
" --------------------

let s:Morphs = []
let s:MorphsRestore = {}
let s:MorphsLoaded = {}
function! Morph#PrepareMorph(...)
	if a:0 == 2
		if ! exists("b:Morph_actions")
			let b:Morph_actions = []
		endif
		let morph_idx = a:1
		let restore_idx = a:2
		call add(b:Morph_actions, [morph_idx, restore_idx])
		let b:Morph_restored = 0
	endif

	setl viminfo=
	setl noswapfile
	if exists("+undofile")
		setl noundofile
	endif
	setl noeol
	setl binary
endfunction

function! Morph#PrepareEdit()
	setl nobinary
	setl eol
endfunction

function! Morph#DoMorph(morph_idx)
	call Morph#PrepareMorph()

	let morph_cmd = s:Morphs[a:morph_idx]
	let morph_cmd = Morph#_BashSingleQuoteEscape(morph_cmd)

	let b:Morph_restored = 0
	
	if ! exists("b:Morph_last_line")
		let b:Morph_last_line = line(".")
		let b:Morph_last_column = col(".")
	endif

	silent! execute "%!bash -lc '".morph_cmd."'"
endfunction

function! Morph#_PostMorphRestorePosition()
	" jump back to the last line/column we were at
	execute "normal ".b:Morph_last_line."G".b:Morph_last_column."|"
endfunction

function! Morph#_ClearPositionVars()
	if exists("b:Morph_last_line")
		unlet b:Morph_last_line
	endif
	if exists("b:Morph_last_column")
		unlet b:Morph_last_column
	endif

	let b:Morph_restored = 0
endfunction

function! Morph#PostInlineMorph()
	call Morph#_PostMorphRestorePosition()
endfunction

function! Morph#_BashSingleQuoteEscape(cmd)
	let res = substitute(a:cmd, "'", "'\"'\"'", "g")
	let res = substitute(res, "%", "\\\\\%", "g")
	return res
endfunction

function! Morph#PostMorph(restore_idx)
	if g:Morph_PostMorphRestore
		call Morph#DoMorphRestore(a:restore_idx)
	else
		" just undo the morph to go back to the last position
		u
	endif

	call Morph#_PostMorphRestorePosition()
endfunction

function! Morph#DoMorphRestore(restore_idx)
	if a:restore_idx == -1
		if exists("b:Morph_actions") && b:Morph_restored == 0
			let curr_action_idx = len(b:Morph_actions)
			while curr_action_idx > 0
				let curr_action_idx = curr_action_idx - 1
				let curr_morph_action = b:Morph_actions[curr_action_idx]
				let curr_restore_cmd = s:Morphs[curr_morph_action[1]]
				let curr_restore_cmd = Morph#_BashSingleQuoteEscape(curr_restore_cmd)
				silent! execute "%!bash -lc '".curr_restore_cmd."'"
			endwhile
			call Morph#PrepareEdit()
		endif
		let b:Morph_restored = 1
		return
	endif

	let restore_cmd = s:Morphs[a:restore_idx]
	let restore_cmd = Morph#_BashSingleQuoteEscape(restore_cmd)
	silent! execute "%!bash -lc '".restore_cmd."'"
	call Morph#PrepareEdit()
endfunction

function! Morph#_CreateMorphAutoCommands(filetypes, morph_cmd, restore_cmd, buffer_autos, force_prepare)
	" double escape it, once for the execute, once for the call string
	" parameter
	let morph_idx = len(s:Morphs)
	call add(s:Morphs, a:morph_cmd)

	let restore_idx = len(s:Morphs)
	call add(s:Morphs, a:restore_cmd)
	" 1-to-1 relationship between morphs and restores, this will let us
	" look them up and restore in reverse order
	let s:MorphsRestore[restore_idx] = a:restore_cmd

	if a:buffer_autos
		let auto_opts = "<buffer>"
	else
		let auto_opts = a:filetypes
	endif

	augroup Morph
		execute "autocmd BufNewFile,BufReadPre,FileReadPre ".auto_opts." call Morph#PrepareMorph(".morph_idx.", ".restore_idx.")"
		execute "autocmd BufReadPost,FileReadPost ".auto_opts." call Morph#DoMorphRestore(-1)"

		execute "autocmd BufWritePre,FileWritePre ".auto_opts." call Morph#DoMorph(".morph_idx.")"
		execute "autocmd BufWritePost,FileWritePost ".auto_opts." call Morph#PostMorph(-1)"
	augroup end

	if a:force_prepare
		call Morph#PrepareMorph(morph_idx, restore_idx)
	endif
endfunction

function! Morph#_CreateMorphInlineAutoCommands(filetypes, morph_cmd, buffer_autos)
	let morph_idx = len(s:Morphs)
	call add(s:Morphs, a:morph_cmd)

	if a:buffer_autos
		let auto_opts = "<buffer>"
	else
		let auto_opts = a:filetypes
	endif

	augroup Morph
		execute "autocmd BufReadPre,FileReadPre ".auto_opts." call Morph#PrepareMorph()"
		execute "autocmd BufWritePre,FileWritePre ".auto_opts." call Morph#DoMorph(".morph_idx.")"
		execute "autocmd BufWritePost,FileWritePost ".auto_opts." call Morph#PostInlineMorph()"
	augroup end
endfunction

function! Morph#_CurrBufferMatchesFiletype(filetypes)
	let patterns = split(a:filetypes, ",")
	let currfile = fnamemodify(expand("%"), ":t")

	silent! execute "!rm -rf ".g:Morph_TmpDirectory
	silent! execute "!mkdir -p ".g:Morph_TmpDirectory
	silent! execute "!touch ".g:Morph_TmpDirectory."/".currfile

	for pattern in patterns
		let matching_files = split(globpath(g:Morph_TmpDirectory, pattern), "\n")
		if len(matching_files) > 0
			return 1
		endif
	endfor

	return 0
endfunction

" Function to define data transformations
" E.g. Morph("*.b64", "base64", "base64 -d")
function! Morph#Define(...) "filetypes, morph_cmd, restore_cmd, [morph_type], [mfile], [buffer_autos], [force_prepare]
	let filetypes = a:1
	let morph_cmd = a:2
	let restore_cmd = a:3

	if a:0 > 3
		let morph_type = a:4
	else
		let morph_type = "Morph"
	end

	if a:0 > 4
		let mfile = a:5
	else
		let mfile = "??"
	end

	if a:0 > 5
		let buffer_autos = a:6
	else
		let buffer_autos = 0
	endif

	if a:0 > 6
		let force_prepare = a:7
	else
		let force_prepare = 0
	endif

	if buffer_autos && ! Morph#_CurrBufferMatchesFiletype(filetypes)
		return
	endif

	if morph_type == "Morph"
		call Morph#_CreateMorphAutoCommands(filetypes, morph_cmd, restore_cmd, buffer_autos, force_prepare)
	elseif morph_type == "Morph!"
		call Morph#_CreateMorphInlineAutoCommands(filetypes, morph_cmd, buffer_autos)
	endif

	if ! has_key(s:MorphsLoaded, mfile)
		let s:MorphsLoaded[mfile] = []
	endif

	if ! buffer_autos
		call add(
			\ s:MorphsLoaded[mfile],
			\ {
				\ "morph": morph_cmd,
				\ "restore": restore_cmd,
				\ "file": mfile,
				\ "type": morph_type,
				\ "filetypes": filetypes
			\ }
		\ )
	endif
endfunction

function! Morph#_GetCommands(_idx, _lines, mfile)
	let idx = a:_idx
	let lines = a:_lines

	let morph_cmd = ""
	let restore_cmd = ""
	" attempt to find the two commands
	while idx < len(lines)-1
		let idx = idx + 1
		let line = lines[idx]
		" skip comments and empty lines
		if len(line) == 0 || split(line)[0][0] == "#"
			continue
		endif
		let line = Morph#_DiscardComments(line)

		let splits = split(line)

		" found the end marker
		if splits[0] == "MorphEnd"
			break
		endif

		if morph_cmd == ""
			let morph_cmd = join(splits, " ")
		elseif restore_cmd == ""
			let restore_cmd = join(splits, " ")
		else
			echom "unused command '".join(splits, " ")."' in Morph ".a:mfile.":".(idx+1)." for ".filetypes
		endif
	endwhile

	return {"morph": morph_cmd, "restore": restore_cmd, "new_idx": idx}
endfunction

function! Morph#_DiscardComments(line)
		" discard anything after the first pound sign (comment)
		return split(a:line, "#")[0]
endfunction

function! Morph#_ValidateMorphCommands(cmds, mfile, filetypes, morph_type)
	" check validity of Morph
	let morph_valid = 1
	if a:cmds.morph == ""
		let morph_valid = 0
		echom a:morph_type." in ".a:mfile." for ".a:filetypes." did not contain a morph command"
	endif
	if a:cmds.restore == "" && a:morph_type != "Morph!"
		let morph_valid = 0
		echom a:morph_type." in ".a:mfile." for ".a:filetypes." did not contain a restore command"
	endif

	return morph_valid
endfunction

function! Morph#LoadMorphFile(...)
	if a:0 == 0
		echom "must supply at least the path to the morph file to load"
		return
	endif

	let mfile = expand(a:1)

	if a:0 > 1
		let buffer_autos = a:2
	else
		let buffer_autos = 0
	endif

	if a:0 > 2
		let force_prepare = a:3
	else
		let force_prepare = 0
	endif

	if a:0 > 3
		let morph_contents = a:4
	else
		let morph_contents = []
	endif


	if ! buffer_autos && ! filereadable(mfile)
		if g:Morph_AlwaysCreateMorphFile
			echom "Morph file '".mfile."' not readable, initializing it"
			call Morph#_CreateMorphFile(mfile)
		else
			" silent fail
			return
		endif
	endif

	if len(morph_contents) == 0
		let mdata = readfile(mfile)
	else
		let mdata = morph_contents
	endif

	let line_count = 0
	let idx = -1
	while idx < len(mdata)-1
		let idx = idx + 1
		let line = mdata[idx]
		" skip comments and empty lines
		if len(line) == 0 || split(line)[0][0] == "#"
			continue
		endif
		let line = Morph#_DiscardComments(line)

		let splits = split(line)
		if len(splits) == 2 && (splits[0] == "Morph" || splits[0] == "Morph!")
			let morph_type = splits[0]
			let filetypes = splits[1]
		else
			echom "Invalid Morph line in Morph file ".mfile.":".(idx+1).": ".line
			continue
		endif

		let cmds = Morph#_GetCommands(idx, mdata, mfile)
		let idx = cmds.new_idx

		let morph_valid = Morph#_ValidateMorphCommands(cmds, mfile, filetypes, morph_type)
		if !morph_valid
			silent! echom "Morph not valid, skipping"
			continue
		endif

		call Morph#Define(filetypes, cmds.morph, cmds.restore, morph_type, mfile, buffer_autos, force_prepare)
	endwhile
endfunction

" assumes the file DOES NOT exist
function! Morph#_CreateMorphFile(mfile)
	if has("win32") || has("win16")
		let copy = "copy"
	else
		let copy = "cp"
	endif
	silent! execute "!".copy." '".s:morph_vim_path."/MorphTemplate.morph' '".a:mfile."'"
endfunction

let s:morph_vim_path=expand("<sfile>:p:h")
function! Morph#EditMorphFile(mfile)
	let was_new = ! filereadable(a:mfile)
	if ! filereadable(a:mfile)
		call Morph#_CreateMorphFile(a:mfile)
	endif

	execute 'edit '.a:mfile
	execute "autocmd! BufWritePost <buffer> :call Morph#_PostMorphEdit(".was_new.")"
endfunction

function! Morph#_PostMorphEdit(was_new)
	if a:was_new
		call Morph#LoadUserMorphs()
	else
		" this will remove all morphs and reload them
		call Morph#ReloadLoaded()
	endif

	" automatically close the file
	bd
endfunction

function! Morph#EditUserMorphs()
	echom "editing user morphs at '".g:Morph_UserMorphs."'"
	call Morph#EditMorphFile(g:Morph_UserMorphs)
endfunction

function! Morph#LoadUserMorphs(...)
	if a:0 > 0
		call Morph#LoadMorphFile(a:1)
	else
		call Morph#LoadMorphFile(g:Morph_UserMorphs)
	endif
endfunction

function! Morph#UnloadMorphs(_mfile)
	let mfile = expand(a:_mfile)
	echom "removing morphs from file ".expand(mfile)
	if has_key(s:MorphsLoaded, mfile)
		unlet s:MorphsLoaded[mfile]
	endif
	call Morph#ReloadLoaded()
endfunction

function! Morph#ListMorphs()
	let morphs = items(s:MorphsLoaded)
	let morph_count = 0
	for morph in morphs
		let mfile = morph[0]
		if morph_count != 0
			echom repeat("-", len(mfile))
		endif
		echom mfile
		let morph_count = morph_count + 1
		let minfos = morph[1]

		for minfo in minfos
			echom minfo.type." ".minfo.filetypes
			echom "     morph: ".minfo.morph
			if minfo.type == "Morph"
				echom "   restore: ".minfo.restore
			endif
		endfor
	endfor
endfunction

function! Morph#RemoveMorphs()
	" remove all Morph autocommands
	autocmd! Morph *
endfunction

" Reload all currently loaded Morphs, from ALL loaded Morph
" files. If a file wasn't used to load the Morph, then it
" will always be readded unless Morph#ClearLoaded() is called
" first
function! Morph#ReloadLoaded()
	call Morph#RemoveMorphs()

	let morphs = items(s:MorphsLoaded)
	call Morph#ClearLoaded()
	for morph in morphs
		let mfile = morph[0]
		let minfos = morph[1]

		if mfile != "??"
			call Morph#LoadUserMorphs(mfile)
		else
			for minfo in minfos
				call Morph#Define(minfo.filetypes, minfo.morph, minfo.restore, minfo.type, minfo.file)
			endfor
		endif
	endfor
endfunction

" clear the hash of loaded Morphs
function! Morph#ClearLoaded()
	let s:MorphsLoaded = {}
	let s:Morphs = []
endfunction

function! Morph#ClearAll()
	call Morph#ClearLoaded()
	call Morph#RemoveMorphs()
endfunction

function! Morph#ShowMorphs()
	let idx = -1
	while idx < len(s:Morphs)-1
		let idx = idx + 1
		echom idx." - ".s:Morphs[idx]
	endwhile
endfunction

" This will load all project morphs on the path back to
" the root directory. Project morphs only apply to files
" in or under the directory containing the .morph file
function! Morph#LoadProjectMorphs()
	if ! exists("g:Morph_ProjectMorphModtimes")
		let g:Morph_ProjectMorphModtimes = {}
	endif

	" find the project root
	let dots = ""
	let project_morph = ""
	let file_base_dir = expand("%:p:h")."/"
	let curr_file = expand("%:p")
	let loaded_morphs = 0
	while 1
		let check_path_dir = simplify(file_base_dir.dots)
		if check_path_dir == "/"
			break
		endif
		let check_path = check_path_dir.".morph"
		if filereadable(check_path) && curr_file != check_path
			" only load if the project Morphs either haven't been
			" applied to this buffer, or the file has changed
			let curr_mod_time = getftime(check_path)
			let modtime_key = curr_file." - ".check_path
			if !has_key(g:Morph_ProjectMorphModtimes, modtime_key) || g:Morph_ProjectMorphModtimes[modtime_key] != curr_mod_time
				if has_key(g:Morph_ProjectMorphModtimes, modtime_key)
					" remove existing auto commands that are local to the buffer
					" (these would only be project Morphs)
					autocmd! Morph * <buffer>
				endif

				let g:Morph_ProjectMorphModtimes[modtime_key] = curr_mod_time
				call Morph#LoadMorphFile(check_path, 1, 1)
				let loaded_morphs = 1
			endif
		endif
		let dots = dots . "../"
	endwhile
endfunction


" --------------------
" COMMANDS
" --------------------

command! -nargs=0 MorphEdit call Morph#EditUserMorphs()
command! -nargs=* MorphLoad call Morph#LoadUserMorphs(<f-args>)
command! -nargs=1 MorphUnload call Morph#UnloadMorphs(<f-args>)
command! -nargs=0 MorphList call Morph#ListMorphs()
command! -nargs=0 MorphReload call Morph#ReloadLoaded()
command! -nargs=0 MorphClear call Morph#ClearAll()

augroup MorphMeta
	autocmd! BufNewFile,BufReadPre * call Morph#LoadProjectMorphs()

	" this should fire before any other Morph BufWritePre event
	" so we'll use this clear position vars at the start of
	" each new write
	autocmd BufWritePre * call Morph#_ClearPositionVars()
augroup end

call Morph#ClearLoaded()
if exists("g:Morph_is_loaded")
	" for when this file is manually reloaded, we'll want to
	" reload all Morphs that have already been loaded.
	MorphReload
endif
let g:Morph_is_loaded = 1
MorphLoad
