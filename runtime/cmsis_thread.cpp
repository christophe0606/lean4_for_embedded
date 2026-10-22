#include "cmsis_thread.h"
#include <cstdio>
#include <cstdlib>
#include <limits>

namespace lean {
[[noreturn]] void cmsis_fail(const char * message) {
    fprintf(stderr, "CMSIS runtime failure: %s\n", message);
    fflush(stderr);
    abort();
}
mutex::mutex(uint32_t flags) {
    osMutexAttr_t attr{};
    attr.attr_bits = flags;
    m_id = osMutexNew(&attr);
    if (!m_id) cmsis_fail("osMutexNew (RTX object memory exhausted)");
}
mutex::~mutex() { cmsis_check(osMutexDelete(m_id), "osMutexDelete"); }
void mutex::lock() { cmsis_check(osMutexAcquire(m_id, osWaitForever), "osMutexAcquire"); }
bool mutex::try_lock() {
    osStatus_t status = osMutexAcquire(m_id, 0);
    if (status == osErrorResource) return false;
    cmsis_check(status, "osMutexAcquire(try)");
    return true;
}
void mutex::unlock() { cmsis_check(osMutexRelease(m_id), "osMutexRelease"); }

condition_variable::~condition_variable() {
    if (m_head) cmsis_fail("destroyed a condition variable with waiters");
}
void condition_variable::wait_ticks(unique_lock<mutex> & lock, uint32_t ticks) {
    waiter node{osSemaphoreNew(1, 0, nullptr), nullptr, true};
    if (!node.semaphore) cmsis_fail("condition waiter allocation");
    {
        lock_guard<mutex> guard(m_mutex);
        *m_tail = &node;
        m_tail = &node.next;
        // Enrollment precedes unlock: notification cannot be lost in between.
        lock.unlock();
    }
    osStatus_t status = osSemaphoreAcquire(node.semaphore, ticks);
    {
        lock_guard<mutex> guard(m_mutex);
        if (node.queued) {
            waiter ** link = &m_head;
            while (*link != &node) link = &(*link)->next;
            *link = node.next;
            if (!node.next) m_tail = link;
        }
    }
    cmsis_check(osSemaphoreDelete(node.semaphore), "condition waiter deletion");
    lock.lock();
    if (status != osOK && status != osErrorTimeout) cmsis_fail("condition wait");
}
void condition_variable::notify_one() {
    lock_guard<mutex> guard(m_mutex);
    if (!m_head) return;
    waiter * node = m_head;
    m_head = node->next;
    if (!m_head) m_tail = &m_head;
    node->queued = false;
    cmsis_check(osSemaphoreRelease(node->semaphore), "condition notification");
}
void condition_variable::notify_all() {
    lock_guard<mutex> guard(m_mutex);
    while (m_head) {
        waiter * node = m_head;
        m_head = node->next;
        node->queued = false;
        cmsis_check(osSemaphoreRelease(node->semaphore), "condition broadcast");
    }
    m_tail = &m_head;
}
void shared_mutex::lock() {
    unique_lock<mutex> lock(m_state);
    ++m_waiting_writers;
    m_changed.wait(lock, [&] { return !m_writer && !m_readers; });
    --m_waiting_writers;
    m_writer = true;
}
bool shared_mutex::try_lock() {
    lock_guard<mutex> guard(m_state);
    if (m_writer || m_readers) return false;
    return m_writer = true;
}
void shared_mutex::unlock() {
    lock_guard<mutex> guard(m_state);
    if (!m_writer) cmsis_fail("shared_mutex write unlock without writer");
    m_writer = false;
    m_changed.notify_all();
}
void shared_mutex::lock_shared() {
    unique_lock<mutex> lock(m_state);
    m_changed.wait(lock, [&] { return !m_writer && !m_waiting_writers; });
    ++m_readers;
}
bool shared_mutex::try_lock_shared() {
    lock_guard<mutex> guard(m_state);
    if (m_writer || m_waiting_writers) return false;
    ++m_readers;
    return true;
}
void shared_mutex::unlock_shared() {
    lock_guard<mutex> guard(m_state);
    if (!m_readers) cmsis_fail("shared_mutex read unlock without reader");
    if (!--m_readers) m_changed.notify_all();
}
void this_thread::sleep_for(std::chrono::milliseconds delay) {
    if (delay.count() <= 0) { yield(); return; }
    uint64_t ticks = (uint64_t(delay.count()) * osKernelGetTickFreq() + 999) / 1000;
    if (ticks >= osWaitForever) cmsis_fail("sleep duration exceeds RTX tick range");
    cmsis_check(osDelay(uint32_t(ticks)), "osDelay");
}
}

#include "SSE300MPS3.h"
namespace lean {
cmsis_clock::time_point cmsis_clock::now() {
    static uint32_t previous;
    static uint64_t extended;
    const uint32_t primask = __get_PRIMASK();
    __disable_irq();
    uint32_t current = osKernelGetTickCount();
    extended += uint32_t(current - previous);
    previous = current;
    uint64_t ticks = extended;
    __set_PRIMASK(primask);
    uint64_t frequency = osKernelGetTickFreq();
    uint64_t ns = (ticks / frequency) * 1000000000ULL +
                  (ticks % frequency) * 1000000000ULL / frequency;
    return time_point(duration(ns));
}
}

namespace lean {
void this_thread::sleep_for(std::chrono::seconds delay) {
    if (delay.count() <= 0) { yield(); return; }
    const int64_t chunk = (uint64_t(osWaitForever) - 1) / osKernelGetTickFreq();
    int64_t seconds = delay.count();
    while (seconds > chunk) {
        cmsis_check(osDelay(uint32_t(chunk * osKernelGetTickFreq())), "osDelay(long)");
        seconds -= chunk;
    }
    sleep_for(std::chrono::milliseconds(seconds * 1000));
}
}
