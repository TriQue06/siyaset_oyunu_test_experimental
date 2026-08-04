# Siyaset Oyunu - Röle Sunucusu

Bu klasördeki `server.js`, oyuncuların CGNAT/statik IP olmadan, sadece
5 haneli oda koduyla birbirine bağlanabilmesi için gereken küçük bir
WebSocket röle sunucusudur. Oyun mantığını çalıştırmaz, sadece paketleri
doğru oyuncuya yönlendirir.

## Render.com'a ücretsiz deploy (önerilen, kod yazmaya gerek yok)

1. https://render.com adresinde ücretsiz bir hesap aç (GitHub ile giriş yapabilirsin).
2. Bu projeyi (ya da en azından `relay-server/` klasörünü) bir GitHub reposuna push'la.
3. Render panelinde **New +** → **Web Service** → reponu seç.
4. Ayarlar:
   - **Root Directory**: `relay-server`
   - **Runtime**: Node
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
   - **Instance Type**: Free
5. Deploy tamamlanınca Render sana `https://<servis-adin>.onrender.com` gibi bir adres verir.
6. Oyunun içinde `scripts/multiplayer_manager.gd` dosyasındaki `RELAY_URL` sabitini bul ve
   `https://` yerine `wss://` koyarak güncelle:
   ```gdscript
   const RELAY_URL := "wss://<servis-adin>.onrender.com"
   ```

**Not:** Render'ın ücretsiz planı, 15 dakika istek gelmezse sunucuyu uyutur; ilk
bağlantı isteği sunucuyu uyandırırken birkaç saniye sürebilir (oda kurarken
"Oda kuruluyor..." biraz uzun sürebilir, normaldir). Sık oynanacaksa
ücretli bir plana geçmek bunu ortadan kaldırır.

## Yerelde test etmek için

```bash
cd relay-server
npm install
npm start
```

Sunucu `ws://127.0.0.1:8080` adresinde çalışır. Test için `RELAY_URL`'i
geçici olarak bu adrese çevirip iki Godot örneğini (biri host, biri client)
aynı ağda çalıştırabilirsin.
