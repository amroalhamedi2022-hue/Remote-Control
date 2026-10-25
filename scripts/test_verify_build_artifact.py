import struct
import tempfile
import unittest
import zipfile
from pathlib import Path
from verify_build_artifact import verify_android, verify_windows


class ArtifactVerificationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_rejects_renamed_non_apk(self):
        apk = self.root / 'not-an-apk.apk'
        apk.write_bytes(b'Z' * 1_100_000)
        with self.assertRaisesRegex(ValueError, 'Not a valid'):
            verify_android(apk)

    def test_rejects_apk_missing_flutter_engine(self):
        apk = self.root / 'wrong.apk'
        with zipfile.ZipFile(apk, 'w', zipfile.ZIP_STORED) as z:
            z.writestr('AndroidManifest.xml', b'manifest')
            z.writestr('classes.dex', b'dex')
            z.writestr('assets/flutter_assets/a', b'a' * 1_100_000)
        with self.assertRaisesRegex(ValueError, 'structure validation failed'):
            verify_android(apk)

    def test_accepts_structurally_valid_apk(self):
        apk = self.root / 'debug.apk'
        with zipfile.ZipFile(apk, 'w', zipfile.ZIP_STORED) as z:
            z.writestr('AndroidManifest.xml', b'manifest')
            z.writestr('classes.dex', b'dex')
            z.writestr('lib/arm64-v8a/libflutter.so', b'a' * 1_100_000)
            z.writestr('assets/flutter_assets/AssetManifest.bin', b'data')
        result = verify_android(apk)
        self.assertEqual(result['kind'], 'android-debug')
        self.assertEqual(len(result['sha256']), 64)

    def test_rejects_windows_stub_executable(self):
        bundle = self.root / 'Debug'
        (bundle / 'data' / 'flutter_assets').mkdir(parents=True)
        (bundle / 'data' / 'flutter_assets' / 'x').write_bytes(b'asset')
        (bundle / 'flutter_windows.dll').write_bytes(b'A' * 110_000)
        (bundle / 'remote.exe').write_bytes(b'MZ' + b'X' * 20000)
        with self.assertRaisesRegex(ValueError, 'Incomplete Windows'):
            verify_windows(bundle)

    def test_accepts_structurally_valid_windows_bundle(self):
        bundle = self.root / 'Debug'
        (bundle / 'data' / 'flutter_assets').mkdir(parents=True)
        (bundle / 'data' / 'flutter_assets' / 'x').write_bytes(b'asset')
        (bundle / 'flutter_windows.dll').write_bytes(b'A' * 110_000)
        pe = bytearray(20_000)
        pe[:2] = b'MZ'
        struct.pack_into('<I', pe, 60, 128)
        pe[128:132] = b'PE\0\0'
        (bundle / 'remote.exe').write_bytes(pe)
        result = verify_windows(bundle)
        self.assertEqual(result['kind'], 'windows-debug')
        self.assertEqual(result['file_count'], 3)


if __name__ == '__main__':
    unittest.main()
