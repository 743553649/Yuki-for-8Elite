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

mod common;
pub mod fas_types;
pub mod i18n;
mod logger;
mod monitor;
mod scheduler;
pub mod utils;
use crate::i18n::{load_language, t, t_with_args};
use crate::scheduler::config::Config;
use anyhow::Result;
use log::{error, info};
use std::sync::mpsc;
use std::thread;

fn main() -> Result<()> {
    // 1. 环境初始化
    if let Some(path) = std::env::args().nth(1) {
        nix::unistd::chdir(path.as_str())?;
    }

    let root = common::get_module_root();
    let log_dir = root.join("logs");
    std::fs::create_dir_all(&log_dir)?;

    // 2. 提前读取配置：读不出来也要把守护进程拉起来（否则什么都监控不了），
    //    但错误必须在日志初始化后报到日志里，不能静默换默认参数
    let config_path: std::path::PathBuf = root.join("config/config.yaml");
    let (config, config_error) =
        Config::from_file_or_default(config_path.to_str().unwrap_or_default());

    // 3. 立即加载语言
    load_language(&config.meta.language);

    // 4. 初始化日志
    logger::init(&config.meta.loglevel)?;

    if let Some(error) = config_error {
        error!(
            "{}",
            t_with_args(
                "config-load-failed",
                &fluent_args!(
                    "path" => config_path.display().to_string(),
                    "error" => error.to_string()
                )
            )
        );
    }

    info!("{}", t("yumi-module-starting"));

    // 5. 上次若被强杀，快照会留在模块目录里：先把原始 CPU 状态恢复，再重新接管，
    //    否则会把已经受限的频率当成"手机原始状态"记录下来
    match scheduler::baseline::restore_pending() {
        Ok(true) => info!("{}", t("baseline-restored")),
        Ok(false) => {}
        Err(error) => error!(
            "{}",
            t_with_args(
                "baseline-restore-failed",
                &fluent_args!(
                    "error" => error.to_string()
                )
            )
        ),
    }

    // 6. 安装 SIGTERM/SIGINT 处理：停止服务时先恢复频率再退出
    if let Err(error) = common::install_signal_handlers() {
        error!(
            "{}",
            t_with_args(
                "signal-handler-install-failed",
                &fluent_args!(
                    "error" => error.to_string()
                )
            )
        );
    }

    // 7. 创建通信通道
    let (tx, rx) = mpsc::channel::<common::DaemonEvent>();

    // 8. 启动 Scheduler
    let scheduler_thread = match scheduler::start_scheduler_thread(rx) {
        Ok(handle) => handle,
        Err(e) => {
            error!(
                "{}",
                t_with_args(
                    "scheduler-module-start-failed",
                    &fluent_args!("error" => e.to_string())
                )
            );
            return Err(e);
        }
    };
    info!("{}", t("scheduler-module-started"));

    // 9. 启动 Monitor
    let monitor_thread = thread::Builder::new()
        .name("monitor_core".to_string())
        .spawn(move || {
            if let Err(e) = monitor::start_monitor(tx) {
                error!(
                    "{}",
                    t_with_args(
                        "monitor-module-crashed",
                        &fluent_args!("error" => e.to_string())
                    )
                );
            }
        })?;

    info!("{}", t("monitor-module-started"));

    // 10. 两个线程都要等：退出信号到达时监控线程先退，调度线程随后恢复 CPU 状态。
    //     只等监控线程就返回会导致恢复逻辑被进程退出打断。
    if monitor_thread.join().is_err() {
        error!("{}", t("monitor-thread-panicked"));
    }
    if scheduler_thread.join().is_err() {
        error!("{}", t("scheduler-thread-panicked"));
    }

    info!("{}", t("yumi-module-stopped"));
    Ok(())
}
