; #######################################################################################################################################

; apLib decruncher for the NES (yes, not kidding)
; /Mic, 2010
;
; Assembles with NESASM
;
; Example (decrunching packed_data into RAM at $0200):
;
;	lda		#(packed_data % 256)
;	sta		<APLIB_SRC
;	lda		#(packed_data / 256)
;	sta		<APLIB_SRC+1
;	lda		#$00
;	sta		<APLIB_DEST
;	lda		#$02
;	sta		<APLIB_DEST+1
;	jsr		aplib_decrunch
;

; #######################################################################################################################################

; Zeropage variables
APLIB_LWM 		= $10
APLIB_BITS 		= $12
APLIB_BITCOUNT 	= $13
APLIB_OFFS 		= $14
APLIB_OFFS2 	= $16
APLIB_GAMMA 	= $18
APLIB_SRC 		= $1A
APLIB_DEST 		= $1C
APLIB_SRC2 		= $1E


; #######################################################################################################################################

; Increase a 16-bit zeropage variable
apl_inc16_zp .macro
	inc		<\1
	bne		.x\@
	inc		<\1+1
 .x\@:
 .endm

; Decrease a 16-bit zeropage variable
apl_dec16_zp .macro
	lda		<\1
	bne		.x\@
	dec		<\1+1
 .x\@:
 	dec		<\1
 .endm
 

; Add an 8-bit zeropage variable to a 16-bit zeropage variable
apl_add16_8_zp .macro
	lda 	<\1
	clc
 	adc 	<\2
 	sta 	<\1
 	rol		<\1+1
 .endm 


; Subtract one zeropage variable from another
apl_sub16_zp .macro
	lda 	<\1
 	sec
 	sbc 	<\2
 	sta 	<\1
 	lda 	<\1+1
 	sbc 	<\2+1
 	sta 	<\1+1
 .endm


apl_mov16_zp .macro
	lda 	<\2
	sta 	<\1
	lda 	<\2+1
	sta 	<\1+1
 .endm
 
; #######################################################################################################################################
 
	
; In:
; APLIB_SRC = source address
; APLIB_DEST = dest address
aplib_decrunch:
	; Skip the 24-byte header added by appack
	lda 	<APLIB_SRC
	clc
 	adc 	#24
 	sta 	<APLIB_SRC
 	lda 	<APLIB_SRC+1
 	adc 	#0
 	sta 	<APLIB_SRC+1
 	
	lda 	#0
	sta 	<APLIB_OFFS+1
	sta		<APLIB_LWM+1
	lda		#1
	sta		<APLIB_BITCOUNT
	ldy		#0
_ad_copy_byte:
	lda		[APLIB_SRC],y
	sta		[APLIB_DEST],y
	apl_inc16_zp APLIB_SRC
	apl_inc16_zp APLIB_DEST
_ad_next_sequence_init:
	lda		#0
	sta		<APLIB_LWM
_ad_next_sequence:
	jsr		_ad_get_bit
	bcc		_ad_copy_byte		; if bit sequence is %0..., then copy next byte
	jsr		_ad_get_bit
	bcc 	_ad_code_pair		; if bit sequence is %10..., then is a code pair
	jsr		_ad_get_bit
	lda		#0
	sta		<APLIB_OFFS
	sta		<APLIB_OFFS+1
	bcs		_ad_skip_jmp
	jmp		_ad_short_match		; if bit sequence is %110..., then is a short match
_ad_skip_jmp:
	; The sequence is %111..., the next 4 bits are the offset (0-15)
	jsr		_ad_get_bit
	rol		<APLIB_OFFS
	jsr		_ad_get_bit
	rol		<APLIB_OFFS
	jsr		_ad_get_bit
	rol		<APLIB_OFFS
	jsr		_ad_get_bit
	rol		<APLIB_OFFS
	lda		<APLIB_OFFS
	beq		_ad_write_byte		; if offset == 0, then write 0x00
	
	; If offset != 0, then write the byte at destination - offset
	apl_mov16_zp APLIB_SRC2,APLIB_DEST
	apl_sub16_zp APLIB_SRC2,APLIB_OFFS
	lda		[APLIB_SRC2],y
