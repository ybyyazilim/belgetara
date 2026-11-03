# Belge Tara

Tekstil sevk belgelerini telefon kamerasıyla okuyup iş emrine çeviren Flutter uygulaması (Android/iOS).

- Metin tanıma cihaz üzerinde yapılır (Google ML Kit); belge internete gönderilmez.
- Belge türünü başlığından tanır: Kumaş Sevk Çeki Listesi, Kumaş Çeki Listesi, Ürün Sevk Fişi, Çıkış Çeki Listesi, Kesim Takip Formu, Kumaş İrsaliyesi.
- Kamera iki saniye sabit tutulunca en net kareyi dondurur ve firma, kumaş/kalite, parti, en, metre, kilo, top adedi, evrak no ve tarih alanlarını okur. Galerideki bir fotoğraftan da okunabilir.
- Okunan değerlerden taslak iş emri oluşur; satırlar düzeltilebilir, süreç aşamaları (kabul, işlemler, sevk) izlenir ve iş emri PDF olarak yazdırılır/paylaşılır.
- Hazır tasarımı olmayan bir belge, dondurulan görüntü üzerinde başlığa ve alanlara dokunularak tanımlanır; sonraki taramalarda tanınır.
- Veriler (firmalar, stoklar, iş emirleri, belge tanımları) yalnızca telefonda tutulur.

## Çalıştırma

```sh
flutter pub get
flutter run
```

Kamera ve metin tanıma gerçek cihaz ister; emülatörde "Fotoğraftan Oku" kullanılabilir.

## Testler

```sh
flutter analyze
flutter test
```

## Test verisi

Gerçek belge fotoğrafları ve onlardan çıkarılan metinler müşteri bilgisi içerdiği için depoda yoktur. Bu verilere bağlı testler, dosyalar yoksa atlanır (skip). Kendi örneklerinizle çalıştırmak için:

1. Belge fotoğraflarını `assets/` altına koyun (`assets/WhatsApp Image*` adları depoya girmez; başka ad kullanacaksanız `.gitignore`'a ekleyin).
2. Her belgenin ML Kit çıktısını `test/fixtures/ocr/<ad>.json` olarak kaydedin. Biçim:
   `{"width": 2160, "height": 3840, "words": [{"t": "Firma", "c": [[x, y], [x, y], [x, y], [x, y]]}]}`
   Beklenen adlar: `ceki_net`, `ceki_bulanik`, `sevk_ceki`, `sevk_fisi`, `cikis_ceki`, `kesim_takip`, `irsaliye`.
3. Beklenen değerleri `test/fixtures/ocr/expected.json` dosyasına yazın:
   `{"sevk_ceki": {"firma": "Demirçelik Tekstil A.Ş.", "parti.0": "P-000000-001", "metre.0": "1.250"}, ...}`
   Belge tanımı testleri için `"custom": {"sevk_fisi": {"picks": {...}, "values": {...}}}` bölümü eklenir.

`test/fixtures/ocr/` klasörü `.gitignore` içindedir; gerçek verili dosyalar commit edilmez.
