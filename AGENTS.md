# Yayın akışı

Kullanıcı, tamamlanan her oyun değişikliğinden sonra sürüm artırılıp Windows EXE üretilerek mevcut siteye yayınlanmasını istiyor (0.0.319'dan beri yalnız Windows; APK üretilmez, sitede Android düğmesi yok); bu işlemler için tekrar onay istemeyin.

- `siyaset-oyunu/project.godot` config/version, export_presets.cfg Windows file/product_version ve Android version/name/code değerlerini birlikte artırın.
- Godot 4.7.2 aracı `C:\Users\baris\Desktop\Siyaset Oyunu Build\.godot` klasöründedir. Windows için export-release testoyun kullanılır.
- Paketi `build/release-<version>` içine üretin. Export başarıyla tamamlanmadan yayınlamayın.
- `python website/publish.py --build-dir build/release-<version>` Windows ZIP dosyasını builds/ içine, sürüm bilgisini builds/version.json ve website/public/version.json içine yazar.
- İlgili kaynaklar ve paketleri main dalına commit/push edin; indirme adresleri bu dalı kullanır. `firebase deploy --only hosting` website/ içinde çalışır; proje proje-siyaset-oyunu.
- Başarısız yayınları açıkça raporlayın; tamamlanmadan yayınlandı demeyin. Eşzamanlı oturumların ilgisiz değişikliklerini commit'e dahil etmeyin.
- Kullanıcının settings.cfg dosyasına dokunmayın. tools/smoke_test_party_politics.gd başka oturumda değiştirilebilir; kullanıcı istemedikçe düzenlemeyin.
