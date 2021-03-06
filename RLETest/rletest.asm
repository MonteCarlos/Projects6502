;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; RLE Test - experiments with RLE frame encoding
;
; 2016-01 Scott Lawrence
;
;  Created for the RetroChallenge RC2016-1
; Scott Lawrence - yorgle@gmail.com
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Version history

.define VERSIONH #$00
.define VERSIONL #$01

; v 00 01 - 2016-01-01 - initial version


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; define the functionality we want to use in the library
UseVideoDisplay0 = 1 ; video display 0


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; include our support defines and libraries

.include "KimDefs.asm"
.include "KimCode200.asm"
.include "KimLib.asm"


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; RLE format:
; 	0xnM	repeat color M for N bytes
;	0x00	End of image
;	0x0F	End of row (skip to next start)
;	0x01	(skip 0x01 pixels)
;	0x0E	(skip 0x0e pixels)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; main 
;  - the library entry point.
main:
	lda	COLOR_DKGRAY		
	jsr	fillscr			; fill the screen to start fresh

	jsr	rleRenderStripes	; draw the color bars
	jsr 	rleRenderRedGhost	; draw the red ghost
	jsr 	rleRenderMouse		; draw the brown mouse

	rts


; RAM usage (put these wherever in zero page)
SCREEN    = $20		; pointer to the screen, will be modified
SCREENBAK = $22		; pointer to the start of each new line
IMAGE     = $24		; pointer to the RLE image we're displaying
COLOR     = $26		; current color being spit onto the screen
REPS      = $27		; number of repetitions left of this color

rleRenderStripes:
	; setup IMAGE to point to image to be drawn
	lda	#<stripesRLE
	sta	IMAGE
	lda	#>stripesRLE
	sta	IMAGE+1
	ldy	#$00		; start it at this Y position 00..1f
	ldx	#$00		; start at this X position
	jsr	rleAdjustXY
	rts

rleRenderRedGhost:
	; setup IMAGE to point to image to be drawn
	lda	#<redGhostRLE
	sta	IMAGE
	lda	#>redGhostRLE
	sta	IMAGE+1
	ldy	#$0A		; start it at this Y position 00..1f
	ldx	#$01		; start at this X position
	jsr	rleAdjustXY
	rts

rleRenderMouse:
	; setup IMAGE to point to image to be drawn
	lda	#<mouseRLE
	sta	IMAGE
	lda	#>mouseRLE
	sta	IMAGE+1
	ldy	#$08		; start it at this Y position 00..1f
	ldx	#$11		; start at this X position
	jsr	rleAdjustXY
	rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

rleAdjustXY:
	; Adjust the start position for the X,Y position passed in
	; setup "SCREEN" to point to raster data ram
	lda	#<RASTER
	sta	SCREEN
	lda	#>RASTER
	sta	SCREEN+1	; "SCREEN" points to base of RASTER ram

	; adjust for Y position
	tya
	lsr
	lsr
	lsr
	clc
	adc	SCREEN+1
	sta	SCREEN+1	; bank offset
	sta	SCREENBAK+1 	; set it aside for 0F 

	tya
	asl
	asl
	asl
	asl
	asl
	clc
	adc	SCREEN
	sta	SCREEN		; row offset

	; adjust for X position
	clc
	txa
	adc	SCREEN	
	sta	SCREEN
	sta	SCREENBAK 	; set it aside for 0F 

	; Initialize our loop variables...
	lda	#0
	sta	COLOR		; color = 0
	sta	REPS		; reps = 0
	lda	#0
	tay			; clear Y


; main loop to handle image data..
rleLoop:
	; if there's no reps left, advance to the next byte
	lda	REPS
	cmp	#$00
	beq	rleNext

	; okay, we have more colors to draw
	dec	REPS		; REPS--

	; output the color to the screen buffer
	lda	COLOR
	sta	(SCREEN), y

	; increment screen position
	inc	SCREEN

	; and repeat
	jmp	rleLoop

; handle skipping over screen data
; optimization: instead of this, just add in the number of skips
rleSkip:
	; same as rleLoop. but for skip (no color putting)
	lda	REPS
	cmp	#$00		; if REPS == 0, next data byte
	beq	rleNext

	dec	REPS		; REPS--
	inc	SCREEN
	jmp	rleSkip		; and go again.


