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

//! CPU 原始状态基线（落盘快照）。
//!
//! 问题背景：守护进程被 OOM 杀死、`kill -9` 或掉电时，恢复逻辑根本来不及执行，
//! 受限的 governor / 频率区间会留在系统里；下次启动又把这些受限值当成"原始值"。
//!
//! 做法：真正写入 sysfs 之前，把 governor 与频率上下限写到模块根目录的
//! `cpufreq_baseline.conf`。正常退出恢复成功后删除；下次启动若发现它还在，
//! 说明上次没恢复干净，先按它恢复再接管。

use log::{info, warn};
use std::fs;
use std::path::PathBuf;

use crate::common;

const HEADER: &str = "# yumi cpu baseline v1";

/// 单个 policy 的原始状态
pub struct PolicyBaseline {
    pub id: i32,
    pub governor: String,
    pub min: u32,
    pub max: u32,
}

pub fn path() -> PathBuf {
    common::get_module_root().join("cpufreq_baseline.conf")
}

/// 确保基线文件记录了本次接管前的原始状态。
///
/// - policy 部分只在文件里还没有时写入：系统原始状态运行期不会变；
///   若文件已存在，说明是上次异常退出留下的，那才是真正的原始值，不能覆盖。
/// - perfmgr 部分按路径补齐：CLG 先接管、FAS 后接管时，perfmgr 的原始值
///   只有 FAS 才会改动，需要追加进同一份快照。
pub fn ensure(policies: &[PolicyBaseline], perfmgr: &[(String, String)]) -> bool {
    let file = path();
    let existing = fs::read_to_string(&file).unwrap_or_default();
    let mut lines: Vec<String> = existing
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_owned)
        .collect();
    let mut changed = false;

    if lines.is_empty() {
        lines.push(HEADER.to_string());
        changed = true;
    }

    if !policies.is_empty() && !lines.iter().any(|line| line.starts_with("policy ")) {
        for policy in policies {
            lines.push(format!(
                "policy {} {} {} {}",
                policy.id, policy.governor, policy.min, policy.max
            ));
        }
        changed = true;
    }

    for (path_value, value) in perfmgr {
        let prefix = format!("perfmgr {path_value} ");
        if !lines.iter().any(|line| line.starts_with(&prefix)) {
            lines.push(format!("perfmgr {} {}", path_value, value.trim()));
            changed = true;
        }
    }

    if changed {
        match write_atomic(&file, &(lines.join("\n") + "\n")) {
            Ok(()) => {
                info!("[Baseline] CPU 原始状态已记录: {}", file.display());
                true
            }
            // 落盘失败不影响调频本身，但必须留下日志：这次异常退出将无法自动恢复
            Err(error) => {
                warn!("[Baseline] 记录 CPU 原始状态失败: {error}");
                false
            }
        }
    } else {
        // 文件已存在（CLG 先接管时写过），基线有效
        true
    }
}

/// 启动时调用：如果上次异常退出留下了快照，按它恢复原始状态。
///
/// 返回 Ok(true) 表示确实执行了恢复；恢复失败时保留文件，下次启动再试。
pub fn restore_pending() -> std::io::Result<bool> {
    let file = path();
    let text = match fs::read_to_string(&file) {
        Ok(text) => text,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error),
    };

    // 先解析再动手：文件损坏时宁可不动 sysfs，也不写半截状态
    let mut policies = Vec::new();
    let mut perfmgr = Vec::new();
    for line in text.lines().map(str::trim) {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let fields: Vec<&str> = line.split_whitespace().collect();
        match fields.as_slice() {
            ["policy", id, governor, min, max] => {
                match (id.parse::<i32>(), min.parse::<u32>(), max.parse::<u32>()) {
                    (Ok(id), Ok(min), Ok(max)) => policies.push(PolicyBaseline {
                        id,
                        governor: (*governor).to_owned(),
                        min,
                        max,
                    }),
                    _ => warn!("[Baseline] 无法解析快照行: {line}"),
                }
            }
            ["perfmgr", path_value, value] => {
                perfmgr.push(((*path_value).to_owned(), (*value).to_owned()));
            }
            _ => warn!("[Baseline] 忽略无法识别的快照行: {line}"),
        }
    }

    if policies.is_empty() && perfmgr.is_empty() {
        let _ = fs::remove_file(&file);
        return Ok(false);
    }

    let mut failed = 0usize;
    for policy in &policies {
        if !restore_policy(policy) {
            failed += 1;
        }
    }
    for (path_value, value) in &perfmgr {
        if fs::write(path_value, format!("{value}\n")).is_err() {
            failed += 1;
        }
    }

    if failed == 0 {
        // 恢复干净了才删快照；否则保留，下次启动继续尝试
        let _ = fs::remove_file(&file);
        info!("[Baseline] 已恢复上次异常退出前的 CPU 原始状态");
        Ok(true)
    } else {
        warn!("[Baseline] 有 {failed} 项恢复失败，快照保留，下次启动重试");
        Ok(true)
    }
}

fn restore_policy(policy: &PolicyBaseline) -> bool {
    let base = PathBuf::from(format!(
        "/sys/devices/system/cpu/cpufreq/policy{}",
        policy.id
    ));
    if !base.is_dir() {
        // policy 已不存在（CPU 热插拔或设备差异），没有可恢复的对象
        return true;
    }

    // 先放宽上限再调整下限：即使当前下限高于原始上限，也不会出现 min>max 的中间态
    let max_write = fs::write(base.join("scaling_max_freq"), format!("{}\n", policy.max));
    if max_write.is_err() {
        let _ = fs::write(base.join("scaling_min_freq"), format!("{}\n", policy.min));
        let _ = fs::write(base.join("scaling_max_freq"), format!("{}\n", policy.max));
    } else {
        let _ = fs::write(base.join("scaling_min_freq"), format!("{}\n", policy.min));
    }
    fs::write(
        base.join("scaling_governor"),
        format!("{}\n", policy.governor),
    )
    .is_ok()
}

/// 正常退出且恢复成功后调用
pub fn clear() {
    let _ = fs::remove_file(path());
}

/// 先写临时文件再改名，避免写到一半掉电留下半截快照
fn write_atomic(file: &PathBuf, content: &str) -> std::io::Result<()> {
    let temp = file.with_extension("conf.tmp");
    fs::write(&temp, content)?;
    fs::rename(&temp, file)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_lines_round_trip() {
        let text = format!(
            "{HEADER}\npolicy 0 schedutil 300000 1500000\npolicy 4 performance 500000 2000000\nperfmgr /sys/module/perfmgr/parameters/perfmgr_enable 1\n"
        );
        let mut policies = Vec::new();
        let mut perfmgr = Vec::new();
        for line in text.lines().map(str::trim) {
            let fields: Vec<&str> = line.split_whitespace().collect();
            match fields.as_slice() {
                ["policy", id, governor, min, max] => policies.push(PolicyBaseline {
                    id: id.parse().unwrap(),
                    governor: (*governor).to_owned(),
                    min: min.parse().unwrap(),
                    max: max.parse().unwrap(),
                }),
                ["perfmgr", path_value, value] => {
                    perfmgr.push(((*path_value).to_owned(), (*value).to_owned()))
                }
                _ => {}
            }
        }
        assert_eq!(policies.len(), 2);
        assert_eq!(policies[1].id, 4);
        assert_eq!(policies[1].governor, "performance");
        assert_eq!((policies[0].min, policies[0].max), (300_000, 1_500_000));
        assert_eq!(perfmgr.len(), 1);
        assert_eq!(perfmgr[0].1, "1");
    }
}
