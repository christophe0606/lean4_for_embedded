#include <lean/lean.h>
#include "cmsis_thread.h"
#include "runtime/thread.h"
#include "runtime/alloc.h"
#include "runtime/interrupt.h"
#include "runtime/object.h"
#include <cstdio>
#include <stdexcept>

extern "C" lean_object * lean_embedded_smoke(lean_object *);
extern "C" lean_object * lean_io_mono_ms_now();
namespace {
std::atomic<unsigned> workers{0};
osThreadId_t main_thread;
lean_object * task_body(lean_object * n, lean_object *) {
    if (osThreadGetId() == main_thread) lean::cmsis_fail("Task ran synchronously on main");
    workers.fetch_add(1);
    lean::this_thread::sleep_for(std::chrono::milliseconds(1));
    return lean_embedded_smoke(n);
}
lean_object * add_one(lean_object * n) {
    auto result = lean_nat_add(n, lean_box(1));
    lean_dec(n);
    return result;
}
lean_object * nested(lean_object * n) {
    auto closure = lean_alloc_closure((void *)task_body, 2, 1);
    lean_closure_set(closure, 0, n);
    return lean_task_spawn_core(closure, 0, false);
}
std::atomic<unsigned> static_constructions{0};
struct guarded_value {
    unsigned value;
    guarded_value() : value(42) {
        ++static_constructions;
        lean::this_thread::sleep_for(std::chrono::milliseconds(3));
    }
};
unsigned guarded() { static guarded_value value; return value.value; }
void require(bool value, const char * message) { if (!value) lean::cmsis_fail(message); }
}
extern "C" int lean_cmsis_selftest() {
    main_thread = osThreadGetId();
    lean_init_task_manager_using(2);
    lean_object * tasks[24];
    for (unsigned i = 0; i < 24; ++i) {
        auto closure = lean_alloc_closure((void *)task_body, 2, 1);
        lean_closure_set(closure, 0, lean_unsigned_to_nat(100000 + i));
        tasks[i] = lean_task_spawn_core(closure, 0, false);
    }
    for (unsigned i = 0; i < 24; ++i) {
        uint64_t n = 100000 + i;
        auto expected = lean_uint64_to_nat((n + 42) * (n + 1));
        require(lean_nat_dec_eq(lean_task_get(tasks[i]), expected), "cross-thread big Nat result");
        lean_dec(expected);
        lean_dec(tasks[i]);
    }
    auto original = lean_task_pure(lean_box(2));
    auto mapped = lean_task_map_core(lean_alloc_closure((void *)add_one, 1, 0), original, 0, false, false);
    require(lean_nat_dec_eq(lean_task_get(mapped), lean_box(3)), "Task.map");
    auto bound = lean_task_bind_core(mapped, lean_alloc_closure((void *)nested, 1, 0), 0, false, false);
    require(lean_nat_dec_eq(lean_task_get(bound), lean_box(180)), "Task.bind");
    lean_dec(bound);
    auto dedicated_closure = lean_alloc_closure((void *)task_body, 2, 1);
    lean_closure_set(dedicated_closure, 0, lean_box(3));
    auto dedicated = lean_task_spawn_core(dedicated_closure, 9, false);
    require(lean_nat_dec_eq(lean_task_get(dedicated), lean_box(180)), "dedicated Task");
    lean_dec(dedicated);
    auto promise = lean::lean_promise_new();
    auto promised = lean::lean_io_promise_result_opt(promise);
    {
        lean::lthread resolver([&] {
            lean::this_thread::sleep_for(std::chrono::milliseconds(3));
            lean::lean_promise_resolve(lean_box(42), promise);
        });
        auto option = lean_task_get(promised);
        require(lean_obj_tag(option) == 1 && lean_unbox(lean_ctor_get(option, 0)) == 42, "Promise resolution");
        resolver.join();
    }
    lean_dec(promised);
    lean_dec(promise);
    lean_finalize_task_manager();
    require(workers == 26, "worker execution count");
    puts("PASS: upstream Task spawn/map/bind/dedicated + RTX workers");

    lean::set_heartbeats(1234);
    lean::set_max_heartbeat(7654);
    for (unsigned iteration = 0; iteration < 12; ++iteration) {
        lean::lthread worker([&] {
            require(lean::get_num_heartbeats() == 0, "new worker inherited allocation counter");
            require(lean::get_max_heartbeat() == 7654, "heartbeat limit propagation");
            lean::set_heartbeats(9000 + iteration);
            for (unsigned i = 0; i < 20; ++i) {
                auto n = lean_cstr_to_nat("184467440737095516170");
                lean_dec(n);
                lean::this_thread::sleep_for(std::chrono::milliseconds(1));
            }
            try { throw std::runtime_error("worker exception"); }
            catch (std::runtime_error const &) {}
        });
        worker.join();
        require(lean::get_num_heartbeats() == 1234, "TLS leaked between RTX threads");
    }
    puts("PASS: TLS isolation/reuse, concurrent allocation, C++ exceptions");
    lean::recursive_mutex recursive;
    recursive.lock(); require(recursive.try_lock(), "recursive mutex"); recursive.unlock(); recursive.unlock();
    lean::shared_mutex shared;
    shared.lock_shared(); require(shared.try_lock_shared(), "shared readers");
    require(!shared.try_lock(), "writer excluded by readers");
    shared.unlock_shared(); shared.unlock_shared();
    require(shared.try_lock(), "shared writer"); require(!shared.try_lock_shared(), "reader excluded by writer"); shared.unlock();
    puts("PASS: RTX recursive/shared mutexes");
    {
        std::atomic<unsigned> complete{0};
        auto allocate = [&] {
            require(guarded() == 42, "C++ static initialization");
            for (unsigned i=0; i<1600; ++i) {
                auto n = lean_cstr_to_nat("184467440737095516170000");
                auto m = lean_nat_mul(n, n);
                lean_dec(m); lean_dec(n);
                if ((i % 16) == 0) lean::this_thread::sleep_for(std::chrono::milliseconds(1));
            }
            ++complete;
        };
        lean::lthread first(allocate), second(allocate);
        allocate();
        first.join(); second.join();
        require(complete == 3 && static_constructions == 1, "concurrent allocator/static guard");
    }
    puts("PASS: Promise wait/resolve, concurrent heap stress, C++ once guard");
    auto ref = lean_st_mk_ref(lean_box(10));
    lean_mark_mt(ref);
    auto old = lean_st_ref_swap(ref, lean_box(11));
    require(lean_unbox(old) == 10, "ST.Ref swap");
    lean_dec(old);
    auto current = lean_st_ref_get(ref);
    require(lean_unbox(current) == 11, "ST.Ref get");
    lean_dec(current); lean_dec(ref);
    auto before = lean_io_mono_ms_now();
    lean::this_thread::sleep_for(std::chrono::milliseconds(3));
    auto after = lean_io_mono_ms_now();
    require(lean_nat_dec_lt(before, after), "monotonic clock");
    lean_dec(before); lean_dec(after);
    volatile double input = 3.25;
    auto boxed_float = lean_box_float(lean_float_add(lean_float_mul(input, 2.0), 1.0));
    require(lean_unbox_float(boxed_float) == 7.5, "FPU/boxed Float round trip");
    lean_dec(boxed_float);
    puts("PASS: upstream ST.Ref primitives + RTX monotonic clock");
    return 0;
}
