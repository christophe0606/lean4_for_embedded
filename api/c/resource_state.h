#pragma once
#include <stdint.h>
#include <stddef.h>

/* Callers serialize each registry operation; hardware calls happen outside it.
 * Tickets and operation IDs never wrap. Exhaustion fails closed. */
uint32_t board_resource_claim(uint32_t kind, size_t key, uint32_t subkey);
uint32_t board_resource_claim_range(uint32_t kind, size_t key, size_t extent);
uint32_t board_resource_find(uint32_t kind, size_t key, uint32_t subkey);
uint32_t board_resource_epoch(uint32_t ticket);
uint32_t board_resource_begin(uint32_t ticket, uint32_t epoch, uint32_t write);
/* Exclusive outcomes: 0 poison, 1 advance epoch, 2 retire, 3 preserve epoch.
 * Shared completion only releases its unique operation token. */
uint32_t board_resource_end(uint32_t operation, uint32_t outcome);
