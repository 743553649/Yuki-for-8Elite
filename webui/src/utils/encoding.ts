// 通过 KernelSU 的 root shell 写文件时，内容统一走 base64：
// base64 字符集只有 A-Za-z0-9+/=，放进 shell 单引号里不会被解释。
// 独立成模块便于单元测试，也避免把逻辑绑死在 window.ksu 上。

/** 把任意 UTF-8 文本编码成无换行的 base64 */
export function encodeUtf8Base64(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

/** 把 base64 还原成 UTF-8 文本（用于测试与诊断） */
export function decodeUtf8Base64(encoded: string): string {
  const binary = atob(encoded);
  const bytes = Uint8Array.from(binary, (ch) => ch.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}
