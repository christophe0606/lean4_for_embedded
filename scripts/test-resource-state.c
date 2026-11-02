/* Tests the actual target registry implementation without MCU/Lean dependencies. */
#include "resource_state.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    uint32_t ticket = board_resource_claim(1, 100, 2);
    assert(ticket && !board_resource_claim(1, 100, 2));
    assert(board_resource_find(1, 100, 2) == ticket);
    uint32_t first = board_resource_begin(ticket, 1, 0);
    uint32_t second = board_resource_begin(ticket, 1, 0);
    assert(first && second && first != second);
    assert(!board_resource_begin(ticket, 1, 1)); /* no delete/transition while pinned */
    assert(board_resource_end(first, 1) == 1);
    assert(!board_resource_end(first, 1)); /* copied retention cannot release another user */
    assert(!board_resource_begin(ticket, 1, 1));
    assert(board_resource_end(second, 1) == 1);
    uint32_t write = board_resource_begin(ticket, 1, 1);
    assert(write && !board_resource_begin(ticket, 1, 0));
    assert(!board_resource_begin(ticket, 1, 1)); /* shared driver operation mutex */
    assert(board_resource_end(write, 1) == 2);
    assert(!board_resource_begin(ticket, 1, 1)); /* old typed handle is stale */
    write = board_resource_begin(ticket, 2, 1);
    assert(board_resource_end(write, 3) == 2); /* same-state operation keeps owner usable */
    write = board_resource_begin(ticket, 2, 1);
    assert(board_resource_end(write, 2)); /* delete */
    assert(!board_resource_begin(ticket, 2, 0));
    uint32_t replacement = board_resource_claim(1, 100, 2);
    assert(replacement && replacement != ticket); /* address reuse does not revive old owner */
    assert(!board_resource_begin(ticket, 2, 0));
    write = board_resource_begin(replacement, 1, 1);
    assert(!board_resource_end(write, 0)); /* failed mutation poisons */
    assert(!board_resource_epoch(replacement));
    assert(!board_resource_find(1, 100, 2));
    assert(!board_resource_claim(1, 100, 2)); /* fail closed until reset */

    ticket = board_resource_claim(3, 200, 0);
    uint32_t operations[64];
    for (unsigned i = 0; i < 64; ++i) {
        operations[i] = board_resource_begin(ticket, 1, 0);
        assert(operations[i]);
    }
    assert(!board_resource_begin(ticket, 1, 0)); /* bounded registry exhaustion */
    for (unsigned i = 0; i < 64; ++i) assert(board_resource_end(operations[i], 1));
    assert(!board_resource_end(operations[0], 1));
    write = board_resource_begin(ticket, 1, 1);
    assert(write && board_resource_end(write, 2));

    uint32_t range = board_resource_claim_range(5, 1000, 64);
    assert(range);
    assert(!board_resource_claim_range(5, 1000, 64));
    assert(!board_resource_claim_range(5, 1032, 64)); /* overlaps tail */
    assert(!board_resource_claim_range(5, 968, 64)); /* overlaps head */
    assert(!board_resource_claim_range(5, 900, 200)); /* contains old range */
    assert(!board_resource_claim_range(5, 1016, 8)); /* contained by old range */
    uint32_t adjacent = board_resource_claim_range(5, 1064, 16);
    assert(adjacent);
    assert(!board_resource_claim_range(5, 0, 16));
    assert(!board_resource_claim_range(5, 2000, 0));
    assert(!board_resource_claim_range(5, SIZE_MAX-4, 6));
    write = board_resource_begin(range, 1, 1);
    assert(board_resource_end(write, 2));
    write = board_resource_begin(adjacent, 1, 1);
    assert(board_resource_end(write, 2));
    unsigned available = 0;
    while (board_resource_claim(9, ++available, 0)) {}
    assert(available == 32); /* one poisoned key plus 31 additional slots */
    puts("PASS: registry stale handles, pinning, replay, deletion, reuse, failures and capacity");
    return 0;
}