_ad_write_byte:
	sta		[APLIB_DEST],y
	apl_inc16_zp APLIB_DEST
	jmp		_ad_next_sequence_init

	; Code pair %10...
_ad_code_pair:
	jsr		_ad_decode_gamma
	apl_dec16_zp APLIB_GAMMA
	apl_dec16_zp APLIB_GAMMA
	lda		<APLIB_GAMMA
	ora		<APLIB_GAMMA+1
	bne		_ad_normal_code_pair
	lda		APLIB_LWM
	bne		_ad_normal_code_pair
	jsr		_ad_decode_gamma
	apl_mov16_zp APLIB_OFFS,APLIB_OFFS2
	jmp		_ad_copy_code_pair
_ad_normal_code_pair:
	apl_add16_8_zp APLIB_GAMMA,APLIB_LWM
	apl_dec16_zp APLIB_GAMMA
	lda		<APLIB_GAMMA
	sta		<APLIB_OFFS+1
	lda		[APLIB_SRC],y
	sta		<APLIB_OFFS
	apl_inc16_zp APLIB_SRC
	jsr		_ad_decode_gamma
	lda		<APLIB_OFFS+1
	cmp		#$7D					; OFFS >= 32000 ?
	bcc		_ad_compare_1280
	apl_inc16_zp APLIB_GAMMA
_ad_compare_1280:
	cmp		#$05					; OFFS >= 1280 ?
	bcc		_ad_compare_128
	apl_inc16_zp APLIB_GAMMA
	jmp		_ad_continue_short_match
_ad_compare_128:
	cmp		#1
	bcs		_ad_continue_short_match
	lda		<APLIB_OFFS
	cmp		#128					; OFFS < 128 ?
	bcs		_ad_continue_short_match
	apl_inc16_zp APLIB_GAMMA
	apl_inc16_zp APLIB_GAMMA
	jmp		_ad_continue_short_match
	
; get_bit: Get bits from the crunched data and insert the most significant bit in the carry flag.
_ad_get_bit:
	dec		<APLIB_BITCOUNT
	bne		_ad_still_bits_left
	lda		#8
	sta		<APLIB_BITCOUNT
	lda		[APLIB_SRC],y
	sta		<APLIB_BITS
	apl_inc16_zp APLIB_SRC
_ad_still_bits_left:
	asl		<APLIB_BITS
	rts

; decode_gamma: Decode values from the crunched data using gamma code
_ad_decode_gamma:
	lda		#1
	sta		<APLIB_GAMMA
	lda		#0
	sta		<APLIB_GAMMA+1
_ad_get_more_gamma:
	jsr		_ad_get_bit
	rol		<APLIB_GAMMA
	rol		<APLIB_GAMMA+1
	jsr		_ad_get_bit
	bcs		_ad_get_more_gamma
	rts

; Short match %110...
_ad_short_match:  
	lda		#1
	sta		<APLIB_GAMMA
	lda		#0
	sta		<APLIB_GAMMA+1
	lda		[APLIB_SRC],y	; Get offset (offset is 7 bits + 1 bit to mark if copy 2 or 3 bytes) 
	apl_inc16_zp APLIB_SRC
	lsr		a
	beq		_ad_end_decrunch
	rol		<APLIB_GAMMA
	sta		<APLIB_OFFS
	lda		#0
	sta		<APLIB_OFFS+1
_ad_continue_short_match:
	apl_mov16_zp APLIB_OFFS2,APLIB_OFFS
_ad_copy_code_pair:
	apl_mov16_zp APLIB_SRC2,APLIB_DEST
	apl_sub16_zp APLIB_SRC2,APLIB_OFFS
_ad_loop_do_copy:
	lda		[APLIB_SRC2],y
	sta		[APLIB_DEST],y
	apl_inc16_zp APLIB_SRC2
	apl_inc16_zp APLIB_DEST
	apl_dec16_zp APLIB_GAMMA
	lda		<APLIB_GAMMA
	ora		<APLIB_GAMMA+1
	bne		_ad_loop_do_copy	
	lda		#1
	sta		<APLIB_LWM
	jmp		_ad_next_sequence
	
_ad_end_decrunch:
	rts