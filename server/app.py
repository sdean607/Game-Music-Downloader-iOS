from __future__ import annotations

import asyncio
import hmac
import json
import os
import re
import uuid
import ipaddress
import socket
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote, urljoin, urlsplit

import httpx
import aiohttp
from aiohttp.abc import AbstractResolver
from fastapi import Depends, FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel, Field
from starlette.staticfiles import StaticFiles

ROOT = Path(__file__).resolve().parents[1]
WEB_DIR = ROOT / "web"
DATA_DIR = Path(os.environ.get("GMD_DATA_DIR", str(Path(__file__).resolve().parent / "data"))).resolve()
MUSIC_DIR = DATA_DIR / "music"
LIBRARY_FILE = DATA_DIR / "library.json"
MAX_DOWNLOAD_BYTES = 150 * 1024 * 1024
ARCHIVE_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,200}$")
USERNAME = os.environ.get("GMD_ADMIN_USER", "admin")
PASSWORD = os.environ.get("GMD_ADMIN_PASSWORD", "")

app = FastAPI(title="Game Music Downloader API", version="1.0.0")
security = HTTPBasic(auto_error=False)
library_lock = asyncio.Lock()


def require_auth(credentials: HTTPBasicCredentials | None = Depends(security)) -> str:
    if not PASSWORD:
        raise HTTPException(status_code=503, detail="O servidor ainda não foi protegido. Defina GMD_ADMIN_PASSWORD e reinicie.")
    valid_user = credentials is not None and hmac.compare_digest(credentials.username, USERNAME)
    valid_password = credentials is not None and hmac.compare_digest(credentials.password, PASSWORD)
    if not (valid_user and valid_password):
        raise HTTPException(
            status_code=401,
            detail="Autenticação necessária.",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username


def clean_string(value: Any) -> str | None:
    if isinstance(value, str):
        value = value.strip()
        return value or None
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return ", ".join(str(part) for part in value if part is not None) or None
    return None


def valid_identifier(identifier: str) -> bool:
    return identifier not in {'.', '..'} and bool(ARCHIVE_ID_PATTERN.fullmatch(identifier))


def valid_mp3_filename(filename: str) -> bool:
    return (
        bool(filename)
        and filename not in {".", ".."}
        and "/" not in filename
        and "\\" not in filename
        and Path(filename).name == filename
        and filename.lower().endswith(".mp3")
    )


def license_assessment(search_url: str | None, metadata_url: str | None) -> dict[str, Any]:
    def normalize(raw: str | None) -> tuple[str, str] | None:
        if not raw:
            return None
        from urllib.parse import urlsplit
        try:
            parsed = urlsplit(raw.strip())
            parsed_port = parsed.port
        except ValueError:
            return None
        if parsed.scheme.lower() not in {"http", "https"}:
            return None
        if (parsed.hostname or "").lower() not in {"creativecommons.org", "www.creativecommons.org"}:
            return None
        if parsed.query or parsed.fragment or parsed.username or parsed.password or parsed_port is not None:
            return None
        path = parsed.path.strip("/").lower()
        if not path or path in {".", ".."}:
            return None
        return path, f"https://creativecommons.org/{path}/"

    search = normalize(search_url)
    metadata = normalize(metadata_url)
    blocked = {
        "canOfferDownload": False,
        "name": "Licença não confirmada",
        "message": "A licença não pôde ser confirmada nos dados da pesquisa e dos metadados.",
        "licenseURL": None,
        "attributionRequired": False,
        "shareAlikeRequired": False,
    }
    if not search:
        return {**blocked, "name": "Licença ausente ou inválida", "message": "A pesquisa não apresentou uma licença Creative Commons reconhecida."}
    if not metadata:
        return {**blocked, "licenseURL": search[1]}
    if search[0] != metadata[0]:
        return {**blocked, "name": "Licenças divergentes", "message": "A licença da pesquisa é diferente da licença dos metadados. O download foi bloqueado.", "licenseURL": metadata[1]}

    path, url = metadata
    if path == "publicdomain/zero/1.0":
        return {"canOfferDownload": True, "name": "CC0 1.0", "message": "A declaração indica CC0. Verifique a origem do áudio e a titularidade dos direitos.", "licenseURL": url, "attributionRequired": False, "shareAlikeRequired": False}
    if path == "publicdomain/mark/1.0":
        return {"canOfferDownload": True, "name": "Public Domain Mark 1.0", "message": "O item está marcado como domínio público. Confirme se essa classificação é válida na sua jurisdição.", "licenseURL": url, "attributionRequired": False, "shareAlikeRequired": False}
    parts = path.split("/")
    if len(parts) == 3 and parts[0] == "licenses" and parts[2] in {"1.0", "2.0", "2.5", "3.0", "4.0"}:
        if parts[1] == "by":
            return {"canOfferDownload": True, "name": f"Creative Commons BY {parts[2]}", "message": "Exige atribuição ao autor, indicação da fonte e link para a licença. Confirme também que o uploader tinha autorização para disponibilizar o áudio.", "licenseURL": url, "attributionRequired": True, "shareAlikeRequired": False}
        if parts[1] == "by-sa":
            return {"canOfferDownload": True, "name": f"Creative Commons BY-SA {parts[2]}", "message": "Exige atribuição e atenção às condições ShareAlike em eventual adaptação ou redistribuição. Confirme a autorização do uploader.", "licenseURL": url, "attributionRequired": True, "shareAlikeRequired": True}
    return {**blocked, "name": "Licença não aceita automaticamente", "message": "A licença está fora da lista permitida nesta versão. O download não será oferecido.", "licenseURL": url}


async def archive_json(url: str, params: dict[str, str] | list[tuple[str, str]] | None = None) -> dict[str, Any]:
    try:
        async with httpx.AsyncClient(timeout=45, follow_redirects=True) as client:
            response = await client.get(url, params=params, headers={"User-Agent": "GameMusicDownloader/1.0"})
            response.raise_for_status()
            return response.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise HTTPException(status_code=502, detail=f"Falha ao consultar o Internet Archive: {exc}") from exc


async def load_library() -> list[dict[str, Any]]:
    async with library_lock:
        if not LIBRARY_FILE.exists():
            return []
        try:
            values = json.loads(LIBRARY_FILE.read_text(encoding="utf-8"))
            return values if isinstance(values, list) else []
        except (OSError, json.JSONDecodeError):
            raise HTTPException(status_code=500, detail="Não foi possível ler a biblioteca local.")


async def save_library(values: list[dict[str, Any]]) -> None:
    async with library_lock:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        temporary = LIBRARY_FILE.with_suffix(".tmp")
        temporary.write_text(json.dumps(values, ensure_ascii=False, indent=2), encoding="utf-8")
        temporary.replace(LIBRARY_FILE)


class DownloadRequest(BaseModel):
    identifier: str = Field(min_length=1, max_length=200)
    filename: str = Field(min_length=1, max_length=255)
    search_license_url: str | None = None
    confirmed: bool = False


class OpenverseDownloadRequest(BaseModel):
    identifier: str = Field(min_length=36, max_length=36)
    search_license_url: str = Field(min_length=1, max_length=500)
    confirmed: bool = False


def valid_openverse_id(identifier: str) -> bool:
    try:
        return str(uuid.UUID(identifier)) == identifier.lower()
    except (ValueError, AttributeError):
        return False


async def openverse_json(url: str, params: dict[str, str] | None = None) -> dict[str, Any]:
    try:
        async with httpx.AsyncClient(timeout=35, follow_redirects=False) as client:
            response = await client.get(url, params=params, headers={"User-Agent": "GameMusicDownloader/1.0"})
            response.raise_for_status()
            payload = response.json()
            if not isinstance(payload, dict):
                raise ValueError("Resposta inesperada da API")
            return payload
    except httpx.HTTPStatusError as exc:
        if exc.response.status_code == 429:
            raise HTTPException(status_code=503, detail="O Openverse limitou temporariamente as pesquisas. Tente novamente mais tarde.") from exc
        raise HTTPException(status_code=502, detail="O Openverse não conseguiu responder à consulta.") from exc
    except (httpx.HTTPError, ValueError) as exc:
        raise HTTPException(status_code=502, detail="Falha ao consultar o Openverse.") from exc


def openverse_license_url(item: dict[str, Any]) -> str | None:
    direct = clean_string(item.get("license_url"))
    if direct:
        return direct
    slug = clean_string(item.get("license"))
    version = clean_string(item.get("license_version"))
    if slug == "cc0":
        return "https://creativecommons.org/publicdomain/zero/1.0/"
    if slug == "pdm":
        return "https://creativecommons.org/publicdomain/mark/1.0/"
    if slug in {"by", "by-sa", "by-nc", "by-nc-sa", "by-nd", "by-nc-nd"} and version:
        return f"https://creativecommons.org/licenses/{slug}/{version}/"
    return None


def openverse_mp3(item: dict[str, Any]) -> bool:
    filetype = (clean_string(item.get("filetype")) or "").lower().lstrip(".")
    url = clean_string(item.get("url")) or ""
    return filetype == "mp3" or urlsplit(url).path.lower().endswith(".mp3")


def has_mp3_signature(header: bytes) -> bool:
    """Rejects HTML, images and other payloads masquerading as MP3 files."""
    if header.startswith(b"ID3"):
        return True
    return len(header) >= 2 and header[0] == 0xFF and (header[1] & 0xE0) == 0xE0


class PinnedIPResolver(AbstractResolver):
    """Resolve apenas para o IP público já validado; preserva Host e TLS SNI originais."""

    def __init__(self, hostname: str, address: ipaddress.IPv4Address | ipaddress.IPv6Address):
        self.hostname = hostname.lower()
        self.address = address

    async def resolve(self, host: str, port: int = 0, family: int = socket.AF_INET) -> list[dict[str, Any]]:
        if host.lower() != self.hostname:
            raise OSError("Tentativa de resolver host diferente do validado.")
        return [{
            "hostname": host,
            "host": str(self.address),
            "port": port,
            "family": socket.AF_INET6 if self.address.version == 6 else socket.AF_INET,
            "proto": 0,
            "flags": socket.AI_NUMERICHOST,
        }]

    async def close(self) -> None:
        return None


async def validate_public_media_url(raw_url: str) -> tuple[str, ipaddress.IPv4Address | ipaddress.IPv6Address]:
    try:
        parsed = urlsplit(raw_url)
        if parsed.scheme.lower() != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.port not in (None, 443):
            raise ValueError("URL inválida")
        if parsed.hostname.lower() in {"localhost", "localhost.localdomain"}:
            raise ValueError("host local")
        try:
            literal = ipaddress.ip_address(parsed.hostname)
            candidates = [literal]
        except ValueError:
            records = await asyncio.to_thread(socket.getaddrinfo, parsed.hostname, 443, type=socket.SOCK_STREAM)
            candidates = list(dict.fromkeys(ipaddress.ip_address(entry[4][0]) for entry in records))
        if not candidates or any(not address.is_global for address in candidates):
            raise ValueError("endereço não público")
        return parsed.hostname, candidates[0]
    except (ValueError, OSError, socket.gaierror) as exc:
        raise HTTPException(status_code=400, detail="O endereço do arquivo não é um destino HTTPS público válido.") from exc


async def write_mp3_payload(content: Any, temporary: Path) -> int:
    """Grava o fluxo em disco, validando a assinatura e limpando em qualquer interrupção."""
    received = 0
    prefix = bytearray()
    try:
        with temporary.open("wb") as output:
            async for chunk in content.iter_chunked(64 * 1024):
                if len(prefix) < 3:
                    needed = 3 - len(prefix)
                    prefix.extend(chunk[:needed])
                    chunk = chunk[needed:]
                    if len(prefix) >= 3:
                        if not has_mp3_signature(bytes(prefix)):
                            raise HTTPException(status_code=415, detail="O conteúdo recebido não possui assinatura de áudio MP3.")
                        output.write(prefix)
                        received += len(prefix)
                        prefix.clear()
                if chunk:
                    received += len(chunk)
                    if received > MAX_DOWNLOAD_BYTES:
                        raise HTTPException(status_code=413, detail="O arquivo ultrapassa o limite de 150 MB.")
                    output.write(chunk)
            if prefix:
                if not has_mp3_signature(bytes(prefix)):
                    raise HTTPException(status_code=415, detail="O conteúdo recebido não possui assinatura de áudio MP3.")
                output.write(prefix)
                received += len(prefix)
            if received <= 0:
                raise HTTPException(status_code=422, detail="O arquivo baixado está vazio.")
        return received
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


async def stream_openverse_media(raw_url: str, temporary: Path) -> int:
    current_url = raw_url
    try:
        for _ in range(6):
            hostname, pinned_ip = await validate_public_media_url(current_url)
            resolver = PinnedIPResolver(hostname, pinned_ip)
            connector = aiohttp.TCPConnector(resolver=resolver, use_dns_cache=False, ssl=True)
            timeout = aiohttp.ClientTimeout(total=120, connect=20, sock_read=60)
            async with aiohttp.ClientSession(connector=connector, timeout=timeout, trust_env=False, auto_decompress=False) as client:
                async with client.get(current_url, headers={"User-Agent": "GameMusicDownloader/1.0"}, allow_redirects=False) as response:
                    if response.status in {301, 302, 303, 307, 308}:
                        location = response.headers.get("location")
                        if not location:
                            raise HTTPException(status_code=502, detail="Redirecionamento inválido do provedor de áudio.")
                        current_url = urljoin(current_url, location)
                        continue
                    if response.status >= 400:
                        raise HTTPException(status_code=502, detail="O provedor de áudio recusou o download.")
                    mime = (response.headers.get("content-type") or "").split(";")[0].lower()
                    accepted = {"audio/mpeg", "audio/mp3", "audio/x-mpeg", "audio/x-mp3", "application/octet-stream", "binary/octet-stream"}
                    if mime and mime not in accepted:
                        raise HTTPException(status_code=415, detail="O provedor não entregou um arquivo MP3 reconhecido.")
                    declared_length = response.headers.get("content-length")
                    if declared_length and declared_length.isdigit() and int(declared_length) > MAX_DOWNLOAD_BYTES:
                        raise HTTPException(status_code=413, detail="O arquivo ultrapassa o limite de 150 MB.")
                    return await write_mp3_payload(response.content, temporary)
        raise HTTPException(status_code=502, detail="O provedor excedeu o limite de redirecionamentos.")
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


@app.get("/api/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "app": "Game Music Downloader"}


def build_archive_search_query(term: str) -> str:
    """Prioriza título e assunto para reduzir resultados sem relação com o jogo."""
    fields = ("title", "subject")
    escaped_phrase = term.replace("\\", "\\\\").replace('"', '\\"')
    phrase_clause = " OR ".join(f'{field}:"{escaped_phrase}"' for field in fields)

    # Todos os termos precisam aparecer no título e/ou assunto. Não usamos
    # creator/description/identifier como correspondência ampla, pois isso
    # traz nomes de usuários e descrições sem relação com a trilha.
    tokens = [
        token for token in dict.fromkeys(re.findall(r"[\w]+", term, flags=re.UNICODE))
        if token.upper() not in {"AND", "OR", "NOT"}
    ]
    token_groups = [
        "(" + " OR ".join(f"{field}:{token}" for field in fields) + ")"
        for token in tokens
    ]
    clauses = [phrase_clause]
    if token_groups:
        clauses.append("(" + " AND ".join(token_groups) + ")")
    return f"mediatype:audio AND licenseurl:* AND ({' OR '.join(clauses)})"


def exceeds_download_limit(raw_size: str | None) -> bool:
    """Indica se o tamanho declarado ultrapassa o limite de download."""
    return bool(raw_size and raw_size.isdigit() and int(raw_size) > MAX_DOWNLOAD_BYTES)


@app.get("/api/search")
async def search_archive(q: str, _: str = Depends(require_auth)) -> dict[str, Any]:
    term = q.strip()
    if not term or len(term) > 160:
        raise HTTPException(status_code=400, detail="Digite um termo de pesquisa válido (até 160 caracteres).")
    lucene = build_archive_search_query(term)
    params = [("q", lucene), ("rows", "50"), ("output", "json")]
    params.extend(("fl[]", field) for field in ("identifier", "title", "creator", "licenseurl"))
    payload = await archive_json("https://archive.org/advancedsearch.php", params)
    docs = payload.get("response", {}).get("docs", [])
    results = []
    for item in docs:
        identifier = clean_string(item.get("identifier"))
        if not identifier or not valid_identifier(identifier):
            continue
        results.append({
            "identifier": identifier,
            "title": clean_string(item.get("title")) or identifier,
            "creator": clean_string(item.get("creator")) or "Autor não informado",
            "licenseURL": clean_string(item.get("licenseurl")),
        })
    return {"results": results}


@app.get("/api/items/{identifier}")
async def item_details(identifier: str, search_license_url: str | None = None, _: str = Depends(require_auth)) -> dict[str, Any]:
    if not valid_identifier(identifier):
        raise HTTPException(status_code=400, detail="Identificador do Internet Archive inválido.")
    payload = await archive_json(f"https://archive.org/metadata/{quote(identifier, safe='')}")
    metadata = payload.get("metadata") or {}
    if payload.get("error") or not metadata:
        raise HTTPException(status_code=404, detail="Metadados do item não encontrados.")
    search_license = clean_string(metadata.get("licenseurl"))
    files = []
    for item in payload.get("files") or []:
        filename = clean_string(item.get("name"))
        source = clean_string(item.get("source"))
        private_flag = str(item.get("private", "")).lower()
        if not filename or not valid_mp3_filename(filename) or (source or "").lower() == "metadata" or private_flag in {"true", "1", "yes"}:
            continue
        file_size = clean_string(item.get("size"))
        if exceeds_download_limit(file_size):
            continue
        files.append({
            "filename": filename,
            "size": file_size,
            "format": clean_string(item.get("format")),
            "license": license_assessment(search_license_url, search_license),
        })
    return {
        "identifier": identifier,
        "title": clean_string(metadata.get("title")) or identifier,
        "creator": clean_string(metadata.get("creator")) or "Autor não informado",
        "licenseURL": search_license,
        "itemURL": f"https://archive.org/details/{quote(identifier, safe='')}",
        "files": files,
    }


@app.post("/api/download")
async def download_track(body: DownloadRequest, _: str = Depends(require_auth)) -> dict[str, Any]:
    if not body.confirmed:
        raise HTTPException(status_code=400, detail="É necessária a confirmação dos direitos de uso.")
    if not valid_identifier(body.identifier) or not valid_mp3_filename(body.filename):
        raise HTTPException(status_code=400, detail="Item ou nome de arquivo inválido.")

    payload = await archive_json(f"https://archive.org/metadata/{quote(body.identifier, safe='')}")
    metadata = payload.get("metadata") or {}
    if payload.get("error") or not metadata:
        raise HTTPException(status_code=404, detail="Metadados do item não encontrados.")
    current_license = clean_string(metadata.get("licenseurl"))
    assessment = license_assessment(body.search_license_url, current_license)
    if not assessment["canOfferDownload"]:
        raise HTTPException(status_code=403, detail=assessment["message"])

    selected = None
    for item in payload.get("files") or []:
        if clean_string(item.get("name")) == body.filename:
            selected = item
            break
    if not selected or not valid_mp3_filename(body.filename):
        raise HTTPException(status_code=404, detail="Arquivo MP3 não encontrado nos metadados atuais.")
    if str(selected.get("private", "")).lower() in {"true", "1", "yes"} or clean_string(selected.get("source")) == "metadata":
        raise HTTPException(status_code=403, detail="O arquivo está privado ou não é um arquivo de áudio público.")
    existing_tracks = await load_library()
    if any(item.get("archiveIdentifier") == body.identifier and item.get("filename", "").endswith("_" + body.filename) for item in existing_tracks):
        raise HTTPException(status_code=409, detail="Esta faixa já está na biblioteca.")
    declared_size = clean_string(selected.get("size"))
    if declared_size and declared_size.isdigit() and int(declared_size) > MAX_DOWNLOAD_BYTES:
        raise HTTPException(status_code=413, detail="O arquivo ultrapassa o limite de 150 MB.")

    remote_url = f"https://archive.org/download/{quote(body.identifier, safe='')}/{quote(body.filename, safe='')}"
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    track_id = str(uuid.uuid4())
    stored_name = f"{track_id}_{Path(body.filename).name}"
    destination = MUSIC_DIR / stored_name
    temporary = MUSIC_DIR / f"{stored_name}.part"
    received = 0
    try:
        async with httpx.AsyncClient(timeout=120, follow_redirects=True) as client:
            async with client.stream("GET", remote_url, headers={"User-Agent": "GameMusicDownloader/1.0"}) as response:
                response.raise_for_status()
                mime = (response.headers.get("content-type") or "").split(";")[0].lower()
                accepted_mime = {"audio/mpeg", "audio/mp3", "audio/x-mpeg", "audio/x-mp3", "application/octet-stream", "binary/octet-stream"}
                if mime and mime not in accepted_mime:
                    raise HTTPException(status_code=415, detail=f"Tipo de arquivo inesperado: {mime}")
                with temporary.open("wb") as output:
                    async for chunk in response.aiter_bytes(64 * 1024):
                        received += len(chunk)
                        if received > MAX_DOWNLOAD_BYTES:
                            raise HTTPException(status_code=413, detail="O arquivo ultrapassa o limite de 150 MB.")
                        output.write(chunk)
        if received <= 0:
            raise HTTPException(status_code=422, detail="O arquivo baixado está vazio.")
        temporary.replace(destination)
    except HTTPException:
        temporary.unlink(missing_ok=True)
        raise
    except (httpx.HTTPError, OSError) as exc:
        temporary.unlink(missing_ok=True)
        raise HTTPException(status_code=502, detail=f"Falha no download: {exc}") from exc

    track = {
        "id": track_id,
        "title": Path(body.filename).stem,
        "artist": clean_string(metadata.get("creator")) or "Desconhecido",
        "game": clean_string(metadata.get("title")) or body.identifier,
        "archiveIdentifier": body.identifier,
        "filename": stored_name,
        "license": assessment["licenseURL"],
        "attributionURL": f"https://archive.org/details/{quote(body.identifier, safe='')}",
        "size": received,
        "downloadedAt": datetime.now(timezone.utc).isoformat(),
    }
    tracks = await load_library()
    tracks.insert(0, track)
    await save_library(tracks)
    return {"track": track, "message": "Música salva na biblioteca do servidor."}


@app.get("/api/openverse/search")
async def search_openverse(q: str, _: str = Depends(require_auth)) -> dict[str, Any]:
    term = q.strip()
    if not term or len(term) > 160:
        raise HTTPException(status_code=400, detail="Digite um termo de pesquisa válido (até 160 caracteres).")
    payload = await openverse_json("https://api.openverse.org/v1/audio/", {"q": term, "page_size": "20", "extension": "mp3", "filter_dead": "true", "mature": "false"})
    results = []
    for item in payload.get("results") or []:
        identifier = clean_string(item.get("id"))
        if not identifier or not valid_openverse_id(identifier) or not openverse_mp3(item):
            continue
        license_url = openverse_license_url(item)
        assessment = license_assessment(license_url, license_url)
        size = item.get("filesize")
        if isinstance(size, (int, float)) and size > MAX_DOWNLOAD_BYTES:
            continue
        results.append({"identifier": identifier, "title": clean_string(item.get("title")) or "Áudio sem título", "creator": clean_string(item.get("creator")) or "Autor não informado", "licenseURL": license_url, "license": assessment, "landingURL": clean_string(item.get("foreign_landing_url")), "provider": clean_string(item.get("provider")), "filesize": size})
    return {"results": results}


@app.get("/api/openverse/items/{identifier}")
async def openverse_item_details(identifier: str, search_license_url: str | None = None, _: str = Depends(require_auth)) -> dict[str, Any]:
    if not valid_openverse_id(identifier):
        raise HTTPException(status_code=400, detail="Identificador Openverse inválido.")
    item = await openverse_json(f"https://api.openverse.org/v1/audio/{identifier}/")
    current_license = openverse_license_url(item)
    assessment = license_assessment(search_license_url, current_license)
    size = item.get("filesize")
    oversized = isinstance(size, (int, float)) and size > MAX_DOWNLOAD_BYTES
    eligible = openverse_mp3(item) and not oversized and assessment["canOfferDownload"]
    return {"identifier": identifier, "title": clean_string(item.get("title")) or "Áudio sem título", "creator": clean_string(item.get("creator")) or "Autor não informado", "licenseURL": current_license, "itemURL": clean_string(item.get("foreign_landing_url")), "provider": clean_string(item.get("provider")), "file": {"eligible": eligible, "size": size, "license": assessment, "reason": "Arquivo acima de 150 MB." if oversized else ("Somente arquivos MP3 são aceitos." if not openverse_mp3(item) else None)}}


@app.post("/api/openverse/download")
async def download_openverse_track(body: OpenverseDownloadRequest, _: str = Depends(require_auth)) -> dict[str, Any]:
    if not body.confirmed:
        raise HTTPException(status_code=400, detail="É necessária a confirmação dos direitos de uso.")
    if not valid_openverse_id(body.identifier):
        raise HTTPException(status_code=400, detail="Identificador Openverse inválido.")
    item = await openverse_json(f"https://api.openverse.org/v1/audio/{body.identifier}/")
    current_license = openverse_license_url(item)
    assessment = license_assessment(body.search_license_url, current_license)
    if not assessment["canOfferDownload"]:
        raise HTTPException(status_code=403, detail=assessment["message"])
    if not openverse_mp3(item):
        raise HTTPException(status_code=415, detail="Somente arquivos MP3 são aceitos nesta versão.")
    declared_size = item.get("filesize")
    if isinstance(declared_size, (int, float)) and declared_size > MAX_DOWNLOAD_BYTES:
        raise HTTPException(status_code=413, detail="O arquivo ultrapassa o limite de 150 MB.")
    media_url = clean_string(item.get("url"))
    landing_url = clean_string(item.get("foreign_landing_url"))
    if not media_url or not landing_url:
        raise HTTPException(status_code=422, detail="O Openverse não forneceu o endereço do áudio e sua página de origem.")
    if any(track.get("sourceIdentifier") == body.identifier and track.get("source") == "openverse" for track in await load_library()):
        raise HTTPException(status_code=409, detail="Esta faixa já está na biblioteca.")
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)
    track_id = str(uuid.uuid4())
    safe_title = re.sub(r"[^A-Za-z0-9._-]+", "_", clean_string(item.get("title")) or "openverse-audio").strip("._")[:100] or "openverse-audio"
    stored_name = f"{track_id}_{safe_title}.mp3"
    destination = MUSIC_DIR / stored_name
    temporary = MUSIC_DIR / f"{stored_name}.part"
    try:
        received = await stream_openverse_media(media_url, temporary)
        temporary.replace(destination)
        track = {"id": track_id, "title": clean_string(item.get("title")) or safe_title, "artist": clean_string(item.get("creator")) or "Desconhecido", "game": clean_string(item.get("provider")) or "Openverse", "source": "openverse", "sourceIdentifier": body.identifier, "filename": stored_name, "license": assessment["licenseURL"], "attributionURL": landing_url, "creatorURL": clean_string(item.get("creator_url")), "provider": clean_string(item.get("provider")), "size": received, "downloadedAt": datetime.now(timezone.utc).isoformat()}
        tracks = await load_library()
        tracks.insert(0, track)
        await save_library(tracks)
    except BaseException:
        temporary.unlink(missing_ok=True)
        destination.unlink(missing_ok=True)
        raise
    return {"track": track, "message": "Música do Openverse salva na biblioteca do servidor."}


@app.get("/api/library")
async def get_library(_: str = Depends(require_auth)) -> dict[str, Any]:
    return {"tracks": await load_library()}


@app.get("/api/library/{track_id}/audio")
async def play_track(track_id: str, _: str = Depends(require_auth)) -> FileResponse:
    tracks = await load_library()
    track = next((item for item in tracks if item.get("id") == track_id), None)
    if not track:
        raise HTTPException(status_code=404, detail="Faixa não encontrada.")
    path = MUSIC_DIR / str(track.get("filename", ""))
    if not path.is_file() or path.parent != MUSIC_DIR:
        raise HTTPException(status_code=404, detail="Arquivo de áudio não encontrado.")
    return FileResponse(path, media_type="audio/mpeg", filename=path.name)


@app.delete("/api/library/{track_id}")
async def delete_track(track_id: str, _: str = Depends(require_auth)) -> dict[str, str]:
    tracks = await load_library()
    track = next((item for item in tracks if item.get("id") == track_id), None)
    if not track:
        raise HTTPException(status_code=404, detail="Faixa não encontrada.")
    filename = str(track.get("filename", ""))
    path = MUSIC_DIR / filename
    if path.parent == MUSIC_DIR and path.is_file():
        path.unlink()
    await save_library([item for item in tracks if item.get("id") != track_id])
    return {"status": "deleted"}


if not WEB_DIR.is_dir():
    raise RuntimeError(f"Pasta web não encontrada: {WEB_DIR}")

app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")
