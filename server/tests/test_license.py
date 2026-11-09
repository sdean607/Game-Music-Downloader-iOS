import unittest

from app import build_archive_search_query, exceeds_download_limit, license_assessment, valid_mp3_filename, valid_identifier


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


if __name__ == "__main__":
    unittest.main()
