/*
 * This file contains the example code for the second part of the
 * "Advanced Linking" section. It's only compatible with the FE8 family of ROMs,
 * since it makes use of Event Slots. It exposes some_asmc, which is intended
 * for being called by an ASMC event.
 * 
 * This code has the same effect as the code in "adv_funcptr.c"
 * 
 * Example:
 *   ASMC some_asmc   // call asmc
 *   SADD 0x0C3       // r3 = sC + s0
 *   GIVEITEMTOMAIN 0 // give mone
 */

#include "gbafe.h"

void some_asmc() {
	eventSlot[0xC] = GetGameTime();
}
