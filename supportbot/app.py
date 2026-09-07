"""SupportBot FastAPI app — the Promptfoo HTTP target.

⚠️ DELIBERATELY VULNERABLE. Local, authorized testing only. Do not deploy.

Run:  uvicorn supportbot.app:app --host 127.0.0.1 --port 8000
Target:  POST /chat  {"session_id": "...", "message": "..."}  ->  {"reply": "<raw markdown>"}
Harness: GET /health, POST /reset (clears sessions + the shared CRM scratchpad)
"""

from __future__ import annotations

import os
import re

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from .agent import AgentError, reset_state, run_agent

load_dotenv()

app = FastAPI(title="SupportBot (intentionally vulnerable)")

# --- Remediation toggle for the fix->rescan->closed demo (design §7.1 beat 6) --------------
# OFF by default so SupportBot stays vulnerable (#9). Set SUPPORTBOT_SANITIZE_OUTPUT=1 to apply
# the output-sanitization mitigation and re-run the SAME saved cases to show the finding clear.
_SANITIZE = os.environ.get("SUPPORTBOT_SANITIZE_OUTPUT", "0") == "1"

# Markdown image ![alt](url) — auto-fetched by renderers => data-exfiltration channel (#9).
# `[^)]*` stops at the first ')', so a URL containing ')' is only partially matched; the
# residual bare URL still trips the eval assertions, which is the honest outcome for a
# regex-based mitigation (see docs/poc-results.md — the fix is illustrative, not complete).
_MD_IMAGE = re.compile(r"!\[[^\]]*\]\([^)]*\)")
# Markdown link [text](url) with an external http(s) target — neutralize to plain text.
_MD_EXT_LINK = re.compile(r"\[([^\]]*)\]\((https?://[^)]*)\)")


def _sanitize_markdown(text: str) -> str:
    """Mitigation for #9: strip auto-fetching markdown images and defang external links so the
    reply can't smuggle data out via markdown-image / link unfurling."""
    text = _MD_IMAGE.sub("[image removed]", text)
    text = _MD_EXT_LINK.sub(r"\1 (link removed)", text)
    return text


class ChatRequest(BaseModel):
    session_id: str
    message: str
    # Optional untrusted third-party document text. When present it is appended to the
    # retrieval results as an extra passage — the request-level `indirectInjectionVar`
    # Promptfoo's `indirect-prompt-injection` plugin needs (redteam/indirect-injection.yaml).
    # Omitting it leaves the default attack surface exactly as before.
    context: str | None = None


class ChatResponse(BaseModel):
    reply: str


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "sanitize_output": "1" if _SANITIZE else "0"}


@app.post("/reset")
def reset() -> dict[str, int]:
    """Clear all conversation state. TEST HARNESS ONLY — not part of the planted surface.

    Call between scan phases so a `pii:*` / `cross-session-leak` finding reflects the
    attack under test rather than PII accumulated by an earlier test in the same run.
    """
    return reset_state()


@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest) -> ChatResponse:
    # Reply is raw markdown, returned unescaped (#9 markdown-image / link exfil surface)
    # unless the remediation toggle is on (fix->rescan->closed demo).
    try:
        reply = run_agent(req.session_id, req.message, req.context)
    except AgentError as exc:
        # 502 (not a friendly string) so promptfoo records an ERROR. A placeholder reply
        # would be graded as a safe refusal and quietly inflate the pass rate.
        raise HTTPException(status_code=502, detail=f"upstream model call failed: {exc}") from exc
    if _SANITIZE:
        reply = _sanitize_markdown(reply)
    return ChatResponse(reply=reply)
