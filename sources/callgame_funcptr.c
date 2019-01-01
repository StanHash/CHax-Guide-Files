/*
 * This file contains the example code for the first part of the
 * "Advanced Linking" section. It's hardcoded for FE8U, and exposes some_asmc,
 * which is intended for being called by an ASMC event.
 * 
 * Example:
 *   ASMC some_asmc   // call asmc
 *   SADD 0x0C3       // r3 = sC + s0
 *   GIVEITEMTOMAIN 0 // give mone
 */

static const int(*GetGameTime)() = (int(*)()) (0x08000D29); // note the thumb bit here.

static int* const sEventSlot = (int* const) (0x030004B8);

/*!
 * Gets game time (in frames) and stores it to event slot C.
 */
void asmc_get_time(void) {
    sEventSlot[0xC] = GetGameTime();
}
