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
      \ host-arg-base host-arg-count host-arg-len host-arg-text
      \ host-env-base host-env-has host-env-len host-env-present host-env-text
      \ host-put-byte host-seq host-write-text let-layout let-load-layout load match nat-case nat-elim pure
      \ ptr-add ptr-field ptr-from-addr ptr-step ptr-to-addr size-of
      \ store store-field store-fields the u8 u8-eq u8-to-u64 u64
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
