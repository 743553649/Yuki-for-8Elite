/*
 * Copyright (C) 2026 yuki
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

use crate::monitor::config::RulesConfig;
use std::path::PathBuf;
use std::env;
use std::sync::atomic::{AtomicBool, Ordering};

/// 守护进程全局事件总线
#[derive(Debug, Clone)]
pub enum DaemonEvent {
    /// 低频事件：前台应用切换或环境温度变化引起的模式改变
    ModeChange {
        package_name: String,
        pid: i32,
        mode: String,
        temperature: f64,
    },
    /// 高频事件：eBPF 捕获到的底层渲染帧数据
    FrameUpdate {
        frame_delta_ns: u64, // 纳秒级帧间隔
        pid: u32,
        sampled_at: std::time::Instant,
    },
    /// eBPF 全局系统负载更新 (每 X 毫秒触发一次)
    SystemLoadUpdate {
        sampled_at: std::time::Instant,
        /// 每个 CPU 核心的真实利用率 (0.0 ~ 1.0)，数组索引即 cpu_id
        core_utils: Vec<f32>,
        /// 如果当前有前台应用，这是该应用最吃 CPU 的那 1 个线程的利用率
        foreground_max_util: f32, 
    },

    CpuMonitorUnavailable,
    FpsProbeUnavailable,
    ConfigReload(RulesConfig),

    ScreenStateChange(bool),
}

// ════════════════════════════════════════════════════════════════
//  退出信号
// ════════════════════════════════════════════════════════════════

/// 收到 SIGTERM / SIGINT 后置位；各循环检查它来决定何时退出。
/// 用普通原子量而不是 channel：信号处理函数里不能做 IO、不能加锁。
static SHUTDOWN_REQUESTED: AtomicBool = AtomicBool::new(false);

/// 信号处理函数：只置标志，真正的恢复动作留给主循环
extern "C" fn handle_shutdown_signal(_signal: libc::c_int) {
    SHUTDOWN_REQUESTED.store(true, Ordering::Relaxed);
}

/// 安装 SIGTERM / SIGINT 处理。
/// 用 sigaction 而不是 signal()：SA_RESTART 避免打断 inotify 等阻塞调用。
pub fn install_signal_handlers() -> std::io::Result<()> {
    unsafe {
        let mut action: libc::sigaction = std::mem::zeroed();
        action.sa_sigaction = handle_shutdown_signal as *const () as usize;
        action.sa_flags = libc::SA_RESTART;
        libc::sigemptyset(&mut action.sa_mask);
        for signal in [libc::SIGTERM, libc::SIGINT] {
            if libc::sigaction(signal, &action, std::ptr::null_mut()) != 0 {
                return Err(std::io::Error::last_os_error());
            }
        }
    }
    Ok(())
}

pub fn shutdown_requested() -> bool {
    SHUTDOWN_REQUESTED.load(Ordering::Relaxed)
}

/// 可被退出信号打断的睡眠：长退避期间也能在 200ms 内响应停止请求
pub fn sleep_interruptible(duration: std::time::Duration) {
    let deadline = std::time::Instant::now() + duration;
    while !shutdown_requested() {
        let now = std::time::Instant::now();
        if now >= deadline {
            break;
        }
        std::thread::sleep((deadline - now).min(std::time::Duration::from_millis(200)));
    }
}

/// 获取模块根目录的绝对路径
pub fn get_module_root() -> PathBuf {
    // 获取当前执行文件的绝对路径
    let exe_path = env::current_exe().unwrap_or_else(|_| PathBuf::from("/"));
    
    // 回溯两级目录:
    // core/bin/yumi -> core/bin -> core -> yumi
    exe_path
        .parent().unwrap_or(&exe_path) // .../core/bin
        .parent().unwrap_or(&exe_path) // .../core
        .parent().unwrap_or(&exe_path) // .../yumi (Root)
        .to_path_buf()
}
