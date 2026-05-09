if exists("b:current_syntax")
  finish
endif

syntax match siltComment ";.*$"
syntax match siltNumber "\v<\d+>"
syntax match siltAtom "\v[[:alnum:]_+\-*\/<>=!?$%&~.^:|]+"

syntax keyword siltDeclaration
      \ abi-contract boot-contract calling-convention claim data def entry
      \ export extern include layout section static-bytes static-cell
      \ static-value target-contract

syntax keyword siltForm
      \ Eff Pi addr align-of bind bool-case field field-offset fn let
      \ ascii-byte-is-alnum ascii-byte-is-alpha ascii-byte-is-digit
      \ ascii-byte-is-hex-digit ascii-byte-is-lower ascii-byte-is-space
      \ ascii-byte-is-upper ascii-byte-is-whitespace
      \ byte-slice-all-ascii-alnum byte-slice-all-ascii-digits
      \ byte-slice-all-ascii-hex-digits byte-slice-all-ascii-whitespace
      \ byte-slice-at byte-slice-base byte-slice-drop byte-slice-from
      \ byte-slice-ends-with byte-slice-eq byte-slice-is-empty byte-slice-len
      \ byte-slice-starts-with byte-slice-take
      \ host-arg-base host-arg-count host-arg-len host-arg-text
      \ host-env-base host-env-has host-env-len host-env-present host-env-text
      \ host-file-read-base host-file-read-len host-file-write-bytes
      \ host-put-byte host-read-file host-seq host-write-file
      \ host-write-text let-layout let-load-layout list-head-or list-is-empty
      \ list-tail-or load match nat-case nat-elim pure
      \ option-and-then option-is-some option-map option-unwrap-or
      \ ptr-add ptr-field ptr-from-addr ptr-step ptr-to-addr result-and-then
      \ result-error-or result-is-ok result-map result-map-err result-unwrap-or size-of
      \ store store-field store-fields the u8 u8-eq u8-to-u64 u64
      \ text-base text-byte-at text-drop text-from-bytes text-is-empty
      \ text-ends-with text-eq text-len text-starts-with text-take
      \ text-view-from text-all-ascii-alnum text-all-ascii-digits
      \ text-all-ascii-hex-digits text-all-ascii-whitespace
      \ u64-add u64-and u64-div u64-eq u64-lt u64-lte u64-mul u64-or
      \ u64-rem u64-shl u64-shr u64-sub u64-to-nat u64-to-u8 u64-xor
      \ with-fields x86-in8 x86-out8

syntax keyword siltType Addr Bool Console Heap Nat Ptr Type U8 U64 Unit
syntax keyword siltConstant False S True Z tt

syntax match siltParen "[()]"

highlight default link siltComment Comment
highlight default link siltNumber Number
highlight default link siltDeclaration Keyword
highlight default link siltForm Function
highlight default link siltType Type
highlight default link siltConstant Constant
highlight default link siltParen Delimiter

let b:current_syntax = "silt"
