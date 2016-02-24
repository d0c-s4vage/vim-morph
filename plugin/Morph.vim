scriptencoding utf-8

" ----------------------
" GLOBAL VARIABLES
" ----------------------

" The default location for the user morphs
let g:Morph_UserMorphs = expand("~")."/.vim/Morphs.morph"

" Whether undo should be used after morphing the file, or
" if the morph's restore command should explicitly be used to
" display the buffer's contents.
let g:Morph_PostMorphRestore = 0

" flag to always automatically create the user's morph file
let g:Morph_AlwaysCreateMorphFile = 0


" --------------------
" CORE FUNCTIONS
" --------------------

let s:Morphs = []
let s:MorphsLoaded = {}
function! Morph#PrepareMorph()
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
	
	" save our current location in the file in the p register
	normal mp
	let b:last_line = line(".")
	let b:last_column = col(".")
	silent! execute "%!bash -lc '".morph_cmd."'"
endfunction

function! Morph#_PostMorphRestorePosition()
	" jump back to the last line/column we were at
	execute "normal ".b:last_line."G".b:last_column."|"
endfunction

function! Morph#PostInlineMorph()
	call Morph#_PostMorphRestorePosition()
endfunction

function! Morph#_BashSingleQuoteEscape(cmd)
	return substitute(a:cmd, "'", "'\"'\"'", "g")
endfunction

function! Morph#PostMorph(restore_idx)
	let restore_cmd = s:Morphs[a:restore_idx]
	let restore_cmd = Morph#_BashSingleQuoteEscape(restore_cmd)

	if g:Morph_PostMorphRestore
		call Morph#DoMorphRestore(restore_cmd)
	else
		" just undo the morph to go back to the last position
		u
	endif

	call Morph#_PostMorphRestorePosition()
endfunction

function! Morph#DoMorphRestore(restore_idx)
	let restore_cmd = s:Morphs[a:restore_idx]
	let restore_cmd = Morph#_BashSingleQuoteEscape(restore_cmd)
	silent! execute "%!bash -lc '".restore_cmd."'"
	call Morph#PrepareEdit()
endfunction

function! Morph#_CreateMorphAutoCommands(filetypes, morph_cmd, restore_cmd)
	" double escape it, once for the execute, once for the call string
	" parameter
	let morph_idx = len(s:Morphs)
	call add(s:Morphs, a:morph_cmd)

	let restore_idx = len(s:Morphs)
	call add(s:Morphs, a:restore_cmd)

	augroup Morph
		execute "autocmd BufReadPre,FileReadPre ".a:filetypes." call Morph#PrepareMorph()"
		execute "autocmd BufReadPost,FileReadPost ".a:filetypes." call Morph#DoMorphRestore(".restore_idx.")"

		execute "autocmd BufWritePre,FileWritePre ".a:filetypes." call Morph#DoMorph(".morph_idx.")"
		execute "autocmd BufWritePost,FileWritePost ".a:filetypes." call Morph#PostMorph(".restore_idx.")"
	augroup end
endfunction

function! Morph#_CreateMorphInlineAutoCommands(filetypes, morph_cmd)
	let morph_idx = len(s:Morphs)
	call add(s:Morphs, a:morph_cmd)

	augroup Morph
		execute "autocmd BufReadPre,FileReadPre ".a:filetypes." call Morph#PrepareMorph()"
		execute "autocmd BufWritePre,FileWritePre ".a:filetypes." call Morph#DoMorph(".morph_idx.")"
		execute "autocmd BufWritePost,FileWritePost ".a:filetypes." call Morph#PostInlineMorph()"
	augroup end
endfunction

" Function to define data transformations
" E.g. Morph("*.b64", "base64", "base64 -d")
function! Morph#Define(...) "filetypes, morph_cmd, restore_cmd, [morph_type], [mfile]
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

	if morph_type == "Morph"
		call Morph#_CreateMorphAutoCommands(filetypes, morph_cmd, restore_cmd)
	elseif morph_type == "Morph!"
		call Morph#_CreateMorphInlineAutoCommands(filetypes, morph_cmd)
	endif

	if ! has_key(s:MorphsLoaded, mfile)
		let s:MorphsLoaded[mfile] = []
	endif

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

function! Morph#LoadMorphFile(_mfile)
	let mfile = expand(a:_mfile)
	if ! filereadable(mfile)
		if g:Morph_AlwaysCreateMorphFile
			echom "Morph file '".mfile."' not readable, initializing it"
			call Morph#_CreateMorphFile(mfile)
		else
			" silent fail
			return
		endif
	endif

	let mdata = readfile(mfile)
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
			echom "Invalid Morph line in Morph file ".mfile.":".(idx+1)
			continue
		endif

		let cmds = Morph#_GetCommands(idx, mdata, mfile)
		let idx = cmds.new_idx

		let morph_valid = Morph#_ValidateMorphCommands(cmds, mfile, filetypes, morph_type)
		if !morph_valid
			continue
		endif

		call Morph#Define(filetypes, cmds.morph, cmds.restore, morph_type, mfile)
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

	execute 'tabf '.a:mfile
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

function! Morph#ShowMorphs()
	let idx = -1
	while idx < len(s:Morphs)-1
		let idx = idx + 1
		echom idx." - ".s:Morphs[idx]
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
command! -nargs=0 MorphClear call Morph#ClearLoaded()

MorphClear
if exists("g:Morph_is_loaded")
	MorphReload
endif
let g:Morph_is_loaded = 1
MorphLoad
