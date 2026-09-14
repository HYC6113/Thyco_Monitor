import Darwin

/// `mach_host_self()` 每次调用都会新增一个端口发送权引用，按秒轮询时会持续累积。
/// 全局只取一次，供 CPU / 内存采样复用。
enum MachHost {
    nonisolated static let port: host_t = mach_host_self()
}
