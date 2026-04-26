module Main (main) where

import Data.List (isInfixOf)
import Silt.Codegen.C
  ( emitDefinitionC
  , emitDefinitionFreestandingC
  , emitDefinitionsC
  , emitDefinitionsFreestandingC
  )
import Silt.Elab (checkProgram, normalizeDefinition)
import Silt.Parse (parseProgram)
import Silt.Source (readProgramBundle)
import Silt.Syntax (Program (..))
import System.Exit (exitFailure)

main :: IO ()
main = do
  ok1 <- expectCheck "identity module" identitySource
  ok2 <- expectCheck "composition module" compositionSource
  ok3 <- expectCheck "let bindings" letSource
  ok4 <- expectCheck "bool match" boolSource
  ok5 <- expectCheck "nat recursion primitive" natElimSource
  ok6 <- expectCheck "quantities" quantitiesSource
  ok7 <- expectCheck "effects" effectSource
  ok8 <- expectCheck "u64 repr" u64Source
  ok9 <- expectCheck "low-level repr" lowLevelSource
  ok10 <- expectCheck "extern interop" externSource
  ok11 <- expectCheck "memory effects" memorySource
  ok12 <- expectCheck "ABI interop" abiSource
  ok13 <- expectCheck "freestanding source" freestandingSource
  ok13b <- expectCheck "capability source" capabilitySource
  ok13c <- expectCheckFile "capability example file" "examples/capabilities.silt"
  ok13d <- expectCheckFile "limine include example source" "examples/limine.silt"
  ok13e <- expectCheckFile "limine panic include example source" "examples/limine-panic.silt"
  ok13f <- expectCheckFile "limine serial shared source" "examples/limine-serial.silt"
  ok13g <- expectCheckFile "top-level include fixture" "test/fixtures/includes/main.silt"
  ok13h <- expectSourceFailure "include rejects parent traversal" ["test/fixtures/includes/unsafe-parent.silt"] "include path cannot contain '..'"
  ok13i <- expectSourceFailure "include rejects non-silt extension" ["test/fixtures/includes/bad-extension.silt"] "include path must end in .silt"
  ok13j <- expectSourceFailure "include rejects cycles" ["test/fixtures/includes/cycle-a.silt"] "include cycle:"
  ok13k <- expectCheckFile "byte buffer example file" "examples/bytes.silt"
  ok13l <- expectCheckFile "limine protocol shared source" "examples/limine-protocol.silt"
  ok14 <- expectCheck "generic data" optionSource
  ok15 <- expectCheck "recursive generic data" recursiveDataSource
  ok16 <- expectFailure "missing claim" "(def nope Type)"
  ok17 <- expectFailure "ill-typed body" illTypedSource
  ok18 <- expectFailure "bad match scrutinee" badMatchSource
  ok19 <- expectFailure "erased binder used" badErasedSource
  ok20 <- expectFailure "linear binder duplicated" badLinearSource
  ok21 <- expectNormalized "normalization" normalizationSource "three" "(S (S (S Z)))"
  ok22 <- expectNormalized "effect normalization" effectSource "eff-three" "(((pure Console) Nat) (S (S Z)))"
  ok23 <- expectNormalized "u64 normalization" u64Source "word-answer" "(u64 42)"
  ok24 <- expectNormalized "addr normalization" lowLevelSource "heap-next" "(addr 4160)"
  ok25 <- expectNormalized "addr diff normalization" lowLevelSource "heap-span" "(u64 64)"
  ok26 <- expectNormalized "page alignment normalization" lowLevelSource "aligned-page" "(u64 8192)"
  ok27 <- expectNormalized "align-up normalization" lowLevelSource "aligned-up" "(u64 8192)"
  ok28 <- expectNormalized "page-count normalization" lowLevelSource "page-count-5000" "(u64 2)"
  ok29 <- expectNormalized "size-of normalization" lowLevelSource "u64-size" "(u64 8)"
  ok30 <- expectNormalized "align-of normalization" lowLevelSource "u64-align" "(u64 8)"
  ok31 <- expectNormalized "layout size normalization" lowLevelSource "header-size" "(u64 16)"
  ok32 <- expectNormalized "layout align normalization" lowLevelSource "header-align" "(u64 8)"
  ok33 <- expectNormalized "layout field offset normalization" lowLevelSource "header-next-offset" "(u64 8)"
  ok34 <- expectNormalized "layout field ptr normalization" lowLevelSource "header-next-ptr-addr" "(addr 8200)"
  ok35 <- expectNormalized "ptr-step normalization" lowLevelSource "heap-ptr-step-addr" "(addr 4104)"
  ok36 <- expectNormalized "pointer normalization" lowLevelSource "heap-ptr-addr" "(addr 4104)"
  ok37 <- expectNormalized "layout ptr-step normalization" lowLevelSource "header-step-addr" "(addr 8224)"
  ok38 <- expectNormalized "generic data normalization" optionSource "picked" "Z"
  ok39 <- expectNormalized "recursive generic data normalization" recursiveDataSource "picked-head" "Z"
  ok39b <- expectNormalized "capability linear token normalization" capabilitySource "rotated-lease" "lease1"
  ok39c <- expectNormalized "capability owned abstraction normalization" capabilitySource "unpacked-owned-lease" "lease1"
  ok39d <- expectNormalized "capability owned pointer handle normalization" capabilitySource "retagged-word-handle" "((((OwnedAt Lease1) U64) lease1) ((ptr-from-addr U64) (addr 4096)))"
  ok39e <- expectNormalized "capability observed value normalization" capabilitySource "observed-sample-value" "(u64 77)"
  ok39f <- expectNormalized "capability observed handle recovery normalization" capabilitySource "restored-word-handle" "((((OwnedAt Lease1) U64) lease1) ((ptr-from-addr U64) (addr 4096)))"
  ok39g <- expectNormalized "capability word updater normalization" capabilitySource "incremented-sample-word" "(u64 8)"
  ok39h <- expectNormalized "capability header updater normalization" capabilitySource "advanced-sample-next" "(addr 8192)"
  ok39i <- expectNormalized "capability state-indexed owned handle normalization" capabilitySource "forgot-word-cap-handle" "((((OwnedAt Lease1) U64) lease1) ((ptr-from-addr U64) (addr 4096)))"
  ok39j <- expectNormalized "capability state-indexed observed handle normalization" capabilitySource "forgot-word-cap-observed" "((((((ObservedAt Lease1) U64) U64) lease1) ((ptr-from-addr U64) (addr 4096))) (u64 33))"
  ok39k <- expectNormalized "capability state-indexed header handle normalization" capabilitySource "forgot-header-cap-handle" "((((OwnedAt HeaderLease1) Header) header-lease1) ((ptr-from-addr Header) (addr 8192)))"
  ok39l <- expectNormalizedFile "capability step settled word normalization" "examples/capabilities.silt" "settled-word-cap-step" "(((((OwnedCapAt Lease1) WordSlot1) U64) lease1) ((ptr-from-addr U64) (addr 4096)))"
  ok39m <- expectNormalizedFile "capability step forgotten word normalization" "examples/capabilities.silt" "forgot-word-cap-step" "((((OwnedAt Lease1) U64) lease1) ((ptr-from-addr U64) (addr 4096)))"
  ok39n <- expectNormalizedFile "capability step settled header normalization" "examples/capabilities.silt" "settled-header-cap-step" "(((((OwnedCapAt HeaderLease1) HeaderRegion1) Header) header-lease1) ((ptr-from-addr Header) (addr 8192)))"
  ok39o <- expectNormalizedFile "capability step forgotten header normalization" "examples/capabilities.silt" "forgot-header-cap-step" "((((OwnedAt HeaderLease1) Header) header-lease1) ((ptr-from-addr Header) (addr 8192)))"
  ok39p <- expectNormalizedFile "capability generic header update normalization" "examples/capabilities.silt" "replaced-header-next-sample" "(addr 12288)"
  ok39q <- expectNormalizedFile "u8 literal conversion normalization" "examples/bytes.silt" "byte-answer" "(u8 2)"
  ok39r <- expectNormalizedFile "u8 widening normalization" "examples/bytes.silt" "byte-answer-word" "(u64 2)"
  ok39s <- expectNormalizedFile "u8 equality normalization" "examples/bytes.silt" "byte-eq-sample" "True"
  ok39t <- expectNormalizedFile "u8 size normalization" "examples/bytes.silt" "u8-size" "(u64 1)"
  ok39u <- expectNormalizedFile "u8 align normalization" "examples/bytes.silt" "u8-align" "(u64 1)"
  ok39v <- expectNormalizedFile "u8 ptr-step normalization" "examples/bytes.silt" "byte-third-addr" "(addr 4099)"
  ok39w <- expectNormalizedFile "byte slice length normalization" "examples/bytes.silt" "byte-slice-len" "(u64 20)"
  ok39x <- expectNormalizedFile "byte slice base normalization" "examples/bytes.silt" "byte-slice-base-addr" "(addr 4096)"
  ok39y <- expectNormalizedFile "static byte length normalization" "examples/bytes.silt" "static-byte-sample-len-value" "(u64 4)"
  ok39z <- expectNormalizedFile "static byte slice length normalization" "examples/bytes.silt" "static-byte-sample-slice-len" "(u64 4)"
  ok40 <- expectCodegen "C backend seed" normalizationSource "three" "uint64_t three(void) {"
  ok41 <- expectCodegen "C backend add fn" codegenFunctionSource "add" "uint64_t add(uint64_t a, uint64_t b) {"
  ok42 <- expectCodegen "C backend erase arg" codegenFunctionSource "erase-first" "uint64_t erase_first(uint64_t x) {"
  ok43 <- expectCodegen "C backend u64 fn" u64Source "word-inc" "uint64_t word_inc(uint64_t x) {"
  ok44 <- expectCodegen "C backend addr fn" lowLevelSource "bump-addr" "uintptr_t bump_addr(uintptr_t base, uint64_t bytes) {"
  ok45 <- expectCodegen "C backend ptr fn" lowLevelSource "bump-ptr" "uintptr_t bump_ptr(uintptr_t base, uint64_t bytes) {"
  ok46 <- expectCodegen "C backend ptr-step fn" lowLevelSource "step-ptr" "uintptr_t step_ptr(uintptr_t base, uint64_t count) {"
  ok47 <- expectCodegen "C backend layout ptr-step signature" lowLevelSource "step-header" "uintptr_t step_header(uintptr_t base, uint64_t count) {"
  ok48 <- expectCodegen "C backend layout ptr-step stride" lowLevelSource "step-header" "(count * 16ULL)"
  ok49 <- expectCodegen "C backend align fn" lowLevelSource "align-up" "uint64_t align_up(uint64_t x, uint64_t align) {"
  ok50 <- expectCodegen "C backend generic load signature" memorySource "read-word" "uint64_t read_word(uintptr_t ptr) {"
  ok51 <- expectCodegen "C backend generic load deref" memorySource "read-word" "return (*((uint64_t*)(ptr)));"
  ok52 <- expectCodegen "C backend generic store signature" memorySource "write-word" "uint8_t write_word(uintptr_t ptr, uint64_t value) {"
  ok53 <- expectCodegen "C backend generic store write" memorySource "write-word" "(*((uint64_t*)(ptr))) = value;"
  ok54 <- expectCodegen "C backend bind effect fn" memorySource "increment-word" "uint64_t increment_word(uintptr_t ptr) {"
  ok55 <- expectCodegen "C backend aggregate load temp" memorySource "copy-header" "silt_layout_Header hdr_0 = (*((silt_layout_Header*)(src)));"
  ok56 <- expectCodegen "C backend aggregate store" memorySource "copy-header" "(*((silt_layout_Header*)(dst))) = hdr_0;"
  ok57 <- expectCodegen "C backend layout extern prototype" abiSource "inspect-header" "uint64_t header_magic(silt_layout_Header hdr);"
  ok58 <- expectCodegen "C backend unit extern prototype" abiSource "call-header-zero" "uint8_t header_zero(uintptr_t ptr);"
  ok59 <- expectCodegen "C backend extern prototype" externSource "call-host-add3" "uint64_t host_add3(uint64_t x);"
  ok60 <- expectCodegen "C backend extern addr prototype" externSource "call-host-bump" "uintptr_t host_bump(uintptr_t base, uint64_t bytes);"
  ok61 <- expectBundle "C backend bundle" codegenFunctionSource ["add", "erase-first"] "uint64_t erase_first(uint64_t x) {"
  ok62 <- expectBundle "memory backend bundle" memorySource ["read-word", "increment-word"] "uint64_t increment_word(uintptr_t ptr) {"
  ok63 <- expectBundle "ABI backend bundle" abiSource ["inspect-header", "call-header-zero"] "uint8_t call_header_zero(uintptr_t ptr) {"
  ok64 <- expectFreestandingCodegen "freestanding prelude" freestandingSource "init-and-read" "typedef __UINTPTR_TYPE__ uintptr_t;"
  ok65 <- expectFreestandingCodegen "freestanding layout typedef" freestandingSource "init-and-read" "silt_layout_Header;"
  ok66 <- expectFreestandingCodegen "freestanding signature" freestandingSource "init-and-read" "uint64_t init_and_read(uintptr_t base) {"
  ok67 <- expectFreestandingBundle "freestanding bundle" freestandingSource ["init-header", "init-and-read"] "uint8_t init_header(uintptr_t base) {"
  ok67b <- expectFreestandingCodegenFiles "freestanding u8 load signature" ["examples/bytes.silt"] "load-byte" "uint8_t load_byte(uintptr_t ptr) {"
  ok67c <- expectFreestandingCodegenFiles "freestanding u8 load deref" ["examples/bytes.silt"] "load-byte" "return (*((uint8_t*)(ptr)));"
  ok67d <- expectFreestandingCodegenFiles "freestanding u8 store signature" ["examples/bytes.silt"] "store-byte" "uint8_t store_byte(uintptr_t ptr, uint8_t value) {"
  ok67e <- expectFreestandingCodegenFiles "freestanding u8 store write" ["examples/bytes.silt"] "store-byte" "(*((uint8_t*)(ptr))) = value;"
  ok67f <- expectFreestandingCodegenFiles "freestanding static bytes rodata" ["examples/bytes.silt"] "static-byte-sample-first" "static const uint8_t silt_static_static_byte_sample[4] __attribute__((section(\".rodata.silt\"))) = {83u, 73u, 76u, 84u};"
  ok67g <- expectFreestandingCodegenFiles "freestanding static bytes load" ["examples/bytes.silt"] "static-byte-sample-first" "return (*((uint8_t*)(((uintptr_t)&silt_static_static_byte_sample[0]))));"
  ok68 <- expectCheck "layout literals" layoutLiteralSource
  ok69 <- expectFailure "layout literal missing field" layoutLiteralMissingFieldSource
  ok70 <- expectFailure "layout literal unknown field" layoutLiteralUnknownFieldSource
  ok70b <- expectFailure "layout-values arity" layoutValuesAritySource
  ok70c <- expectFailure "layout-values wrong field type" layoutValuesWrongTypeSource
  ok70d <- expectFailure "u8 literal out of range" "(claim bad U8)\n(def bad (u8 256))"
  ok70e <- expectFailure "u8 store rejects u64" badU8StoreSource
  ok70f <- expectFailure "static bytes reject empty object" "(static-bytes empty-bytes ())"
  ok70g <- expectFailure "static cell rejects non-runtime type" "(static-cell bad-cell (Pi ((x U64)) U64))"
  ok70h <- expectFailure "static value rejects non-runtime type" "(static-value bad-value (Pi ((x U64)) U64) .data.silt (fn ((x U64)) x))"
  ok70i <- expectFailure "static value rejects non-static initializer" "(claim runtime-word U64)\n(static-value bad-value U64 .data.silt runtime-word)"
  ok71 <- expectNormalized "layout literal normalization" layoutLiteralSource "header-template" "(layout Header ((magic (u64 77)) (next (addr 4096))))"
  ok71b <- expectNormalized "layout-values normalization" layoutLiteralSource "header-template-positional" "(layout Header ((magic (u64 77)) (next (addr 4096))))"
  ok72 <- expectCodegen "C backend layout literal zero-init" layoutLiteralSource "header-template" "silt_layout_Header Header_0 = {0};"
  ok73 <- expectCodegen "C backend layout literal field write" layoutLiteralSource "header-template" "(*((uint64_t*)(((uintptr_t)&Header_0 + 0ULL)))) = 77ULL;"
  ok74 <- expectCodegen "C backend layout literal extern call" layoutLiteralSource "header-template-magic" "return header_magic(Header_0);"
  ok75 <- expectFreestandingCodegen "freestanding layout literal store" freestandingSource "init-header" "(*((silt_layout_Header*)(base))) = Header_0;"
  ok76 <- expectNormalized "layout field projection normalization" layoutLiteralSource "header-template-next" "(addr 4096)"
  ok77 <- expectCodegen "C backend layout field projection" layoutLiteralSource "header-magic-from-arg" "return (*((uint64_t*)(((uintptr_t)&magic_0 + 0ULL))));"
  ok78 <- expectCodegen "C backend layout field projection from arg" layoutLiteralSource "header-magic-from-arg" "silt_layout_Header magic_0 = hdr;"
  ok79 <- expectFailure "layout update wrong field type" layoutUpdateWrongTypeSource
  ok80 <- expectNormalized "layout update normalization" layoutLiteralSource "retarget-template-next" "(addr 8192)"
  ok81 <- expectCodegen "C backend layout update" layoutLiteralSource "retarget-header" "(*((uintptr_t*)(((uintptr_t)&Header_0 + 8ULL)))) = next_addr;"
  ok82 <- expectFreestandingCodegen "freestanding layout update" freestandingSource "boot-header-at" "(*((uintptr_t*)(((uintptr_t)&Header_0 + 8ULL)))) = next_addr;"
  ok83 <- expectCheck "layout destructuring" layoutLiteralSource
  ok84 <- expectFailure "layout destructuring unknown field" layoutLetUnknownFieldSource
  ok85 <- expectNormalized "layout destructuring normalization" layoutLiteralSource "let-layout-next" "(addr 4096)"
  ok86 <- expectCodegen "C backend layout destructuring" layoutLiteralSource "let-layout-magic-from-arg" "return (*((uint64_t*)(((uintptr_t)&magic_0 + 0ULL))));"
  ok87 <- expectFreestandingCodegen "freestanding layout destructuring" freestandingSource "boot-header-next" "return ((uintptr_t)0ULL);"
  ok88 <- expectFailure "layout multi-update unknown field" layoutWithFieldsUnknownFieldSource
  ok89 <- expectNormalized "layout multi-update normalization" layoutLiteralSource "repacked-template-next" "(addr 12288)"
  ok90 <- expectNormalized "layout multi-update order normalization" layoutLiteralSource "override-template-next" "(addr 12288)"
  ok91 <- expectCodegen "C backend layout multi-update magic write" layoutLiteralSource "repack-header" "(*((uint64_t*)(((uintptr_t)&Header_0 + 0ULL)))) = magic;"
  ok92 <- expectCodegen "C backend layout multi-update next write" layoutLiteralSource "repack-header" "(*((uintptr_t*)(((uintptr_t)&Header_1 + 8ULL)))) = next_addr;"
  ok93 <- expectFreestandingCodegen "freestanding layout multi-update" freestandingSource "boot-header-remap" "(*((uintptr_t*)(((uintptr_t)&Header_0 + 8ULL)))) = next_addr;"
  ok94 <- expectCodegen "C backend load-field" memorySource "read-header-magic" "return (*((uint64_t*)(((uintptr_t)((uintptr_t)(((uintptr_t)hdr) + 0ULL))))));"
  ok95 <- expectCodegen "C backend store-field" memorySource "write-header-next" "(*((uintptr_t*)(((uintptr_t)((uintptr_t)(((uintptr_t)hdr) + 8ULL)))))) = value;"
  ok96 <- expectFreestandingCodegen "freestanding store-field" freestandingSource "reset-next" "(*((uintptr_t*)(((uintptr_t)((uintptr_t)(((uintptr_t)base) + 8ULL)))))) = next_addr;"
  ok97 <- expectFailure "layout multi-store unknown field" layoutStoreFieldsUnknownFieldSource
  ok98 <- expectCodegen "C backend multi-store magic write" memorySource "write-header-fields" "(*((uint64_t*)(((uintptr_t)((uintptr_t)(((uintptr_t)hdr) + 0ULL)))))) = magic;"
  ok99 <- expectCodegen "C backend multi-store next write" memorySource "write-header-fields" "(*((uintptr_t*)(((uintptr_t)((uintptr_t)(((uintptr_t)hdr) + 8ULL)))))) = next_addr;"
  ok100 <- expectFreestandingCodegen "freestanding multi-store" freestandingSource "reset-header-fields" "(*((uintptr_t*)(((uintptr_t)((uintptr_t)(((uintptr_t)base) + 8ULL)))))) = next_addr;"
  ok101 <- expectFailure "layout load destructuring unknown field" layoutLoadUnknownFieldSource
  ok102 <- expectCodegen "C backend layout load destructuring temp" memorySource "read-header-next-via-layout" "silt_layout_Header silt_value_0 = (*((silt_layout_Header*)(hdr)));"
  ok103 <- expectCodegen "C backend layout load destructuring return" memorySource "read-header-next-via-layout" "return (*((uintptr_t*)(((uintptr_t)&next_1 + 8ULL))));"
  ok104 <- expectFreestandingCodegen "freestanding layout load destructuring" freestandingSource "read-next-via-layout" "return (*((uintptr_t*)(((uintptr_t)&next_1 + 8ULL))));"
  ok105 <- expectCheck "explicit effect transitions" explicitEffectSource
  ok106 <- expectFailure "effect transition mismatch" badEffectTransitionSource
  ok107 <- expectCodegen "C backend explicit capability store" memorySource "seed-word-token" "(*((uint64_t*)(ptr))) = value;"
  ok108 <- expectCodegen "C backend explicit capability bind read" memorySource "seed-and-read-token" "return (*((uint64_t*)(ptr)));"
  ok109 <- expectCodegen "C backend explicit capability field load" memorySource "read-header-next-token" "return (*((uintptr_t*)(((uintptr_t)((uintptr_t)(((uintptr_t)hdr) + 8ULL))))));"
  ok110 <- expectFreestandingCodegen "freestanding explicit capability field store" freestandingSource "reset-next-token" "(*((uintptr_t*)(((uintptr_t)((uintptr_t)(((uintptr_t)base) + 8ULL)))))) = next_addr;"
  ok111 <- expectFailure "memory capability transition mismatch" badMemoryCapabilitySource
  ok112 <- expectFailure "capability token duplication" badCapabilityDupSource
  ok113 <- expectFailure "capability pattern duplication" badCapabilityPatternDupSource
  ok114 <- expectFailure "capability observed split duplication" badObservedSplitSource
  ok115 <- expectFailure "capability rewrite step duplication" badRewriteWordHandleSource
  ok116 <- expectFailure "capability carrier state mismatch" badCapabilityCarrierStateSource
  ok117 <- expectFailureFileWithSuffix "capability step post-state mismatch" "examples/capabilities.silt" badCapabilityStepPostStateSuffix
  ok118 <- expectFailureFileWithSuffix "capability step stale-state read" "examples/capabilities.silt" badCapabilityStepStaleReadSuffix
  ok119 <- expectCheckFile "memory example file" "examples/memory.silt"
  ok120 <- expectCheckFile "freestanding example file" "examples/freestanding.silt"
  ok121 <- expectCodegen "C backend cap-stable multi-store" memorySource "write-header-fields-token" "(*((uintptr_t*)(((uintptr_t)((uintptr_t)(((uintptr_t)hdr) + 8ULL)))))) = next_addr;"
  ok122 <- expectCodegen "C backend cap-stable layout load destructuring" memorySource "read-header-next-via-layout-token" "silt_layout_Header silt_value_0 = (*((silt_layout_Header*)(hdr)));"
  ok123 <- expectFreestandingCodegen "freestanding cap-stable multi-store" freestandingSource "reset-header-fields-token" "(*((uintptr_t*)(((uintptr_t)((uintptr_t)(((uintptr_t)base) + 8ULL)))))) = next_addr;"
  ok124 <- expectFreestandingCodegen "freestanding cap-stable layout load destructuring" freestandingSource "read-next-via-layout-token" "return (*((uintptr_t*)(((uintptr_t)&next_1 + 8ULL))));"
  ok125 <- expectFailure "layout multi-store capability mismatch" layoutStoreFieldsCapabilityMismatchSource
  ok126 <- expectFailure "layout load capability mismatch" layoutLoadCapabilityMismatchSource
  ok127 <- expectFailure "layout alignment power-of-two" badLayoutAlignmentSource
  ok128 <- expectFailure "layout size alignment multiple" badLayoutSizeAlignmentSource
  ok129 <- expectFailure "layout overlapping fields" badLayoutOverlapSource
  ok130 <- expectFailure "layout alignment covers fields" badLayoutWeakAlignmentSource
  ok131 <- expectFreestandingCodegen "freestanding layout extern prototype" freestandingSource "inspect-header-platform" "uint64_t platform_header_magic(silt_layout_Header hdr);"
  ok132 <- expectFreestandingCodegen "freestanding layout extern call" freestandingSource "inspect-header-platform" "return platform_header_magic(hdr_0);"
  ok133 <- expectFreestandingCodegen "freestanding unit extern prototype" freestandingSource "call-platform-zero" "uint8_t platform_header_zero(uintptr_t ptr);"
  ok134 <- expectFreestandingCodegen "freestanding unit extern call" freestandingSource "call-platform-zero" "return platform_header_zero(base);"
  ok135 <- expectFreestandingCodegen "freestanding exported symbol" freestandingSource "boot-entry" "uint64_t silt_boot_entry(uintptr_t base) {"
  ok136 <- expectFailure "export unknown target" badExportUnknownSource
  ok137 <- expectFailure "export extern target" badExportExternSource
  ok138 <- expectFailure "export duplicate target" badExportDuplicateTargetSource
  ok139 <- expectFailure "export duplicate symbol" badExportDuplicateSymbolSource
  ok140 <- expectFailure "extern invalid C symbol" badExternSymbolSource
  ok141 <- expectFailure "export invalid C symbol" badExportSymbolSource
  ok142 <- expectFreestandingCodegen "freestanding entry section and calling convention attributes" freestandingSource "boot-entry" "__attribute__((used)) __attribute__((sysv_abi)) __attribute__((section(\".text.silt.boot\"))) uint64_t silt_boot_entry(uintptr_t base) {"
  ok143 <- expectFailure "section unknown target" badSectionUnknownSource
  ok144 <- expectFailure "section extern target" badSectionExternSource
  ok145 <- expectFailure "section duplicate target" badSectionDuplicateTargetSource
  ok146 <- expectFailure "section invalid name" badSectionNameSource
  ok147 <- expectFreestandingCodegen "freestanding extern calling convention" freestandingSource "inspect-header-platform" "__attribute__((sysv_abi)) uint64_t platform_header_magic(silt_layout_Header hdr);"
  ok148 <- expectFailure "calling-convention unknown target" badCallingConventionUnknownSource
  ok149 <- expectFailure "calling-convention claim target" badCallingConventionClaimSource
  ok150 <- expectFailure "calling-convention duplicate target" badCallingConventionDuplicateTargetSource
  ok151 <- expectFailure "calling-convention invalid name" badCallingConventionNameSource
  ok152 <- expectFailure "entry unknown target" badEntryUnknownSource
  ok153 <- expectFailure "entry extern target" badEntryExternSource
  ok154 <- expectFailure "entry duplicate target" badEntryDuplicateSource
  ok155 <- expectFailure "entry unsupported signature" badEntryUnsupportedSignatureSource
  ok156 <- expectFailure "abi-contract symbol mismatch" badAbiContractSymbolSource
  ok157 <- expectFailure "abi-contract missing entry metadata" badAbiContractEntrySource
  ok158 <- expectFailure "abi-contract calling convention mismatch" badAbiContractCallingConventionSource
  ok159 <- expectFailure "abi-contract duplicate clause" badAbiContractDuplicateClauseSource
  ok160 <- expectFailure "abi-contract unsupported freestanding signature" badAbiContractFreestandingSource
  ok161 <- expectCheck "target contract source" targetContractSource
  ok162 <- expectFailure "target-contract unsupported target" badTargetContractTargetSource
  ok163 <- expectFailure "target-contract format mismatch" badTargetContractFormatSource
  ok164 <- expectFailure "target-contract entry metadata missing" badTargetContractEntrySource
  ok165 <- expectFailure "target-contract symbol mismatch" badTargetContractSymbolSource
  ok166 <- expectFailure "target-contract unaligned entry address" badTargetContractAddressSource
  ok167 <- expectFailure "target-contract duplicate clause" badTargetContractDuplicateClauseSource
  ok168 <- expectFreestandingCodegenFiles "limine freestanding entry signature" ["examples/limine.silt"] "limine-entry" "__attribute__((used)) __attribute__((sysv_abi)) __attribute__((section(\".text.silt.boot\"))) uint8_t silt_limine_entry(void) {"
  ok169 <- expectFreestandingCodegenFiles "limine static bytes rodata from Silt" ["examples/limine.silt"] "limine-entry" "static const uint8_t silt_static_limine_ok_bytes[20] __attribute__((section(\".rodata.silt\"))) = {83u, 73u, 76u, 84u, 95u, 76u, 73u, 77u, 73u, 78u, 69u, 95u, 81u, 69u, 77u, 85u, 95u, 79u, 75u, 10u};"
  ok169a <- expectFreestandingCodegenFiles "limine static cell bss from Silt" ["examples/limine.silt"] "limine-entry" "static uint8_t silt_cell_limine_boot_state[16] __attribute__((section(\".bss.silt\"), aligned(8)));"
  ok169a1 <- expectFreestandingCodegenFiles "limine static cell store from Silt" ["examples/limine.silt"] "limine-entry" "(*((silt_layout_BootState*)(((uintptr_t)&silt_cell_limine_boot_state[0])))) = BootState_0;"
  ok169a2 <- expectFreestandingCodegenFiles "limine static cell load from Silt" ["examples/limine.silt"] "limine-entry" "silt_layout_BootState state_1 = (*((silt_layout_BootState*)(((uintptr_t)&silt_cell_limine_boot_state[0]))));"
  ok169a3 <- expectFreestandingCodegenFiles "limine static value data from Silt" ["examples/limine.silt"] "limine-entry" "static silt_layout_BootState silt_value_limine_boot_manifest __attribute__((used, section(\".data.silt\"), aligned(8))) = {{1u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 66u, 0u, 0u, 0u, 0u, 0u, 0u, 0u}};"
  ok169a4 <- expectFreestandingCodegenFiles "limine static value load from Silt" ["examples/limine.silt"] "limine-entry" "silt_layout_BootState manifest_2 = (*((silt_layout_BootState*)(((uintptr_t)&silt_value_limine_boot_manifest))));"
  ok169b <- expectFreestandingCodegen "x86 in8 primitive codegen" machineIoSource "read-status" "__asm__ volatile (\"inb %1, %0\" : \"=a\"(in8_0) : \"Nd\"((uint16_t)(1016ULL)));"
  ok169c <- expectFreestandingCodegenFiles "limine serial readiness from Silt" ["examples/limine.silt"] "limine-entry" "__asm__ volatile (\"inb %1, %0\" : \"=a\"(in8_"
  ok169d <- expectFreestandingCodegenFiles "limine panic marker from Silt" ["examples/limine-panic.silt"] "panic-entry" "__asm__ volatile (\"outb %0, %1\" : : \"a\"((uint8_t)(80ULL)), \"Nd\"((uint16_t)(1016ULL)));"
  ok169e <- expectFailure "x86 out8 transition mismatch" badMachineIoTransitionSource
  ok169f <- expectFailureFilesWithSuffix "limine panic cause mismatch" ["examples/limine-panic.silt"] badPanicCauseMismatchSuffix
  ok169g <- expectFreestandingCodegenFiles "limine panic oom cause codegen" ["examples/limine-panic.silt"] "kernel-panic-oom" "__asm__ volatile (\"outb %0, %1\" : : \"a\"((uint8_t)(18ULL)), \"Nd\"((uint16_t)(244ULL)));"
  ok169h <- expectFreestandingCodegenFiles "limine panic invariant cause codegen" ["examples/limine-panic.silt"] "kernel-panic-invariant" "__asm__ volatile (\"outb %0, %1\" : : \"a\"((uint8_t)(19ULL)), \"Nd\"((uint16_t)(244ULL)));"
  ok169i <- expectFailureFilesWithSuffix "limine panic cause cross mismatch" ["examples/limine-panic.silt"] badPanicCauseCrossMismatchSuffix
  ok169j <- expectFreestandingCodegenFiles "limine panic oom marker codegen" ["examples/limine-panic.silt"] "kernel-panic-oom" "__asm__ volatile (\"outb %0, %1\" : : \"a\"((uint8_t)(79ULL)), \"Nd\"((uint16_t)(1016ULL)));"
  ok169k <- expectFreestandingCodegenFiles "limine panic invariant marker codegen" ["examples/limine-panic.silt"] "kernel-panic-invariant" "__asm__ volatile (\"outb %0, %1\" : : \"a\"((uint8_t)(86ULL)), \"Nd\"((uint16_t)(1016ULL)));"
  ok169l <- expectFreestandingCodegenFiles "limine message writer signature" ["examples/limine-serial.silt"] "serial-write-msg20" "uint8_t serial_write_msg20(silt_layout_SerialMsg20 msg) {"
  ok169m <- expectFailureFilesWithSuffix "limine message length mismatch" ["examples/limine.silt"] badMessageLengthMismatchSuffix
  ok169n <- expectFreestandingCodegenFiles "limine panic oom marker M codegen" ["examples/limine-panic.silt"] "kernel-panic-oom" "__asm__ volatile (\"outb %0, %1\" : : \"a\"((uint8_t)(77ULL)), \"Nd\"((uint16_t)(1016ULL)));"
  ok169o <- expectNormalizedFiles "limine layout-values message normalization" ["examples/limine.silt"] "limine-ok-message" "(layout SerialMsg20 ((b0 (u64 83)) (b1 (u64 73)) (b2 (u64 76)) (b3 (u64 84)) (b4 (u64 95)) (b5 (u64 76)) (b6 (u64 73)) (b7 (u64 77)) (b8 (u64 73)) (b9 (u64 78)) (b10 (u64 69)) (b11 (u64 95)) (b12 (u64 81)) (b13 (u64 69)) (b14 (u64 77)) (b15 (u64 85)) (b16 (u64 95)) (b17 (u64 79)) (b18 (u64 75)) (b19 (u64 10))))"
  ok169o1 <- expectNormalizedFiles "limine boot state normalization" ["examples/limine.silt"] "boot-state-ready" "(layout BootState ((phase (u64 1)) (code (u64 66))))"
  ok169o2 <- expectNormalizedFiles "limine boot manifest acceptance normalization" ["examples/limine.silt"] "boot-state-ready-accepted" "True"
  ok169p <- expectFreestandingCodegenFiles "limine serial slice writer signature" ["examples/limine-serial.silt"] "serial-write-slice20" "uint8_t serial_write_slice20(silt_layout_SerialSlice slice) {"
  ok169q <- expectFreestandingCodegenFiles "limine serial slice length guard" ["examples/limine-serial.silt"] "serial-write-slice20" "== 20ULL"
  ok169r <- expectFreestandingCodegenFiles "limine serial slice byte load" ["examples/limine-serial.silt"] "serial-write-slice20" "uint8_t byte_2 = (*((uint8_t*)"
  ok169s <- expectNormalizedFiles "limine static byte slice length normalization" ["examples/limine.silt"] "limine-ok-slice-len" "(u64 20)"
  ok169t <- expectNormalizedFiles "limine base revision marker normalization" ["examples/limine.silt"] "limine-base-revision-value" "(layout LimineBaseRevision ((magic0 (u64 17966595237268006600)) (magic1 (u64 7672788277485857756)) (revision (u64 3))))"
  ok169u <- expectFreestandingCodegenFiles "limine request start section codegen" ["examples/limine.silt"] "limine-entry" "silt_value_limine_requests_start __attribute__((used, section(\".limine_requests_start\"), aligned(8)))"
  ok169v <- expectFreestandingCodegenFiles "limine HHDM request section codegen" ["examples/limine.silt"] "limine-entry" "silt_value_limine_hhdm_request __attribute__((used, section(\".limine_requests\"), aligned(8)))"
  ok169w <- expectFreestandingCodegenFiles "limine HHDM response load codegen" ["examples/limine.silt"] "limine-entry" "silt_layout_LimineHhdmResponse response_"
  ok169x <- expectFreestandingCodegenFiles "limine HHDM marker codegen" ["examples/limine.silt"] "limine-entry" "__asm__ volatile (\"outb %0, %1\" : : \"a\"((uint8_t)(72ULL)), \"Nd\"((uint16_t)(1016ULL)));"
  ok169y <- expectNormalizedFiles "limine Memmap request normalization" ["examples/limine.silt"] "limine-memmap-request-value" "(layout LimineMemmapRequest ((id0 (u64 14389525486399949704)) (id1 (u64 757423339400917115)) (id2 (u64 7480265251536666735)) (id3 (u64 16358389823600082018)) (revision (u64 0)) (response ((ptr-from-addr LimineMemmapResponse) (addr 0)))))"
  ok169z <- expectFreestandingCodegenFiles "limine Memmap request section codegen" ["examples/limine.silt"] "limine-entry" "silt_value_limine_memmap_request __attribute__((used, section(\".limine_requests\"), aligned(8)))"
  ok169aa <- expectFreestandingCodegenFiles "limine Memmap response load codegen" ["examples/limine.silt"] "limine-entry" "silt_layout_LimineMemmapResponse response_"
  ok169ab <- expectFreestandingCodegenFiles "limine Memmap entry pointer load codegen" ["examples/limine.silt"] "limine-entry" "uintptr_t first_entry_ptr_"
  ok169ac <- expectFreestandingCodegenFiles "limine Memmap entry load codegen" ["examples/limine.silt"] "limine-entry" "silt_layout_LimineMemmapEntry first_entry_"
  ok169ad <- expectFreestandingCodegenFiles "limine Memmap marker rodata codegen" ["examples/limine.silt"] "limine-entry" "static const uint8_t silt_static_limine_memmap_ok_bytes[20] __attribute__((section(\".rodata.silt\"))) = {83u, 73u, 76u, 84u, 95u, 77u, 69u, 77u, 77u, 65u, 80u, 95u, 81u, 69u, 77u, 85u, 95u, 79u, 75u, 10u};"
  ok169ae <- expectNormalizedFiles "limine boot info readiness normalization" ["examples/limine.silt"] "boot-info-sample-ready" "True"
  ok169af <- expectFreestandingCodegenFiles "limine boot info static cell bss from Silt" ["examples/limine.silt"] "limine-entry" "static uint8_t silt_cell_limine_boot_info[40] __attribute__((section(\".bss.silt\"), aligned(8)));"
  ok169ag <- expectFreestandingCodegenFiles "limine boot info store from Silt" ["examples/limine.silt"] "limine-entry" "(*((silt_layout_BootInfo*)(((uintptr_t)&silt_cell_limine_boot_info[0])))) = BootInfo_"
  ok169ah <- expectFreestandingCodegenFiles "limine boot info load from Silt" ["examples/limine.silt"] "limine-entry" "silt_layout_BootInfo info_"
  ok169ai <- expectFreestandingCodegenFiles "limine boot info marker rodata codegen" ["examples/limine.silt"] "limine-entry" "static const uint8_t silt_static_limine_boot_info_ok_bytes[20] __attribute__((section(\".rodata.silt\"))) = {83u, 73u, 76u, 84u, 95u, 66u, 79u, 79u, 84u, 95u, 73u, 78u, 70u, 79u, 95u, 79u, 75u, 33u, 33u, 10u};"
  ok169aj <- expectNormalizedFiles "limine boot info first end normalization" ["examples/limine.silt"] "boot-info-sample-first-end" "(u64 4096)"
  ok169ak <- expectNormalizedFiles "limine boot info direct-map base normalization" ["examples/limine.silt"] "boot-info-sample-direct-map-first-base" "(u64 4096)"
  ok169al <- expectNormalizedFiles "limine boot info direct-map end normalization" ["examples/limine.silt"] "boot-info-sample-direct-map-first-end" "(u64 8192)"
  ok169am <- expectNormalizedFiles "limine boot info span validity normalization" ["examples/limine.silt"] "boot-info-sample-first-span-valid" "True"
  ok169an <- expectFreestandingCodegenFiles "limine boot span marker rodata codegen" ["examples/limine.silt"] "limine-entry" "static const uint8_t silt_static_limine_boot_span_ok_bytes[20] __attribute__((section(\".rodata.silt\"))) = {83u, 73u, 76u, 84u, 95u, 66u, 79u, 79u, 84u, 95u, 83u, 80u, 65u, 78u, 95u, 79u, 75u, 33u, 33u, 10u};"
  ok169ao <- expectNormalizedFiles "limine kernel span normalization" ["examples/limine.silt"] "kernel-span-sample" "(layout KernelBootSpan ((physical-base (u64 0)) (physical-end (u64 4096)) (direct-base (u64 4096)) (direct-end (u64 8192)) (kind (u64 0))))"
  ok169ap <- expectNormalizedFiles "limine kernel span readiness normalization" ["examples/limine.silt"] "kernel-span-sample-ready" "True"
  ok169aq <- expectFreestandingCodegenFiles "limine kernel span static cell bss from Silt" ["examples/limine.silt"] "limine-entry" "static uint8_t silt_cell_limine_kernel_span[40] __attribute__((section(\".bss.silt\"), aligned(8)));"
  ok169ar <- expectFreestandingCodegenFiles "limine kernel span store from Silt" ["examples/limine.silt"] "limine-entry" "(*((silt_layout_KernelBootSpan*)(((uintptr_t)&silt_cell_limine_kernel_span[0])))) = KernelBootSpan_"
  ok169as <- expectFreestandingCodegenFiles "limine kernel span load from Silt" ["examples/limine.silt"] "limine-entry" "silt_layout_KernelBootSpan span_"
  ok169at <- expectFreestandingCodegenFiles "limine kernel span marker rodata codegen" ["examples/limine.silt"] "limine-entry" "static const uint8_t silt_static_limine_kernel_span_ok_bytes[20] __attribute__((section(\".rodata.silt\"))) = {83u, 73u, 76u, 84u, 95u, 75u, 69u, 82u, 78u, 69u, 76u, 95u, 83u, 80u, 65u, 78u, 95u, 79u, 75u, 10u};"
  ok169au <- expectNormalizedFiles "limine kernel span page count normalization" ["examples/limine.silt"] "kernel-span-sample-page-count" "(u64 1)"
  ok169av <- expectNormalizedFiles "limine kernel span has pages normalization" ["examples/limine.silt"] "kernel-span-sample-has-pages" "True"
  ok169aw <- expectFreestandingCodegenFiles "limine kernel page count static cell bss from Silt" ["examples/limine.silt"] "limine-entry" "static uint8_t silt_cell_limine_kernel_page_count[8] __attribute__((section(\".bss.silt\"), aligned(8)));"
  ok169ax <- expectFreestandingCodegenFiles "limine kernel page count store from Silt" ["examples/limine.silt"] "limine-entry" "(*((uint64_t*)(((uintptr_t)&silt_cell_limine_kernel_page_count[0])))) ="
  ok169ay <- expectFreestandingCodegenFiles "limine kernel page count load from Silt" ["examples/limine.silt"] "limine-entry" "uint64_t page_count_"
  ok169ba <- expectFreestandingCodegenFiles "limine kernel pages marker rodata codegen" ["examples/limine.silt"] "limine-entry" "static const uint8_t silt_static_limine_kernel_pages_ok_bytes[20] __attribute__((section(\".rodata.silt\"))) = {83u, 73u, 76u, 84u, 95u, 75u, 80u, 65u, 71u, 69u, 83u, 95u, 79u, 75u, 33u, 33u, 33u, 33u, 33u, 10u};"
  ok170 <- expectFailure "target-contract limine lower-half address" badTargetContractLimineAddressSource
  ok171 <- expectFailure "boot-contract unknown target" badBootContractUnknownTargetSource
  ok172 <- expectFailure "boot-contract target mismatch" badBootContractTargetMismatchSource
  ok173 <- expectFailure "boot-contract duplicate clause" badBootContractDuplicateClauseSource
  if and [ok1, ok2, ok3, ok4, ok5, ok6, ok7, ok8, ok9, ok10, ok11, ok12, ok13, ok13b, ok13c, ok13d, ok13e, ok13f, ok13g, ok13h, ok13i, ok13j, ok13k, ok13l, ok14, ok15, ok16, ok17, ok18, ok19, ok20, ok21, ok22, ok23, ok24, ok25, ok26, ok27, ok28, ok29, ok30, ok31, ok32, ok33, ok34, ok35, ok36, ok37, ok38, ok39, ok39b, ok39c, ok39d, ok39e, ok39f, ok39g, ok39h, ok39i, ok39j, ok39k, ok39l, ok39m, ok39n, ok39o, ok39p, ok39q, ok39r, ok39s, ok39t, ok39u, ok39v, ok39w, ok39x, ok39y, ok39z, ok40, ok41, ok42, ok43, ok44, ok45, ok46, ok47, ok48, ok49, ok50, ok51, ok52, ok53, ok54, ok55, ok56, ok57, ok58, ok59, ok60, ok61, ok62, ok63, ok64, ok65, ok66, ok67, ok67b, ok67c, ok67d, ok67e, ok67f, ok67g, ok68, ok69, ok70, ok70b, ok70c, ok70d, ok70e, ok70f, ok70g, ok70h, ok70i, ok71, ok71b, ok72, ok73, ok74, ok75, ok76, ok77, ok78, ok79, ok80, ok81, ok82, ok83, ok84, ok85, ok86, ok87, ok88, ok89, ok90, ok91, ok92, ok93, ok94, ok95, ok96, ok97, ok98, ok99, ok100, ok101, ok102, ok103, ok104, ok105, ok106, ok107, ok108, ok109, ok110, ok111, ok112, ok113, ok114, ok115, ok116, ok117, ok118, ok119, ok120, ok121, ok122, ok123, ok124, ok125, ok126, ok127, ok128, ok129, ok130, ok131, ok132, ok133, ok134, ok135, ok136, ok137, ok138, ok139, ok140, ok141, ok142, ok143, ok144, ok145, ok146, ok147, ok148, ok149, ok150, ok151, ok152, ok153, ok154, ok155, ok156, ok157, ok158, ok159, ok160, ok161, ok162, ok163, ok164, ok165, ok166, ok167, ok168, ok169, ok169a, ok169a1, ok169a2, ok169a3, ok169a4, ok169b, ok169c, ok169d, ok169e, ok169f, ok169g, ok169h, ok169i, ok169j, ok169k, ok169l, ok169m, ok169n, ok169o, ok169o1, ok169o2, ok169p, ok169q, ok169r, ok169s, ok169t, ok169u, ok169v, ok169w, ok169x, ok169y, ok169z, ok169aa, ok169ab, ok169ac, ok169ad, ok169ae, ok169af, ok169ag, ok169ah, ok169ai, ok169aj, ok169ak, ok169al, ok169am, ok169an, ok169ao, ok169ap, ok169aq, ok169ar, ok169as, ok169at, ok169au, ok169av, ok169aw, ok169ax, ok169ay, ok169ba, ok170, ok171, ok172, ok173]
    then putStrLn "silt-test: all checks passed"
    else exitFailure

