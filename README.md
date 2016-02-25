# vim-morph

vim-morph is a vim plugin that handles file transformations, such as
automatically encrypting/decrypting data, encoding/decoding data, etc. File transformations
(Morphs) are performed in the order defined, and are performed in reverse when
restoring a file.

vim-morph lets the user easily define Morphs, either as a view into
an encrypted/encoded file (a `Morph`), or as an inline transformation (a `Morph!`).

## TL;DR

Install by running `git clone https://github.com/d0c-s4vage/vim-morph ~/.vim/bundle`.

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
* `g:Morph_TmpDirectory` - default it `/tmp/morphtmp` and is used for misc stuff

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

Or if you prefer base64-encoded gpg-encrypted files (yes, it performs actions
in the correct order: writes by doing `gpg | base64` and restores by doing
`base64 -d | gpg`):

	Morph *.gpg
		gpg --encrypt --batch --recipient my@email 2>/dev/null
		gpg --decrypt --batch 2>/dev/null
	MorphEnd

	Morph *.gpg
		base64
		base64 -d
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

To automatically replace `DATE` with the current date on file writes:

	Morph! *.txt
		sed "s/DATE/$(date +%m-%d-%y)/g"
	MorphEnd

#### Base64

To automatically decode base64 files (I have no idea if there is a common file extension
for base64 encoded files), one could define a `Morph` as:

	Morph *.b64
		base64
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

View `Morph`s contain two commands, the `morph` command, and the `restore` command (e.g. encrypt/decrypt).

Inline `Morph!`s contain one command, a `morph` command (e.g. word wrap the text).

### Comments

Comments in `.morph` files begin with a `#` sign and are valid anywhere
within the file. All data following a `#` sign is discarded.

### Project Morphs

`.morph` files can be also be scattered throughout your filesystem or put at the
root of your projects.

For example, given the directory structure below:

	/project
		.morph
		file_1.txt
		/subdir
			.morph
			file_2.txt

Opening `file_2.txt` will cause any matching morphs in `project/subdir/.morph` as well
as any matching morphs in `project/.morph` to be added to the file `file_2.txt`.


### Multiple Morphs

#### Example 1

_*TL;DR*: Morphs are executed sequentially and can be thought of as being piped together_

Suppose you had multiple Morphs that affected the same filetype. In the case
of `Morph!` commands, this is simple, and you shouldn't have to worry about
possible side effects. Just be sure you have the `g:Morph_PostMorphRestore`
option set to `1` (the default).

As an example of this, supposed we have a project where all files within it
should be base64 encoded. Now say we also want to add an inline morph
that substitutes any occurences of `DATE` with the current date in `*.txt` files. Let's also
add in another inline morph that replaces all occurences of `cyber` with 
`CYBER`, since it's an ultra-proper cyber noun and should be cyber capitalized. Such a
`.morph` file might look like:

	Morph! *.txt
		sed "s/DATE/$(date +%m-%d-%y)/g"
	MorphEnd

	Morph! *.txt
		sed 's/cyber/CYBER/g'
	MorphEnd

	Morph *
		base64
		base64 -d
	MorphEnd

Note the order of the Morphs - inline morphs come before the view morphs. Since we're
changing the literal contents of the file with the base64 morph, any morphs
defined afterwards will operate on the base64 representation of the file. As
such, placing the inline morphs after the base64 view morph will make them useless,
as they will be performing substitutions on base64'd data.

The result of the `.morph` file above essentially performs this when a file is
written (excuse the useless cat):

	cat file | sed "s/DATE/(date +%m-%d-%y)/g" | sed 's/cyber/CYBER/g' | base64

#### Example 2

_*TL;DR* - View morphs are performed sequentially in order of declaration when morphing (writing), and
in reverse when restoring (reading)._

vim-morph should successfully perform view Morphs in the order they are declared when morphing,
and in reverse order when restoring.

An example that gzips `*.wtf` files, encrypts, then base64 encodes them.

	Morph *.wtf
		gzip -
		gunzip -
	MorphEnd

	Morph *.wtf
		openssl enc -e -aes256 -k "some_password"
		openssl enc -d -aes256 -k "some_password"
	MorphEnd

	Morph *.wtf
		base64
		base64 -d
	MorphEnd
