"""Local LLM Inference Service for Solace Companion Server.

Designed to be modular and model-agnostic: easily swap `model_id` to any
HuggingFace or local causal LM (e.g., Qwen2.5-0.5B, Qwen2.5-1.5B, Llama-3.2-1B, SmolLM2).
Provides synchronous and asynchronous token-by-token streaming via TextIteratorStreamer.
"""

from __future__ import annotations

import asyncio
import logging
import threading
import time
from typing import AsyncGenerator, Iterator, List, Dict, Any, Optional

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, TextIteratorStreamer

logger = logging.getLogger("solace_llm")

DEFAULT_SYSTEM_PROMPT = (
    "You are Solace, an empathetic, warm, and emotionally supportive mental health companion.\n"
    "Your purpose is to offer a calm, grounding, and non-judgmental presence.\n"
    "Guidelines:\n"
    "- Keep responses brief, warm, and conversational (usually 1 to 3 sentences).\n"
    "- Empathize with and validate what the user is experiencing without diagnosing or lecturing.\n"
    "- Offer gentle comfort or ask an open, thoughtful question to help them reflect.\n"
    "- Speak naturally and tenderly like a trusted friend. Do not use bullet points or lists."
)


class LlmService:
    """Manages causal LM tokenizer, model loading, and streaming text generation."""

    def __init__(
        self,
        model_id: str = "Qwen/Qwen2.5-0.5B-Instruct",
        device: Optional[str] = None,
        system_prompt: str = DEFAULT_SYSTEM_PROMPT,
    ) -> None:
        self.model_id = model_id
        self.system_prompt = system_prompt
        self._tokenizer: Optional[AutoTokenizer] = None
        self._model: Optional[AutoModelForCausalLM] = None
        self._is_ready: bool = False
        self._load_lock = threading.Lock()

        # Device selection: prefer CUDA if available, else CPU
        if device:
            self.device = device
        else:
            self.device = "cuda" if torch.cuda.is_available() else "cpu"

    @property
    def is_ready(self) -> bool:
        return self._is_ready

    def initialize(self) -> bool:
        """Load tokenizer and model weights into memory. Thread-safe."""
        with self._load_lock:
            if self._is_ready:
                return True

            logger.info(f"Loading LLM model '{self.model_id}' on device '{self.device}'...")
            t0 = time.time()
            try:
                self._tokenizer = AutoTokenizer.from_pretrained(
                    self.model_id,
                    trust_remote_code=True,
                )

                # Use float32 on CPU for universal compatibility; float16/bfloat16 on CUDA
                torch_dtype = torch.float16 if self.device == "cuda" else torch.float32

                self._model = AutoModelForCausalLM.from_pretrained(
                    self.model_id,
                    dtype=torch_dtype,
                    device_map=self.device,
                    trust_remote_code=True,
                )

                load_sec = time.time() - t0
                self._is_ready = True
                logger.info(
                    f"LLM loaded successfully in {load_sec:.2f}s ({self.model_id} on {self.device})"
                )
                return True
            except Exception as e:
                logger.error(f"Failed to load LLM '{self.model_id}': {e}", exc_info=True)
                self._is_ready = False
                return False

    def build_messages(
        self,
        user_message: str,
        history: Optional[List[Dict[str, str]]] = None,
    ) -> List[Dict[str, str]]:
        """Construct the prompt message list with system prompt and prior conversation turns."""
        messages: List[Dict[str, str]] = [
            {"role": "system", "content": self.system_prompt}
        ]

        if history:
            # Append recent history turns (e.g. up to 10 messages)
            for turn in history[-10:]:
                role = turn.get("role", "user")
                content = turn.get("content", "")
                if role in ("user", "assistant") and content:
                    messages.append({"role": role, "content": content})

        messages.append({"role": "user", "content": user_message})
        return messages

    def generate_stream(
        self,
        messages: List[Dict[str, str]],
        max_new_tokens: int = 128,
        temperature: float = 0.7,
        top_p: float = 0.9,
    ) -> Iterator[str]:
        """Synchronously stream decoded tokens using TextIteratorStreamer."""
        if not self._is_ready or self._model is None or self._tokenizer is None:
            self.initialize()
            if not self._is_ready:
                yield "I am currently preparing my thoughts. Please try again in a moment."
                return

        # Apply chat template
        prompt_text = self._tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
        )

        inputs = self._tokenizer([prompt_text], return_tensors="pt")
        inputs = {k: v.to(self.device) for k, v in inputs.items()}

        streamer = TextIteratorStreamer(
            self._tokenizer,
            skip_prompt=True,
            skip_special_tokens=True,
        )

        generation_kwargs = dict(
            **inputs,
            streamer=streamer,
            max_new_tokens=max_new_tokens,
            temperature=temperature,
            top_p=top_p,
            do_sample=True,
            pad_token_id=self._tokenizer.eos_token_id,
        )

        gen_thread = threading.Thread(
            target=self._model.generate,
            kwargs=generation_kwargs,
            daemon=True,
        )
        gen_thread.start()

        for token in streamer:
            if token:
                yield token

        gen_thread.join(timeout=30.0)

    async def generate_stream_async(
        self,
        messages: List[Dict[str, str]],
        max_new_tokens: int = 128,
        temperature: float = 0.7,
        top_p: float = 0.9,
    ) -> AsyncGenerator[str, None]:
        """Asynchronously stream tokens to integrate smoothly with FastAPI WebSockets."""
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[Optional[str]] = asyncio.Queue()

        def _producer():
            try:
                for token in self.generate_stream(
                    messages,
                    max_new_tokens=max_new_tokens,
                    temperature=temperature,
                    top_p=top_p,
                ):
                    if loop.is_closed():
                        break
                    loop.call_soon_threadsafe(queue.put_nowait, token)
            except Exception as e:
                logger.debug(f"LLM producer terminated: {e}")
            finally:
                if not loop.is_closed():
                    try:
                        loop.call_soon_threadsafe(queue.put_nowait, None)
                    except RuntimeError:
                        pass

        threading.Thread(target=_producer, daemon=True).start()

        while True:
            token = await queue.get()
            if token is None:
                break
            yield token
