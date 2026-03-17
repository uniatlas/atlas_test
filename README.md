# atlas_test

## 使用 Gemini 2.5 Pro 提取图片中的结构化文字信息

本工具通过 GitHub Models API（Copilot Pro 内置的 Gemini 2.5 Pro 模型）对本地图片进行分析，自动提取其中的文字和结构化信息，并以 JSON 格式输出。

---

## 前置条件

| 要求 | 说明 |
|------|------|
| Python | 3.10 或更高版本 |
| GitHub Token | 具有 GitHub Models（或 Copilot Pro）访问权限的 Personal Access Token |
| 网络 | 能访问 `models.inference.ai.azure.com` |

### 获取 GitHub Token

1. 打开 <https://github.com/settings/tokens>
2. 点击 **"Generate new token (classic)"**
3. 勾选 `read:user`（或根据 GitHub Models 要求选择对应权限）
4. 复制生成的 Token

> **注意**：需要订阅 **GitHub Copilot Pro** 或加入 **GitHub Models** 预览计划，才能访问 `google/gemini-2.5-pro` 模型。

---

## 安装

```bash
pip install -r requirements.txt
```

---

## 使用方法

### 1. 设置环境变量

```bash
export GITHUB_TOKEN="ghp_your_token_here"
```

### 2. 分析单张图片（使用默认提示词）

```bash
python image_analyzer.py path/to/image.png
```

### 3. 分析多张图片

```bash
python image_analyzer.py invoice.jpg receipt.png form.webp
```

### 4. 使用自定义提示词

```bash
python image_analyzer.py invoice.jpg --prompt "提取发票中的所有字段，包括金额、日期、购买方和销售方信息"
```

### 5. 指定不同模型

```bash
python image_analyzer.py image.png --model google/gemini-2.5-pro
```

### 6. 紧凑 JSON 输出（无缩进）

```bash
python image_analyzer.py image.png --indent 0
```

---

## 输出示例

默认情况下，脚本输出包含以下字段的 JSON：

```json
{
  "raw_text": "图片中识别到的所有文字，尽量保留原有排版",
  "structured_data": {
    "发票号码": "12345678",
    "开票日期": "2024-01-15",
    "购买方": "某某有限公司",
    "金额": "¥1,234.56"
  },
  "summary": "这是一张增值税普通发票"
}
```

---

## 命令行参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `IMAGE` | 一个或多个本地图片路径（支持 JPEG、PNG、GIF、WebP） | 必填 |
| `--prompt` | 自定义提取提示词 | 通用结构化提取提示词 |
| `--model` | GitHub Models 模型标识符 | `google/gemini-2.5-pro` |
| `--token` | GitHub Token（优先于环境变量） | `$GITHUB_TOKEN` |
| `--indent` | JSON 输出缩进空格数，0 表示紧凑格式 | `2` |

---

## 在 Python 代码中使用

```python
import os
from image_analyzer import analyze_images

result = analyze_images(
    image_paths=["invoice.jpg"],
    prompt="提取发票中的所有字段",
    token=os.environ["GITHUB_TOKEN"],
)

print(result["structured_data"])
```

---

## 支持的图片格式

- JPEG / JPG
- PNG
- GIF
- WebP