expectCheck :: String -> String -> IO Bool
expectCheck label source =
  case parseProgram source >>= checkProgram of
    Left err -> do
      putStrLn ("FAIL [" ++ label ++ "] expected success, got: " ++ err)
      pure False
    Right _ -> do
      putStrLn ("PASS [" ++ label ++ "]")
      pure True

expectCheckFile :: String -> FilePath -> IO Bool
expectCheckFile label path = do
  programResult <- readProgramBundle [path]
  expectCheckProgram label programResult

expectCheckProgram :: String -> Either String Program -> IO Bool
expectCheckProgram label programResult =
  case programResult >>= checkProgram of
    Left err -> do
      putStrLn ("FAIL [" ++ label ++ "] expected success, got: " ++ err)
      pure False
    Right _ -> do
      putStrLn ("PASS [" ++ label ++ "]")
      pure True

expectSourceFailure :: String -> [FilePath] -> String -> IO Bool
expectSourceFailure label paths expectedFragment = do
  programResult <- readProgramBundle paths
  case programResult of
    Left err
      | expectedFragment `isInfixOf` err -> do
          putStrLn ("PASS [" ++ label ++ "]")
          pure True
      | otherwise -> do
          putStrLn ("FAIL [" ++ label ++ "] expected fragment " ++ expectedFragment ++ ", got: " ++ err)
          pure False
    Right _ -> do
      putStrLn ("FAIL [" ++ label ++ "] expected source loading failure")
      pure False

