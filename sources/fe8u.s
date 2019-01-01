.macro SET_FUNC name, value
	.global \name
	.type   \name, %function
	.set    \name, \value
.endm

.macro SET_DATA name, value
	.global \name
	.type   \name, %object
	.set    \name, \value
.endm

SET_DATA gEventSlot,  (0x030004B8)

SET_FUNC GetGameTime, (0x08000D28+1)
