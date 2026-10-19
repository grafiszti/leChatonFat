from app.config import settings

import re


def _split_sentences(paragraph: str) -> list[str]:
    """Split a paragraph into sentences, keeping delimiters attached."""
    parts = re.split(r"(?<=[.!?])\s+", paragraph.strip())
    return [p for p in parts if p]


def _cap_by_sentence(paragraph: str, target: int, overlap: int) -> list[str]:
    """Hard-cap an oversized paragraph by splitting on sentences.

    Returns one or more chunks for this single paragraph. Each chunk targets
    ~target words (at least one sentence). A ~overlap-word tail is repeated
    into the next chunk to preserve continuity.
    """
    sentences = _split_sentences(paragraph)
    if not sentences:
        return [paragraph] if paragraph.strip() else []

    chunks = []
    window = []
    window_words = 0

    def flush():
        nonlocal window, window_words
        chunk = " ".join(window)
        text = chunk.strip()
        if text:
            chunks.append(text)
        # Keep trailing sentences as overlap for the next window
        overlap_kept = []
        words = 0
        for s in reversed(window):
            w = len(s.split())
            if words + w > overlap:
                break
            overlap_kept.insert(0, s)
            words += w
        window = overlap_kept
        window_words = words

    for sentence in sentences:
        window.append(sentence)
        window_words += len(sentence.split())
        if window_words >= target:
            flush()

    # Flush remainder
    for s in window:
        if s.strip():
            chunks.append(" ".join(window))
            break

    return chunks


def chunk_text(text: str) -> list[str]:
    """Split text into chunks using paragraph-based greedy merge strategy.

    Target ~CHUNK_WORDS words per chunk with ~CHUNK_OVERLAP words overlap.
    Paragraphs larger than the target are hard-capped by splitting sentences.
    """
    target = settings.CHUNK_WORDS
    overlap = settings.CHUNK_OVERLAP

    # Split on paragraph boundaries
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]

    chunks = []
    current = []

    for para in paragraphs:
        # Oversized paragraph: flush current buffer, then cap the paragraph itself
        if len(para.split()) > target * 1.5:
            if current:
                chunks.append("\n\n".join(current))
                current = []
            chunks.extend(_cap_by_sentence(para, target, overlap))
            continue

        current.append(para)
        word_count = sum(len(p.split()) for p in current)

        if word_count >= target:
            chunk = "\n\n".join(current)
            chunks.append(chunk)

            # Keep the last paragraph(s) as overlap
            overlap_words = 0
            overlap_paras = []
            for p in reversed(current):
                pw = len(p.split())
                if overlap_words + pw > overlap:
                    break
                overlap_paras.insert(0, p)
                overlap_words += pw
            current = overlap_paras

    # Flush remaining
    if current:
        chunks.append("\n\n".join(current))

    return chunks if chunks else [text]
