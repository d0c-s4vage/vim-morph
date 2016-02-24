syntax match Morph '\v^(Morph|Morph!) '
syntax match MorphFileTypes '\v(^Morph(!?) )@<=[^#]*'
syntax match MorphEnd '\v^MorphEnd'
syntax match MorphComment '\v#.*$'

highlight default link Morph Identifier
highlight default link MorphFileTypes Statement
highlight default link MorphCmds Constant
highlight default link MorphEnd Identifier
highlight default link MorphComment Comment
