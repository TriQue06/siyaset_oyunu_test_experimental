# Yayın akışı

Kullanıcı, tamamlanan her oyun değişikliğinden sonra sürüm artırılıp APK ve Windows EXE üretilerek mevcut siteye yayınlanmasını istiyor; bu işlemler için tekrar onay istemeyin.

- `siyaset-oyunu/project.godot` config/version, export_presets.cfg Windows file/product_version ve Android version/name/code değerlerini birlikte artırın.
- Godot 4.7.2 aracı `C:\Users\baris\Desktop\Siyaset Oyunu Build\.godot` klasöründedir. Mevcut build.bat Android için export-debug Android, Windows için export-release testoyun kullanır. Android yolları editor_settings.template.tres şablonundan gelir.
- Paketleri `build/release-<version>` içine üretin. Her iki export başarıyla tamamlanmadan yayınlamayın.
- `python website/publish.py --build-dir build/release-<version>` APK ve Windows ZIP dosyalarını builds/ içine, sürüm bilgisini builds/version.json ve website/public/version.json içine yazar.
- İlgili kaynaklar ve paketleri oyun-duzeltmeleri dalına commit/push edin; indirme adresleri bu dalı kullanır. `firebase deploy --only hosting` website/ içinde çalışır; proje proje-siyaset-oyunu.
- Başarısız yayınları açıkça raporlayın; tamamlanmadan yayınlandı demeyin. Eşzamanlı oturumların ilgisiz değişikliklerini commit'e dahil etmeyin.
- Kullanıcının settings.cfg dosyasına dokunmayın. tools/smoke_test_party_politics.gd başka oturumda değiştirilebilir; kullanıcı istemedikçe düzenlemeyin.
