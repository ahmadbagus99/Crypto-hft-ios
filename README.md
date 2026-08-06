# Seqra Quant iOS

Native SwiftUI client untuk backend `crypto-hft-btcusdt`.

## Fitur

- Market BTCUSDT dengan candlestick multi-interval yang bisa digeser, di-zoom (pinch),
  crosshair tekan-tahan, mode full screen landscape, plus garis entry/TP/SL/trailing stop
  dan liquidation sesuai state engine backend
- Account balance, posisi aktif, TP/SL, dan trailing stop
- AI Decision, Claude validation, serta Claude API usage
- History dengan chart realized PnL dan pagination 10 posisi per halaman
- Konfigurasi paper/live trading, auto trading, position sizing, dan risk limit
- Binance/Anthropic connection test serta Futures kill switch
- REST polling setiap 8 detik tanpa dependency pihak ketiga
- Sinkronisasi trading settings dua arah melalui backend sebagai source of truth
- Dukungan native APNs yang dapat diaktifkan setelah Apple Developer tersedia

## Menjalankan

1. Buka `CryptoHFT.xcodeproj` menggunakan Xcode 16 atau lebih baru.
2. Pilih signing team dan ganti bundle identifier bila diperlukan.
3. Jalankan backend `crypto-hft-btcusdt`.
4. Run aplikasi di iOS 17+.
5. Aplikasi terhubung ke backend production yang ditentukan di `APIClient.swift`.

Endpoint yang dipakai aplikasi berasal dari kontrak REST pada
`CryptoHft.Api/Program.cs` di repository backend.

## Sinkronisasi web dan iOS

Web dan aplikasi iOS membaca serta menulis record settings yang sama melalui `/api/settings/trading`. Aplikasi mengambil perubahan backend setiap 8 detik; dashboard web mengambilnya setiap 5 detik. Jika dua client menyimpan bersamaan, perubahan yang terakhir diterima backend yang berlaku. Editor iOS menampilkan peringatan bila settings berubah dari client lain ketika form sedang diedit.

## Push notification

Selama aplikasi masih memakai Apple Personal Team, notifikasi trading dikirim melalui
Bark dari backend. Native APNs sudah tersedia di source, tetapi hanya diaktifkan pada
build bertanda `PUSH_NOTIFICATIONS` setelah capability Apple tersedia.

## Catatan keamanan

Konfigurasi debug saat ini mengizinkan HTTP agar backend lokal dapat diakses. Sebelum distribusi App Store, gunakan HTTPS dan hapus `NSAllowsArbitraryLoads` dari `Info.plist`. API key exchange tidak disimpan oleh aplikasi ini; credential tetap dikelola backend.
