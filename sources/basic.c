/*
 * This file contains the example code from the first section of the tutorial
 * It's hardcoded for FE8U, and exposes test_asmc, which is intended for being
 * called by an ASMC event.
 * 
 * Example (from the tutorial):
 *   SVAL 1 1
 *   SVAL 2 2
 *   SVAL 3 3
 *   SVAL 4 4
 *   ASMC test_asmc   // call asmc
 *   SADD 0x0C3       // r3 = sC + s0
 *   GIVEITEMTOMAIN 0 // give mone
 */

static int* const eventSlot = (int* const) (0x030004B8);

int range_sum(const int* begin, const int* end) {
	int result = 0;
	
	while (begin != end)
		result = result + *begin++;
	
	return result;
}

void test_asmc() {
	eventSlot[0xC] = range_sum(&eventSlot[1], &eventSlot[5]);
}