; advance to the next byte in the image data block
rleNext:
	; get the next byte, store it in color and number of reps
	ldx	#0
	lda	(IMAGE, x)	; A = current image pointer item
	sta	COLOR		; COLOR = low nibble of data
	lsr
	lsr
	lsr
	lsr
	sta	REPS		; REPS = high nibble of data

	; inc IMAGE but adjust for bank switchover too (carry)
	clc
	lda	IMAGE
	adc	#$01
	sta	IMAGE
	lda	IMAGE+1
	adc	#$00
	sta	IMAGE+1

	; check that it's not a commandable byte...
	lda	COLOR		; (COLOR contains the current data byte)
	and	#$F0
	bne	rleLoop

	; if flow gets to here, the high nibble is '0', so it's a command

	; check for command $00 - Done with the image
	lda	COLOR
	cmp	#$00
	beq	rleDone

	; check for command $0F - skip to next line
	lda	COLOR
	cmp	#$0F
	beq	rleNextLine


	; it's gotta be $01-$0E - skip that number of bytes
	lda	COLOR
	sta	REPS
	jmp	rleSkip
	

; $0F encountered. Skip to start the next line
rleNextLine:
	; add $20 to the last known backup, and use that
	clc
	lda	SCREENBAK
	adc	#$20
	sta	SCREENBAK
	sta	SCREEN

	lda	SCREENBAK+1
	adc	#0
	sta	SCREENBAK+1
	sta	SCREEN+1

	jmp 	rleNext


; $00 encountered. We're done. return.
rleDone:
	rts



; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ; 
; Image Data


; Commands: (quick reference)
; 00	    - end of image
; 01 .. 0e  - skip that many bytes
; 0F	    - end of line, advance to next line

; Colors:

;	0	1	2	3	4	5	6	7
;	Black	DkGray	LtGray	White	Red	DkRed	Brown	Orange
;
;	8	9	A	B	C	D	E	F
;	Yellow	Green	DkGreen	G Blu	Cyan	Blue	Violet	Purple

stripesRLE:
	.byte	$20, $21, $22, $23, $24, $25, $26, $27
	.byte	$28, $29, $2A, $2B, $2C, $2D, $2E, $2F, $0F

	.byte	$10, $11, $12, $13, $14, $15, $16, $17, $0F
	.byte	$18, $19, $1A, $1B, $1C, $1D, $1E, $1F, $0F
	.byte	$0F

	.byte 	$13, $01, $13, $02, $13, $03, $13, $04, $13
	.byte	     $05, $13, $06, $13, $0F
	.byte 	$13, $01, $13, $02, $13, $03, $13, $04, $13
	.byte	     $05, $13, $06, $13, $0F

	.byte	$00	; END OF IMAGE


redGhostRLE:
	.byte	$05, $44, $0F
	.byte	$03, $84, $0F
	.byte	$02, $A4, $0F
	.byte	$01, $34, $23, $44, $23, $14, $0F
	.byte	$01, $24, $43, $24, $43, $0F
	.byte	$34, $23, $2d, $24, $23, $2d, $14, $0F
	.byte	$34, $23, $2d, $24, $23, $2d, $14, $0F
	.byte	$44, $23, $44, $23, $24, $0F
	.byte	$E4, $0F
	.byte	$E4, $0F
	.byte	$E4, $0F
	.byte	$E4, $0F
	.byte	$24, $01, $34, $02, $34, $01, $24, $0F
	.byte	$14, $03, $24, $02, $24, $03, $14
	.byte	$00


mouseRLE:
	.byte	$04, $36, $01, $26, $0F
	.byte 	$03, $16, $27, $26, $01, $26, $0F
	.byte 	$03, $16, $37, $16, $01, $26, $0F
	.byte 	$04, $16, $27, $16, $01, $26, $0F
	.byte	$05, $66, $0F
	.byte	$04, $36, $20, $36, $01, $17, $0F
	.byte	$16, $03, $56, $10, $36, $17, $0F
	.byte	$01, $16, $03, $86, $0F
	.byte	$01, $16, $04, $56, $17, $0F
	.byte	$01, $16, $02, $26, $01, $26, $0F

	.byte	$01, $16, $02, $66, $17, $0F
	.byte	$01, $16, $04, $46, $27, $0F
	.byte	$02, $16, $02, $46, $37, $0F
	.byte	$03, $26, $01, $36, $27, $0F
	.byte	$08, $26, $0F
	.byte	$07, $46
	.byte 	$00
