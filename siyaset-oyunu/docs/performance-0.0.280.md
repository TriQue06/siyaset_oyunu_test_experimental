# 0.0.280 performans doğrulaması

Oyun kuralları, rastgele sayı çağrılarının sırası, animasyon süreleri, çizim sıklığı,
görsel kaynaklar, renderer, MSAA, VSync ve kullanıcının settings.cfg dosyası değiştirilmedi.

## Uygulanan değişiklikler

- Parti plaketleri yalnız görüntülerinin girdileri değiştiğinde yeniden kurulur.
- El kartlarının aynı envanter için tekrar oluşturulması önlenir; etkileşim ve
  hedef iptali güncellemeleri korunur. Dil değişimi önbelleği geçersiz kılar.
- Aynı düğme ve vergi stilleri tekrar üretilmez; metin ölçümleri genişlik/metin
  değiştiğinde yapılır. Fare ve basma animasyonları aynı kod yolunda kalır.
- Harita geometrisi renk değişiminde yeniden yüklenmez. Aynı RGBA8 renk baytları
  güncellenir; farklı yüzey biçimleri eski oluşturma yolunu kullanır.
- Değişmeyen harita, meclis ve vekil dağılımları yeniden kurulmaz.
- İl anketindeki yinelenen ülke hesabı ve kullanılmayan grup hesapları kaldırılır.
- Seçmen tabanı toplu sorgusunda doğrulama bir kez yapılır; bot miting
  değerlendirmesinde aynı ideoloji uyumu iki kez hesaplanmaz.
- Seçim gecesi aynı oy/baraj/yöntem/vekil sayısı için sandalye dağılımı yeniden
  hesaplanmaz. Sayım ve animasyon yine her karede güncellenir.
- Çevrim içi sıradan hamleler yalnız değişen durum alanlarını taşır. Başlangıç,
  seçim, parti değişimleri ve sürüm uyuşmazlıklarında tam durum gönderilir.
  İstemci farkları son alınan otoriter duruma uygular; yerel saatler temel alınmaz.
- Röle istemcisinde FIFO kuyruğu her pakette dizinin başını kaydırmaz; sunucuda
  yönlendirilen çerçeve tek tamponda oluşturulur. Kablo biçimi aynıdır.

## Ölçüm

Godot 4.7.2, aynı 4242 tohumu, aynı sekiz partili durum, headless CPU ölçümü.
Referans: değişikliklerden önceki 0.0.279 kaynakları. Süreler aynı ölçüm
betiğinin ortalamalarıdır; telefon FPS'i veya ağ ping'i değildir.

| İşlem | Önce | Sonra |
|---|---:|---:|
| Parti paneli gerçek yenileme | 8,03 ms | 0,21 ms |
| Ana durum olayı ve bağlı işlemleri | 12,05 ms | 1,45 ms |
| Hükümet sinyalleri ve bağlı işlemleri | 15,19 ms | 2,04 ms |
| Harita renk verisi güncelleme | 2,58 ms | 0,18 ms |
| Toplu seçmen durumu | 2,54 ms | 1,36 ms |
| Ülke projeksiyonu | 14,31 ms | 10,41 ms |

Türkiye haritasında yalnız kasa değişen test durumunun Variant boyutu:
tam durum 97.380 bayt, fark 184 bayt (RPC/taşıma başlıkları hariç).

## Testler

- Rastgele ülke ve Türkiye × D'Hondt, Hare, WTA: altı sabit senaryonun haritası,
  anketi, projeksiyonu, seçmen tabanı, bot kararları, kesin sonuçları ve 12 zaman
  noktasındaki seçim yayını verileri eski kaynaklarla birebir karşılaştırıldı.
- `performance_regression.gd`: durum farkının tam durumu oluşturması ve 4096
  röle paketinde sıra/gönderen/veri bütünlüğü doğrulandı.
- `performance_render_regression.gd`: her iki haritada renk ve köşe baytları
  eski ArrayMesh oluşturma yoluyla hem D3D12/Forward+ hem OpenGL'de eşit.
- `performance_ui_regression.gd`, `--rendering-method gl_compatibility` ile:
  önbellekli arayüz ve zorla yeniden kurulmuş arayüz piksel piksel eşit.
  D3D12 kontrol görüntülerinde, arayüzde hiçbir işlem yapılmadan da az sayıda
  kenar pikselinin değiştiği doğrulandı. Bu nedenle tam ekran piksel testi
  değişken görüntü üreten arka uçta atlanır; kesin karşılaştırma OpenGL'de yapılır.
- İki gerçek ENet süreci: kart çekimi, teşkilat hamlesi, tam seçim sonucu,
  hükümet oylaması, heartbeat ile tam onarım ve ayrılan oyuncunun bot tarafından
  devralınması geçti. Eski ağ testindeki sabit 67 il ve eski ayrılma beklentisi
  güncel oyun davranışına uyarlandı; test saatleri açıkça ilerletiliyor.
- 28 smoke betiğinden 26'sı geçti (uzun hamle sırası testi de tamamlandı).
  İki mevcut hata referans 0.0.279'da da tekrarlandı:
  `smoke_test_party_politics.gd` eski `SPEECH_FUNDS_COST` sabitini kullanıyor;
  `smoke_test_voter_levels.gd` içindeki çoklu miting beklentisi başarısız.
  Bu testler ve oyun dengesi değiştirilmedi.
- `node --test relay-server/server.test.js`: 4096 çerçeve, yayın, tek hedef ve
  hariç tutulan hedef yönlendirmesi geçti.

Test kullanıcı verileri `build/` altında ayrı APPDATA dizinlerinde tutuldu.
APK'nın cihaz üzerindeki FPS'i bu bilgisayar testlerinden çıkarılamaz.
