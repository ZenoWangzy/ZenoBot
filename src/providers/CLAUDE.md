[根目录](../../CLAUDE.md) > [src](../) > **providers**

# Providers

## 模块职责

Providers 模块实现了 OpenClaw 与各种 LLM 提供者的集成，包括：

1. **API 集成** - 与各 LLM 提供者的 API 通信
2. **模型适配** - 统一不同提供者的接口
3. **流式处理** - 处理流式响应
4. **错误处理** - 提供者特定的错误处理
5. **认证管理** - API 密钥和认证

## 入口与启动

- 主入口：`index.ts` - 导出所有提供者
- 注册：`registry.ts` - 提供者注册表
- 选择：`model-picker.ts` - 模型选择逻辑

## 对外接口

### 支持的提供者

| 提供者 | 模块 | 描述 |
|--------|------|------|
| OpenAI | `openai/` | GPT-4、GPT-3.5 等 |
| Anthropic | `anthropic/` | Claude 系列 |
| Google | `google/` | Gemini 系列 |
| OpenRouter | `openrouter/` | 多模型聚合 |
| Ollama | `ollama/` | 本地模型 |
| Groq | `groq/` | 快速推理 |
| Mistral | `mistral/` | Mistral 系列 |
| Azure | `azure/` | Azure OpenAI |
| AWS | `aws/` | Bedrock |
| Cerebras | `cerebras/` | Cerebras |
| DeepSeek | `deepseek/` | DeepSeek |
| xAI | `xai/` | Grok |

### 核心接口

| 模块 | 职责 |
|------|------|
| `types.ts` | 提供者类型定义 |
| `registry.ts` | 提供者注册表 |
| `model-picker.ts` | 模型选择 |
| `model-config.ts` | 模型配置 |
| `capabilities.ts` | 能力查询 |

### 通用功能

| 模块 | 职责 |
|------|------|
| `stream-parser.ts` | 流解析 |
| `error-handling.ts` | 错误处理 |
| `rate-limit.ts` | 速率限制 |
| `retry.ts` | 重试逻辑 |

## 关键依赖与配置

### 认证配置

```json
{
  "providers": {
    "openai": {
      "apiKey": "sk-..."
    },
    "anthropic": {
      "apiKey": "sk-ant-..."
    },
    "google": {
      "apiKey": "..."
    }
  }
}
```

### 环境变量

- `OPENAI_API_KEY` - OpenAI API 密钥
- `ANTHROPIC_API_KEY` - Anthropic API 密钥
- `GOOGLE_API_KEY` - Google API 密钥
- `OPENROUTER_API_KEY` - OpenRouter API 密钥

## 数据模型

### 提供者接口

```typescript
interface Provider {
  id: string;
  name: string;
  models: Model[];
  chat(params: ChatParams): AsyncIterable<ChatChunk>;
  complete(params: CompleteParams): Promise<string>;
}
```

### 模型配置

```typescript
interface Model {
  id: string;
  name: string;
  contextWindow: number;
  maxOutput: number;
  capabilities: string[];
}
```

## 测试与质量

- 测试覆盖：各提供者的 API 调用、流处理、错误处理
- Live 测试：`LIVE=1 pnpm test:live`

## 常见问题 (FAQ)

### 如何添加新的提供者？

1. 在 `src/providers/<name>/` 创建目录
2. 实现 `Provider` 接口
3. 在 `registry.ts` 中注册
4. 添加配置类型

### 如何调试提供者问题？

1. 检查 API 密钥：`openclaw config get providers.<name>.apiKey`
2. 启用调试日志：`DEBUG=openclaw:provider:<name>:*`
3. 检查速率限制和配额

## 相关文件清单

```
src/providers/
├── index.ts                # 导出
├── types.ts                # 类型
├── registry.ts             # 注册表
├── model-picker.ts         # 模型选择
├── model-config.ts         # 模型配置
├── capabilities.ts         # 能力
├── openai/                 # OpenAI
├── anthropic/              # Anthropic
├── google/                 # Google
├── openrouter/             # OpenRouter
├── ollama/                 # Ollama
├── groq/                   # Groq
├── mistral/                # Mistral
├── azure/                  # Azure
├── aws/                    # AWS Bedrock
├── cerebras/               # Cerebras
├── deepseek/               # DeepSeek
├── xai/                    # xAI
└── *.test.ts               # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档
