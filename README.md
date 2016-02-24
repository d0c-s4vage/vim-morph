# vim-morph

vim-morph is a vim plugin that handles file tranformations, such as
automatically encrypting/decrypting data, encoding/decoding data, etc.

vim-morph lets the user easily define Morphs, either as a view into
an encrypted/encoded file (a `Morph`), or as an inline transformation (a `Morph!`).

## TL;DR

Install by doing `git clone https://github.com/d0c-s4vage/vim-morph ~/.vim/bundle`.

Available commands:

* `MorphEdit` - open the default morph file (defaults to `~/.vim/Morphs.morph`)
* `MorphLoad` - specifically load a `.morph` file
* `MorphUnload` - specifically unload any Morphs a previously-loaded `.morph` file had defined
* `MorphList` - list all loaded Morphs
* `MorphReload` - reload all loaded morph files

Global variables:

* `g:Morph_UserMorphs` - the default file location for user Morphs
* `g:Morph_PostMorphRestore` - default is `0`. Says whether undo or an explicit restore should be used after morphing a buffer
* `g:Morph_AlwaysCreateMorphFile` - default is `0`. Says whether the default user morph file should always be created. Default is to only create it on the first use of the `:MorphEdit` command.

### Examples

Run `:MorphEdit` to open the default morph file

#### GPG

To add a `Morph` that automatically encrypts and decrypts
gpg-encrypted files, one could define the `Morph` for `*.gpg` files as:

	Morph *.gpg
		gpg --encrypt --batch --recipient my@email 2>/dev/null
		gpg --decrypt --batch 2>/dev/null
	MorphEnd

Or if you prefer ascii-armored gpg files:

	Morph *.asc
		gpg --encrypt --armor --batch --recipient my@email 2>/dev/null
		gpg --decrypt --batch 2>/dev/null
	MorphEnd

#### AES-256

To add a `Morph` that automatically encrypts and decrypts data using
openssl's aes256 functionality, one could define the `Morph` for `*.enc` files as:

	Morph *.enc
		openssl enc -e -aes256 -k "$MYPASSWORD"
		openssl enc -d -aes256 -k "$MYPASSWORD"
	MorphEnd

Note that the commands are interpreted by `bash -lc`, so any environment variables
and such that that would load would be available (such as `$MYPASSWORD`).

#### Inline Formatting

To automatically wrap `*.txt` files at 80 chars, one could define a `Morph!` as:

	Morph! *.txt
		fmt -w 80
	MorphEnd

#### Base64

To automatically decode base64 files (I have no idea if there is a common file extension
for base64 encoded files), one could define a `Morph` as:

	Morph *.b64
		# morph
		base64

		# restore
		base64 -d
	MorphEnd

#### Tabs vs Spaces

To automatically convert all tabs to spaces while editing
a file but converting the spaces back to tabs again when saving, a `Morph` could be
defined as (pick your file extensions, or `*` for everything):

	Morph *.c
		# on writing (morph)
		unexpand -t 4

		# on reading (restore)
		expand -t 4
	MorphEnd

## Installation

I recommend you use a vim plugin manager such as [pathogen](https://github.com/tpope/vim-pathogen).

Once pathogen is setup, git clone vim-morph into the `~/.vim/bundle` directory:

	git clone https://github.com/d0c-s4vage/vim-morph.git ~/.vim/bundle

## Morph File Details

Morph files are files that define individual `Morph`s, aka inline transformations on
or views into encoded/encrypted files.

A Morph can be a view into a file that requires two distinct steps (a `Morph`).
A good example of a `Morph` would be automatically encrypting/decrypting gpg-encrypted
files.

Morphs can also be inline morphs (a `Morph!`). A simple example is automatically word-wrapping all
`*.txt` files at 80 chars.

### Morphs

A Morph begins with a line that starts with either `Morph` or `Morph!` and is followed by
a comma-separated list of filetypes (think autocmds). Note that the comma-separated list of
filetypes should not contain whitespace.

Morphs end with the `MorphEnd` keyword.

### Commands

Commands are defined as the non-empty line(s) in the Morph body, after comments are stripped.

`Morph`s contain two commands, the `morph` command, and the `restore` command (e.g. encrypt/decrypt).

`Morph!`s contain one command, a `morph` command (e.g. word wrap the text).

### Comments

Comments in `.morph` files begin with a `#` sign and are valid anywhere
within the file. All data following a `#` sign is discarded.
