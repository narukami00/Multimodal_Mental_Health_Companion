"""Unit test for LlmService streaming generation."""

import asyncio
import time
from llm_service import LlmService


def test_sync_streaming(service: LlmService):
    print("\n--- Testing Sync LLM Streaming ---")
    t0 = time.time()
    ready = service.initialize()
    print(f"Service initialized in {time.time() - t0:.2f}s (ready={ready})")
    assert ready, "Failed to initialize LlmService"

    messages = service.build_messages("Hello Solace, I had a very hectic day at work.")
    chunks = []
    t_gen = time.time()
    for chunk in service.generate_stream(messages, max_new_tokens=40):
        chunks.append(chunk)
        print(chunk, end="", flush=True)

    full_resp = "".join(chunks)
    print(f"\n[Generated {len(chunks)} tokens in {time.time() - t_gen:.2f}s]")
    assert len(full_resp.strip()) > 0, "Generated response is empty"
    print("Sync streaming test PASSED!")


async def test_async_streaming(service: LlmService):
    print("\n--- Testing Async LLM Streaming ---")
    assert service.is_ready, "Service should already be initialized"

    history = [
        {"role": "user", "content": "I am feeling tired."},
        {"role": "assistant", "content": "I hear you. Resting when your body asks for it is so important."}
    ]
    messages = service.build_messages("What should I do to unwind?", history=history)

    chunks = []
    t_gen = time.time()
    async for chunk in service.generate_stream_async(messages, max_new_tokens=40):
        chunks.append(chunk)
        print(chunk, end="", flush=True)

    full_resp = "".join(chunks)
    print(f"\n[Generated {len(chunks)} tokens in {time.time() - t_gen:.2f}s]")
    assert len(full_resp.strip()) > 0, "Async response is empty"
    print("Async streaming test PASSED!")


if __name__ == "__main__":
    service = LlmService()
    test_sync_streaming(service)
    asyncio.run(test_async_streaming(service))
    print("\nALL LLM TESTS PASSED!")
