.macro SET_ABS_FUNC name, value
	.global \name
	.type   \name, %function
	.set    \name, \value
.endm

.macro SET_ABS_DATA name, value
	.global \name
	.type   \name, %object
	.set    \name, \value
.endm

SET_ABS_DATA eventSlot,   (0x030004B8)

SET_ABS_FUNC GetGameTime, (0x08000D28+1)