expectFailure :: String -> String -> IO Bool
expectFailure label source =
  case parseProgram source >>= checkProgram of
    Left _ -> do
      putStrLn ("PASS [" ++ label ++ "]")
      pure True
    Right _ -> do
      putStrLn ("FAIL [" ++ label ++ "] expected failure")
      pure False

expectFailureFileWithSuffix :: String -> FilePath -> String -> IO Bool
expectFailureFileWithSuffix label path suffix = do
  source <- readFile path
  expectFailure label (source ++ "\n" ++ suffix)

expectFailureFilesWithSuffix :: String -> [FilePath] -> String -> IO Bool
expectFailureFilesWithSuffix label paths suffix = do
  programResult <- readProgramBundle paths
  case (programResult, parseProgram suffix) of
    (Right (Program decls), Right (Program suffixDecls)) ->
      expectFailureProgram label (Program (decls ++ suffixDecls))
    (Left _, _) -> do
      putStrLn ("FAIL [" ++ label ++ "] expected base source success")
      pure False
    (_, Left err) -> do
      putStrLn ("FAIL [" ++ label ++ "] expected suffix parse success, got: " ++ err)
      pure False

expectFailureProgram :: String -> Program -> IO Bool
expectFailureProgram label program =
  case checkProgram program of
    Left _ -> do
      putStrLn ("PASS [" ++ label ++ "]")
      pure True
    Right _ -> do
      putStrLn ("FAIL [" ++ label ++ "] expected failure")
      pure False

expectNormalized :: String -> String -> String -> String -> IO Bool
expectNormalized label source name expected =
  case parseProgram source >>= \program -> normalizeDefinition program name of
    Left err -> do
      putStrLn ("FAIL [" ++ label ++ "] expected normalization, got: " ++ err)
      pure False
    Right actual
      | actual == expected -> do
          putStrLn ("PASS [" ++ label ++ "]")
          pure True
      | otherwise -> do
          putStrLn
            ( "FAIL ["
                ++ label
                ++ "] expected "
                ++ expected
                ++ ", got "
                ++ actual
            )
          pure False

expectNormalizedFile :: String -> FilePath -> String -> String -> IO Bool
expectNormalizedFile label path name expected = do
  programResult <- readProgramBundle [path]
  expectNormalizedProgram label programResult name expected

expectNormalizedFiles :: String -> [FilePath] -> String -> String -> IO Bool
expectNormalizedFiles label paths name expected = do
  programResult <- readProgramBundle paths
  expectNormalizedProgram label programResult name expected

expectNormalizedProgram :: String -> Either String Program -> String -> String -> IO Bool
expectNormalizedProgram label programResult name expected =
  case programResult >>= \program -> normalizeDefinition program name of
    Left err -> do
      putStrLn ("FAIL [" ++ label ++ "] expected normalization, got: " ++ err)
      pure False
    Right actual
      | actual == expected -> do
          putStrLn ("PASS [" ++ label ++ "]")
          pure True
      | otherwise -> do
          putStrLn
            ( "FAIL ["
                ++ label
                ++ "] expected "
                ++ expected
                ++ ", got "
                ++ actual
            )
          pure False

expectCodegen :: String -> String -> String -> String -> IO Bool
expectCodegen label source name expectedFragment =
  case parseProgram source >>= \program -> emitDefinitionC program name of
    Left err -> do
      putStrLn ("FAIL [" ++ label ++ "] expected codegen, got: " ++ err)
      pure False
    Right output
      | expectedFragment `elem` lines output || expectedFragment `isInfixOf` output -> do
          putStrLn ("PASS [" ++ label ++ "]")
          pure True
      | otherwise -> do
          putStrLn
            ( "FAIL ["
                ++ label
                ++ "] expected fragment "
                ++ expectedFragment
                ++ ", got "
                ++ output
            )
          pure False

expectBundle :: String -> String -> [String] -> String -> IO Bool
expectBundle label source names expectedFragment =
  case parseProgram source >>= \program -> emitDefinitionsC program names of
    Left err -> do
      putStrLn ("FAIL [" ++ label ++ "] expected bundle emission, got: " ++ err)
      pure False
    Right output
      | expectedFragment `isInfixOf` output -> do
          putStrLn ("PASS [" ++ label ++ "]")
          pure True
      | otherwise -> do
          putStrLn
            ( "FAIL ["
                ++ label
                ++ "] expected fragment "
                ++ expectedFragment
                ++ ", got "
                ++ output
            )
          pure False

expectFreestandingCodegen :: String -> String -> String -> String -> IO Bool
expectFreestandingCodegen label source name expectedFragment =
  case parseProgram source >>= \program -> emitDefinitionFreestandingC program name of
    Left err -> do
      putStrLn ("FAIL [" ++ label ++ "] expected freestanding codegen, got: " ++ err)
      pure False
    Right output
      | expectedFragment `elem` lines output || expectedFragment `isInfixOf` output -> do
          putStrLn ("PASS [" ++ label ++ "]")
          pure True
      | otherwise -> do
          putStrLn
            ( "FAIL ["
                ++ label
                ++ "] expected fragment "
                ++ expectedFragment
                ++ ", got "
                ++ output
            )
          pure False

expectFreestandingCodegenFiles :: String -> [FilePath] -> String -> String -> IO Bool
expectFreestandingCodegenFiles label paths name expectedFragment = do
  programResult <- readProgramBundle paths
  case programResult >>= \program -> emitDefinitionFreestandingC program name of
    Left err -> do
      putStrLn ("FAIL [" ++ label ++ "] expected freestanding codegen, got: " ++ err)
      pure False
    Right output
      | expectedFragment `elem` lines output || expectedFragment `isInfixOf` output -> do
          putStrLn ("PASS [" ++ label ++ "]")
          pure True
      | otherwise -> do
          putStrLn
            ( "FAIL ["
                ++ label
                ++ "] expected fragment "
                ++ expectedFragment
                ++ ", got "
                ++ output
            )
          pure False

