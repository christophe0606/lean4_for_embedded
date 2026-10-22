#pragma once
#include <atomic>
#include <chrono>
#include <functional>
#include <memory>
#include <mutex>
#include <utility>
#include "cmsis_os2.h"

namespace lean {
using std::atomic;
using std::atomic_bool;
using std::atomic_ushort;
using std::atomic_uint;
using std::atomic_uchar;
using std::lock_guard;
using std::unique_lock;
using std::atomic_load;
using std::atomic_load_explicit;
using std::atomic_fetch_add_explicit;
using std::atomic_fetch_sub_explicit;
using std::memory_order_relaxed;
using std::memory_order_release;
using std::memory_order_acquire;
using std::memory_order_acq_rel;
using std::memory_order_seq_cst;
using std::atomic_thread_fence;

[[noreturn]] void cmsis_fail(const char * message);
inline void cmsis_check(osStatus_t status, const char * message) {
    if (status != osOK) cmsis_fail(message);
}
class mutex {
    osMutexId_t m_id;
protected:
    explicit mutex(uint32_t attributes);
public:
    mutex() : mutex(osMutexPrioInherit) {}
    ~mutex();
    mutex(const mutex &) = delete;
    mutex & operator=(const mutex &) = delete;
    void lock();
    bool try_lock();
    void unlock();
};
class recursive_mutex : public mutex {
public:
    recursive_mutex() : mutex(osMutexPrioInherit | osMutexRecursive) {}
};
class condition_variable {
    struct waiter {
        osSemaphoreId_t semaphore;
        waiter * next;
        bool queued;
    };
    mutex m_mutex;
    waiter * m_head = nullptr;
    waiter ** m_tail = &m_head;
    void wait_ticks(unique_lock<mutex> & lock, uint32_t ticks);
public:
    ~condition_variable();
    void wait(unique_lock<mutex> & lock) { wait_ticks(lock, osWaitForever); }
    template<typename P> void wait(unique_lock<mutex> & lock, P predicate) {
        while (!predicate()) wait(lock);
    }
    void notify_one();
    void notify_all();
};
class shared_mutex {
    mutex m_state;
    condition_variable m_changed;
    unsigned m_readers = 0;
    unsigned m_waiting_writers = 0;
    bool m_writer = false;
public:
    void lock();
    bool try_lock();
    void unlock();
    void lock_shared();
    bool try_lock_shared();
    void unlock_shared();
};
namespace this_thread {
inline osThreadId_t get_id() { return osThreadGetId(); }
inline void yield() { cmsis_check(osThreadYield(), "osThreadYield"); }
void sleep_for(std::chrono::milliseconds delay);
void sleep_for(std::chrono::seconds delay);
}
inline unsigned hardware_concurrency() { return 1; }
class thread { public: using id = osThreadId_t; };
class lthread {
    static size_t m_thread_stack_size;
    struct imp;
    std::unique_ptr<imp> m_imp;
public:
    lthread(std::function<void(void)> const & fn);
    ~lthread();
    void join();
    static void set_thread_stack_size(size_t size);
    static size_t get_thread_stack_size();
};
}

namespace lean {
struct cmsis_clock {
    using duration = std::chrono::nanoseconds;
    using rep = duration::rep;
    using period = duration::period;
    using time_point = std::chrono::time_point<cmsis_clock>;
    static constexpr bool is_steady = true;
    static time_point now();
};
}
