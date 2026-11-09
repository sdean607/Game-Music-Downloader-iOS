from __future__ import annotations

import asyncio
import hmac
import json
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote

import httpx
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


@app.get("/api/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "app": "Game Music Downloader"}


def build_archive_search_query(term: str) -> str:
    """Busca a expressão completa e também combina termos em campos descritivos."""
    fields = ("title", "subject", "creator", "description", "identifier")
    escaped_phrase = term.replace("\\", "\\\\").replace('"', '\\"')
    phrase_clause = " OR ".join(f'{field}:"{escaped_phrase}"' for field in fields)

    # Cada palavra pode aparecer em um campo diferente: por exemplo, o jogo
    # no assunto e o nome da trilha no título. Os tokens vêm de regex alfanumérica,
    # portanto não podem introduzir operadores Lucene.
    tokens = list(dict.fromkeys(re.findall(r"[\\w]+", term, flags=re.UNICODE)))
    token_groups = [
        "(" + " OR ".join(f"{field}:{token}" for field in fields) + ")"
        for token in tokens
    ]
    token_clause = " AND ".join(token_groups)
    return f"mediatype:audio AND licenseurl:* AND ({phrase_clause} OR ({token_clause}))"


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
        files.append({
            "filename": filename,
            "size": clean_string(item.get("size")),
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