expectFreestandingBundle :: String -> String -> [String] -> String -> IO Bool
expectFreestandingBundle label source names expectedFragment =
  case parseProgram source >>= \program -> emitDefinitionsFreestandingC program names of
    Left err -> do
      putStrLn ("FAIL [" ++ label ++ "] expected freestanding bundle emission, got: " ++ err)
      pure False
    Right output
      | expectedFragment `isInfixOf` output -> do
          putStrLn ("PASS [" ++ label ++ "]")
          pure True
      | otherwise -> do
          putStrLn
            ( "FAIL ["
                ++ label
                ++ "] expected fragment "
                ++ expectedFragment
                ++ ", got "
                ++ output
            )
          pure False

identitySource :: String
identitySource =
  unlines
    [ "(claim id (Pi ((A Type) (x A)) A))"
    , "(def id (fn ((A Type) (x A)) x))"
    , "(claim use-id (Pi ((A Type) (x A)) A))"
    , "(def use-id (fn ((A Type) (x A)) (id A x)))"
    ]

compositionSource :: String
compositionSource =
  unlines
    [ "(claim const (Pi ((A Type) (B Type) (x A) (y B)) A))"
    , "(def const (fn ((A Type) (B Type) (x A) (y B)) x))"
    ]

illTypedSource :: String
illTypedSource =
  unlines
    [ "(claim bad (Pi ((A Type) (x A)) A))"
    , "(def bad (fn ((A Type) (x A)) A))"
    ]

letSource :: String
letSource =
  unlines
    [ "(claim two Nat)"
    , "(def two (let ((one (S Z))) (S one)))"
    ]

boolSource :: String
boolSource =
  unlines
    [ "(claim not (Pi ((b Bool)) Bool))"
    , "(def not"
    , "  (fn ((b Bool))"
    , "    (match b"
    , "      ((True) False)"
    , "      ((False) True))))"
    ]

natElimSource :: String
natElimSource =
  unlines
    [ "(claim add (Pi ((a Nat) (b Nat)) Nat))"
    , "(def add"
    , "  (fn ((a Nat) (b Nat))"
    , "    (nat-elim Nat"
    , "      b"
    , "      (fn ((k Nat) (rec Nat)) (S rec))"
    , "      a)))"
    ]

badMatchSource :: String
badMatchSource =
  unlines
    [ "(claim bad-match (Pi ((A Type) (x A)) A))"
    , "(def bad-match"
    , "  (fn ((A Type) (x A))"
    , "    (match x"
    , "      ((True) x)"
    , "      ((False) x))))"
    ]

quantitiesSource :: String
quantitiesSource =
  unlines
    [ "(claim choose-left (Pi ((A 0 Type) (B 0 Type) (x 1 A) (y 0 B)) A))"
    , "(def choose-left (fn ((A 0 Type) (B 0 Type) (x 1 A) (y 0 B)) x))"
    , "(claim keep-one Nat)"
    , "(def keep-one (let ((tmp 1 (S Z))) tmp))"
    ]

badErasedSource :: String
badErasedSource =
  unlines
    [ "(claim bad-erased (Pi ((x 0 Nat)) Nat))"
    , "(def bad-erased (fn ((x 0 Nat)) x))"
    ]

badLinearSource :: String
badLinearSource =
  unlines
    [ "(claim add (Pi ((a Nat) (b Nat)) Nat))"
    , "(def add"
    , "  (fn ((a Nat) (b Nat))"
    , "    (nat-elim Nat"
    , "      b"
    , "      (fn ((k Nat) (rec Nat)) (S rec))"
    , "      a)))"
    , "(claim dup (Pi ((x 1 Nat)) Nat))"
    , "(def dup (fn ((x 1 Nat)) (add x x)))"
    ]

effectSource :: String
effectSource =
  unlines
    [ "(claim eff-three (Eff Console Nat))"
    , "(def eff-three"
    , "  (bind Console Nat Nat"
    , "    (pure Console Nat (S Z))"
    , "    (fn ((x 1 Nat))"
    , "      (pure Console Nat (S x)))))"
    ]

explicitEffectSource :: String
explicitEffectSource =
  unlines
    [ "(claim eff-three-explicit (Eff Console Console Nat))"
    , "(def eff-three-explicit"
    , "  (bind Console Console Console Nat Nat"
    , "    (pure Console Nat (S Z))"
    , "    (fn ((x 1 Nat))"
    , "      (pure Console Nat (S x)))))"
    ]

badEffectTransitionSource :: String
badEffectTransitionSource =
  unlines
    [ "(claim bad-eff (Eff Console Heap Nat))"
    , "(def bad-eff"
    , "  (bind Console Console Heap Nat Nat"
    , "    (pure Console Nat (S Z))"
    , "    (fn ((x 1 Nat))"
    , "      (pure Heap Nat (S x)))))"
    ]

badMemoryCapabilitySource :: String
badMemoryCapabilitySource =
  unlines
    [ "(data HeapCell0 ())"
    , "(data HeapCell1 ())"
    , "(claim bad-write (Pi ((ptr (Ptr U64)) (value U64)) (Eff HeapCell0 HeapCell0 Unit)))"
    , "(def bad-write"
    , "  (fn ((ptr (Ptr U64)) (value U64))"
    , "    (store HeapCell0 HeapCell1 U64 ptr value)))"
    ]

badU8StoreSource :: String
badU8StoreSource =
  unlines
    [ "(data ByteMem0 ())"
    , "(data ByteMem1 ())"
    , "(claim bad-store (Pi ((ptr (Ptr U8))) (Eff ByteMem0 ByteMem1 Unit)))"
    , "(def bad-store"
    , "  (fn ((ptr (Ptr U8)))"
    , "    (store ByteMem0 ByteMem1 U8 ptr (u64 1))))"
    ]

badExportUnknownSource :: String
badExportUnknownSource =
  "(export missing silt_missing)"

badExportExternSource :: String
badExportExternSource =
  unlines
    [ "(extern host-add3 (Pi ((x U64)) U64) host_add3)"
    , "(export host-add3 silt_host_add3)"
    ]

badExportDuplicateTargetSource :: String
badExportDuplicateTargetSource =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(export entry silt_entry)"
    , "(export entry silt_entry_again)"
    ]

badExportDuplicateSymbolSource :: String
badExportDuplicateSymbolSource =
  unlines
    [ "(claim first U64)"
    , "(def first (u64 1))"
    , "(claim second U64)"
    , "(def second (u64 2))"
    , "(export first silt_entry)"
    , "(export second silt_entry)"
    ]

badExternSymbolSource :: String
badExternSymbolSource =
  "(extern host-add3 (Pi ((x U64)) U64) host-add3)"

badExportSymbolSource :: String
badExportSymbolSource =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(export entry bad-symbol)"
    ]

badSectionUnknownSource :: String
badSectionUnknownSource =
  "(section missing .text.missing)"

badSectionExternSource :: String
badSectionExternSource =
  unlines
    [ "(extern host-add3 (Pi ((x U64)) U64) host_add3)"
    , "(section host-add3 .text.host)"
    ]

badSectionDuplicateTargetSource :: String
badSectionDuplicateTargetSource =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(section entry .text.one)"
    , "(section entry .text.two)"
    ]

badSectionNameSource :: String
badSectionNameSource =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(section entry bad\"section)"
    ]

badCallingConventionUnknownSource :: String
badCallingConventionUnknownSource =
  "(calling-convention missing sysv-abi)"

badCallingConventionClaimSource :: String
badCallingConventionClaimSource =
  unlines
    [ "(claim entry U64)"
    , "(calling-convention entry sysv-abi)"
    ]

badCallingConventionDuplicateTargetSource :: String
badCallingConventionDuplicateTargetSource =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(calling-convention entry sysv-abi)"
    , "(calling-convention entry ms-abi)"
    ]

badCallingConventionNameSource :: String
badCallingConventionNameSource =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(calling-convention entry fastcall)"
    ]

badEntryUnknownSource :: String
badEntryUnknownSource =
  "(entry missing)"

badEntryExternSource :: String
badEntryExternSource =
  unlines
    [ "(extern host-add3 (Pi ((x U64)) U64) host_add3)"
    , "(entry host-add3)"
    ]

badEntryDuplicateSource :: String
badEntryDuplicateSource =
  unlines
    [ "(claim first U64)"
    , "(def first (u64 1))"
    , "(entry first)"
    , "(claim second U64)"
    , "(def second (u64 2))"
    , "(entry second)"
    ]

badEntryUnsupportedSignatureSource :: String
badEntryUnsupportedSignatureSource =
  unlines
    [ "(claim bad Type)"
    , "(def bad U64)"
    , "(entry bad)"
    ]

badAbiContractSymbolSource :: String
badAbiContractSymbolSource =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(export entry silt_entry)"
    , "(abi-contract entry ((symbol wrong_entry)))"
    ]

badAbiContractEntrySource :: String
badAbiContractEntrySource =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(abi-contract entry ((entry)))"
    ]

badAbiContractCallingConventionSource :: String
badAbiContractCallingConventionSource =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(calling-convention entry sysv-abi)"
    , "(abi-contract entry ((calling-convention ms-abi)))"
    ]

badAbiContractDuplicateClauseSource :: String
badAbiContractDuplicateClauseSource =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(export entry silt_entry)"
    , "(abi-contract entry ((symbol silt_entry) (symbol silt_entry)))"
    ]

badAbiContractFreestandingSource :: String
badAbiContractFreestandingSource =
  unlines
    [ "(claim bad Type)"
    , "(def bad U64)"
    , "(abi-contract bad ((freestanding)))"
    ]

targetContractSource :: String
targetContractSource =
  targetContractBase
    ++ unlines
      [ "(target-contract x86_64-sysv-elf"
      , "  ((format elf64)"
      , "   (arch x86_64)"
      , "   (abi sysv)"
      , "   (entry entry)"
      , "   (symbol silt_entry)"
      , "   (section .text.silt.boot)"
      , "   (calling-convention sysv-abi)"
      , "   (entry-address 1048576)"
      , "   (red-zone disabled)"
      , "   (freestanding)))"
      ]

badTargetContractTargetSource :: String
badTargetContractTargetSource =
  targetContractBase
    ++ unlines
      [ "(target-contract aarch64-elf"
      , "  ((format elf64)"
      , "   (arch x86_64)"
      , "   (abi sysv)"
      , "   (entry entry)"
      , "   (symbol silt_entry)"
      , "   (section .text.silt.boot)"
      , "   (calling-convention sysv-abi)"
      , "   (entry-address 1048576)"
      , "   (red-zone disabled)"
      , "   (freestanding)))"
      ]

badTargetContractFormatSource :: String
badTargetContractFormatSource =
  targetContractBase
    ++ unlines
      [ "(target-contract x86_64-sysv-elf"
      , "  ((format elf32)"
      , "   (arch x86_64)"
      , "   (abi sysv)"
      , "   (entry entry)"
      , "   (symbol silt_entry)"
      , "   (section .text.silt.boot)"
      , "   (calling-convention sysv-abi)"
      , "   (entry-address 1048576)"
      , "   (red-zone disabled)"
      , "   (freestanding)))"
      ]

badTargetContractEntrySource :: String
badTargetContractEntrySource =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(export entry silt_entry)"
    , "(section entry .text.silt.boot)"
    , "(calling-convention entry sysv-abi)"
    , "(target-contract x86_64-sysv-elf"
    , "  ((format elf64)"
    , "   (arch x86_64)"
    , "   (abi sysv)"
    , "   (entry entry)"
    , "   (symbol silt_entry)"
    , "   (section .text.silt.boot)"
    , "   (calling-convention sysv-abi)"
    , "   (entry-address 1048576)"
    , "   (red-zone disabled)"
    , "   (freestanding)))"
    ]

badTargetContractSymbolSource :: String
badTargetContractSymbolSource =
  targetContractBase
    ++ unlines
      [ "(target-contract x86_64-sysv-elf"
      , "  ((format elf64)"
      , "   (arch x86_64)"
      , "   (abi sysv)"
      , "   (entry entry)"
      , "   (symbol wrong_entry)"
      , "   (section .text.silt.boot)"
      , "   (calling-convention sysv-abi)"
      , "   (entry-address 1048576)"
      , "   (red-zone disabled)"
      , "   (freestanding)))"
      ]

badTargetContractAddressSource :: String
badTargetContractAddressSource =
  targetContractBase
    ++ unlines
      [ "(target-contract x86_64-sysv-elf"
      , "  ((format elf64)"
      , "   (arch x86_64)"
      , "   (abi sysv)"
      , "   (entry entry)"
      , "   (symbol silt_entry)"
      , "   (section .text.silt.boot)"
      , "   (calling-convention sysv-abi)"
      , "   (entry-address 123)"
      , "   (red-zone disabled)"
      , "   (freestanding)))"
      ]

badTargetContractDuplicateClauseSource :: String
badTargetContractDuplicateClauseSource =
  targetContractBase
    ++ unlines
      [ "(target-contract x86_64-sysv-elf"
      , "  ((format elf64)"
      , "   (format elf64)"
      , "   (arch x86_64)"
      , "   (abi sysv)"
      , "   (entry entry)"
      , "   (symbol silt_entry)"
      , "   (section .text.silt.boot)"
      , "   (calling-convention sysv-abi)"
      , "   (entry-address 1048576)"
      , "   (red-zone disabled)"
      , "   (freestanding)))"
      ]

targetContractBase :: String
targetContractBase =
  unlines
    [ "(claim entry U64)"
    , "(def entry (u64 1))"
    , "(export entry silt_entry)"
    , "(section entry .text.silt.boot)"
    , "(calling-convention entry sysv-abi)"
    , "(entry entry)"
    ]

badTargetContractLimineAddressSource :: String
badTargetContractLimineAddressSource =
  limineContractBase
    ++ unlines
      [ "(target-contract x86_64-limine-elf"
      , "  ((format elf64)"
      , "   (arch x86_64)"
      , "   (abi sysv)"
      , "   (entry limine-entry)"
      , "   (symbol silt_limine_entry)"
      , "   (section .text.silt.boot)"
      , "   (calling-convention sysv-abi)"
      , "   (entry-address 1048576)"
      , "   (red-zone disabled)"
      , "   (freestanding)))"
      ]

badBootContractUnknownTargetSource :: String
badBootContractUnknownTargetSource =
  limineContractBase
    ++ unlines
      [ "(boot-contract limine-x86_64"
      , "  ((protocol limine)"
      , "   (target x86_64-limine-elf)"
      , "   (entry limine-entry)"
      , "   (kernel-path /boot/silt-limine.elf)"
      , "   (config-path /boot/limine.conf)"
      , "   (freestanding)))"
      ]

badBootContractTargetMismatchSource :: String
badBootContractTargetMismatchSource =
  limineContractBase
    ++ limineTargetContract
    ++ unlines
      [ "(boot-contract limine-x86_64"
      , "  ((protocol limine)"
      , "   (target x86_64-sysv-elf)"
      , "   (entry limine-entry)"
      , "   (kernel-path /boot/silt-limine.elf)"
      , "   (config-path /boot/limine.conf)"
      , "   (freestanding)))"
      ]

badBootContractDuplicateClauseSource :: String
badBootContractDuplicateClauseSource =
  limineContractBase
    ++ limineTargetContract
    ++ unlines
      [ "(boot-contract limine-x86_64"
      , "  ((protocol limine)"
      , "   (protocol limine)"
      , "   (target x86_64-limine-elf)"
      , "   (entry limine-entry)"
      , "   (kernel-path /boot/silt-limine.elf)"
      , "   (config-path /boot/limine.conf)"
      , "   (freestanding)))"
      ]

limineContractBase :: String
limineContractBase =
  unlines
    [ "(extern platform-kernel-halt Unit platform_kernel_halt)"
    , "(calling-convention platform-kernel-halt sysv-abi)"
    , "(claim limine-entry Unit)"
    , "(def limine-entry (platform-kernel-halt))"
    , "(export limine-entry silt_limine_entry)"
    , "(section limine-entry .text.silt.boot)"
    , "(calling-convention limine-entry sysv-abi)"
    , "(entry limine-entry)"
    ]

limineTargetContract :: String
limineTargetContract =
  unlines
    [ "(target-contract x86_64-limine-elf"
    , "  ((format elf64)"
    , "   (arch x86_64)"
    , "   (abi sysv)"
    , "   (entry limine-entry)"
    , "   (symbol silt_limine_entry)"
    , "   (section .text.silt.boot)"
    , "   (calling-convention sysv-abi)"
    , "   (entry-address 18446744071562067968)"
    , "   (red-zone disabled)"
    , "   (freestanding)))"
    ]

badCapabilityDupSource :: String
badCapabilityDupSource =
  unlines
    [ "(data Owned ((Tok 0 Type) (A 0 Type)) (Hold Tok A))"
    , "(data Lease0 () (lease0))"
    , "(claim own (Pi ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (value 1 A)) (Owned Tok A)))"
    , "(def own"
    , "  (fn ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (value 1 A))"
    , "    (Hold Tok A tok value)))"
    , "(claim bad-dup-lease (Pi ((lease 1 Lease0)) (Owned Lease0 Lease0)))"
    , "(def bad-dup-lease"
    , "  (fn ((lease 1 Lease0))"
    , "    (own Lease0 Lease0 lease lease)))"
    ]

badCapabilityPatternDupSource :: String
badCapabilityPatternDupSource =
  unlines
    [ "(data Pair ((A 0 Type) (B 0 Type)) (MkPair A B))"
    , "(data Lease0 () (lease0))"
    , "(data Lease1 () (lease1))"
    , "(claim bad-unpack (Pi ((owned 1 (Pair Lease0 Lease1))) (Pair Lease1 Lease1)))"
    , "(def bad-unpack"
    , "  (fn ((owned 1 (Pair Lease0 Lease1)))"
    , "    (match owned"
    , "      ((MkPair (spent 0) (fresh 1))"
    , "       (MkPair Lease1 Lease1 fresh fresh)))))"
    ]

