import { describe, expect, it } from 'vitest';
import { decodeUtf8Base64, encodeUtf8Base64 } from './encoding';

describe('base64 helpers', () => {
  it('round-trips ASCII, Chinese and shell metacharacters', () => {
    const text = ['global_mode: "fas"', '# $HOME `id` \\ $(rm -rf /) ', '中文规则：王者荣耀'].join('\n');
    expect(decodeUtf8Base64(encodeUtf8Base64(text))).toBe(text);
  });

  it('produces standard base64 without line breaks', () => {
    expect(encodeUtf8Base64('abc')).toBe('YWJj');
    expect(encodeUtf8Base64('a'.repeat(1000))).not.toContain('\n');
  });

  it('round-trips an empty string', () => {
    expect(decodeUtf8Base64(encodeUtf8Base64(''))).toBe('');
  });
});
