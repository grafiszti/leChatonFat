import hashlib
from pathlib import Path


def parse_url(html: str, url: str) -> tuple[str, str]:
    """Extract text content from HTML, return (title, text)."""
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html, "lxml")

    # Remove scripts and styles
    for tag in soup(["script", "style", "nav", "header", "footer"]):
        tag.decompose()

    # Prefer <article> or <main>, fall back to full body
    content = soup.find("article") or soup.find("main") or soup.body
    if content is None:
        content = soup

    text = content.get_text(separator="\n", strip=True)

    title = ""
    title_tag = soup.find("title")
    if title_tag:
        title = title_tag.get_text(strip=True)

    return title, text


def extract_links(html: str, base_url: str, max_links: int = 50) -> list[str]:
    """Return absolute same-origin http(s) link URLs found in HTML."""
    from bs4 import BeautifulSoup
    from urllib.parse import urljoin, urlparse

    soup = BeautifulSoup(html, "lxml")
    base_parsed = urlparse(base_url)

    seen = set()
    links = []
    for a in soup.find_all("a", href=True):
        href = a["href"].strip()
        if href.startswith(("#", "mailto:", "tel:", "javascript:")):
            continue
        absolute = urljoin(base_url, href)
        parsed = urlparse(absolute)
        if parsed.scheme not in ("http", "https"):
            continue
        # Same-origin only
        if parsed.netloc != base_parsed.netloc:
            continue
        # Deduplicate by full URL
        if absolute in seen:
            continue
        seen.add(absolute)
        links.append(absolute)
        if len(links) >= max_links:
            break

    return links


def parse_pdf(data: bytes) -> tuple[str, str]:
    """Extract text from PDF bytes, return (filename, text)."""
    from pypdf import PdfReader
    import io

    reader = PdfReader(io.BytesIO(data))
    pages = []
    for page in reader.pages:
        t = page.extract_text()
        if t:
            pages.append(t)
    return "", "\n\n".join(pages)


def parse_docx(data: bytes) -> tuple[str, str]:
    """Extract text from DOCX bytes, return (filename, text)."""
    import mammoth
    import io

    result = mammoth.extract_raw_text(io.BytesIO(data))
    return "", result.value


def parse_text(data: bytes) -> tuple[str, str]:
    """Return raw text with no title."""
    return "", data.decode("utf-8", errors="replace")


def file_ext(filename: str) -> str:
    return Path(filename).suffix.lstrip(".").lower()


def content_hash_url(url: str) -> str:
    return hashlib.sha256(url.encode()).hexdigest()


def content_hash_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def content_hash_text(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()