badObservedSplitSource :: String
badObservedSplitSource =
  unlines
    [ "(data Owned ((Tok 0 Type) (A 0 Type)) (Hold Tok A))"
    , "(data OwnedPtr ((Tok 0 Type) (A 0 Type)) (OwnedAt Tok (Ptr A)))"
    , "(data Observed ((Tok 0 Type) (A 0 Type) (V 0 Type)) (ObservedAt Tok (Ptr A) V))"
    , "(data Pair ((A 0 Type) (B 0 Type)) (MkPair A B))"
    , "(data Lease1 () (lease1))"
    , "(claim own (Pi ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (value 1 A)) (Owned Tok A)))"
    , "(def own"
    , "  (fn ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (value 1 A))"
    , "    (Hold Tok A tok value)))"
    , "(claim own-ptr (Pi ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (ptr (Ptr A))) (OwnedPtr Tok A)))"
    , "(def own-ptr"
    , "  (fn ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (ptr (Ptr A)))"
    , "    (OwnedAt Tok A tok ptr)))"
    , "(claim observe"
    , "  (Pi ((Tok 0 Type) (A 0 Type) (V 0 Type) (tok 1 Tok) (ptr (Ptr A)) (value 1 V))"
    , "      (Observed Tok A V)))"
    , "(def observe"
    , "  (fn ((Tok 0 Type) (A 0 Type) (V 0 Type) (tok 1 Tok) (ptr (Ptr A)) (value 1 V))"
    , "    (ObservedAt Tok A V tok ptr value)))"
    , "(claim with-observed"
    , "  (Pi ((Tok 0 Type) (A 0 Type) (V 0 Type) (B 0 Type)"
    , "       (observed 1 (Observed Tok A V))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A)) (value 1 V)) B)))"
    , "      B))"
    , "(def with-observed"
    , "  (fn ((Tok 0 Type) (A 0 Type) (V 0 Type) (B 0 Type)"
    , "       (observed 1 (Observed Tok A V))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A)) (value 1 V)) B)))"
    , "    (match observed"
    , "      ((ObservedAt (tok 1) ptr (value 1))"
    , "       (k tok ptr value)))))"
    , "(claim bad-split"
    , "  (Pi ((observed 1 (Observed Lease1 U64 U64)))"
    , "      (Pair (OwnedPtr Lease1 U64) (Owned Lease1 U64))))"
    , "(def bad-split"
    , "  (fn ((observed 1 (Observed Lease1 U64 U64)))"
    , "    (with-observed Lease1 U64 U64 (Pair (OwnedPtr Lease1 U64) (Owned Lease1 U64)) observed"
    , "      (fn ((lease 1 Lease1) (ptr (Ptr U64)) (value 1 U64))"
    , "        (MkPair (OwnedPtr Lease1 U64) (Owned Lease1 U64)"
    , "          (own-ptr Lease1 U64 lease ptr)"
    , "          (own Lease1 U64 lease value))))))"
    ]

badRewriteWordHandleSource :: String
badRewriteWordHandleSource =
  unlines
    [ "(data OwnedPtr ((Tok 0 Type) (A 0 Type)) (OwnedAt Tok (Ptr A)))"
    , "(data Observed ((Tok 0 Type) (A 0 Type) (V 0 Type)) (ObservedAt Tok (Ptr A) V))"
    , "(data Lease1 () (lease1))"
    , "(data WordSlot1 ())"
    , "(claim own-ptr (Pi ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (ptr (Ptr A))) (OwnedPtr Tok A)))"
    , "(def own-ptr"
    , "  (fn ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (ptr (Ptr A)))"
    , "    (OwnedAt Tok A tok ptr)))"
    , "(claim with-owned-ptr"
    , "  (Pi ((Tok 0 Type) (A 0 Type) (B 0 Type)"
    , "       (owned 1 (OwnedPtr Tok A))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A))) B)))"
    , "      B))"
    , "(def with-owned-ptr"
    , "  (fn ((Tok 0 Type) (A 0 Type) (B 0 Type)"
    , "       (owned 1 (OwnedPtr Tok A))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A))) B)))"
    , "    (match owned"
    , "      ((OwnedAt (tok 1) ptr)"
    , "       (k tok ptr)))))"
    , "(claim observe"
    , "  (Pi ((Tok 0 Type) (A 0 Type) (V 0 Type) (tok 1 Tok) (ptr (Ptr A)) (value 1 V))"
    , "      (Observed Tok A V)))"
    , "(def observe"
    , "  (fn ((Tok 0 Type) (A 0 Type) (V 0 Type) (tok 1 Tok) (ptr (Ptr A)) (value 1 V))"
    , "    (ObservedAt Tok A V tok ptr value)))"
    , "(claim with-observed"
    , "  (Pi ((Tok 0 Type) (A 0 Type) (V 0 Type) (B 0 Type)"
    , "       (observed 1 (Observed Tok A V))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A)) (value 1 V)) B)))"
    , "      B))"
    , "(def with-observed"
    , "  (fn ((Tok 0 Type) (A 0 Type) (V 0 Type) (B 0 Type)"
    , "       (observed 1 (Observed Tok A V))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A)) (value 1 V)) B)))"
    , "    (match observed"
    , "      ((ObservedAt (tok 1) ptr (value 1))"
    , "       (k tok ptr value)))))"
    , "(claim read-owned-word-handle (Pi ((owned 1 (OwnedPtr Lease1 U64))) (Eff WordSlot1 WordSlot1 (Observed Lease1 U64 U64))))"
    , "(def read-owned-word-handle"
    , "  (fn ((owned 1 (OwnedPtr Lease1 U64)))"
    , "    (with-owned-ptr Lease1 U64 (Eff WordSlot1 WordSlot1 (Observed Lease1 U64 U64)) owned"
    , "      (fn ((lease 1 Lease1) (ptr (Ptr U64)))"
    , "        (bind WordSlot1 WordSlot1 WordSlot1 U64 (Observed Lease1 U64 U64)"
    , "          (load WordSlot1 U64 ptr)"
    , "          (fn ((value 1 U64))"
    , "            (pure WordSlot1 (Observed Lease1 U64 U64) (observe Lease1 U64 U64 lease ptr value))))))))"
    , "(claim rewrite-owned-word-handle"
    , "  (Pi ((owned 1 (OwnedPtr Lease1 U64))"
    , "       (step 1 (Pi ((old 1 U64)) U64)))"
    , "      (Eff WordSlot1 WordSlot1 (OwnedPtr Lease1 U64))))"
    , "(def rewrite-owned-word-handle"
    , "  (fn ((owned 1 (OwnedPtr Lease1 U64))"
    , "       (step 1 (Pi ((old 1 U64)) U64)))"
    , "    (bind WordSlot1 WordSlot1 WordSlot1 (Observed Lease1 U64 U64) (OwnedPtr Lease1 U64)"
    , "      (read-owned-word-handle owned)"
    , "      (fn ((observed 1 (Observed Lease1 U64 U64)))"
    , "        (with-observed Lease1 U64 U64 (Eff WordSlot1 WordSlot1 (OwnedPtr Lease1 U64)) observed"
    , "          (fn ((lease 1 Lease1) (ptr (Ptr U64)) (old 1 U64))"
    , "            (bind WordSlot1 WordSlot1 WordSlot1 Unit (OwnedPtr Lease1 U64)"
    , "              (store WordSlot1 WordSlot1 U64 ptr (step old))"
    , "              (fn ((done 1 Unit))"
    , "                (let ((ignored 0 done))"
    , "                  (pure WordSlot1 (OwnedPtr Lease1 U64) (own-ptr Lease1 U64 lease ptr)))))))))))"
    , "(claim bad-rewrite (Pi ((owned 1 (OwnedPtr Lease1 U64))) (Eff WordSlot1 WordSlot1 (OwnedPtr Lease1 U64))))"
    , "(def bad-rewrite"
    , "  (fn ((owned 1 (OwnedPtr Lease1 U64)))"
    , "    (rewrite-owned-word-handle owned"
    , "      (fn ((old 1 U64))"
    , "        (u64-add old old)))))"
    ]

badCapabilityCarrierStateSource :: String
badCapabilityCarrierStateSource =
  unlines
    [ "(data OwnedCap ((Tok 0 Type) (Cap 0 Type) (A 0 Type)) (OwnedCapAt Tok (Ptr A)))"
    , "(data Lease1 () (lease1))"
    , "(data WordSlot0 ())"
    , "(data WordSlot1 ())"
    , "(claim own-cap"
    , "  (Pi ((Tok 0 Type) (Cap 0 Type) (A 0 Type)"
    , "       (tok 1 Tok)"
    , "       (ptr (Ptr A)))"
    , "      (OwnedCap Tok Cap A)))"
    , "(def own-cap"
    , "  (fn ((Tok 0 Type) (Cap 0 Type) (A 0 Type)"
    , "       (tok 1 Tok)"
    , "       (ptr (Ptr A)))"
    , "    (OwnedCapAt Tok Cap A tok ptr)))"
    , "(claim keep-word-handle"
    , "  (Pi ((owned 1 (OwnedCap Lease1 WordSlot1 U64)))"
    , "      (OwnedCap Lease1 WordSlot1 U64)))"
    , "(def keep-word-handle"
    , "  (fn ((owned 1 (OwnedCap Lease1 WordSlot1 U64)))"
    , "    owned))"
    , "(claim word-base (Ptr U64))"
    , "(def word-base"
    , "  (ptr-from-addr U64 (addr 4096)))"
    , "(claim bad-handle (OwnedCap Lease1 WordSlot1 U64))"
    , "(def bad-handle"
    , "  (keep-word-handle"
    , "    (own-cap Lease1 WordSlot0 U64 lease1 word-base)))"
    ]

badCapabilityStepPostStateSuffix :: String
badCapabilityStepPostStateSuffix =
  unlines
    [ "(claim bad-settled-word-cap-step (OwnedCap Lease1 WordSlot0 U64))"
    , "(def bad-settled-word-cap-step"
    , "  (settle-cap-step Lease0 Lease1 WordSlot0 WordSlot1 U64 word-cap-step))"
    ]

badCapabilityStepStaleReadSuffix :: String
badCapabilityStepStaleReadSuffix =
  unlines
    [ "(claim bad-read-after-word-cap-step"
    , "  (Eff WordSlot0 WordSlot0 (ObservedCap Lease1 WordSlot1 U64 U64)))"
    , "(def bad-read-after-word-cap-step"
    , "  (read-after-word-cap-step word-cap-step))"
    ]

u64Source :: String
u64Source =
  unlines
    [ "(claim word-answer U64)"
    , "(def word-answer (u64-add (u64 40) (u64 2)))"
    , "(claim word-inc (Pi ((x U64)) U64))"
    , "(def word-inc (fn ((x U64)) (u64-add x (u64 1))))"
    ]

machineIoSource :: String
machineIoSource =
  unlines
    [ "(data MachineIO ())"
    , "(claim read-status (Eff MachineIO U64))"
    , "(def read-status"
    , "  (x86-in8 MachineIO (u64 1016)))"
    ]

badMachineIoTransitionSource :: String
badMachineIoTransitionSource =
  unlines
    [ "(data MachineStart ())"
    , "(data MachineDone ())"
    , "(claim bad-exit (Eff MachineStart MachineStart Unit))"
    , "(def bad-exit"
    , "  (x86-out8 MachineStart MachineDone (u64 244) (u64 16)))"
    ]

badPanicCauseMismatchSuffix :: String
badPanicCauseMismatchSuffix =
  unlines
    [ "(claim bad-panic-entry (Eff BootIO (KernelPanicked PanicOom) Unit))"
    , "(def bad-panic-entry"
    , "  (io-seq BootIO SerialReady (KernelPanicked PanicOom)"
    , "    serial-init"
    , "    kernel-panic-smoke))"
    ]

badPanicCauseCrossMismatchSuffix :: String
badPanicCauseCrossMismatchSuffix =
  unlines
    [ "(claim bad-panic-invariant-as-oom (Eff SerialReady (KernelPanicked PanicOom) Unit))"
    , "(def bad-panic-invariant-as-oom"
    , "  kernel-panic-invariant)"
    ]

badMessageLengthMismatchSuffix :: String
badMessageLengthMismatchSuffix =
  unlines
    [ "(claim bad-message-length (Eff SerialReady SerialReady Unit))"
    , "(def bad-message-length"
    , "  (serial-write-msg11 limine-ok-message))"
    ]

lowLevelSource :: String
lowLevelSource =
  unlines
    [ "(claim aligned-page U64)"
    , "(def aligned-page (u64-shl (u64-shr (u64 8201) (u64 12)) (u64 12)))"
    , "(claim u64-size U64)"
    , "(def u64-size (size-of U64))"
    , "(claim u64-align U64)"
    , "(def u64-align (align-of U64))"
    , "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(claim header-size U64)"
    , "(def header-size (size-of Header))"
    , "(claim header-align U64)"
    , "(def header-align (align-of Header))"
    , "(claim header-magic-offset U64)"
    , "(def header-magic-offset (field-offset Header magic))"
    , "(claim header-next-offset U64)"
    , "(def header-next-offset (field-offset Header next))"
    , "(claim align-up (Pi ((x U64) (align U64)) U64))"
    , "(def align-up"
    , "  (fn ((x U64) (align U64))"
    , "    (u64-mul"
    , "      (u64-div (u64-add x (u64-sub align (u64 1))) align)"
    , "      align)))"
    , "(claim aligned-up U64)"
    , "(def aligned-up (align-up (u64 4105) (u64 4096)))"
    , "(claim page-count (Pi ((bytes U64)) U64))"
    , "(def page-count"
    , "  (fn ((bytes U64))"
    , "    (u64-div (u64-add bytes (u64 4095)) (u64 4096))))"
    , "(claim page-count-5000 U64)"
    , "(def page-count-5000 (page-count (u64 5000)))"
    , "(claim heap-base Addr)"
    , "(def heap-base (addr 4096))"
    , "(claim heap-next Addr)"
    , "(def heap-next (addr-add heap-base (u64 64)))"
    , "(claim heap-span U64)"
    , "(def heap-span (addr-diff heap-next heap-base))"
    , "(claim same-heap-base Bool)"
    , "(def same-heap-base (addr-eq heap-base (addr 4096)))"
    , "(claim heap-ptr (Ptr U64))"
    , "(def heap-ptr (ptr-from-addr U64 heap-base))"
    , "(claim heap-ptr-next (Ptr U64))"
    , "(def heap-ptr-next (ptr-add U64 heap-ptr (u64 8)))"
    , "(claim heap-ptr-addr Addr)"
    , "(def heap-ptr-addr (ptr-to-addr U64 heap-ptr-next))"
    , "(claim heap-ptr-step (Ptr U64))"
    , "(def heap-ptr-step (ptr-step U64 heap-ptr (u64 1)))"
    , "(claim heap-ptr-step-addr Addr)"
    , "(def heap-ptr-step-addr (ptr-to-addr U64 heap-ptr-step))"
    , "(claim header-base (Ptr Header))"
    , "(def header-base (ptr-from-addr Header (addr 8192)))"
    , "(claim header-magic-ptr (Ptr U64))"
    , "(def header-magic-ptr (ptr-field Header magic header-base))"
    , "(claim header-next-ptr (Ptr Addr))"
    , "(def header-next-ptr (ptr-field Header next header-base))"
    , "(claim header-next-ptr-addr Addr)"
    , "(def header-next-ptr-addr (ptr-to-addr Addr header-next-ptr))"
    , "(claim header-step (Ptr Header))"
    , "(def header-step (ptr-step Header header-base (u64 2)))"
    , "(claim header-step-addr Addr)"
    , "(def header-step-addr (ptr-to-addr Header header-step))"
    , "(claim bump-addr (Pi ((base Addr) (bytes U64)) Addr))"
    , "(def bump-addr (fn ((base Addr) (bytes U64)) (addr-add base bytes)))"
    , "(claim bump-ptr (Pi ((base (Ptr U64)) (bytes U64)) (Ptr U64)))"
    , "(def bump-ptr (fn ((base (Ptr U64)) (bytes U64)) (ptr-add U64 base bytes)))"
    , "(claim step-ptr (Pi ((base (Ptr U64)) (count U64)) (Ptr U64)))"
    , "(def step-ptr (fn ((base (Ptr U64)) (count U64)) (ptr-step U64 base count)))"
    , "(claim step-header (Pi ((base (Ptr Header)) (count U64)) (Ptr Header)))"
    , "(def step-header (fn ((base (Ptr Header)) (count U64)) (ptr-step Header base count)))"
    ]

externSource :: String
externSource =
  unlines
    [ "(extern host-add3 (Pi ((x U64)) U64) host_add3)"
    , "(claim call-host-add3 (Pi ((x U64)) U64))"
    , "(def call-host-add3 (fn ((x U64)) (host-add3 x)))"
    , "(extern host-bump (Pi ((base Addr) (bytes U64)) Addr) host_bump)"
    , "(claim call-host-bump (Pi ((base Addr) (bytes U64)) Addr))"
    , "(def call-host-bump (fn ((base Addr) (bytes U64)) (host-bump base bytes)))"
    ]

