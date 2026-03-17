#!/usr/bin/env python3
"""
Image text extraction and structuring using Gemini via GitHub Models API.

Usage:
    python image_analyzer.py <image_path> [image_path2 ...]
    python image_analyzer.py <image_path> --prompt "Extract invoice fields"

Requires:
    GITHUB_TOKEN environment variable with a valid GitHub personal access token
    that has access to GitHub Models (Copilot Pro / GitHub Models preview).
"""

import argparse
import base64
import json
import mimetypes
import os
import sys
from pathlib import Path

from openai import OpenAI

# GitHub Models endpoint and the Gemini 2.5 Pro model identifier
GITHUB_MODELS_ENDPOINT = "https://models.inference.ai.azure.com"
DEFAULT_MODEL = "google/gemini-2.5-pro"

DEFAULT_PROMPT = (
    "Please analyze the image carefully and extract all text and structured "
    "information you can identify. Return ONLY a valid JSON object (no markdown "
    "fences, no extra commentary) with the following structure:\n"
    "{\n"
    '  "raw_text": "<all text found in the image, preserving layout>",\n'
    '  "structured_data": { <key-value pairs of any structured information, '
    "such as form fields, table data, labels and values, dates, amounts, etc.> },\n"
    '  "summary": "<brief description of what the image contains>"\n'
    "}"
)

SUPPORTED_MIME_TYPES = {
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/webp",
}


def load_image_as_data_url(image_path: str) -> tuple[str, str]:
    """Read an image file and return (mime_type, base64-encoded data URL)."""
    path = Path(image_path)
    if not path.exists():
        raise FileNotFoundError(f"Image file not found: {image_path}")
    if not path.is_file():
        raise ValueError(f"Path is not a file: {image_path}")

    mime_type, _ = mimetypes.guess_type(str(path))
    if mime_type is None:
        # Fallback: read magic bytes
        with open(path, "rb") as f:
            header = f.read(16)
        if header[:8] == b"\x89PNG\r\n\x1a\n":
            mime_type = "image/png"
        elif header[:3] == b"\xff\xd8\xff":
            mime_type = "image/jpeg"
        elif header[:6] in (b"GIF87a", b"GIF89a"):
            mime_type = "image/gif"
        elif header[:4] == b"RIFF" and header[8:12] == b"WEBP":
            mime_type = "image/webp"
        else:
            mime_type = "image/jpeg"  # best-effort fallback

    if mime_type not in SUPPORTED_MIME_TYPES:
        raise ValueError(
            f"Unsupported image type '{mime_type}' for {image_path}. "
            f"Supported types: {', '.join(sorted(SUPPORTED_MIME_TYPES))}"
        )

    with open(path, "rb") as f:
        encoded = base64.b64encode(f.read()).decode("utf-8")

    data_url = f"data:{mime_type};base64,{encoded}"
    return mime_type, data_url


def build_message_content(data_urls: list[str], prompt: str) -> list[dict]:
    """Build the multimodal message content list."""
    content: list[dict] = []
    for data_url in data_urls:
        content.append({"type": "image_url", "image_url": {"url": data_url}})
    content.append({"type": "text", "text": prompt})
    return content


def analyze_images(
    image_paths: list[str],
    prompt: str = DEFAULT_PROMPT,
    model: str = DEFAULT_MODEL,
    token: str | None = None,
) -> dict:
    """
    Send images to the Gemini model via GitHub Models and return parsed JSON.

    Args:
        image_paths: List of local image file paths.
        prompt: Instruction sent along with the images.
        model: Model identifier to use.
        token: GitHub personal access token. Defaults to GITHUB_TOKEN env var.

    Returns:
        Parsed JSON dictionary from the model response.

    Raises:
        ValueError: If no GitHub token is available.
        json.JSONDecodeError: If the model response cannot be parsed as JSON.
    """
    if token is None:
        token = os.environ.get("GITHUB_TOKEN")
    if not token:
        raise ValueError(
            "GitHub token is required. Set the GITHUB_TOKEN environment variable "
            "or pass --token on the command line."
        )

    client = OpenAI(base_url=GITHUB_MODELS_ENDPOINT, api_key=token)

    data_urls: list[str] = []
    for path in image_paths:
        _, data_url = load_image_as_data_url(path)
        data_urls.append(data_url)

    content = build_message_content(data_urls, prompt)

    response = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": content}],
        temperature=0.1,
    )

    raw_text = response.choices[0].message.content or ""

    # Strip markdown code fences if present
    stripped = raw_text.strip()
    if stripped.startswith("```"):
        lines = stripped.splitlines()
        # Remove first fence line (e.g. ```json) and last fence line
        inner_lines = lines[1:]
        if inner_lines and inner_lines[-1].strip() == "```":
            inner_lines = inner_lines[:-1]
        stripped = "\n".join(inner_lines).strip()

    return json.loads(stripped)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract structured text from images using Gemini via GitHub Models."
    )
    parser.add_argument(
        "images",
        nargs="+",
        metavar="IMAGE",
        help="One or more local image file paths (JPEG, PNG, GIF, WebP).",
    )
    parser.add_argument(
        "--prompt",
        default=DEFAULT_PROMPT,
        help="Custom extraction prompt. Defaults to a general-purpose extraction prompt.",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        help=f"GitHub Models model identifier. Default: {DEFAULT_MODEL}",
    )
    parser.add_argument(
        "--token",
        default=None,
        help="GitHub personal access token. Defaults to GITHUB_TOKEN env var.",
    )
    parser.add_argument(
        "--indent",
        type=int,
        default=2,
        help="JSON output indentation (default: 2). Use 0 for compact output.",
    )
    args = parser.parse_args()

    try:
        result = analyze_images(
            image_paths=args.images,
            prompt=args.prompt,
            model=args.model,
            token=args.token,
        )
    except FileNotFoundError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as exc:
        print(f"Error: Model response is not valid JSON — {exc}", file=sys.stderr)
        sys.exit(1)

    indent = args.indent if args.indent > 0 else None
    print(json.dumps(result, ensure_ascii=False, indent=indent))


if __name__ == "__main__":
    main()
