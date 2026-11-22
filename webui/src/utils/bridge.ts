// src/utils/bridge.ts
import { exec, toast, listPackages } from '@/kernelsu'; 
import yaml from 'js-yaml';
import { MockBridge } from './mock';
import i18n from '@/i18n';

declare global {
  interface Window {
    ksu?: any;
  }
}

const MODULE_BASE_PATH = "/data/adb/modules/yumi"; 
const PATHS = {
  RULES_YAML: `${MODULE_BASE_PATH}/rules.yaml`,          
  CONFIG_YAML: `${MODULE_BASE_PATH}/config/config.yaml`, 
  CURRENT_MODE: `${MODULE_BASE_PATH}/current_mode.txt`,
  DAEMON_LOG: `${MODULE_BASE_PATH}/logs/daemon.log`
};

const isDev = import.meta.env.DEV || typeof window.ksu === 'undefined';

// 把任意 UTF-8 文本编码成 base64。写入文件时只把 base64 交给 shell，
// 避免内容里的 $、反引号、反斜杠被 shell 解释（轻则写坏 YAML，重则执行命令）。
const encodeBase64Utf8 = (text: string): string => {
  const bytes = new TextEncoder().encode(text);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
};

// 严格解析配置文件：读取失败或内容不是 YAML 对象时直接抛错，绝不返回空对象。
// 调用方只有在拿到合法对象后才允许写回，防止把现有规则整体覆盖成空配置。
const parseConfigObject = (text: string, path: string): Record<string, unknown> => {
  if (!text.trim()) return {};
  let parsed: unknown;
  try {
    parsed = yaml.load(text);
  } catch (e) {
    throw new Error(i18n.global.t('config_parse_failed', { path }) as string);
  }
  if (parsed == null) return {};
  if (typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error(i18n.global.t('config_parse_failed', { path }) as string);
  }
  return parsed as Record<string, unknown>;
};

const RealBridge = {
  async isDaemonRunning(): Promise<boolean> {
    try {
      const { errno, stdout } = await exec(`pidof yumi`);
      return errno === 0 && stdout.trim().length > 0;
    } catch (e) {
      return false;
    }
  },

  async readFile(path: string): Promise<string> {
    const { errno, stdout } = await exec(`cat "${path}"`);
    if (errno !== 0) throw new Error(i18n.global.t('read_failed', { path }) as string);
    return stdout;
  },
  async writeFile(path: string, content: string): Promise<void> {
    // base64 的字符集只有 A-Za-z0-9+/=，放进 shell 单引号里没有注入风险。
    const encoded = encodeBase64Utf8(content);
    const { errno } = await exec(`printf '%s' '${encoded}' | base64 -d > "${path}"`);
    if (errno !== 0) throw new Error(i18n.global.t('write_failed', { path }) as string);
  },

  async getRulesConfig(): Promise<any> {
    return parseConfigObject(await this.readFile(PATHS.RULES_YAML), PATHS.RULES_YAML);
  },
  async saveRulesConfig(config: any): Promise<void> { await this.writeFile(PATHS.RULES_YAML, yaml.dump(config)); },
  async getMainConfig(): Promise<any> {
    return parseConfigObject(await this.readFile(PATHS.CONFIG_YAML), PATHS.CONFIG_YAML);
  },
  async saveMainConfig(config: any): Promise<void> { await this.writeFile(PATHS.CONFIG_YAML, yaml.dump(config)); toast(i18n.global.t('core_config_saved') as string); },

  async getCurrentMode(): Promise<string> { try { return (await this.readFile(PATHS.CURRENT_MODE)).trim(); } catch (e) { return 'balance'; } },
  async setMode(mode: string): Promise<void> {
    const rules = await this.getRulesConfig();
    rules.global_mode = mode;
    await this.saveRulesConfig(rules);
    toast(i18n.global.t('switch_success', { mode }) as string);
  },

  async getInstalledApps(): Promise<string[]> {
    // 主方法: KernelSU 原生 bridge
    try {
      const apps = await listPackages('user');
      if (apps.length > 0) return apps;
    } catch (_) { /* 尝试备用方法 */ }

    // 备用方法: pm shell 命令
    try {
      const { errno, stdout } = await exec('pm list packages -3');
      if (errno === 0 && stdout.trim()) {
        return stdout.trim().split('\n')
          .map(line => line.replace(/^package:/, '').trim())
          .filter(Boolean);
      }
    } catch (_) { /* 备用方法也失败 */ }

    return [];
  },
  // 只读展示用：读取失败时降级为空列表，不影响页面运行；
  // 任何写入路径都会重新严格读取，失败就中止，不会拿空对象覆盖配置。
  async getAppRules(): Promise<Record<string, string>> {
    try { return (await this.getRulesConfig()).app_modes || {}; } catch (e) { return {}; }
  },
  
  // ================= 修改这里 =================
  async saveAppRule(packageName: string, mode: string): Promise<void> {
     const rules = await this.getRulesConfig();
     if (!rules.app_modes) rules.app_modes = {};
     
     if (mode === '') {
       delete rules.app_modes[packageName];
     } else {
       rules.app_modes[packageName] = mode;
     }

     // 如果设为 fas 模式，同步初始化 per_app_profiles
     if (mode === 'fas') {
       if (!rules.fas_rules) rules.fas_rules = {};
       if (!rules.fas_rules.per_app_profiles) rules.fas_rules.per_app_profiles = {};
       
       // 仅在不存在时初始化，防止覆盖用户已修改的帧率配置
       if (!rules.fas_rules.per_app_profiles[packageName]) {
         rules.fas_rules.per_app_profiles[packageName] = {
           target_fps: [30, 60, 90, 120], // 默认覆盖常用帧率
           fps_margin: 3.0
         };
       }
     }
     
     await this.saveRulesConfig(rules);
     toast(i18n.global.t('app_rules_saved') as string);
  },
  // ============================================

  async getDaemonLog(): Promise<string> {
    try {
      const raw = await this.readFile(PATHS.DAEMON_LOG);
      return raw || '';
    } catch (e) {
      return '';
    }
  },

  async getCpuPolicies(): Promise<number[]> {
    try {
      const { errno, stdout } = await exec('ls /sys/devices/system/cpu/cpufreq/');
      if (errno !== 0) return [];
      return stdout.trim().split(/\s+/)
        .filter(s => /^policy\d+$/.test(s))
        .map(s => parseInt(s.replace('policy', ''), 10))
        .sort((a, b) => a - b);
    } catch (e) {
      return [];
    }
  },

  async getAvailableGovernors(policyNum: number): Promise<string[]> {
    try {
      const path = `/sys/devices/system/cpu/cpufreq/policy${policyNum}/scaling_available_governors`;
      const raw = await this.readFile(path);
      return raw.trim().split(/\s+/).filter(Boolean);
    } catch (e) {
      return [];
    }
  }
};

export const Bridge = isDev ? MockBridge : RealBridge;