memorySource :: String
memorySource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(data HeapCell0 ())"
    , "(data HeapCell1 ())"
    , "(data HeaderClean ())"
    , "(data HeaderDirty ())"
    , "(claim read-word (Pi ((ptr (Ptr U64))) (Eff Heap U64)))"
    , "(def read-word"
    , "  (fn ((ptr (Ptr U64)))"
    , "    (load U64 ptr)))"
    , "(claim write-word (Pi ((ptr (Ptr U64)) (value U64)) (Eff Heap Unit)))"
    , "(def write-word"
    , "  (fn ((ptr (Ptr U64)) (value U64))"
    , "    (store U64 ptr value)))"
    , "(claim seed-word-token (Pi ((ptr (Ptr U64)) (value U64)) (Eff HeapCell0 HeapCell1 Unit)))"
    , "(def seed-word-token"
    , "  (fn ((ptr (Ptr U64)) (value U64))"
    , "    (store HeapCell0 HeapCell1 U64 ptr value)))"
    , "(claim seed-and-read-token (Pi ((ptr (Ptr U64)) (value U64)) (Eff HeapCell0 HeapCell1 U64)))"
    , "(def seed-and-read-token"
    , "  (fn ((ptr (Ptr U64)) (value U64))"
    , "    (bind HeapCell0 HeapCell1 HeapCell1 Unit U64"
    , "      (store HeapCell0 HeapCell1 U64 ptr value)"
    , "      (fn ((done 1 Unit))"
    , "        (let ((ignored 0 done))"
    , "          (load HeapCell1 U64 ptr))))))"
    , "(claim increment-word (Pi ((ptr (Ptr U64))) (Eff Heap U64)))"
    , "(def increment-word"
    , "  (fn ((ptr (Ptr U64)))"
    , "    (bind Heap U64 U64"
    , "      (load U64 ptr)"
    , "      (fn ((x 1 U64))"
    , "        (bind Heap Unit U64"
    , "          (store U64 ptr (u64-add x (u64 1)))"
    , "          (fn ((done 1 Unit))"
    , "            (let ((ignored 0 done))"
    , "              (load U64 ptr))))))))"
    , "(claim bump-and-read (Pi ((base (Ptr U64))) (Eff Heap U64)))"
    , "(def bump-and-read"
    , "  (fn ((base (Ptr U64)))"
    , "    (load U64 (ptr-step U64 base (u64 1)))))"
    , "(claim read-next (Pi ((ptr (Ptr Addr))) (Eff Heap Addr)))"
    , "(def read-next"
    , "  (fn ((ptr (Ptr Addr)))"
    , "    (load Addr ptr)))"
    , "(claim write-next (Pi ((ptr (Ptr Addr)) (value Addr)) (Eff Heap Unit)))"
    , "(def write-next"
    , "  (fn ((ptr (Ptr Addr)) (value Addr))"
    , "    (store Addr ptr value)))"
    , "(claim header-magic-ptr (Pi ((hdr (Ptr Header))) (Ptr U64)))"
    , "(def header-magic-ptr"
    , "  (fn ((hdr (Ptr Header)))"
    , "    (ptr-field Header magic hdr)))"
    , "(claim header-next-ptr (Pi ((hdr (Ptr Header))) (Ptr Addr)))"
    , "(def header-next-ptr"
    , "  (fn ((hdr (Ptr Header)))"
    , "    (ptr-field Header next hdr)))"
    , "(claim read-header-magic (Pi ((hdr (Ptr Header))) (Eff Heap U64)))"
    , "(def read-header-magic"
    , "  (fn ((hdr (Ptr Header)))"
    , "    (load-field Header magic hdr)))"
    , "(claim read-header-next (Pi ((hdr (Ptr Header))) (Eff Heap Addr)))"
    , "(def read-header-next"
    , "  (fn ((hdr (Ptr Header)))"
    , "    (load-field Header next hdr)))"
    , "(claim read-header-next-via-layout (Pi ((hdr (Ptr Header))) (Eff Heap Addr)))"
    , "(def read-header-next-via-layout"
    , "  (fn ((hdr (Ptr Header)))"
    , "    (let-load-layout Header ((magic 0 ignored) (next next)) hdr"
    , "      (pure Heap Addr next))))"
    , "(claim write-header-next (Pi ((hdr (Ptr Header)) (value Addr)) (Eff Heap Unit)))"
    , "(def write-header-next"
    , "  (fn ((hdr (Ptr Header)) (value Addr))"
    , "    (store-field Header next hdr value)))"
    , "(claim write-header-next-token (Pi ((hdr (Ptr Header)) (value Addr)) (Eff HeaderClean HeaderDirty Unit)))"
    , "(def write-header-next-token"
    , "  (fn ((hdr (Ptr Header)) (value Addr))"
    , "    (store-field HeaderClean HeaderDirty Header next hdr value)))"
    , "(claim read-header-next-token (Pi ((hdr (Ptr Header))) (Eff HeaderDirty Addr)))"
    , "(def read-header-next-token"
    , "  (fn ((hdr (Ptr Header)))"
    , "    (load-field HeaderDirty Header next hdr)))"
    , "(claim read-header-next-via-layout-token (Pi ((hdr (Ptr Header))) (Eff HeaderDirty Addr)))"
    , "(def read-header-next-via-layout-token"
    , "  (fn ((hdr (Ptr Header)))"
    , "    (let-load-layout HeaderDirty Header ((magic 0 ignored) (next next)) hdr"
    , "      (pure HeaderDirty Addr next))))"
    , "(claim write-header-fields (Pi ((hdr (Ptr Header)) (magic U64) (next-addr Addr)) (Eff Heap Unit)))"
    , "(def write-header-fields"
    , "  (fn ((hdr (Ptr Header)) (magic U64) (next-addr Addr))"
    , "    (store-fields Header hdr"
    , "      ((magic magic)"
    , "       (next next-addr)))))"
    , "(claim write-header-fields-token (Pi ((hdr (Ptr Header)) (magic U64) (next-addr Addr)) (Eff HeaderDirty Unit)))"
    , "(def write-header-fields-token"
    , "  (fn ((hdr (Ptr Header)) (magic U64) (next-addr Addr))"
    , "    (store-fields HeaderDirty Header hdr"
    , "      ((magic magic)"
    , "       (next next-addr)))))"
    , "(claim override-header-next (Pi ((hdr (Ptr Header))) (Eff Heap Unit)))"
    , "(def override-header-next"
    , "  (fn ((hdr (Ptr Header)))"
    , "    (store-fields Header hdr"
    , "      ((next (addr 8192))"
    , "       (next (addr 12288))))))"
    , "(claim header-next-offset U64)"
    , "(def header-next-offset (field-offset Header next))"
    , "(claim copy-header (Pi ((src (Ptr Header)) (dst (Ptr Header))) (Eff Heap Unit)))"
    , "(def copy-header"
    , "  (fn ((src (Ptr Header)) (dst (Ptr Header)))"
    , "    (bind Heap Header Unit"
    , "      (load Header src)"
    , "      (fn ((hdr 1 Header))"
    , "        (store Header dst hdr)))))"
    ]

abiSource :: String
abiSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(extern header-magic (Pi ((hdr Header)) U64) header_magic)"
    , "(extern header-zero (Pi ((ptr (Ptr Header))) Unit) header_zero)"
    , "(claim inspect-header (Pi ((ptr (Ptr Header))) (Eff Heap U64)))"
    , "(def inspect-header"
    , "  (fn ((ptr (Ptr Header)))"
    , "    (bind Heap Header U64"
    , "      (load Header ptr)"
    , "      (fn ((hdr 1 Header))"
    , "        (pure Heap U64 (header-magic hdr))))))"
    , "(claim call-header-zero (Pi ((ptr (Ptr Header))) Unit))"
    , "(def call-header-zero"
    , "  (fn ((ptr (Ptr Header)))"
    , "    (header-zero ptr)))"
    ]

freestandingSource :: String
freestandingSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(extern platform-header-magic (Pi ((hdr Header)) U64) platform_header_magic)"
    , "(extern platform-header-zero (Pi ((ptr (Ptr Header))) Unit) platform_header_zero)"
    , "(calling-convention platform-header-magic sysv-abi)"
    , "(abi-contract platform-header-magic"
    , "  ((symbol platform_header_magic)"
    , "   (calling-convention sysv-abi)"
    , "   (freestanding)))"
    , "(data BootHeap0 ())"
    , "(data BootHeap1 ())"
    , "(claim boot-header Header)"
    , "(def boot-header"
    , "  (layout Header"
    , "    ((magic (u64 305419896))"
    , "     (next (addr 0)))))"
    , "(claim boot-header-at (Pi ((next-addr Addr)) Header))"
    , "(def boot-header-at"
    , "  (fn ((next-addr Addr))"
    , "    (with-field Header next boot-header next-addr)))"
    , "(claim boot-header-remap (Pi ((magic U64) (next-addr Addr)) Header))"
    , "(def boot-header-remap"
    , "  (fn ((magic U64) (next-addr Addr))"
    , "    (with-fields Header boot-header"
    , "      ((magic magic)"
    , "       (next next-addr)))))"
    , "(claim boot-header-next Addr)"
    , "(def boot-header-next"
    , "  (let-layout Header ((next next)) boot-header next))"
    , "(claim init-header (Pi ((base (Ptr Header))) (Eff Heap Unit)))"
    , "(def init-header"
    , "  (fn ((base (Ptr Header)))"
    , "    (store Header base (boot-header-at (addr 0)))))"
    , "(claim init-header-token (Pi ((base (Ptr Header))) (Eff BootHeap0 BootHeap1 Unit)))"
    , "(def init-header-token"
    , "  (fn ((base (Ptr Header)))"
    , "    (store BootHeap0 BootHeap1 Header base (boot-header-at (addr 0)))))"
    , "(claim read-magic (Pi ((base (Ptr Header))) (Eff Heap U64)))"
    , "(def read-magic"
    , "  (fn ((base (Ptr Header)))"
    , "    (load-field Header magic base)))"
    , "(claim read-next-via-layout (Pi ((base (Ptr Header))) (Eff Heap Addr)))"
    , "(def read-next-via-layout"
    , "  (fn ((base (Ptr Header)))"
    , "    (let-load-layout Header ((magic 0 ignored) (next next)) base"
    , "      (pure Heap Addr next))))"
    , "(claim read-next-via-layout-token (Pi ((base (Ptr Header))) (Eff BootHeap1 Addr)))"
    , "(def read-next-via-layout-token"
    , "  (fn ((base (Ptr Header)))"
    , "    (let-load-layout BootHeap1 Header ((magic 0 ignored) (next next)) base"
    , "      (pure BootHeap1 Addr next))))"
    , "(claim inspect-header-platform (Pi ((base (Ptr Header))) (Eff Heap U64)))"
    , "(def inspect-header-platform"
    , "  (fn ((base (Ptr Header)))"
    , "    (bind Heap Header U64"
    , "      (load Header base)"
    , "      (fn ((hdr 1 Header))"
    , "        (pure Heap U64 (platform-header-magic hdr))))))"
    , "(claim boot-entry (Pi ((base (Ptr Header))) (Eff Heap U64)))"
    , "(def boot-entry"
    , "  (fn ((base (Ptr Header)))"
    , "    (inspect-header-platform base)))"
    , "(export boot-entry silt_boot_entry)"
    , "(section boot-entry .text.silt.boot)"
    , "(calling-convention boot-entry sysv-abi)"
    , "(entry boot-entry)"
    , "(abi-contract boot-entry"
    , "  ((entry)"
    , "   (symbol silt_boot_entry)"
    , "   (section .text.silt.boot)"
    , "   (calling-convention sysv-abi)"
    , "   (freestanding)))"
    , "(target-contract x86_64-sysv-elf"
    , "  ((format elf64)"
    , "   (arch x86_64)"
    , "   (abi sysv)"
    , "   (entry boot-entry)"
    , "   (symbol silt_boot_entry)"
    , "   (section .text.silt.boot)"
    , "   (calling-convention sysv-abi)"
    , "   (entry-address 1048576)"
    , "   (red-zone disabled)"
    , "   (freestanding)))"
    , "(claim call-platform-zero (Pi ((base (Ptr Header))) Unit))"
    , "(def call-platform-zero"
    , "  (fn ((base (Ptr Header)))"
    , "    (platform-header-zero base)))"
    , "(claim reset-next (Pi ((base (Ptr Header)) (next-addr Addr)) (Eff Heap Unit)))"
    , "(def reset-next"
    , "  (fn ((base (Ptr Header)) (next-addr Addr))"
    , "    (store-field Header next base next-addr)))"
    , "(claim reset-next-token (Pi ((base (Ptr Header)) (next-addr Addr)) (Eff BootHeap0 BootHeap1 Unit)))"
    , "(def reset-next-token"
    , "  (fn ((base (Ptr Header)) (next-addr Addr))"
    , "    (store-field BootHeap0 BootHeap1 Header next base next-addr)))"
    , "(claim reset-header-fields (Pi ((base (Ptr Header)) (magic U64) (next-addr Addr)) (Eff Heap Unit)))"
    , "(def reset-header-fields"
    , "  (fn ((base (Ptr Header)) (magic U64) (next-addr Addr))"
    , "    (store-fields Header base"
    , "      ((magic magic)"
    , "       (next next-addr)))))"
    , "(claim reset-header-fields-token (Pi ((base (Ptr Header)) (magic U64) (next-addr Addr)) (Eff BootHeap1 Unit)))"
    , "(def reset-header-fields-token"
    , "  (fn ((base (Ptr Header)) (magic U64) (next-addr Addr))"
    , "    (store-fields BootHeap1 Header base"
    , "      ((magic magic)"
    , "       (next next-addr)))))"
    , "(claim init-and-read-token (Pi ((base (Ptr Header))) (Eff BootHeap0 BootHeap1 U64)))"
    , "(def init-and-read-token"
    , "  (fn ((base (Ptr Header)))"
    , "    (bind BootHeap0 BootHeap1 BootHeap1 Unit U64"
    , "      (init-header-token base)"
    , "      (fn ((done 1 Unit))"
    , "        (let ((ignored 0 done))"
    , "          (load-field BootHeap1 Header magic base))))))"
    , "(claim init-and-read (Pi ((base (Ptr Header))) (Eff Heap U64)))"
    , "(def init-and-read"
    , "  (fn ((base (Ptr Header)))"
    , "    (bind Heap Unit U64"
    , "      (init-header base)"
    , "      (fn ((done 1 Unit))"
    , "        (let ((ignored 0 done))"
    , "          (read-magic base))))))"
    ]

