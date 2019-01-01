/*
 * This file contains the example code from the first section of the tutorial
 * It's hardcoded for FE8U, and exposes asmc_sum_slots, which is intended for being
 * called by an ASMC event instruction.
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

/*!
 * Sums an arbitrary range of ints stored contiguously in memory.
 *
 * @param begin pointer to the first element of the range
 * @param end pointer to past the last element of the range
 * @return the sum of all int values in the given range
 */
int sum_range(const int* begin, const int* end) {
    int result = 0;

    while (begin != end)
        result = result + *begin++;

    return result;
}

static int* const sEventSlot = (int* const) (0x030004B8);

/*!
 * Sums event slots 1 through 4 and stores the result in slot C.
 */
void asmc_sum_slots(void) {
    sEventSlot[0xC] = sum_range(
        &sEventSlot[1],
        &sEventSlot[5]
    );
}
