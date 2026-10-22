/* Included inside namespace lean in upstream runtime/thread.cpp.
 * Keep upstream thread_main, heartbeat propagation, and finalizers. */
struct lthread::imp {
    osThreadId_t m_thread;
    bool m_joined = false;
    static void entry(void * argument) {
        thread_main(argument);
        lean_cmsis_tls_cleanup();
        osThreadExit();
    }
    imp(runnable const & fn) {
        auto action = std::make_unique<runnable>(mk_thread_proc(fn, get_max_heartbeat()));
        osThreadAttr_t attr{};
        attr.name = "lean-worker";
        attr.attr_bits = osThreadJoinable;
        attr.stack_size = uint32_t(m_thread_stack_size);
        attr.priority = osPriorityNormal;
        // A worker may preempt its creator immediately; transfer ownership first.
        runnable * raw = action.release();
        m_thread = osThreadNew(entry, raw, &attr);
        if (!m_thread) { delete raw; cmsis_fail("osThreadNew (RTX memory exhausted)"); }
    }
    ~imp() {
        if (!m_joined) cmsis_check(osThreadDetach(m_thread), "osThreadDetach");
    }
    void join() {
        cmsis_check(osThreadJoin(m_thread), "osThreadJoin");
        m_joined = true;
    }
};
