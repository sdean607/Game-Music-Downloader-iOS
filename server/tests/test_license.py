import asyncio
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import app as app_module
from fastapi import HTTPException

from app import PinnedIPResolver, build_archive_search_query, exceeds_download_limit, license_assessment, valid_mp3_filename, valid_identifier, openverse_license_url, openverse_mp3, valid_openverse_id, has_mp3_signature


class ArchiveSearchQueryTests(unittest.TestCase):
    def test_search_prioritizes_title_and_subject(self):
        query = build_archive_search_query("Road Rash Jailbreak")
        self.assertIn('title:"Road Rash Jailbreak"', query)
        self.assertIn('subject:"Road Rash Jailbreak"', query)
        query_lower = query.lower()
        self.assertIn("title:road", query_lower)
        self.assertIn("subject:jailbreak", query_lower)
        self.assertNotIn("creator:", query_lower)
        self.assertNotIn("description:", query_lower)
        self.assertNotIn("identifier:", query_lower)
        self.assertIn("mediatype:audio", query)
        self.assertIn("licenseurl:*", query)

    def test_search_terms_cannot_inject_lucene_operators(self):
        query = build_archive_search_query('Road) OR *:*')
        query_lower = query.lower()
        self.assertNotIn("title:or", query_lower)
        self.assertIn("title:road", query_lower)

    def test_oversized_files_are_excluded(self):
        self.assertTrue(exceeds_download_limit(str(150 * 1024 * 1024 + 1)))
        self.assertFalse(exceeds_download_limit(str(150 * 1024 * 1024)))
        self.assertFalse(exceeds_download_limit("unknown"))


class PinnedResolverTests(unittest.IsolatedAsyncioTestCase):
    async def test_resolver_returns_only_the_validated_ip(self):
        import ipaddress
        resolver = PinnedIPResolver("media.example", ipaddress.ip_address("93.184.216.34"))
        result = await resolver.resolve("media.example", 443)
        self.assertEqual(result[0]["host"], "93.184.216.34")
        self.assertEqual(result[0]["hostname"], "media.example")

    async def test_resolver_rejects_a_different_hostname(self):
        import ipaddress
        resolver = PinnedIPResolver("media.example", ipaddress.ip_address("93.184.216.34"))
        with self.assertRaises(OSError):
            await resolver.resolve("attacker.example", 443)


class OpenverseMetadataTests(unittest.TestCase):
    def test_supported_license_slugs_are_mapped(self):
        self.assertEqual(openverse_license_url({"license": "cc0"}), "https://creativecommons.org/publicdomain/zero/1.0/")
        self.assertEqual(openverse_license_url({"license": "by", "license_version": "4.0"}), "https://creativecommons.org/licenses/by/4.0/")
        self.assertIsNone(openverse_license_url({"license": "unknown"}))

    def test_only_mp3_media_is_eligible(self):
        self.assertTrue(openverse_mp3({"filetype": "mp3"}))
        self.assertTrue(openverse_mp3({"url": "https://media.example/audio.mp3"}))
        self.assertFalse(openverse_mp3({"filetype": "wav", "url": "https://media.example/audio.wav"}))

    def test_openverse_identifier_must_be_uuid(self):
        self.assertTrue(valid_openverse_id("8624ba61-57f1-4f98-8a85-ece206c319cf"))
        self.assertFalse(valid_openverse_id("../private"))

    def test_mp3_payload_signature_is_checked(self):
        self.assertTrue(has_mp3_signature(b"ID3\x04\x00\x00"))
        self.assertTrue(has_mp3_signature(bytes([0xFF, 0xFB, 0x90, 0x64])))
        self.assertFalse(has_mp3_signature(b"<!DOCTYPE html>"))
        self.assertFalse(has_mp3_signature(b""))


class LicenseAssessmentTests(unittest.TestCase):
    def test_cc0_is_allowed(self):
        result = license_assessment(
            "https://creativecommons.org/publicdomain/zero/1.0/",
            "https://creativecommons.org/publicdomain/zero/1.0/",
        )
        self.assertTrue(result["canOfferDownload"])
        self.assertEqual(result["name"], "CC0 1.0")

    def test_by_requires_attribution(self):
        url = "https://creativecommons.org/licenses/by/4.0/"
        result = license_assessment(url, url)
        self.assertTrue(result["canOfferDownload"])
        self.assertTrue(result["attributionRequired"])

    def test_nc_is_blocked(self):
        url = "https://creativecommons.org/licenses/by-nc/4.0/"
        result = license_assessment(url, url)
        self.assertFalse(result["canOfferDownload"])

    def test_mismatch_is_blocked(self):
        result = license_assessment(
            "https://creativecommons.org/licenses/by/4.0/",
            "https://creativecommons.org/licenses/by-sa/4.0/",
        )
        self.assertFalse(result["canOfferDownload"])
        self.assertEqual(result["name"], "Licenças divergentes")

    def test_bad_filename_and_identifier_are_rejected(self):
        self.assertTrue(valid_mp3_filename("track.mp3"))
        self.assertFalse(valid_mp3_filename("../track.mp3"))
        self.assertFalse(valid_mp3_filename("track.wav"))
        self.assertTrue(valid_identifier("archive-item_01"))
        self.assertFalse(valid_identifier("../private"))
        self.assertFalse(valid_identifier(".."))


class ChunkedPayloadTests(unittest.IsolatedAsyncioTestCase):
    class FakeContent:
        def __init__(self, chunks, cancel_after_chunks=False):
            self.chunks = chunks
            self.cancel_after_chunks = cancel_after_chunks

        async def iter_chunked(self, _size):
            for chunk in self.chunks:
                yield chunk
            if self.cancel_after_chunks:
                raise asyncio.CancelledError()

    async def test_mp3_header_split_across_chunks_is_accepted(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "audio.part"
            size = await app_module.write_mp3_payload(
                self.FakeContent([b"I", b"D", b"3", b"\\x04\\x00\\x00audio"]),
                target,
            )
            self.assertEqual(size, 10)
            self.assertEqual(target.read_bytes(), b"ID3\\x04\\x00\\x00audio")

    async def test_html_payload_is_rejected_and_removed(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "audio.part"
            with self.assertRaises(HTTPException) as error:
                await app_module.write_mp3_payload(self.FakeContent([b"<html>not audio"]), target)
            self.assertEqual(error.exception.status_code, 415)
            self.assertFalse(target.exists())

    async def test_empty_payload_is_rejected_and_removed(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "audio.part"
            with self.assertRaises(HTTPException) as error:
                await app_module.write_mp3_payload(self.FakeContent([]), target)
            self.assertEqual(error.exception.status_code, 422)
            self.assertFalse(target.exists())

    async def test_oversized_payload_is_rejected_and_removed(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "audio.part"
            with patch.object(app_module, "MAX_DOWNLOAD_BYTES", 4):
                with self.assertRaises(HTTPException) as error:
                    await app_module.write_mp3_payload(self.FakeContent([b"ID3abc"]), target)
            self.assertEqual(error.exception.status_code, 413)
            self.assertFalse(target.exists())

    async def test_cancelled_stream_removes_partial_file(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "audio.part"
            with self.assertRaises(asyncio.CancelledError):
                await app_module.write_mp3_payload(self.FakeContent([b"ID3partial"], cancel_after_chunks=True), target)
            self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
