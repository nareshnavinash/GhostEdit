#!/usr/bin/env python3
"""
GhostEdit Local Model Inference Script

JSON stdin/stdout protocol for model inference, downloading, and package checking.
Launched as a subprocess by LocalModelRunner.swift.

Commands:
  - infer: Run inference on text using a local model
  - download: Download a model from Hugging Face Hub
  - check_packages: Check which required Python packages are installed
  - check_hf_login: Check HuggingFace login status
  - save_hf_token: Save a HuggingFace token
  - logout_hf: Remove HuggingFace token

Modes:
  - One-shot (default): Reads single JSON from stdin, writes response to stdout.
  - Serve (--serve): Persistent process reading line-delimited JSON from stdin,
    caching model in memory between requests.
"""

import json
import sys
import time
import os


def _get_hf_token():
    """Read the HuggingFace token from env var or token file."""
    token = os.environ.get("HF_TOKEN", "")
    if token:
        return token
    # Check both the standard huggingface-cli location and the legacy path
    for path in ["~/.cache/huggingface/token", "~/.huggingface/token"]:
        expanded = os.path.expanduser(path)
        if os.path.isfile(expanded):
            with open(expanded) as f:
                token = f.read().strip()
            if token:
                return token
    return None


def _detect_model_type(model_path):
    """Read the saved model type marker, defaulting to seq2seq."""
    marker = os.path.join(model_path, "ghostedit_model_type.json")
    if os.path.isfile(marker):
        try:
            with open(marker) as f:
                return json.load(f).get("type", "seq2seq")
        except Exception:
            pass
    return "seq2seq"


def _load_model(model_path):
    """Load the correct model class based on the model type marker."""
    model_type = _detect_model_type(model_path)
    if model_type == "causal":
        from transformers import AutoModelForCausalLM
        return AutoModelForCausalLM.from_pretrained(model_path), model_type
    else:
        from transformers import AutoModelForSeq2SeqLM
        return AutoModelForSeq2SeqLM.from_pretrained(model_path), model_type


def _run_inference(tokenizer, model, model_type, text, max_length):
    """Run inference with the appropriate strategy for the model type."""
    if model_type == "causal":
        # For causal LMs, use chat-style or text-generation approach
        prompt = f"Fix grammatical errors in the following text:\n\n{text}\n\nCorrected text:"
        inputs = tokenizer(prompt, return_tensors="pt", max_length=512, truncation=True)
        input_length = inputs["input_ids"].shape[1]
        outputs = model.generate(
            **inputs,
            max_new_tokens=max_length,
            do_sample=False,
            pad_token_id=tokenizer.eos_token_id,
        )
        # Only decode the newly generated tokens (after the prompt)
        corrected = tokenizer.decode(outputs[0][input_length:], skip_special_tokens=True).strip()
    else:
        # Seq2seq: standard encode-decode
        inputs = tokenizer(text, return_tensors="pt", max_length=512, truncation=True)
        outputs = model.generate(**inputs, max_length=max_length)
        corrected = tokenizer.decode(outputs[0], skip_special_tokens=True)
    return corrected