capabilitySource :: String
capabilitySource =
  unlines
    [ "(data Owned ((Tok 0 Type) (A 0 Type))"
    , "  (Hold Tok A))"
    , "(data OwnedPtr ((Tok 0 Type) (A 0 Type))"
    , "  (OwnedAt Tok (Ptr A)))"
    , "(data Observed ((Tok 0 Type) (A 0 Type) (V 0 Type))"
    , "  (ObservedAt Tok (Ptr A) V))"
    , "(data OwnedCap ((Tok 0 Type) (Cap 0 Type) (A 0 Type))"
    , "  (OwnedCapAt Tok (Ptr A)))"
    , "(data ObservedCap ((Tok 0 Type) (Cap 0 Type) (A 0 Type) (V 0 Type))"
    , "  (ObservedCapAt Tok (Ptr A) V))"
    , "(data Lease0 ()"
    , "  (lease0))"
    , "(data Lease1 ()"
    , "  (lease1))"
    , "(data WordSlot0 ())"
    , "(data WordSlot1 ())"
    , "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(data HeaderLease0 ()"
    , "  (header-lease0))"
    , "(data HeaderLease1 ()"
    , "  (header-lease1))"
    , "(data HeaderRegion0 ())"
    , "(data HeaderRegion1 ())"
    , "(claim rotate-lease (Pi ((lease 1 Lease0)) Lease1))"
    , "(def rotate-lease"
    , "  (fn ((lease 1 Lease0))"
    , "    (let ((spent 0 lease))"
    , "      lease1)))"
    , "(claim rotated-lease Lease1)"
    , "(def rotated-lease"
    , "  (rotate-lease lease0))"
    , "(claim own (Pi ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (value 1 A)) (Owned Tok A)))"
    , "(def own"
    , "  (fn ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (value 1 A))"
    , "    (Hold Tok A tok value)))"
    , "(claim with-owned"
    , "  (Pi ((Tok 0 Type) (A 0 Type) (B 0 Type)"
    , "       (owned 1 (Owned Tok A))"
    , "       (k 1 (Pi ((tok 1 Tok) (value 1 A)) B)))"
    , "      B))"
    , "(def with-owned"
    , "  (fn ((Tok 0 Type) (A 0 Type) (B 0 Type)"
    , "       (owned 1 (Owned Tok A))"
    , "       (k 1 (Pi ((tok 1 Tok) (value 1 A)) B)))"
    , "    (match owned"
    , "      ((Hold (tok 1) (value 1))"
    , "       (k tok value)))))"
    , "(claim own-ptr (Pi ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (ptr (Ptr A))) (OwnedPtr Tok A)))"
    , "(def own-ptr"
    , "  (fn ((Tok 0 Type) (A 0 Type) (tok 1 Tok) (ptr (Ptr A)))"
    , "    (OwnedAt Tok A tok ptr)))"
    , "(claim with-owned-ptr"
    , "  (Pi ((Tok 0 Type) (A 0 Type) (B 0 Type)"
    , "       (owned 1 (OwnedPtr Tok A))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A))) B)))"
    , "      B))"
    , "(def with-owned-ptr"
    , "  (fn ((Tok 0 Type) (A 0 Type) (B 0 Type)"
    , "       (owned 1 (OwnedPtr Tok A))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A))) B)))"
    , "    (match owned"
    , "      ((OwnedAt (tok 1) ptr)"
    , "       (k tok ptr)))))"
    , "(claim observe"
    , "  (Pi ((Tok 0 Type) (A 0 Type) (V 0 Type)"
    , "       (tok 1 Tok)"
    , "       (ptr (Ptr A))"
    , "       (value 1 V))"
    , "      (Observed Tok A V)))"
    , "(def observe"
    , "  (fn ((Tok 0 Type) (A 0 Type) (V 0 Type)"
    , "       (tok 1 Tok)"
    , "       (ptr (Ptr A))"
    , "       (value 1 V))"
    , "    (ObservedAt Tok A V tok ptr value)))"
    , "(claim with-observed"
    , "  (Pi ((Tok 0 Type) (A 0 Type) (V 0 Type) (B 0 Type)"
    , "       (observed 1 (Observed Tok A V))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A)) (value 1 V)) B)))"
    , "      B))"
    , "(def with-observed"
    , "  (fn ((Tok 0 Type) (A 0 Type) (V 0 Type) (B 0 Type)"
    , "       (observed 1 (Observed Tok A V))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A)) (value 1 V)) B)))"
    , "    (match observed"
    , "      ((ObservedAt (tok 1) ptr (value 1))"
    , "       (k tok ptr value)))))"
    , "(claim own-cap"
    , "  (Pi ((Tok 0 Type) (Cap 0 Type) (A 0 Type)"
    , "       (tok 1 Tok)"
    , "       (ptr (Ptr A)))"
    , "      (OwnedCap Tok Cap A)))"
    , "(def own-cap"
    , "  (fn ((Tok 0 Type) (Cap 0 Type) (A 0 Type)"
    , "       (tok 1 Tok)"
    , "       (ptr (Ptr A)))"
    , "    (OwnedCapAt Tok Cap A tok ptr)))"
    , "(claim with-owned-cap"
    , "  (Pi ((Tok 0 Type) (Cap 0 Type) (A 0 Type) (B 0 Type)"
    , "       (owned 1 (OwnedCap Tok Cap A))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A))) B)))"
    , "      B))"
    , "(def with-owned-cap"
    , "  (fn ((Tok 0 Type) (Cap 0 Type) (A 0 Type) (B 0 Type)"
    , "       (owned 1 (OwnedCap Tok Cap A))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A))) B)))"
    , "    (match owned"
    , "      ((OwnedCapAt (tok 1) ptr)"
    , "       (k tok ptr)))))"
    , "(claim observe-cap"
    , "  (Pi ((Tok 0 Type) (Cap 0 Type) (A 0 Type) (V 0 Type)"
    , "       (tok 1 Tok)"
    , "       (ptr (Ptr A))"
    , "       (value 1 V))"
    , "      (ObservedCap Tok Cap A V)))"
    , "(def observe-cap"
    , "  (fn ((Tok 0 Type) (Cap 0 Type) (A 0 Type) (V 0 Type)"
    , "       (tok 1 Tok)"
    , "       (ptr (Ptr A))"
    , "       (value 1 V))"
    , "    (ObservedCapAt Tok Cap A V tok ptr value)))"
    , "(claim with-observed-cap"
    , "  (Pi ((Tok 0 Type) (Cap 0 Type) (A 0 Type) (V 0 Type) (B 0 Type)"
    , "       (observed 1 (ObservedCap Tok Cap A V))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A)) (value 1 V)) B)))"
    , "      B))"
    , "(def with-observed-cap"
    , "  (fn ((Tok 0 Type) (Cap 0 Type) (A 0 Type) (V 0 Type) (B 0 Type)"
    , "       (observed 1 (ObservedCap Tok Cap A V))"
    , "       (k 1 (Pi ((tok 1 Tok) (ptr (Ptr A)) (value 1 V)) B)))"
    , "    (match observed"
    , "      ((ObservedCapAt (tok 1) ptr (value 1))"
    , "       (k tok ptr value)))))"
    , "(claim forget-owned-cap"
    , "  (Pi ((Tok 0 Type) (Cap 0 Type) (A 0 Type)"
    , "       (owned 1 (OwnedCap Tok Cap A)))"
    , "      (OwnedPtr Tok A)))"
    , "(def forget-owned-cap"
    , "  (fn ((Tok 0 Type) (Cap 0 Type) (A 0 Type)"
    , "       (owned 1 (OwnedCap Tok Cap A)))"
    , "    (with-owned-cap Tok Cap A (OwnedPtr Tok A) owned"
    , "      (fn ((tok 1 Tok) (ptr (Ptr A)))"
    , "        (own-ptr Tok A tok ptr)))))"
    , "(claim forget-observed-cap"
    , "  (Pi ((Tok 0 Type) (Cap 0 Type) (A 0 Type) (V 0 Type)"
    , "       (observed 1 (ObservedCap Tok Cap A V)))"
    , "      (Observed Tok A V)))"
    , "(def forget-observed-cap"
    , "  (fn ((Tok 0 Type) (Cap 0 Type) (A 0 Type) (V 0 Type)"
    , "       (observed 1 (ObservedCap Tok Cap A V)))"
    , "    (with-observed-cap Tok Cap A V (Observed Tok A V) observed"
    , "      (fn ((tok 1 Tok) (ptr (Ptr A)) (value 1 V))"
    , "        (observe Tok A V tok ptr value)))))"
    , "(claim wrap-lease (Pi ((lease 1 Lease0)) (Owned Lease1 Lease1)))"
    , "(def wrap-lease"
    , "  (fn ((lease 1 Lease0))"
    , "    (let ((spent 0 lease))"
    , "      (own Lease1 Lease1 lease1 lease1))))"
    , "(claim unpack-owned-lease (Pi ((owned 1 (Owned Lease1 Lease1))) Lease1))"
    , "(def unpack-owned-lease"
    , "  (fn ((owned 1 (Owned Lease1 Lease1)))"
    , "    (with-owned Lease1 Lease1 Lease1 owned"
    , "      (fn ((tok 1 Lease1) (value 1 Lease1))"
    , "        (let ((spent 0 tok))"
    , "          value)))))"
    , "(claim unpacked-owned-lease Lease1)"
    , "(def unpacked-owned-lease"
    , "  (unpack-owned-lease (wrap-lease lease0)))"
    , "(claim word-base (Ptr U64))"
    , "(def word-base"
    , "  (ptr-from-addr U64 (addr 4096)))"
    , "(claim header-base (Ptr Header))"
    , "(def header-base"
    , "  (ptr-from-addr Header (addr 8192)))"
    , "(claim retag-owned-word-handle (Pi ((owned 1 (OwnedPtr Lease0 U64))) (OwnedPtr Lease1 U64)))"
    , "(def retag-owned-word-handle"
    , "  (fn ((owned 1 (OwnedPtr Lease0 U64)))"
    , "    (with-owned-ptr Lease0 U64 (OwnedPtr Lease1 U64) owned"
    , "      (fn ((lease 1 Lease0) (ptr (Ptr U64)))"
    , "        (let ((spent 0 lease))"
    , "          (own-ptr Lease1 U64 lease1 ptr))))))"
    , "(claim retagged-word-handle (OwnedPtr Lease1 U64))"
    , "(def retagged-word-handle"
    , "  (retag-owned-word-handle (own-ptr Lease0 U64 lease0 word-base)))"
    , "(claim recover-word-handle (Pi ((observed 1 (Observed Lease1 U64 U64))) (OwnedPtr Lease1 U64)))"
    , "(def recover-word-handle"
    , "  (fn ((observed 1 (Observed Lease1 U64 U64)))"
    , "    (with-observed Lease1 U64 U64 (OwnedPtr Lease1 U64) observed"
    , "      (fn ((lease 1 Lease1) (ptr (Ptr U64)) (value 1 U64))"
    , "        (let ((ignored 0 value))"
    , "          (own-ptr Lease1 U64 lease ptr))))))"
    , "(claim restored-word-handle (OwnedPtr Lease1 U64))"
    , "(def restored-word-handle"
    , "  (recover-word-handle (observe Lease1 U64 U64 lease1 word-base (u64 91))))"
    , "(claim word-cap-handle (OwnedCap Lease1 WordSlot1 U64))"
    , "(def word-cap-handle"
    , "  (own-cap Lease1 WordSlot1 U64 lease1 word-base))"
    , "(claim forgot-word-cap-handle (OwnedPtr Lease1 U64))"
    , "(def forgot-word-cap-handle"
    , "  (forget-owned-cap Lease1 WordSlot1 U64 word-cap-handle))"
    , "(claim word-cap-observed (ObservedCap Lease1 WordSlot1 U64 U64))"
    , "(def word-cap-observed"
    , "  (observe-cap Lease1 WordSlot1 U64 U64 lease1 word-base (u64 33)))"
    , "(claim forgot-word-cap-observed (Observed Lease1 U64 U64))"
    , "(def forgot-word-cap-observed"
    , "  (forget-observed-cap Lease1 WordSlot1 U64 U64 word-cap-observed))"
    , "(claim observed-word-value (Pi ((observed 1 (Observed Lease1 U64 U64))) U64))"
    , "(def observed-word-value"
    , "  (fn ((observed 1 (Observed Lease1 U64 U64)))"
    , "    (with-observed Lease1 U64 U64 U64 observed"
    , "      (fn ((lease 1 Lease1) (ptr (Ptr U64)) (value 1 U64))"
    , "        (let ((spent 0 lease)"
    , "              (ignored 0 ptr))"
    , "          value)))))"
    , "(claim observed-sample-value U64)"
    , "(def observed-sample-value"
    , "  (observed-word-value (observe Lease1 U64 U64 lease1 word-base (u64 77))))"
    , "(claim seed-owned-word (Pi ((lease 1 Lease0) (ptr (Ptr U64)) (value U64)) (Eff WordSlot0 WordSlot1 (Owned Lease1 Unit))))"
    , "(def seed-owned-word"
    , "  (fn ((lease 1 Lease0) (ptr (Ptr U64)) (value U64))"
    , "    (bind WordSlot0 WordSlot1 WordSlot1 Unit (Owned Lease1 Unit)"
    , "      (store WordSlot0 WordSlot1 U64 ptr value)"
    , "      (fn ((done 1 Unit))"
    , "        (let ((ignored 0 done)"
    , "              (spent 0 lease))"
    , "          (pure WordSlot1 (Owned Lease1 Unit) (own Lease1 Unit lease1 tt)))))))"
    , "(claim read-owned-word (Pi ((lease 1 Lease1) (ptr (Ptr U64))) (Eff WordSlot1 WordSlot1 (Owned Lease1 U64))))"
    , "(def read-owned-word"
    , "  (fn ((lease 1 Lease1) (ptr (Ptr U64)))"
    , "    (bind WordSlot1 WordSlot1 WordSlot1 U64 (Owned Lease1 U64)"
    , "      (load WordSlot1 U64 ptr)"
    , "      (fn ((value 1 U64))"
    , "        (let ((spent 0 lease))"
    , "          (pure WordSlot1 (Owned Lease1 U64) (own Lease1 U64 lease1 value)))))))"
    , "(claim seed-owned-word-handle (Pi ((owned 1 (OwnedPtr Lease0 U64)) (value U64)) (Eff WordSlot0 WordSlot1 (OwnedPtr Lease1 U64))))"
    , "(def seed-owned-word-handle"
    , "  (fn ((owned 1 (OwnedPtr Lease0 U64)) (value U64))"
    , "    (with-owned-ptr Lease0 U64 (Eff WordSlot0 WordSlot1 (OwnedPtr Lease1 U64)) owned"
    , "      (fn ((lease 1 Lease0) (ptr (Ptr U64)))"
    , "        (bind WordSlot0 WordSlot1 WordSlot1 Unit (OwnedPtr Lease1 U64)"
    , "          (store WordSlot0 WordSlot1 U64 ptr value)"
    , "          (fn ((done 1 Unit))"
    , "            (let ((ignored 0 done)"
    , "                  (spent 0 lease))"
    , "              (pure WordSlot1 (OwnedPtr Lease1 U64) (own-ptr Lease1 U64 lease1 ptr)))))))))"
    , "(claim read-owned-word-handle (Pi ((owned 1 (OwnedPtr Lease1 U64))) (Eff WordSlot1 WordSlot1 (Observed Lease1 U64 U64))))"
    , "(def read-owned-word-handle"
    , "  (fn ((owned 1 (OwnedPtr Lease1 U64)))"
    , "    (with-owned-ptr Lease1 U64 (Eff WordSlot1 WordSlot1 (Observed Lease1 U64 U64)) owned"
    , "      (fn ((lease 1 Lease1) (ptr (Ptr U64)))"
    , "        (bind WordSlot1 WordSlot1 WordSlot1 U64 (Observed Lease1 U64 U64)"
    , "          (load WordSlot1 U64 ptr)"
    , "          (fn ((value 1 U64))"
    , "            (pure WordSlot1 (Observed Lease1 U64 U64) (observe Lease1 U64 U64 lease ptr value))))))))"
    , "(claim read-owned-word-cap (Pi ((owned 1 (OwnedCap Lease1 WordSlot1 U64))) (Eff WordSlot1 WordSlot1 (ObservedCap Lease1 WordSlot1 U64 U64))))"
    , "(def read-owned-word-cap"
    , "  (fn ((owned 1 (OwnedCap Lease1 WordSlot1 U64)))"
    , "    (with-owned-cap Lease1 WordSlot1 U64 (Eff WordSlot1 WordSlot1 (ObservedCap Lease1 WordSlot1 U64 U64)) owned"
    , "      (fn ((lease 1 Lease1) (ptr (Ptr U64)))"
    , "        (bind WordSlot1 WordSlot1 WordSlot1 U64 (ObservedCap Lease1 WordSlot1 U64 U64)"
    , "          (load WordSlot1 U64 ptr)"
    , "          (fn ((value 1 U64))"
    , "            (pure WordSlot1 (ObservedCap Lease1 WordSlot1 U64 U64) (observe-cap Lease1 WordSlot1 U64 U64 lease ptr value))))))))"
    , "(claim increment-word-value (Pi ((old 1 U64)) U64))"
    , "(def increment-word-value"
    , "  (fn ((old 1 U64))"
    , "    (u64-add old (u64 1))))"
    , "(claim incremented-sample-word U64)"
    , "(def incremented-sample-word"
    , "  (increment-word-value (u64 7)))"
    , "(claim rewrite-owned-word-handle"
    , "  (Pi ((owned 1 (OwnedPtr Lease1 U64))"
    , "       (step 1 (Pi ((old 1 U64)) U64)))"
    , "      (Eff WordSlot1 WordSlot1 (OwnedPtr Lease1 U64))))"
    , "(def rewrite-owned-word-handle"
    , "  (fn ((owned 1 (OwnedPtr Lease1 U64))"
    , "       (step 1 (Pi ((old 1 U64)) U64)))"
    , "    (bind WordSlot1 WordSlot1 WordSlot1 (Observed Lease1 U64 U64) (OwnedPtr Lease1 U64)"
    , "      (read-owned-word-handle owned)"
    , "      (fn ((observed 1 (Observed Lease1 U64 U64)))"
    , "        (with-observed Lease1 U64 U64 (Eff WordSlot1 WordSlot1 (OwnedPtr Lease1 U64)) observed"
    , "          (fn ((lease 1 Lease1) (ptr (Ptr U64)) (old 1 U64))"
    , "            (bind WordSlot1 WordSlot1 WordSlot1 Unit (OwnedPtr Lease1 U64)"
    , "              (store WordSlot1 WordSlot1 U64 ptr (step old))"
    , "              (fn ((done 1 Unit))"
    , "                (let ((ignored 0 done))"
    , "                  (pure WordSlot1 (OwnedPtr Lease1 U64) (own-ptr Lease1 U64 lease ptr)))))))))))"
    , "(claim rewrite-owned-word-cap"
    , "  (Pi ((owned 1 (OwnedCap Lease1 WordSlot1 U64))"
    , "       (step 1 (Pi ((old 1 U64)) U64)))"
    , "      (Eff WordSlot1 WordSlot1 (OwnedCap Lease1 WordSlot1 U64))))"
    , "(def rewrite-owned-word-cap"
    , "  (fn ((owned 1 (OwnedCap Lease1 WordSlot1 U64))"
    , "       (step 1 (Pi ((old 1 U64)) U64)))"
    , "    (bind WordSlot1 WordSlot1 WordSlot1 (ObservedCap Lease1 WordSlot1 U64 U64) (OwnedCap Lease1 WordSlot1 U64)"
    , "      (read-owned-word-cap owned)"
    , "      (fn ((observed 1 (ObservedCap Lease1 WordSlot1 U64 U64)))"
    , "        (with-observed-cap Lease1 WordSlot1 U64 U64 (Eff WordSlot1 WordSlot1 (OwnedCap Lease1 WordSlot1 U64)) observed"
    , "          (fn ((lease 1 Lease1) (ptr (Ptr U64)) (old 1 U64))"
    , "            (bind WordSlot1 WordSlot1 WordSlot1 Unit (OwnedCap Lease1 WordSlot1 U64)"
    , "              (store WordSlot1 WordSlot1 U64 ptr (step old))"
    , "              (fn ((done 1 Unit))"
    , "                (let ((ignored 0 done))"
    , "                  (pure WordSlot1 (OwnedCap Lease1 WordSlot1 U64) (own-cap Lease1 WordSlot1 U64 lease ptr)))))))))))"
    , "(claim increment-owned-word-handle (Pi ((owned 1 (OwnedPtr Lease1 U64))) (Eff WordSlot1 WordSlot1 (OwnedPtr Lease1 U64))))"
    , "(def increment-owned-word-handle"
    , "  (fn ((owned 1 (OwnedPtr Lease1 U64)))"
    , "    (rewrite-owned-word-handle owned increment-word-value)))"
    , "(claim write-owned-header-next (Pi ((lease 1 HeaderLease0) (hdr (Ptr Header)) (next-addr Addr)) (Eff HeaderRegion0 HeaderRegion1 (Owned HeaderLease1 Unit))))"
    , "(def write-owned-header-next"
    , "  (fn ((lease 1 HeaderLease0) (hdr (Ptr Header)) (next-addr Addr))"
    , "    (bind HeaderRegion0 HeaderRegion1 HeaderRegion1 Unit (Owned HeaderLease1 Unit)"
    , "      (store-field HeaderRegion0 HeaderRegion1 Header next hdr next-addr)"
    , "      (fn ((done 1 Unit))"
    , "        (let ((ignored 0 done)"
    , "              (spent 0 lease))"
    , "          (pure HeaderRegion1 (Owned HeaderLease1 Unit) (own HeaderLease1 Unit header-lease1 tt)))))))"
    , "(claim read-owned-header-next (Pi ((lease 1 HeaderLease1) (hdr (Ptr Header))) (Eff HeaderRegion1 HeaderRegion1 (Owned HeaderLease1 Addr))))"
    , "(def read-owned-header-next"
    , "  (fn ((lease 1 HeaderLease1) (hdr (Ptr Header)))"
    , "    (bind HeaderRegion1 HeaderRegion1 HeaderRegion1 Addr (Owned HeaderLease1 Addr)"
    , "      (load-field HeaderRegion1 Header next hdr)"
    , "      (fn ((value 1 Addr))"
    , "        (let ((spent 0 lease))"
    , "          (pure HeaderRegion1 (Owned HeaderLease1 Addr) (own HeaderLease1 Addr header-lease1 value)))))))"
    , "(claim read-owned-header-next-handle (Pi ((owned 1 (OwnedPtr HeaderLease1 Header))) (Eff HeaderRegion1 HeaderRegion1 (Observed HeaderLease1 Header Addr))))"
    , "(def read-owned-header-next-handle"
    , "  (fn ((owned 1 (OwnedPtr HeaderLease1 Header)))"
    , "    (with-owned-ptr HeaderLease1 Header (Eff HeaderRegion1 HeaderRegion1 (Observed HeaderLease1 Header Addr)) owned"
    , "      (fn ((lease 1 HeaderLease1) (hdr (Ptr Header)))"
    , "        (bind HeaderRegion1 HeaderRegion1 HeaderRegion1 Addr (Observed HeaderLease1 Header Addr)"
    , "          (load-field HeaderRegion1 Header next hdr)"
    , "          (fn ((value 1 Addr))"
    , "            (pure HeaderRegion1 (Observed HeaderLease1 Header Addr) (observe HeaderLease1 Header Addr lease hdr value))))))))"
    , "(claim header-cap-handle (OwnedCap HeaderLease1 HeaderRegion1 Header))"
    , "(def header-cap-handle"
    , "  (own-cap HeaderLease1 HeaderRegion1 Header header-lease1 header-base))"
    , "(claim forgot-header-cap-handle (OwnedPtr HeaderLease1 Header))"
    , "(def forgot-header-cap-handle"
    , "  (forget-owned-cap HeaderLease1 HeaderRegion1 Header header-cap-handle))"
    , "(claim read-owned-header-next-cap (Pi ((owned 1 (OwnedCap HeaderLease1 HeaderRegion1 Header))) (Eff HeaderRegion1 HeaderRegion1 (ObservedCap HeaderLease1 HeaderRegion1 Header Addr))))"
    , "(def read-owned-header-next-cap"
    , "  (fn ((owned 1 (OwnedCap HeaderLease1 HeaderRegion1 Header)))"
    , "    (with-owned-cap HeaderLease1 HeaderRegion1 Header (Eff HeaderRegion1 HeaderRegion1 (ObservedCap HeaderLease1 HeaderRegion1 Header Addr)) owned"
    , "      (fn ((lease 1 HeaderLease1) (hdr (Ptr Header)))"
    , "        (bind HeaderRegion1 HeaderRegion1 HeaderRegion1 Addr (ObservedCap HeaderLease1 HeaderRegion1 Header Addr)"
    , "          (load-field HeaderRegion1 Header next hdr)"
    , "          (fn ((value 1 Addr))"
    , "            (pure HeaderRegion1 (ObservedCap HeaderLease1 HeaderRegion1 Header Addr) (observe-cap HeaderLease1 HeaderRegion1 Header Addr lease hdr value))))))))"
    , "(claim write-owned-header-next-handle (Pi ((owned 1 (OwnedPtr HeaderLease0 Header)) (next-addr Addr)) (Eff HeaderRegion0 HeaderRegion1 (OwnedPtr HeaderLease1 Header))))"
    , "(def write-owned-header-next-handle"
    , "  (fn ((owned 1 (OwnedPtr HeaderLease0 Header)) (next-addr Addr))"
    , "    (with-owned-ptr HeaderLease0 Header (Eff HeaderRegion0 HeaderRegion1 (OwnedPtr HeaderLease1 Header)) owned"
    , "      (fn ((lease 1 HeaderLease0) (hdr (Ptr Header)))"
    , "        (bind HeaderRegion0 HeaderRegion1 HeaderRegion1 Unit (OwnedPtr HeaderLease1 Header)"
    , "          (store-field HeaderRegion0 HeaderRegion1 Header next hdr next-addr)"
    , "          (fn ((done 1 Unit))"
    , "            (let ((ignored 0 done)"
    , "                  (spent 0 lease))"
    , "              (pure HeaderRegion1 (OwnedPtr HeaderLease1 Header) (own-ptr HeaderLease1 Header header-lease1 hdr)))))))))"
    , "(claim rewrite-observed-header-next (Pi ((observed 1 (Observed HeaderLease1 Header Addr)) (next-addr Addr)) (Eff HeaderRegion1 HeaderRegion1 (OwnedPtr HeaderLease1 Header))))"
    , "(def rewrite-observed-header-next"
    , "  (fn ((observed 1 (Observed HeaderLease1 Header Addr)) (next-addr Addr))"
    , "    (with-observed HeaderLease1 Header Addr (Eff HeaderRegion1 HeaderRegion1 (OwnedPtr HeaderLease1 Header)) observed"
    , "      (fn ((lease 1 HeaderLease1) (hdr (Ptr Header)) (old-next 1 Addr))"
    , "        (let ((ignored-old 0 old-next))"
    , "          (bind HeaderRegion1 HeaderRegion1 HeaderRegion1 Unit (OwnedPtr HeaderLease1 Header)"
    , "            (store-field HeaderRegion1 HeaderRegion1 Header next hdr next-addr)"
    , "            (fn ((done 1 Unit))"
    , "              (let ((ignored 0 done))"
    , "                (pure HeaderRegion1 (OwnedPtr HeaderLease1 Header) (own-ptr HeaderLease1 Header lease hdr))))))))))"
    , "(claim advance-header-next-value (Pi ((old-next 1 Addr)) Addr))"
    , "(def advance-header-next-value"
    , "  (fn ((old-next 1 Addr))"
    , "    (addr-add old-next (u64 4096))))"
    , "(claim advanced-sample-next Addr)"
    , "(def advanced-sample-next"
    , "  (advance-header-next-value (addr 4096)))"
    , "(claim rewrite-owned-header-next-handle"
    , "  (Pi ((owned 1 (OwnedPtr HeaderLease1 Header))"
    , "       (step 1 (Pi ((old-next 1 Addr)) Addr)))"
    , "      (Eff HeaderRegion1 HeaderRegion1 (OwnedPtr HeaderLease1 Header))))"
    , "(def rewrite-owned-header-next-handle"
    , "  (fn ((owned 1 (OwnedPtr HeaderLease1 Header))"
    , "       (step 1 (Pi ((old-next 1 Addr)) Addr)))"
    , "    (bind HeaderRegion1 HeaderRegion1 HeaderRegion1 (Observed HeaderLease1 Header Addr) (OwnedPtr HeaderLease1 Header)"
    , "      (read-owned-header-next-handle owned)"
    , "      (fn ((observed 1 (Observed HeaderLease1 Header Addr)))"
    , "        (with-observed HeaderLease1 Header Addr (Eff HeaderRegion1 HeaderRegion1 (OwnedPtr HeaderLease1 Header)) observed"
    , "          (fn ((lease 1 HeaderLease1) (hdr (Ptr Header)) (old-next 1 Addr))"
    , "            (bind HeaderRegion1 HeaderRegion1 HeaderRegion1 Unit (OwnedPtr HeaderLease1 Header)"
    , "              (store-field HeaderRegion1 HeaderRegion1 Header next hdr (step old-next))"
    , "              (fn ((done 1 Unit))"
    , "                (let ((ignored 0 done))"
    , "                  (pure HeaderRegion1 (OwnedPtr HeaderLease1 Header) (own-ptr HeaderLease1 Header lease hdr)))))))))))"
    , "(claim rewrite-owned-header-next-cap"
    , "  (Pi ((owned 1 (OwnedCap HeaderLease1 HeaderRegion1 Header))"
    , "       (step 1 (Pi ((old-next 1 Addr)) Addr)))"
    , "      (Eff HeaderRegion1 HeaderRegion1 (OwnedCap HeaderLease1 HeaderRegion1 Header))))"
    , "(def rewrite-owned-header-next-cap"
    , "  (fn ((owned 1 (OwnedCap HeaderLease1 HeaderRegion1 Header))"
    , "       (step 1 (Pi ((old-next 1 Addr)) Addr)))"
    , "    (bind HeaderRegion1 HeaderRegion1 HeaderRegion1 (ObservedCap HeaderLease1 HeaderRegion1 Header Addr) (OwnedCap HeaderLease1 HeaderRegion1 Header)"
    , "      (read-owned-header-next-cap owned)"
    , "      (fn ((observed 1 (ObservedCap HeaderLease1 HeaderRegion1 Header Addr)))"
    , "        (with-observed-cap HeaderLease1 HeaderRegion1 Header Addr (Eff HeaderRegion1 HeaderRegion1 (OwnedCap HeaderLease1 HeaderRegion1 Header)) observed"
    , "          (fn ((lease 1 HeaderLease1) (hdr (Ptr Header)) (old-next 1 Addr))"
    , "            (bind HeaderRegion1 HeaderRegion1 HeaderRegion1 Unit (OwnedCap HeaderLease1 HeaderRegion1 Header)"
    , "              (store-field HeaderRegion1 HeaderRegion1 Header next hdr (step old-next))"
    , "              (fn ((done 1 Unit))"
    , "                (let ((ignored 0 done))"
    , "                  (pure HeaderRegion1 (OwnedCap HeaderLease1 HeaderRegion1 Header) (own-cap HeaderLease1 HeaderRegion1 Header lease hdr)))))))))))"
    , "(claim advance-owned-header-next-handle (Pi ((owned 1 (OwnedPtr HeaderLease1 Header))) (Eff HeaderRegion1 HeaderRegion1 (OwnedPtr HeaderLease1 Header))))"
    , "(def advance-owned-header-next-handle"
    , "  (fn ((owned 1 (OwnedPtr HeaderLease1 Header)))"
    , "    (rewrite-owned-header-next-handle owned advance-header-next-value)))"
    ]

