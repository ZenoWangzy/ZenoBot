[根目录](../../CLAUDE.md) > [src](../) > **i18n**

# i18n (Internationalization)

## 模块职责

i18n 模块负责国际化支持，包括：

1. **多语言支持** - 支持多种语言的翻译
2. **语言检测** - 自动检测用户语言偏好
3. **格式化** - 日期、数字等的本地化格式化
4. **翻译管理** - 加载和管理翻译资源

## 入口与启动

- 主入口：`index.ts`
- 翻译文件：`locales/` 目录

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | i18n 导出 |
| `locales/` | 翻译文件 |
| `format.ts` | 格式化工具 |

### 使用方式

```typescript
import { t } from '../i18n';

console.log(t('welcome.message'));
console.log(t('greeting', { name: 'User' }));
```

## 关键依赖与配置

### 支持的语言

- English (en)
- 简体中文 (zh-CN)
- 更多语言可通过插件添加

### 配置

```json
{
  "i18n": {
    "defaultLocale": "en",
    "fallbackLocale": "en"
  }
}
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖翻译查找、格式化、回退

## 相关文件清单

```
src/i18n/
├── index.ts           # i18n 导出
├── format.ts          # 格式化
├── locales/           # 翻译文件
│   ├── en.json
│   └── zh-CN.json
└── *.test.ts          # 测试
```

## 相关模块

- [docs/.i18n/](../../docs/.i18n/) - 文档翻译

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