def cmd_infer(request):
    """Run inference using a local model (auto-detects seq2seq vs causal)."""
    model_path = request.get("model_path", "")
    text = request.get("text", "")
    max_length = request.get("max_length", 256)

    if not model_path or not text:
        return {"status": "error", "message": "model_path and text are required"}

    if not os.path.isdir(model_path):
        return {"status": "error", "message": f"Model directory not found: {model_path}"}

    try:
        from transformers import AutoTokenizer

        start = time.time()
        tokenizer = AutoTokenizer.from_pretrained(model_path)
        model, model_type = _load_model(model_path)
        corrected = _run_inference(tokenizer, model, model_type, text, max_length)
        elapsed_ms = int((time.time() - start) * 1000)

        return {"status": "ok", "corrected": corrected, "elapsed_ms": elapsed_ms}

    except ImportError as e:
        return {"status": "error", "message": f"Missing package: {e}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def cmd_infer_with_cache(request, tokenizer, model, model_type):
    """Run inference using pre-loaded model and tokenizer."""
    text = request.get("text", "")
    max_length = request.get("max_length", 256)

    if not text:
        return {"status": "error", "message": "text is required"}

    try:
        start = time.time()
        corrected = _run_inference(tokenizer, model, model_type, text, max_length)
        elapsed_ms = int((time.time() - start) * 1000)

        return {"status": "ok", "corrected": corrected, "elapsed_ms": elapsed_ms}

    except Exception as e:
        return {"status": "error", "message": str(e)}


def cmd_download(request):
    """Download a model from Hugging Face Hub (auto-detects seq2seq vs causal)."""
    repo_id = request.get("repo_id", "")
    dest_path = request.get("dest_path", "")

    if not repo_id or not dest_path:
        return {"status": "error", "message": "repo_id and dest_path are required"}

    try:
        from transformers import AutoTokenizer

        token = _get_hf_token()

        def progress_callback(msg, pct):
            print(json.dumps({"progress": pct, "message": msg}), file=sys.stderr, flush=True)

        progress_callback("Downloading tokenizer...", 10)
        tokenizer = AutoTokenizer.from_pretrained(repo_id, token=token)

        progress_callback("Downloading model...", 30)
        model_type = "seq2seq"
        try:
            from transformers import AutoModelForSeq2SeqLM
            model = AutoModelForSeq2SeqLM.from_pretrained(repo_id, token=token)
        except (ValueError, OSError):
            from transformers import AutoModelForCausalLM
            model = AutoModelForCausalLM.from_pretrained(repo_id, token=token)
            model_type = "causal"

        progress_callback("Saving tokenizer...", 70)
        os.makedirs(dest_path, exist_ok=True)
        tokenizer.save_pretrained(dest_path)

        progress_callback("Saving model...", 85)
        model.save_pretrained(dest_path)

        # Save model type marker for future inference
        with open(os.path.join(dest_path, "ghostedit_model_type.json"), "w") as f:
            json.dump({"type": model_type}, f)

        progress_callback("Download complete", 100)
        return {"status": "ok", "model_path": dest_path, "model_type": model_type}

    except ImportError as e:
        return {"status": "error", "message": f"Missing package: {e}"}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def cmd_check_packages(_request):
    """Check which required Python packages are installed."""
    required = ["transformers", "torch", "huggingface_hub"]
    installed = []
    missing = []

    for pkg in required:
        try:
            __import__(pkg)
            installed.append(pkg)
        except ImportError:
            missing.append(pkg)

    return {"status": "ok", "installed": installed, "missing": missing}


def cmd_check_hf_login(_request):
    """Check HuggingFace login status."""
    env_token = os.environ.get("HF_TOKEN", "")

    token = None
    source = "none"
    if env_token:
        token = env_token
        source = "env"
    else:
        for path in ["~/.cache/huggingface/token", "~/.huggingface/token"]:
            expanded = os.path.expanduser(path)
            if os.path.isfile(expanded):
                with open(expanded) as f:
                    t = f.read().strip()
                if t:
                    token = t
                    source = "file"
                    break

    if not token:
        return {"status": "ok", "logged_in": False, "username": "", "token_source": "none"}

    try:
        from huggingface_hub import whoami
        info = whoami(token=token)
        return {"status": "ok", "logged_in": True, "username": info.get("name", ""), "token_source": source}
    except Exception:
        return {"status": "ok", "logged_in": False, "username": "", "token_source": source}


def cmd_save_hf_token(request):
    """Save a HuggingFace token after validation.

    Writes to both ~/.cache/huggingface/token (standard transformers/huggingface_hub
    location) and ~/.huggingface/token (legacy) so that from_pretrained() can find it.
    """
    token = request.get("token", "").strip()
    if not token:
        return {"status": "error", "message": "Token is required"}

    try:
        from huggingface_hub import whoami
        info = whoami(token=token)
        username = info.get("name", "")
    except ImportError:
        return {"status": "error", "message": "huggingface_hub package is not installed"}
    except Exception as e:
        return {"status": "error", "message": f"Invalid token: {e}"}

    # Write to both standard and legacy token locations
    for token_dir in ["~/.cache/huggingface", "~/.huggingface"]:
        expanded = os.path.expanduser(token_dir)
        os.makedirs(expanded, exist_ok=True)
        with open(os.path.join(expanded, "token"), "w") as f:
            f.write(token)

    return {"status": "ok", "username": username}


def cmd_logout_hf(_request):
    """Remove HuggingFace token files from both standard and legacy locations."""
    for path in ["~/.cache/huggingface/token", "~/.huggingface/token"]:
        expanded = os.path.expanduser(path)
        if os.path.isfile(expanded):
            os.remove(expanded)
    return {"status": "ok"}


def serve():
    """Persistent serve mode -- reads line-delimited JSON requests from stdin."""
    cached_model = None
    cached_tokenizer = None
    cached_model_path = None
    cached_model_type = None

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
                    from transformers import AutoTokenizer
                    cached_tokenizer = AutoTokenizer.from_pretrained(model_path)
                    cached_model, cached_model_type = _load_model(model_path)
                    cached_model_path = model_path
                except Exception as e:
                    print(json.dumps({"status": "error", "message": str(e)}), flush=True)
                    continue
            result = cmd_infer_with_cache(request, cached_tokenizer, cached_model, cached_model_type)
        elif command == "ping":
            result = {"status": "ok"}
        else:
            handler = {
                "download": cmd_download,
                "check_packages": cmd_check_packages,
                "check_hf_login": cmd_check_hf_login,
                "save_hf_token": cmd_save_hf_token,
                "logout_hf": cmd_logout_hf,
            }.get(command)
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
        "check_hf_login": cmd_check_hf_login,
        "save_hf_token": cmd_save_hf_token,
        "logout_hf": cmd_logout_hf,
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
