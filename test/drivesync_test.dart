import 'package:drivesync/models/sim_models.dart';
import 'package:drivesync/models/storage_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Jio detection', () {
    test('matches the display names carriers actually report', () {
      for (final name in ['Jio', 'JIO 4G', 'Jio 5G', 'RELIANCE JIO', 'jio']) {
        expect(SimInfo.detectJio(name, ''), isTrue, reason: name);
      }
    });

    test('matches the Reliance Jio MNC block under MCC 405', () {
      expect(SimInfo.detectJio('', '405854'), isTrue);
      expect(SimInfo.detectJio('', '405840'), isTrue);
      expect(SimInfo.detectJio('', '405874'), isTrue);
    });

    test('does not match other Indian carriers', () {
      expect(SimInfo.detectJio('Airtel', '405551'), isFalse);
      expect(SimInfo.detectJio('Vi India', '404011'), isFalse);
      expect(SimInfo.detectJio('', ''), isFalse);
    });

    test('offer message names the slot when a Jio SIM is present', () {
      final offer = CarrierOffer(
        sims: [
          SimInfo.fromMap({
            'carrierName': 'Jio 4G',
            'operatorNumeric': '405854',
            'slotIndex': 1,
          }),
        ],
        checked: true,
      );
      expect(offer.hasJio, isTrue);
      expect(offer.geminiProMessage, contains('slot 2'));
      expect(offer.geminiProMessage, contains('Gemini Pro Pack'));
    });

    test('unchecked is distinct from "no Jio"', () {
      const unchecked = CarrierOffer(sims: [], checked: false);
      expect(unchecked.checked, isFalse);
      expect(unchecked.hasJio, isFalse);
    });
  });

  group('formatBytes', () {
    test('scales to sensible units', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
    });
  });

  group('VolumeInfo', () {
    test('derives used bytes and warning thresholds', () {
      const v = VolumeInfo(
        id: 'C:',
        label: 'C:',
        path: r'C:\',
        totalBytes: 1000,
        freeBytes: 50,
      );
      expect(v.usedBytes, 950);
      expect(v.usedFraction, closeTo(0.95, 0.001));
      expect(v.isCritical, isTrue);
      expect(v.isWarning, isTrue);
    });

    test('treats an unknown capacity as empty rather than full', () {
      const v = VolumeInfo(
        id: 'x',
        label: 'x',
        path: '/',
        totalBytes: 0,
        freeBytes: 0,
      );
      expect(v.usedFraction, 0);
      expect(v.isCritical, isFalse);
    });
  });

  group('ScanResult round trip', () {
    test('survives the offline cache encode/decode', () {
      final original = ScanResult(
        volume: const VolumeInfo(
          id: 'C:',
          label: 'Local Disk (C:)',
          path: r'C:\',
          totalBytes: 500,
          freeBytes: 100,
        ),
        categories: [CategoryUsage(FileCategory.videos, 400, 3)],
        largestFiles: [
          FileEntry(
            path: r'C:\clip.mp4',
            name: 'clip.mp4',
            bytes: 400,
            modified: DateTime(2026, 1, 2, 3, 4),
            category: FileCategory.videos,
          ),
        ],
        scannedFiles: 3,
        scannedBytes: 400,
        duration: const Duration(seconds: 7),
        partial: true,
        skippedPaths: const [r'C:\System Volume Information'],
      );

      final restored = ScanResult.fromJson(original.toJson());
      expect(restored.volume.id, 'C:');
      expect(restored.categories.single.category, FileCategory.videos);
      expect(restored.largestFiles.single.name, 'clip.mp4');
      expect(restored.largestFiles.single.modified, DateTime(2026, 1, 2, 3, 4));
      expect(restored.partial, isTrue);
      expect(restored.skippedPaths, hasLength(1));
      expect(restored.takenAt, original.takenAt);
    });
  });

  group('FileCategory', () {
    test('classifies by extension, case-insensitively', () {
      expect(FileCategory.forExtension('.MP4'), FileCategory.videos);
      expect(FileCategory.forExtension('.jpg'), FileCategory.images);
      expect(FileCategory.forExtension('.7z'), FileCategory.archives);
      expect(FileCategory.forExtension('.qqq'), FileCategory.other);
    });
  });
}