layoutLiteralSource :: String
layoutLiteralSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(extern header-magic (Pi ((hdr Header)) U64) header_magic)"
    , "(claim header-template Header)"
    , "(def header-template"
    , "  (layout Header"
    , "    ((magic (u64 77))"
    , "     (next (addr 4096)))))"
    , "(claim header-template-positional Header)"
    , "(def header-template-positional"
    , "  (layout-values Header"
    , "    (u64 77)"
    , "    (addr 4096)))"
    , "(claim header-template-positional-next Addr)"
    , "(def header-template-positional-next"
    , "  (field Header next header-template-positional))"
    , "(claim header-template-magic U64)"
    , "(def header-template-magic (header-magic header-template))"
    , "(claim header-template-next Addr)"
    , "(def header-template-next (field Header next header-template))"
    , "(claim header-magic-from-arg (Pi ((hdr Header)) U64))"
    , "(def header-magic-from-arg"
    , "  (fn ((hdr Header))"
    , "    (field Header magic hdr)))"
    , "(claim retarget-header (Pi ((hdr Header) (next-addr Addr)) Header))"
    , "(def retarget-header"
    , "  (fn ((hdr Header) (next-addr Addr))"
    , "    (with-field Header next hdr next-addr)))"
    , "(claim retarget-template Header)"
    , "(def retarget-template"
    , "  (with-field Header next header-template (addr 8192)))"
    , "(claim retarget-template-next Addr)"
    , "(def retarget-template-next"
    , "  (field Header next retarget-template))"
    , "(claim retargeted-magic-from-arg (Pi ((hdr Header) (next-addr Addr)) U64))"
    , "(def retargeted-magic-from-arg"
    , "  (fn ((hdr Header) (next-addr Addr))"
    , "    (field Header magic (with-field Header next hdr next-addr))))"
    , "(claim repack-header (Pi ((hdr Header) (magic U64) (next-addr Addr)) Header))"
    , "(def repack-header"
    , "  (fn ((hdr Header) (magic U64) (next-addr Addr))"
    , "    (with-fields Header hdr"
    , "      ((magic magic)"
    , "       (next next-addr)))))"
    , "(claim repacked-template Header)"
    , "(def repacked-template"
    , "  (with-fields Header header-template"
    , "    ((magic (u64 99))"
    , "     (next (addr 12288)))))"
    , "(claim repacked-template-magic U64)"
    , "(def repacked-template-magic"
    , "  (field Header magic repacked-template))"
    , "(claim repacked-template-next Addr)"
    , "(def repacked-template-next"
    , "  (field Header next repacked-template))"
    , "(claim override-template-next Addr)"
    , "(def override-template-next"
    , "  (field Header next"
    , "    (with-fields Header header-template"
    , "      ((next (addr 8192))"
    , "       (next (addr 12288))))))"
    , "(claim let-layout-next Addr)"
    , "(def let-layout-next"
    , "  (let-layout Header ((next next)) header-template next))"
    , "(claim let-layout-magic-from-arg (Pi ((hdr Header)) U64))"
    , "(def let-layout-magic-from-arg"
    , "  (fn ((hdr Header))"
    , "    (let-layout Header ((magic magic) (next 0 ignored)) hdr magic)))"
    ]

layoutLiteralMissingFieldSource :: String
layoutLiteralMissingFieldSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(claim broken Header)"
    , "(def broken"
    , "  (layout Header"
    , "    ((magic (u64 77)))))"
    ]

layoutLiteralUnknownFieldSource :: String
layoutLiteralUnknownFieldSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(claim broken Header)"
    , "(def broken"
    , "  (layout Header"
    , "    ((magic (u64 77))"
    , "     (bogus (addr 4096))"
    , "     (next (addr 0)))))"
    ]

layoutValuesAritySource :: String
layoutValuesAritySource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(claim broken Header)"
    , "(def broken"
    , "  (layout-values Header"
    , "    (u64 77)))"
    ]

layoutValuesWrongTypeSource :: String
layoutValuesWrongTypeSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(claim broken Header)"
    , "(def broken"
    , "  (layout-values Header"
    , "    (u64 77)"
    , "    (u64 88)))"
    ]

layoutUpdateWrongTypeSource :: String
layoutUpdateWrongTypeSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(claim broken Header)"
    , "(def broken"
    , "  (with-field Header next"
    , "    (layout Header ((magic (u64 77)) (next (addr 4096))))"
    , "    (u64 9)))"
    ]

layoutLetUnknownFieldSource :: String
layoutLetUnknownFieldSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(claim broken Addr)"
    , "(def broken"
    , "  (let-layout Header ((bogus value))"
    , "    (layout Header ((magic (u64 77)) (next (addr 4096))))"
    , "    value))"
    ]

layoutWithFieldsUnknownFieldSource :: String
layoutWithFieldsUnknownFieldSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(claim broken Header)"
    , "(def broken"
    , "  (with-fields Header"
    , "    (layout Header ((magic (u64 77)) (next (addr 4096))))"
    , "    ((bogus (addr 9))"
    , "     (next (addr 0)))))"
    ]

layoutStoreFieldsUnknownFieldSource :: String
layoutStoreFieldsUnknownFieldSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(claim broken (Pi ((hdr (Ptr Header))) (Eff Heap Unit)))"
    , "(def broken"
    , "  (fn ((hdr (Ptr Header)))"
    , "    (store-fields Header hdr"
    , "      ((bogus (addr 9))"
    , "       (next (addr 0))))))"
    ]

layoutLoadUnknownFieldSource :: String
layoutLoadUnknownFieldSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(claim broken (Pi ((hdr (Ptr Header))) (Eff Heap Addr)))"
    , "(def broken"
    , "  (fn ((hdr (Ptr Header)))"
    , "    (let-load-layout Header ((bogus value)) hdr"
    , "      (pure Heap Addr value))))"
    ]

layoutStoreFieldsCapabilityMismatchSource :: String
layoutStoreFieldsCapabilityMismatchSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(data HeaderClean ())"
    , "(data HeaderDirty ())"
    , "(claim broken (Pi ((hdr (Ptr Header)) (magic U64) (next-addr Addr)) (Eff HeaderClean Unit)))"
    , "(def broken"
    , "  (fn ((hdr (Ptr Header)) (magic U64) (next-addr Addr))"
    , "    (store-fields HeaderDirty Header hdr"
    , "      ((magic magic)"
    , "       (next next-addr)))))"
    ]

layoutLoadCapabilityMismatchSource :: String
layoutLoadCapabilityMismatchSource =
  unlines
    [ "(layout Header 16 8 ((magic U64 0) (next Addr 8)))"
    , "(data HeaderClean ())"
    , "(data HeaderDirty ())"
    , "(claim broken (Pi ((hdr (Ptr Header))) (Eff HeaderClean Addr)))"
    , "(def broken"
    , "  (fn ((hdr (Ptr Header)))"
    , "    (let-load-layout HeaderDirty Header ((magic 0 ignored) (next next)) hdr"
    , "      (pure HeaderDirty Addr next))))"
    ]

badLayoutAlignmentSource :: String
badLayoutAlignmentSource =
  "(layout Bad 16 3)"

badLayoutSizeAlignmentSource :: String
badLayoutSizeAlignmentSource =
  "(layout Bad 12 8)"

badLayoutOverlapSource :: String
badLayoutOverlapSource =
  "(layout Bad 16 8 ((first U64 0) (second U64 4)))"

badLayoutWeakAlignmentSource :: String
badLayoutWeakAlignmentSource =
  "(layout Bad 16 1 ((word U64 0)))"

optionSource :: String
optionSource =
  unlines
    [ "(data Option ((A 0 Type))"
    , "  (None)"
    , "  (Some A))"
    , "(claim unwrap-or (Pi ((A 0 Type) (fallback A) (opt (Option A))) A))"
    , "(def unwrap-or"
    , "  (fn ((A 0 Type) (fallback A) (opt (Option A)))"
    , "    (match opt"
    , "      ((None) fallback)"
    , "      ((Some value) value))))"
    , "(claim picked Nat)"
    , "(def picked (unwrap-or Nat (S Z) (Some Nat Z)))"
    ]

recursiveDataSource :: String
recursiveDataSource =
  unlines
    [ "(data List ((A 0 Type))"
    , "  (Nil)"
    , "  (Cons A (List A)))"
    , "(claim head-or (Pi ((A 0 Type) (fallback A) (xs (List A))) A))"
    , "(def head-or"
    , "  (fn ((A 0 Type) (fallback A) (xs (List A)))"
    , "    (match xs"
    , "      ((Nil) fallback)"
    , "      ((Cons head tail) head))))"
    , "(claim picked-head Nat)"
    , "(def picked-head (head-or Nat (S Z) (Cons Nat Z (Nil Nat))))"
    ]

normalizationSource :: String
normalizationSource =
  unlines
    [ "(claim add (Pi ((a Nat) (b Nat)) Nat))"
    , "(def add"
    , "  (fn ((a Nat) (b Nat))"
    , "    (nat-elim Nat"
    , "      b"
    , "      (fn ((k Nat) (rec Nat)) (S rec))"
    , "      a)))"
    , "(claim two Nat)"
    , "(def two (S (S Z)))"
    , "(claim three Nat)"
    , "(def three (add two (S Z)))"
    ]

codegenFunctionSource :: String
codegenFunctionSource =
  unlines
    [ "(claim add (Pi ((a Nat) (b Nat)) Nat))"
    , "(def add"
    , "  (fn ((a Nat) (b Nat))"
    , "    (nat-elim Nat"
    , "      b"
    , "      (fn ((k Nat) (rec Nat)) (S rec))"
    , "      a)))"
    , "(claim erase-first (Pi ((proof 0 Nat) (x 1 Nat)) Nat))"
    , "(def erase-first (fn ((proof 0 Nat) (x 1 Nat)) x))"
    ]
