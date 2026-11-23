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

use crate::common;
pub use crate::fas_types::FasRulesConfig;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

pub fn get_rules_path() -> PathBuf {
    common::get_module_root().join("rules.yaml")
}

/// 统一的规则读取入口：解析后立即迁移，避免各调用点漏掉。
pub fn read_rules<P: AsRef<std::path::Path>>(path: P) -> anyhow::Result<RulesConfig> {
    let mut rules: RulesConfig = crate::utils::read_config(path)?;
    rules.migrate();
    Ok(rules)
}

impl RulesConfig {
    /// 把旧版规则就地迁移到当前结构。返回是否发生了迁移。
    pub fn migrate(&mut self) -> bool {
        if self.schema_version > RULES_SCHEMA_VERSION {
            log::warn!(
                "[Config] rules.yaml 结构版本 {} 高于程序支持的 {}，按兼容模式读取",
                self.schema_version,
                RULES_SCHEMA_VERSION
            );
            return false;
        }
        if self.schema_version >= RULES_SCHEMA_VERSION {
            return false;
        }
        // v0 -> v1：把旧的 per_app_margins 迁到 per_app_profiles
        self.fas_rules.migrate_legacy_margins();
        self.schema_version = RULES_SCHEMA_VERSION;
        log::info!(
            "[Config] rules.yaml 已迁移到结构版本 v{}",
            RULES_SCHEMA_VERSION
        );
        true
    }
}

#[cfg(test)]
mod tests {
    use super::{RULES_SCHEMA_VERSION, RulesConfig};

    #[test]
    fn old_rules_are_migrated_and_versioned() {
        let yaml = "dynamic_enabled: true\nglobal_mode: balance\napp_modes: {}\nfas_rules:\n  per_app_margins:\n    com.demo: 4.0\n";
        let mut rules: RulesConfig = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(rules.schema_version, 0);
        assert!(rules.migrate());
        assert_eq!(rules.schema_version, RULES_SCHEMA_VERSION);
        assert_eq!(rules.fas_rules.per_app_margins.len(), 0);
        assert_eq!(
            rules.fas_rules.per_app_profiles["com.demo"].fps_margin,
            Some(4.0)
        );
        // 幂等：第二次迁移不再改动
        assert!(!rules.migrate());
    }

    #[test]
    fn future_version_is_read_without_touching_fields() {
        let yaml =
            "schema_version: 99\ndynamic_enabled: true\nglobal_mode: balance\napp_modes: {}\n";
        let mut rules: RulesConfig = serde_yaml::from_str(yaml).unwrap();
        assert!(!rules.migrate());
        assert_eq!(rules.schema_version, 99);
    }
}

// ════════════════════════════════════════════════════════════════
//  Rules 配置
// ════════════════════════════════════════════════════════════════

/// 当前规则文件的结构版本。新增字段或改变字段语义时递增，并在 migrate 里补迁移。
pub const RULES_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct RulesConfig {
    /// 规则结构版本；缺失时为 0，表示旧版文件
    #[serde(default)]
    pub schema_version: u32,
    #[serde(default = "crate::utils::default_true")]
    pub yumi_scheduler: bool,
    pub dynamic_enabled: bool,
    pub global_mode: String,
    pub app_modes: HashMap<String, String>,
    #[serde(default)]
    pub ignored_apps: Vec<String>,
    #[serde(default)]
    pub fas_rules: FasRulesConfig,
}
