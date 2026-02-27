#!/usr/bin/env python3
"""
GhostEdit Local Model Inference Script

JSON stdin/stdout protocol for model inference, downloading, and package checking.
Launched as a subprocess by LocalModelRunner.swift.

Commands:
  - infer: Run inference on text using a local model
  - download: Download a model from Hugging Face Hub
  - check_packages: Check which required Python packages are installed

Modes:
  - One-shot (default): Reads single JSON from stdin, writes response to stdout.
  - Serve (--serve): Persistent process reading line-delimited JSON from stdin,
    caching model in memory between requests.
"""

import json
import sys
import time
import os


def cmd_infer(request):
    """Run inference using a local seq2seq model."""
    model_path = request.get("model_path", "")
    text = request.get("text", "")
    max_length = request.get("max_length", 256)

    if not model_path or not text:
        return {"status": "error", "message": "model_path and text are required"}

    if not os.path.isdir(model_path):
        return {"status": "error", "message": f"Model directory not found: {model_path}"}

    try:
        from transformers import AutoTokenizer, AutoModelForSeq2SeqLM

        start = time.time()
        tokenizer = AutoTokenizer.from_pretrained(model_path)
        model = AutoModelForSeq2SeqLM.from_pretrained(model_path)
        inputs = tokenizer(text, return_tensors="pt", max_length=512, truncation=True)
        outputs = model.generate(**inputs, max_length=max_length)
        corrected = tokenizer.decode(outputs[0], skip_special_tokens=True)
        elapsed_ms = int((time.time() - start) * 1000)

        return {"status": "ok", "corrected": corrected, "elapsed_ms": elapsed_ms}

    except ImportError as e:
        return {"status": "error", "message": f"Missing package: {e}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def cmd_infer_with_cache(request, tokenizer, model):
    """Run inference using pre-loaded model and tokenizer."""
    text = request.get("text", "")
    max_length = request.get("max_length", 256)

    if not text:
        return {"status": "error", "message": "text is required"}

    try:
        start = time.time()
        inputs = tokenizer(text, return_tensors="pt", max_length=512, truncation=True)
        outputs = model.generate(**inputs, max_length=max_length)
        corrected = tokenizer.decode(outputs[0], skip_special_tokens=True)
        elapsed_ms = int((time.time() - start) * 1000)

        return {"status": "ok", "corrected": corrected, "elapsed_ms": elapsed_ms}

    except Exception as e:
        return {"status": "error", "message": str(e)}


def cmd_download(request):
    """Download a model from Hugging Face Hub."""
    repo_id = request.get("repo_id", "")
    dest_path = request.get("dest_path", "")

    if not repo_id or not dest_path:
        return {"status": "error", "message": "repo_id and dest_path are required"}

    try:
        from transformers import AutoTokenizer, AutoModelForSeq2SeqLM

        def progress_callback(msg, pct):
            print(json.dumps({"progress": pct, "message": msg}), file=sys.stderr, flush=True)

        progress_callback("Downloading tokenizer...", 10)
        tokenizer = AutoTokenizer.from_pretrained(repo_id)

        progress_callback("Downloading model...", 30)
        model = AutoModelForSeq2SeqLM.from_pretrained(repo_id)

        progress_callback("Saving tokenizer...", 70)
        os.makedirs(dest_path, exist_ok=True)
        tokenizer.save_pretrained(dest_path)

        progress_callback("Saving model...", 85)
        model.save_pretrained(dest_path)

        progress_callback("Download complete", 100)
        return {"status": "ok", "model_path": dest_path}

    except ImportError as e:
        return {"status": "error", "message": f"Missing package: {e}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def cmd_check_packages(_request):
    """Check which required Python packages are installed."""
    required = ["transformers", "torch"]
    installed = []
    missing = []

    for pkg in required:
        try:
            __import__(pkg)
            installed.append(pkg)
        except ImportError:
            missing.append(pkg)

    return {"status": "ok", "installed": installed, "missing": missing}


def serve():
    """Persistent serve mode -- reads line-delimited JSON requests from stdin."""
    cached_model = None
    cached_tokenizer = None
    cached_model_path = None

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as e:
            print(json.dumps({"status": "error", "message": f"Invalid JSON: {e}"}), flush=True)
            continue

        command = request.get("command", "")

        if command == "infer":
            model_path = request.get("model_path", "")
            if model_path != cached_model_path:
                try:
                    from transformers import AutoTokenizer, AutoModelForSeq2SeqLM
                    cached_tokenizer = AutoTokenizer.from_pretrained(model_path)
                    cached_model = AutoModelForSeq2SeqLM.from_pretrained(model_path)
                    cached_model_path = model_path
                except Exception as e:
                    print(json.dumps({"status": "error", "message": str(e)}), flush=True)
                    continue
            result = cmd_infer_with_cache(request, cached_tokenizer, cached_model)
        elif command == "ping":
            result = {"status": "ok"}
        else:
            handler = {"download": cmd_download, "check_packages": cmd_check_packages}.get(command)
            result = handler(request) if handler else {"status": "error", "message": f"Unknown command: {command}"}

        print(json.dumps(result), flush=True)


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        print(json.dumps({"status": "error", "message": "Empty input"}))
        sys.exit(1)

    try:
        request = json.loads(raw)
    except json.JSONDecodeError as e:
        print(json.dumps({"status": "error", "message": f"Invalid JSON: {e}"}))
        sys.exit(1)

    command = request.get("command", "")

    handlers = {
        "infer": cmd_infer,
        "download": cmd_download,
        "check_packages": cmd_check_packages,
    }

    handler = handlers.get(command)
    if handler is None:
        result = {"status": "error", "message": f"Unknown command: {command}"}
    else:
        result = handler(request)

    print(json.dumps(result))


if __name__ == "__main__":
    if "--serve" in sys.argv:
        serve()
    else:
        main()
