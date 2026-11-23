import js from '@eslint/js';
import pluginVue from 'eslint-plugin-vue';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import prettier from 'eslint-config-prettier';

export default [
  {
    ignores: ['dist/**', 'node_modules/**', 'src/components.d.ts', 'src/auto-imports.d.ts'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...pluginVue.configs['flat/essential'],
  {
    files: ['**/*.vue'],
    languageOptions: {
      parserOptions: { parser: tseslint.parser },
    },
  },
  {
    // KernelSU 注入的全局对象，只在 kernelsu 适配层里使用
    files: ['src/kernelsu/**/*.js'],
    languageOptions: {
      globals: { ksu: 'readonly' },
    },
  },
  {
    // Vue 的 .vue 类型声明固定使用 `{}` 占位，这条规则不适用于 .d.ts
    files: ['**/*.d.ts'],
    rules: { '@typescript-eslint/no-empty-object-type': 'off' },
  },
  {
    languageOptions: {
      globals: { ...globals.browser, ...globals.node },
    },
    rules: {
      'vue/multi-word-component-names': 'off',
      // KernelSU / YAML 桥接层的返回值类型不稳定，mock 与桥接层有意使用 any
      '@typescript-eslint/no-explicit-any': 'off',
      // 捕获后不使用的错误很常见（降级路径），不要因此报错
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_', caughtErrors: 'none' }],
    },
  },
  // 放在最后：关闭与 Prettier 冲突的格式类规则，格式交给 Prettier
  prettier,
];
