#include "resource_state.h"
#include <limits.h>

#define RESOURCES 32
#define OPERATIONS 64
typedef struct {
    size_t key, extent;
    uint32_t kind, subkey, ticket, epoch, readers, writer, poisoned;
} resource;
typedef struct { uint32_t id, ticket, write; } operation;
static resource resources[RESOURCES];
static operation operations[OPERATIONS];
static uint32_t next_ticket, next_operation;

static resource *lookup(uint32_t ticket) {
    if (!ticket) return NULL;
    for (unsigned i = 0; i < RESOURCES; ++i)
        if (resources[i].ticket == ticket) return &resources[i];
    return NULL;
}
uint32_t board_resource_find(uint32_t kind, size_t key, uint32_t subkey) {
    for (unsigned i = 0; i < RESOURCES; ++i) {
        resource *r = &resources[i];
        if (r->ticket && !r->poisoned && r->kind == kind && r->key == key && r->subkey == subkey)
            return r->ticket;
    }
    return 0;
}
static uint32_t claim(uint32_t kind, size_t key, uint32_t subkey, size_t extent) {
    resource *empty = NULL;
    for (unsigned i = 0; i < RESOURCES; ++i) {
        resource *r = &resources[i];
        /* A failed transition reserves the key until reset. Reinitializing
         * partially configured hardware is not an implicit recovery policy. */
        if (r->ticket && r->kind == kind && r->key == key && r->subkey == subkey) return 0;
        if (extent && r->ticket && r->kind == kind && r->extent &&
            (key >= r->key ? key-r->key < r->extent : r->key-key < extent)) return 0;
        if (!r->ticket && !empty) empty = r;
    }
    if (!empty || next_ticket == UINT32_MAX) return 0;
    *empty = (resource){.kind=kind, .key=key, .extent=extent, .subkey=subkey,
                        .ticket=++next_ticket, .epoch=1};
    return empty->ticket;
}
uint32_t board_resource_claim(uint32_t kind, size_t key, uint32_t subkey) {
    return claim(kind, key, subkey, 0);
}
uint32_t board_resource_claim_range(uint32_t kind, size_t key, size_t extent) {
    if (!key || !extent || extent-1 > SIZE_MAX-key) return 0;
    return claim(kind, key, 0, extent);
}
uint32_t board_resource_epoch(uint32_t ticket) {
    resource *r = lookup(ticket);
    return r && !r->poisoned ? r->epoch : 0;
}
uint32_t board_resource_begin(uint32_t ticket, uint32_t epoch, uint32_t write) {
    resource *r = lookup(ticket);
    if (!r || r->poisoned || r->epoch != epoch || r->writer ||
        (write && r->readers) || next_operation == UINT32_MAX) return 0;
    for (unsigned i = 0; i < OPERATIONS; ++i) {
        if (operations[i].id) continue;
        operations[i] = (operation){++next_operation, ticket, write != 0};
        if (write) r->writer = 1; else ++r->readers;
        return operations[i].id;
    }
    return 0;
}
uint32_t board_resource_end(uint32_t id, uint32_t outcome) {
    for (unsigned i = 0; i < OPERATIONS; ++i) {
        operation *op = &operations[i];
        if (!id || op->id != id) continue;
        resource *r = lookup(op->ticket);
        if (!r) return 0;
        uint32_t write = op->write;
        *op = (operation){0};
        if (!write) { --r->readers; return r->epoch; }
        r->writer = 0;
        if (outcome == 2) { *r = (resource){0}; return 1; }
        if (outcome == 3) return r->epoch;
        if (!outcome || r->epoch == UINT32_MAX) { r->poisoned=1; return 0; }
        return ++r->epoch;
    }
    return 0; /* A copied/replayed operation cannot release somebody else's lease. */
}
